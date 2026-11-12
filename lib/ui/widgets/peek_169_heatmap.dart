import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/preflop/range_notation.dart';
import '../theme/obsidian_theme.dart';

/// Mapa de calor 13x13 (AA..22) del peso de cada clase que sobrevive en el RangeFunnel del villano en el nodo.
class Peek169Heatmap extends StatelessWidget {
  const Peek169Heatmap(this.weights, {super.key});
  final List<double> weights;

  static Future<void> show(BuildContext context, List<double> weights) => showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(10),
          child: Obsidian.panel(
            key: const ValueKey('heatmap-dialog'),
            padding: const EdgeInsets.all(8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Rango del villano en este nodo (13x13)', style: TextStyle(color: Obsidian.text, fontWeight: FontWeight.w900, fontSize: 13)),
              const SizedBox(height: 6),
              Peek169Heatmap(weights),
              const SizedBox(height: 4),
              Text('0% ▁▂▃▅▇ 100% · suited arriba / offsuit abajo', style: Obsidian.num(size: 10, color: Obsidian.muted)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final side = math.min(c.maxWidth, c.maxHeight.isFinite ? c.maxHeight : c.maxWidth);
        return SizedBox(
          width: side,
          height: side,
          child: RepaintBoundary(child: CustomPaint(key: const ValueKey('heatmap'), painter: _HeatPainter(weights))),
        );
      });
}

class _HeatPainter extends CustomPainter {
  _HeatPainter(this.w);
  final List<double> w;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 13;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < 169; i++) {
      final row = i ~/ 13, col = i % 13;
      final v = i < w.length ? w[i].clamp(0.0, 1.0) : 0.0;
      final rect = Rect.fromLTWH(col * cell, row * cell, cell, cell).deflate(0.5);
      final base = row == col ? Obsidian.amberCheck : (col > row ? Obsidian.emeraldRaise : Obsidian.cyanCall);
      canvas.drawRect(rect, Paint()..color = Color.lerp(Obsidian.surfaceCard, base, v)!);
      tp
        ..text = TextSpan(
            text: Matrix169.label(i),
            style: TextStyle(color: v > .55 ? Colors.black : Obsidian.muted, fontSize: cell * .30, fontWeight: FontWeight.w700))
        ..layout();
      tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_HeatPainter o) => !identical(o.w, w);
}
