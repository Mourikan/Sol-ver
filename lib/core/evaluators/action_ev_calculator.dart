import 'dart:math' as math;

import '../models/game_state.dart';
import '../postflop/eqr_table.dart';
import '../postflop/hand_tier.dart';
import '../postflop/range_equity.dart';
import '../preflop/preflop_ranges_db.dart';
import '../reads/gg_profiler.dart';
import '../reads/mda_consensus_db.dart';
import '../reads/range_funnel.dart';

/// EV aproximado (bb) de cada acción legal. Modelo de una calle (showdown con EQR calibrado), no árbol completo.
class ActionEVs {
  const ActionEVs({
    required this.fold,
    required this.checkCall,
    required this.betRaise,
    required this.betSizeBb,
    required this.foldEquity,
    required this.equity,
    required this.equityVsContinue,
    required this.eqr,
    required this.facingBet,
  });

  final double fold;
  final double checkCall;
  final double betRaise;
  final double betSizeBb;
  final double foldEquity;
  final double equity;
  final double equityVsContinue;
  final double eqr;
  final bool facingBet;

  double get best => math.max(fold, math.max(checkCall, betRaise));

  Map<String, double> toMap() => {'fold': fold, facingBet ? 'call' : 'check': checkCall, 'betRaise': betRaise};
}

class ActionEvCalculator {
  ActionEvCalculator._();

  static const samples = 300;

  /// Caché O(1) de showdowns por (rango del nodo, mano de Hero): la puerta de EV, el ancla Nash y exploitDeltaEV
  /// reutilizan el mismo muestreo determinista dentro de una decisión (resultado idéntico, sin recomputar Monte Carlo).
  static final _shotCache = <String, List<(int, double)>>{};

  /// ¿El villano continúa contra una apuesta de fracción [f] del bote con este tier? (perfil: station/fish pagan con
  /// cualquier par; maniac paga showdown hasta bote).
  static bool continues(HandTier t, double f, {required bool river, VillainProfile vp = VillainProfile.gtoBase}) {
    final station = vp == VillainProfile.callingStation;
    final agro = vp == VillainProfile.maniac || vp == VillainProfile.regAgro;
    return switch (t) {
      HandTier.nutsMonster || HandTier.strongTopPairOverpair || HandTier.highEquityComboDraw => true,
      HandTier.marginalMadeShowdown => station || f <= (agro ? 1.0 : 0.5),
      HandTier.backdoorBlockerBluff => !river && (station || f <= 0.33),
      HandTier.airGiveUp => false,
    };
  }

  static int _ord(HandTier t) => switch (t) {
        HandTier.airGiveUp => 0,
        HandTier.backdoorBlockerBluff => 1,
        HandTier.highEquityComboDraw => 2,
        HandTier.marginalMadeShowdown => 3,
        HandTier.strongTopPairOverpair => 4,
        HandTier.nutsMonster => 5,
      };

  /// Fold_Equity_Real: combos que foldean en el rango real del villano, modulado por perfil.
  static double foldEquity(double rawFe, double alpha, ReadProfile read, VillainProfile vp,
      {required bool river, required bool capped, bool secondBarrel = false, double betFraction = 0.5}) {
    if ((read.archetype == GgArchetype.recPassiveFish || vp == VillainProfile.callingStation) && river) return 0.05;
    if (read.archetype == GgArchetype.poolDefault || vp == VillainProfile.poolDefault) {
      // Pool paga de más vs apuestas pequeñas de River => techo de FE; foldea de más vs double barrel => suelo de FE.
      if (river && betFraction <= MDAParameters.smallBetMaxFraction) return math.min(rawFe, 1 - MDAParameters.riverCallEfficiencyVsSmallBet);
      if (secondBarrel) return math.max(rawFe, MDAParameters.turnOverfoldVsDoubleBarrel);
      return rawFe;
    }
    if (read.archetype == GgArchetype.scaredMoneyReg && capped) return math.min(0.85, alpha * 1.35);
    return switch (vp) {
      VillainProfile.callingStation => rawFe * 0.5,
      VillainProfile.nit => math.min(0.9, rawFe * 1.2),
      VillainProfile.maniac || VillainProfile.regAgro => rawFe * 0.7,
      VillainProfile.trapperPremium => rawFe * 0.5,
      _ => rawFe,
    }.clamp(0.0, 0.95);
  }

  /// Future_Bluff_Capture_EV (horizonte 2 calles): tras pagar en Flop/Turn vs Reg/Agro, fracción de faroles que el rival
  /// seguirá apostando en la siguiente calle (acotada por el ratio de indiferencia del sizing siguiente), ponderada por
  /// unblockers (no tener cartas del proyecto del rival) y por nuestra probabilidad de seguir en la mano.
  static double futureBluffCapture(GameState s, ({List<(int, int)> combos, List<double> weights, List<HandTier> tiers}) vc, double eq,
      {required double potAfterCall}) {
    if (s.street == Street.river) return 0;
    final vp = s.villainProfile;
    final regOrAgro = vp == VillainProfile.gtoBase || vp == VillainProfile.regAgro || vp == VillainProfile.maniac;
    if (!regOrAgro) return 0;
    var tot = 0.0, bluffs = 0.0;
    for (var k = 0; k < vc.combos.length; k++) {
      tot += vc.weights[k];
      final t = vc.tiers[k];
      if (t == HandTier.airGiveUp || t == HandTier.backdoorBlockerBluff || t == HandTier.highEquityComboDraw) bluffs += vc.weights[k];
    }
    if (tot == 0) return 0;
    final b = bluffs / tot;
    final b2 = 0.66 * potAfterCall;
    final alpha2 = b2 / (potAfterCall + 2 * b2);
    final bluffBets = math.min(b, (1 - b) * alpha2 / (1 - alpha2));
    final suits = List<int>.filled(4, 0);
    for (final c in s.board) {
      suits[c.suit.index]++;
    }
    final drawSuit = suits.indexWhere((n) => n == 2);
    final blocking = drawSuit < 0 ? 0 : [s.hero!.high, s.hero!.low].where((c) => c.suit.index == drawSuit).length;
    final unblock = 1 - 0.25 * blocking;
    return bluffBets * b2 * unblock * eq.clamp(0.0, 1.0);
  }

  static double _rake(GameState s, double finalPot) => RakeConfig.byStake[s.stake]!.rakeOn(finalPot);

  /// [potBefore] = bote antes de la apuesta del villano (incluye lo ya comprometido por ambos en la calle);
  /// [toCall] = lo que Hero debe pagar; [betSizeBb] = tamaño de nuestra apuesta (o raise-to) candidata.
  static ActionEVs postflop(GameState s, ReadProfile read,
      {required double potBefore,
      required double toCall,
      required double betSizeBb,
      bool exactSize = false,
      double? foldEquityOverride,
      double? villainBluffShare}) {
    final river = s.street == Street.river;
    final pool = read.archetype == GgArchetype.poolDefault || s.villainProfile == VillainProfile.poolDefault;
    final multiwayCbet = pool && toCall > 0 && s.street == Street.flop && s.activePlayers >= 3;
    final vc = RangeEquity.villainCombos(s, valuePrior: multiwayCbet ? MDAParameters.flopCbetHonestyMultiway : null);
    final secondBarrel = s.street == Street.turn && toCall == 0 &&
        s.actions.any((a) => a.street == Street.flop && a.actor == s.heroPosition && a.isAggressive);
    final shotKey = '${identityHashCode(vc.combos)}|${s.hero!.mask}|$samples';
    final shots = _shotCache[shotKey] ??= RangeEquity.sampleShowdowns(s, vc.combos, vc.weights, samples);
    if (_shotCache.length > 64) _shotCache.remove(_shotCache.keys.first);
    final ip = s.heroPosition.isInPositionVs(s.villainPosition!);
    final spr = (s.effectiveStackBb ?? 100) / (s.potBb ?? 1);
    final eqr = EqrTable.factor(s.hero!.index169, ip: ip, spr: spr);
    final eqAll = shots.isEmpty ? 1.0 : shots.fold<double>(0, (a, x) => a + x.$2) / shots.length;

    final facing = toCall > 0;
    final potNow = potBefore + toCall;
    final capped = s.board.length >= 3 && RangeFunnel.track(s).isCapped;
    final vp = s.villainProfile;

    final order = List<int>.generate(vc.combos.length, (k) => k)..sort((a, b) => _ord(vc.tiers[a]).compareTo(_ord(vc.tiers[b])));

    /// EV de apostar/subir a [size] (bb): fold equity = combos que foldean (los más débiles primero) => equity vs el resto.
    (double, double, double) betEv(double size) {
      final f = facing ? (size - toCall) / (potNow + toCall) : size / potNow;
      var tot = 0.0, folds = 0.0;
      for (var k = 0; k < vc.combos.length; k++) {
        tot += vc.weights[k];
        if (!continues(vc.tiers[k], f, river: river, vp: vp)) folds += vc.weights[k];
      }
      final rawFe = tot == 0 ? 0.0 : folds / tot;
      final alpha = size / (potNow + size);
      // Terminaciones T1-T6: FE del perfil en la línea (prior declarado) sustituye al FE genérico.
      final fe = foldEquityOverride ?? foldEquity(rawFe, alpha, read, vp, river: river, capped: capped, secondBarrel: secondBarrel, betFraction: f);
      // Retira el FE% más débil del rango (orden por tier) y mide la equity contra lo que paga.
      final foldW = List<double>.filled(vc.combos.length, 0);
      var acc = 0.0;
      for (final k in order) {
        final need = fe * tot - acc;
        if (need <= 0) break;
        final take = need < vc.weights[k] ? need : vc.weights[k];
        foldW[k] = take / vc.weights[k];
        acc += take;
      }
      var cw = 0.0, cs = 0.0;
      for (final (idx, r) in shots) {
        final keep = 1 - foldW[idx];
        cw += keep;
        cs += keep * r;
      }
      final eqCont = cw == 0 ? eqAll : cs / cw;
      final fin = facing ? potBefore + 2 * size : potNow + 2 * size;
      return (fe * potNow + (1 - fe) * (eqCont * eqr * (fin - _rake(s, fin)) - size), fe, eqCont);
    }

    final double cc;
    if (facing) {
      final fin = potNow + toCall;
      // T2: bluff-catcher puro vs rango polar sub-faroleado => solo gana contra la cuota real de faroles.
      cc = villainBluffShare != null
          ? villainBluffShare * (fin - _rake(s, fin)) - toCall
          : eqAll * eqr * (fin - _rake(s, fin)) - toCall + futureBluffCapture(s, vc, eqAll, potAfterCall: fin);
    } else {
      final vp = s.villainProfile;
      final stab = vp == VillainProfile.maniac || vp == VillainProfile.regAgro ? futureBluffCapture(s, vc, eqAll, potAfterCall: potNow) : 0.0;
      cc = eqAll * eqr * (potNow - _rake(s, potNow)) + stab;
      // Villain_Stab_Capture (Agro/Maniac): tras nuestro check el agro apuesta su cuota de faroles (acotada por α geométrico,
      // mismo modelo que Future_Bluff_Capture); Hero la captura con su equity. Solo Flop/Turn.
    }
    final stack = s.effectiveStackBb ?? double.infinity;
    // exactSize: EV del tamaño pedido (auditoría Δ EV por sizing); por defecto argmax sobre sizings candidatos.
    final sizes = exactSize
        ? {betSizeBb}
        : facing
            ? {betSizeBb, toCall * 2.5, toCall * 3}
            : {betSizeBb, potNow * 0.33, potNow * 0.66, potNow};
    var best = betEv(betSizeBb);
    var bestSize = betSizeBb;
    for (final sz in sizes) {
      final x = math.min(sz, stack);
      final e = betEv(x);
      if (e.$1 > best.$1) {
        best = e;
        bestSize = x;
      }
    }
    final br = best.$1, fe = best.$2, eqCont = best.$3;
    final S = bestSize;
    return ActionEVs(
      fold: 0,
      checkCall: cc,
      betRaise: br,
      betSizeBb: S,
      foldEquity: fe,
      equity: eqAll,
      equityVsContinue: eqCont,
      eqr: eqr,
      facingBet: facing,
    );
  }
}
