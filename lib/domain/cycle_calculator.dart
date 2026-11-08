import 'dart:math' as math;

import 'dates.dart';
import 'models.dart';

/// Where an estimate came from, so the UI can explain it honestly.
enum EstimateSource { history, userSetting }

class CycleSummary {
  const CycleSummary({
    required this.today,
    required this.periods,
    this.lastPeriod,
    this.ongoingPeriod,
    this.cycleDay,
    this.cycleLength,
    this.cycleSource,
    this.periodLength,
    this.periodSource,
    this.nextPeriodStart,
    this.predictedPeriodDays = const {},
    this.fertileDays = const {},
    this.ovulationDays = const {},
    this.stats = const CycleStats(),
    this.nextWindow,
    this.staleEstimate = false,
    this.paused = false,
  });

  final DateTime today;

  /// All periods, newest first.
  final List<Period> periods;
  final Period? lastPeriod;
  final Period? ongoingPeriod;

  /// Day of the current cycle (start = day 1), when a start is known.
  final int? cycleDay;

  final int? cycleLength;
  final EstimateSource? cycleSource;
  final int? periodLength;
  final EstimateSource? periodSource;

  final DateTime? nextPeriodStart;

  /// Estimated (not logged) period days from today onward.
  final Set<DateTime> predictedPeriodDays;

  /// Estimated fertile-window days; empty unless the user opted in.
  final Set<DateTime> fertileDays;
  final Set<DateTime> ovulationDays;

  final CycleStats stats;

  /// Likely range for the next start, from the shortest and longest recent
  /// cycles. Only when estimates come from the user's own history.
  final ({DateTime earliest, DateTime latest})? nextWindow;

  /// True when it has been more than two cycles since the last logged
  /// period, so no estimate is shown.
  final bool staleEstimate;

  /// Predictions paused (pregnant, postpartum, breastfeeding).
  final bool paused;

  bool get hasEstimate => nextPeriodStart != null;

  /// Days until the estimated next start. Negative when the estimate has passed.
  int? get daysUntilNext =>
      nextPeriodStart == null ? null : daysBetween(today, nextPeriodStart!);

  /// The fertile window that is current or next, if any.
  ({DateTime start, DateTime end})? get upcomingFertileWindow {
    final future = fertileDays.where((d) => !d.isBefore(today)).toList()
      ..sort();
    if (future.isEmpty) return null;
    var end = future.first;
    for (final d in future.skip(1)) {
      if (daysBetween(end, d) == 1) {
        end = d;
      } else {
        break;
      }
    }
    return (start: future.first, end: end);
  }

  /// The logged period covering [day], if any.
  Period? periodOn(DateTime day) {
    for (final p in periods) {
      if (p.covers(day, today)) return p;
    }
    return null;
  }
}

class CycleStats {
  const CycleStats({
    this.intervals = const [],
    this.validIntervals = const [],
    this.validPoints = const [],
    this.unconfirmedLongGaps = const [],
    this.durations = const [],
    this.averageCycle,
    this.averagePeriod,
    this.shortestCycle,
    this.longestCycle,
  });

  /// Days between consecutive starts, oldest first.
  final List<int> intervals;

  /// Intervals used for estimates, oldest first.
  final List<int> validIntervals;

  /// (start of cycle, length) for each interval used, oldest first.
  final List<(DateTime, int)> validPoints;

  /// Periods whose preceding gap is over 60 days and the user has not said
  /// whether it was a real cycle. (period, gap days)
  final List<(Period, int)> unconfirmedLongGaps;

  /// Recorded period durations, oldest first.
  final List<int> durations;

  final double? averageCycle;
  final double? averagePeriod;
  final int? shortestCycle;
  final int? longestCycle;

  /// Difference between longest and shortest recent cycle.
  int? get variation => (shortestCycle == null || longestCycle == null)
      ? null
      : longestCycle! - shortestCycle!;

  int get excludedIntervals => intervals.length - validIntervals.length;
}

class CycleCalculator {
  const CycleCalculator._();

  static const int minValidCycle = 15;
  static const int maxValidCycle = 60;

  /// Longest gap that can count as a real cycle once the user confirms it.
  static const int maxConfirmedCycle = 180;

  /// Intervals needed before history is used instead of the user's setting.
  static const int minIntervalsForEstimate = 3;

  /// Recorded durations needed before history is used for period length.
  static const int minDurationsForEstimate = 3;

  /// Only the latest N values feed an estimate, so recent changes count.
  static const int recentWindow = 6;

  static const int lutealDays = 14;
  static const int fertileDaysBefore = 5;
  static const int fertileDaysAfter = 1;

  /// Periods sorted by start, oldest first.
  static List<Period> sortedByStart(Iterable<Period> periods) =>
      periods.toList()..sort((a, b) => a.start.compareTo(b.start));

  /// Days between each start and the next, oldest first.
  static List<int> cycleIntervals(Iterable<Period> periods) {
    final sorted = sortedByStart(periods);
    return [
      for (var i = 1; i < sorted.length; i++)
        daysBetween(sorted[i - 1].start, sorted[i].start),
    ];
  }

  static bool isValidInterval(int days) =>
      days >= minValidCycle && days <= maxValidCycle;

  /// Whether the gap ending at [next] counts as a cycle.
  static bool countsAsCycle(int days, Period next) {
    if (isValidInterval(days)) return true;
    return days > maxValidCycle &&
        days <= maxConfirmedCycle &&
        next.gapIsCycle == true;
  }

  /// Median rounded to whole days; null for an empty list.
  static int? median(List<int> values) {
    if (values.isEmpty) return null;
    final s = [...values]..sort();
    final mid = s.length ~/ 2;
    if (s.length.isOdd) return s[mid];
    return ((s[mid - 1] + s[mid]) / 2).round();
  }

  static List<T> _latest<T>(List<T> values, int n) =>
      values.length <= n ? values : values.sublist(values.length - n);

  static CycleStats stats(List<Period> periods) {
    final sorted = sortedByStart(periods);
    final intervals = cycleIntervals(sorted);
    final valid = <int>[];
    final points = <(DateTime, int)>[];
    final unconfirmed = <(Period, int)>[];
    for (var i = 1; i < sorted.length; i++) {
      final days = intervals[i - 1];
      if (countsAsCycle(days, sorted[i])) {
        valid.add(days);
        points.add((sorted[i - 1].start, days));
      } else if (days > maxValidCycle &&
          days <= maxConfirmedCycle &&
          sorted[i].gapIsCycle == null) {
        unconfirmed.add((sorted[i], days));
      }
    }
    final durations = [
      for (final p in sortedByStart(periods))
        if (p.durationDays != null) p.durationDays!,
    ];
    final recentValid = _latest(valid, recentWindow);
    final enoughCycles = valid.length >= minIntervalsForEstimate;
    final enoughDurations = durations.length >= minDurationsForEstimate;
    return CycleStats(
      intervals: intervals,
      validIntervals: valid,
      validPoints: points,
      unconfirmedLongGaps: unconfirmed,
      durations: durations,
      averageCycle:
          enoughCycles ? median(recentValid)!.toDouble() : null,
      averagePeriod: enoughDurations
          ? median(_latest(durations, recentWindow))!.toDouble()
          : null,
      shortestCycle: enoughCycles ? recentValid.reduce(math.min) : null,
      longestCycle: enoughCycles ? recentValid.reduce(math.max) : null,
    );
  }

  /// Builds every estimate the app shows from the user's own records.
  ///
  /// [typicalCycleLength] / [typicalPeriodLength] are the user's optional
  /// settings, used only until there is enough history. No generic default
  /// (such as 28 days) is ever assumed.
  static CycleSummary summarize({
    required List<Period> periods,
    required DateTime today,
    int? typicalCycleLength,
    int? typicalPeriodLength,
    bool includeFertileWindow = false,
    bool pausePredictions = false,
    int cyclesToPredict = 3,
  }) {
    final day = dateOnly(today);
    final oldestFirst = sortedByStart(periods);
    final newestFirst = oldestFirst.reversed.toList();
    final st = stats(oldestFirst);

    // Only starts on or before today count as "last period".
    Period? last;
    for (final p in newestFirst) {
      if (!p.start.isAfter(day)) {
        last = p;
        break;
      }
    }
    final ongoing = (last != null && last.isOngoingOn(day)) ? last : null;
    final cycleDay = last == null ? null : daysBetween(last.start, day) + 1;

    // Cycle length estimate.
    int? cycleLength;
    EstimateSource? cycleSource;
    if (st.validIntervals.length >= minIntervalsForEstimate) {
      cycleLength = median(_latest(st.validIntervals, recentWindow));
      cycleSource = EstimateSource.history;
    } else if (typicalCycleLength != null) {
      cycleLength = typicalCycleLength;
      cycleSource = EstimateSource.userSetting;
    }

    // Period length estimate.
    int? periodLength;
    EstimateSource? periodSource;
    if (st.durations.length >= minDurationsForEstimate) {
      periodLength = median(_latest(st.durations, recentWindow));
      periodSource = EstimateSource.history;
    } else if (typicalPeriodLength != null) {
      periodLength = typicalPeriodLength;
      periodSource = EstimateSource.userSetting;
    }

    DateTime? nextStart;
    final predicted = <DateTime>{};
    final fertile = <DateTime>{};
    final ovulation = <DateTime>{};

    // More than two cycles since the last logged period: no estimate.
    final stale = last != null &&
        cycleLength != null &&
        daysBetween(last.start, day) > cycleLength * 2;

    // The fertile window needs real history, not just a typed-in length.
    final fertileAllowed =
        includeFertileWindow && cycleSource == EstimateSource.history;

    if (last != null && cycleLength != null && !stale && !pausePredictions) {
      nextStart = addDays(last.start, cycleLength);
      final lastCovered = last.effectiveEnd(day);

      for (var k = 1; k <= cyclesToPredict; k++) {
        final start = addDays(last.start, cycleLength * k);
        final len = periodLength ?? 1;
        for (var i = 0; i < len; i++) {
          final d = addDays(start, i);
          if (!d.isBefore(day) && d.isAfter(lastCovered)) predicted.add(d);
        }

        if (fertileAllowed) {
          final ov = addDays(start, -lutealDays);
          for (var i = -fertileDaysBefore; i <= fertileDaysAfter; i++) {
            final d = addDays(ov, i);
            if (!d.isBefore(day) && d.isAfter(lastCovered)) fertile.add(d);
          }
          if (!ov.isBefore(day) && ov.isAfter(lastCovered)) ovulation.add(ov);
        }
      }
      // A day can't be both an estimated period day and fertile.
      fertile.removeAll(predicted);
      ovulation.removeAll(predicted);
    }

    ({DateTime earliest, DateTime latest})? window;
    final lastStart = last?.start;
    if (nextStart != null &&
        lastStart != null &&
        cycleSource == EstimateSource.history &&
        st.shortestCycle != null &&
        st.longestCycle != null) {
      window = (
        earliest: addDays(lastStart, st.shortestCycle!),
        latest: addDays(lastStart, st.longestCycle!),
      );
    }

    return CycleSummary(
      today: day,
      periods: newestFirst,
      nextWindow: window,
      staleEstimate: stale && !pausePredictions,
      paused: pausePredictions,
      lastPeriod: last,
      ongoingPeriod: ongoing,
      cycleDay: cycleDay,
      cycleLength: cycleLength,
      cycleSource: cycleSource,
      periodLength: periodLength,
      periodSource: periodSource,
      nextPeriodStart: nextStart,
      predictedPeriodDays: predicted,
      fertileDays: fertile,
      ovulationDays: ovulation,
      stats: st,
    );
  }

  /// Returns a recorded period that would overlap a period from [start] to
  /// [end] (open-ended if null), ignoring [excludeId]. Null if none.
  static Period? findOverlap({
    required List<Period> existing,
    required DateTime start,
    DateTime? end,
    String? excludeId,
    required DateTime today,
  }) {
    final candidate = Period(id: '_candidate', start: start, end: end);
    final cStart = candidate.start;
    final cEnd = candidate.effectiveEnd(today);
    for (final p in existing) {
      if (p.id == excludeId) continue;
      final pEnd = p.effectiveEnd(today);
      final overlaps = !cStart.isAfter(pEnd) && !p.start.isAfter(cEnd);
      if (overlaps) return p;
    }
    return null;
  }
}
