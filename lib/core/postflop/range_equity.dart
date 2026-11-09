import '../evaluators/hand_evaluator.dart';
import '../models/game_state.dart';
import '../preflop/range_notation.dart';
import 'defense_budget.dart';
import 'eqr_table.dart';
import 'flop_lookup_table.dart';
import 'hand_tier.dart';

/// Equity real de Hero vs el rango del villano filtrado por su línea (Monte Carlo determinista).
class RangeEquity {
  RangeEquity._();

  /// Equity_Real = equity cruda x EQR(categoría, IP/OOP, SPR) (tabla calibrada por modelo, ver EqrTable).
  static double realized(GameState s, {double? valuePrior}) {
    final raw = vsVillainLine(s, valuePrior: valuePrior);
    final ip = s.heroPosition.isInPositionVs(s.villainPosition!);
    final spr = (s.effectiveStackBb ?? 100) / (s.potBb ?? 1);
    return (raw * EqrTable.factor(s.hero!.index169, ip: ip, spr: spr)).clamp(0.0, 1.0);
  }

  /// Peso residual de tiers fuera de la política del bucket (mezclas / desviaciones del villano).
  static const policyMix = 0.15;

  static double _lineWeight(HandTier t, {required bool bet, required bool called}) {
    if (bet) {
      return switch (t) {
        HandTier.marginalMadeShowdown || HandTier.airGiveUp => 0.4,
        HandTier.backdoorBlockerBluff => 0.6,
        _ => 1.0,
      };
    }
    if (called) return t == HandTier.airGiveUp ? 0.0 : 1.0;
    return 1.0;
  }

  /// Combos del villano (sin cartas muertas) ponderados por su línea; [tiers] = tier actual de cada combo.
  static final _vcCache = <String, ({List<(int, int)> combos, List<double> weights, List<HandTier> tiers})>{};

  /// Cacheado por nodo (sin las cartas de Hero: el muestreo rechaza los combos bloqueados por Hero).
  static ({List<(int, int)> combos, List<double> weights, List<HandTier> tiers}) villainCombos(GameState s, {double? valuePrior}) {
    final key = [
      s.board.join(),
      s.villainPosition?.name,
      s.heroPosition.name,
      s.stake.name,
      s.potType.name,
      valuePrior,
      for (final a in s.actions) '${a.street.index}${a.actor.index}${a.type.index}${a.amountBb}',
    ].join('|');
    return _vcCache.putIfAbsent(key, () {
      if (_vcCache.length > 256) _vcCache.clear();
      return _buildVillainCombos(s, valuePrior);
    });
  }

  static ({List<(int, int)> combos, List<double> weights, List<HandTier> tiers}) _buildVillainCombos(GameState s, double? valuePrior) {
    final range = DefenseBudget.villainPreflopRange(s);
    final ids = [for (final c in s.board) c.id];
    var dead = 0;
    for (final c in ids) {
      dead |= 1 << c;
    }
    final v = s.villainPosition!;
    StrategyClass? pfaClass;
    var trap = false;
    if (s.preflopAggressor == v && s.potType != PotType.limped && ids.length >= 3) {
      final node = FlopLookupTable.nodeOf(s.potType, pfaInPosition: v.isInPositionVs(s.heroPosition));
      final flop = s.board.sublist(0, 3);
      pfaClass = FlopLookupTable.strategy(FlopLookupTable.bucketOf(flop), node).strategy;
      trap = FlopLookupTable.trapActive(flop, node, pfa: v, defender: s.heroPosition);
    }
    final combos = <(int, int)>[];
    final weights = <double>[];
    final tiers = <HandTier>[];
    for (var i = 0; i < 169; i++) {
      if (range[i] <= 0) continue;
      for (final (a, b) in Matrix169.concreteCombos(i)) {
        if (dead & ((1 << a) | (1 << b)) != 0) continue;
        var w = range[i].toDouble();
        for (final st in [Street.flop, Street.turn, Street.river]) {
          if (st.index > s.street.index) break;
          final acts = s.actions.where((x) => x.street == st && x.actor == v).toList();
          if (acts.isEmpty) continue;
          final t = HandTierClassifier.classify(a, b, ids.sublist(0, st == Street.flop ? 3 : (st == Street.turn ? 4 : 5))).tier;
          final bet = acts.any((x) => x.isAggressive);
          if (st == Street.flop && bet && pfaClass != null) {
            w *= FlopLookupTable.betProbability(pfaClass, t, trap: trap).clamp(policyMix, 1.0);
          } else {
            w *= _lineWeight(t, bet: bet, called: acts.any((x) => x.type == ActionType.call));
          }
        }
        if (w <= 0) continue;
        combos.add((a, b));
        weights.add(w);
        tiers.add(ids.length >= 3 ? HandTierClassifier.classify(a, b, ids).tier : HandTier.airGiveUp);
      }
    }
    if (valuePrior != null && combos.isNotEmpty) {
      var m = 0.0, o = 0.0;
      for (var k = 0; k < weights.length; k++) {
        if (tiers[k] == HandTier.nutsMonster) {
          m += weights[k];
        } else {
          o += weights[k];
        }
      }
      if (m > 0 && o > 0) {
        final scale = m * (1 - valuePrior) / valuePrior / o;
        for (var k = 0; k < weights.length; k++) {
          if (tiers[k] != HandTier.nutsMonster) weights[k] *= scale;
        }
      }
    }
    return (combos: combos, weights: weights, tiers: tiers);
  }

  /// Monte Carlo determinista: devuelve por muestra (índice de combo del villano, resultado de Hero 0/0.5/1).
  static List<(int, double)> sampleShowdowns(GameState s, List<(int, int)> combos, List<double> weights, int samples) {
    if (combos.isEmpty) return const [];
    final ids = [for (final c in s.board) c.id];
    final hero = [s.hero!.high.id, s.hero!.low.id];
    var dead = 0;
    for (final c in [...ids, ...hero]) {
      dead |= 1 << c;
    }
    final cum = <double>[];
    var acc = 0.0;
    for (final w in weights) {
      cum.add(acc += w);
    }
    var seed = 0x2545F491 ^ (hero[0] * 53 + hero[1]) ^ ids.fold<int>(0, (h, c) => h * 31 + c);
    int rnd(int n) {
      seed ^= (seed << 13) & 0xFFFFFFFF;
      seed ^= seed >> 17;
      seed ^= (seed << 5) & 0xFFFFFFFF;
      return (seed & 0x7FFFFFFF) % n;
    }

    final need = 5 - ids.length;
    final cards = List<int>.filled(7, 0);
    final out = <(int, double)>[];
    var rejected = 0;
    for (var k = 0; k < samples; k++) {
      final x = rnd(1 << 30) / (1 << 30) * acc;
      var lo = 0, hi = cum.length - 1;
      while (lo < hi) {
        final m = (lo + hi) >> 1;
        if (cum[m] < x) {
          lo = m + 1;
        } else {
          hi = m;
        }
      }
      final (va, vb) = combos[lo];
      if (dead & ((1 << va) | (1 << vb)) != 0) {
        if (++rejected > samples * 20) break;
        k--;
        continue;
      }
      var d = dead | (1 << va) | (1 << vb);
      for (var j = 0; j < ids.length; j++) {
        cards[2 + j] = ids[j];
      }
      for (var j = 0; j < need; j++) {
        int c;
        do {
          c = rnd(52);
        } while (d & (1 << c) != 0);
        d |= 1 << c;
        cards[2 + ids.length + j] = c;
      }
      cards[0] = hero[0];
      cards[1] = hero[1];
      final hs = HandEvaluator.evaluate(cards, 7);
      cards[0] = va;
      cards[1] = vb;
      final vs = HandEvaluator.evaluate(cards, 7);
      out.add((lo, hs > vs ? 1.0 : (hs == vs ? 0.5 : 0.0)));
    }
    return out;
  }

  /// [valuePrior]: si se da (p.ej. 0.85 en pot-donk nutted), re-pondera el rango para que los monsters pesen ese prior.
  static double vsVillainLine(GameState s, {int samples = 600, double? valuePrior}) {
    final v = villainCombos(s, valuePrior: valuePrior);
    if (v.combos.isEmpty) return 1.0;
    final r = sampleShowdowns(s, v.combos, v.weights, samples);
    if (r.isEmpty) return 1.0;
    return r.fold<double>(0, (a, x) => a + x.$2) / r.length;
  }

  /// Nuts absolutas en River: ningún combo de 2 cartas posible supera a Hero (y Hero mejora al board).
  static bool isAbsoluteNuts(GameState s) {
    if (s.board.length < 5) return false;
    final ids = [for (final c in s.board) c.id];
    final hero = HandEvaluator.evaluate([s.hero!.high.id, s.hero!.low.id, ...ids]);
    if (hero <= HandEvaluator.evaluate(ids)) return false;
    final dead = s.deadMask;
    for (var a = 0; a < 52; a++) {
      if (dead & (1 << a) != 0) continue;
      for (var b = a + 1; b < 52; b++) {
        if (dead & (1 << b) != 0) continue;
        if (HandEvaluator.evaluate([a, b, ...ids]) > hero) return false;
      }
    }
    return true;
  }
}
