import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers.dart';
import '../core/widgets/app_shell.dart';
import '../core/widgets/common.dart';
import '../domain/dates.dart';
import '../features/auth/auth_screens.dart';
import '../features/calendar/calendar_screen.dart';
import '../features/dashboard/home_screen.dart';
import '../features/history/history_screen.dart';
import '../features/insights/insights_screen.dart';
import '../features/logging/log_day_screen.dart';
import '../features/logging/period_editor_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/reminders/notifications_screen.dart';
import '../features/settings/health_and_lock_screens.dart';
import '../features/settings/info_screens.dart';
import '../features/settings/settings_screens.dart';
import '../features/welcome/install_screen.dart';
import '../features/welcome/welcome_screen.dart';

class AppRoutes {
  const AppRoutes._();

  static const splash = '/splash';
  static const welcome = '/welcome';
  static const signIn = '/sign-in';
  static const signUp = '/sign-up';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';
  static const onboarding = '/onboarding';
  static const install = '/install';
  static const privacy = '/privacy';
  static const disclaimer = '/disclaimer';

  static const home = '/home';
  static const calendar = '/calendar';
  static const insights = '/insights';
  static const more = '/more';

  static const log = '/log';
  static const periodNew = '/period/new';
  static const history = '/history';
  static const profile = '/settings/profile';
  static const cycleSettings = '/settings/cycle';
  static const notifications = '/settings/notifications';
  static const privacySettings = '/settings/privacy';
  static const about = '/about';
  static const healthProfile = '/settings/health';
  static const appLock = '/settings/lock';

  static String periodEdit(String id) => '/period/$id';
  static String logFor(DateTime day) => '$log?date=${toDbDate(day)}';
  static String newPeriodFrom(DateTime day) =>
      '$periodNew?start=${toDbDate(day)}';
}

/// Open to everyone, signed in or not.
const _openRoutes = {
  AppRoutes.install,
  AppRoutes.privacy,
  AppRoutes.disclaimer,
};

/// Only for signed-out users.
const _signedOutRoutes = {
  AppRoutes.welcome,
  AppRoutes.signIn,
  AppRoutes.signUp,
  AppRoutes.forgotPassword,
};

class _RouterRefresh extends ChangeNotifier {
  void ping() => notifyListeners();
}

final _rootKey = GlobalKey<NavigatorState>();

DateTime? _dateParam(GoRouterState s, String name) {
  final v = s.uri.queryParameters[name];
  if (v == null) return null;
  try {
    return parseDbDate(v);
  } catch (_) {
    return null;
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh();
  ref.listen(authProvider, (previous, next) => refresh.ping());
  ref.listen(profileProvider, (previous, next) => refresh.ping());
  ref.onDispose(refresh.dispose);

  String? redirect(BuildContext context, GoRouterState state) {
    final loc = state.matchedLocation;
    if (_openRoutes.contains(loc)) return null;

    final auth = ref.read(authProvider);
    if (!auth.hasValue) return loc == AppRoutes.splash ? null : AppRoutes.splash;
    final snap = auth.value!;

    if (!snap.signedIn) {
      return _signedOutRoutes.contains(loc) ? null : AppRoutes.welcome;
    }
    if (snap.recovering) {
      return loc == AppRoutes.resetPassword ? null : AppRoutes.resetPassword;
    }

    final profile = ref.read(profileProvider);
    final waiting = !profile.hasError &&
        (!profile.hasValue || (profile.isLoading && profile.value == null));
    if (waiting) {
      return loc == AppRoutes.splash ? null : AppRoutes.splash;
    }
    // If the profile can't load (offline), let the app show its own errors.
    final onboarded = profile.value?.onboardingCompleted ?? profile.hasError;
    if (!onboarded) {
      return loc == AppRoutes.onboarding ? null : AppRoutes.onboarding;
    }
    if (_signedOutRoutes.contains(loc) ||
        loc == AppRoutes.splash ||
        loc == AppRoutes.onboarding ||
        loc == AppRoutes.resetPassword) {
      return AppRoutes.home;
    }
    return null;
  }

  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: AppRoutes.home,
    refreshListenable: refresh,
    redirect: redirect,
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) => AppRoutes.home,
      ),
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const _SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: AppRoutes.signUp,
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (context, state) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.install,
        builder: (context, state) => const InstallScreen(),
      ),
      GoRoute(
        path: AppRoutes.privacy,
        builder: (context, state) => const PrivacyNoticeScreen(),
      ),
      GoRoute(
        path: AppRoutes.disclaimer,
        builder: (context, state) => const DisclaimerScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.home,
              builder: (context, state) => const HomeScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.calendar,
              builder: (context, state) => const CalendarScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.insights,
              builder: (context, state) => const InsightsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.more,
              builder: (context, state) => const SettingsScreen(),
            ),
          ]),
        ],
      ),
      GoRoute(
        path: AppRoutes.log,
        parentNavigatorKey: _rootKey,
        builder: (context, state) =>
            LogDayScreen(date: _dateParam(state, 'date')),
      ),
      GoRoute(
        path: AppRoutes.periodNew,
        parentNavigatorKey: _rootKey,
        builder: (context, state) =>
            PeriodEditorScreen(initialStart: _dateParam(state, 'start')),
      ),
      GoRoute(
        path: '/period/:id',
        parentNavigatorKey: _rootKey,
        builder: (context, state) =>
            PeriodEditorScreen(periodId: state.pathParameters['id']),
      ),
      GoRoute(
        path: AppRoutes.history,
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(
        path: AppRoutes.profile,
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const ProfileSettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.cycleSettings,
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const CycleSettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.privacySettings,
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const PrivacySettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.about,
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const AboutScreen(),
      ),
      GoRoute(
        path: AppRoutes.healthProfile,
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const HealthProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.appLock,
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const AppLockScreen(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const GradientScaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLogo(size: 96),
            SizedBox(height: 24),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }
}
