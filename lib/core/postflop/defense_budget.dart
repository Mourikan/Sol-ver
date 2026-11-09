import 'dart:math' as math;
import 'dart:typed_data';

import '../evaluators/hand_evaluator.dart';
import '../models/game_state.dart';
import '../preflop/range_notation.dart';
import '../reads/gg_profiler.dart';
import 'geometry.dart';
import 'hand_tier.dart';
import 'postflop_ranges.dart';

/// Ranking de combos para defensa: realización + equity cruda + redraws.
class ComboStrength {
  ComboStrength._();

  static double score(int a, int b, List<int> board) {
    final r = HandTierClassifier.classify(a, b, board);
    final ev = HandEvaluator.evaluate([a, b, ...board]);
    final river = board.length >= 5;
    final outs = river
        ? 0.0
        : (r.flushDraw ? 9 : 0) + (r.oesd ? 8 : (r.gutshot ? 4 : 0)) + (r.overcards ? 3 : 0) + (r.backdoorFlush ? 1.5 : 0);
    final frac = (ev & 0xFFFFF) / (1 << 20);
    final unblock = river ? _missedSuitPenalty(a, b, board) : 0.0;
    return -unblock + switch (r.tier) {
      HandTier.nutsMonster => 6 + HandEvaluator.category(ev) / 10 + frac / 10,
      HandTier.strongTopPairOverpair => 5 + frac,
      HandTier.marginalMadeShowdown => 3 + ((ev >> 16) & 0xF) / 15 + outs * 0.03 + (ev & 0xFFFF) / (1 << 16) / 20,
      HandTier.highEquityComboDraw => 3 + outs * 0.05 + frac / 100,
      HandTier.backdoorBlockerBluff => 2 + outs * 0.05 + frac / 10,
      HandTier.airGiveUp => 1 + frac,
    };
  }

  /// River: penaliza bluff-catchers que bloquean el proyecto de color fallido del rival (prioriza unblockers).
  static double _missedSuitPenalty(int a, int b, List<int> board) {
    final turn = List<int>.filled(4, 0), fin = List<int>.filled(4, 0);
    for (var i = 0; i < board.length; i++) {
      if (i < 4) turn[board[i] & 3]++;
      fin[board[i] & 3]++;
    }
    for (var s = 0; s < 4; s++) {
      if (turn[s] >= 2 && fin[s] < 3) {
        final n = ((a & 3) == s ? 1 : 0) + ((b & 3) == s ? 1 : 0);
        return n * 0.04;
      }
    }
    return 0;
  }
}

class DefenseResult {
  const DefenseResult(this.continues, this.target, this.percentile, this.mdf);
  final bool continues;
  final double target;
  final double percentile;
  final double mdf;
}

/// DefenseBudget (Flop/Turn): defiende exactamente el top MDF x factor del rango de Hero que llega al nodo.
class DefenseBudget {
  DefenseBudget._();

  static final _cache = <String, List<(double, double)>>{};

  static double factor(ReadProfile r, Stake stake) => switch (r.archetype) {
        GgArchetype.agroSpewy => 1.15,
        GgArchetype.recPassiveFish when stake.index <= Stake.nl50.index => 0.82,
        GgArchetype.scaredMoneyReg when stake.index <= Stake.nl50.index => 0.90,
        _ => 1.0,
      };

  /// MDF por jugador en multiway: 1 - (1 - MDF_HU)^(1/N), N = defensores.
  static double perPlayerMdf(double mdfHu, int players) {
    final n = math.max(1, players - 1);
    return n == 1 ? mdfHu : 1 - math.pow(1 - mdfHu, 1 / n).toDouble();
  }

  static Float32List heroPreflopRange(GameState s) {
    if (s.potType == PotType.limped) return Float32List(169)..fillRange(0, 169, 1);
    final pfa = s.preflopAggressor!;
    final other = pfa == s.heroPosition ? s.villainPosition! : s.heroPosition;
    final (p, d) = PostflopRanges.forPot(pfa, other, s.potType, s.rakeTier);
    return pfa == s.heroPosition ? p : d;
  }

  static Float32List villainPreflopRange(GameState s) {
    if (s.potType == PotType.limped) return Float32List(169)..fillRange(0, 169, 1);
    final pfa = s.preflopAggressor!;
    final other = pfa == s.villainPosition ? s.heroPosition : s.villainPosition!;
    final (p, d) = PostflopRanges.forPot(pfa, other, s.potType, s.rakeTier);
    return pfa == s.villainPosition ? p : d;
  }

  /// Bote al inicio de cada calle reconstruido desde las acciones.
  static Map<Street, double> potsByStreet(GameState s) {
    final committed = <Position, double>{Position.sb: 0.5, Position.bb: 1.0};
    var current = 1.0;
    for (final a in s.actions.where((a) => a.street == Street.preflop)) {
      if (a.isAggressive) {
        committed[a.actor] = a.amountBb;
        current = a.amountBb;
      } else if (a.type == ActionType.call) {
        committed[a.actor] = current;
      }
    }
    var pot = committed.values.fold<double>(0, (x, y) => x + y);
    final out = <Street, double>{};
    for (final st in [Street.flop, Street.turn, Street.river]) {
      out[st] = pot;
      final c = <Position, double>{};
      var cur = 0.0;
      for (final a in s.actions.where((a) => a.street == st)) {
        if (a.isAggressive) {
          c[a.actor] = a.amountBb;
          cur = a.amountBb;
        } else if (a.type == ActionType.call) {
          c[a.actor] = cur;
        }
      }
      pot += c.values.fold<double>(0, (x, y) => x + y);
    }
    out[s.street] = s.potBb ?? out[s.street]!;
    return out;
  }

  /// Combos (clave a*52+b) y peso del rango de Hero al inicio de la calle actual.
  static Map<int, double> heroRangeAtStreet(GameState s, ReadProfile r) {
    final pre = heroPreflopRange(s);
    final boardAll = [for (final c in s.board) c.id];
    final dead = boardAll.fold<int>(0, (m, c) => m | (1 << c));
    var range = <int, double>{};
    for (var i = 0; i < 169; i++) {
      if (pre[i] <= 0) continue;
      for (final (a, b) in Matrix169.concreteCombos(i)) {
        if (dead & ((1 << a) | (1 << b)) != 0) continue;
        range[a < b ? a * 52 + b : b * 52 + a] = pre[i].toDouble();
      }
    }
    final pots = potsByStreet(s);
    for (final st in [Street.flop, Street.turn]) {
      if (st.index >= s.street.index) break;
      final acts = s.actions.where((a) => a.street == st).toList();
      final vBet = acts.where((a) => a.actor == s.villainPosition && a.isAggressive).lastOrNull;
      final heroCalled = acts.any((a) => a.actor == s.heroPosition && a.type == ActionType.call);
      if (vBet == null || !heroCalled) continue;
      final heroIn = acts.where((a) => a.actor == s.heroPosition && a.isAggressive).lastOrNull?.amountBb ?? 0;
      final potBefore = pots[st]! + 2 * heroIn;
      final mdf = perPlayerMdf(PotGeometry.mdf(potBefore, vBet.amountBb - heroIn), s.activePlayers);
      final board = boardAll.sublist(0, st == Street.flop ? 3 : 4);
      range = _top(range, board, math.min(1.0, mdf * factor(r, s.stake)));
    }
    return range;
  }

  static Map<int, double> _top(Map<int, double> range, List<int> board, double frac) {
    final scored = [for (final e in range.entries) (e.key, e.value, ComboStrength.score(e.key ~/ 52, e.key % 52, board))]
      ..sort((x, y) => y.$3.compareTo(x.$3));
    final total = range.values.fold<double>(0, (x, y) => x + y);
    final out = <int, double>{};
    var acc = 0.0;
    for (final (k, w, _) in scored) {
      if (acc >= frac * total) break;
      out[k] = w;
      acc += w;
    }
    return out;
  }

  static String _key(GameState s, ReadProfile r, double call) => [
        s.board.join(),
        s.heroPosition.name,
        s.villainPosition?.name,
        s.stake.name,
        s.activePlayers,
        r.archetype.name,
        call.toStringAsFixed(2),
        s.potBb?.toStringAsFixed(2),
        for (final a in s.actions) '${a.street.index}${a.actor.index}${a.type.index}${a.amountBb}',
      ].join('|');

  /// Evalúa si la mano de Hero entra en el presupuesto de defensa del nodo actual.
  static DefenseResult evaluate(GameState s, ReadProfile r, {required double potBeforeBet, required double call}) {
    final mdf = perPlayerMdf(PotGeometry.mdf(potBeforeBet, call), s.activePlayers);
    final target = math.min(1.0, mdf * factor(r, s.stake));
    final board = [for (final c in s.board) c.id];
    final sorted = _cache.putIfAbsent(_key(s, r, call), () {
      if (_cache.length > 512) _cache.clear();
      final range = heroRangeAtStreet(s, r);
      final list = [for (final e in range.entries) (ComboStrength.score(e.key ~/ 52, e.key % 52, board), e.value)]
        ..sort((x, y) => y.$1.compareTo(x.$1));
      return list;
    });
    final total = sorted.fold<double>(0, (x, y) => x + y.$2);
    final mine = ComboStrength.score(s.hero!.high.id, s.hero!.low.id, board);
    var above = 0.0;
    for (final (sc, w) in sorted) {
      if (sc > mine) above += w;
    }
    final pct = total == 0 ? 0.0 : above / total;
    return DefenseResult(pct < target, target, pct, mdf);
  }

  /// Percentil (0 = mejor) de la mano de Hero dentro de su propio rango actual.
  static double percentile(GameState s, ReadProfile r) =>
      evaluate(s, r, potBeforeBet: 1, call: 0).percentile;
}
