import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/constants/app_text.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/inputs.dart';
import '../../data/repositories/cycle_repository.dart';
import '../../data/services/notification_service.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';
import '../settings/health_and_lock_screens.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _steps = 5;
  int _step = 0;
  bool _saving = false;

  final _name = TextEditingController();
  DateTime? _lastStart;
  bool _stillGoing = false;
  DateTime? _lastEnd;
  int? _cycleLength = 28;
  bool _cycleUnknown = true;
  int? _periodLength = 5;
  bool _periodUnknown = true;
  bool _periodReminder = false;
  bool _dailyReminder = false;
  LifeStage _stage = LifeStage.cycling;
  Contraception? _method;

  /// Set once the first period is saved, so a retry never saves it twice.
  bool _periodSaved = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    final repo = ref.read(repositoryProvider);
    try {
      if (_lastStart != null && !_periodSaved) {
        try {
          await repo.savePeriod(
            start: _lastStart!,
            end: _stillGoing ? null : _lastEnd,
          );
        } on PeriodOverlapException {
          // Already saved by an earlier attempt.
        }
        _periodSaved = true;
      }
      final prefs = ReminderPrefs(
        periodReminderEnabled: _periodReminder && !_stage.paused,
        dailyReminderEnabled: _dailyReminder,
      );
      await repo.saveReminders(prefs);
      if ((_periodReminder || _dailyReminder) && NotificationService.supported) {
        await ref.read(notificationServiceProvider).requestPermission();
      }
      await repo.updateProfile({
        'display_name': _name.text.trim().isEmpty ? null : _name.text.trim(),
        'average_cycle_length': _cycleUnknown ? null : _cycleLength,
        'average_period_length': _periodUnknown ? null : _periodLength,
        'life_stage': _stage.db,
        'contraception': _method?.db,
        // Consent was given at sign-up; record when it took effect.
        'health_consent_at': DateTime.now().toUtc().toIso8601String(),
        'onboarding_completed': true,
      });
      ref.invalidate(periodsProvider);
      ref.invalidate(remindersProvider);
      ref.invalidate(profileProvider); // router moves on to Home
    } on PeriodOverlapException {
      if (mounted) {
        showMessage(context, 'That period overlaps one you already logged.');
      }
    } on AppException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _next() {
    if (_step < _steps - 1) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final pages = [
      _nameStep(context),
      _aboutYouStep(context),
      _lastPeriodStep(context, today),
      _lengthsStep(context),
      _remindersStep(context),
    ];
    return GradientScaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: _step == 0
                            ? null
                            : () => setState(() => _step--),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      Expanded(
                        child: Semantics(
                          label: 'Step ${_step + 1} of $_steps',
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: (_step + 1) / _steps,
                              minHeight: 8,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                    child: pages[_step],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: GradientButton(
                          label: _step == _steps - 1 ? 'Finish' : 'Continue',
                          trailingIcon: _step == _steps - 1
                              ? null
                              : Icons.arrow_forward,
                          loading: _saving,
                          onPressed: _next,
                        ),
                      ),
                      if (_step < _steps - 1)
                        TextButton(
                          onPressed: _saving ? null : _next,
                          child: const Text('Skip for now'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: context.text.headlineSmall),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: context.text.bodyMedium?.copyWith(color: context.cycle.muted),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _nameStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Center(child: AppLogo(size: 88)),
        const SizedBox(height: 24),
        _header(context, 'Welcome to CycleSync',
            "Let's set things up. Everything here is optional and can be changed later."),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'What should we call you? (optional)',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 20),
        const NoticeCard(
          icon: Icons.health_and_safety_outlined,
          text: AppText.estimatesShort,
        ),
      ],
    );
  }

  Widget _aboutYouStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, 'About you',
            'Optional. This avoids wrong estimates and unhelpful notes.'),
        Text('Right now I am…', style: context.text.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in LifeStage.values)
              ChoiceChip(
                label: Text(s.description),
                selected: _stage == s,
                onSelected: (_) => setState(() => _stage = s),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text('Contraception', style: context.text.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in Contraception.values)
              ChoiceChip(
                label: Text(c.label),
                selected: _method == c,
                onSelected: (_) => setState(() => _method = c),
              ),
            ChoiceChip(
              label: const Text('Prefer not to say'),
              selected: _method == null,
              onSelected: (_) => setState(() => _method = null),
            ),
          ],
        ),
        const SizedBox(height: 16),
        NoticeCard(
          icon: Icons.info_outline,
          tint: context.cycle.softLavenderCard,
          text: _stage != LifeStage.cycling
              ? lifeStageEffect(_stage)
              : contraceptionEffect(_method),
        ),
      ],
    );
  }

  Widget _lastPeriodStep(BuildContext context, DateTime today) {
    final fmt = DateFormat('EEE, d MMM yyyy');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, 'Your most recent period',
            'When did it start? Skip this if you are not sure.'),
        DateField(
          label: 'First day of bleeding',
          value: _lastStart,
          firstDate: addDays(today, -365),
          lastDate: today,
          onChanged: (d) => setState(() {
            _lastStart = d;
            if (_lastEnd != null && d != null && _lastEnd!.isBefore(d)) {
              _lastEnd = null;
            }
          }),
        ),
        if (_lastStart != null) ...[
          const SizedBox(height: 16),
          SwitchListTile(
            value: _stillGoing,
            onChanged: (v) => setState(() => _stillGoing = v),
            title: const Text('My period is still going'),
            contentPadding: EdgeInsets.zero,
          ),
          if (!_stillGoing)
            DateField(
              label: 'Last day (optional)',
              value: _lastEnd,
              firstDate: _lastStart!,
              lastDate: today,
              onChanged: (d) => setState(() => _lastEnd = d),
            ),
          const SizedBox(height: 12),
          Text(
            _stillGoing
                ? 'Started ${fmt.format(_lastStart!)}. You can mark the end later.'
                : 'Started ${fmt.format(_lastStart!)}.',
            style: context.text.bodySmall?.copyWith(color: context.cycle.muted),
          ),
        ],
      ],
    );
  }

  Widget _lengthsStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, 'Your typical cycle',
            'Used for estimates until you have logged a few cycles. Choose "I don\'t know" if unsure.'),
        NumberStepper(
          label: 'Cycle length',
          unit: 'days',
          value: _cycleLength ?? 28,
          min: 15,
          max: 60,
          enabled: !_cycleUnknown,
          onChanged: (v) => setState(() => _cycleLength = v),
        ),
        CheckboxListTile(
          value: _cycleUnknown,
          onChanged: (v) => setState(() => _cycleUnknown = v ?? true),
          title: const Text("I don't know"),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 12),
        NumberStepper(
          label: 'Period length',
          unit: 'days',
          value: _periodLength ?? 5,
          min: 1,
          max: 15,
          enabled: !_periodUnknown,
          onChanged: (v) => setState(() => _periodLength = v),
        ),
        CheckboxListTile(
          value: _periodUnknown,
          onChanged: (v) => setState(() => _periodUnknown = v ?? true),
          title: const Text("I don't know"),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        Text(
          'Cycle length is counted from the first day of one period to the first day of the next.',
          style: context.text.bodySmall?.copyWith(color: context.cycle.muted),
        ),
      ],
    );
  }

  Widget _remindersStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, 'Reminders',
            'Optional. Notification text is neutral, so nothing private shows on your lock screen.'),
        SoftCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              SwitchListTile(
                value: _periodReminder,
                onChanged: (v) => setState(() => _periodReminder = v),
                secondary: const Icon(Icons.water_drop_outlined),
                title: const Text('Period expected soon'),
                subtitle: const Text('2 days before your estimated start'),
              ),
              SwitchListTile(
                value: _dailyReminder,
                onChanged: (v) => setState(() => _dailyReminder = v),
                secondary: const Icon(Icons.edit_note),
                title: const Text('Daily check-in'),
                subtitle: const Text('Every day at 20:00'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        NoticeCard(
          icon: Icons.info_outline,
          tint: context.cycle.softLavenderCard,
          text: kIsWeb
              ? 'In the web app, reminders appear when you open CycleSync. '
                  'Phone notifications need the Android app.'
              : 'You can change times and options later in Settings.',
        ),
        const SizedBox(height: 12),
        Text(
          'You can change all of this later in More → Settings.',
          style: context.text.bodySmall?.copyWith(color: AppTheme.plum),
        ),
      ],
    );
  }
}
