import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/application/hand_flow_fsm.dart';
import 'package:sol_ver/application/linear_hand_flow.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/ui/screens/solver_cockpit_screen.dart';
import 'package:sol_ver/ui/theme.dart';
import 'package:sol_ver/ui/widgets/bet_size_scrubber_bar.dart';

Future<void> tapKey(WidgetTester t, String key) async {
  await t.pump();
  final any = find.descendant(of: find.byKey(const ValueKey('pane-0')), matching: find.byKey(ValueKey(key), skipOffstage: false), skipOffstage: false);
  if (any.evaluate().isEmpty) fail('falta "$key"');
  await t.ensureVisible(any);
  await t.pump();
  await t.tap(find.byKey(ValueKey(key)));
  await t.pump();
}

Future<void> pick(WidgetTester t, String card) async {
  await tapKey(t, 'rank-${card[0]}');
  await tapKey(t, 'suit-${card[1]}');
}

String oracle(WidgetTester t) => t.widget<Text>(find.byKey(const ValueKey('oracle-action'))).data!;
String label(WidgetTester t, String key) => t.widget<Text>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)).first).data!;

Future<LinearHandFlow> start(WidgetTester t, String c1, String c2, String pos) async {
  await t.binding.setSurfaceSize(const Size(412, 1500));
  final flow = LinearHandFlow(HandFlowFSM()..configure(stake: Stake.nl50));
  await t.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: SolverCockpitScreen(key: UniqueKey(), flow: flow),
    ),
  );
  await pick(t, c1);
  await pick(t, c2);
  await tapKey(t, 'pos-$pos');
  return flow;
}

bool heroActedAfter(HandFlowFSM fsm, Position v) {
  final i = fsm.actions.lastIndexWhere((a) => a.actor == v);
  return i >= 0 && fsm.actions.skip(i + 1).any((a) => a.actor == fsm.heroPosition);
}

void main() {
  testWidgets('Farha: UTG OR -> Hero CO 3-Bet 7.5 -> SB +Call (Farha) -> UTG Call ➔ Flop => 3-way, bote 23.5', (t) async {
    final flow = await start(t, 'Kh', 'Kd', 'co');
    final fsm = flow.fsm;
    await tapKey(t, 'act-utg-or');
    expect(oracle(t), 'ACCIÓN: 3-BET a 7.5 bb');
    expect(label(t, 'act-sb-call'), '+Call (Farha)');
    for (final k in ['act-sb-callflop', 'act-sb-4bet', 'act-sb-allin', 'act-utg-callflop', 'act-utg-4bet']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    await tapKey(t, 'act-sb-call');
    expect(fsm.phase, HandPhase.preflop, reason: 'Farha mantiene la órbita abierta para UTG');
    await tapKey(t, 'act-utg-callflop');
    expect(fsm.screenPhase, ScreenPhase.pickFlop);
    expect(fsm.activeSeats, [Position.sb, Position.utg, Position.co]);
    expect(fsm.totalPotBB, closeTo(23.5, 1e-9));
    expect(t.takeException(), isNull);
  });

  testWidgets('Cold spot: UTG OR + MP 3-Bet -> Hero AA evalúa Cold 4-Bet; Cold 4-Bet/5-Bet detrás reabre a Hero', (t) async {
    final flow = await start(t, 'Ah', 'Ad', 'co');
    final fsm = flow.fsm;
    await tapKey(t, 'act-utg-or');
    await tapKey(t, 'act-mp-3bet');
    expect(heroActedAfter(fsm, Position.mp), isTrue, reason: 'Hero evaluado en el nodo OR + 3-Bet');
    expect(flow.lastHero!.action, DecisionAction.betRaise, reason: 'AA => Cold 4-Bet');
    expect(oracle(t), startsWith('ACCIÓN: 4-BET'));
    final hero4 = fsm.currentHighBetBB;
    expect(find.byKey(const ValueKey('act-btn-5bet')), findsOneWidget, reason: 'BTN frente al 4-Bet: 5-Bet / All-In');
    await tapKey(t, 'act-btn-5bet');
    expect(fsm.currentHighBetBB, greaterThan(hero4));
    expect(heroActedAfter(fsm, Position.btn), isTrue, reason: 'Law_3: el turno vuelve a Hero');
    expect(t.takeException(), isNull);
  });

  testWidgets('Farha de Hero: UTG OR + MP 3-Bet -> Hero JJ con decisión válida; Cold 4-Bet de BTN reabre a Hero', (t) async {
    final flow = await start(t, 'Jh', 'Jd', 'co');
    final fsm = flow.fsm;
    await tapKey(t, 'act-utg-or');
    await tapKey(t, 'act-mp-3bet');
    expect(flow.lastHero, isNotNull);
    if (flow.lastHero!.action == DecisionAction.call) {
      expect(label(t, 'act-btn-4bet'), startsWith('4-Bet (Cold 4B)'));
      await tapKey(t, 'act-btn-4bet');
      expect(heroActedAfter(fsm, Position.btn), isTrue, reason: 'Cold 4-Bet detrás => turno de Hero');
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('3-Bet vs ROL: UTG Limp -> Hero MP ROL -> [3-Bet] en todos (Limp-3Bet en UTG) -> CO 3-Bet reabre a Hero', (t) async {
    final flow = await start(t, 'Ah', 'Qh', 'mp');
    final fsm = flow.fsm;
    await tapKey(t, 'act-utg-limp');
    expect(oracle(t), startsWith('ACCIÓN: ROL / ISO-RAISE a '));
    final rol = fsm.currentHighBetBB;
    for (final p in ['co', 'btn', 'sb', 'bb']) {
      expect(label(t, 'act-$p-3bet'), startsWith('3-Bet (vs ROL)'), reason: p);
    }
    expect(label(t, 'act-utg-3bet'), startsWith('Limp-3Bet'));
    final before = oracle(t);
    await tapKey(t, 'act-co-3bet');
    expect(fsm.actions.lastWhere((a) => a.actor == Position.co).amountBb, closeTo(rol * 3, .5));
    expect(heroActedAfter(fsm, Position.co), isTrue, reason: 'Hero_ROL_vs_3Bet');
    expect(find.textContaining('ACTUALIZADO VS CO 3-Bet'), findsOneWidget);
    expect(oracle(t), isNot(before));
    expect(t.takeException(), isNull);
  });

  testWidgets('Limp-3Bet: UTG Limp -> Hero MP ROL -> UTG Limp-3Bet => Hero re-evaluado', (t) async {
    final flow = await start(t, 'Ah', 'Qh', 'mp');
    final fsm = flow.fsm;
    await tapKey(t, 'act-utg-limp');
    await tapKey(t, 'act-utg-3bet');
    expect(heroActedAfter(fsm, Position.utg), isTrue);
    expect(find.textContaining('ACTUALIZADO VS UTG 3-Bet'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('Stack efectivo 100 -> 35: GameState, SPR y Oráculo re-evaluados al instante', (t) async {
    final flow = await start(t, 'Ts', '9s', 'btn');
    final fsm = flow.fsm;
    final sig = fsm.stateSignature;
    final spr = fsm.currentSPR;
    expect(fsm.tableStackBB, 100);
    await tapKey(t, 'stack-chip');
    expect(t.getSize(find.byKey(const ValueKey('stack-chip'))).height, greaterThanOrEqualTo(44));
    for (final v in ['20', '30', '40', '50', '60', '80', '100', '125', '150', '200']) {
      expect(find.byKey(ValueKey('stack-$v')), findsOneWidget);
    }
    await tapKey(t, 'stack-40');
    await tapKey(t, 'stack-minus5');
    expect(fsm.tableStackBB, 35);
    expect(fsm.buildGameState().effectiveStackBb, 35.0);
    expect(fsm.stateSignature, isNot(sig));
    expect(fsm.currentSPR, isNot(spr));
    expect(find.text('35bb ▾'), findsOneWidget);
    expect(flow.lastHero, isNotNull, reason: 'Hero re-evaluado con 35bb');
    expect(fsm.actions.where((a) => a.actor == Position.btn).length, 1, reason: 'jugada especulativa rehecha (no duplicada)');
    expect(t.takeException(), isNull);
  });

  testWidgets('Barra lenta: ventana contextual fina en pasos de 0.5bb + expansión a stack + onChangeEnd', (t) async {
    final flow = await start(t, 'As', 'Qs', 'co');
    final fsm = flow.fsm;
    await tapKey(t, 'act-btn-3bet');
    final s = t.widget<Slider>(find.byKey(const ValueKey('scrub-slider')));
    final span = s.max - s.min;
    expect(span, lessThanOrEqualTo(fsm.totalPotBB * 2.2 + 1e-9 < 13 ? 13 : fsm.totalPotBB * 2.2 + 1e-9));
    expect(span, lessThan(40), reason: 'ventana contextual, no 1..100bb');
    expect(s.divisions, (span / BetSizeScrubberBar.step).round(), reason: 'pasos exactos de 0.5bb');
    expect(find.byKey(const ValueKey('scrub-expand')), findsOneWidget);
    await tapKey(t, 'scrub-expand');
    final s2 = t.widget<Slider>(find.byKey(const ValueKey('scrub-slider')));
    expect(s2.max, closeTo(fsm.seats[Position.btn]!.committed + fsm.seats[Position.btn]!.stack, .01));
    expect(s2.onChangeEnd, isNotNull);
    expect(BetSizeScrubberBar.contextualMax(min: 2, max: 100, pot: 3.5), 14.0);
    expect(BetSizeScrubberBar.contextualMax(min: 5, max: 100, pot: 12.5), 27.5);
    expect(t.takeException(), isNull);
  });
}
