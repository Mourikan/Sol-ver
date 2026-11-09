import '../models/game_state.dart';

enum ActionTag { openLimp, limpReraisePreflop, checkCallFlopCheckTurn, barrelOffOnBricks }

enum GgArchetype { recPassiveFish, trapperLimpReraiser, scaredMoneyReg, agroSpewy, unknownReg }

class SmartHudInput {
  const SmartHudInput({this.vpip, this.pfr, this.threeBet, this.foldTo4Bet, required this.stackBb, this.autoRebuy = true});
  final double? foldTo4Bet;
  final double? vpip;
  final double? pfr;
  final double? threeBet;
  final double stackBb;
  final bool autoRebuy;
}

/// Read resultante. Los priors (85%, 70%) son lecturas poblacionales especificadas por el usuario, no frecuencias de solver.
class ReadProfile {
  const ReadProfile(this.archetype, this.reasons, {this.threeBet, this.foldTo4Bet});

  final GgArchetype archetype;
  final List<String> reasons;
  final double? threeBet;
  final double? foldTo4Bet;

  /// 4-bet bluff habilitado: reg/GTO con fold-to-4bet >= 45% (o desconocido); nunca vs fish/station/trapper/3-bettor < 4%.
  bool get allows4BetBluff {
    if (archetype == GgArchetype.recPassiveFish || archetype == GgArchetype.trapperLimpReraiser) return false;
    if (threeBet != null && threeBet! < 4) return false;
    if (foldTo4Bet != null && foldTo4Bet! < 45) return false;
    return true;
  }

  static const trapperPremiumPrior = 0.85;
  static const scaredMoneyFoldPrior = 0.70;
  static const nuttedDonkPrior = 0.85;
  static const scaredBigPotBb = 35.0;

  VillainProfile get engineProfile => switch (archetype) {
        GgArchetype.recPassiveFish => VillainProfile.callingStation,
        GgArchetype.trapperLimpReraiser => VillainProfile.trapperPremium,
        GgArchetype.scaredMoneyReg => VillainProfile.regAbc,
        GgArchetype.agroSpewy => VillainProfile.maniac,
        GgArchetype.unknownReg => VillainProfile.gtoBase,
      };

  bool get isRec => archetype == GgArchetype.recPassiveFish || archetype == GgArchetype.trapperLimpReraiser;

  static ReadProfile fromVillainProfile(VillainProfile vp) => switch (vp) {
        VillainProfile.callingStation => const ReadProfile(GgArchetype.recPassiveFish, ['perfil manual: station']),
        VillainProfile.maniac || VillainProfile.regAgro => const ReadProfile(GgArchetype.agroSpewy, ['perfil manual: agro']),
        VillainProfile.nit || VillainProfile.regAbc => const ReadProfile(GgArchetype.scaredMoneyReg, ['perfil manual: tight']),
        VillainProfile.gtoBase => const ReadProfile(GgArchetype.unknownReg, ['perfil manual: GTO']),
        VillainProfile.trapperPremium => const ReadProfile(GgArchetype.trapperLimpReraiser, ['perfil manual: trapper']),
      };
}

class GgProfiler {
  GgProfiler._();

  static ReadProfile classify(SmartHudInput h, [Set<ActionTag> tags = const {}]) {
    final r = _classify(h, tags);
    return ReadProfile(r.archetype, r.reasons, threeBet: h.threeBet, foldTo4Bet: h.foldTo4Bet);
  }

  static ReadProfile _classify(SmartHudInput h, Set<ActionTag> tags) {
    final v = h.vpip, p = h.pfr, t = h.threeBet;
    if (tags.contains(ActionTag.limpReraisePreflop)) {
      return ReadProfile(GgArchetype.trapperLimpReraiser,
          ['Tag Limp_ReRaise', if (p != null && p < 12) 'PFR ${p.round()}% bajo: el re-raise es atípico => rango premium']);
    }
    if ((v != null && p != null && t != null && v > 35 && p > 28 && t > 12) || tags.contains(ActionTag.barrelOffOnBricks)) {
      return const ReadProfile(GgArchetype.agroSpewy, ['VPIP>35/PFR>28/3B>12 o Barrel_Off_On_Bricks']);
    }
    final fishStats = v != null && p != null && v > 38 && p < 12;
    final shortNoRebuy = h.stackBb < 85 && !h.autoRebuy;
    if (fishStats || shortNoRebuy || tags.contains(ActionTag.openLimp)) {
      return ReadProfile(GgArchetype.recPassiveFish, [
        if (fishStats) 'VPIP ${v.round()} / PFR ${p.round()}',
        if (shortNoRebuy) 'Stack ${h.stackBb.round()}bb sin auto-rebuy',
        if (tags.contains(ActionTag.openLimp)) 'Open limp',
      ]);
    }
    final scaredStats = v != null && p != null && t != null && v >= 18 && v <= 23 && p >= 15 && p <= 19 && t < 6;
    if (scaredStats || tags.contains(ActionTag.checkCallFlopCheckTurn)) {
      return const ReadProfile(GgArchetype.scaredMoneyReg, ['VPIP 18-23 / PFR 15-19 / 3B<6 o X/C flop -> X turn']);
    }
    return const ReadProfile(GgArchetype.unknownReg, ['Sin señal: base GTO']);
  }
}

enum DonkTell { blockingBetWeakOrDraw, nuttedUnbalancedValue, standard }

class DonkTellDecoder {
  DonkTellDecoder._();

  static DonkTell classify({required double donkBb, required double potBb, required ReadProfile read, required Stake stake, bool donkRaise = false}) {
    final frac = donkBb / potBb;
    if (read.isRec && (donkBb <= 1.0 || frac <= 0.20) && !donkRaise) return DonkTell.blockingBetWeakOrDraw;
    final big = frac >= 0.75 || donkRaise;
    if (big && (read.isRec || (stake.index <= Stake.nl25.index && frac >= 0.80))) return DonkTell.nuttedUnbalancedValue;
    return DonkTell.standard;
  }
}

enum TrapperResponse { fourBetJam, call, setMineCall, fold }

class TrapperDecoder {
  TrapperDecoder._();

  static const premium = {'AA', 'KK', 'AKs'};

  /// Hero enfrenta limp-reraise. raiseToBb = total del re-raise; heroRaiseBb = iso de Hero.
  static (TrapperResponse, String) respond(String handClass, {required double raiseToBb, required double heroRaiseBb, required double effStackBb}) {
    final call = raiseToBb - heroRaiseBb;
    final ratio = raiseToBb / heroRaiseBb;
    final pair = handClass.length == 2;
    final alert = 'ALERTA: Rango 85%+ AA/KK/AKs (prior ${(ReadProfile.trapperPremiumPrior * 100).round()}%), 15% pares bajos/random.';
    if (handClass == 'AA') return (TrapperResponse.fourBetJam, '$alert AA: domina su rango => 4-bet/jam.');
    if (handClass == 'KK' || handClass == 'AKs') return (TrapperResponse.call, '$alert $handClass: no jam (vs AA/KK); call.');
    if (pair && call < 0.10 * effStackBb) {
      return (TrapperResponse.setMineCall, '$alert Set-mining: call ${call.toStringAsFixed(1)}bb < 10% stack (implícitas vs rango premium).');
    }
    return (TrapperResponse.fold, '$alert $handClass fold${ratio > 4 ? ' (sizing ${ratio.toStringAsFixed(1)}x > 4x)' : ''}: dominada por AA/KK/AKs.');
  }
}
