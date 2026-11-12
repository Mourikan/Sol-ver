import '../models/decision_output.dart';
import '../models/game_state.dart';
import '../postflop/hand_tier.dart';
import '../postflop/range_equity.dart';
import '../preflop/range_notation.dart';
import 'gg_profiler.dart';
import 'unmapped_spots_resolver.dart';

/// Datos del min-3bet / click-back preflop.
class ClickBack {
  const ClickBack({required this.openBb, required this.threeBetBb, required this.heroInvestedBb, required this.potBb, required this.raiser});
  final double openBb, threeBetBb, heroInvestedBb, potBb;
  final Position raiser;
  double get callCostBb => threeBetBb - heroInvestedBb;
  double get directPotOdds => callCostBb / (potBb + callCostBb);
}

/// Decodificador de sizings anómalos (fuera del árbol estándar): min-3bet/click-back, 1bb/nano-bet, min-raise postflop.
/// Matemática exacta de pot odds + rango percibido declarado por el usuario (priors, no solver).
class FreakFishSizingDecoder {
  FreakFishSizingDecoder._();

  static const clickBackMaxMult = 2.2, nanoMaxFrac = 0.15, minRaiseMaxMult = 2.15;
  static const punishMult = 3.75; // 4-bet de castigo 3.5-4.0x el min-3bet
  static const nanoRaisePotFrac = 0.80; // raise al 75-90% del bote total
  static const clickBackNutShare = 0.35;
  static final clickBackMedium = RangeNotation.parse('77-TT,AJo,KQo,A2s-AJs,K9s-KJs,QTs,JTs,T9s,98s,87s,76s,65s');
  static final clickBackNuts = RangeNotation.parse('AA,KK');
  static final premium = RangeNotation.parse('QQ+,AKs,AKo');

  /// Min-3bet preflop: segundo raise <= 2.2x el open, Hero enfrentándolo.
  static ClickBack? clickBack(GameState s) {
    if (s.board.isNotEmpty) return null;
    final pre = [for (final a in s.actions) if (a.street == Street.preflop) a];
    final raises = [for (final a in pre) if (a.isAggressive) a];
    if (raises.length != 2) return null;
    final open = raises[0], tb = raises[1];
    if (tb.actor == s.heroPosition || tb.amountBb > open.amountBb * clickBackMaxMult) return null;
    final committed = <Position, double>{Position.sb: 0.5, Position.bb: 1.0};
    for (final a in pre) {
      if (a.isAggressive || a.type == ActionType.call) committed[a.actor] = a.amountBb;
    }
    final hero = committed[s.heroPosition] ?? 0;
    final pot = committed.values.fold<double>(0, (x, y) => x + y) + s.extraDeadMoneyBb;
    return ClickBack(openBb: open.amountBb, threeBetBb: tb.amountBb, heroInvestedBb: hero, potBb: pot, raiser: tb.actor);
  }

  static bool _playable(int i) {
    final l = Matrix169.label(i);
    final pair = l.length == 2;
    const ranks = '23456789TJQKA';
    final hi = ranks.indexOf(l[0]), lo = ranks.indexOf(l[1]);
    if (pair) return hi <= ranks.indexOf('J');
    final suited = l.endsWith('s');
    if (suited && l[0] == 'A') return true;
    if (suited && hi - lo == 1) return true;
    return hi >= ranks.indexOf('T') && lo >= ranks.indexOf('T');
  }

  /// Respuesta Max-EV al click-back: premium => 4-bet de castigo; jugable => call obligatorio (odds directas + implícitas).
  static DecisionOutput? preflopResponse(GameState s, int hand169) {
    final cb = clickBack(s);
    if (cb == null) return null;
    final odds = cb.directPotOdds;
    final alert = 'Min-3Bet de recreativo (Pot Odds regaladas del ${(odds * 100).toStringAsFixed(1)}%)';
    if (premium[hand169] > 0) {
      final to = cb.threeBetBb * punishMult;
      final cap = s.effectiveStackBb ?? 100;
      final size = to >= cap * 0.9 ? cap : to;
      return DecisionOutput(
        action: DecisionAction.betRaise,
        sizing: Sizing(bb: size, potPct: size / cb.potBb * 100),
        freqGto: const {DecisionAction.betRaise: 1.0},
        freqSource: FreqSource.pure,
        metrics: [KeyMetric(MetricType.potOdds, odds)],
        justificacionGto: '$alert | ${Matrix169.label(hand169)} premium lineal: Punish_4Bet_Big ${punishMult}x el min-3bet = ${size.toStringAsFixed(1)}bb.',
        ajusteExplotativoRead: 'Freak_Sizing ClickBack: cobra máximo valor de su rango medio inelástico y niega equidad multiway.',
      );
    }
    if (_playable(hand169) && odds <= 0.22) {
      return DecisionOutput(
        action: DecisionAction.call,
        sizing: Sizing(bb: cb.callCostBb, potPct: cb.callCostBb / cb.potBb * 100),
        freqGto: const {DecisionAction.call: 1.0},
        freqSource: FreqSource.pure,
        metrics: [KeyMetric(MetricType.potOdds, odds)],
        justificacionGto: '$alert: call ${cb.callCostBb.toStringAsFixed(1)}bb para ganar ${cb.potBb.toStringAsFixed(1)}bb.',
        ajusteExplotativoRead: 'Freak_Sizing ClickBack: call obligatorio por odds directas/implícitas con todo el rango jugable; '
            'precaución postflop ante posible trampa AA/KK si mete pot-bet.',
      );
    }
    return null;
  }

  /// Rango percibido del click-back (Unknown/Pool): 65% especulativo medio + 35% AA/KK, por combos.
  static List<double>? clickBackRange(GameState s, VillainProfile vp) {
    if (vp != VillainProfile.poolDefault && vp != VillainProfile.gtoBase) return null;
    if (clickBack(s) == null) return null;
    double combos(List<double> r) {
      var c = 0.0;
      for (var i = 0; i < 169; i++) {
        c += r[i] * Matrix169.combos(i);
      }
      return c;
    }
    final m = combos(clickBackMedium), n = combos(clickBackNuts);
    return [
      for (var i = 0; i < 169; i++)
        clickBackMedium[i] * (1 - clickBackNutShare) / m + clickBackNuts[i] * clickBackNutShare / n,
    ];
  }

  static bool isNano(double betBb, double potBefore) => betBb > 0 && (betBb <= 1.0 || betBb / potBefore < nanoMaxFrac);

  /// Hero apostó en la calle y el villano sube a <= 2.15x esa apuesta.
  static (double heroBet, double raiseTo)? minRaise(GameState s) {
    final cur = [for (final a in s.actions) if (a.street == s.street) a];
    final hb = cur.where((a) => a.actor == s.heroPosition && a.isAggressive).lastOrNull;
    if (hb == null) return null;
    final vr = cur.skip(cur.indexOf(hb) + 1).where((a) => a.actor == s.villainPosition && a.isAggressive).lastOrNull;
    if (vr == null || hb.amountBb <= 0 || vr.amountBb > hb.amountBb * minRaiseMaxMult) return null;
    return (hb.amountBb, vr.amountBb);
  }

  static const monsterAlert = '[🚨 MIN-RAISE TURN/RIVER = NUTTED MONSTER (>82% 2P/Set/Flush)]';

  /// Respuestas postflop (nunca vs Reg_GTO ni multiway).
  static SpotPlan? postflopPlan(GameState s, ReadProfile r, HandTierResult h, {required double potBefore, required double toCall}) {
    if (toCall <= 0 || r.archetype == GgArchetype.unknownReg || s.activeVillains.length >= 2) return null;
    final t = h.tier;
    final odds = toCall / (potBefore + 2 * toCall);
    final mr = minRaise(s);
    if (mr != null) {
      if (t == HandTier.nutsMonster) return null;
      if (s.street == Street.flop) {
        const defend = {HandTier.strongTopPairOverpair, HandTier.marginalMadeShowdown, HandTier.highEquityComboDraw};
        return defend.contains(t)
            ? SpotPlan('MinRaise_Flop', DecisionAction.call,
                'Min-raise en Flop (<= ${minRaiseMaxMult}x): rango mezclado protección/draws + 2P/sets; odds directas ${(odds * 100).round()}% => defender 1 par+ y draws.')
            : SpotPlan('MinRaise_Flop', DecisionAction.fold, 'Min-raise en Flop: sin par ni draw de 5+ outs no hay odds suficientes.');
      }
      final target = r.archetype == GgArchetype.recPassiveFish || r.archetype == GgArchetype.poolDefault || r.archetype == GgArchetype.scaredMoneyReg;
      if (!target || s.stake.index > Stake.nl50.index) return null;
      // Equity contra el rango "monstruo" (prior de valor 85%): Nutted_Unbalanced_Value.
      final eq = RangeEquity.realized(s, valuePrior: ReadProfile.nuttedDonkPrior);
      final why = '$monsterAlert Nutted_Unbalanced_Value: 0% re-bluff; equity vs su rango ${(eq * 100).round()}% vs odds ${(odds * 100).round()}%.';
      return eq >= odds && t == HandTier.highEquityComboDraw
          ? SpotPlan('MinRaise_Monster', DecisionAction.call, '$why Call solo por odds del proyecto.')
          : SpotPlan('MinRaise_Monster', DecisionAction.fold, '$why FOLD DISCIPLINADO.');
    }
    final vBet = [for (final a in s.actions) if (a.street == s.street && a.actor == s.villainPosition && a.isAggressive) a].lastOrNull;
    final heroBet = s.actions.any((a) => a.street == s.street && a.actor == s.heroPosition && a.isAggressive);
    // Los min-donks contra nuestra iniciativa siguen en DonkTellDecoder (raise 4.5-5bb, test AUDIT 2).
    if (vBet != null && !heroBet && isNano(toCall, potBefore) && !UnmappedSpotsResolver.isDonk(s)) {
      const value = {HandTier.nutsMonster, HandTier.strongTopPairOverpair, HandTier.highEquityComboDraw};
      if (value.contains(t)) {
        final to = nanoRaisePotFrac * (potBefore + toCall);
        return SpotPlan('Nano_Bet', DecisionAction.betRaise,
            '1bb / nano-bet (${(toCall / potBefore * 100).toStringAsFixed(1)}% pot) = check disfrazado: Normal_Value_Raise al ${(nanoRaisePotFrac * 100).round()}% del bote total (${to.toStringAsFixed(1)}bb), no 3x de 1bb.',
            raiseToBb: to);
      }
      final eq = RangeEquity.realized(s);
      return eq >= odds
          ? SpotPlan('Nano_Bet', DecisionAction.call, '1bb / nano-bet: odds directas ${(odds * 100).round()}% < equity realizada ${(eq * 100).round()}% => call.')
          : null;
    }
    return null;
  }
}
