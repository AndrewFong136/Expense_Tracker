import 'dart:math' show pi, min;
import 'package:flutter/material.dart';

class WeeklyOverviewChart extends StatelessWidget {
  const WeeklyOverviewChart({
    super.key,
    required this.values,
    required this.progress,
    required this.progressColor,
    required this.centerAmount,
    this.centerLabel = '',
    this.sublabel = '',
    this.todayIndex,
    this.selectedIndex,
    this.onBarTap,
  });

  /// (label, saved) per day, Mon..Sun.
  final List<({String label, double saved})> values;

  /// 0..1 — ring fill = spent/target.
  final double progress;

  /// Ring + centre-amount colour: green under target, red over.
  final Color progressColor;

  /// Bold amount shown in the ring centre.
  final String centerAmount;
  final String centerLabel;
  final String sublabel;

  /// Index of today's day (0=Mon..6=Sun) for label highlighting, or null when
  /// the displayed week isn't the current week.
  final int? todayIndex;

  /// Index of the selected day (bar highlighted), or null.
  final int? selectedIndex;

  /// Called when a bar is tapped, with the day index (0..6).
  final ValueChanged<int>? onBarTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            if (onBarTap == null || values.isEmpty) return;
            final chartW = width * 0.60;
            final dx = details.localPosition.dx;
            if (dx > chartW) return;
            final slot = chartW / values.length;
            final idx = (dx / slot).floor().clamp(0, values.length - 1);
            onBarTap!(idx);
          },
          child: CustomPaint(
            size: Size.infinite,
            painter: _OverviewPainter(
              values: values,
              progress: progress.clamp(0.0, 1.0),
              progressColor: progressColor,
              centerAmount: centerAmount,
              centerLabel: centerLabel,
              sublabel: sublabel,
              onSurface: theme.colorScheme.onSurface,
              primary: theme.colorScheme.primary,
              todayIndex: todayIndex,
              selectedIndex: selectedIndex,
            ),
          ),
        );
      },
    );
  }
}

class _OverviewPainter extends CustomPainter {
  _OverviewPainter({
    required this.values,
    required this.progress,
    required this.progressColor,
    required this.centerAmount,
    required this.centerLabel,
    required this.sublabel,
    required this.onSurface,
    required this.primary,
    required this.todayIndex,
    required this.selectedIndex,
  });

  final List<({String label, double saved})> values;
  final double progress;
  final Color progressColor;
  final String centerAmount;
  final String centerLabel;
  final String sublabel;
  final Color onSurface;
  final Color primary;
  final int? todayIndex;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const labelArea = 16.0;
    const chartTop = 6.0;
    final chartBottom = h - labelArea;
    final midY = (chartTop + chartBottom) / 2;
    final chartH = chartBottom - chartTop;
    final chartW = w * 0.60;
    final ringCenterX = w * 0.80;
    const strokeWidth = 12.0;
    final ringR = min(
      w * 0.18,
      min(midY - chartTop, h - midY) - strokeWidth / 2 - 2,
    );
    if (ringR <= 0) return;

    final linePaint = Paint()
      ..color = onSurface.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, midY),
      Offset(ringCenterX - ringR, midY),
      linePaint,
    );

    // Diverging bars (left ~60%).
    final n = values.length;
    if (n > 0) {
      final barSlot = chartW / n;
      final barW = barSlot * 0.5;
      double maxAbs = 0;
      for (final v in values) {
        if (v.saved.abs() > maxAbs) maxAbs = v.saved.abs();
      }
      final halfH = chartH / 2 - 4;
      final scale = maxAbs > 0 ? halfH / maxAbs : 0.0;
      for (var i = 0; i < n; i++) {
        final cx = i * barSlot + barSlot / 2;

        // Selected-day highlight (faint primary backdrop across the slot).
        if (selectedIndex == i) {
          final hlPaint = Paint()
            ..color = primary.withValues(alpha: 0.10);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(i * barSlot, chartTop, barSlot, chartH),
              const Radius.circular(6),
            ),
            hlPaint,
          );
        }

        final v = values[i].saved;
        final left = cx - barW / 2;
        final bh = v.abs() * scale;
        final paint = Paint()..color = v >= 0 ? Colors.green : Colors.red;
        final rect = v >= 0
            ? Rect.fromLTWH(left, midY - bh, barW, bh)
            : Rect.fromLTWH(left, midY, barW, bh);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          paint,
        );

        // Day label — today in primary, otherwise muted.
        _text(
          canvas,
          values[i].label,
          cx,
          chartBottom + 2,
          TextStyle(
            color: todayIndex == i ? primary : onSurface.withValues(alpha: 0.6),
            fontSize: 11,
            fontWeight: todayIndex == i ? FontWeight.w800 : FontWeight.normal,
          ),
        );
      }
    }

    // Ring — centred on the zero line so the line touches its left edge.
    final bgRing = Paint()
      ..color = onSurface.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(Offset(ringCenterX, midY), ringR, bgRing);
    final fgRing = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(ringCenterX, midY), radius: ringR),
      -pi / 2,
      2 * pi * progress,
      false,
      fgRing,
    );

    // Ring-centre text (3-line block centred at ringCenterX, midY).
    final amountTp = TextPainter(
      text: TextSpan(
        text: centerAmount,
        style: TextStyle(
          color: progressColor,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    TextPainter? labelTp;
    if (centerLabel.isNotEmpty) {
      labelTp = TextPainter(
        text: TextSpan(
          text: centerLabel,
          style: TextStyle(color: onSurface.withValues(alpha: 0.6), fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }
    TextPainter? subTp;
    if (sublabel.isNotEmpty) {
      subTp = TextPainter(
        text: TextSpan(
          text: sublabel,
          style: TextStyle(color: onSurface.withValues(alpha: 0.45), fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }
    const gap = 2.0;
    final totalH = amountTp.height +
        (labelTp != null ? gap + labelTp.height : 0) +
        (subTp != null ? gap + subTp.height : 0);
    double y = midY - totalH / 2;
    amountTp.paint(canvas, Offset(ringCenterX - amountTp.width / 2, y));
    y += amountTp.height + gap;
    if (labelTp != null) {
      labelTp.paint(canvas, Offset(ringCenterX - labelTp.width / 2, y));
      y += labelTp.height + gap;
    }
    if (subTp != null) {
      subTp.paint(canvas, Offset(ringCenterX - subTp.width / 2, y));
    }
  }

  void _text(Canvas canvas, String s, double cx, double topY, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, topY));
  }

  @override
  bool shouldRepaint(covariant _OverviewPainter old) => true;
}
