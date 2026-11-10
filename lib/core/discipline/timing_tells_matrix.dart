import '../models/game_state.dart';
import '../postflop/turn_river_solver.dart';

enum TimingRead {
  none,
  instaCheckCappedWeak,
  instaCallDrawsOrInelasticPair,
  longTankCheckMediumValue,
  longTankBigBetHeavyValue,
}

class TimingEffect {
  const TimingEffect(this.read, {this.capped = false, this.removesMonsters = false, this.villainBluffMultiplier = 1.0, this.minPressureSizePct = 0, this.note = ''});
  final TimingRead read;
  final bool capped;
  final bool removesMonsters;
  final double villainBluffMultiplier;
  final double minPressureSizePct;
  final String note;
}

/// Priors poblacionales de timing (declarados por el usuario): 85% trampas eliminadas en insta-check; 80% del pool con falso tank = valor.
class TimingTellsMatrix {
  TimingTellsMatrix._();

  static const instaCheckTrapRemoval = 0.85;
  static const falseTankValuePrior = 0.80;
  static const falseTankBluffMultiplier = 0.5;

  static TimingEffect of(PlayerAction a, Stake stake) {
    final micro = stake.index <= Stake.nl50.index;
    if (a.timing == TimingTell.instaAction && a.type == ActionType.check) {
      return const TimingEffect(TimingRead.instaCheckCappedWeak,
          capped: true, note: 'Insta-check: -85% trampas con nuts => rango 100% capado débil/medio; float/probe/overbet al máximo.');
    }
    if (a.timing == TimingTell.instaAction && a.type == ActionType.call && a.street != Street.river) {
      return const TimingEffect(TimingRead.instaCallDrawsOrInelasticPair,
          removesMonsters: true, note: 'Insta-call: draw evidente o par medio inelástico; sin sets/monsters (habrían pensado raise).');
    }
    if (a.timing == TimingTell.longTank && a.type == ActionType.check) {
      return const TimingEffect(TimingRead.longTankCheckMediumValue,
          capped: true, minPressureSizePct: 75, note: 'Long tank -> check: valor medio dudoso (TP mal kicker / 2nd pair); paga 1 apuesta pequeña => sizing >= 75%.');
    }
    if (a.timing == TimingTell.longTank && a.isAggressive && a.street != Street.flop && micro) {
      return const TimingEffect(TimingRead.longTankBigBetHeavyValue,
          villainBluffMultiplier: falseTankBluffMultiplier, note: 'Falso tank + apuesta grande (NL2-NL50): 80% valor pesado => faroles x0.5.');
    }
    return const TimingEffect(TimingRead.none);
  }

  /// Último tell relevante del villano (acción más reciente).
  static TimingEffect lastVillain(GameState s) {
    final v = s.actions.where((a) => a.actor == s.villainPosition && a.timing != TimingTell.none).toList();
    return v.isEmpty ? const TimingEffect(TimingRead.none) : of(v.last, s.stake);
  }

  /// Insta-call en turn y river ladrillo/completa: (aplica, riverBrick).
  static (bool, bool) instaCallTurnIntoRiver(GameState s) {
    if (s.street != Street.river) return (false, false);
    final insta = s.actions.any((a) =>
        a.street == Street.turn && a.actor == s.villainPosition && a.type == ActionType.call && a.timing == TimingTell.instaAction);
    if (!insta) return (false, false);
    return (true, CardShiftMatrix.classify(s.board.sublist(0, 4), s.board[4]) != CardShift.flushOrStraightCompletes);
  }
}
