import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repositories/cycle_repository.dart';
import '../data/services/notification_service.dart';
import '../domain/cycle_calculator.dart';
import '../domain/dates.dart';
import '../domain/models.dart';
import '../domain/reminder_planner.dart';
import 'constants/app_text.dart';
import 'platform/platform_actions.dart';

/// Data access. Overridden with a fake in tests.
final repositoryProvider = Provider<CycleRepository>((ref) {
  return SupabaseCycleRepository(
    Supabase.instance.client,
    redirectUrl: AppLinks.authRedirect,
  );
});

final notificationServiceProvider =
    Provider<NotificationService>((ref) => NotificationService());

/// Today's date on this device. Overridden in tests.
final todayProvider = Provider<DateTime>((ref) => todayDate());

/// Who is signed in; updates on sign-in, sign-out and password recovery.
final authProvider = StreamProvider<AuthSnapshot>((ref) {
  return ref.watch(repositoryProvider).authChanges();
});

String? _userId(Ref ref) => ref.watch(authProvider).value?.userId;

final profileProvider = FutureProvider<Profile?>((ref) async {
  if (_userId(ref) == null) return null;
  return ref.watch(repositoryProvider).fetchProfile();
});

final periodsProvider = FutureProvider<List<Period>>((ref) async {
  if (_userId(ref) == null) return const [];
  return ref.watch(repositoryProvider).fetchPeriods();
});

final logsProvider = FutureProvider<List<DailyLog>>((ref) async {
  if (_userId(ref) == null) return const [];
  return ref.watch(repositoryProvider).fetchLogs();
});

final remindersProvider = FutureProvider<ReminderPrefs>((ref) async {
  if (_userId(ref) == null) return const ReminderPrefs();
  return ref.watch(repositoryProvider).fetchReminders();
});

/// All estimates, recalculated whenever periods or settings change.
final summaryProvider = FutureProvider<CycleSummary>((ref) async {
  final periods = await ref.watch(periodsProvider.future);
  final profile = await ref.watch(profileProvider.future);
  return CycleCalculator.summarize(
    periods: periods,
    today: ref.watch(todayProvider),
    typicalCycleLength: profile?.typicalCycleLength,
    typicalPeriodLength: profile?.typicalPeriodLength,
    includeFertileWindow: (profile?.showFertileWindow ?? false) &&
        (profile?.fertileWindowAllowed ?? true),
    pausePredictions: profile?.lifeStage.paused ?? false,
  );
});

/// Logs keyed by date for quick lookup.
final logsByDateProvider = FutureProvider<Map<DateTime, DailyLog>>((ref) async {
  final logs = await ref.watch(logsProvider.future);
  return {for (final l in logs) l.date: l};
});

/// Keeps reminders in step with the latest data and settings:
/// Android schedules local notifications; the web app schedules web pushes.
final reminderSyncProvider = FutureProvider<void>((ref) async {
  if (_userId(ref) == null) return;
  if (!kIsWeb && !NotificationService.supported) return;
  final prefs = await ref.watch(remindersProvider.future);
  final summary = await ref.watch(summaryProvider.future);
  final planned = prefs.anyEnabled
      ? ReminderPlanner.plan(prefs: prefs, summary: summary, now: DateTime.now())
      : const <PlannedReminder>[];
  if (kIsWeb) {
    try {
      // Only keep server reminders while this browser has notifications on.
      final subscribed = await currentWebPushEndpoint() != null;
      await ref
          .read(repositoryProvider)
          .replaceScheduledPushes(subscribed ? planned : const []);
    } catch (_) {
      // Web push tables not set up yet; in-app reminders still work.
    }
    return;
  }
  await ref.watch(notificationServiceProvider).apply(planned);
});

/// Call after any change to periods or logs.
void refreshCycleData(WidgetRef ref) {
  ref.invalidate(periodsProvider);
  ref.invalidate(logsProvider);
}

/// Local, non-sensitive device preferences.
final devicePrefsProvider = FutureProvider<SharedPreferences>(
  (ref) => SharedPreferences.getInstance(),
);

const installTipDismissedKey = 'install_tip_dismissed';
