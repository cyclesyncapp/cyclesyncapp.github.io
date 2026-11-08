import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/constants/app_text.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/cycle_visuals.dart';
import '../../domain/cycle_calculator.dart';
import '../../domain/dates.dart';
import '../../domain/insights_engine.dart';
import '../../domain/models.dart';
import '../../routing/app_router.dart';
import 'insights_charts.dart';

/// Patterns, trends and suggestions from the user's own logs.
final insightsProvider = FutureProvider<Insights>((ref) async {
  final summary = await ref.watch(summaryProvider.future);
  final logs = await ref.watch(logsProvider.future);
  final profile = await ref.watch(profileProvider.future);
  return InsightsEngine.analyze(
    summary: summary,
    logs: logs,
    contraception: profile?.contraception,
    lifeStage: profile?.lifeStage ?? LifeStage.cycling,
  );
});

class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(summaryProvider);
    final insights = ref.watch(insightsProvider);
    final logs = ref.watch(logsProvider).value ?? const <DailyLog>[];
    final showFertile =
        ref.watch(profileProvider).value?.showFertileWindow ?? false;

    return GradientScaffold(
      title: 'Insights',
      automaticallyImplyLeading: false,
      body: (summary.hasError || insights.hasError)
          ? ErrorView(onRetry: () => refreshCycleData(ref))
          : (!summary.hasValue || !insights.hasValue)
              ? const LoadingView()
              : PageBody(
                  children: [
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('Overview')),
                        ButtonSegment(value: 1, label: Text('Trends')),
                        ButtonSegment(value: 2, label: Text('Patterns')),
                        ButtonSegment(value: 3, label: Text('About')),
                      ],
                      selected: {_tab},
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        padding: WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 4),
                        ),
                      ),
                      onSelectionChanged: (v) => setState(() => _tab = v.first),
                    ),
                    const SizedBox(height: 16),
                    ...switch (_tab) {
                      0 => _overview(context, summary.value!, insights.value!,
                          logs, showFertile),
                      1 => _trends(context, summary.value!, insights.value!),
                      2 => _patterns(context, insights.value!),
                      _ => _about(context),
                    },
                  ],
                ),
    );
  }

  // ------------------------------------------------------------ Overview

  List<Widget> _overview(BuildContext context, CycleSummary s, Insights ins,
      List<DailyLog> logs, bool showFertile) {
    final avg = s.stats.averageCycle?.round();
    final avgPeriod = s.stats.averagePeriod?.round();
    final logged = logs.map((l) => l.date).toSet();
    final strip = [
      for (var i = 29; i >= 0; i--) logged.contains(addDays(s.today, -i)),
    ];
    final fmt = DateFormat('d MMM');
    final window = ins.nextWindow;

    return [
      SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your cycle overview', style: context.text.titleMedium),
            const SizedBox(height: 16),
            Row(
              children: [
                _CycleRing(cycle: avg, period: avgPeriod),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _LegendLine(
                        color: context.cycle.period,
                        title: 'Period',
                        value: avgPeriod == null
                            ? 'Not enough data'
                            : '$avgPeriod days',
                      ),
                      const SizedBox(height: 10),
                      if (showFertile)
                        _LegendLine(
                          color: context.cycle.fertile,
                          title: 'Fertile window',
                          value: s.cycleLength == null
                              ? 'Needs a cycle estimate'
                              : '~7 days (estimate)',
                        )
                      else
                        _LegendLine(
                          color: context.colors.secondary,
                          title: 'Cycles logged',
                          value: '${s.stats.validIntervals.length}',
                        ),
                      const SizedBox(height: 10),
                      _LegendLine(
                        color: context.cycle.todayFill,
                        title: 'Cycle day',
                        value: s.cycleDay == null || s.cycleDay! > 60
                            ? '—'
                            : 'Day ${s.cycleDay}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      if (window != null && window.latest.isAfter(s.today)) ...[
        const SizedBox(height: 14),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('When your next period may start',
                  style: context.text.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Most likely ${fmt.format(window.earliest)} – '
                '${fmt.format(window.latest)}'
                '${s.nextPeriodStart == null ? '' : ', best estimate ${fmt.format(s.nextPeriodStart!)}'}.',
                style: context.text.bodyMedium,
              ),
              const SizedBox(height: 12),
              WindowTimeline(
                today: s.today,
                earliest: window.earliest.isBefore(s.today)
                    ? s.today
                    : window.earliest,
                latest: window.latest,
                estimate: s.nextPeriodStart,
              ),
            ],
          ),
        ),
      ],
      const SectionTitle('Suggestions for you'),
      if (ins.suggestions.isEmpty)
        const NoticeCard(
          icon: Icons.auto_awesome_outlined,
          text: 'Keep logging. Personal suggestions appear as patterns emerge.',
        )
      else
        for (final sug in ins.suggestions.take(7)) ...[
          _SuggestionCard(suggestion: sug),
          const SizedBox(height: 10),
        ],
      const SectionTitle('Logging in the last 30 days'),
      SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    value: '${ins.loggedDaysLast30}/30',
                    label: 'days logged',
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    value: '${ins.loggingStreak}',
                    label: 'day streak',
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    value: '${s.periods.length}',
                    label: 'periods logged',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Semantics(
              label: '${ins.loggedDaysLast30} of the last 30 days logged',
              excludeSemantics: true,
              child: LoggingStrip(logged: strip),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('30 days ago',
                    style: context.text.labelSmall
                        ?.copyWith(color: context.cycle.muted)),
                const Spacer(),
                Text('Today',
                    style: context.text.labelSmall
                        ?.copyWith(color: context.cycle.muted)),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      GradientButton(
        label: "Log Today's Symptoms",
        icon: Icons.edit_note,
        onPressed: () => context.push(AppRoutes.logFor(s.today)),
      ),
      const SizedBox(height: 12),
      Text(
        'Suggestions are based only on what you log and are not medical '
        'advice.',
        textAlign: TextAlign.center,
        style: context.text.bodySmall?.copyWith(color: context.cycle.muted),
      ),
    ];
  }

  // ------------------------------------------------------------ Trends

  List<Widget> _trends(BuildContext context, CycleSummary s, Insights ins) {
    final oldestFirst = CycleCalculator.sortedByStart(s.periods);
    final points = s.stats.validPoints;
    final recent =
        points.length > 8 ? points.sublist(points.length - 8) : points;
    final durations = [
      for (final p in oldestFirst)
        if (p.durationDays != null) (p.start, p.durationDays!),
    ];
    final recentDur = durations.length > 8
        ? durations.sublist(durations.length - 8)
        : durations;
    final st = s.stats;
    final flow = ins.flowByPeriodDay;
    const flowNames = ['None', 'Spotting', 'Light', 'Medium', 'Heavy'];
    String flowName(double v) => flowNames[v.round().clamp(0, 4)];

    return [
      Row(
        children: [
          Expanded(
            child: _StatBox(
              label: 'Average',
              value: st.averageCycle == null
                  ? '—'
                  : '${st.averageCycle!.round()}d',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatBox(
              label: 'Shortest',
              value: st.shortestCycle == null ? '—' : '${st.shortestCycle}d',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatBox(
              label: 'Longest',
              value: st.longestCycle == null ? '—' : '${st.longestCycle}d',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatBox(
              label: 'Variation',
              value: st.variation == null ? '—' : '${st.variation}d',
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cycle length', style: context.text.titleMedium),
            const SizedBox(height: 2),
            Text('Days from one period start to the next',
                style: context.text.bodySmall
                    ?.copyWith(color: context.cycle.muted)),
            const SizedBox(height: 18),
            if (recent.length < 2)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                    child: Text('Log at least 3 periods to see a trend.')),
              )
            else
              CycleRangeChart(points: recent),
          ],
        ),
      ),
      const SizedBox(height: 14),
      SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Period length', style: context.text.titleMedium),
            const SizedBox(height: 2),
            Text(
              st.averagePeriod == null
                  ? 'Days of bleeding per period'
                  : 'Dashed line: your average (${st.averagePeriod!.round()} days)',
              style:
                  context.text.bodySmall?.copyWith(color: context.cycle.muted),
            ),
            const SizedBox(height: 16),
            if (recentDur.isEmpty)
              const Text('Add end dates to your periods to see their length.')
            else
              BarChart(
                values: [for (final d in recentDur) d.$2.toDouble()],
                labels: [
                  for (final d in recentDur) DateFormat('MMM').format(d.$1),
                ],
                color: context.cycle.period,
                max: math
                    .max(8, recentDur.map((d) => d.$2).reduce(math.max))
                    .toDouble(),
                reference: st.averagePeriod,
                semanticsLabel: 'Period lengths: ${recentDur.map((d) => '${DateFormat('MMM').format(d.$1)} ${d.$2} days').join(', ')}',
              ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Flow by period day', style: context.text.titleMedium),
            const SizedBox(height: 2),
            Text('Average flow you logged on each day of your period',
                style: context.text.bodySmall
                    ?.copyWith(color: context.cycle.muted)),
            const SizedBox(height: 16),
            if (flow.isEmpty)
              const Text('Log flow during your period to see this chart.')
            else
              BarChart(
                values: flow,
                labels: [for (var i = 0; i < flow.length; i++) 'D${i + 1}'],
                color: context.colors.secondary,
                max: 4,
                valueLabel: flowName,
                semanticsLabel: 'Average flow: ${[
                  for (var i = 0; i < flow.length; i++)
                    'day ${i + 1} ${flow[i] == null ? 'no logs' : flowName(flow[i]!)}',
                ].join(', ')}',
              ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'Charts use only what you have logged. Gaps shorter than 15 or longer '
        'than 60 days are left out unless you confirm they were real cycles. '
        'The 21–35 day band is a commonly cited '
        'range for adults, shown for context only.',
        style: context.text.bodySmall?.copyWith(color: context.cycle.muted),
      ),
      const SizedBox(height: 14),
      OutlinedButton.icon(
        onPressed: () => context.push(AppRoutes.history),
        icon: const Icon(Icons.history),
        label: const Text('View Period History'),
      ),
    ];
  }

  // ------------------------------------------------------------ Patterns

  List<Widget> _patterns(BuildContext context, Insights ins) {
    final symptoms = Symptom.values
        .where((x) => ins.symptomGrid.total(x) > 0)
        .toList()
      ..sort((a, b) =>
          ins.symptomGrid.total(b).compareTo(ins.symptomGrid.total(a)));
    final moods = Mood.values.where((x) => ins.moodGrid.total(x) > 0).toList()
      ..sort((a, b) => ins.moodGrid.total(b).compareTo(ins.moodGrid.total(a)));

    final notes = <String>[
      for (final x in symptoms.take(4))
        if (ins.symptomGrid.total(x) >= InsightsEngine.minLogsForPattern)
          _peakSentence(x.label, ins.symptomGrid.peak(x)),
      for (final x in moods.take(3))
        if (ins.moodGrid.total(x) >= InsightsEngine.minLogsForPattern)
          _peakSentence(
              'Feeling ${x.label.toLowerCase()}', ins.moodGrid.peak(x)),
    ].where((n) => n.isNotEmpty).toList();

    return [
      Text(
        'How often you logged each symptom and mood, by day of your cycle '
        '(day 1 = first day of your period). Darker means more often.',
        style: context.text.bodyMedium?.copyWith(color: context.cycle.muted),
      ),
      const SectionTitle('Symptoms through your cycle'),
      SoftCard(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
        child: symptoms.isEmpty
            ? const Text('Log symptoms to see when they tend to appear.')
            : PatternHeatmap<Symptom>(
                grid: ins.symptomGrid,
                items: symptoms,
                labelOf: (x) => x.label,
                iconOf: symptomIcon,
                color: context.cycle.period,
              ),
      ),
      const SectionTitle('Mood through your cycle'),
      SoftCard(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
        child: moods.isEmpty
            ? const Text('Log your mood to see how it changes over your cycle.')
            : PatternHeatmap<Mood>(
                grid: ins.moodGrid,
                items: moods,
                labelOf: (x) => x.label,
                iconOf: moodIcon,
                color: context.colors.secondary,
              ),
      ),
      if (notes.isNotEmpty) ...[
        const SectionTitle('What stands out'),
        for (final n in notes) ...[
          NoticeCard(
            icon: Icons.insights_outlined,
            tint: context.cycle.softLavenderCard,
            text: n,
          ),
          const SizedBox(height: 8),
        ],
      ],
      const SizedBox(height: 8),
      Text(
        'Patterns need at least 3 logs to be shown. They describe your logs, '
        'not a diagnosis.',
        style: context.text.bodySmall?.copyWith(color: context.cycle.muted),
      ),
    ];
  }

  String _peakSentence(String what,
      ({DayBucket bucket, int count, int total, int cycleCount})? p) {
    if (p == null) return '';
    final pct = (p.count / p.total * 100).round();
    final where = p.bucket.phrase.startsWith('cycle')
        ? 'on ${p.bucket.phrase}'
        : p.bucket.phrase;
    return '$what: $pct% of your logs were $where '
        '(${p.count} of ${p.total}, across ${p.cycleCount} '
        'cycle${p.cycleCount == 1 ? '' : 's'}).';
  }

  // ------------------------------------------------------------ About

  List<Widget> _about(BuildContext context) {
    return [
      for (final (title, body) in AppText.howEstimatesWork) ...[
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.text.titleSmall),
              const SizedBox(height: 6),
              Text(body, style: context.text.bodyMedium),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
      SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Suggestions', style: context.text.titleSmall),
            const SizedBox(height: 6),
            Text(
              'Suggestions are simple rules applied to your own logs, for '
              'example noticing that most of your cramp logs fall on cycle '
              'days 1–5. Health notes use commonly cited guidance (such as '
              'cycles usually between 21 and 35 days, and periods up to 7 '
              'days) and only suggest talking to a professional.',
              style: context.text.bodyMedium,
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      const NoticeCard(
        icon: Icons.health_and_safety_outlined,
        text: AppText.healthDisclaimer,
      ),
    ];
  }
}

// ---------------------------------------------------------------- widgets

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.suggestion});
  final Suggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final (icon, color, tag) = switch (suggestion.kind) {
      SuggestionKind.health => (
          Icons.health_and_safety_outlined,
          const Color(0xFFE0663D),
          'Worth knowing',
        ),
      SuggestionKind.pattern => (
          Icons.insights_outlined,
          context.colors.primary,
          'Pattern',
        ),
      SuggestionKind.planning => (
          Icons.event_available_outlined,
          context.colors.secondary,
          'Plan ahead',
        ),
      SuggestionKind.logging => (
          Icons.edit_note,
          context.cycle.muted,
          'Better insights',
        ),
    };
    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBubble(icon: icon, color: color, size: 42),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tag.toUpperCase(),
                  style: context.text.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(suggestion.title, style: context.text.titleSmall),
                const SizedBox(height: 4),
                Text(suggestion.body, style: context.text.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: context.text.titleLarge
                ?.copyWith(color: context.colors.primary)),
        Text(label,
            textAlign: TextAlign.center,
            style:
                context.text.bodySmall?.copyWith(color: context.cycle.muted)),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      tint: context.cycle.softPinkCard,
      child: Column(
        children: [
          Text(value, style: context.text.titleMedium),
          const SizedBox(height: 2),
          Text(label,
              style: context.text.labelSmall
                  ?.copyWith(color: context.cycle.muted)),
        ],
      ),
    );
  }
}

class _LegendLine extends StatelessWidget {
  const _LegendLine({
    required this.color,
    required this.title,
    required this.value,
  });

  final Color color;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 5),
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.text.bodyMedium),
              Text(value, style: context.text.titleSmall),
            ],
          ),
        ),
      ],
    );
  }
}

/// Donut showing the share of an average cycle spent on the period.
class _CycleRing extends StatelessWidget {
  const _CycleRing({required this.cycle, required this.period});

  final int? cycle;
  final int? period;

  @override
  Widget build(BuildContext context) {
    final c = context.cycle;
    return Semantics(
      label: cycle == null
          ? 'Average cycle: not enough data'
          : 'Average cycle: $cycle days',
      excludeSemantics: true,
      child: SizedBox(
        width: 130,
        height: 130,
        child: CustomPaint(
          painter: _RingPainter(
            fraction: (cycle != null && period != null)
                ? (period! / cycle!).clamp(0.0, 1.0)
                : 0,
            track: c.fertileSoft,
            arc: c.period,
            rest: c.fertile.withValues(alpha: 0.55),
            hasData: cycle != null,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(cycle == null ? '—' : '$cycle',
                    style: context.text.headlineMedium),
                Text(cycle == null ? 'no average' : 'days (avg)',
                    style: context.text.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.track,
    required this.arc,
    required this.rest,
    required this.hasData,
  });

  final double fraction;
  final Color track;
  final Color arc;
  final Color rest;
  final bool hasData;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - stroke / 2,
    );
    Paint p(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, p(track));
    if (!hasData) return;
    const startAngle = -math.pi / 2;
    if (fraction > 0) {
      canvas.drawArc(rect, startAngle, 2 * math.pi * fraction, false, p(arc));
    }
    final restStart = startAngle + 2 * math.pi * fraction + 0.18;
    final restSweep = 2 * math.pi * (1 - fraction) - 0.36;
    if (restSweep > 0) {
      canvas.drawArc(rect, restStart, restSweep, false, p(rest));
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.hasData != hasData || old.arc != arc;
}
