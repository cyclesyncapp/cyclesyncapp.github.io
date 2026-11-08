import 'package:cyclesync/domain/csv_export.dart';
import 'package:cyclesync/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DailyLog rows', () {
    test('round trips and drops unknown values', () {
      final log = DailyLog.fromRow({
        'id': 'x',
        'log_date': '2026-11-08',
        'flow': 'medium',
        'symptoms': ['cramps', 'back_pain', 'unknown'],
        'mood': ['low_energy'],
        'notes': 'tired',
      });
      expect(log.flow, FlowLevel.medium);
      expect(log.symptoms, [Symptom.cramps, Symptom.backPain]);
      expect(log.moods, [Mood.lowEnergy]);
      final row = log.toRow();
      expect(row['log_date'], '2026-11-08');
      expect(row['symptoms'], ['cramps', 'back_pain']);
      expect(row['mood'], ['low_energy']);
    });

    test('blank notes are stored as null', () {
      final log = DailyLog(date: DateTime.utc(2026, 1, 1), notes: '   ');
      expect(log.toRow()['notes'], isNull);
      expect(log.isEmpty, isTrue);
    });
  });

  group('ReminderPrefs', () {
    test('parses time and round trips', () {
      final r = ReminderPrefs.fromRow({
        'period_reminder_enabled': true,
        'reminder_days_before': 3,
        'daily_reminder_enabled': true,
        'daily_reminder_time': '08:30:00',
        'neutral_notification_text': true,
      });
      expect(r.dailyHour, 8);
      expect(r.dailyMinute, 30);
      expect(r.toRow()['daily_reminder_time'], '08:30:00');
      expect(r.fertileReminderEnabled, isFalse);
    });
  });

  group('CSV export', () {
    test('header, periods then logs, oldest first', () {
      final csv = CsvExport.build(
        periods: [
          Period(id: '2', start: DateTime.utc(2026, 10, 1)),
          Period(
              id: '1',
              start: DateTime.utc(2026, 9, 1),
              end: DateTime.utc(2026, 9, 5)),
        ],
        logs: [
          DailyLog(
            date: DateTime.utc(2026, 9, 2),
            flow: FlowLevel.heavy,
            symptoms: const [Symptom.cramps, Symptom.headache],
            moods: const [Mood.sad],
            pain: 3,
            painDisrupted: true,
            notes: 'said "ouch", then rested',
          ),
        ],
      );
      final lines = csv.trim().split('\r\n');
      expect(lines.first, CsvExport.header);
      expect(lines[1], 'period,2026-09-01,2026-09-05,,,,,,,');
      expect(lines[2], 'period,2026-10-01,,,,,,,,');
      expect(lines[3],
          'daily_log,2026-09-02,,heavy,cramps;headache,sad,3,yes,,"said ""ouch"", then rested"');
    });

    test('neutralises spreadsheet formulas', () {
      expect(CsvExport.escape('=HYPERLINK("x")'), '"\'=HYPERLINK(""x"")"');
      expect(CsvExport.escape('-5'), "'-5");
    });
  });
}
