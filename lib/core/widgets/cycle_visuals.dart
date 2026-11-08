import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../domain/cycle_calculator.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';
import '../theme/app_theme.dart';

IconData symptomIcon(Symptom s) => switch (s) {
      Symptom.cramps => Icons.bolt,
      Symptom.headache => Icons.psychology_outlined,
      Symptom.bloating => Icons.bubble_chart_outlined,
      Symptom.acne => Icons.grain,
      Symptom.breastTenderness => Icons.favorite_border,
      Symptom.fatigue => Icons.bedtime_outlined,
      Symptom.nausea => Icons.sick_outlined,
      Symptom.backPain => Icons.accessibility_new,
      Symptom.other => Icons.more_horiz,
    };

IconData moodIcon(Mood m) => switch (m) {
      Mood.happy => Icons.sentiment_very_satisfied,
      Mood.calm => Icons.sentiment_satisfied,
      Mood.neutral => Icons.sentiment_neutral,
      Mood.anxious => Icons.waves,
      Mood.sad => Icons.sentiment_dissatisfied,
      Mood.irritable => Icons.sentiment_very_dissatisfied,
      Mood.lowEnergy => Icons.battery_alert,
      Mood.other => Icons.more_horiz,
    };

IconData flowIcon(FlowLevel f) => switch (f) {
      FlowLevel.none => Icons.block,
      FlowLevel.spotting => Icons.grain,
      FlowLevel.light => Icons.water_drop_outlined,
      FlowLevel.medium => Icons.water_drop,
      FlowLevel.heavy => Icons.invert_colors,
    };

enum DayMark { none, period, predictedPeriod, fertile, ovulation }

/// What to draw for [day], from the summary.
DayMark markFor(CycleSummary s, DateTime day) {
  if (s.periodOn(day) != null) return DayMark.period;
  if (s.predictedPeriodDays.contains(day)) return DayMark.predictedPeriod;
  // A single "ovulation day" implies more certainty than a calendar estimate
  // has, so only the fertile window is shown.
  if (s.fertileDays.contains(day)) return DayMark.fertile;
  return DayMark.none;
}

String describeDay(DateTime day, DayMark mark,
    {required bool isToday, required bool hasLog}) {
  final parts = <String>[DateFormat('EEEE d MMMM').format(day)];
  if (isToday) parts.add('today');
  switch (mark) {
    case DayMark.period:
      parts.add('logged period day');
    case DayMark.predictedPeriod:
      parts.add('estimated period day');
    case DayMark.fertile:
      parts.add('estimated fertile day');
    case DayMark.ovulation:
      parts.add('estimated ovulation day');
    case DayMark.none:
      break;
  }
  if (hasLog) parts.add('has a daily log');
  return parts.join(', ');
}

/// One round day in a calendar. Uses fill, outline style and labels
/// (not colour alone) to tell logged and estimated days apart.
class DayCell extends StatelessWidget {
  const DayCell({
    super.key,
    required this.day,
    required this.mark,
    required this.isToday,
    this.hasLog = false,
    this.dimmed = false,
    this.selected = false,
    this.onTap,
    this.size = 40,
  });

  final DateTime day;
  final DayMark mark;
  final bool isToday;
  final bool hasLog;
  final bool dimmed;
  final bool selected;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.cycle;
    Color? fill;
    Color text = c.heading;
    Border? border;
    var dashed = false;

    switch (mark) {
      case DayMark.period:
        fill = c.period;
        text = Colors.white;
      case DayMark.predictedPeriod:
        fill = c.periodSoft;
        dashed = true;
      case DayMark.fertile:
        fill = c.fertileSoft;
        border = Border.all(color: c.fertile);
      case DayMark.ovulation:
        fill = c.fertile;
        text = Colors.white;
      case DayMark.none:
        break;
    }
    if (isToday && mark == DayMark.none) {
      fill = c.todayFill;
      text = c.onTodayFill;
    }

    Widget circle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: border,
      ),
      child: Text(
        '${day.day}',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: size * 0.38,
          fontWeight:
              (mark != DayMark.none || isToday) ? FontWeight.w700 : FontWeight.w500,
          color: text,
        ),
      ),
    );
    if (dashed) {
      circle = CustomPaint(
        foregroundPainter: DashedCirclePainter(color: c.period),
        child: circle,
      );
    }
    if ((isToday && mark != DayMark.none) || selected) {
      circle = Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? context.colors.primary : c.todayFill,
            width: 2.5,
          ),
        ),
        child: circle,
      );
    }

    return Semantics(
      button: onTap != null,
      selected: selected,
      label: describeDay(day, mark, isToday: isToday, hasLog: hasLog),
      excludeSemantics: true,
      child: Opacity(
        opacity: dimmed ? 0.4 : 1,
        child: InkResponse(
          onTap: onTap,
          radius: size * 0.6,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              circle,
              const SizedBox(height: 3),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasLog ? context.colors.secondary : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DashedCirclePainter extends CustomPainter {
  DashedCirclePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    final r = math.min(size.width, size.height) / 2 - 1;
    final center = Offset(size.width / 2, size.height / 2);
    const dashes = 12;
    const sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        i * sweep,
        sweep * 0.55,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(DashedCirclePainter old) => old.color != color;
}

/// Legend explaining each day style.
class CalendarLegend extends StatelessWidget {
  const CalendarLegend({super.key, required this.showFertile});

  final bool showFertile;

  @override
  Widget build(BuildContext context) {
    final c = context.cycle;
    Widget item(Widget swatch, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            swatch,
            const SizedBox(width: 6),
            Text(label, style: context.text.bodySmall),
          ],
        );
    Widget dot(Color color, {Border? border}) => Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: border,
          ),
        );
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        item(dot(c.period), 'Period'),
        item(
          CustomPaint(
            foregroundPainter: DashedCirclePainter(color: c.period),
            child: dot(c.periodSoft),
          ),
          'Predicted',
        ),
        if (showFertile)
          item(dot(c.fertileSoft, border: Border.all(color: c.fertile)),
              'Fertile (est.)'),
        item(dot(c.todayFill), 'Today'),
        item(
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.colors.secondary,
            ),
          ),
          'Logged',
        ),
      ],
    );
  }
}

const weekdayInitials = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Seven-day strip (Mon–Sun) around [anchor].
class WeekStrip extends StatelessWidget {
  const WeekStrip({
    super.key,
    required this.summary,
    required this.loggedDays,
    required this.onDayTap,
  });

  final CycleSummary summary;
  final Set<DateTime> loggedDays;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final monday = startOfWeek(summary.today);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Column(
              children: [
                ExcludeSemantics(
                  child: Text(
                    weekdayInitials[i],
                    style: context.text.bodySmall?.copyWith(
                      color: context.cycle.muted,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Builder(builder: (context) {
                  final day = addDays(monday, i);
                  return DayCell(
                    day: day,
                    size: 36,
                    mark: markFor(summary, day),
                    isToday: sameDate(day, summary.today),
                    hasLog: loggedDays.contains(day),
                    onTap: () => onDayTap(day),
                  );
                }),
              ],
            ),
          ),
      ],
    );
  }
}
