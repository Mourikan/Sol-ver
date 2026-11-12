import '../models/decision_output.dart';
import '../models/game_state.dart';
import '../reads/anti_counter_exploit_shield.dart';
import '../reads/gg_profiler.dart';
import '../reads/unmapped_spots_resolver.dart';
import 'hand_tier.dart';

/// Asimetría en flops monocolor y boards con 4 al color (priors del usuario, Fase 9.5). Nunca vs Reg_GTO.
class MonotoneFourFlushSolver {
  MonotoneFourFlushSolver._();

  static bool enabled = true; // interruptor de auditoría
  static const poolFoldVsSmallMonotone = 0.58;
  static const stabPct = 28.0, stealPct = 68.0;
  static const directOdds = 0.20;

  /// Palo con >= [n] cartas en [cards]; -1 si no hay.
  static int suitWith(List<Card> cards, int n) {
    final c = List<int>.filled(4, 0);
    for (final x in cards) {
      c[x.suit.index]++;
    }
    for (var k = 0; k < 4; k++) {
      if (c[k] >= n) return k;
    }
    return -1;
  }

  /// Hero tiene exactamente una carta del palo y es el nut o 2º nut (rangos libres más altos).
  static bool nutBlocker(GameState s, int suit) {
    final on = {for (final c in s.board) if (c.suit.index == suit) c.rank.value};
    final free = [for (var r = 14; r >= 2; r--) if (!on.contains(r)) r].take(2).toSet();
    final mine = [s.hero!.high, s.hero!.low].where((c) => c.suit.index == suit).toList();
    return mine.length == 1 && free.contains(mine.first.rank.value);
  }

  static bool heroHasSuit(GameState s, int suit) => s.hero!.high.suit.index == suit || s.hero!.low.suit.index == suit;

  /// ¿Fuera faroles sin carta del palo con 4 al color? (TurnRiverSolver).
  static bool killNoSuitBluff(GameState s, ReadProfile r) {
    if (!enabled || r.archetype == GgArchetype.unknownReg || s.board.length < 4) return false;
    final k = suitWith(s.board, 4);
    return k >= 0 && !heroHasSuit(s, k);
  }

  static SpotPlan? plan(GameState s, ReadProfile r, HandTierResult h, {required double potBefore, required double toCall}) {
    if (!enabled || r.archetype == GgArchetype.unknownReg || s.activeVillains.length >= 2) return null;
    final v = s.villainPosition!;
    final cur = [for (final a in s.actions) if (a.street == s.street) a];
    if (s.street == Street.flop) {
      final k = suitWith(s.board, 3);
      if (k < 0) return null;
      final heroPfa = s.preflopAggressor == s.heroPosition;
      if (toCall == 0 && heroPfa && s.stake.index <= Stake.nl100.index && nutBlocker(s, k)) {
        return SpotPlan('Monotone_Small_Stab', DecisionAction.betRaise,
            'Flop monocolor: pool foldea ~${(poolFoldVsSmallMonotone * 100).round()}% sin carta del palo; blocker nut/2nd => stab ${stabPct.round()}% (auto-profit si FE > 22%).',
            sizePct: stabPct, foldEquityOverride: poolFoldVsSmallMonotone);
      }
      final vAgg = cur.where((a) => a.actor == v && a.isAggressive).lastOrNull;
      final heroBet = cur.any((a) => a.actor == s.heroPosition && a.isAggressive);
      final donkPot = vAgg != null && !heroBet && potBefore > 0 && toCall / potBefore >= 0.75;
      final checkRaise = vAgg != null && heroBet;
      if (toCall > 0 && (checkRaise || donkPot) && s.stake.index <= Stake.nl50.index &&
          h.tier == HandTier.strongTopPairOverpair && !heroHasSuit(s, k) && !AntiCounterExploitShield.active(s.stake, r)) {
        final odds = toCall / (potBefore + 2 * toCall);
        if (odds > directOdds) {
          return SpotPlan('Monotone_Disciplined_Fold', DecisionAction.fold,
              'Monocolor sin carta del palo vs ${checkRaise ? 'check-raise' : 'donk pot'} (NL2-NL50): rango >80% flush/nut-FD => Disciplined_Fold (odds ${(odds * 100).round()}% > ${(directOdds * 100).round()}%).');
        }
      }
      return null;
    }
    final k4 = suitWith(s.board, 4);
    if (k4 < 0 || toCall > 0) return null;
    final prev = [for (final a in s.actions) if (a.street == Street.values[s.street.index - 1]) a];
    final checkedTwice = cur.any((a) => a.actor == v && a.type == ActionType.check) && prev.any((a) => a.actor == v && a.type == ActionType.check);
    final insta = cur.any((a) => a.actor == v && a.type == ActionType.check && a.timing == TimingTell.instaAction);
    final fourthNow = suitWith(s.board.sublist(0, s.board.length - 1), 4) < 0;
    if ((checkedTwice || (insta && fourthNow)) && nutBlocker(s, k4)) {
      return SpotPlan('FourFlush_Blocker_Steal', DecisionAction.betRaise,
          '4 al color: villano pasa ${insta ? '(insta-check en la 4ª carta)' : 'dos veces'} y Hero tiene la carta nut/2nd del palo => Blocker_Steal ${stealPct.round()}%.',
          sizePct: stealPct);
    }
    return null;
  }
}
