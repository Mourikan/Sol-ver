import 'dart:math' as math;

import '../evaluators/hand_evaluator.dart';
import '../models/game_state.dart';

/// Historia de texturas flop -> river: qué proyectos existían y cuáles se completaron.
class BoardHistory {
  BoardHistory(List<Card> board)
      : flop = board.sublist(0, 3),
        finalBoard = board;

  final List<Card> flop;
  final List<Card> finalBoard;

  static (List<int>, int, int) _stats(List<Card> b) {
    final suits = List<int>.filled(4, 0);
    var mask = 0;
    for (final c in b) {
      suits[c.suit.index]++;
      mask |= 1 << c.rank.value;
    }
    if (mask & (1 << 14) != 0) mask |= 2;
    var s3 = 0, s2 = 0;
    for (var lo = 1; lo <= 10; lo++) {
      var n = 0, m = mask & (0x1F << lo);
      while (m != 0) {
        m &= m - 1;
        n++;
      }
      if (n >= 3) {
        s3++;
      } else if (n == 2) {
        s2++;
      }
    }
    return (suits, s3, s2);
  }

  /// Palo con proyecto de color en flop o turn (>=2 cartas antes del river), -1 si no hubo.
  int get drawSuit {
    final pre = finalBoard.length >= 4 ? finalBoard.sublist(0, 4) : flop;
    final (s, _, _) = _stats(pre);
    final m = s.reduce(math.max);
    return m >= 2 ? s.indexOf(m) : -1;
  }

  bool get flushCompleted => _stats(finalBoard).$1.any((n) => n >= 3);
  bool get flushDrawExisted => drawSuit >= 0;
  bool get missedFlushDraw => flushDrawExisted && !flushCompleted;

  bool get straightDrawExisted {
    final pre = finalBoard.length >= 4 ? finalBoard.sublist(0, 4) : flop;
    final (_, s3, s2) = _stats(pre);
    return s2 > 0 || s3 > 0;
  }

  bool get straightCompleted {
    final pre = finalBoard.length >= 4 ? finalBoard.sublist(0, finalBoard.length - 1) : flop;
    return _stats(finalBoard).$2 > _stats(flop).$2 || _stats(finalBoard).$2 > _stats(pre).$2;
  }

  bool get missedStraightDraw => straightDrawExisted && !straightCompleted;
  bool get brickOut => !flushCompleted && !straightCompleted && (flushDrawExisted || straightDrawExisted);

  /// ¿Hero bloquea las nuts del rival (carta alta libre del color completado o rango que completa escalera)?
  bool heroBlocksNuts(HoleCards h) {
    final hero = [h.high, h.low];
    if (flushCompleted) {
      final (s, _, _) = _stats(finalBoard);
      final fs = s.indexOf(s.reduce(math.max));
      final on = {for (final c in finalBoard) if (c.suit.index == fs) c.rank.value};
      final top = [for (var r = 14; r >= 2; r--) if (!on.contains(r)) r].first;
      if (hero.any((c) => c.suit.index == fs && c.rank.value == top)) return true;
    }
    if (straightCompleted) {
      var mask = 0;
      for (final c in finalBoard) {
        mask |= 1 << (c.rank.value - 2);
      }
      final best = _bestStraightNeed(mask);
      if (hero.any((c) => best.contains(c.rank.value - 2))) return true;
    }
    return false;
  }

  static Set<int> _bestStraightNeed(int mask) {
    var bestHigh = -1;
    var need = <int>{};
    for (var a = 0; a < 13; a++) {
      for (var b = a; b < 13; b++) {
        final m = mask | (1 << a) | (1 << b);
        final hi = HandEvaluator.straightHigh(m);
        if (hi < 0 || HandEvaluator.straightHigh(mask) >= hi) continue;
        if (hi > bestHigh) {
          bestHigh = hi;
          need = {};
        }
        if (hi == bestHigh) need.addAll([if (mask & (1 << a) == 0) a, if (mask & (1 << b) == 0) b]);
      }
    }
    return need;
  }
}
