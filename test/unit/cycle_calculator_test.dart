import 'package:cyclesync/domain/cycle_calculator.dart';
import 'package:cyclesync/domain/dates.dart';
import 'package:cyclesync/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

Period p(String id, DateTime start, [DateTime? end]) =>
    Period(id: id, start: start, end: end);

/// Periods with the given cycle lengths, starting at [first], each 5 days long.
List<Period> history(DateTime first, List<int> cycles, {int length = 5}) {
  final out = <Period>[];
  var start = first;
  out.add(p('p0', start, addDays(start, length - 1)));
  for (var i = 0; i < cycles.length; i++) {
    start = addDays(start, cycles[i]);
    out.add(p('p${i + 1}', start, addDays(start, length - 1)));
  }
  return out;
}

void main() {
  group('dates', () {
    test('daysBetween counts calendar days across month and year ends', () {
      expect(daysBetween(d(2026, 1, 31), d(2026, 2, 1)), 1);
      expect(daysBetween(d(2025, 12, 31), d(2026, 1, 1)), 1);
      expect(daysBetween(d(2026, 3, 1), d(2026, 2, 1)), -28);
    });

    test('leap years', () {
      expect(daysBetween(d(2028, 2, 28), d(2028, 3, 1)), 2);
      expect(addDays(d(2028, 2, 28), 1), d(2028, 2, 29));
      expect(addDays(d(2027, 2, 28), 1), d(2027, 3, 1));
    });

    test('dateOnly ignores time of day and time zone', () {
      final lateLocal = DateTime(2026, 3, 29, 23, 59);
      expect(dateOnly(lateLocal), d(2026, 3, 29));
      expect(daysBetween(DateTime(2026, 3, 28, 1), DateTime(2026, 3, 30, 23)),
          2);
    });

    test('db date round trip', () {
      expect(toDbDate(d(2026, 11, 8)), '2026-11-08');
      expect(parseDbDate('2026-11-08'), d(2026, 11, 8));
      expect(() => parseDbDate('nope'), throwsFormatException);
    });

    test('startOfWeek is Monday', () {
      expect(startOfWeek(d(2026, 11, 8)), d(2026, 11, 2)); // Sunday
      expect(startOfWeek(d(2026, 11, 2)), d(2026, 11, 2)); // Monday
    });
  });

  group('no history', () {
    test('no periods and no setting gives no estimate', () {
      final s = CycleCalculator.summarize(periods: [], today: d(2026, 11, 8));
      expect(s.hasEstimate, isFalse);
      expect(s.cycleDay, isNull);
      expect(s.cycleLength, isNull);
      expect(s.predictedPeriodDays, isEmpty);
    });

    test('never assumes a default 28-day cycle', () {
      final s = CycleCalculator.summarize(
        periods: [p('a', d(2026, 11, 1), d(2026, 11, 5))],
        today: d(2026, 11, 8),
      );
      expect(s.cycleLength, isNull);
      expect(s.nextPeriodStart, isNull);
      expect(s.cycleDay, 8);
    });
  });

  group('first-ever period with user setting', () {
    test('uses the setting and labels it as such', () {
      final s = CycleCalculator.summarize(
        periods: [p('a', d(2026, 11, 1), d(2026, 11, 5))],
        today: d(2026, 11, 8),
        typicalCycleLength: 30,
        typicalPeriodLength: 4,
      );
      expect(s.cycleSource, EstimateSource.userSetting);
      expect(s.nextPeriodStart, d(2026, 12, 1));
      expect(s.daysUntilNext, 23);
      expect(s.predictedPeriodDays, contains(d(2026, 12, 4)));
      expect(s.predictedPeriodDays, isNot(contains(d(2026, 12, 5))));
    });
  });

  group('one or two intervals', () {
    test('two intervals still use the setting, not history', () {
      final periods = history(d(2026, 8, 1), [26, 27]);
      final s = CycleCalculator.summarize(
        periods: periods,
        today: d(2026, 10, 1),
        typicalCycleLength: 30,
      );
      expect(s.stats.validIntervals, [26, 27]);
      expect(s.cycleSource, EstimateSource.userSetting);
      expect(s.cycleLength, 30);
      expect(s.stats.averageCycle, isNull);
    });

    test('two intervals and no setting: no estimate', () {
      final s = CycleCalculator.summarize(
        periods: history(d(2026, 8, 1), [26, 27]),
        today: d(2026, 10, 1),
      );
      expect(s.hasEstimate, isFalse);
    });
  });

  group('three or more intervals', () {
    test('median of recent valid intervals', () {
      final periods = history(d(2026, 1, 5), [28, 30, 29]);
      final s = CycleCalculator.summarize(
        periods: periods,
        today: d(2026, 4, 10),
        typicalCycleLength: 35,
      );
      expect(s.cycleSource, EstimateSource.history);
      expect(s.cycleLength, 29);
      expect(s.nextPeriodStart, addDays(s.lastPeriod!.start, 29));
    });

    test('only the latest six intervals count', () {
      final periods = history(d(2025, 1, 1), [40, 40, 40, 40, 26, 26, 26, 26, 26, 26]);
      final s = CycleCalculator.summarize(
        periods: periods,
        today: addDays(periods.last.start, 3),
      );
      expect(s.cycleLength, 26);
    });

    test('even count median is rounded average of the middle two', () {
      expect(CycleCalculator.median([28, 29, 30, 31]), 30);
      expect(CycleCalculator.median([27, 28]), 28);
    });

    test('averages and variation in stats', () {
      final s = CycleCalculator.summarize(
        periods: history(d(2026, 1, 1), [27, 29, 31]),
        today: d(2026, 5, 1),
      );
      expect(s.stats.averageCycle, 29);
      expect(s.stats.variation, 4);
      expect(s.stats.averagePeriod, 5);
      expect(s.periodLength, 5);
      expect(s.periodSource, EstimateSource.history);
    });
  });

  group('irregular and invalid data', () {
    test('implausible gaps are excluded, not used', () {
      // 120-day gap (e.g. missed logging) and a 10-day gap.
      final periods = history(d(2025, 1, 1), [28, 120, 29, 10, 30, 28]);
      final s = CycleCalculator.summarize(
        periods: periods,
        today: addDays(periods.last.start, 2),
      );
      expect(s.stats.excludedIntervals, 2);
      expect(s.stats.validIntervals, [28, 29, 30, 28]);
      expect(s.cycleLength, 29);
    });

    test('mostly invalid history falls back to setting', () {
      final periods = history(d(2025, 1, 1), [90, 100, 28]);
      final s = CycleCalculator.summarize(
        periods: periods,
        today: addDays(periods.last.start, 2),
        typicalCycleLength: 31,
      );
      expect(s.cycleSource, EstimateSource.userSetting);
      expect(s.cycleLength, 31);
    });
  });

  group('ongoing period', () {
    test('recent period with no end is ongoing; cycle day counts from start',
        () {
      final s = CycleCalculator.summarize(
        periods: [
          p('a', d(2026, 10, 4), d(2026, 10, 8)),
          p('b', d(2026, 11, 6)),
        ],
        today: d(2026, 11, 8),
        typicalCycleLength: 30,
      );
      expect(s.ongoingPeriod?.id, 'b');
      expect(s.cycleDay, 3);
      expect(s.periodOn(d(2026, 11, 8))?.id, 'b');
      expect(s.periodOn(d(2026, 11, 9)), isNull);
      expect(s.nextPeriodStart, d(2026, 12, 6));
    });

    test('an old open-ended record is not treated as ongoing', () {
      final old = p('a', d(2026, 9, 1));
      expect(old.isOngoingOn(d(2026, 11, 8)), isFalse);
      expect(old.effectiveEnd(d(2026, 11, 8)), d(2026, 9, 14));
    });

    test('predictions never land inside the current period', () {
      final s = CycleCalculator.summarize(
        periods: [p('b', d(2026, 11, 6))],
        today: d(2026, 11, 8),
        typicalCycleLength: 21,
        typicalPeriodLength: 5,
      );
      expect(s.predictedPeriodDays.every((x) => x.isAfter(d(2026, 11, 8))),
          isTrue);
    });
  });

  group('edits and deletes', () {
    test('adding then removing a period changes the estimate', () {
      final base = history(d(2026, 1, 1), [28, 28, 28]);
      final withExtra = [...base, p('x', addDays(base.last.start, 35))];
      final a = CycleCalculator.summarize(periods: base, today: d(2026, 4, 1));
      final b =
          CycleCalculator.summarize(periods: withExtra, today: d(2026, 5, 10));
      expect(a.cycleLength, 28);
      expect(b.lastPeriod!.id, 'x');
      expect(b.stats.validIntervals.last, 35);
      final c = CycleCalculator.summarize(periods: base, today: d(2026, 4, 1));
      expect(c.cycleLength, a.cycleLength);
    });

    test('order of input does not matter', () {
      final periods = history(d(2026, 1, 1), [27, 30, 28]);
      final a = CycleCalculator.summarize(periods: periods, today: d(2026, 5, 1));
      final b = CycleCalculator.summarize(
          periods: periods.reversed.toList(), today: d(2026, 5, 1));
      expect(a.nextPeriodStart, b.nextPeriodStart);
    });
  });

  group('late period', () {
    test('estimate in the past gives negative days', () {
      final s = CycleCalculator.summarize(
        periods: [p('a', d(2026, 10, 1), d(2026, 10, 5))],
        today: d(2026, 11, 8),
        typicalCycleLength: 30,
      );
      expect(s.nextPeriodStart, d(2026, 10, 31));
      expect(s.daysUntilNext, -8);
      expect(s.predictedPeriodDays.every((x) => !x.isBefore(d(2026, 11, 8))),
          isTrue);
    });
  });

  group('fertile window', () {
    test('hidden unless opted in', () {
      final s = CycleCalculator.summarize(
        periods: [p('a', d(2026, 11, 1), d(2026, 11, 5))],
        today: d(2026, 11, 6),
        typicalCycleLength: 28,
      );
      expect(s.fertileDays, isEmpty);
      expect(s.ovulationDays, isEmpty);
    });

    test('needs real history, not just a typed-in cycle length', () {
      final s = CycleCalculator.summarize(
        periods: [p('a', d(2026, 11, 1), d(2026, 11, 5))],
        today: d(2026, 11, 6),
        typicalCycleLength: 28,
        includeFertileWindow: true,
      );
      expect(s.fertileDays, isEmpty);
    });

    test('estimated 14 days before next start, window -5..+1', () {
      final s = CycleCalculator.summarize(
        periods: history(d(2026, 8, 9), [28, 28, 28]),
        today: d(2026, 11, 6),
        includeFertileWindow: true,
        cyclesToPredict: 1,
      );
      // next start 29 Nov -> ovulation 15 Nov -> window 10..16 Nov
      expect(s.ovulationDays, {d(2026, 11, 15)});
      expect(s.fertileDays.length, 7);
      expect(s.fertileDays, contains(d(2026, 11, 10)));
      expect(s.fertileDays, contains(d(2026, 11, 16)));
      final w = s.upcomingFertileWindow!;
      expect(w.start, d(2026, 11, 10));
      expect(w.end, d(2026, 11, 16));
    });
  });

  group('overlap detection', () {
    final existing = [
      p('a', d(2026, 10, 1), d(2026, 10, 5)),
      p('b', d(2026, 11, 6)), // open
    ];
    final today = d(2026, 11, 8);

    test('detects overlap with a closed period', () {
      final o = CycleCalculator.findOverlap(
          existing: existing, start: d(2026, 10, 5), end: d(2026, 10, 7), today: today);
      expect(o?.id, 'a');
    });

    test('detects overlap with an open period running to today', () {
      final o = CycleCalculator.findOverlap(
          existing: existing, start: d(2026, 11, 8), today: today);
      expect(o?.id, 'b');
    });

    test('no overlap for a separate range', () {
      final o = CycleCalculator.findOverlap(
          existing: existing, start: d(2026, 10, 10), end: d(2026, 10, 12), today: today);
      expect(o, isNull);
    });

    test('editing a period ignores itself', () {
      final o = CycleCalculator.findOverlap(
          existing: existing,
          start: d(2026, 10, 2),
          end: d(2026, 10, 6),
          excludeId: 'a',
          today: today);
      expect(o, isNull);
    });
  });

  group('long gaps and staleness', () {
    test('a confirmed long gap counts as a cycle', () {
      final ps = [
        p('a', d(2026, 1, 1), d(2026, 1, 5)),
        p('b', d(2026, 3, 22), d(2026, 3, 26)), // 80 days
        Period(
            id: 'c',
            start: d(2026, 6, 10),
            end: d(2026, 6, 14),
            gapIsCycle: true), // 80 days, confirmed
      ];
      final s = CycleCalculator.summarize(periods: ps, today: d(2026, 6, 20));
      expect(s.stats.validIntervals, [80]);
      expect(s.stats.unconfirmedLongGaps.single.$1.id, 'b');
      expect(s.stats.unconfirmedLongGaps.single.$2, 80);
    });

    test('a gap marked as missed logging is not counted or asked about', () {
      final ps = [
        p('a', d(2026, 1, 1)),
        Period(id: 'b', start: d(2026, 3, 22), gapIsCycle: false),
      ];
      final s = CycleCalculator.summarize(periods: ps, today: d(2026, 3, 25));
      expect(s.stats.validIntervals, isEmpty);
      expect(s.stats.unconfirmedLongGaps, isEmpty);
    });

    test('no estimate when more than two cycles have passed', () {
      final s = CycleCalculator.summarize(
        periods: [p('a', d(2026, 6, 1), d(2026, 6, 5))],
        today: d(2026, 9, 1),
        typicalCycleLength: 28,
      );
      expect(s.staleEstimate, isTrue);
      expect(s.hasEstimate, isFalse);
      expect(s.predictedPeriodDays, isEmpty);
    });

    test('paused predictions show no estimate', () {
      final s = CycleCalculator.summarize(
        periods: history(d(2026, 6, 1), [28, 28, 28]),
        today: d(2026, 9, 1),
        pausePredictions: true,
      );
      expect(s.paused, isTrue);
      expect(s.hasEstimate, isFalse);
    });

    test('likely window from shortest and longest recent cycles', () {
      final s = CycleCalculator.summarize(
        periods: history(d(2026, 6, 1), [27, 30, 28]),
        today: d(2026, 8, 30),
      );
      // last start 25 Aug
      expect(s.nextWindow!.earliest, d(2026, 9, 21));
      expect(s.nextWindow!.latest, d(2026, 9, 24));
    });
  });

  group('period model', () {
    test('duration is inclusive', () {
      expect(p('a', d(2026, 1, 30), d(2026, 2, 2)).durationDays, 4);
      expect(p('a', d(2026, 1, 30)).durationDays, isNull);
    });
  });
}
