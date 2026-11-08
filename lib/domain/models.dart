import 'dates.dart';

/// Longest a period with no end date is treated as running (days).
/// Matches the database overlap guard.
const int openPeriodMaxDays = 14;

class Period {
  const Period({
    required this.id,
    required this.start,
    this.end,
    this.notes,
    this.gapIsCycle,
  });

  final String id;
  final DateTime start;
  final DateTime? end;
  final String? notes;

  /// The user's answer about an unusually long gap before this period:
  /// true = it was a real (long) cycle, false = logging was missed,
  /// null = not answered.
  final bool? gapIsCycle;

  /// Inclusive length in days, when the end date is recorded.
  int? get durationDays => end == null ? null : daysBetween(start, end!) + 1;

  /// True when no end date is recorded and the start is recent enough that
  /// the period may still be going.
  bool isOngoingOn(DateTime today) =>
      end == null &&
      !start.isAfter(today) &&
      daysBetween(start, today) < openPeriodMaxDays;

  /// Last day this record covers. Open records run to today, capped.
  DateTime effectiveEnd(DateTime today) {
    if (end != null) return end!;
    final cap = addDays(start, openPeriodMaxDays - 1);
    final runTo = today.isBefore(start) ? start : today;
    return runTo.isAfter(cap) ? cap : runTo;
  }

  bool covers(DateTime day, DateTime today) =>
      !day.isBefore(start) && !day.isAfter(effectiveEnd(today));

  factory Period.fromRow(Map<String, dynamic> row) => Period(
        id: row['id'] as String,
        start: parseDbDate(row['start_date'] as String),
        end: row['end_date'] == null
            ? null
            : parseDbDate(row['end_date'] as String),
        notes: row['notes'] as String?,
        gapIsCycle: row['gap_is_cycle'] as bool?,
      );
}

enum FlowLevel {
  none('none', 'None'),
  spotting('spotting', 'Spotting'),
  light('light', 'Light'),
  medium('medium', 'Medium'),
  heavy('heavy', 'Heavy');

  const FlowLevel(this.db, this.label);
  final String db;
  final String label;

  bool get isBleeding => this == light || this == medium || this == heavy;
  bool get anyBleeding => this != none;

  static FlowLevel fromDb(String? v) => FlowLevel.values
      .firstWhere((f) => f.db == v, orElse: () => FlowLevel.none);
}

enum Symptom {
  cramps('cramps', 'Cramps'),
  pelvicPain('pelvic_pain', 'Pelvic pain'),
  headache('headache', 'Headache'),
  bloating('bloating', 'Bloating'),
  acne('acne', 'Acne'),
  breastTenderness('breast_tenderness', 'Tender breasts'),
  fatigue('fatigue', 'Fatigue'),
  nausea('nausea', 'Nausea'),
  backPain('back_pain', 'Back pain'),
  hotFlushes('hot_flushes', 'Hot flushes', lifeStageOnly: true),
  nightSweats('night_sweats', 'Night sweats', lifeStageOnly: true),
  sleepProblems('sleep_problems', 'Sleep problems'),
  other('other', 'Other');

  const Symptom(this.db, this.label, {this.lifeStageOnly = false});
  final String db;
  final String label;

  /// Shown by default only in perimenopause (always shown if already logged).
  final bool lifeStageOnly;

  static Symptom? fromDb(String v) {
    for (final s in Symptom.values) {
      if (s.db == v) return s;
    }
    return null;
  }
}

enum Mood {
  happy('happy', 'Happy'),
  calm('calm', 'Calm'),
  neutral('neutral', 'Neutral'),
  anxious('anxious', 'Anxious'),
  sad('sad', 'Sad'),
  irritable('irritable', 'Irritable'),
  lowEnergy('low_energy', 'Low energy'),
  other('other', 'Other');

  const Mood(this.db, this.label);
  final String db;
  final String label;

  static Mood? fromDb(String v) {
    for (final m in Mood.values) {
      if (m.db == v) return m;
    }
    return null;
  }
}

/// Pain level 0–3.
const painLabels = ['None', 'Mild', 'Moderate', 'Severe'];

class DailyLog {
  const DailyLog({
    this.id,
    required this.date,
    this.flow = FlowLevel.none,
    this.symptoms = const [],
    this.moods = const [],
    this.notes,
    this.pain,
    this.painDisrupted = false,
    this.heavySoaked = false,
  });

  final String? id;
  final DateTime date;
  final FlowLevel flow;
  final List<Symptom> symptoms;
  final List<Mood> moods;
  final String? notes;

  /// 0 none … 3 severe; null when not recorded.
  final int? pain;

  /// Pain stopped normal daily activities.
  final bool painDisrupted;

  /// Soaked through protection within 1–2 hours or passed large clots.
  final bool heavySoaked;

  bool get isEmpty =>
      flow == FlowLevel.none &&
      symptoms.isEmpty &&
      moods.isEmpty &&
      (pain == null || pain == 0) &&
      !painDisrupted &&
      !heavySoaked &&
      (notes == null || notes!.trim().isEmpty);

  factory DailyLog.fromRow(Map<String, dynamic> row) => DailyLog(
        id: row['id'] as String?,
        date: parseDbDate(row['log_date'] as String),
        flow: FlowLevel.fromDb(row['flow'] as String?),
        symptoms: (row['symptoms'] as List? ?? const [])
            .whereType<String>()
            .map(Symptom.fromDb)
            .whereType<Symptom>()
            .toList(),
        moods: (row['mood'] as List? ?? const [])
            .whereType<String>()
            .map(Mood.fromDb)
            .whereType<Mood>()
            .toList(),
        notes: row['notes'] as String?,
        pain: (row['pain'] as num?)?.toInt(),
        painDisrupted: row['pain_disrupted'] as bool? ?? false,
        heavySoaked: row['heavy_soaked'] as bool? ?? false,
      );

  Map<String, dynamic> toRow() => {
        'log_date': toDbDate(date),
        'flow': flow.db,
        'symptoms': [for (final s in symptoms) s.db],
        'mood': [for (final m in moods) m.db],
        'notes': (notes == null || notes!.trim().isEmpty) ? null : notes!.trim(),
        'pain': pain,
        'pain_disrupted': painDisrupted,
        'heavy_soaked': heavySoaked,
      };
}

enum Contraception {
  none('none', 'None'),
  pill('pill', 'The pill'),
  injection('injection', 'Injection (e.g. Depo, Nur-Isterate)'),
  implant('implant', 'Implant'),
  hormonalIud('hormonal_iud', 'Hormonal IUD'),
  copperIud('copper_iud', 'Copper IUD'),
  other('other', 'Other');

  const Contraception(this.db, this.label);
  final String db;
  final String label;

  /// Methods that change bleeding patterns so natural-cycle estimates and
  /// some notes are unreliable.
  bool get hormonal =>
      this == pill || this == injection || this == implant || this == hormonalIud;

  /// Methods where little or no bleeding is common.
  bool get oftenNoBleeding =>
      this == injection || this == implant || this == hormonalIud;

  static Contraception? fromDb(String? v) {
    for (final c in Contraception.values) {
      if (c.db == v) return c;
    }
    return null;
  }
}

enum LifeStage {
  cycling('cycling', 'Regular tracking', 'Tracking my cycle'),
  pregnant('pregnant', 'Pregnant', 'Pregnant'),
  postpartum('postpartum', 'Postpartum', 'Recently gave birth'),
  breastfeeding('breastfeeding', 'Breastfeeding', 'Breastfeeding'),
  perimenopause('perimenopause', 'Perimenopause', 'Perimenopause');

  const LifeStage(this.db, this.label, this.description);
  final String db;
  final String label;
  final String description;

  /// Predictions and period reminders are paused.
  bool get paused => this == pregnant || this == postpartum || this == breastfeeding;

  static LifeStage fromDb(String? v) => LifeStage.values
      .firstWhere((s) => s.db == v, orElse: () => LifeStage.cycling);
}

class Profile {
  const Profile({
    required this.id,
    this.displayName,
    this.typicalCycleLength,
    this.typicalPeriodLength,
    this.onboardingCompleted = false,
    this.showFertileWindow = false,
    this.contraception,
    this.lifeStage = LifeStage.cycling,
    this.healthConsentAt,
  });

  final String id;
  final String? displayName;
  final int? typicalCycleLength;
  final int? typicalPeriodLength;
  final bool onboardingCompleted;
  final bool showFertileWindow;
  final Contraception? contraception;
  final LifeStage lifeStage;
  final DateTime? healthConsentAt;

  bool get hormonalContraception => contraception?.hormonal ?? false;

  /// The fertile window is meaningless on hormonal contraception or when
  /// predictions are paused.
  bool get fertileWindowAllowed => !hormonalContraception && !lifeStage.paused;

  factory Profile.fromRow(Map<String, dynamic> row) => Profile(
        id: row['id'] as String,
        displayName: row['display_name'] as String?,
        typicalCycleLength: (row['average_cycle_length'] as num?)?.toInt(),
        typicalPeriodLength: (row['average_period_length'] as num?)?.toInt(),
        onboardingCompleted: row['onboarding_completed'] as bool? ?? false,
        showFertileWindow: row['show_fertile_window'] as bool? ?? false,
        contraception: Contraception.fromDb(row['contraception'] as String?),
        lifeStage: LifeStage.fromDb(row['life_stage'] as String?),
        healthConsentAt: row['health_consent_at'] == null
            ? null
            : DateTime.tryParse(row['health_consent_at'] as String),
      );
}

({int hour, int minute}) _parseTime(String? t, int h, int m) {
  if (t == null || t.length < 5) return (hour: h, minute: m);
  return (
    hour: int.tryParse(t.substring(0, 2)) ?? h,
    minute: int.tryParse(t.substring(3, 5)) ?? m,
  );
}

String _time(int h, int m) =>
    '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:00';

class ReminderPrefs {
  const ReminderPrefs({
    this.periodReminderEnabled = false,
    this.reminderDaysBefore = 2,
    this.fertileReminderEnabled = false,
    this.dailyReminderEnabled = false,
    this.dailyHour = 20,
    this.dailyMinute = 0,
    this.neutralText = true,
    this.pillReminderEnabled = false,
    this.pillHour = 8,
    this.pillMinute = 0,
    this.injectionReminderEnabled = false,
    this.injectionLastDate,
    this.injectionIntervalWeeks = 12,
  });

  final bool periodReminderEnabled;
  final int reminderDaysBefore;
  final bool fertileReminderEnabled;
  final bool dailyReminderEnabled;
  final int dailyHour;
  final int dailyMinute;
  final bool neutralText;
  final bool pillReminderEnabled;
  final int pillHour;
  final int pillMinute;
  final bool injectionReminderEnabled;
  final DateTime? injectionLastDate;
  final int injectionIntervalWeeks;

  bool get anyEnabled =>
      periodReminderEnabled ||
      fertileReminderEnabled ||
      dailyReminderEnabled ||
      pillReminderEnabled ||
      injectionReminderEnabled;

  /// Next injection due date, when known.
  DateTime? get injectionDue => injectionLastDate == null
      ? null
      : addDays(injectionLastDate!, injectionIntervalWeeks * 7);

  ReminderPrefs copyWith({
    bool? periodReminderEnabled,
    int? reminderDaysBefore,
    bool? fertileReminderEnabled,
    bool? dailyReminderEnabled,
    int? dailyHour,
    int? dailyMinute,
    bool? neutralText,
    bool? pillReminderEnabled,
    int? pillHour,
    int? pillMinute,
    bool? injectionReminderEnabled,
    DateTime? injectionLastDate,
    int? injectionIntervalWeeks,
  }) =>
      ReminderPrefs(
        periodReminderEnabled:
            periodReminderEnabled ?? this.periodReminderEnabled,
        reminderDaysBefore: reminderDaysBefore ?? this.reminderDaysBefore,
        fertileReminderEnabled:
            fertileReminderEnabled ?? this.fertileReminderEnabled,
        dailyReminderEnabled: dailyReminderEnabled ?? this.dailyReminderEnabled,
        dailyHour: dailyHour ?? this.dailyHour,
        dailyMinute: dailyMinute ?? this.dailyMinute,
        neutralText: neutralText ?? this.neutralText,
        pillReminderEnabled: pillReminderEnabled ?? this.pillReminderEnabled,
        pillHour: pillHour ?? this.pillHour,
        pillMinute: pillMinute ?? this.pillMinute,
        injectionReminderEnabled:
            injectionReminderEnabled ?? this.injectionReminderEnabled,
        injectionLastDate: injectionLastDate ?? this.injectionLastDate,
        injectionIntervalWeeks:
            injectionIntervalWeeks ?? this.injectionIntervalWeeks,
      );

  factory ReminderPrefs.fromRow(Map<String, dynamic> row) {
    final daily = _parseTime(row['daily_reminder_time'] as String?, 20, 0);
    final pill = _parseTime(row['pill_reminder_time'] as String?, 8, 0);
    return ReminderPrefs(
      periodReminderEnabled: row['period_reminder_enabled'] as bool? ?? false,
      reminderDaysBefore: (row['reminder_days_before'] as num?)?.toInt() ?? 2,
      fertileReminderEnabled: row['fertile_reminder_enabled'] as bool? ?? false,
      dailyReminderEnabled: row['daily_reminder_enabled'] as bool? ?? false,
      dailyHour: daily.hour,
      dailyMinute: daily.minute,
      neutralText: row['neutral_notification_text'] as bool? ?? true,
      pillReminderEnabled: row['pill_reminder_enabled'] as bool? ?? false,
      pillHour: pill.hour,
      pillMinute: pill.minute,
      injectionReminderEnabled:
          row['injection_reminder_enabled'] as bool? ?? false,
      injectionLastDate: row['injection_last_date'] == null
          ? null
          : parseDbDate(row['injection_last_date'] as String),
      injectionIntervalWeeks:
          (row['injection_interval_weeks'] as num?)?.toInt() ?? 12,
    );
  }

  Map<String, dynamic> toRow() => {
        'period_reminder_enabled': periodReminderEnabled,
        'reminder_days_before': reminderDaysBefore,
        'fertile_reminder_enabled': fertileReminderEnabled,
        'daily_reminder_enabled': dailyReminderEnabled,
        'daily_reminder_time': _time(dailyHour, dailyMinute),
        'neutral_notification_text': neutralText,
        'pill_reminder_enabled': pillReminderEnabled,
        'pill_reminder_time': _time(pillHour, pillMinute),
        'injection_reminder_enabled': injectionReminderEnabled,
        'injection_last_date':
            injectionLastDate == null ? null : toDbDate(injectionLastDate!),
        'injection_interval_weeks': injectionIntervalWeeks,
      };
}
