import 'dart:math' as math;

import '../models/game_state.dart';
import '../postflop/eqr_table.dart';
import '../postflop/hand_tier.dart';
import '../postflop/range_equity.dart';
import '../preflop/preflop_ranges_db.dart';
import '../reads/gg_profiler.dart';
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
  static double foldEquity(double rawFe, double alpha, ReadProfile read, VillainProfile vp, {required bool river, required bool capped}) {
    if ((read.archetype == GgArchetype.recPassiveFish || vp == VillainProfile.callingStation) && river) return 0.05;
    if (read.archetype == GgArchetype.scaredMoneyReg && capped) return math.min(0.85, alpha * 1.35);
    return switch (vp) {
      VillainProfile.callingStation => rawFe * 0.5,
      VillainProfile.nit => math.min(0.9, rawFe * 1.2),
      VillainProfile.maniac || VillainProfile.regAgro => rawFe * 0.7,
      VillainProfile.trapperPremium => rawFe * 0.5,
      _ => rawFe,
    }.clamp(0.0, 0.95);
  }

  static double _rake(GameState s, double finalPot) => RakeConfig.byStake[s.stake]!.rakeOn(finalPot);

  /// [potBefore] = bote antes de la apuesta del villano (incluye lo ya comprometido por ambos en la calle);
  /// [toCall] = lo que Hero debe pagar; [betSizeBb] = tamaño de nuestra apuesta (o raise-to) candidata.
  static ActionEVs postflop(GameState s, ReadProfile read, {required double potBefore, required double toCall, required double betSizeBb}) {
    final river = s.street == Street.river;
    final vc = RangeEquity.villainCombos(s);
    final shots = RangeEquity.sampleShowdowns(s, vc.combos, vc.weights, samples);
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
      final fe = foldEquity(rawFe, alpha, read, vp, river: river, capped: capped);
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
      cc = eqAll * eqr * (fin - _rake(s, fin)) - toCall;
    } else {
      cc = eqAll * eqr * (potNow - _rake(s, potNow));
    }
    final stack = s.effectiveStackBb ?? double.infinity;
    final sizes = facing
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
