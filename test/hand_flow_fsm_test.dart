import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/application/hand_flow_fsm.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/preflop/full_tree_preflop.dart';

HandFlowFSM start(Position hero, String cards, {Stake stake = Stake.nl50}) {
  final f = HandFlowFSM()..configure(stake: stake, hero: hero);
  for (final c in Card.parseMany(cards)) {
    f.addCard(c);
  }
  return f;
}

void main() {
  test('Setup: 2da carta de Hero inicia PREFLOP con ciegas (pot 1.5bb) y turno UTG', () {
    final f = start(Position.btn, 'AhKh');
    expect(f.phase, HandPhase.preflop);
    expect(f.pot, 1.5);
    expect(f.currentActor, Position.utg);
    expect(() => f.addCard(Card.parse('Ah')), throwsA(isA<IllegalAction>()));
  });

  test('1. UTG F, MP F, CO open 2.5, BTN 3-bet 7.5, SB F => recomendación de Hero BB en nodo cold 4-bet', () {
    final f = start(Position.bb, 'QhQd');
    f
      ..act(Position.utg, ActionType.fold)
      ..act(Position.mp, ActionType.fold)
      ..act(Position.co, ActionType.raise, amountBb: 2.5)
      ..act(Position.btn, ActionType.raise, amountBb: 7.5)
      ..act(Position.sb, ActionType.fold);
    expect(f.currentActor, Position.bb);
    expect(f.activeRecommendation, isNotNull, reason: f.recommendationError);
    final gs = f.buildGameState();
    final spot = FullTreePreflop.classify(gs);
    expect(spot.scenario, TreeScenario.cold4Bet);
    expect(spot.opener, Position.co);
    expect(spot.threeBettor, Position.btn);
    expect(f.activeRecommendation!.justificacionGto, contains('cold 4-bet'));
    expect(f.pot, closeTo(0.5 + 1 + 2.5 + 7.5, 1e-9));
  });

  test('2. Street_Gate: flop bloqueado hasta que el abridor iguale el 3-bet; luego 3 cartas y turno OOP', () {
    final f = start(Position.co, 'AhQh');
    f
      ..act(Position.utg, ActionType.fold)
      ..act(Position.mp, ActionType.fold)
      ..act(Position.co, ActionType.raise, amountBb: 2.5)
      ..act(Position.btn, ActionType.raise, amountBb: 7.5)
      ..act(Position.sb, ActionType.fold)
      ..act(Position.bb, ActionType.fold);
    expect(f.currentActor, Position.co);
    expect(f.isStreetActionClosed, isFalse);
    expect(() => f.addCard(Card.parse('2c')), throwsA(isA<IllegalAction>()));
    expect(f.activeRecommendation, isNotNull);
    f.act(Position.co, ActionType.call);
    expect(f.isStreetActionClosed, isTrue);
    expect(f.phase, HandPhase.flopCards);
    expect(f.cardsNeeded, 3);
    f
      ..addCard(Card.parse('Kd'))
      ..addCard(Card.parse('7c'));
    expect(f.phase, HandPhase.flopCards);
    expect(f.cardsNeeded, 1);
    f.addCard(Card.parse('2s'));
    expect(f.phase, HandPhase.flop);
    expect(f.currentActor, Position.co);
    expect(f.pot, closeTo(0.5 + 1 + 7.5 + 7.5, 1e-9));
    expect(f.activeRecommendation, isNotNull, reason: f.recommendationError);
  });

  test('3. Fast-forward preflop: CO open con turno en UTG => UTG y MP fold, turno BTN', () {
    final f = start(Position.bb, '9h9d');
    f.act(Position.co, ActionType.raise, amountBb: 2.5);
    expect(f.seats[Position.utg]!.alive, isFalse);
    expect(f.seats[Position.mp]!.alive, isFalse);
    expect(f.actions.where((a) => a.type == ActionType.fold).map((a) => a.actor), [Position.utg, Position.mp]);
    expect(f.currentActor, Position.btn);
  });

  test('Fast-forward nunca salta a Hero; acciones postflop fuera de turno se rechazan', () {
    final f = start(Position.mp, '9h9d');
    expect(() => f.act(Position.co, ActionType.raise, amountBb: 2.5), throwsA(isA<IllegalAction>()));
    f.act(Position.utg, ActionType.fold);
    expect(f.currentActor, Position.mp);
  });

  test('Reapertura: el 3-bet reabre la acción solo para jugadores vivos', () {
    final f = start(Position.btn, 'AhKd');
    f
      ..act(Position.utg, ActionType.raise, amountBb: 2.5)
      ..act(Position.mp, ActionType.fold)
      ..act(Position.co, ActionType.call)
      ..act(Position.btn, ActionType.raise, amountBb: 10)
      ..act(Position.sb, ActionType.fold)
      ..act(Position.bb, ActionType.fold);
    expect(f.currentActor, Position.utg);
    f.act(Position.utg, ActionType.fold);
    expect(f.currentActor, Position.co);
    f.act(Position.co, ActionType.call);
    expect(f.phase, HandPhase.flopCards);
  });

  test('Ejecutar acción óptima de Hero avanza la FSM', () {
    final f = start(Position.btn, 'AhKh');
    f
      ..act(Position.utg, ActionType.fold)
      ..act(Position.mp, ActionType.fold)
      ..act(Position.co, ActionType.fold);
    expect(f.currentActor, Position.btn);
    f.executeRecommendation();
    expect(f.seats[Position.btn]!.committed, 2.5);
    expect(f.currentActor, Position.sb);
  });

  test('Mano termina cuando queda 1 jugador; raise mínimo validado', () {
    final f = start(Position.bb, '7h2d');
    expect(() => f.act(Position.utg, ActionType.raise, amountBb: 1.5), throwsA(isA<IllegalAction>()));
    f
      ..act(Position.utg, ActionType.raise, amountBb: 2.5)
      ..act(Position.mp, ActionType.fold)
      ..act(Position.co, ActionType.fold)
      ..act(Position.btn, ActionType.fold)
      ..act(Position.sb, ActionType.fold);
    f.executeRecommendation();
    expect(f.phase, HandPhase.handOver);
  });
}
