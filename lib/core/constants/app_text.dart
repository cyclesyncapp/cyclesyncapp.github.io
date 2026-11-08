import 'package:flutter/foundation.dart';

/// Fixed user-facing text. Have legal wording reviewed before launch.
class AppText {
  const AppText._();

  static const String appName = 'CycleSync';
  static const String tagline = 'Know your cycle,\ncare for yourself';

  /// Public contact for privacy and security concerns. Set before launch.
  static const String supportEmail =
      String.fromEnvironment('SUPPORT_EMAIL');

  static const String healthDisclaimer =
      'CycleSync is a period and cycle tracking tool. Its dates and insights '
      'are estimates based on information you enter and are not medical '
      'advice. CycleSync cannot diagnose a health condition, confirm '
      'ovulation, or prevent pregnancy. Menstrual cycles can vary. If you '
      'have concerns about your cycle, symptoms or health, speak with a '
      'qualified healthcare professional.';

  static const List<(String, String)> helplines = [
    ('SADAG Suicide Crisis Helpline (24 hours, free)', '0800 567 567'),
    ('Cipla Mental Health Helpline (24 hours, free)', '0800 456 789'),
    ('GBV Command Centre (24 hours, free)', '0800 428 428'),
    ('GBV Command Centre "please call me"', '*120*7867#'),
  ];

  static const String healthConsentLabel =
      'I agree that CycleSync may store my period and health information '
      'to run the app';

  static const String estimatesShort =
      'Predictions are estimates and can change as you log more.';

  static const String fertileWarning =
      'Fertile-window and ovulation dates are rough calendar estimates. They '
      'cannot confirm ovulation and must not be used as contraception or to '
      'decide that unprotected sex is safe.';

  static const List<(String, String)> howEstimatesWork = [
    (
      'Cycle length',
      'The number of days from the first day of one period to the first day '
          'of the next.',
    ),
    (
      'Next period',
      'Once you have logged at least 3 cycles, CycleSync uses your usual '
          'cycle length from your last 6 cycles (the middle one, so one odd '
          'month doesn\'t throw it off), and shows a likely range from your '
          'shortest and longest. Before that, it uses the typical length you '
          'entered, if any. It never assumes a default.',
    ),
    (
      'Unusual gaps',
      'Gaps shorter than 15 days are left out. For gaps longer than 60 days, '
          'CycleSync asks in Period History whether it was a real cycle or a '
          'missed log, and only counts it if you say it was real.',
    ),
    (
      'Period length',
      'Once you have logged 3 periods with end dates, CycleSync uses the '
          'median of your recent period lengths; before that, your setting.',
    ),
    (
      'Fertile window (optional)',
      'If you turn it on, and once you have logged 3 cycles, it is estimated '
          'as about a week ending a day after a date 14 days before your next '
          'estimated period. It is hidden on hormonal contraception. This is a '
          'calendar estimate only.',
    ),
  ];

  static String get privacyNotice => '''
CycleSync privacy notice (draft)

Who is responsible
CycleSync is run by its owner, who acts as the responsible party and Information Officer under South Africa's Protection of Personal Information Act (POPIA). Contact: ${supportEmail.isEmpty ? 'a contact address will be published here before launch' : supportEmail}.

What we collect
• Your email address and a securely hashed password, to run your account.
• What you choose to log: period dates, flow, pain, symptoms, mood and notes, and optional settings such as typical cycle length, display name, life stage, contraception method and reminder times.
• If you turn on web notifications: a technical address for your browser, so reminders can be delivered.

Some of this is "special personal information" about your health and sex life. We only process it with your explicit consent, which you give when creating your account and can withdraw at any time by deleting your account.

We do not collect your date of birth, location, contacts, photos or advertising identifiers, and we do not use analytics or advertising tools.

Why
Only to provide the tracking, estimates, reminders and export features you use. We never sell or share your information for advertising.

Where it is stored
Your data is stored with our database provider, Supabase, in a data centre in Europe. This is a transfer of personal information outside South Africa, made with your consent and to a provider bound to keep it secure. Each account's records are isolated by database security rules, and all connections use HTTPS.

Reminders
On Android, reminders are created on your phone. In the web app, only the time of each reminder is stored on our server so it can be sent; the text is always neutral ("You have a CycleSync reminder"), so nothing private shows on your screen or is stored with it.

App lock
If you set a PIN, it is stored only on your device, never on our servers.

How long we keep it
Until you delete it or delete your account. Deleting your account removes your login and every record immediately. We do not currently keep separate backups; if that changes, deleted data will expire from backups within 30 days and this notice will say so.

Your rights
You can view and correct your records at any time, export them (CSV, or a PDF summary for a doctor), and permanently delete your account and all records in Settings → Privacy, Export & Delete. You may object to processing, and you may complain to the Information Regulator (South Africa), inforeg.org.za.

Requests from authorities
We only disclose information when legally required to, and will tell you about a request unless the law forbids it.

Age
CycleSync is intended for adults (18+).

This notice is a draft and will be reviewed before public launch.
''';

  /// Shown in About. Set by the build.
  static String get buildMode => kReleaseMode ? 'Release' : 'Debug';
}

/// Links used across the app.
class AppLinks {
  const AppLinks._();

  /// Public address of the web app, set by the build workflow.
  static const String webAppUrl = String.fromEnvironment(
    'WEB_APP_URL',
    defaultValue: 'https://cyclesyncapp.github.io/',
  );

  /// Where Supabase sends people back to from Android emails.
  static const String androidAuthCallback =
      'io.github.ebrahimomar0729.cyclesync://login-callback';

  /// Where sign-up and password-reset emails should send the user back to.
  static String authRedirect() {
    if (kIsWeb) {
      final base = Uri.base;
      return '${base.origin}${base.path}';
    }
    return androidAuthCallback;
  }

  static String shareMessage() =>
      'Track your cycle privately with CycleSync: $webAppUrl';
}
