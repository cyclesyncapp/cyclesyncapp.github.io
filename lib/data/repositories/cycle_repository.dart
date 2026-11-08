import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/platform/push_types.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';
import '../../domain/reminder_planner.dart';

/// Thrown when a period would overlap another recorded period.
class PeriodOverlapException implements Exception {
  const PeriodOverlapException();
}

/// User-facing failure. [message] is safe to show.
class AppException implements Exception {
  const AppException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// True when an error means the app is newer than the database
/// (a migration has not been run yet).
bool isSchemaOutOfDate(String? code, String message) {
  const codes = {'PGRST204', 'PGRST202', 'PGRST205', '42703', '42883', '42P01'};
  if (code != null && codes.contains(code)) return true;
  final m = message.toLowerCase();
  return m.contains('schema cache') ||
      (m.contains('column') && m.contains('does not exist'));
}

/// Snapshot of who is signed in.
class AuthSnapshot {
  const AuthSnapshot({this.userId, this.email, this.recovering = false});

  final String? userId;
  final String? email;

  /// True after opening a password-reset link, until a new password is set.
  final bool recovering;

  bool get signedIn => userId != null;
}

/// Everything the app reads or writes. Swapped for a fake in tests.
abstract class CycleRepository {
  Stream<AuthSnapshot> authChanges();
  AuthSnapshot currentAuth();

  /// Returns true when a session started straight away (no email check).
  Future<bool> signUp(String email, String password);
  Future<void> signIn(String email, String password);
  Future<void> sendPasswordReset(String email);
  Future<void> updatePassword(String password);
  Future<void> signOut();
  Future<void> deleteAccount();

  Future<Profile?> fetchProfile();
  Future<void> updateProfile(Map<String, dynamic> values);

  Future<List<Period>> fetchPeriods();
  Future<void> savePeriod({
    String? id,
    required DateTime start,
    DateTime? end,
    String? notes,
  });
  Future<void> deletePeriod(String id);

  /// Answer for an unusually long gap before period [id]:
  /// true = real cycle, false = missed logging, null = unanswered.
  Future<void> setGapIsCycle(String id, bool? value);

  Future<List<DailyLog>> fetchLogs();
  Future<void> saveLog(DailyLog log);
  Future<void> deleteLog(String id);

  Future<ReminderPrefs> fetchReminders();
  Future<void> saveReminders(ReminderPrefs prefs);

  /// Web push (web app only).
  Future<String> fetchPushPublicKey();
  Future<void> savePushSubscription(WebPushSubscriptionData sub);
  Future<void> deletePushSubscription(String endpoint);
  Future<void> replaceScheduledPushes(List<PlannedReminder> reminders);
}

class SupabaseCycleRepository implements CycleRepository {
  SupabaseCycleRepository(this._client, {required this.redirectUrl});

  final SupabaseClient _client;
  final String Function() redirectUrl;

  GoTrueClient get _auth => _client.auth;

  String get _uid {
    final id = _auth.currentUser?.id;
    if (id == null) throw const AppException('Please sign in again.');
    return id;
  }

  // ---------------- Auth ----------------

  @override
  AuthSnapshot currentAuth() => AuthSnapshot(
        userId: _auth.currentUser?.id,
        email: _auth.currentUser?.email,
      );

  @override
  Stream<AuthSnapshot> authChanges() async* {
    var recovering = false;
    yield currentAuth();
    await for (final state in _auth.onAuthStateChange) {
      switch (state.event) {
        case AuthChangeEvent.passwordRecovery:
          recovering = true;
        case AuthChangeEvent.userUpdated:
        case AuthChangeEvent.signedOut:
          recovering = false;
        default:
          break;
      }
      final user = state.session?.user;
      yield AuthSnapshot(
        userId: user?.id,
        email: user?.email,
        recovering: recovering && user != null,
      );
    }
  }

  @override
  Future<bool> signUp(String email, String password) => _guardAuth(() async {
        final res = await _auth.signUp(
          email: email.trim(),
          password: password,
          emailRedirectTo: redirectUrl(),
        );
        return res.session != null;
      });

  @override
  Future<void> signIn(String email, String password) => _guardAuth(() async {
        await _auth.signInWithPassword(email: email.trim(), password: password);
      });

  @override
  Future<void> sendPasswordReset(String email) => _guardAuth(() async {
        await _auth.resetPasswordForEmail(
          email.trim(),
          redirectTo: redirectUrl(),
        );
      });

  @override
  Future<void> updatePassword(String password) => _guardAuth(() async {
        await _auth.updateUser(UserAttributes(password: password));
      });

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> deleteAccount() async {
    try {
      await _client.rpc('delete_my_account');
    } on PostgrestException {
      throw const AppException(
        "We couldn't delete your account right now. Please try again.",
      );
    }
    try {
      await _auth.signOut();
    } catch (_) {
      // The account is already gone; a failed sign-out only clears locally.
    }
  }

  Future<T> _guardAuth<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on AuthException catch (e) {
      throw AppException(_friendlyAuthMessage(e));
    } on AppException {
      rethrow;
    } catch (_) {
      throw const AppException(
        "We couldn't reach CycleSync. Check your connection and try again.",
      );
    }
  }

  /// Messages never confirm whether an email address has an account.
  static String _friendlyAuthMessage(AuthException e) {
    final code = (e.code ?? '').toLowerCase();
    final msg = e.message.toLowerCase();
    if (code.contains('weak_password') || msg.contains('password should')) {
      return 'Please choose a stronger password (at least 8 characters, '
          'mixing letters and numbers).';
    }
    if (code.contains('rate_limit') ||
        msg.contains('rate limit') ||
        e.statusCode == '429') {
      return 'Too many attempts. Please wait a few minutes and try again.';
    }
    if (code.contains('same_password')) {
      return 'Your new password must be different from the old one.';
    }
    if (code.contains('email_address_invalid') || msg.contains('invalid email')) {
      return 'Please enter a valid email address.';
    }
    if (code.contains('reauthentication') || code.contains('session')) {
      return 'Your session has expired. Please sign in again.';
    }
    return 'Email or password is incorrect, or your email is not confirmed yet.';
  }

  // ---------------- Data ----------------

  Future<T> _guardData<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      if (e.message.contains('period_overlap')) {
        throw const PeriodOverlapException();
      }
      if (isSchemaOutOfDate(e.code, e.message)) {
        throw const AppException(
          "CycleSync's database needs an update. Please ask the person who "
          'shared the app to run the latest database update, then try again.',
        );
      }
      throw const AppException(
        "Something went wrong saving your data. Please try again.",
      );
    } on AppException {
      rethrow;
    } on PeriodOverlapException {
      rethrow;
    } catch (_) {
      throw const AppException(
        "We couldn't reach CycleSync. Check your connection and try again.",
      );
    }
  }

  @override
  Future<Profile?> fetchProfile() => _guardData(() async {
        final row = await _client
            .from('profiles')
            .select()
            .eq('id', _uid)
            .maybeSingle();
        if (row != null) return Profile.fromRow(row);
        // Safety net if the sign-up trigger did not run.
        final created = await _client
            .from('profiles')
            .upsert({'id': _uid})
            .select()
            .single();
        return Profile.fromRow(created);
      });

  @override
  Future<void> updateProfile(Map<String, dynamic> values) =>
      _guardData(() async {
        await _client.from('profiles').upsert({...values, 'id': _uid});
      });

  @override
  Future<List<Period>> fetchPeriods() => _guardData(() async {
        final rows = await _client
            .from('periods')
            .select('id, start_date, end_date, notes, gap_is_cycle')
            .eq('user_id', _uid)
            .order('start_date', ascending: false);
        return [for (final r in rows) Period.fromRow(r)];
      });

  @override
  Future<void> savePeriod({
    String? id,
    required DateTime start,
    DateTime? end,
    String? notes,
  }) =>
      _guardData(() async {
        final values = {
          'user_id': _uid,
          'start_date': toDbDate(start),
          'end_date': end == null ? null : toDbDate(end),
          'notes': (notes == null || notes.trim().isEmpty) ? null : notes.trim(),
        };
        if (id == null) {
          await _client.from('periods').insert(values);
        } else {
          await _client.from('periods').update(values).eq('id', id);
        }
      });

  @override
  Future<void> deletePeriod(String id) => _guardData(() async {
        await _client.from('periods').delete().eq('id', id);
      });

  @override
  Future<void> setGapIsCycle(String id, bool? value) => _guardData(() async {
        await _client
            .from('periods')
            .update({'gap_is_cycle': value}).eq('id', id);
      });

  @override
  Future<List<DailyLog>> fetchLogs() => _guardData(() async {
        final rows = await _client
            .from('daily_logs')
            .select(
                'id, log_date, flow, symptoms, mood, notes, pain, pain_disrupted, heavy_soaked')
            .eq('user_id', _uid)
            .order('log_date', ascending: false);
        return [for (final r in rows) DailyLog.fromRow(r)];
      });

  @override
  Future<void> saveLog(DailyLog log) => _guardData(() async {
        await _client.from('daily_logs').upsert(
          {...log.toRow(), 'user_id': _uid},
          onConflict: 'user_id,log_date',
        );
      });

  @override
  Future<void> deleteLog(String id) => _guardData(() async {
        await _client.from('daily_logs').delete().eq('id', id);
      });

  @override
  Future<ReminderPrefs> fetchReminders() => _guardData(() async {
        final row = await _client
            .from('reminder_preferences')
            .select()
            .eq('user_id', _uid)
            .maybeSingle();
        return row == null ? const ReminderPrefs() : ReminderPrefs.fromRow(row);
      });

  @override
  Future<void> saveReminders(ReminderPrefs prefs) => _guardData(() async {
        await _client.from('reminder_preferences').upsert(
          {...prefs.toRow(), 'user_id': _uid},
          onConflict: 'user_id',
        );
      });

  // ---------------- Web push ----------------

  @override
  Future<String> fetchPushPublicKey() async {
    try {
      final res = await _client.functions
          .invoke('send-reminders', method: HttpMethod.get);
      final data = res.data;
      final key = data is Map ? data['publicKey'] : null;
      if (key is String && key.isNotEmpty) return key;
    } catch (_) {
      // Falls through to the message below.
    }
    throw const AppException(
      "Notifications aren't set up on the server yet. Please try again later.",
    );
  }

  @override
  Future<void> savePushSubscription(WebPushSubscriptionData sub) =>
      _guardData(() async {
        await _client.from('push_subscriptions').upsert(
          {
            'user_id': _uid,
            'endpoint': sub.endpoint,
            'p256dh': sub.p256dh,
            'auth': sub.auth,
          },
          onConflict: 'user_id,endpoint',
        );
      });

  @override
  Future<void> deletePushSubscription(String endpoint) => _guardData(() async {
        await _client
            .from('push_subscriptions')
            .delete()
            .eq('user_id', _uid)
            .eq('endpoint', endpoint);
      });

  @override
  Future<void> replaceScheduledPushes(List<PlannedReminder> reminders) =>
      _guardData(() async {
        // Only times are sent; the server always stores neutral text.
        await _client.rpc('replace_my_scheduled_pushes', params: {
          'items': [
            for (final r in reminders)
              {
                'send_at': r.at.toUtc().toIso8601String(),
                'repeats_daily': r.repeatsDaily,
              },
          ],
        });
      });
}
