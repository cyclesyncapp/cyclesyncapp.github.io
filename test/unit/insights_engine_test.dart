import 'package:cyclesync/domain/cycle_calculator.dart';
import 'package:cyclesync/domain/dates.dart';
import 'package:cyclesync/domain/insights_engine.dart';
import 'package:cyclesync/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

List<Period> history(DateTime first, List<int> cycles, {int length = 5}) {
  final out = <Period>[];
  var start = first;
  out.add(Period(id: 'p0', start: start, end: addDays(start, length - 1)));
  for (var i = 0; i < cycles.length; i++) {
    start = addDays(start, cycles[i]);
    out.add(
        Period(id: 'p${i + 1}', start: start, end: addDays(start, length - 1)));
  }
  return out;
}

Insights run(
  List<Period> periods,
  List<DailyLog> logs,
  DateTime today, {
  int? typical,
  Contraception? contraception,
  LifeStage lifeStage = LifeStage.cycling,
}) {
  final s = CycleCalculator.summarize(
    periods: periods,
    today: today,
    typicalCycleLength: typical,
    pausePredictions: lifeStage.paused,
  );
  return InsightsEngine.analyze(
    summary: s,
    logs: logs,
    contraception: contraception,
    lifeStage: lifeStage,
  );
}

bool hasTitle(Insights r, String text) =>
    r.suggestions.any((s) => s.title.contains(text));

void main() {
  final periods = history(d(2026, 6, 1), [28, 30, 27, 29]);
  // starts: 1 Jun, 29 Jun, 29 Jul, 25 Aug, 23 Sep
  final today = d(2026, 10, 10);

  test('logs are placed by cycle day and by days before the next period', () {
    final sorted = CycleCalculator.sortedByStart(periods);
    expect(InsightsEngine.bucketOf(d(2026, 6, 2), sorted, null)!.bucket, 0);
    expect(InsightsEngine.bucketOf(d(2026, 6, 8), sorted, null)!.bucket, 1);
    expect(InsightsEngine.bucketOf(d(2026, 6, 15), sorted, null)!.bucket, 2);
    // 29 Jun is the next start: 23 Jun = 6 days before, 27 Jun = 2 days before.
    expect(InsightsEngine.bucketOf(d(2026, 6, 23), sorted, null)!.bucket, 3);
    expect(InsightsEngine.bucketOf(d(2026, 6, 27), sorted, null)!.bucket, 4);
    expect(InsightsEngine.bucketOf(d(2026, 5, 1), sorted, null), isNull);
  });

  test('a pattern needs 5+ logs across at least 2 cycles', () {
    final logs = [
      for (final p in periods)
        DailyLog(date: addDays(p.start, 1), symptoms: const [Symptom.cramps]),
    ];
    final r = run(periods, logs, today);
    final peak = r.symptomGrid.peak(Symptom.cramps)!;
    expect(peak.count, 5);
    expect(peak.cycleCount, 5);
    expect(hasTitle(r, 'Cramps tends to show up on cycle days 1–5'), isTrue);
  });

  test('pre-period pattern is detected', () {
    final logs = [
      for (final p in periods.skip(1))
        for (final back in [1, 2])
          DailyLog(
              date: addDays(p.start, -back),
              symptoms: const [Symptom.headache]),
    ];
    final r = run(periods, logs, today);
    expect(hasTitle(r, 'Headache tends to show up 1–3 days before your period'),
        isTrue);
  });

  test('three logs are not enough for a pattern', () {
    final logs = [
      for (final p in periods.take(3))
        DailyLog(date: addDays(p.start, 1), symptoms: const [Symptom.acne]),
    ];
    final r = run(periods, logs, today);
    expect(r.suggestions.where((s) => s.kind == SuggestionKind.pattern),
        isEmpty);
  });

  test('flow by period day averages logged flow', () {
    final logs = [
      DailyLog(date: d(2026, 6, 1), flow: FlowLevel.medium),
      DailyLog(date: d(2026, 6, 2), flow: FlowLevel.heavy),
      DailyLog(date: d(2026, 6, 29), flow: FlowLevel.light),
      DailyLog(date: d(2026, 6, 30), flow: FlowLevel.heavy),
    ];
    final r = run(periods, logs, today);
    expect(r.flowByPeriodDay, [2.5, 4.0]);
    expect(hasTitle(r, 'heaviest flow is usually on day 2'), isTrue);
  });

  test('planning note gives the date range', () {
    final r = run(periods, const [], today);
    expect(hasTitle(r, 'between 20 October and 23 October'), isTrue);
  });

  test('long cycles note uses counts, and health notes come first', () {
    final long = history(d(2025, 1, 1), [40, 42, 41], length: 9);
    final r = run(long, const [], d(2025, 5, 20));
    expect(hasTitle(r, '3 of your last 3 cycles were longer than 35 days'),
        isTrue);
    expect(hasTitle(r, 'of your last 4 periods lasted more than 7 days'),
        isTrue);
    expect(r.suggestions.first.kind, SuggestionKind.health);
  });

  test('one long period does not trigger the long-period note', () {
    final ps = history(d(2026, 6, 1), [28, 30, 27]);
    final withOne = [
      ...ps.take(3),
      Period(id: 'x', start: ps.last.start, end: addDays(ps.last.start, 13)),
    ];
    final r = run(withOne, const [], d(2026, 9, 1));
    expect(hasTitle(r, 'lasted more than 7 days'), isFalse);
  });

  test('no health notes for typical cycles', () {
    final r = run(periods, const [], today);
    expect(
        r.suggestions.where((s) => s.kind == SuggestionKind.health), isEmpty);
  });

  test('heavy bleeding only counts recent periods', () {
    final old = [
      for (var i = 0; i < 5; i++)
        DailyLog(date: addDays(periods.first.start, i), flow: FlowLevel.heavy),
    ];
    final r = run(periods, old, today);
    expect(hasTitle(r, 'Heavy flow'), isFalse);

    final recent = [
      for (final p in periods.skip(3))
        for (var i = 0; i < 3; i++)
          DailyLog(
              date: addDays(p.start, i),
              flow: FlowLevel.heavy,
              heavySoaked: i == 0),
    ];
    final r2 = run(periods, recent, today);
    expect(hasTitle(r2, 'very heavy bleeding on 2 days'), isTrue);
  });

  test('pain that disrupted daily life twice is flagged', () {
    final logs = [
      DailyLog(date: d(2026, 9, 23), pain: 3),
      DailyLog(date: d(2026, 9, 24), pain: 2, painDisrupted: true),
    ];
    final r = run(periods, logs, today);
    expect(hasTitle(r, 'Pain stopped your usual activities on 2 days'), isTrue);
  });

  test('bleeding between periods is flagged', () {
    final logs = [
      for (final day in [5, 8, 11])
        DailyLog(date: d(2026, 9, day), flow: FlowLevel.spotting),
    ];
    final r = run(periods, logs, today);
    expect(hasTitle(r, 'Bleeding between periods on 3 days'), isTrue);
  });

  test('no period for 90+ days, but not on contraception that stops periods',
      () {
    final ps = history(d(2026, 1, 1), [28, 28, 28]);
    final r = run(ps, const [], d(2026, 7, 1));
    expect(hasTitle(r, 'No period logged for'), isTrue);
    final r2 =
        run(ps, const [], d(2026, 7, 1), contraception: Contraception.injection);
    expect(hasTitle(r2, 'No period logged for'), isFalse);
  });

  test('paused life stage has no late or missing-period notes', () {
    final ps = history(d(2026, 1, 1), [28, 28, 28]);
    final r = run(ps, const [], d(2026, 7, 1), lifeStage: LifeStage.postpartum);
    expect(r.suggestions.where((s) => s.kind == SuggestionKind.health), isEmpty);
  });

  test('asks about unconfirmed long gaps', () {
    final ps = [
      Period(id: 'a', start: d(2026, 1, 1), end: d(2026, 1, 5)),
      Period(id: 'b', start: d(2026, 3, 22), end: d(2026, 3, 26)),
    ];
    final r = run(ps, const [], d(2026, 4, 1));
    expect(hasTitle(r, 'Was the 80-day gap before 22 March a real cycle?'),
        isTrue);
  });

  test('logging streak and last-30 count', () {
    final logs = [
      for (var i = 0; i < 5; i++) DailyLog(date: addDays(today, -i)),
      DailyLog(date: addDays(today, -10)),
    ];
    final r = run(periods, logs, today);
    expect(r.loggingStreak, 5);
    expect(r.loggedDaysLast30, 6);
  });

  test('suggests adding end dates for open old periods', () {
    final ps = [
      Period(id: 'a', start: d(2026, 8, 1)),
      Period(id: 'b', start: d(2026, 8, 29), end: d(2026, 9, 2)),
    ];
    final r = run(ps, const [], today);
    expect(r.periodsWithoutEnd, 1);
    expect(hasTitle(r, 'Add end dates'), isTrue);
  });
}
