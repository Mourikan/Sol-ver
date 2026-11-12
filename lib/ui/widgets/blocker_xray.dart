import 'package:flutter/material.dart' hide Card;

import '../../core/evaluators/hand_evaluator.dart';
import '../../core/models/game_state.dart';
import '../theme/obsidian_theme.dart';

enum XRay { nutBlocker, unblockerOk, blocksBluffs }

/// Rayos-X de bloqueadores por carta de Hero frente al board (solo lectura; no altera decisiones).
class BlockerXRay {
  BlockerXRay._();

  static int _suitWith(List<Card> b, int n) {
    final c = List<int>.filled(4, 0);
    for (final x in b) {
      c[x.suit.index]++;
    }
    for (var k = 0; k < 4; k++) {
      if (c[k] >= n) return k;
    }
    return -1;
  }

  /// Palo del proyecto de color fallido en River (2 en el flop, ninguna más).
  static int missedFlushSuit(List<Card> b) {
    if (b.length < 5) return -1;
    final flop = List<int>.filled(4, 0), all = List<int>.filled(4, 0);
    for (var i = 0; i < 5; i++) {
      if (i < 3) flop[b[i].suit.index]++;
      all[b[i].suit.index]++;
    }
    for (var k = 0; k < 4; k++) {
      if (flop[k] == 2 && all[k] == 2) return k;
    }
    return -1;
  }

  static XRay? of(Card c, List<Card> board) {
    if (board.isEmpty) return c.rank == Rank.ace || c.rank == Rank.king ? XRay.nutBlocker : null;
    final fs = _suitWith(board, 3);
    if (fs >= 0 && c.suit.index == fs) {
      final on = {for (final x in board) if (x.suit.index == fs) x.rank.value};
      final free = [for (var r = 14; r >= 2; r--) if (!on.contains(r)) r].take(2);
      if (free.contains(c.rank.value)) return XRay.nutBlocker;
    }
    var mask = 0;
    for (final x in board) {
      mask |= 1 << (x.rank.value - 2);
    }
    final r = c.rank.value - 2;
    if (mask & (1 << r) == 0) {
      for (var o = 0; o < 13; o++) {
        if (o == r || mask & (1 << o) != 0) continue;
        if (HandEvaluator.straightHigh(mask | (1 << r) | (1 << o)) >= 0) return XRay.nutBlocker;
      }
    }
    final top = board.map((x) => x.rank.value).reduce((a, b) => a > b ? a : b);
    if ((c.rank == Rank.ace || c.rank == Rank.king) && c.rank.value >= top && fs < 0) return XRay.nutBlocker;
    final miss = missedFlushSuit(board);
    if (miss >= 0) return c.suit.index == miss ? XRay.blocksBluffs : XRay.unblockerOk;
    return null;
  }

  static (String, Color) label(XRay x) => switch (x) {
        XRay.nutBlocker => ('🔒 NUT BLOCKER', Obsidian.cyanCall),
        XRay.unblockerOk => ('⚡ UNBLOCKER OK', const Color(0xFF4D8DFF)),
        XRay.blocksBluffs => ('⚠️ BLOCKS BLUFFS', Obsidian.amberCheck),
      };
}

class BlockerXRayBadge extends StatelessWidget {
  const BlockerXRayBadge(this.x, {super.key});
  final XRay? x;

  @override
  Widget build(BuildContext context) {
    if (x == null) return const SizedBox.shrink();
    final (t, c) = BlockerXRay.label(x!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: .16), borderRadius: BorderRadius.circular(4), border: Border.all(color: c.withValues(alpha: .7), width: 1)),
      child: FittedBox(child: Text(t, style: TextStyle(color: c, fontSize: 9, fontWeight: FontWeight.w900))),
    );
  }
}
