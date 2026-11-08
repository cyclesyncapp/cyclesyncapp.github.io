import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_text.dart';
import '../../core/lock/app_lock.dart';
import '../../core/platform/platform_actions.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/inputs.dart';
import '../../data/repositories/cycle_repository.dart';
import '../../data/services/doctor_report.dart';
import '../../domain/csv_export.dart';
import '../../routing/app_router.dart';

// ------------------------------------------------------------------ More tab

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _share(BuildContext context) async {
    try {
      await SharePlus.instance.share(
        ShareParams(text: AppLinks.shareMessage(), subject: 'CycleSync'),
      );
    } catch (_) {
      if (context.mounted) context.push(AppRoutes.install);
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Log out?',
      message: 'Your data stays saved in your account.',
      confirmLabel: 'Log out',
    );
    if (!ok) return;
    await ref.read(notificationServiceProvider).cancelAll();
    if (kIsWeb) {
      try {
        final endpoint = await currentWebPushEndpoint();
        if (endpoint != null) {
          await ref.read(repositoryProvider).deletePushSubscription(endpoint);
        }
        await unsubscribeWebPush();
      } catch (_) {
        // Signing out still works if this fails.
      }
    }
    await ref.read(repositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final email = ref.watch(authProvider).value?.email;

    Widget tile(IconData icon, String title, VoidCallback onTap,
            {Color? color, String? subtitle}) =>
        ListTile(
          leading: IconBubble(icon: icon, size: 38, color: color),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        );

    return GradientScaffold(
      title: 'Settings',
      automaticallyImplyLeading: false,
      body: PageBody(
        children: [
          SoftCard(
            onTap: () => context.push(AppRoutes.profile),
            child: Row(
              children: [
                InitialsAvatar(name: profile?.displayName, size: 60),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (profile?.displayName?.trim().isNotEmpty ?? false)
                            ? profile!.displayName!
                            : 'Your profile',
                        style: context.text.titleMedium,
                      ),
                      if (email != null)
                        Text(email,
                            style: context.text.bodySmall
                                ?.copyWith(color: context.cycle.muted),
                            overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SoftCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                tile(Icons.person_outline, 'My Profile',
                    () => context.push(AppRoutes.profile)),
                tile(Icons.calendar_month_outlined, 'Cycle Settings',
                    () => context.push(AppRoutes.cycleSettings),
                    color: context.colors.secondary),
                tile(Icons.favorite_outline, 'Health Profile',
                    () => context.push(AppRoutes.healthProfile),
                    subtitle: profile == null
                        ? null
                        : [
                            profile.lifeStage.label,
                            if (profile.contraception != null)
                              profile.contraception!.label,
                          ].join(' · ')),
                tile(Icons.notifications_none, 'Notifications & Reminders',
                    () => context.push(AppRoutes.notifications),
                    color: const Color(0xFFE8833A)),
                tile(Icons.history, 'Period History',
                    () => context.push(AppRoutes.history)),
                tile(Icons.pin_outlined, 'App Lock',
                    () => context.push(AppRoutes.appLock),
                    color: const Color(0xFFD4A017),
                    subtitle: ref.watch(lockProvider).enabled ? 'On' : 'Off'),
                tile(Icons.lock_outline, 'Privacy, Export & Delete',
                    () => context.push(AppRoutes.privacySettings),
                    color: const Color(0xFF2E9E6E),
                    subtitle: 'CSV export, doctor summary, delete account'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SoftCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                if (kIsWeb)
                  tile(Icons.add_to_home_screen, 'Add to Home Screen',
                      () => context.push(AppRoutes.install)),
                tile(Icons.share_outlined, 'Share CycleSync',
                    () => _share(context),
                    subtitle: 'Send the link on WhatsApp or anywhere'),
                tile(Icons.info_outline, 'About & Health Disclaimer',
                    () => context.push(AppRoutes.about),
                    color: const Color(0xFF3B6FD8)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => _signOut(context, ref),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Profile

class ProfileSettingsScreen extends ConsumerStatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  ConsumerState<ProfileSettingsScreen> createState() =>
      _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends ConsumerState<ProfileSettingsScreen> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  bool _loaded = false;
  bool _saving = false;
  bool _savingPassword = false;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    setState(() => _saving = true);
    try {
      final v = _name.text.trim();
      await ref
          .read(repositoryProvider)
          .updateProfile({'display_name': v.isEmpty ? null : v});
      ref.invalidate(profileProvider);
      if (mounted) showMessage(context, 'Profile saved');
    } on AppException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    final p = _password.text;
    if (p.length < 8 ||
        !RegExp(r'[A-Za-z]').hasMatch(p) ||
        !RegExp(r'\d').hasMatch(p)) {
      showMessage(context, 'Use at least 8 characters with letters and numbers.');
      return;
    }
    setState(() => _savingPassword = true);
    try {
      await ref.read(repositoryProvider).updatePassword(p);
      _password.clear();
      if (mounted) showMessage(context, 'Password changed');
    } on AppException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final email = ref.watch(authProvider).value?.email;
    if (!_loaded && profile.hasValue) {
      _name.text = profile.value?.displayName ?? '';
      _loaded = true;
    }
    return GradientScaffold(
      title: 'My Profile',
      body: PageBody(
        children: [
          const SizedBox(height: 8),
          Center(child: InitialsAvatar(name: _name.text, size: 84)),
          const SizedBox(height: 20),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Display name (optional)',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.mail_outline),
            ),
            child: Text(email ?? ''),
          ),
          const SizedBox(height: 16),
          GradientButton(
            label: 'Save Profile',
            loading: _saving,
            onPressed: _saveName,
          ),
          const SectionTitle('Change password'),
          TextField(
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: const InputDecoration(
              labelText: 'New password',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _savingPassword ? null : _changePassword,
            child: Text(_savingPassword ? 'Saving…' : 'Change Password'),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Cycle

class CycleSettingsScreen extends ConsumerStatefulWidget {
  const CycleSettingsScreen({super.key});

  @override
  ConsumerState<CycleSettingsScreen> createState() =>
      _CycleSettingsScreenState();
}

class _CycleSettingsScreenState extends ConsumerState<CycleSettingsScreen> {
  bool _loaded = false;
  bool _saving = false;
  int _cycle = 28;
  bool _cycleUnknown = true;
  int _period = 5;
  bool _periodUnknown = true;
  bool _fertile = false;

  Future<void> _toggleFertile(bool on) async {
    if (on) {
      final ok = await confirmDialog(
        context,
        title: 'Show ovulation & fertile window?',
        message: AppText.fertileWarning,
        confirmLabel: 'I understand',
      );
      if (!ok) return;
    }
    setState(() => _fertile = on);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).updateProfile({
        'average_cycle_length': _cycleUnknown ? null : _cycle,
        'average_period_length': _periodUnknown ? null : _period,
        'show_fertile_window': _fertile,
      });
      if (!_fertile) {
        final prefs = await ref.read(remindersProvider.future);
        if (prefs.fertileReminderEnabled) {
          await ref
              .read(repositoryProvider)
              .saveReminders(prefs.copyWith(fertileReminderEnabled: false));
          ref.invalidate(remindersProvider);
        }
      }
      ref.invalidate(profileProvider);
      if (mounted) {
        showMessage(context, 'Cycle settings saved');
        context.pop();
      }
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
      final p = profile.value;
      _cycleUnknown = p?.typicalCycleLength == null;
      _cycle = p?.typicalCycleLength ?? 28;
      _periodUnknown = p?.typicalPeriodLength == null;
      _period = p?.typicalPeriodLength ?? 5;
      _fertile = p?.showFertileWindow ?? false;
      _loaded = true;
    }
    final fertileAllowed = profile.value?.fertileWindowAllowed ?? true;
    return GradientScaffold(
      title: 'Cycle Settings',
      body: !_loaded
          ? const LoadingView()
          : PageBody(
              children: [
                Text(
                  'These are used for estimates until you have logged 3 cycles. '
                  'After that, your own history is used.',
                  style: context.text.bodyMedium
                      ?.copyWith(color: context.cycle.muted),
                ),
                const SizedBox(height: 16),
                SoftCard(
                  child: Column(
                    children: [
                      NumberStepper(
                        label: 'Typical cycle',
                        unit: 'days',
                        value: _cycle,
                        min: 15,
                        max: 60,
                        enabled: !_cycleUnknown,
                        onChanged: (v) => setState(() => _cycle = v),
                      ),
                      CheckboxListTile(
                        value: _cycleUnknown,
                        onChanged: (v) =>
                            setState(() => _cycleUnknown = v ?? true),
                        title: const Text("I don't know"),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                      const Divider(),
                      const SizedBox(height: 8),
                      NumberStepper(
                        label: 'Typical period',
                        unit: 'days',
                        value: _period,
                        min: 1,
                        max: 15,
                        enabled: !_periodUnknown,
                        onChanged: (v) => setState(() => _period = v),
                      ),
                      CheckboxListTile(
                        value: _periodUnknown,
                        onChanged: (v) =>
                            setState(() => _periodUnknown = v ?? true),
                        title: const Text("I don't know"),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SoftCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: SwitchListTile(
                    value: _fertile && fertileAllowed,
                    onChanged: fertileAllowed ? _toggleFertile : null,
                    secondary: Icon(Icons.spa_outlined,
                        color: context.cycle.fertile),
                    title: const Text('Show estimated ovulation & fertile window'),
                    subtitle: Text(fertileAllowed
                        ? 'Off by default. Needs 3 logged cycles. A rough '
                            'calendar estimate only.'
                        : 'Not shown with hormonal contraception or while '
                            'estimates are paused (see Health Profile).'),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  AppText.fertileWarning,
                  style: context.text.bodySmall
                      ?.copyWith(color: context.cycle.muted),
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

// ------------------------------------------------------------------ Privacy

class PrivacySettingsScreen extends ConsumerStatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  ConsumerState<PrivacySettingsScreen> createState() =>
      _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends ConsumerState<PrivacySettingsScreen> {
  bool _exporting = false;
  bool _reporting = false;
  bool _deleting = false;

  Future<void> _report() async {
    setState(() => _reporting = true);
    try {
      final summary = await ref.read(summaryProvider.future);
      final logs = await ref.read(logsProvider.future);
      final profile = await ref.read(profileProvider.future);
      final today = ref.read(todayProvider);
      final bytes = await buildDoctorReport(
        summary: summary,
        logs: logs,
        today: today,
        profile: profile,
      );
      await saveBytesFile(
        fileName: doctorReportFileName(today),
        bytes: bytes,
        mimeType: 'application/pdf',
      );
    } catch (_) {
      if (mounted) showMessage(context, "Couldn't create the summary.");
    } finally {
      if (mounted) setState(() => _reporting = false);
    }
  }

  Future<void> _export() async {
    final ok = await confirmDialog(
      context,
      title: 'Export your data?',
      message: 'The file includes your period dates, symptoms, moods and '
          'notes. It is not password-protected: anyone who can open your '
          'Downloads or the app you share it to can read it.',
      confirmLabel: 'Export',
    );
    if (!ok || !mounted) return;
    setState(() => _exporting = true);
    final repo = ref.read(repositoryProvider);
    try {
      final periods = await repo.fetchPeriods();
      final logs = await repo.fetchLogs();
      final csv = CsvExport.build(periods: periods, logs: logs);
      await saveTextFile(
        fileName: CsvExport.fileName(ref.read(todayProvider)),
        content: csv,
        mimeType: 'text/csv',
      );
      if (mounted) {
        showMessage(context,
            kIsWeb ? 'Export downloaded' : 'Choose where to save your export');
      }
    } on AppException catch (e) {
      if (mounted) showMessage(context, e.message);
    } catch (_) {
      if (mounted) showMessage(context, "Couldn't create the export file.");
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _DeleteDialog(),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      await ref.read(notificationServiceProvider).cancelAll();
      if (kIsWeb) await unsubscribeWebPush();
      await ref.read(repositoryProvider).deleteAccount();
      // Router sends the user back to Welcome once signed out.
    } on AppException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: 'Privacy & Security',
      body: PageBody(
        children: [
          SoftCard(
            tint: context.cycle.softLavenderCard,
            child: Row(
              children: [
                const IconBubble(icon: Icons.verified_user_outlined),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Only you can see your records. They are stored with our '
                    'provider, Supabase, in Europe, sent only over HTTPS, and '
                    'never sold or shared for advertising.',
                    style: context.text.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SoftCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.policy_outlined),
                  title: const Text('Privacy notice'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoutes.privacy),
                ),
                ListTile(
                  leading: const Icon(Icons.local_hospital_outlined),
                  title: const Text('Doctor-visit summary (PDF)'),
                  subtitle: const Text(
                      'Cycle and period lengths, heavy days, pain, symptoms'),
                  trailing: _reporting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _reporting ? null : _report,
                ),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Export my data (CSV)'),
                  subtitle: const Text('Periods and daily logs'),
                  trailing: _exporting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _exporting ? null : _export,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => context.push(AppRoutes.appLock),
            icon: const Icon(Icons.pin_outlined),
            label: const Text('App lock and sign-out options'),
          ),
          const SectionTitle('Delete account'),
          Text(
            'Permanently deletes your account and every period, log and '
            'setting. This cannot be undone. Consider exporting first.',
            style: context.text.bodyMedium,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: context.colors.error,
              side: BorderSide(color: context.colors.error, width: 1.5),
            ),
            onPressed: _deleting ? null : _delete,
            icon: const Icon(Icons.delete_forever_outlined),
            label: Text(_deleting ? 'Deleting…' : 'Delete my account'),
          ),
        ],
      ),
    );
  }
}

class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog();

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controller.text.trim().toUpperCase() == 'DELETE';
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'All your data will be permanently deleted. Type DELETE to confirm.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'DELETE'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: context.colors.error),
          onPressed: ready ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Delete forever'),
        ),
      ],
    );
  }
}
