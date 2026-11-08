import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/constants/app_text.dart';
import '../../core/lock/app_lock.dart';
import '../../core/platform/platform_actions.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/cycle_visuals.dart';
import '../../data/repositories/cycle_repository.dart';
import '../../domain/cycle_calculator.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';
import '../../domain/reminder_planner.dart';
import '../../routing/app_router.dart';
import '../calendar/day_sheet.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(summaryProvider);
    final profile = ref.watch(profileProvider).value;
    final logs = ref.watch(logsByDateProvider).value ?? const {};

    return GradientScaffold(
      body: SafeArea(
        child: summary.when(
          loading: () => const LoadingView(),
          error: (error, stack) => ErrorView(
            onRetry: () {
              ref.invalidate(profileProvider);
              refreshCycleData(ref);
            },
          ),
          data: (s) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(profileProvider);
              refreshCycleData(ref);
              await ref.read(summaryProvider.future);
            },
            child: PageBody(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _Greeting(
                  name: profile?.displayName,
                  lockEnabled: ref.watch(lockProvider).enabled,
                  onLock: () => ref.read(lockProvider.notifier).lockNow(),
                ),
                const SizedBox(height: 18),
                if (kIsWeb && isInAppBrowser())
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: NoticeCard(
                      icon: Icons.open_in_browser,
                      text: 'You opened CycleSync inside another app. For '
                          'reminders and to stay signed in, open this link in '
                          'Chrome or Safari, then add it to your home screen.',
                    ),
                  ),
                const _InstallTip(),
                if (profile?.hormonalContraception ?? false)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: NoticeCard(
                      icon: Icons.info_outline,
                      tint: context.cycle.softLavenderCard,
                      text: 'You use ${profile!.contraception!.label.toLowerCase()}. '
                          'Bleeding may not follow a natural cycle, so treat '
                          'estimates as a rough guide.',
                      onTap: () => context.push(AppRoutes.healthProfile),
                    ),
                  ),
                _InAppReminders(summary: s, logs: logs),
                _NextPeriodCard(summary: s),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _StatTile(
                        icon: Icons.water_drop,
                        label: 'Period length',
                        value: s.periodLength,
                        source: s.periodSource,
                        tint: context.cycle.softPinkCard,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatTile(
                        icon: Icons.autorenew,
                        label: 'Cycle length',
                        value: s.cycleLength,
                        source: s.cycleSource,
                        tint: context.cycle.softLavenderCard,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Your cycle this week',
                                style: context.text.titleMedium),
                          ),
                          TextButton(
                            onPressed: () => context.go(AppRoutes.calendar),
                            child: const Text('Calendar'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      WeekStrip(
                        summary: s,
                        loggedDays: logs.keys.toSet(),
                        onDayTap: (d) => showDaySheet(context, ref, d),
                      ),
                      const SizedBox(height: 14),
                      CalendarLegend(
                        showFertile: profile?.showFertileWindow ?? false,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                GradientButton(
                  label: "Log Today's Symptoms",
                  icon: Icons.edit_note,
                  onPressed: () => context.push(AppRoutes.logFor(s.today)),
                ),
                const SizedBox(height: 10),
                _PeriodAction(summary: s),
                const SizedBox(height: 18),
                Text(
                  AppText.estimatesShort,
                  textAlign: TextAlign.center,
                  style: context.text.bodySmall
                      ?.copyWith(color: context.cycle.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({this.name, this.lockEnabled = false, this.onLock});
  final String? name;
  final bool lockEnabled;
  final VoidCallback? onLock;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final part = hour < 12
        ? 'Good morning'
        : hour < 18
            ? 'Good afternoon'
            : 'Good evening';
    final first = (name ?? '').trim().split(' ').first;
    return Row(
      children: [
        InitialsAvatar(name: name, size: 48),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            first.isEmpty ? '$part!' : '$part,\n$first!',
            style: context.text.titleLarge?.copyWith(height: 1.2),
          ),
        ),
        if (lockEnabled)
          IconButton(
            tooltip: 'Lock now',
            onPressed: onLock,
            icon: Icon(Icons.lock_outline, color: context.colors.primary),
          ),
        IconButton(
          tooltip: 'Reminders',
          onPressed: () => context.push(AppRoutes.notifications),
          icon: Icon(Icons.notifications_none_rounded,
              color: context.colors.primary, size: 28),
        ),
      ],
    );
  }
}

class _NextPeriodCard extends StatelessWidget {
  const _NextPeriodCard({required this.summary});
  final CycleSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final fmt = DateFormat('EEE, d MMM yyyy');
    String eyebrow;
    String headline;
    String detail;
    String? source;

    final shortFmt = DateFormat('d MMM');
    if (s.ongoingPeriod != null) {
      final day = daysBetween(s.ongoingPeriod!.start, s.today) + 1;
      eyebrow = 'PERIOD IN PROGRESS';
      headline = 'Day $day';
      detail = 'Started ${fmt.format(s.ongoingPeriod!.start)}';
    } else if (s.paused) {
      eyebrow = 'ESTIMATES PAUSED';
      headline = 'Taking a break';
      detail = 'Period estimates are paused for your life stage. You can '
          'still log bleeding, symptoms and mood.';
    } else if (s.staleEstimate) {
      eyebrow = 'NO CURRENT ESTIMATE';
      headline = "It's been a while";
      detail = 'Log your latest period to restart estimates.';
    } else if (s.hasEstimate) {
      final days = s.daysUntilNext!;
      eyebrow = 'YOUR NEXT PERIOD';
      if (days > 1) {
        headline = '$days days';
      } else if (days == 1) {
        headline = 'Tomorrow';
      } else if (days == 0) {
        headline = 'Today';
      } else {
        eyebrow = 'ESTIMATED START HAS PASSED';
        headline = '${-days} day${days == -1 ? '' : 's'} ago';
      }
      final w = s.nextWindow;
      detail = days < 0
          ? 'Estimated ${fmt.format(s.nextPeriodStart!)}. Log your period when it starts.'
          : (w != null && !sameDate(w.earliest, w.latest))
              ? 'Likely ${shortFmt.format(w.earliest)} – ${shortFmt.format(w.latest)}'
              : fmt.format(s.nextPeriodStart!);
      source = s.cycleSource == EstimateSource.history
          ? 'Estimate based on your logged cycles'
          : 'Estimate based on your typical cycle setting';
    } else {
      eyebrow = 'YOUR NEXT PERIOD';
      headline = 'Not enough data yet';
      detail = s.lastPeriod == null
          ? 'Add period dates to start receiving estimates.'
          : 'Log 3 cycles, or set your typical cycle length, to see estimates.';
    }

    return Semantics(
      container: true,
      label: [eyebrow.toLowerCase(), headline, detail].join(', '),
      excludeSemantics: true,
      child: SoftCard(
        gradient: context.cycle.heroGradient,
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.calendar_month_rounded,
                  color: context.colors.primary, size: 34),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow,
                    style: context.text.labelMedium?.copyWith(
                      color: context.colors.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    headline,
                    style: context.text.headlineMedium?.copyWith(
                      color: context.cycle.heading,
                      fontSize: (s.hasEstimate || s.ongoingPeriod != null) &&
                              !s.paused &&
                              !s.staleEstimate
                          ? 34
                          : 22,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(detail, style: context.text.bodyMedium),
                  if (s.cycleDay != null && s.cycleDay! <= 60) ...[
                    const SizedBox(height: 10),
                    Pill('Cycle day ${s.cycleDay}'),
                  ],
                  if (source != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      source,
                      style: context.text.bodySmall
                          ?.copyWith(color: context.cycle.muted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.source,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final int? value;
  final EstimateSource? source;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final sub = value == null
        ? 'Not enough data'
        : source == EstimateSource.history
            ? '(typical)'
            : '(your setting)';
    return SoftCard(
      tint: tint,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      child: Semantics(
        label: value == null ? '$label: not enough data' : '$label: $value days $sub',
        excludeSemantics: true,
        child: Column(
          children: [
            Icon(icon, color: context.colors.primary, size: 28),
            const SizedBox(height: 6),
            Text(label, style: context.text.bodyMedium),
            const SizedBox(height: 2),
            Text(
              value == null ? '—' : '$value days',
              style: context.text.titleLarge,
            ),
            Text(
              sub,
              style:
                  context.text.bodySmall?.copyWith(color: context.cycle.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodAction extends ConsumerWidget {
  const _PeriodAction({required this.summary});
  final CycleSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ongoing = summary.ongoingPeriod;
    if (ongoing != null) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.check_circle_outline),
        label: const Text('My period ended today'),
        onPressed: () async {
          try {
            await ref.read(repositoryProvider).savePeriod(
                  id: ongoing.id,
                  start: ongoing.start,
                  end: summary.today,
                  notes: ongoing.notes,
                );
            refreshCycleData(ref);
            if (context.mounted) showMessage(context, 'Period end saved');
          } on AppException catch (e) {
            if (context.mounted) showMessage(context, e.message);
          } on PeriodOverlapException {
            if (context.mounted) {
              showMessage(context, 'That would overlap another period.');
            }
          }
        },
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.water_drop_outlined),
            label: const Text('Period started today'),
            onPressed: () => _startToday(context, ref),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.outlined(
          tooltip: 'Log a past period',
          onPressed: () => context.push(AppRoutes.newPeriodFrom(summary.today)),
          icon: const Icon(Icons.edit_calendar_outlined),
        ),
      ],
    );
  }

  /// One tap: records a period starting today. Falls back to the editor if
  /// it would overlap another record.
  Future<void> _startToday(BuildContext context, WidgetRef ref) async {
    final overlap = CycleCalculator.findOverlap(
      existing: summary.periods,
      start: summary.today,
      today: summary.today,
    );
    if (overlap != null) {
      context.push(AppRoutes.newPeriodFrom(summary.today));
      return;
    }
    try {
      await ref.read(repositoryProvider).savePeriod(start: summary.today);
      refreshCycleData(ref);
      if (context.mounted) showMessage(context, 'Period start saved for today');
    } on PeriodOverlapException {
      if (context.mounted) context.push(AppRoutes.newPeriodFrom(summary.today));
    } on AppException catch (e) {
      if (context.mounted) showMessage(context, e.message);
    }
  }
}

/// Reminders shown inside the app (the web app can't notify when closed).
class _InAppReminders extends ConsumerWidget {
  const _InAppReminders({required this.summary, required this.logs});
  final CycleSummary summary;
  final Map<DateTime, DailyLog> logs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(remindersProvider).value;
    if (prefs == null) return const SizedBox.shrink();
    final notices = ReminderPlanner.inAppNotices(
      prefs: prefs,
      summary: summary,
      loggedToday: logs.containsKey(summary.today),
      now: DateTime.now(),
    );
    return Column(
      children: [
        for (final n in notices) ...[
          NoticeCard(
            icon: Icons.notifications_active_outlined,
            text: n,
            onTap: n.contains('checked in')
                ? () => context.push(AppRoutes.logFor(summary.today))
                : null,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// Suggests adding the web app to the home screen (web only, dismissible).
class _InstallTip extends ConsumerWidget {
  const _InstallTip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kIsWeb || isInstalledWebApp()) return const SizedBox.shrink();
    final prefs = ref.watch(devicePrefsProvider).value;
    if (prefs == null || (prefs.getBool(installTipDismissedKey) ?? false)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SoftCard(
        tint: context.cycle.softLavenderCard,
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(
          children: [
            const Icon(Icons.add_to_home_screen, color: AppTheme.plum),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () => context.push(AppRoutes.install),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Add CycleSync to your home screen',
                    style: context.text.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              icon: const Icon(Icons.close),
              onPressed: () async {
                await prefs.setBool(installTipDismissedKey, true);
                ref.invalidate(devicePrefsProvider);
              },
            ),
          ],
        ),
      ),
    );
  }
}
