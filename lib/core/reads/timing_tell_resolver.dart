import '../discipline/timing_tells_matrix.dart';
import '../models/game_state.dart';
import 'villain_archetypes.dart';

/// Resolución de un timing tell subordinada al Profile_Gate (el perfil manda sobre el timing).
class TimingResolution {
  const TimingResolution({
    required this.read,
    this.rangeCappedWeak = false,
    this.autoProfitStabPct,
    this.overbetBluffPct,
    this.riverPolarBarrelPct,
    this.bluffAllowed = true,
    this.thinValueOnly = false,
    this.bluffCatchBudgetMult = 1.0,
    this.topPairDowngrade = false,
    required this.note,
  });

  final TimingRead read;
  final bool rangeCappedWeak;
  final (double, double)? autoProfitStabPct;
  final double? overbetBluffPct;
  final double? riverPolarBarrelPct;
  final bool bluffAllowed;
  final bool thinValueOnly;
  final double bluffCatchBudgetMult;
  final bool topPairDowngrade;
  final String note;
}

class TimingTellResolver {
  TimingTellResolver._();

  /// [action] = acción del villano con su timing; [riverCompletesDraws] solo aplica en River tras insta-call en Turn.
  static TimingResolution resolve(VillainTag tag, PlayerAction action, Stake stake, {bool riverCompletesDraws = false}) {
    final e = TimingTellsMatrix.of(action, stake);
    final fish = tag == VillainTag.fishStation, trapper = tag == VillainTag.trapper, maniac = tag == VillainTag.agroManiac;
    switch (e.read) {
      case TimingRead.instaCheckCappedWeak:
        if (fish) {
          return TimingResolution(read: e.read, rangeCappedWeak: true, bluffAllowed: false, thinValueOnly: true,
              note: 'Profile_Gate Fish: insta-check solo expande Thin_Value (0% farol puro).');
        }
        if (trapper) {
          return TimingResolution(read: e.read, bluffAllowed: false, note: 'Profile_Gate Trapper: el insta-check no capa su rango polar.');
        }
        return TimingResolution(read: e.read, rangeCappedWeak: true, autoProfitStabPct: (66, 80), overbetBluffPct: 125,
            note: 'Insta-check => Capped_Weak: Auto_Profit_Stab 66-80% (Turn) / Overbet_Bluff 125% con blockers (River).');
      case TimingRead.instaCallDrawsOrInelasticPair:
        if (fish) {
          return TimingResolution(read: e.read, bluffAllowed: false, riverPolarBarrelPct: 85,
              note: 'Profile_Gate Fish: ignora Brick_Out (0% farol); valor 85% con TopPair+.');
        }
        if (riverCompletesDraws) {
          return TimingResolution(read: e.read, bluffAllowed: false, topPairDowngrade: true,
              note: 'Insta-call + River completa: 0% farol; TopPair/Overpair -> Check/Call o Block 25%.');
        }
        final reg = tag == VillainTag.scaredReg || tag == VillainTag.poolDefault || tag == VillainTag.nitPassive;
        return TimingResolution(read: e.read, riverPolarBarrelPct: reg ? 85 : null, bluffAllowed: reg,
            note: reg ? 'Insta-call + Brick_Out vs Reg: River_Polar_Barrel 85% (draws fallidos insta-foldean).' : e.note);
      case TimingRead.longTankBigBetHeavyValue:
        return TimingResolution(read: e.read, bluffCatchBudgetMult: maniac ? 1.0 : TimingTellsMatrix.falseTankBluffMultiplier,
            note: maniac ? 'Profile_Gate Maniac: el tank no reduce el budget de bluff-catch.' : e.note);
      case TimingRead.longTankCheckMediumValue:
        return TimingResolution(read: e.read, rangeCappedWeak: !trapper, note: e.note);
      case TimingRead.none:
        return const TimingResolution(read: TimingRead.none, note: 'Sin tell.');
    }
  }
}
