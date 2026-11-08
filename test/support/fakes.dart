import 'dart:async';

import 'package:cyclesync/app.dart';
import 'package:cyclesync/core/platform/push_types.dart';
import 'package:cyclesync/core/providers.dart';
import 'package:cyclesync/data/repositories/cycle_repository.dart';
import 'package:cyclesync/data/services/notification_service.dart';
import 'package:cyclesync/domain/models.dart';
import 'package:cyclesync/domain/reminder_planner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for Supabase.
class FakeRepository implements CycleRepository {
  FakeRepository({
    this.signedIn = true,
    this.profile = const Profile(id: 'u1', onboardingCompleted: true),
    List<Period>? periods,
  }) : periods = periods ?? [];

  bool signedIn;
  Profile profile;
  final List<Period> periods;
  int savePeriodCalls = 0;
  int failProfileUpdates = 0;
  final Map<DateTime, DailyLog> logs = {};
  ReminderPrefs reminders = const ReminderPrefs();
  final _auth = StreamController<AuthSnapshot>.broadcast();

  AuthSnapshot get _snap => signedIn
      ? const AuthSnapshot(userId: 'u1', email: 'test@example.com')
      : const AuthSnapshot();

  @override
  AuthSnapshot currentAuth() => _snap;

  @override
  Stream<AuthSnapshot> authChanges() async* {
    yield _snap;
    yield* _auth.stream;
  }

  @override
  Future<bool> signUp(String email, String password) async => false;

  @override
  Future<void> signIn(String email, String password) async {
    signedIn = true;
    _auth.add(_snap);
  }

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> updatePassword(String password) async {}

  @override
  Future<void> signOut() async {
    signedIn = false;
    _auth.add(_snap);
  }

  @override
  Future<void> deleteAccount() => signOut();

  @override
  Future<Profile?> fetchProfile() async => profile;

  @override
  Future<void> updateProfile(Map<String, dynamic> values) async {
    if (failProfileUpdates > 0) {
      failProfileUpdates--;
      throw const AppException('Network error');
    }
    profile = Profile(
      id: profile.id,
      displayName: values.containsKey('display_name')
          ? values['display_name'] as String?
          : profile.displayName,
      typicalCycleLength: values.containsKey('average_cycle_length')
          ? values['average_cycle_length'] as int?
          : profile.typicalCycleLength,
      typicalPeriodLength: values.containsKey('average_period_length')
          ? values['average_period_length'] as int?
          : profile.typicalPeriodLength,
      onboardingCompleted:
          values['onboarding_completed'] as bool? ?? profile.onboardingCompleted,
      showFertileWindow:
          values['show_fertile_window'] as bool? ?? profile.showFertileWindow,
      contraception: values.containsKey('contraception')
          ? Contraception.fromDb(values['contraception'] as String?)
          : profile.contraception,
      lifeStage: values.containsKey('life_stage')
          ? LifeStage.fromDb(values['life_stage'] as String?)
          : profile.lifeStage,
      healthConsentAt: values.containsKey('health_consent_at')
          ? DateTime.tryParse(values['health_consent_at'] as String)
          : profile.healthConsentAt,
    );
  }

  @override
  Future<List<Period>> fetchPeriods() async =>
      [...periods]..sort((a, b) => b.start.compareTo(a.start));

  @override
  Future<void> savePeriod({
    String? id,
    required DateTime start,
    DateTime? end,
    String? notes,
  }) async {
    periods.removeWhere((p) => p.id == id);
    periods.add(Period(
      id: id ?? 'p${periods.length + 1}',
      start: start,
      end: end,
      notes: notes,
    ));
    savePeriodCalls++;
  }

  @override
  Future<void> deletePeriod(String id) async =>
      periods.removeWhere((p) => p.id == id);

  @override
  Future<void> setGapIsCycle(String id, bool? value) async {
    final i = periods.indexWhere((p) => p.id == id);
    if (i < 0) return;
    final p = periods[i];
    periods[i] = Period(
        id: p.id, start: p.start, end: p.end, notes: p.notes, gapIsCycle: value);
  }

  @override
  Future<List<DailyLog>> fetchLogs() async => logs.values.toList();

  @override
  Future<void> saveLog(DailyLog log) async => logs[log.date] = DailyLog(
        id: log.id ?? 'l${logs.length + 1}',
        date: log.date,
        flow: log.flow,
        symptoms: log.symptoms,
        moods: log.moods,
        notes: log.notes,
        pain: log.pain,
        painDisrupted: log.painDisrupted,
        heavySoaked: log.heavySoaked,
      );

  @override
  Future<void> deleteLog(String id) async =>
      logs.removeWhere((_, l) => l.id == id);

  @override
  Future<ReminderPrefs> fetchReminders() async => reminders;

  @override
  Future<void> saveReminders(ReminderPrefs prefs) async => reminders = prefs;

  final List<PlannedReminder> scheduledPushes = [];
  final List<WebPushSubscriptionData> pushSubs = [];

  @override
  Future<String> fetchPushPublicKey() async => 'test-key';

  @override
  Future<void> savePushSubscription(WebPushSubscriptionData sub) async =>
      pushSubs.add(sub);

  @override
  Future<void> deletePushSubscription(String endpoint) async =>
      pushSubs.removeWhere((s) => s.endpoint == endpoint);

  @override
  Future<void> replaceScheduledPushes(List<PlannedReminder> reminders) async {
    scheduledPushes
      ..clear()
      ..addAll(reminders);
  }
}

class FakeNotificationService extends NotificationService {
  List<PlannedReminder> applied = [];

  @override
  Future<void> apply(List<PlannedReminder> reminders) async =>
      applied = reminders;

  @override
  Future<void> cancelAll() async => applied = [];

  @override
  Future<bool> requestPermission() async => true;
}

final testToday = DateTime.utc(2026, 11, 8);

/// The whole app wired to fakes.
Widget testApp(FakeRepository repo, {ProviderContainer? container}) {
  return UncontrolledProviderScope(
    container: container ?? testContainer(repo),
    child: const CycleSyncApp(),
  );
}

ProviderContainer testContainer(FakeRepository repo,
    {Map<String, Object> prefs = const {}}) {
  SharedPreferences.setMockInitialValues(prefs);
  return _container(repo);
}

ProviderContainer _container(FakeRepository repo) => ProviderContainer(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        notificationServiceProvider
            .overrideWithValue(FakeNotificationService()),
        todayProvider.overrideWithValue(testToday),
      ],
    );
