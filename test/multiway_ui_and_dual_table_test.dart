import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/application/dual_table_session_manager.dart';
import 'package:sol_ver/application/hand_flow_fsm.dart';
import 'package:sol_ver/application/linear_hand_flow.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/preflop/full_tree_preflop.dart';
import 'package:sol_ver/core/reads/multiway_threat_aggregator.dart';
import 'package:sol_ver/ui/screens/solver_cockpit_screen.dart';
import 'package:sol_ver/ui/theme.dart';

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

  testWidgets('Dual-Table: Mesa 1 AsKs flop 18bb intacta tras usar y resetear Mesa 2', (t) async {
    await t.binding.setSurfaceSize(const Size(412, 1800));
    final m = DualTableSessionManager(flowA: _flow(Position.btn), flowB: _flow(Position.btn));
    final a = m.tableSlotA.fsm;
    a.addCard(Card.parse('As'));
    a.addCard(Card.parse('Ks'));
    m.tableSlotA.flow.manualMode = true;
    m.tableSlotA.flow.scenarioOpen(Position.co);
    a.act(Position.btn, ActionType.raise, amountBb: 8.25);
    m.tableSlotA.flow.goToFlop({Position.co});
    for (final c in ['Qh', '7d', '2c']) {
      a.addCard(Card.parse(c));
    }
    expect(a.street, Street.flop);
    expect(a.totalPotBB, closeTo(18, .01));
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: SolverCockpitScreen(manager: m),
      ),
    );
    expect(find.byKey(const ValueKey('dual-tabs')), findsOneWidget);
    expect(find.textContaining('AsKs • Flop'), findsOneWidget);
    await tapKey(t, 'tab-1');
    expect(m.activeIndex, 1);
    await pick(t, '9h');
    await pick(t, '9c');
    expect(m.tableSlotB.fsm.heroCards.length, 2);
    expect(m.tableSlotB.fsm.heroPosition, Position.btn);
    await tapKey(t, 'rush-reset-1');
    expect(m.tableSlotB.fsm.heroCards, isEmpty);
    await tapKey(t, 'tab-0');
    expect(m.activeIndex, 0);
    expect(a.heroCards.map((c) => '$c').join(), 'AsKs');
    expect(a.street, Street.flop);
    expect(a.totalPotBB, closeTo(18, .01));
    expect(find.textContaining('Bote: 18.0 bb | 2 Jugadores (CO, BTN)'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
