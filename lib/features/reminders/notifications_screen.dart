import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform/platform_actions.dart';
import '../../routing/app_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/cycle_repository.dart';
import '../../data/services/notification_service.dart';
import '../../core/widgets/inputs.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  ReminderPrefs? _prefs;
  bool _saving = false;
  bool _dirty = false;

  void _update(ReminderPrefs p) => setState(() {
        _prefs = p;
        _dirty = true;
      });

  Future<void> _pickTime() async {
    final p = _prefs!;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: p.dailyHour, minute: p.dailyMinute),
    );
    if (t != null && mounted) {
      _update(p.copyWith(dailyHour: t.hour, dailyMinute: t.minute));
    }
  }

  Future<void> _pickPillTime() async {
    final p = _prefs!;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: p.pillHour, minute: p.pillMinute),
    );
    if (t != null && mounted) {
      _update(p.copyWith(pillHour: t.hour, pillMinute: t.minute));
    }
  }

  Future<void> _save() async {
    final p = _prefs!;
    setState(() => _saving = true);
    try {
      if (p.anyEnabled && NotificationService.supported) {
        final allowed =
            await ref.read(notificationServiceProvider).requestPermission();
        if (!allowed && mounted) {
          showMessage(context,
              'Notifications are blocked. Allow them for CycleSync in your phone settings.');
        }
      }
      await ref.read(repositoryProvider).saveReminders(p);
      ref.invalidate(remindersProvider); // reschedules on Android
      if (mounted) {
        setState(() => _dirty = false);
        showMessage(context, 'Reminder settings saved');
      }
    } on AppException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(remindersProvider);
    final fertileOn =
        ref.watch(profileProvider).value?.showFertileWindow ?? false;
    _prefs ??= async.value;
    final p = _prefs;

    return GradientScaffold(
      title: 'Notifications',
      body: p == null
          ? (async.hasError
              ? ErrorView(onRetry: () => ref.invalidate(remindersProvider))
              : const LoadingView())
          : PageBody(
              children: [
                SoftCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: SwitchListTile(
                    value: p.anyEnabled,
                    onChanged: (on) => _update(on
                        ? p.copyWith(periodReminderEnabled: true)
                        : p.copyWith(
                            periodReminderEnabled: false,
                            fertileReminderEnabled: false,
                            dailyReminderEnabled: false,
                            pillReminderEnabled: false,
                            injectionReminderEnabled: false,
                          )),
                    title: const Text('Enable reminders'),
                  ),
                ),
                if (kIsWeb) ...[
                  const SectionTitle('This device'),
                  const _WebPushCard(),
                ],
                const SectionTitle('Reminders'),
                SoftCard(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: p.periodReminderEnabled,
                        onChanged: (v) =>
                            _update(p.copyWith(periodReminderEnabled: v)),
                        secondary: Icon(Icons.water_drop_outlined,
                            color: context.cycle.period),
                        title: const Text('Next period reminder'),
                        subtitle: Text(
                            '${p.reminderDaysBefore} day${p.reminderDaysBefore == 1 ? '' : 's'} before the estimate'),
                      ),
                      if (p.periodReminderEnabled)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: SegmentedButton<int>(
                            segments: [
                              for (var d = 1; d <= 5; d++)
                                ButtonSegment(value: d, label: Text('$d')),
                            ],
                            selected: {p.reminderDaysBefore},
                            showSelectedIcon: false,
                            onSelectionChanged: (s) => _update(
                                p.copyWith(reminderDaysBefore: s.first)),
                          ),
                        ),
                      const Divider(indent: 16, endIndent: 16),
                      SwitchListTile(
                        value: p.fertileReminderEnabled && fertileOn,
                        onChanged: fertileOn
                            ? (v) =>
                                _update(p.copyWith(fertileReminderEnabled: v))
                            : null,
                        secondary: Icon(Icons.spa_outlined,
                            color: context.cycle.fertile),
                        title: const Text('Fertile window reminder (optional)'),
                        subtitle: Text(fertileOn
                            ? 'On the first estimated day'
                            : 'Turn on the fertile window in Cycle Settings first'),
                      ),
                      const Divider(indent: 16, endIndent: 16),
                      SwitchListTile(
                        value: p.dailyReminderEnabled,
                        onChanged: (v) =>
                            _update(p.copyWith(dailyReminderEnabled: v)),
                        secondary: Icon(Icons.edit_note,
                            color: context.colors.primary),
                        title: const Text('Daily check-in'),
                        subtitle: Text(
                          'At ${TimeOfDay(hour: p.dailyHour, minute: p.dailyMinute).format(context)}',
                        ),
                      ),
                      if (p.dailyReminderEnabled)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: OutlinedButton.icon(
                            onPressed: _pickTime,
                            icon: const Icon(Icons.schedule),
                            label: const Text('Change time'),
                          ),
                        ),
                    ],
                  ),
                ),
                const SectionTitle('Contraception reminders'),
                SoftCard(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: p.pillReminderEnabled,
                        onChanged: (v) =>
                            _update(p.copyWith(pillReminderEnabled: v)),
                        secondary: Icon(Icons.medication_outlined,
                            color: context.colors.secondary),
                        title: const Text('Daily pill reminder'),
                        subtitle: Text(
                          'At ${TimeOfDay(hour: p.pillHour, minute: p.pillMinute).format(context)}',
                        ),
                      ),
                      if (p.pillReminderEnabled)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: OutlinedButton.icon(
                            onPressed: _pickPillTime,
                            icon: const Icon(Icons.schedule),
                            label: const Text('Change time'),
                          ),
                        ),
                      const Divider(indent: 16, endIndent: 16),
                      SwitchListTile(
                        value: p.injectionReminderEnabled,
                        onChanged: (v) =>
                            _update(p.copyWith(injectionReminderEnabled: v)),
                        secondary: Icon(Icons.vaccines_outlined,
                            color: context.colors.secondary),
                        title: const Text('Injection due reminder'),
                        subtitle: Text(p.injectionDue == null
                            ? 'A week before and on the due date'
                            : 'Next due ${MaterialLocalizations.of(context).formatMediumDate(p.injectionDue!)}'),
                      ),
                      if (p.injectionReminderEnabled)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DateField(
                                label: 'Date of your last injection',
                                value: p.injectionLastDate,
                                allowClear: false,
                                firstDate: addDays(
                                    ref.read(todayProvider), -200),
                                lastDate: ref.read(todayProvider),
                                onChanged: (d) => _update(
                                    p.copyWith(injectionLastDate: d)),
                              ),
                              const SizedBox(height: 10),
                              Text('Repeat every',
                                  style: context.text.bodySmall),
                              const SizedBox(height: 6),
                              SegmentedButton<int>(
                                segments: const [
                                  ButtonSegment(
                                      value: 8, label: Text('8 weeks')),
                                  ButtonSegment(
                                      value: 12, label: Text('12 weeks')),
                                  ButtonSegment(
                                      value: 13, label: Text('13 weeks')),
                                ],
                                selected: {p.injectionIntervalWeeks},
                                showSelectedIcon: false,
                                onSelectionChanged: (v) => _update(p
                                    .copyWith(injectionIntervalWeeks: v.first)),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Use the schedule your clinic gave you '
                                '(e.g. Nur-Isterate often 8 weeks, Depo-Provera '
                                'often 12–13 weeks).',
                                style: context.text.bodySmall
                                    ?.copyWith(color: context.cycle.muted),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SectionTitle('Privacy'),
                SoftCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: SwitchListTile(
                    value: p.neutralText,
                    onChanged: (v) => _update(p.copyWith(neutralText: v)),
                    title: const Text('Discreet notification text'),
                    subtitle: Text(p.neutralText
                        ? 'Shows "You have a CycleSync reminder"'
                        : 'Shows details, e.g. "Your period may start in 2 days"'),
                  ),
                ),
                const SizedBox(height: 16),
                NoticeCard(
                  icon: Icons.info_outline,
                  tint: context.cycle.softLavenderCard,
                  text: NotificationService.supported
                      ? 'Reminders arrive as phone notifications. Estimates can change, so reminders update when you log.'
                      : 'Reminders also show on the Home screen when you open CycleSync. Estimates can change, so reminders update when you log.',
                ),
                const SizedBox(height: 12),
                const NoticeCard(
                  icon: Icons.lock_outline,
                  text: 'Only you can see your records. Web reminders store '
                      'only the time on our server, with neutral text.',
                ),
                const SizedBox(height: 20),
                GradientButton(
                  label: _dirty ? 'Save Changes' : 'Saved',
                  loading: _saving,
                  onPressed: _dirty ? _save : null,
                ),
              ],
            ),
    );
  }
}

/// Turns browser notifications (web push) on or off for this device.
class _WebPushCard extends ConsumerStatefulWidget {
  const _WebPushCard();

  @override
  ConsumerState<_WebPushCard> createState() => _WebPushCardState();
}

class _WebPushCardState extends ConsumerState<_WebPushCard> {
  WebPushState? _state;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await webPushState();
    if (mounted) setState(() => _state = s);
  }

  Future<void> _turnOn() async {
    setState(() => _busy = true);
    final repo = ref.read(repositoryProvider);
    try {
      final key = await repo.fetchPushPublicKey();
      final sub = await subscribeWebPush(key);
      if (sub == null) {
        if (mounted) {
          showMessage(context, 'Notifications were not allowed.');
        }
      } else {
        await repo.savePushSubscription(sub);
        ref.invalidate(reminderSyncProvider);
        if (mounted) showMessage(context, 'Notifications are on for this device');
      }
    } on AppException catch (e) {
      if (mounted) showMessage(context, e.message);
    } catch (_) {
      if (mounted) {
        showMessage(context, "Couldn't turn on notifications in this browser.");
      }
    } finally {
      await _refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _turnOff() async {
    setState(() => _busy = true);
    try {
      final endpoint = await currentWebPushEndpoint();
      if (endpoint != null) {
        await ref.read(repositoryProvider).deletePushSubscription(endpoint);
      }
      await unsubscribeWebPush();
    } on AppException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      await _refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    String text;
    Widget? action;
    switch (state) {
      case null:
        text = 'Checking this browser…';
      case WebPushState.enabled:
        text = 'Notifications are on. Reminders arrive even when CycleSync '
            'is closed.';
        action = OutlinedButton(
          onPressed: _busy ? null : _turnOff,
          child: const Text('Turn off on this device'),
        );
      case WebPushState.notAsked:
        text = 'Get reminders as notifications, even when CycleSync is closed.';
        action = GradientButton(
          label: 'Turn on notifications',
          icon: Icons.notifications_active_outlined,
          loading: _busy,
          onPressed: _turnOn,
        );
      case WebPushState.denied:
        text = 'Notifications are blocked for this site. Allow them in your '
            'browser\'s site settings, then come back.';
        action = TextButton(onPressed: _refresh, child: const Text('Check again'));
      case WebPushState.needsInstall:
        text = 'On iPhone, add CycleSync to your Home Screen first, then open '
            'it from there to turn on notifications.';
        action = OutlinedButton(
          onPressed: () => context.push(AppRoutes.install),
          child: const Text('How to add to Home Screen'),
        );
      case WebPushState.unsupported:
        text = "This browser doesn't support notifications. Reminders will "
            'show on the Home screen when you open CycleSync.';
    }
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                state == WebPushState.enabled
                    ? Icons.notifications_active
                    : Icons.notifications_none,
                color: context.colors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: context.text.bodyMedium)),
            ],
          ),
          if (action != null) ...[const SizedBox(height: 14), action],
        ],
      ),
    );
  }
}
