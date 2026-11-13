import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/application/hand_flow_fsm.dart';
import 'package:sol_ver/core/models/game_state.dart';

var closureChecks = 0;

void step(HandFlowFSM f, Position p, ActionType t, [double amt = 0]) {
  f.act(p, t, amountBb: amt);
  if (f.isBettingRoundClosed && f.phase != HandPhase.handOver) {
    for (final s in f.seats.values.where((s) => s.alive && !s.allIn)) {
      expect(s.committed, closeTo(f.currentHighBetBB, 1e-9), reason: 'Action_Closure_Invariant ${s.position.name}');
    }
    closureChecks++;
  }
}

void main() {
  test('Tortura FSM: open -> call -> click-back -> re-raise -> nano-bet -> min-raise -> all-in incompleto + rewind exacto', () {
    final f = HandFlowFSM()..configure(stake: Stake.nl10, hero: Position.bb);
    f.setStack(Position.btn, 50);
    f
      ..addCard(Card.parse('Ah'))
      ..addCard(Card.parse('Qd'));
    step(f, Position.utg, ActionType.raise, 2.5);
    step(f, Position.mp, ActionType.call);
    step(f, Position.btn, ActionType.raise, 5.0); // click-back (fast-forward CO)
    expect(f.seats[Position.co]!.alive, isFalse);
    step(f, Position.sb, ActionType.fold);
    expect(f.currentActor, Position.bb);
    expect(f.activeRecommendation, isNotNull);
    step(f, Position.bb, ActionType.call);
    expect(f.isBettingRoundClosed, isFalse);
    step(f, Position.utg, ActionType.raise, 15); // re-raise loop
    expect(f.currentActor, Position.mp);
    step(f, Position.mp, ActionType.fold);
    step(f, Position.btn, ActionType.call);
    step(f, Position.bb, ActionType.call);
    expect(f.phase, HandPhase.flopCards);
    for (final c in ['Kc', '7d', '2h']) {
      f.addCard(Card.parse(c));
    }
    step(f, Position.bb, ActionType.check);
    step(f, Position.utg, ActionType.bet, 1); // nano-bet
    step(f, Position.btn, ActionType.call);
    expect(f.currentActor, Position.bb);
    step(f, Position.bb, ActionType.call);
    f.addCard(Card.parse('4s'));
    step(f, Position.bb, ActionType.check);
    final potTurn = f.totalPotBB;
    final stacksTurn = {for (final p in HandFlowFSM.preflopOrder) p: f.stackOf(p)};
    final idxTurnBet = f.stepLabels.length;
    step(f, Position.utg, ActionType.bet, 10);
    step(f, Position.btn, ActionType.raise, 20); // min-raise
    expect(f.currentActor, Position.bb);
    step(f, Position.bb, ActionType.fold);
    step(f, Position.utg, ActionType.call);
    f.addCard(Card.parse('9c'));
    step(f, Position.utg, ActionType.bet, 12);
    expect(f.seats[Position.btn]!.stack, closeTo(14, 1e-9));
    step(f, Position.btn, ActionType.allIn); // incompleto: +2 < 12
    expect(f.reopensBettingForPriorActors, isFalse);
    expect(f.legalActions(), {ActionType.fold, ActionType.call});
    step(f, Position.utg, ActionType.call);
    expect(f.phase, HandPhase.handOver);
    final finalPot = f.totalPotBB;
    // Preflop 0.5 SB + 2.5 MP + 3x15 = 48 | Flop 3x1 = 51 | Turn 2x20 = 91 | River 2x14 (all-in pagado) = 119.
    expect(finalPot, closeTo(119.0, 1e-9));
    // Rewind exacto al paso de la apuesta del turn y reproducción idéntica (sin fugas de estado).
    f.rewindTo(idxTurnBet);
    expect(f.totalPotBB, closeTo(potTurn, 1e-9));
    for (final p in HandFlowFSM.preflopOrder) {
      expect(f.stackOf(p), closeTo(stacksTurn[p]!, 1e-9), reason: p.name);
    }
    step(f, Position.utg, ActionType.bet, 10);
    step(f, Position.btn, ActionType.raise, 20);
    step(f, Position.bb, ActionType.fold);
    step(f, Position.utg, ActionType.call);
    f.addCard(Card.parse('9c'));
    step(f, Position.utg, ActionType.bet, 12);
    step(f, Position.btn, ActionType.allIn);
    step(f, Position.utg, ActionType.call);
    expect(f.totalPotBB, closeTo(finalPot, 1e-9));
    expect(closureChecks, greaterThanOrEqualTo(4)); // 1 por calle cerrada (preflop, flop, turn) + turn de la reproducción
    // ignore: avoid_print
    print('TORTURE_OK closures=$closureChecks pot=${finalPot.toStringAsFixed(2)}');
  });
}
