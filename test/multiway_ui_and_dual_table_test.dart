import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/application/hand_flow_fsm.dart';
import 'package:sol_ver/application/linear_hand_flow.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/preflop/full_tree_preflop.dart';
import 'package:sol_ver/core/reads/multiway_threat_aggregator.dart';

Future<void> tapKey(WidgetTester t, String key) async {
  await t.ensureVisible(find.byKey(ValueKey(key)));
  await t.pump();
  await t.tap(find.byKey(ValueKey(key)));
  await t.pump();
}

Future<void> pick(WidgetTester t, String card) async {
  await tapKey(t, 'rank-${card[0]}');
  await tapKey(t, 'suit-${card[1]}');
}

LinearHandFlow _flow(Position hero) => LinearHandFlow(HandFlowFSM()..configure(stake: Stake.nl25, hero: hero));

void main() {
  test('Multiway: UTG open 2.5 + MP call + CO call => Hero BTN ve 2 cold callers (squeeze/call)', () {
    final flow = _flow(Position.btn)..manualMode = true;
    flow.fsm.addCard(Card.parse('Ah'));
    flow.fsm.addCard(Card.parse('Ad'));
    flow.scenarioOpen(Position.utg, callers: [Position.mp, Position.co]);
    expect(flow.atHeroTurn, isTrue);
    final spot = FullTreePreflop.classify(flow.fsm.buildGameState());
    expect(spot.callers, 2);
    expect(spot.opener, Position.utg);
    expect(flow.fsm.totalPotBB, closeTo(1.5 + 2.5 * 3, 1e-9), reason: 'dinero muerto de los callers en el bote');
    expect(flow.fsm.activeRecommendation, isNotNull);
  });

  test('Multiway: flop 3-way (UTG+MP+BTN) activa MultiwayThreatAggregator; UTG foldea => Turn HU vs MP', () {
    final flow = _flow(Position.btn);
    flow.fsm.addCard(Card.parse('Ah'));
    flow.fsm.addCard(Card.parse('Ad'));
    flow.scenarioOpen(Position.utg, callers: [Position.mp]);
    expect(flow.lastHero, isNotNull, reason: 'auto-commit de Hero');
    expect(flow.lastHero!.action, isNot(DecisionAction.fold));
    expect(flow.pendingOwing, containsAll([Position.utg, Position.mp]));
    flow.goToFlop({Position.utg, Position.mp});
    expect(flow.fsm.phase, HandPhase.flopCards);
    for (final c in ['Kc', '7d', '2h']) {
      flow.pickCard(Card.parse(c));
    }
    expect(flow.liveVillains, [Position.utg, Position.mp]);
    final gs = flow.fsm.buildGameState();
    expect(gs.activeVillains.length, 2);
    final a = MultiwayThreatAggregator.assess(gs);
    expect(a.villains.length, 2);
    expect(flow.fsm.currentActor, Position.utg);
    flow.villainFolded(Position.utg);
    expect(flow.liveVillains, [Position.mp]);
    expect(flow.fsm.buildGameState().activeVillains, isEmpty);
    expect(flow.fsm.currentActor, Position.mp);
    flow.villainAct(ActionType.check);
    // Hero auto-commit en flop; si apuesta, MP paga => Turn.
    if (flow.fsm.currentActor == Position.mp) flow.villainAct(ActionType.call);
    expect(flow.fsm.phase, HandPhase.turnCards);
    expect(flow.fsm.alive, [Position.mp, Position.btn]);
    expect(flow.fsm.buildGameState().villainPosition, Position.mp);
  });

}
