import '../../application/hand_flow_fsm.dart';
import '../../application/linear_hand_flow.dart';
import '../../core/models/game_state.dart';

/// Nivel de apuesta preflop visto por una fila (real o proyectado).
typedef LevelView = ({int r, double bet, double minTo, int limps});

LevelView levelViewOf(HandFlowFSM fsm) => (
  r: fsm.actions.where((a) => a.street == Street.preflop && a.isAggressive).length,
  bet: fsm.currentBet,
  minTo: fsm.minRaiseTo,
  limps: fsm.actions.where((a) => a.street == Street.preflop && a.type == ActionType.call).length,
);

/// L1 Continuous_Speculative_Hero_AutoCommit (Fase 17.5): sin [Mi turno]. En cuanto Hero es alcanzable,
/// los asientos en blanco antes de Hero se asumen Fold y la jugada del solver se AUTO-APLICA. Si el usuario toca
/// luego uno de esos asientos, se hace rollback exacto (snapshots de la FSM) y se re-aplica en vivo.
class SpeculativeHeroController {
  SpeculativeHeroController(this.flow);
  final LinearHandFlow flow;
  HandFlowFSM get fsm => flow.fsm;

  int? _mark;
  int _end = -1;
  int _before = 0;
  Set<Position> folded = const {};
  LevelView? view;

  /// La especulación sigue viva mientras nada ocurrió después de la acción auto-aplicada de Hero.
  bool get active => _mark != null && fsm.phase == HandPhase.preflop && !fsm.awaitingCards && fsm.actions.length == _end;

  /// true si TODA la acción preflop es especulativa (la posición aún puede cambiarse).
  bool get onlySpec => active && _before == 0;

  void maybeSpeculate({required bool positionChosen}) {
    if (!positionChosen || fsm.phase != HandPhase.preflop || fsm.awaitingCards || flow.manualMode || fsm.heroCards.length < 2) return;
    final hero = fsm.heroPosition;
    if (!fsm.pendingToAct.contains(hero) || fsm.currentActorSeat == null) return;
    if (fsm.currentActorSeat == hero) {
      if (fsm.activeRecommendation != null) flow.heroGo();
      return;
    }
    if (!fsm.canTap(hero)) return;
    // Sin decisión real para Hero (p. ej. walk en BB): no se especula; se espera a que alguien entre.
    if (fsm.projectedHeroDecision == null) return;
    _mark = fsm.stepSeq;
    _before = fsm.actions.length;
    view = levelViewOf(fsm);
    flow.heroGo();
    folded = {
      for (final a in fsm.actions.skip(_before))
        if (a.type == ActionType.fold && a.actor != hero) a.actor,
    };
    _end = fsm.actions.length;
  }

  /// Rollback exacto al estado previo a la auto-aplicación especulativa.
  void rollback() {
    final m = _mark;
    if (m == null) return;
    while (fsm.stepSeq > m && fsm.canUndo) {
      fsm.undo();
    }
    _mark = null;
    folded = const {};
    flow.manualMode = false;
  }

  void reset() {
    _mark = null;
    folded = const {};
  }
}
