import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/lock/app_lock.dart';
import 'core/platform/platform_actions.dart';
import 'core/widgets/config_error_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final problems = AppConfig.problems(
    AppConfig.supabaseUrl,
    AppConfig.supabaseAnonKey,
  );
  if (problems.isNotEmpty) {
    runApp(ConfigErrorApp(problems: problems));
    return;
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl.trim(),
    // Accepts the publishable key or the legacy anon key; both are public.
    publishableKey: AppConfig.supabaseAnonKey.trim(),
  );

  // "Sign me out when I close the app" (web): a new browser session means
  // the app was closed, so end the stored login.
  if (kIsWeb) {
    try {
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getBool(signOutOnCloseKey) ?? false) && !hasTabSession()) {
        await Supabase.instance.client.auth.signOut();
      }
    } catch (_) {
      // Never block start-up on this.
    }
  }

  runApp(const ProviderScope(child: CycleSyncApp()));
}
