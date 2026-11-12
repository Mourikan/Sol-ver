import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;

import '../../application/hand_flow_fsm.dart';
import '../../core/models/game_state.dart';
import '../theme.dart';

class SeatSnap {
  const SeatSnap(this.pos, this.stack, this.committed, {required this.alive, required this.hero, required this.turn, required this.tag, required this.selected});
  final Position pos;
  final double stack, committed;
  final bool alive, hero, turn, selected;
  final String tag;

  @override
  bool operator ==(Object other) =>
      other is SeatSnap && other.pos == pos && other.stack == stack && other.committed == committed && other.alive == alive && other.hero == hero && other.turn == turn && other.tag == tag && other.selected == selected;
  @override
  int get hashCode => Object.hash(pos, stack, committed, alive, hero, turn, tag, selected);
}

/// Mesa 6-max vectorial (GPU): tapete radial, glow del turno, fichas por apuesta y bote/SPR al centro.
class ProPokerTable extends StatelessWidget {
  const ProPokerTable(
      {super.key, required this.fsm, required this.tagOf, required this.onTap, required this.onLongPress, this.onSwipeDown, this.geoActive = false});
  final HandFlowFSM fsm;
  final String Function(Position) tagOf;
  final void Function(Position) onTap;
  final void Function(Position) onLongPress;

  /// Swipe vertical hacia abajo sobre el asiento: fold inmediato del villano.
  final void Function(Position)? onSwipeDown;
  final bool geoActive;

  static Offset seatOffset(Position p, Position hero, Size s) {
    final order = HandFlowFSM.preflopOrder;
    final ang = math.pi / 2 + (order.indexOf(p) - order.indexOf(hero)) * math.pi / 3;
    return Offset(s.width / 2 + math.cos(ang) * s.width * 0.40, s.height / 2 + math.sin(ang) * s.height * 0.38);
  }

  @override
  Widget build(BuildContext context) {
    final seats = [
      for (final p in HandFlowFSM.preflopOrder)
        SeatSnap(p, fsm.stackOf(p), fsm.seats[p]?.committed ?? 0,
            alive: fsm.seats[p]?.alive ?? true,
            hero: p == fsm.heroPosition,
            turn: fsm.currentActor == p,
            tag: p == fsm.heroPosition ? 'HERO' : tagOf(p),
            selected: fsm.selectedVillain == p),
    ];
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      return Stack(children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
                key: const ValueKey('pro-table'),
                painter: ProPokerTablePainter(seats, pot: fsm.totalPotBB, spr: fsm.currentSPR, hero: fsm.heroPosition, geoActive: geoActive)),
          ),
        ),
        for (final s in seats)
          Positioned(
            left: seatOffset(s.pos, fsm.heroPosition, size).dx - 38,
            top: seatOffset(s.pos, fsm.heroPosition, size).dy - 22,
            width: 76,
            height: 44,
            child: GestureDetector(
              key: ValueKey('cockpit-seat-${s.pos.name}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(s.pos),
              onLongPress: s.hero ? null : () => onLongPress(s.pos),
              onVerticalDragEnd: s.hero || onSwipeDown == null
                  ? null
                  : (d) {
                      if ((d.primaryVelocity ?? 0) > 150) onSwipeDown!(s.pos);
                    },
            ),
          ),
      ]);
    });
  }
}

class ProPokerTablePainter extends CustomPainter {
  ProPokerTablePainter(this.seats, {required this.pot, required this.spr, required this.hero, this.geoActive = false});
  final List<SeatSnap> seats;
  final double pot;
  final double? spr;
  final Position hero;
  final bool geoActive;

  /// SPR_Commitment_Gauge: escala 13 -> 0 sobre un arco de 270°.
  static const gaugeMaxSpr = 13.0, commitSpr = 2.5;

  static Color tagColor(String t) => switch (t) {
        'HERO' => AppColors.emerald,
        'Fish' || 'Fish/CS' => AppColors.cyan,
        'Nit' => const Color(0xFF94A3B8),
        'Scared' => AppColors.amber,
        'Maniac' => AppColors.crimson,
        'Trapper' => const Color(0xFFF97316),
        'Reg' => const Color(0xFFA78BFA),
        _ => const Color(0xFF60A5FA),
      };

  void _text(Canvas c, String t, Offset at, {double fs = 11, Color col = AppColors.text, FontWeight w = FontWeight.w700}) {
    final tp = TextPainter(
        text: TextSpan(text: t, style: TextStyle(color: col, fontSize: fs, fontWeight: w, fontFeatures: const [FontFeature.tabularFigures()])),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(c, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final table = Rect.fromCenter(center: size.center(Offset.zero), width: size.width * 0.80, height: size.height * 0.62);
    canvas.drawOval(table.inflate(6), Paint()..color = const Color(0xFF1B2230));
    canvas.drawOval(
        table,
        Paint()
          ..shader = const RadialGradient(colors: [Color(0xFF14352B), Color(0xFF0C1F1A), Color(0xFF0A1412)], stops: [0, .7, 1])
              .createShader(table));
    canvas.drawOval(table, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.border);
    // SPR_Commitment_Gauge (270°): cuanto menor el SPR, más compromiso; brilla en zona de compromiso o Geo-2E.
    final rad = math.min(table.height * 0.42, 46.0);
    final arcRect = Rect.fromCircle(center: table.center, radius: rad);
    const start = math.pi * 0.75, sweep = math.pi * 1.5;
    canvas.drawArc(arcRect, start, sweep, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = AppColors.border);
    final commit = spr == null ? 0.0 : (1 - (spr! / gaugeMaxSpr).clamp(0.0, 1.0));
    final hot = spr != null && (spr! <= commitSpr || geoActive);
    final gc = hot ? (geoActive ? AppColors.emerald : AppColors.cyan) : AppColors.amber;
    if (commit > 0) {
      if (hot) {
        canvas.drawArc(arcRect, start, sweep * commit, false, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..color = gc.withValues(alpha: .35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      }
      canvas.drawArc(arcRect, start, sweep * commit, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = gc);
    }
    _text(canvas, 'Pot ${pot.toStringAsFixed(2)} bb', table.center.translate(0, -7), fs: 15, w: FontWeight.w900);
    _text(canvas, 'SPR ${spr == null ? '—' : spr!.toStringAsFixed(2)}', table.center.translate(0, 11), fs: 11, col: hot ? gc : AppColors.muted);
    if (hot) _text(canvas, geoActive ? '[GEO-2E]' : '[COMMIT ZONE]', table.center.translate(0, rad - 4), fs: 9, col: gc, w: FontWeight.w900);
    for (final s in seats) {
      final o = ProPokerTable.seatOffset(s.pos, hero, size);
      final plate = RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: 74, height: 42), const Radius.circular(10));
      if (s.turn) {
        canvas.drawRRect(plate.inflate(3), Paint()
          ..color = AppColors.amber.withValues(alpha: .55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
      }
      canvas.drawRRect(plate, Paint()..color = s.alive ? AppColors.surface : AppColors.surface.withValues(alpha: .35));
      canvas.drawRRect(plate, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.turn ? 2 : (s.selected ? 1.6 : 1)
        ..color = s.turn ? AppColors.amber : (s.selected ? AppColors.cyan : (s.hero ? AppColors.emerald : AppColors.border)));
      final dim = s.alive ? 1.0 : .4;
      _text(canvas, s.pos.name.toUpperCase(), o.translate(-18, -11), fs: 11, w: FontWeight.w900, col: AppColors.text.withValues(alpha: dim));
      _text(canvas, '${s.stack.toStringAsFixed(1)}bb', o.translate(14, -11), fs: 10, col: AppColors.muted.withValues(alpha: dim));
      final tc = tagColor(s.tag);
      final tagR = RRect.fromRectAndRadius(Rect.fromCenter(center: o.translate(0, 9), width: 56, height: 15), const Radius.circular(4));
      canvas.drawRRect(tagR, Paint()..color = tc.withValues(alpha: .22 * dim));
      _text(canvas, s.hero ? '[HERO]' : s.tag, o.translate(0, 9), fs: 10, col: tc.withValues(alpha: dim), w: FontWeight.w800);
      if (s.committed > 0) {
        final toward = Offset.lerp(o, table.center, .42)!;
        for (var k = 0; k < math.min(4, (s.committed / 2).ceil()); k++) {
          final cc = toward.translate(-14, -k * 3.0);
          canvas.drawCircle(cc, 6, Paint()..color = k.isEven ? AppColors.emerald : AppColors.amber);
          canvas.drawCircle(cc, 6, Paint()
            ..style = PaintingStyle.stroke
            ..color = Colors.black54);
        }
        _text(canvas, s.committed.toStringAsFixed(1), toward.translate(6, 0), fs: 10, w: FontWeight.w800);
      }
    }
  }

  @override
  bool shouldRepaint(ProPokerTablePainter o) => o.pot != pot || o.spr != spr || o.hero != hero || o.geoActive != geoActive || !_listEq(o.seats, seats);

  static bool _listEq(List<SeatSnap> a, List<SeatSnap> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
