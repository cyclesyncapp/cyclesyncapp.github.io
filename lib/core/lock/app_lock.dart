import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/platform_actions.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

const _pinHashKey = 'lock_pin_hash';
const _pinSaltKey = 'lock_pin_salt';
const _lockAfterKey = 'lock_after_seconds';
const _pinLengthKey = 'lock_pin_length';
const signOutOnCloseKey = 'web_sign_out_on_close';

/// Hashes a PIN with a per-device random salt (the PIN never leaves the device).
String hashPin(String pin, String salt) =>
    sha256.convert(utf8.encode('$salt:$pin')).toString();

String newSalt() {
  final r = Random.secure();
  return base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
}

class LockState {
  const LockState({
    this.ready = false,
    this.enabled = false,
    this.locked = false,
    this.lockAfterSeconds = 60,
    this.pinLength = 4,
  });

  final int pinLength;
  final bool ready;
  final bool enabled;
  final bool locked;
  final int lockAfterSeconds;

  LockState copyWith({
    bool? ready,
    bool? enabled,
    bool? locked,
    int? lockAfterSeconds,
    int? pinLength,
  }) =>
      LockState(
        ready: ready ?? this.ready,
        enabled: enabled ?? this.enabled,
        locked: locked ?? this.locked,
        lockAfterSeconds: lockAfterSeconds ?? this.lockAfterSeconds,
        pinLength: pinLength ?? this.pinLength,
      );
}

class LockController extends Notifier<LockState> {
  SharedPreferences? _prefs;
  int _failures = 0;
  DateTime? _blockedUntil;

  @override
  LockState build() {
    Future.microtask(_load);
    return const LockState();
  }

  Future<SharedPreferences> _p() async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<void> _load() async {
    final p = await _p();
    final enabled = p.getString(_pinHashKey) != null;
    state = LockState(
      ready: true,
      enabled: enabled,
      locked: enabled, // locked on every app start when a PIN is set
      lockAfterSeconds: p.getInt(_lockAfterKey) ?? 60,
      pinLength: p.getInt(_pinLengthKey) ?? 4,
    );
  }

  /// Seconds left before another attempt is allowed.
  int get waitSeconds {
    final until = _blockedUntil;
    if (until == null) return 0;
    final left = until.difference(DateTime.now()).inSeconds;
    return left > 0 ? left : 0;
  }

  Future<bool> unlock(String pin) async {
    if (waitSeconds > 0) return false;
    final p = await _p();
    final hash = p.getString(_pinHashKey);
    final salt = p.getString(_pinSaltKey) ?? '';
    if (hash != null && hashPin(pin, salt) == hash) {
      _failures = 0;
      state = state.copyWith(locked: false);
      return true;
    }
    _failures++;
    if (_failures >= 5) {
      _blockedUntil = DateTime.now().add(const Duration(seconds: 30));
      _failures = 0;
    }
    return false;
  }

  void lockNow() {
    if (state.enabled) state = state.copyWith(locked: true);
  }

  Future<void> setPin(String pin) async {
    final p = await _p();
    final salt = newSalt();
    await p.setString(_pinSaltKey, salt);
    await p.setString(_pinHashKey, hashPin(pin, salt));
    await p.setInt(_pinLengthKey, pin.length);
    state = state.copyWith(enabled: true, locked: false, pinLength: pin.length);
  }

  Future<void> removePin() async {
    final p = await _p();
    await p.remove(_pinHashKey);
    await p.remove(_pinSaltKey);
    state = state.copyWith(enabled: false, locked: false);
  }

  Future<void> setLockAfter(int seconds) async {
    final p = await _p();
    await p.setInt(_lockAfterKey, seconds);
    state = state.copyWith(lockAfterSeconds: seconds);
  }
}

final lockProvider =
    NotifierProvider<LockController, LockState>(LockController.new);

/// Covers the app with the PIN screen when locked, and locks it again after
/// it has been in the background for the chosen time.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  DateTime? _hiddenAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.hidden || s == AppLifecycleState.paused) {
      _hiddenAt ??= DateTime.now();
    } else if (s == AppLifecycleState.resumed) {
      final hiddenAt = _hiddenAt;
      _hiddenAt = null;
      final lock = ref.read(lockProvider);
      if (hiddenAt != null &&
          lock.enabled &&
          DateTime.now().difference(hiddenAt).inSeconds >=
              lock.lockAfterSeconds) {
        ref.read(lockProvider.notifier).lockNow();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(lockProvider);
    final signedIn = ref.watch(authProvider).value?.signedIn ?? false;
    if (signedIn) markTabSession();
    final showLock = signedIn && lock.enabled && lock.locked;
    return Stack(
      children: [
        // Hidden from screen readers and taps while locked.
        ExcludeSemantics(
          excluding: showLock,
          child: AbsorbPointer(absorbing: showLock, child: widget.child),
        ),
        if (showLock) const Positioned.fill(child: _PinScreen()),
      ],
    );
  }
}

class _PinScreen extends ConsumerStatefulWidget {
  const _PinScreen();

  @override
  ConsumerState<_PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends ConsumerState<_PinScreen> {
  String _pin = '';
  String? _error;

  Future<void> _press(String digit) async {
    final length = ref.read(lockProvider).pinLength;
    if (_pin.length >= length) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == length) {
      final ok = await ref.read(lockProvider.notifier).unlock(_pin);
      if (!mounted) return;
      if (ok) {
        HapticFeedback.lightImpact();
      } else {
        final wait = ref.read(lockProvider.notifier).waitSeconds;
        setState(() {
          _pin = '';
          _error = wait > 0
              ? 'Too many tries. Wait $wait seconds.'
              : 'That PIN is not right.';
        });
      }
    }
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  bool _confirmForgot = false;

  // The lock sits above the app's navigator, so this asks inline rather
  // than with a dialog.
  Future<void> _forgot() async {
    if (!_confirmForgot) {
      setState(() => _confirmForgot = true);
      return;
    }
    await ref.read(lockProvider.notifier).removePin();
    await ref.read(repositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    Widget key(String label, {VoidCallback? onTap, IconData? icon}) =>
        Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: 72,
            height: 72,
            child: Material(
              color: context.colors.surfaceContainerLowest,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap ?? () => _press(label),
                child: Center(
                  child: icon != null
                      ? Icon(icon, semanticLabel: label)
                      : Text(label, style: context.text.headlineSmall),
                ),
              ),
            ),
          ),
        );

    return Material(
      child: GradientBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogo(size: 72),
                  const SizedBox(height: 16),
                  Text('Enter your PIN', style: context.text.titleLarge),
                  const SizedBox(height: 16),
                  Semantics(
                    label: '${_pin.length} digits entered',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0;
                            i < ref.watch(lockProvider).pinLength;
                            i++)
                          Container(
                            margin: const EdgeInsets.all(6),
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < _pin.length
                                  ? context.colors.primary
                                  : context.cycle.cardBorder,
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 28,
                    child: _error == null
                        ? null
                        : Semantics(
                            liveRegion: true,
                            child: Text(_error!,
                                style: TextStyle(color: context.colors.error)),
                          ),
                  ),
                  for (final row in const [
                    ['1', '2', '3'],
                    ['4', '5', '6'],
                    ['7', '8', '9'],
                  ])
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [for (final d in row) key(d)],
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 88),
                      key('0'),
                      key('Delete', onTap: _back, icon: Icons.backspace_outlined),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_confirmForgot) ...[
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Text(
                        'You will be signed out and the PIN removed from this '
                        'device. Your data stays safe in your account.',
                        textAlign: TextAlign.center,
                        style: context.text.bodyMedium,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () =>
                              setState(() => _confirmForgot = false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: _forgot,
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                  ] else
                    TextButton(
                      onPressed: _forgot,
                      child: const Text('Forgot PIN?'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
