import 'package:cyclesync/core/lock/app_lock.dart';
import 'package:cyclesync/domain/models.dart';
import 'package:cyclesync/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('signed-out users see the welcome screen', (tester) async {
    _phone(tester);
    await tester.pumpWidget(testApp(FakeRepository(signedIn: false)));
    await tester.pumpAndSettle();

    expect(find.text('CycleSync'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('new users are sent to onboarding', (tester) async {
    _phone(tester);
    final repo = FakeRepository(profile: const Profile(id: 'u1'));
    await tester.pumpWidget(testApp(repo));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to CycleSync'), findsOneWidget);
  });

  testWidgets('home shows no estimate without data', (tester) async {
    _phone(tester);
    await tester.pumpWidget(testApp(FakeRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Not enough data yet'), findsOneWidget);
    expect(find.text('Add period dates to start receiving estimates.'),
        findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('home shows countdown from the user setting', (tester) async {
    _phone(tester);
    final repo = FakeRepository(
      profile: const Profile(
        id: 'u1',
        displayName: 'Sarah Johnson',
        onboardingCompleted: true,
        typicalCycleLength: 28,
      ),
      periods: [
        Period(
          id: 'p1',
          start: DateTime.utc(2026, 11, 1),
          end: DateTime.utc(2026, 11, 5),
        ),
      ],
    );
    await tester.pumpWidget(testApp(repo));
    await tester.pumpAndSettle();

    // 1 Nov + 28 days = 29 Nov, 21 days after 8 Nov.
    expect(find.text('21 days'), findsOneWidget);
    expect(find.text('Cycle day 8'), findsOneWidget);
    expect(find.textContaining('Sarah!'), findsOneWidget);
    expect(find.text('Estimate based on your typical cycle setting'),
        findsOneWidget);
  });

  testWidgets('calendar tab shows the current month', (tester) async {
    _phone(tester);
    await tester.pumpWidget(testApp(FakeRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Calendar').last);
    await tester.pumpAndSettle();
    expect(find.text('November 2026'), findsOneWidget);
    expect(find.text('Period'), findsWidgets);
  });

  testWidgets('saving a daily log stores symptoms and mood', (tester) async {
    _phone(tester);
    final repo = FakeRepository();
    final container = testContainer(repo);
    addTearDown(container.dispose);
    await tester.pumpWidget(testApp(repo, container: container));
    await tester.pumpAndSettle();

    container.read(routerProvider).push(AppRoutes.logFor(testToday));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Calm'));
    await tester.tap(find.text('Calm'));
    await tester.pump();
    await tester.ensureVisible(find.text('Cramps'));
    await tester.tap(find.text('Cramps'));
    await tester.pump();
    await tester.ensureVisible(find.text('Save Entry'));
    await tester.tap(find.text('Save Entry'));
    await tester.pumpAndSettle();

    final saved = repo.logs[testToday];
    expect(saved, isNotNull);
    expect(saved!.symptoms, [Symptom.cramps]);
    expect(saved.moods, [Mood.calm]);
  });

  testWidgets('insights show suggestions, trends and patterns',
      (tester) async {
    _phone(tester);
    final starts = [
      DateTime.utc(2026, 7, 1),
      DateTime.utc(2026, 7, 29),
      DateTime.utc(2026, 8, 28),
      DateTime.utc(2026, 9, 25),
      DateTime.utc(2026, 10, 24),
    ];
    final repo = FakeRepository(periods: [
      for (var i = 0; i < starts.length; i++)
        Period(
          id: 'p$i',
          start: starts[i],
          end: starts[i].add(const Duration(days: 4)),
        ),
    ]);
    for (final s in starts) {
      final d = s.add(const Duration(days: 1));
      repo.logs[d] = DailyLog(
        id: 'l${d.day}${d.month}',
        date: d,
        flow: FlowLevel.heavy,
        symptoms: const [Symptom.cramps],
      );
    }
    await tester.pumpWidget(testApp(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Insights').last);
    await tester.pumpAndSettle();
    expect(find.text('Suggestions for you'), findsOneWidget);
    expect(find.textContaining('Cramps tends to show up'), findsOneWidget);

    await tester.tap(find.text('Trends'));
    await tester.pumpAndSettle();
    expect(find.text('Cycle length'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Flow by period day'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Flow by period day'), findsOneWidget);
    // Back to the top so the tab bar is fully on screen.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 5000));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Patterns'));
    await tester.pumpAndSettle();
    expect(find.text('Symptoms through your cycle', skipOffstage: false),
        findsOneWidget);
  });

  testWidgets('a PIN locks the app until it is entered', (tester) async {
    _phone(tester);
    final repo = FakeRepository();
    final container = testContainer(repo, prefs: {
      'lock_pin_salt': 'salt',
      'lock_pin_hash': hashPin('2468', 'salt'),
      'lock_pin_length': 4,
    });
    addTearDown(container.dispose);
    await tester.pumpWidget(testApp(repo, container: container));
    await tester.pumpAndSettle();

    expect(find.text('Enter your PIN'), findsOneWidget);
    for (final d in ['1', '1', '1', '1']) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('That PIN is not right.'), findsOneWidget);

    for (final d in ['2', '4', '6', '8']) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('Enter your PIN'), findsNothing);
  });

  testWidgets('postpartum pauses estimates', (tester) async {
    _phone(tester);
    final repo = FakeRepository(
      profile: const Profile(
        id: 'u1',
        onboardingCompleted: true,
        typicalCycleLength: 28,
        lifeStage: LifeStage.postpartum,
      ),
      periods: [
        Period(
          id: 'p1',
          start: DateTime.utc(2026, 11, 1),
          end: DateTime.utc(2026, 11, 5),
        ),
      ],
    );
    await tester.pumpWidget(testApp(repo));
    await tester.pumpAndSettle();
    expect(find.text('Taking a break'), findsOneWidget);
    expect(find.text('21 days'), findsNothing);
  });

  testWidgets('wide screens use a side rail', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(testApp(FakeRepository()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
