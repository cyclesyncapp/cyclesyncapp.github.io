import 'package:cyclesync/domain/cycle_calculator.dart';
import 'package:cyclesync/domain/models.dart';
import 'package:cyclesync/domain/reminder_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime.utc(2026, 11, 8);
  // Starts 9 Aug, 6 Sep, 4 Oct, 1 Nov (28-day cycles, 5-day periods).
  final summary = CycleCalculator.summarize(
    periods: [
      for (final s in [
        DateTime.utc(2026, 8, 9),
        DateTime.utc(2026, 9, 6),
        DateTime.utc(2026, 10, 4),
        DateTime.utc(2026, 11, 1),
      ])
        Period(
            id: '$s', start: s, end: s.add(const Duration(days: 4))),
    ],
    today: today,
    includeFertileWindow: true,
  );
  final now = DateTime(2026, 11, 8, 10, 0);

  test('nothing planned when all reminders are off', () {
    expect(
      ReminderPlanner.plan(
          prefs: const ReminderPrefs(), summary: summary, now: now),
      isEmpty,
    );
  });

  test('period reminder N days before at 09:00, neutral by default', () {
    final plan = ReminderPlanner.plan(
      prefs: const ReminderPrefs(
          periodReminderEnabled: true, reminderDaysBefore: 3),
      summary: summary,
      now: now,
    );
    expect(plan, hasLength(1));
    expect(plan.first.at, DateTime(2026, 11, 26, 9));
    expect(plan.first.body, ReminderPlanner.neutralBody);
  });

  test('detailed text only when neutral text is off', () {
    final plan = ReminderPlanner.plan(
      prefs: const ReminderPrefs(
        periodReminderEnabled: true,
        reminderDaysBefore: 1,
        neutralText: false,
      ),
      summary: summary,
      now: now,
    );
    expect(plan.first.body, contains('1 day'));
  });

  test('daily reminder rolls to tomorrow if the time has passed', () {
    final plan = ReminderPlanner.plan(
      prefs: const ReminderPrefs(
          dailyReminderEnabled: true, dailyHour: 8, dailyMinute: 0),
      summary: summary,
      now: now,
    );
    expect(plan.single.at, DateTime(2026, 11, 9, 8));
    expect(plan.single.repeatsDaily, isTrue);
  });

  test('fertile reminder on the first estimated day', () {
    final plan = ReminderPlanner.plan(
      prefs: const ReminderPrefs(fertileReminderEnabled: true),
      summary: summary,
      now: now,
    );
    expect(plan.single.at, DateTime(2026, 11, 10, 9));
  });

  test('in-app notices', () {
    final soon = CycleCalculator.summarize(
      periods: [
        Period(
            id: 'a',
            start: DateTime.utc(2026, 10, 13),
            end: DateTime.utc(2026, 10, 17)),
      ],
      today: today,
      typicalCycleLength: 28,
    );
    final notices = ReminderPlanner.inAppNotices(
      prefs: const ReminderPrefs(
        periodReminderEnabled: true,
        reminderDaysBefore: 3,
        dailyReminderEnabled: true,
        dailyHour: 9,
      ),
      summary: soon,
      loggedToday: false,
      now: now,
    );
    expect(notices, hasLength(2));
    expect(notices.first, contains('2 days'));
    expect(notices.last, contains("haven't checked in"));
  });

  test('pill reminder repeats daily at the chosen time', () {
    final plan = ReminderPlanner.plan(
      prefs: const ReminderPrefs(
          pillReminderEnabled: true, pillHour: 21, pillMinute: 30),
      summary: summary,
      now: now,
    );
    expect(plan.single.kind, ReminderKind.pill);
    expect(plan.single.at, DateTime(2026, 11, 8, 21, 30));
    expect(plan.single.repeatsDaily, isTrue);
    expect(plan.single.body, ReminderPlanner.neutralBody);
  });

  test('injection reminders a week before and on the due day', () {
    final plan = ReminderPlanner.plan(
      prefs: ReminderPrefs(
        injectionReminderEnabled: true,
        injectionLastDate: DateTime.utc(2026, 9, 1),
        injectionIntervalWeeks: 12,
      ),
      summary: summary,
      now: now,
    );
    // due 24 Nov 2026
    expect(plan.map((r) => r.at), [
      DateTime(2026, 11, 17, 9),
      DateTime(2026, 11, 24, 9),
    ]);
  });
}
