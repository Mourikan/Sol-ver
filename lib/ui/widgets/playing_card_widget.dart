import 'package:flutter/material.dart' hide Card;

import '../../core/models/game_state.dart';
import '../theme.dart';

/// Carta vectorial (4 colores) con bordes redondeados; slot vacío con foco opcional.
class PlayingCardWidget extends StatelessWidget {
  const PlayingCardWidget(this.card, {super.key, this.focus = false});
  final Card? card;
  final bool focus;

  @override
  Widget build(BuildContext context) => AspectRatio(aspectRatio: 0.72, child: CustomPaint(painter: _CardPainter(card, focus)));
}

class _CardPainter extends CustomPainter {
  _CardPainter(this.card, this.focus);
  final Card? card;
  final bool focus;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.width * 0.14));
    final c = card;
    if (c == null) {
      canvas.drawRRect(r, Paint()..color = AppColors.surface);
      canvas.drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = focus ? 2 : 1
          ..color = focus ? AppColors.amber : AppColors.border,
      );
      return;
    }
    final col = AppColors.suit(c.suit);
    canvas.drawRRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFF1E2128), const Color(0xFF15171C)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = col.withValues(alpha: .85),
    );
    void text(String t, double fs, Offset at, {FontWeight w = FontWeight.w900}) {
      final tp = TextPainter(
        text: TextSpan(
          text: t,
          style: TextStyle(color: col, fontSize: fs, fontWeight: w, height: 1),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }

    text(c.rank.symbol, size.height * 0.40, Offset(size.width / 2, size.height * 0.36));
    text(AppColors.suitGlyph(c.suit), size.height * 0.34, Offset(size.width / 2, size.height * 0.74), w: FontWeight.w700);
  }

  @override
  bool shouldRepaint(_CardPainter o) => o.card != card || o.focus != focus;
}
