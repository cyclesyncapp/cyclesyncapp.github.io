import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/cycle_visuals.dart';
import '../../domain/cycle_calculator.dart';
import '../../domain/dates.dart';
import '../../routing/app_router.dart';
import 'day_sheet.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _month = firstOfMonth(ref.read(todayProvider));

  void _shift(int months) => setState(
        () => _month = DateTime.utc(_month.year, _month.month + months, 1),
      );

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(summaryProvider);
    final logs = ref.watch(logsByDateProvider).value ?? const {};
    final profile = ref.watch(profileProvider).value;
    final showFertile = (profile?.showFertileWindow ?? false) &&
        (profile?.fertileWindowAllowed ?? true);

    return GradientScaffold(
      title: 'Cycle Calendar',
      automaticallyImplyLeading: false,
      leading: const Icon(Icons.calendar_month_rounded),
      actions: [
        IconButton(
          tooltip: 'Cycle settings',
          onPressed: () => context.push(AppRoutes.cycleSettings),
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
      body: summary.when(
        loading: () => const LoadingView(),
        error: (error, stack) => ErrorView(onRetry: () => refreshCycleData(ref)),
        data: (s) => PageBody(
          children: [
            SoftCard(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous month',
                        onPressed: () => _shift(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            DateFormat('MMMM yyyy').format(_month),
                            textAlign: TextAlign.center,
                            style: context.text.titleLarge,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next month',
                        onPressed: () => _shift(1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  if (!sameDate(_month, firstOfMonth(s.today)))
                    TextButton(
                      onPressed: () =>
                          setState(() => _month = firstOfMonth(s.today)),
                      child: const Text('Back to today'),
                    ),
                  const SizedBox(height: 8),
                  _MonthGrid(
                    month: _month,
                    summary: s,
                    loggedDays: logs.keys.toSet(),
                    onTap: (d) => showDaySheet(context, ref, d),
                  ),
                  const SizedBox(height: 16),
                  CalendarLegend(showFertile: showFertile),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _NextPeriodSummary(summary: s),
            if (showFertile) ...[
              const SizedBox(height: 12),
              _OvulationCard(summary: s),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => context.push(AppRoutes.history),
              icon: const Icon(Icons.history),
              label: const Text('View Cycle History'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.summary,
    required this.loggedDays,
    required this.onTap,
  });

  final DateTime month;
  final CycleSummary summary;
  final Set<DateTime> loggedDays;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final first = startOfWeek(month);
    final dim = daysInMonth(month.year, month.month);
    final lastOfMonth = DateTime.utc(month.year, month.month, dim);
    final weeks = (daysBetween(first, lastOfMonth) ~/ 7) + 1;

    return LayoutBuilder(builder: (context, constraints) {
      final cell = ((constraints.maxWidth / 7) - 10).clamp(28.0, 46.0);
      return Column(
        children: [
          Row(
            children: [
              for (final w in weekdayInitials)
                Expanded(
                  child: ExcludeSemantics(
                    child: Text(
                      w,
                      textAlign: TextAlign.center,
                      style: context.text.bodySmall
                          ?.copyWith(color: context.cycle.muted),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (var w = 0; w < weeks; w++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Builder(builder: (context) {
                        final day = addDays(first, w * 7 + i);
                        return DayCell(
                          day: day,
                          size: cell,
                          mark: markFor(summary, day),
                          isToday: sameDate(day, summary.today),
                          hasLog: loggedDays.contains(day),
                          dimmed: day.month != month.month,
                          onTap: () => onTap(day),
                        );
                      }),
                    ),
                ],
              ),
            ),
        ],
      );
    });
  }
}

class _NextPeriodSummary extends StatelessWidget {
  const _NextPeriodSummary({required this.summary});
  final CycleSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    String title;
    String value;
    String? sub;
    if (s.ongoingPeriod != null) {
      title = 'Period in progress';
      value = 'Day ${daysBetween(s.ongoingPeriod!.start, s.today) + 1}';
    } else if (s.hasEstimate) {
      final d = s.daysUntilNext!;
      title = 'Next period';
      value = d > 1
          ? 'In $d days'
          : d == 1
              ? 'Tomorrow'
              : d == 0
                  ? 'Today'
                  : 'Estimated ${-d} day${d == -1 ? '' : 's'} ago';
      sub = DateFormat('EEE, d MMM yyyy').format(s.nextPeriodStart!);
    } else {
      title = 'Next period';
      value = 'Not enough data yet';
      sub = 'Log your periods to see estimates.';
    }
    return SoftCard(
      child: Row(
        children: [
          const IconBubble(icon: Icons.calendar_month_rounded, size: 56),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleSmall),
                Text(value,
                    style: context.text.headlineSmall
                        ?.copyWith(color: context.colors.secondary)),
                if (sub != null) Text(sub, style: context.text.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Next estimated ovulation day and fertile window (opt-in).
class _OvulationCard extends StatelessWidget {
  const _OvulationCard({required this.summary});
  final CycleSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final window = s.upcomingFertileWindow;
    final upcoming = s.ovulationDays.where((d) => !d.isBefore(s.today)).toList()
      ..sort();
    final ov = upcoming.isEmpty ? null : upcoming.first;

    if (window == null && ov == null) {
      return NoticeCard(
        icon: Icons.star_outline_rounded,
        tint: context.cycle.softLavenderCard,
        text: s.cycleSource == EstimateSource.history
            ? 'No upcoming ovulation estimate right now.'
            : 'Ovulation and fertile-window estimates appear after you have '
                'logged 3 cycles.',
      );
    }

    final day = DateFormat('EEE d MMM');
    final short = DateFormat('d MMM');
    final daysToOv = ov == null ? null : daysBetween(s.today, ov);
    return SoftCard(
      tint: context.cycle.softLavenderCard,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBubble(icon: Icons.star_rounded, color: context.cycle.ovulation),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Estimated ovulation', style: context.text.titleSmall),
                if (ov != null)
                  Text(
                    daysToOv == 0
                        ? 'Around today (${day.format(ov)})'
                        : 'Around ${day.format(ov)} · in $daysToOv day'
                            '${daysToOv == 1 ? '' : 's'}',
                    style: context.text.titleMedium
                        ?.copyWith(color: context.cycle.ovulation),
                  ),
                if (window != null)
                  Text(
                    'Fertile window ${short.format(window.start)} – '
                    '${short.format(window.end)}',
                    style: context.text.bodyMedium,
                  ),
                const SizedBox(height: 6),
                Text(
                  'A calendar estimate: 14 days before your next estimated '
                  'period. It can be several days off and is not reliable as '
                  'contraception.',
                  style: context.text.bodySmall
                      ?.copyWith(color: context.cycle.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
