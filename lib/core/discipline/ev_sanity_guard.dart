import 'dart:math' as math;

import '../evaluators/hand_evaluator.dart';
import '../models/decision_output.dart';
import '../models/game_state.dart';
import '../postflop/hand_tier.dart';
import '../reads/gg_profiler.dart';

/// EV_Sanity_Guard: interceptor final contra jugadas -EV evidentes.
class EvSanityGuard {
  EvSanityGuard._();

  static const tag = '[SANITY_GUARD_APPLIED]';
  static const blockerBluffs = {'A5s', 'A4s', 'A3s', 'A2s', 'K9s'};
  static const allInDirectOddsMax = 0.28;
  static const setFoldOddsMax = 0.35;

  static bool board4Flush(List<Card> b) {
    final c = List<int>.filled(4, 0);
    for (final x in b) {
      c[x.suit.index]++;
    }
    return c.reduce(math.max) >= 4;
  }

  static bool board4Straight(List<Card> b) {
    var mask = 0;
    for (final c in b) {
      mask |= 1 << (c.rank.value - 2);
    }
    for (var r = 0; r < 13; r++) {
      if (mask & (1 << r) != 0) continue;
      if (HandEvaluator.straightHigh(mask | (1 << r)) >= 0) return true;
    }
    return false;
  }

  static DecisionOutput _fix(DecisionOutput d, DecisionAction a, String why, {Sizing? sizing}) => DecisionOutput(
        action: a,
        sizing: sizing,
        freqGto: d.freqGto,
        metrics: d.metrics,
        justificacionGto: d.justificacionGto,
        ajusteExplotativoRead: '$tag $why | original: ${d.action.name}. ${d.ajusteExplotativoRead}',
      );

  static DecisionOutput postflop(GameState s, ReadProfile read, DecisionOutput d, HandTierResult h,
      {required double toCall, required double potBeforeBet}) {
    final vp = s.villainProfile;
    final cat = HandEvaluator.category(HandEvaluator.evaluate([s.hero!.high.id, s.hero!.low.id, for (final c in s.board) c.id]));
    final setPlus = h.tier == HandTier.nutsMonster && cat >= HandEvaluator.trips;
    final odds = toCall > 0 ? toCall / (potBeforeBet + 2 * toCall) : 0.0;
    final callSizing = toCall > 0 ? Sizing(bb: toCall, potPct: toCall / potBeforeBet * 100) : null;
    final agro = read.archetype == GgArchetype.agroSpewy || vp == VillainProfile.maniac || vp == VillainProfile.regAgro;
    final nutDraw = h.nutFlushDraw || (h.flushDraw && h.oesd);

    if (d.action == DecisionAction.fold && toCall > 0) {
      final safeBoard = !board4Flush(s.board) && !board4Straight(s.board);
      if (setPlus && safeBoard && odds < setFoldOddsMax) {
        return _fix(d, DecisionAction.call, 'Fold de Set+ en board sin 4-flush/4-straight con pot odds ${(odds * 100).round()}% < 35%.', sizing: callSizing);
      }
      if (s.street == Street.turn && (setPlus || nutDraw)) {
        return _fix(d, DecisionAction.call, 'Prohibido foldear Sets/Nut-Draws en Turn.', sizing: callSizing);
      }
      if (agro && (setPlus || nutDraw)) {
        return _fix(d, DecisionAction.call, 'Prohibido foldear Sets/Nut-Draws vs Agro/Maniac.', sizing: callSizing);
      }
    }

    final isBet = d.action == DecisionAction.betRaise && toCall == 0;
    const bluffTiers = {HandTier.airGiveUp, HandTier.backdoorBlockerBluff, HandTier.highEquityComboDraw};
    final fish = read.archetype == GgArchetype.recPassiveFish || vp == VillainProfile.callingStation;
    if (isBet && s.street == Street.river && fish && bluffTiers.contains(h.tier)) {
      return _fix(d, DecisionAction.check, 'Prohibido farolear River vs CallingStation/Fish.');
    }
    final trapper = read.archetype == GgArchetype.trapperLimpReraiser || vp == VillainProfile.trapperPremium;
    if (isBet && trapper && (h.tier == HandTier.airGiveUp || h.tier == HandTier.backdoorBlockerBluff)) {
      return _fix(d, DecisionAction.check, 'Prohibido c-betear aire vs Trapper_Limp_Reraiser.');
    }
    return d;
  }

  static DecisionOutput preflop(GameState s, DecisionOutput d, String handClass, {required double callBb, required double potBb}) {
    if (d.action != DecisionAction.call || s.effectiveStackBb == null) return d;
    final allIn = callBb >= s.effectiveStackBb! * 0.9 || (d.sizing?.bb ?? 0) >= s.effectiveStackBb! * 0.9;
    if (!allIn || !blockerBluffs.contains(handClass)) return d;
    final odds = callBb / (potBb + callBb);
    if (odds <= allInDirectOddsMax) return d;
    return _fix(d, DecisionAction.fold, '$handClass es 4-bet bluff, no call-off all-in (pot odds ${(odds * 100).round()}% > 28%).');
  }
}
