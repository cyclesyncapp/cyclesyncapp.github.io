// The pdf package mixes const and non-const constructors across versions.
// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables

import 'package:intl/intl.dart' show DateFormat;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/cycle_calculator.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';

/// Builds a one- or two-page PDF a user can show at a clinic visit.
/// Only the user's own logged data; no estimates presented as facts.
Future<List<int>> buildDoctorReport({
  required CycleSummary summary,
  required List<DailyLog> logs,
  required DateTime today,
  Profile? profile,
}) async {
  final fmt = DateFormat('d MMM yyyy');
  final since6m = addDays(today, -182);
  final oldestFirst = CycleCalculator.sortedByStart(summary.periods);
  final recent = oldestFirst.length > 12
      ? oldestFirst.sublist(oldestFirst.length - 12)
      : oldestFirst;
  final st = summary.stats;

  // Period rows with the cycle length to the next start.
  final rows = <List<String>>[];
  for (var i = 0; i < recent.length; i++) {
    final p = recent[i];
    final idx = oldestFirst.indexOf(p);
    final next = idx + 1 < oldestFirst.length ? oldestFirst[idx + 1] : null;
    rows.add([
      fmt.format(p.start),
      p.end == null ? '-' : fmt.format(p.end!),
      p.durationDays == null ? '-' : '${p.durationDays} days',
      next == null ? '-' : '${daysBetween(p.start, next.start)} days',
    ]);
  }

  // Symptom and bleeding counts over the last 6 months.
  final recentLogs = logs.where((l) => !l.date.isBefore(since6m)).toList();
  final symptomCounts = <Symptom, int>{};
  for (final l in recentLogs) {
    for (final s in l.symptoms) {
      symptomCounts[s] = (symptomCounts[s] ?? 0) + 1;
    }
  }
  final symptomRows = symptomCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final heavy = recentLogs.where((l) => l.flow == FlowLevel.heavy).length;
  final soaked = recentLogs.where((l) => l.heavySoaked).length;
  final painMod = recentLogs.where((l) => (l.pain ?? 0) >= 2).length;
  final disrupted = recentLogs.where((l) => l.painDisrupted).length;
  final between = recentLogs
      .where((l) => l.flow.anyBleeding && summary.periodOn(l.date) == null)
      .length;

  String days(int? n) => n == null ? 'Not enough data' : '$n days';

  final pink = PdfColor.fromHex('#C2266F');
  final grey = PdfColor.fromHex('#6B5A70');

  pw.Widget heading(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
        child: pw.Text(t,
            style: pw.TextStyle(
                fontSize: 13, fontWeight: pw.FontWeight.bold, color: pink)),
      );

  pw.Widget keyValue(List<(String, String)> items) => pw.Table(
        columnWidths: const {
          0: pw.FlexColumnWidth(2),
          1: pw.FlexColumnWidth(3),
        },
        children: [
          for (final (k, v) in items)
            pw.TableRow(children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 3),
                child: pw.Text(k, style: pw.TextStyle(color: grey)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 3),
                child: pw.Text(v,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ),
            ]),
        ],
      );

  final doc = pw.Document(title: 'CycleSync summary', author: 'CycleSync');
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      footer: (ctx) => pw.Text(
        'Made with CycleSync from information the user logged. Not a medical '
        'record or diagnosis. Page ${ctx.pageNumber} of ${ctx.pagesCount}.',
        style: pw.TextStyle(fontSize: 8, color: grey),
      ),
      build: (ctx) => [
        pw.Text('Cycle summary for a healthcare visit',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(
          [
            if ((profile?.displayName ?? '').trim().isNotEmpty)
              profile!.displayName!.trim(),
            'Created ${fmt.format(today)}',
          ].join('  |  '),
          style: pw.TextStyle(color: grey),
        ),
        heading('Overview'),
        keyValue([
          ('Typical cycle length (median)',
              st.averageCycle == null ? 'Not enough data' : days(st.averageCycle!.round())),
          ('Shortest / longest recent cycle',
              st.shortestCycle == null
                  ? 'Not enough data'
                  : '${st.shortestCycle} / ${st.longestCycle} days'),
          ('Typical period length (median)',
              st.averagePeriod == null ? 'Not enough data' : days(st.averagePeriod!.round())),
          ('Last period started',
              summary.lastPeriod == null ? 'None logged' : fmt.format(summary.lastPeriod!.start)),
          ('Periods logged', '${summary.periods.length}'),
          ('Contraception', profile?.contraception?.label ?? 'Not shared'),
          ('Life stage', profile?.lifeStage.label ?? 'Not shared'),
        ]),
        heading('Last 6 months'),
        keyValue([
          ('Heavy flow days', '$heavy'),
          ('Very heavy (soaking through / clots)', '$soaked days'),
          ('Moderate or severe pain', '$painMod days'),
          ('Pain that stopped daily activities', '$disrupted days'),
          ('Bleeding or spotting outside a period', '$between days'),
        ]),
        heading('Recent periods'),
        if (rows.isEmpty)
          pw.Text('No periods logged.')
        else
          pw.TableHelper.fromTextArray(
            headers: ['Start', 'End', 'Period length', 'Cycle length'],
            data: rows.reversed.toList(),
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: pw.BoxDecoration(color: pink),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding:
                const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          ),
        heading('Symptoms logged (last 6 months)'),
        if (symptomRows.isEmpty)
          pw.Text('No symptoms logged.')
        else
          pw.TableHelper.fromTextArray(
            headers: ['Symptom', 'Days logged'],
            data: [
              for (final e in symptomRows) [e.key.label, '${e.value}'],
            ],
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: pw.BoxDecoration(color: pink),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding:
                const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Cycle length is counted from the first day of one period to the '
          'first day of the next. Values reflect what was logged and may be '
          'incomplete.',
          style: pw.TextStyle(fontSize: 9, color: grey),
        ),
      ],
    ),
  );
  return doc.save();
}

String doctorReportFileName(DateTime today) =>
    'cyclesync-summary-${toDbDate(today)}.pdf';
