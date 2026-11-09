import '../evaluators/hand_evaluator.dart';
import '../models/game_state.dart';
import '../postflop/hand_tier.dart';
import '../reads/gg_profiler.dart';
import '../reads/range_funnel.dart';
import 'timing_tells_matrix.dart';

enum ConversionMode { none, polarizedOverbetBluff, riverCheckRaiseBluff }

class ConversionResult {
  const ConversionResult(this.gateActive, this.mode, this.sizePct, this.reasons);
  final bool gateActive;
  final ConversionMode mode;
  final double sizePct;
  final List<String> reasons;
  bool get converts => mode != ConversionMode.none;
}

/// Turn_SDV_Into_Bluff: showdown marginal -> farol polarizado con nut blocker vs rango capado.
class BlockerBluffConverter {
  BlockerBluffConverter._();

  static const overbetPct = 125.0;

  static bool gate(ReadProfile r, Stake stake) => switch (r.archetype) {
        GgArchetype.recPassiveFish || GgArchetype.trapperLimpReraiser || GgArchetype.agroSpewy => false,
        GgArchetype.scaredMoneyReg => true,
        GgArchetype.unknownReg => stake.index >= Stake.nl25.index,
      };

  static ConversionResult evaluate(GameState s, ReadProfile read, {required bool heroCanBet}) {
    final reasons = <String>[];
    if (!gate(read, s.stake)) {
      return ConversionResult(false, ConversionMode.none, 0, ['Gate BLOQUEADO vs ${read.archetype.name}: 0% conversión']);
    }
    if (s.street == Street.flop) return const ConversionResult(true, ConversionMode.none, 0, ['Solo turn/river']);

    final tier = HandTierClassifier.classify(s.hero!.high.id, s.hero!.low.id, [for (final c in s.board) c.id]).tier;
    const convertible = {HandTier.marginalMadeShowdown, HandTier.backdoorBlockerBluff, HandTier.airGiveUp};
    final pairPos = _pairPos(s);
    final sdvLow = pairPos >= 2 && convertible.contains(tier);
    if (!sdvLow) return const ConversionResult(true, ConversionMode.none, 0, ['SDV suficiente (top/2nd pair o mejor)']);
    reasons.add('SDV insuficiente (${pairPos >= 99 ? 'sin par' : '${pairPos + 1}er par'}) < 25% vs rango de check-back/bet');

    final funnel = RangeFunnel.track(s);
    final timing = TimingTellsMatrix.lastVillain(s);
    final capped = funnel.isCapped || timing.capped || funnel.state == VillainRangeState.condensedDrawsAndPairs && timing.capped;
    if (!capped) return ConversionResult(true, ConversionMode.none, 0, [...reasons, 'Villano no capado (${funnel.state.name})']);
    reasons.add('Villano capado (${timing.capped ? timing.note : funnel.state.name})');

    final blocker = nutBlocker(s);
    if (blocker == null) return ConversionResult(true, ConversionMode.none, 0, [...reasons, 'Sin nut blocker']);
    reasons.add('Key blocker $blocker');

    final mode = heroCanBet ? ConversionMode.polarizedOverbetBluff : ConversionMode.riverCheckRaiseBluff;
    return ConversionResult(true, mode, overbetPct, reasons);
  }

  static int _pairPos(GameState s) {
    final ranks = {for (final c in s.board) c.rank.value}.toList()..sort((a, b) => b.compareTo(a));
    final h = s.hero!;
    if (h.isPair) {
      final above = ranks.where((r) => r > h.high.rank.value).length;
      return ranks.contains(h.high.rank.value) ? -1 : above;
    }
    var best = 99;
    for (final c in [h.high, h.low]) {
      final i = ranks.indexOf(c.rank.value);
      if (i >= 0 && i < best) best = i;
    }
    return best;
  }

  /// Carta alta libre del color (board con >=3 del palo) o rango que bloquea la escalera nuts / sets.
  static String? nutBlocker(GameState s) {
    final suits = List<int>.filled(4, 0);
    for (final c in s.board) {
      suits[c.suit.index]++;
    }
    final hero = [s.hero!.high, s.hero!.low];
    for (var fs = 0; fs < 4; fs++) {
      if (suits[fs] < 3) continue;
      final on = {for (final c in s.board) if (c.suit.index == fs) c.rank.value};
      final top = [for (var r = 14; r >= 2; r--) if (!on.contains(r)) r].first;
      for (final c in hero) {
        if (c.suit.index == fs && c.rank.value == top) return '$c (nut flush)';
      }
    }
    var mask = 0;
    for (final c in s.board) {
      mask |= 1 << (c.rank.value - 2);
    }
    var bestHigh = -1;
    final need = <int>{};
    for (var a = 0; a < 13; a++) {
      for (var b = a; b < 13; b++) {
        final hi = HandEvaluator.straightHigh(mask | (1 << a) | (1 << b));
        if (hi < 0 || HandEvaluator.straightHigh(mask) >= hi) continue;
        if (hi > bestHigh) {
          bestHigh = hi;
          need.clear();
        }
        if (hi == bestHigh) need.addAll([if (mask & (1 << a) == 0) a, if (mask & (1 << b) == 0) b]);
      }
    }
    for (final c in hero) {
      if (need.contains(c.rank.value - 2)) return '$c (bloquea escalera nuts)';
    }
    return null;
  }
}
