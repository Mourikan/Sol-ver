import '../evaluators/action_ev_calculator.dart';
import '../models/decision_output.dart';
import '../models/game_state.dart';
import '../reads/gg_profiler.dart';
import '../reads/mental_state_modulator.dart';
import '../reads/unmapped_spots_resolver.dart';
import 'hand_tier.dart';
import 'range_equity.dart';

/// Sizing anzuelo con Nuts vs perfiles agresivos (Maniac, tilt o aggression ratio >= 0.85). EV_Bait incluye la
/// captura del bluff-raise inducido (prior del usuario: el agresivo sube de farol ~30% de su aire ante apuesta pequeña).
class BaitInduceEngine {
  BaitInduceEngine._();

  static const baitPct = 25.0, bigPct = 75.0;
  static const bigSizes = [75.0, 100.0, 125.0];
  /// Prior calibrable del usuario: fracción del aire que hace spazz-raise ante apuesta pequeña. Con 0.30 el anzuelo no
  /// supera a la mejor apuesta grande en ninguno de 273 spots auditados (el motor no lo fuerza).
  static double inducedRaiseFreq = 0.30;
  static const raiseMult = 3.0;

  static bool target(ReadProfile r) =>
      r.archetype == GgArchetype.agroSpewy || MentalStateModulator.tilt(r) || (r.aggressionRatio ?? 0) >= 0.85;

  /// (EV apuesta grande, EV anzuelo) o null si no aplica.
  static (double, double)? evaluate(GameState s, ReadProfile r, HandTierResult h, {required double pot}) {
    if (h.tier != HandTier.nutsMonster || !target(r) || (s.street != Street.turn && s.street != Street.river)) return null;
    // Rival: el MEJOR sizing grande (75/100/125%), no solo el 75%.
    var big = double.negativeInfinity;
    for (final pct in bigSizes) {
      final e = ActionEvCalculator.postflop(s, r, potBefore: pot, toCall: 0, betSizeBb: pot * pct / 100, exactSize: true).betRaise;
      if (e > big) big = e;
    }
    final small = pot * baitPct / 100;
    final base = ActionEvCalculator.postflop(s, r, potBefore: pot, toCall: 0, betSizeBb: small, exactSize: true).betRaise;
    final vc = RangeEquity.villainCombos(s);
    var tot = 0.0, air = 0.0;
    for (var k = 0; k < vc.combos.length; k++) {
      tot += vc.weights[k];
      if (vc.tiers[k] == HandTier.airGiveUp || vc.tiers[k] == HandTier.backdoorBlockerBluff) air += vc.weights[k];
    }
    var airShare = tot == 0 ? 0.0 : air / tot;
    if (MentalStateModulator.tilt(r)) airShare = (airShare * (1 + MentalStateModulator.tiltBluffBoost)).clamp(0.0, 1.0);
    final induced = airShare * inducedRaiseFreq * (raiseMult * small);
    return (big, base + induced);
  }

  static SpotPlan? plan(GameState s, ReadProfile r, HandTierResult h, {required double pot, required double toCall}) {
    if (toCall > 0) return null;
    final e = evaluate(s, r, h, pot: pot);
    if (e == null || e.$2 <= e.$1) return null;
    return SpotPlan('Bait_Induce', DecisionAction.betRaise,
        'ANZUELO INDUCTOR (+${(e.$2 - e.$1).toStringAsFixed(2)}bb vs apuesta grande): sizing ${baitPct.round()}% con Nuts para inducir spazz-raise.',
        sizePct: baitPct);
  }
}
