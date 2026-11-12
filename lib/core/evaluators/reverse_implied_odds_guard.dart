import '../models/decision_output.dart';
import '../models/game_state.dart';
import '../postflop/hand_tier.dart';
import '../postflop/range_equity.dart';
import '../reads/gg_profiler.dart';
import '../reads/unmapped_spots_resolver.dart';

/// Guardia de dominación inversa (RIO): top pair A/K/Q con kicker <= J frente a multi-barril de un perfil honesto.
/// Kicker_Domination_Share = fracción del rango de VALOR del villano (TopPair+) que nos supera: mismo par con mejor
/// kicker + dos pares/sets/escaleras/colores (rango de línea del motor, sin cartas bloqueadas por Hero).
class ReverseImpliedOddsGuard {
  ReverseImpliedOddsGuard._();

  static const threshold = 0.58;
  static const badge = '[⚠️ RIESGO RIO: KICKER DOMINADO]';

  /// Nit / Scared_Reg / Pool_Default. Unknown_Reg (Reg_GTO) excluido: el ancla Nash no se toca (aplicarlo subía el
  /// Δ Nash de River de 2.4% a 8.8% y rompía 3 checks de metric_audit).
  static bool _profile(ReadProfile r) => r.archetype == GgArchetype.scaredMoneyReg || r.archetype == GgArchetype.poolDefault;

  static bool _multiBarrel(GameState s) {
    final v = s.villainPosition!;
    final streets = {for (final a in s.actions) if (a.actor == v && a.isAggressive && a.street != Street.preflop) a.street};
    return streets.length >= 2;
  }

  /// (share de dominación, P(ganar) vs todo su rango de apuesta) o null si el spot no aplica.
  static (double, double)? evaluate(GameState s, ReadProfile r, HandTierResult h) {
    if (s.hero == null || s.villainPosition == null || (s.street != Street.turn && s.street != Street.river)) return null;
    if (!_profile(r) || !_multiBarrel(s) || h.tier != HandTier.strongTopPairOverpair) return null;
    final top = s.board.map((c) => c.rank.value).reduce((a, b) => a > b ? a : b);
    final hc = [s.hero!.high, s.hero!.low];
    final pairCard = hc.where((c) => c.rank.value == top).firstOrNull;
    if (pairCard == null || top < Rank.queen.value) return null;
    final kicker = hc.firstWhere((c) => !identical(c, pairCard)).rank.value;
    if (kicker > Rank.jack.value || kicker == top) return null;
    final vc = RangeEquity.villainCombos(s);
    final mask = s.hero!.mask;
    var value = 0.0, beats = 0.0, all = 0.0;
    for (var k = 0; k < vc.combos.length; k++) {
      final (a, b) = vc.combos[k];
      if ((mask >> a) & 1 == 1 || (mask >> b) & 1 == 1) continue;
      final t = vc.tiers[k];
      all += vc.weights[k];
      if (t != HandTier.nutsMonster && t != HandTier.strongTopPairOverpair) continue;
      final w = vc.weights[k];
      value += w;
      if (t == HandTier.nutsMonster) {
        beats += w;
        continue;
      }
      final ra = (a >> 2) + 2, rb = (b >> 2) + 2;
      final other = ra == top ? rb : (rb == top ? ra : -1);
      if (other > kicker) beats += w;
    }
    return value == 0 || all == 0 ? null : (beats / value, 1 - beats / all);
  }

  static double? dominationShare(GameState s, ReadProfile r, HandTierResult h) => evaluate(s, r, h)?.$1;

  static SpotPlan? plan(GameState s, ReadProfile r, HandTierResult h, {required double toCall}) {
    final e = evaluate(s, r, h);
    if (e == null || e.$1 < threshold) return null;
    final share = e.$1;
    final why = '$badge ${(share * 100).round()}% de su rango de valor nos supera (mismo par con mejor kicker o 2P+) tras multi-barril: '
        'penalización RIO al EV del call.';
    // Contexto EV: con kicker dominado el call solo gana contra lo que no nos supera (P(ganar) del rango de apuesta).
    return toCall > 0
        ? SpotPlan('RIO_Guard', DecisionAction.fold, why, bluffShare: e.$2)
        : SpotPlan('RIO_Guard', DecisionAction.check, '$why Check (no construir bote con kicker dominado).');
  }
}
