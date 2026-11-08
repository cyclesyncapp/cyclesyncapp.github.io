import 'dates.dart';
import 'models.dart';

/// Builds a CSV of the user's own records (periods and daily logs).
class CsvExport {
  const CsvExport._();

  static const header = 'record_type,date,end_date,flow,symptoms,mood,'
      'pain,pain_stopped_activities,very_heavy,notes';

  static String build({
    required List<Period> periods,
    required List<DailyLog> logs,
  }) {
    final rows = <String>[header];
    final ps = [...periods]..sort((a, b) => a.start.compareTo(b.start));
    for (final p in ps) {
      rows.add([
        'period',
        toDbDate(p.start),
        p.end == null ? '' : toDbDate(p.end!),
        '',
        '',
        '',
        '',
        '',
        '',
        p.notes ?? '',
      ].map(escape).join(','));
    }
    final ls = [...logs]..sort((a, b) => a.date.compareTo(b.date));
    for (final l in ls) {
      rows.add([
        'daily_log',
        toDbDate(l.date),
        '',
        l.flow.db,
        l.symptoms.map((s) => s.db).join(';'),
        l.moods.map((m) => m.db).join(';'),
        l.pain == null ? '' : '${l.pain}',
        l.painDisrupted ? 'yes' : '',
        l.heavySoaked ? 'yes' : '',
        l.notes ?? '',
      ].map(escape).join(','));
    }
    return '${rows.join('\r\n')}\r\n';
  }

  /// RFC 4180 quoting. Also neutralises spreadsheet formula injection.
  static String escape(String value) {
    var v = value;
    if (v.isNotEmpty && '=+-@'.contains(v[0])) v = "'$v";
    final needsQuotes = v.contains(',') ||
        v.contains('"') ||
        v.contains('\n') ||
        v.contains('\r');
    if (!needsQuotes) return v;
    return '"${v.replaceAll('"', '""')}"';
  }

  static String fileName(DateTime today) =>
      'cyclesync-export-${toDbDate(today)}.csv';
}
