# CycleSync

Private period and cycle tracker. Flutter (Android + web/PWA) with Supabase.

> CycleSync's dates and insights are estimates, not medical advice. It cannot
> diagnose a condition, confirm ovulation, or prevent pregnancy.

## Status

| Phase | What | State |
| --- | --- | --- |
| 1 | Foundation, CI | Done |
| 2–5 | All screens, logging, insights, reminders, export, delete account | Done |
| 6 | Web push, Add to Home Screen, design and logo | Done |
| 7 | Review fixes: app lock, health profile (life stage, contraception), pain and heavy-bleeding detail, doctor PDF, long-cycle handling, safer server reminders, offline caching | Done (beta) |
| 8 | Legal review (POPIA), signed APK, translations | Next |

## Live app

Web: https://cyclesyncapp.github.io/ (deployed by GitHub Actions)

APK: open the latest successful **Build Android APK** run under the **Actions**
tab and download the `cyclesync-release-apk` artifact.

## Run it on your computer (VS Code terminal)

Prerequisites: Flutter stable, Android Studio (for the Android SDK), Git.

```bash
git clone https://github.com/cyclesyncapp/cyclesyncapp.github.io.git cyclesync
cd cyclesync
flutter pub get

# Web (Chrome), port 3000 matches the Supabase redirect URL
flutter run -d chrome --web-port 3000 \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_KEY

# Android phone or emulator
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_KEY

# Checks (CI runs the same)
flutter analyze
flutter test
```

Without the two `--dart-define` values the app shows a "not configured"
screen instead of starting. It also refuses to start if given a Supabase
**secret** or **service_role** key.

## Configuration and secrets

- GitHub → Settings → Secrets and variables → Actions holds
  `SUPABASE_URL` and `SUPABASE_ANON_KEY` (the publishable/anon key).
- Never put the Supabase secret/service_role key, database password,
  or signing keystore in this repository.
- The public key is safe in the app only because Row Level Security is on
  for every table (see `supabase/migrations/`).

## Project layout

```text
lib/
  main.dart                 config check + Supabase init
  app.dart                  MaterialApp, theme, router
  core/config/              build-time config validation
  core/constants/           fixed text (disclaimer)
  core/theme/               light/dark theme
  core/widgets/             app shell (nav), shared widgets
  core/providers.dart       Riverpod providers
  data/services/            Supabase-facing services
  features/<feature>/       screens per feature
  routing/                  go_router setup
supabase/migrations/        SQL, applied in order
test/unit, test/widget      tests
.github/workflows/          CI: APK build, web build + deploy
```

## Supabase setup order

Run these in the SQL Editor, in order, once each:

1. `20261108000000_initial_schema.sql`
2. `20261108120000_full_app.sql`
3. `20261108150000_web_push.sql` (replace `YOUR-PROJECT` first)
4. `20261108170000_release_a_b.sql`

Deploy `supabase/functions/send-reminders` with "Verify JWT" off.

## Database changes

Each change is a new file in `supabase/migrations/` named
`YYYYMMDDHHMMSS_description.sql`. Run it in the Supabase SQL Editor (dev
project first), then commit it. Never edit an applied migration.

## Adding packages

Use `flutter pub add <package>` so versions match the installed Flutter,
then commit both `pubspec.yaml` and `pubspec.lock`.

## Web push (web app reminders)

`supabase/functions/send-reminders` sends reminders that the app writes to
`scheduled_pushes`. A `pg_cron` job (migration 3) calls it every 5 minutes.
Deploy it with JWT verification off. Web-push keys are created by the
function on first use and kept in `push_config`, which only the server can read.
