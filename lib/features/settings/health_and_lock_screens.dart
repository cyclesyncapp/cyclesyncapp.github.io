import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/lock/app_lock.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/cycle_repository.dart';
import '../../domain/models.dart';
import '../../routing/app_router.dart';

// ------------------------------------------------------------ Health profile

/// What the life-stage and contraception choices change, in plain words.
String lifeStageEffect(LifeStage s) => switch (s) {
      LifeStage.cycling => 'Normal estimates and reminders.',
      LifeStage.pregnant ||
      LifeStage.postpartum ||
      LifeStage.breastfeeding =>
        'Period estimates, period reminders and "late" notes are paused. You '
            'can still log bleeding, symptoms and mood.',
      LifeStage.perimenopause =>
        'Adds hot flushes and night sweats to logging. Long or changing '
            'cycles are common; estimates are shown as a range. Any bleeding '
            'after 12 months without a period should be checked by a '
            'healthcare professional.',
    };

String contraceptionEffect(Contraception? c) {
  if (c == null) return 'Not shared. Notes assume no hormonal contraception.';
  if (c == Contraception.copperIud) {
    return 'Copper IUDs don\'t stop natural cycles, so estimates work as usual. '
        'Periods can be heavier.';
  }
  if (c.oftenNoBleeding) {
    return 'Little or no bleeding is common with this method, so "late" and '
        '"no period" notes are switched off and the fertile window is hidden.';
  }
  if (c == Contraception.pill) {
    return 'Bleeds on the pill are withdrawal bleeds, not natural periods. '
        'Estimates are less meaningful and the fertile window is hidden. You '
        'can set a daily pill reminder.';
  }
  return 'Estimates work as usual.';
}

class HealthProfileScreen extends ConsumerStatefulWidget {
  const HealthProfileScreen({super.key});

  @override
  ConsumerState<HealthProfileScreen> createState() =>
      _HealthProfileScreenState();
}

class _HealthProfileScreenState extends ConsumerState<HealthProfileScreen> {
  bool _loaded = false;
  bool _saving = false;
  LifeStage _stage = LifeStage.cycling;
  Contraception? _method;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final hidesFertile =
          (_method?.hormonal ?? false) || _stage.paused;
      await ref.read(repositoryProvider).updateProfile({
        'life_stage': _stage.db,
        'contraception': _method?.db,
        if (hidesFertile) 'show_fertile_window': false,
      });
      if (hidesFertile || _stage.paused) {
        final prefs = await ref.read(remindersProvider.future);
        if (prefs.fertileReminderEnabled ||
            (_stage.paused && prefs.periodReminderEnabled)) {
          await ref.read(repositoryProvider).saveReminders(prefs.copyWith(
                fertileReminderEnabled: false,
                periodReminderEnabled:
                    _stage.paused ? false : prefs.periodReminderEnabled,
              ));
          ref.invalidate(remindersProvider);
        }
      }
      ref.invalidate(profileProvider);
      if (!mounted) return;
      showMessage(context, 'Health profile saved');
      if (_method == Contraception.pill || _method == Contraception.injection) {
        final go = await confirmDialog(
          context,
          title: _method == Contraception.pill
              ? 'Set a pill reminder?'
              : 'Set an injection reminder?',
          message: 'Reminders use neutral text, so nothing private shows on '
              'your lock screen.',
          confirmLabel: 'Set it up',
        );
        if (go && mounted) {
          context.pushReplacement(AppRoutes.notifications);
          return;
        }
      }
      if (mounted) context.pop();
    } on AppException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    if (!_loaded && profile.hasValue) {
      _stage = profile.value?.lifeStage ?? LifeStage.cycling;
      _method = profile.value?.contraception;
      _loaded = true;
    }
    return GradientScaffold(
      title: 'Health Profile',
      body: !_loaded
          ? const LoadingView()
          : PageBody(
              children: [
                Text(
                  'Optional. This helps CycleSync avoid wrong estimates and '
                  'unhelpful notes. It stays private to your account.',
                  style: context.text.bodyMedium
                      ?.copyWith(color: context.cycle.muted),
                ),
                const SectionTitle('Right now I am…'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in LifeStage.values)
                      ChoiceChip(
                        label: Text(s.description),
                        selected: _stage == s,
                        onSelected: (_) => setState(() => _stage = s),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                NoticeCard(
                  icon: Icons.info_outline,
                  tint: context.cycle.softLavenderCard,
                  text: lifeStageEffect(_stage),
                ),
                const SectionTitle('Contraception'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in Contraception.values)
                      ChoiceChip(
                        label: Text(c.label),
                        selected: _method == c,
                        onSelected: (_) => setState(() => _method = c),
                      ),
                    ChoiceChip(
                      label: const Text('Prefer not to say'),
                      selected: _method == null,
                      onSelected: (_) => setState(() => _method = null),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                NoticeCard(
                  icon: Icons.info_outline,
                  tint: context.cycle.softLavenderCard,
                  text: contraceptionEffect(_method),
                ),
                const SizedBox(height: 20),
                GradientButton(
                  label: 'Save',
                  loading: _saving,
                  onPressed: _save,
                ),
              ],
            ),
    );
  }
}

// ------------------------------------------------------------ App lock

class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key});

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _signOutOnClose = false;
  bool _loadedPrefs = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) {
        setState(() {
          _signOutOnClose = p.getBool(signOutOnCloseKey) ?? false;
          _loadedPrefs = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _setPin() async {
    final pin = _pin.text;
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      showMessage(context, 'Use 4 to 6 digits.');
      return;
    }
    if (pin != _confirm.text) {
      showMessage(context, 'The PINs do not match.');
      return;
    }
    await ref.read(lockProvider.notifier).setPin(pin);
    _pin.clear();
    _confirm.clear();
    if (mounted) showMessage(context, 'App lock is on');
  }

  Future<void> _removePin() async {
    final ok = await confirmDialog(
      context,
      title: 'Turn off app lock?',
      message: 'Anyone with this device will be able to open CycleSync.',
      confirmLabel: 'Turn off',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(lockProvider.notifier).removePin();
    if (mounted) showMessage(context, 'App lock is off');
  }

  Future<void> _setSignOutOnClose(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(signOutOnCloseKey, v);
    if (mounted) setState(() => _signOutOnClose = v);
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(lockProvider);
    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.pin_outlined),
          counterText: '',
        );
    return GradientScaffold(
      title: 'App Lock',
      body: PageBody(
        children: [
          SoftCard(
            tint: context.cycle.softLavenderCard,
            child: Row(
              children: [
                Icon(lock.enabled ? Icons.lock : Icons.lock_open,
                    color: context.colors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    lock.enabled
                        ? 'App lock is on. CycleSync asks for your PIN when it '
                            'opens.'
                        : 'Protect CycleSync with a PIN, so others using this '
                            'phone can\'t see your records.',
                    style: context.text.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          SectionTitle(lock.enabled ? 'Change PIN' : 'Set a PIN'),
          TextField(
            controller: _pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: deco('New PIN (4–6 digits)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: deco('Confirm PIN'),
          ),
          const SizedBox(height: 14),
          GradientButton(
            label: lock.enabled ? 'Change PIN' : 'Turn on app lock',
            icon: Icons.lock_outline,
            onPressed: _setPin,
          ),
          if (lock.enabled) ...[
            const SectionTitle('Lock after'),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Immediately')),
                ButtonSegment(value: 60, label: Text('1 min')),
                ButtonSegment(value: 300, label: Text('5 min')),
              ],
              selected: {lock.lockAfterSeconds},
              showSelectedIcon: false,
              onSelectionChanged: (v) =>
                  ref.read(lockProvider.notifier).setLockAfter(v.first),
            ),
            const SizedBox(height: 8),
            Text(
              'How long CycleSync can be in the background before it locks. '
              'Use the lock button on Home to lock it straight away.',
              style:
                  context.text.bodySmall?.copyWith(color: context.cycle.muted),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _removePin,
              child: const Text('Turn off app lock'),
            ),
          ],
          if (kIsWeb && _loadedPrefs) ...[
            const SectionTitle('On a shared computer'),
            SoftCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SwitchListTile(
                value: _signOutOnClose,
                onChanged: _setSignOutOnClose,
                title: const Text('Sign me out when I close the app'),
                subtitle: const Text(
                    'You will need to sign in each time you open CycleSync.'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Your PIN is stored only on this device, never on our servers. If '
            'you forget it, you can sign out and sign in again.',
            style: context.text.bodySmall?.copyWith(color: context.cycle.muted),
          ),
        ],
      ),
    );
  }
}
