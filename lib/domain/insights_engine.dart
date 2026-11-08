import 'dart:math' as math;

import 'package:intl/intl.dart' show DateFormat;

import 'cycle_calculator.dart';
import 'dates.dart';
import 'models.dart';

/// Where in the cycle a log falls. Plain day ranges, never named "phases",
/// so nothing implies ovulation is known.
class DayBucket {
  const DayBucket(this.label, this.phrase);

  /// Short column label.
  final String label;

  /// Used in sentences, e.g. "1–3 days before your period".
  final String phrase;
}

const dayBuckets = <DayBucket>[
  DayBucket('Day\n1–5', 'cycle days 1–5'),
  DayBucket('Day\n6–10', 'cycle days 6–10'),
  DayBucket('Day\n11+', 'cycle day 11 onwards'),
  DayBucket('7–4 d\nbefore', '4–7 days before your period'),
  DayBucket('3–1 d\nbefore', '1–3 days before your period'),
];

/// Counts per item (symptom or mood) per bucket, and which cycles they came from.
class PatternGrid<T> {
  const PatternGrid(this.rows, [this.cycles = const {}]);

  /// item -> counts per bucket (same order as [dayBuckets]).
  final Map<T, List<int>> rows;

  /// item -> bucket index -> cycle start dates seen.
  final Map<T, Map<int, Set<DateTime>>> cycles;

  int get maxCount =>
      rows.values.expand((r) => r).fold(0, (a, b) => math.max(a, b));

  int total(T item) => (rows[item] ?? const []).fold(0, (a, b) => a + b);

  /// Bucket where [item] was logged most, with its share of that item's logs
  /// and in how many different cycles it happened there.
  ({DayBucket bucket, int count, int total, int cycleCount})? peak(T item) {
    final r = rows[item];
    if (r == null) return null;
    final t = total(item);
    if (t == 0) return null;
    var best = 0;
    for (var i = 1; i < r.length; i++) {
      if (r[i] > r[best]) best = i;
    }
    return (
      bucket: dayBuckets[best],
      count: r[best],
      total: t,
      cycleCount: cycles[item]?[best]?.length ?? 0,
    );
  }
}

enum SuggestionKind { health, pattern, planning, logging }

class Suggestion {
  const Suggestion(this.kind, this.title, this.body);
  final SuggestionKind kind;
  final String title;
  final String body;
}

class Insights {
  const Insights({
    required this.symptomGrid,
    required this.moodGrid,
    required this.flowByPeriodDay,
    required this.loggedDaysLast30,
    required this.loggingStreak,
    required this.periodsWithoutEnd,
    required this.suggestions,
    this.nextWindow,
  });

  final PatternGrid<Symptom> symptomGrid;
  final PatternGrid<Mood> moodGrid;

  /// Average flow (0 none … 4 heavy) for period day 1, 2, … (up to 8).
  final List<double?> flowByPeriodDay;

  /// Likely range for the next period (from the summary).
  final ({DateTime earliest, DateTime latest})? nextWindow;

  final int loggedDaysLast30;
  final int loggingStreak;
  final int periodsWithoutEnd;
  final List<Suggestion> suggestions;
}

/// Turns the user's own records into patterns and gentle, non-medical
/// suggestions. Pure and deterministic, so it can be unit-tested.
class InsightsEngine {
  const InsightsEngine._();

  /// A pattern needs at least this many logs of the item…
  static const int minLogsForPattern = 5;

  /// …with at least this many in its peak bucket…
  static const int minPeakCount = 3;

  /// …spread over at least this many different cycles.
  static const int minCyclesForPattern = 2;

  static const String mentalHealthLine =
      'SADAG Suicide Crisis Helpline 0800 567 567 (free, 24 hours)';

  /// Cycle day for [date]: days since the latest period start on or before it.
  /// Null when there is no such start or it is implausibly long ago.
  static int? cycleDayOf(DateTime date, List<Period> oldestFirst) {
    Period? start;
    for (final p in oldestFirst) {
      if (p.start.isAfter(date)) break;
      start = p;
    }
    if (start == null) return null;
    final d = daysBetween(start.start, date) + 1;
    return d > CycleCalculator.maxConfirmedCycle ? null : d;
  }

  /// Bucket index for [date], or null if it can't be placed.
  static ({int bucket, DateTime cycleStart})? bucketOf(
    DateTime date,
    List<Period> oldestFirst,
    DateTime? estimatedNext,
  ) {
    Period? start;
    DateTime? next;
    for (final p in oldestFirst) {
      if (p.start.isAfter(date)) {
        next = p.start;
        break;
      }
      start = p;
    }
    if (start == null) return null;
    next ??= estimatedNext;
    final day = daysBetween(start.start, date) + 1;
    if (day > CycleCalculator.maxConfirmedCycle) return null;
    if (day <= 5) return (bucket: 0, cycleStart: start.start);
    if (next != null && next.isAfter(date)) {
      final before = daysBetween(date, next);
      if (before >= 1 && before <= 3) return (bucket: 4, cycleStart: start.start);
      if (before >= 4 && before <= 7) return (bucket: 3, cycleStart: start.start);
    }
    return (bucket: day <= 10 ? 1 : 2, cycleStart: start.start);
  }

  static int _flowScore(FlowLevel f) => switch (f) {
        FlowLevel.none => 0,
        FlowLevel.spotting => 1,
        FlowLevel.light => 2,
        FlowLevel.medium => 3,
        FlowLevel.heavy => 4,
      };

  static Insights analyze({
    required CycleSummary summary,
    required List<DailyLog> logs,
    Contraception? contraception,
    LifeStage lifeStage = LifeStage.cycling,
  }) {
    final today = summary.today;
    final oldestFirst = CycleCalculator.sortedByStart(summary.periods);

    // ---- Patterns by cycle day ----
    final symptomRows = <Symptom, List<int>>{};
    final symptomCycles = <Symptom, Map<int, Set<DateTime>>>{};
    final moodRows = <Mood, List<int>>{};
    final moodCycles = <Mood, Map<int, Set<DateTime>>>{};
    for (final log in logs) {
      final b = bucketOf(log.date, oldestFirst, summary.nextPeriodStart);
      if (b == null) continue;
      for (final s in log.symptoms) {
        (symptomRows[s] ??= List.filled(dayBuckets.length, 0))[b.bucket]++;
        ((symptomCycles[s] ??= {})[b.bucket] ??= {}).add(b.cycleStart);
      }
      for (final m in log.moods) {
        (moodRows[m] ??= List.filled(dayBuckets.length, 0))[b.bucket]++;
        ((moodCycles[m] ??= {})[b.bucket] ??= {}).add(b.cycleStart);
      }
    }

    // ---- Flow by period day ----
    final sums = List<int>.filled(8, 0);
    final counts = List<int>.filled(8, 0);
    final logByDate = {for (final l in logs) l.date: l};
    for (final p in oldestFirst) {
      final end = p.effectiveEnd(today);
      for (var i = 0; i < 8; i++) {
        final d = addDays(p.start, i);
        if (d.isAfter(end)) break;
        final l = logByDate[d];
        if (l == null) continue;
        sums[i] += _flowScore(l.flow);
        counts[i]++;
      }
    }
    final flowByDay = [
      for (var i = 0; i < 8; i++) counts[i] == 0 ? null : sums[i] / counts[i],
    ];
    while (flowByDay.isNotEmpty && flowByDay.last == null) {
      flowByDay.removeLast();
    }

    // ---- Logging consistency ----
    final logged = logByDate.keys.toSet();
    var last30 = 0;
    for (var i = 0; i < 30; i++) {
      if (logged.contains(addDays(today, -i))) last30++;
    }
    var streak = 0;
    var cursor = logged.contains(today) ? today : addDays(today, -1);
    while (logged.contains(cursor)) {
      streak++;
      cursor = addDays(cursor, -1);
    }
    final withoutEnd = summary.periods
        .where((p) => p.end == null && !p.isOngoingOn(today))
        .length;

    final symptomGrid = PatternGrid<Symptom>(symptomRows, symptomCycles);
    final moodGrid = PatternGrid<Mood>(moodRows, moodCycles);

    return Insights(
      symptomGrid: symptomGrid,
      moodGrid: moodGrid,
      flowByPeriodDay: flowByDay,
      nextWindow: summary.nextWindow,
      loggedDaysLast30: last30,
      loggingStreak: streak,
      periodsWithoutEnd: withoutEnd,
      suggestions: _suggest(
        summary: summary,
        logs: logs,
        logByDate: logByDate,
        symptomGrid: symptomGrid,
        moodGrid: moodGrid,
        flowByDay: flowByDay,
        loggedLast30: last30,
        withoutEnd: withoutEnd,
        contraception: contraception,
        lifeStage: lifeStage,
      ),
    );
  }

  static bool _isPatternStrong(
          ({DayBucket bucket, int count, int total, int cycleCount})? p) =>
      p != null &&
      p.total >= minLogsForPattern &&
      p.count >= minPeakCount &&
      p.count / p.total >= 0.5 &&
      p.cycleCount >= minCyclesForPattern;

  static List<T> _latest<T>(List<T> values, int n) =>
      values.length <= n ? values : values.sublist(values.length - n);

  static List<Suggestion> _suggest({
    required CycleSummary summary,
    required List<DailyLog> logs,
    required Map<DateTime, DailyLog> logByDate,
    required PatternGrid<Symptom> symptomGrid,
    required PatternGrid<Mood> moodGrid,
    required List<double?> flowByDay,
    required int loggedLast30,
    required int withoutEnd,
    required Contraception? contraception,
    required LifeStage lifeStage,
  }) {
    final health = <Suggestion>[];
    final patterns = <Suggestion>[];
    final planning = <Suggestion>[];
    final logging = <Suggestion>[];
    final st = summary.stats;
    final today = summary.today;
    final fmt = DateFormat('d MMMM');
    final hormonal = contraception?.hormonal ?? false;
    final noBleedExpected = (contraception?.oftenNoBleeding ?? false) ||
        lifeStage.paused;
    final oldestFirst = CycleCalculator.sortedByStart(summary.periods);
    final recentPeriods = _latest(oldestFirst, 3);

    // ---------------- Health notes (only ever "worth discussing") --------
    if (!hormonal && !lifeStage.paused) {
      final recent = _latest(st.validIntervals, CycleCalculator.recentWindow);
      if (recent.length >= 3) {
        final long = recent.where((c) => c > 35).length;
        final short = recent.where((c) => c < 21).length;
        if (long >= 2 && long * 2 >= recent.length) {
          health.add(Suggestion(
            SuggestionKind.health,
            '$long of your last ${recent.length} cycles were longer than 35 days',
            'Cycles that are often longer than 35 days are worth mentioning to '
                'a healthcare professional, especially if this is new for you.',
          ));
        } else if (short >= 2 && short * 2 >= recent.length) {
          health.add(Suggestion(
            SuggestionKind.health,
            '$short of your last ${recent.length} cycles were shorter than 21 days',
            'Cycles that are often shorter than 21 days are worth mentioning to '
                'a healthcare professional.',
          ));
        }
      }
    }

    final durations = _latest(st.durations, CycleCalculator.recentWindow);
    final longPeriods = durations.where((d) => d > 7).length;
    if (durations.length >= 2 && longPeriods >= 2) {
      health.add(Suggestion(
        SuggestionKind.health,
        '$longPeriods of your last ${durations.length} periods lasted more '
            'than 7 days',
        'Periods that often last longer than 7 days are worth discussing with '
            'a healthcare professional.',
      ));
    }

    // Heavy bleeding in the last 3 periods only.
    var heavyDays = 0;
    var soakedDays = 0;
    var bleedDays = 0;
    var disruptedDays = 0;
    for (final p in recentPeriods) {
      final end = p.effectiveEnd(today);
      for (var d = p.start; !d.isAfter(end); d = addDays(d, 1)) {
        final l = logByDate[d];
        if (l == null) continue;
        if (l.flow.isBleeding) bleedDays++;
        if (l.flow == FlowLevel.heavy) heavyDays++;
        if (l.heavySoaked) soakedDays++;
      }
    }
    final since90 = addDays(today, -89);
    for (final l in logs) {
      if (l.date.isBefore(since90)) continue;
      if (l.painDisrupted || l.pain == 3) disruptedDays++;
    }
    if (soakedDays >= 2 || (bleedDays >= 4 && heavyDays * 2 >= bleedDays)) {
      health.add(Suggestion(
        SuggestionKind.health,
        soakedDays >= 2
            ? 'You marked very heavy bleeding on $soakedDays days'
            : 'Heavy flow on $heavyDays of $bleedDays bleeding days recently',
        'If you often soak through protection within 1–2 hours, pass large '
            'clots, or feel tired, short of breath or dizzy, please speak to '
            'a healthcare professional. Heavy periods are common and treatable.',
      ));
    }
    if (disruptedDays >= 2) {
      health.add(Suggestion(
        SuggestionKind.health,
        'Pain stopped your usual activities on $disruptedDays days',
        'Period pain that stops you doing everyday things is not something '
            'you have to put up with. It is worth discussing with a '
            'healthcare professional.',
      ));
    }

    // Bleeding between periods (last 90 days).
    var between = 0;
    for (final l in logs) {
      if (l.date.isBefore(since90) || l.date.isAfter(today)) continue;
      if (!l.flow.anyBleeding) continue;
      final inPeriod = summary.periodOn(l.date) != null;
      final nearStart = oldestFirst.any((p) {
        final gap = daysBetween(l.date, p.start);
        return gap >= 0 && gap <= 2;
      });
      if (!inPeriod && !nearStart) between++;
    }
    if (between >= 3) {
      health.add(Suggestion(
        SuggestionKind.health,
        'Bleeding between periods on $between days',
        hormonal
            ? 'Spotting between periods is common on hormonal contraception, '
                'especially in the first months. If it continues, is heavy, or '
                'happens after sex, speak to a healthcare professional.'
            : 'Bleeding between periods, or after sex, is worth mentioning to '
                'a healthcare professional.',
      ));
    }

    // No period for a long time.
    final last = summary.lastPeriod;
    if (last != null && !noBleedExpected) {
      final since = daysBetween(last.start, today);
      if (since >= 90) {
        health.add(Suggestion(
          SuggestionKind.health,
          'No period logged for $since days',
          'If your period really hasn\'t come for 3 months or more, it is worth '
              'speaking to a healthcare professional. If it has started, log it '
              'to update your estimates.',
        ));
      } else {
        // Later than the latest likely date.
        final latest = summary.nextWindow?.latest ??
            (summary.nextPeriodStart == null
                ? null
                : addDays(summary.nextPeriodStart!, 7));
        if (latest != null &&
            today.isAfter(latest) &&
            summary.ongoingPeriod == null &&
            !hormonal) {
          health.add(Suggestion(
            SuggestionKind.health,
            'No period logged yet',
            'It\'s past the latest date we estimated (${fmt.format(latest)}). '
                'Cycles can shift with stress, illness or travel. If it has '
                'started, log it to update your estimates. If there is a chance '
                'you could be pregnant, a pregnancy test can tell you.',
          ));
        }
      }
    }

    // ---------------- Patterns ----------------
    final variation = st.variation;
    if (variation != null && variation > 7 && !hormonal) {
      patterns.add(Suggestion(
        SuggestionKind.pattern,
        'Your cycle length varies by up to $variation days',
        'Some variation is common, so estimates are shown as a range. Stress, '
            'illness, travel and other changes can affect your cycle.',
      ));
    }
    for (final s in Symptom.values) {
      if (s == Symptom.other) continue;
      final peak = symptomGrid.peak(s);
      if (peak == null || !_isPatternStrong(peak)) continue;
      patterns.add(Suggestion(
        SuggestionKind.pattern,
        '${s.label} tends to show up ${_where(peak.bucket)}',
        'You logged ${s.label.toLowerCase()} on ${peak.count} of ${peak.total} '
            'days ${_where(peak.bucket)}, across ${peak.cycleCount} cycles.'
            '${_planTip(s, peak.bucket, summary)}',
      ));
      if (patterns.length >= 4) break;
    }
    for (final m in const [Mood.lowEnergy, Mood.sad, Mood.anxious, Mood.irritable]) {
      final peak = moodGrid.peak(m);
      if (peak == null || !_isPatternStrong(peak)) continue;
      patterns.add(Suggestion(
        SuggestionKind.pattern,
        'Feeling ${m.label.toLowerCase()} often ${_where(peak.bucket)}',
        'You logged "${m.label.toLowerCase()}" on ${peak.count} days '
            '${_where(peak.bucket)}. Knowing this can help you plan lighter days '
            'and rest. If low mood is affecting daily life, talk to someone you '
            'trust or a professional — $mentalHealthLine.',
      ));
      break;
    }

    // ---------------- Planning ----------------
    final window = summary.nextWindow;
    if (window != null && window.latest.isAfter(today)) {
      planning.add(Suggestion(
        SuggestionKind.planning,
        sameDate(window.earliest, window.latest)
            ? 'Your next period may start around ${fmt.format(window.earliest)}'
            : 'Your next period may start between '
                '${fmt.format(window.earliest)} and ${fmt.format(window.latest)}',
        'Based on your shortest and longest recent cycles. Keeping supplies '
            'with you from a few days before can help.',
      ));
    }
    if (flowByDay.length >= 2) {
      var peakDay = 0;
      for (var i = 1; i < flowByDay.length; i++) {
        if ((flowByDay[i] ?? 0) > (flowByDay[peakDay] ?? 0)) peakDay = i;
      }
      if ((flowByDay[peakDay] ?? 0) >= 2.5) {
        planning.add(Suggestion(
          SuggestionKind.planning,
          'Your heaviest flow is usually on day ${peakDay + 1}',
          'Plan extra supplies and breaks for period day ${peakDay + 1}.',
        ));
      }
    }

    // ---------------- Better data ----------------
    for (final (p, gap) in st.unconfirmedLongGaps.take(2)) {
      logging.add(Suggestion(
        SuggestionKind.logging,
        'Was the $gap-day gap before ${fmt.format(p.start)} a real cycle?',
        'Tell us in Period History. Real long cycles are counted in your '
            'averages and notes; missed logging is left out.',
      ));
    }
    if (summary.staleEstimate) {
      logging.add(const Suggestion(
        SuggestionKind.logging,
        'It\'s been a while',
        'Log your latest period to restart your estimates.',
      ));
    }
    if (withoutEnd > 0) {
      logging.add(Suggestion(
        SuggestionKind.logging,
        'Add end dates to $withoutEnd period${withoutEnd == 1 ? '' : 's'}',
        'End dates let CycleSync show your period length and spot changes.',
      ));
    }
    if (summary.periods.length < 4 && !lifeStage.paused) {
      logging.add(const Suggestion(
        SuggestionKind.logging,
        'Add past periods for better estimates',
        'Estimates use your own history after 3 complete cycles. Adding '
            'earlier periods from memory or another app helps.',
      ));
    } else if (loggedLast30 < 8 && !lifeStage.paused) {
      logging.add(Suggestion(
        SuggestionKind.logging,
        'You logged $loggedLast30 of the last 30 days',
        'Quick check-ins, even "no symptoms", make patterns clearer. A daily '
            'reminder can help.',
      ));
    }

    return [...health, ...patterns, ...planning, ...logging];
  }

  static String _where(DayBucket b) =>
      b.phrase.startsWith('cycle') ? 'on ${b.phrase}' : b.phrase;

  static String _planTip(Symptom s, DayBucket b, CycleSummary summary) {
    final before = identical(b, dayBuckets[3]) || identical(b, dayBuckets[4]);
    if ((!before && !identical(b, dayBuckets[0])) ||
        summary.nextPeriodStart == null) {
      return '';
    }
    final days = summary.daysUntilNext!;
    if (days < 0 || days > 10) return '';
    return switch (s) {
      Symptom.cramps || Symptom.pelvicPain || Symptom.backPain =>
        ' Your next period is estimated in $days days, so you could plan '
            'rest, warmth or the pain relief that usually works for you.',
      Symptom.headache || Symptom.fatigue || Symptom.sleepProblems =>
        ' Your next period is estimated in $days days; extra water, sleep '
            'and lighter plans may help.',
      _ => ' Your next period is estimated in $days days.',
    };
  }
}
