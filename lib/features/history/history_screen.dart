import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/cycle_repository.dart';
import '../../domain/cycle_calculator.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';
import '../../routing/app_router.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(summaryProvider);
    return GradientScaffold(
      title: 'Period History',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            context.push(AppRoutes.newPeriodFrom(ref.read(todayProvider))),
        icon: const Icon(Icons.add),
        label: const Text('Add period'),
      ),
      body: summary.when(
        loading: () => const LoadingView(),
        error: (error, stack) => ErrorView(onRetry: () => refreshCycleData(ref)),
        data: (s) {
          if (s.periods.isEmpty) {
            return PageBody(children: [
              EmptyState(
                icon: Icons.water_drop_outlined,
                title: 'No periods yet',
                message: 'Add your past periods to see your history and '
                    'get estimates.',
                actionLabel: 'Add a period',
                onAction: () =>
                    context.push(AppRoutes.newPeriodFrom(s.today)),
              ),
            ]);
          }
          final fmtShort = DateFormat('d MMM');
          final fmtLong = DateFormat('d MMM yyyy');
          // newest first; cycle length = days to the following (newer) start.
          final ps = s.periods;
          return PageBody(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            children: [
              SoftCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (var i = 0; i < ps.length; i++) ...[
                      if (i > 0) const Divider(indent: 16, endIndent: 16),
                      _PeriodRow(
                        period: ps[i],
                        today: s.today,
                        gapBefore: i + 1 < ps.length
                            ? daysBetween(ps[i + 1].start, ps[i].start)
                            : null,
                        cycleLength: i == 0
                            ? null
                            : daysBetween(ps[i].start, ps[i - 1].start),
                        label: ps[i].end == null
                            ? 'From ${fmtLong.format(ps[i].start)}'
                            : ps[i].start.year == ps[i].end!.year
                                ? '${fmtShort.format(ps[i].start)} – ${fmtLong.format(ps[i].end!)}'
                                : '${fmtLong.format(ps[i].start)} – ${fmtLong.format(ps[i].end!)}',
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SoftCard(
                tint: context.cycle.softLavenderCard,
                child: Row(
                  children: [
                    const IconBubble(icon: Icons.bar_chart_rounded, size: 52),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Usual cycle length',
                              style: context.text.bodyMedium),
                          Text(
                            s.stats.averageCycle == null
                                ? 'Not enough data yet'
                                : '${s.stats.averageCycle!.round()} days',
                            style: context.text.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text('Usual period length',
                              style: context.text.bodyMedium),
                          Text(
                            s.stats.averagePeriod == null
                                ? 'Not enough data yet'
                                : '${s.stats.averagePeriod!.round()} days',
                            style: context.text.titleLarge,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Averages (the usual value) appear after 3 cycles, or 3 periods '
                'with an end date. Cycle length runs from one period start to '
                'the next.',
                style: context.text.bodySmall
                    ?.copyWith(color: context.cycle.muted),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PeriodRow extends ConsumerWidget {
  const _PeriodRow({
    required this.period,
    required this.today,
    required this.cycleLength,
    required this.label,
    this.gapBefore,
  });

  final Period period;
  final DateTime today;
  final int? cycleLength;
  final String label;
  final int? gapBefore;

  Future<void> _answer(WidgetRef ref, BuildContext context, bool? v) async {
    try {
      await ref.read(repositoryProvider).setGapIsCycle(period.id, v);
      ref.invalidate(periodsProvider);
    } on AppException catch (e) {
      if (context.mounted) showMessage(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gap = gapBefore;
    final row = _tile(context);
    if (gap == null || gap <= CycleCalculator.maxValidCycle) return row;
    final answer = period.gapIsCycle;
    return Column(
      children: [
        row,
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.cycle.softLavenderCard,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  answer == null
                      ? 'There were $gap days before this period. Was that a '
                          'real cycle, or did you miss logging?'
                      : answer
                          ? '$gap-day gap counted as a real cycle.'
                          : '$gap-day gap treated as missed logging.',
                  style: context.text.bodySmall,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    if (answer != true)
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 36)),
                        onPressed: () => _answer(ref, context, true),
                        child: const Text('Real cycle'),
                      ),
                    if (answer != false)
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 36)),
                        onPressed: () => _answer(ref, context, false),
                        child: const Text('Missed logging'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context) {
    final duration = period.durationDays;
    final trailing = duration != null
        ? '$duration day${duration == 1 ? '' : 's'}'
        : period.isOngoingOn(today)
            ? 'Ongoing'
            : 'End not set';
    return ListTile(
      leading: Icon(Icons.water_drop, color: context.cycle.period),
      title: Text(label),
      subtitle: cycleLength == null ? null : Text('Cycle: $cycleLength days'),
      trailing: Text(
        trailing,
        style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      onTap: () => context.push(AppRoutes.periodEdit(period.id)),
    );
  }
}
