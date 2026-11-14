import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/application/hand_flow_fsm.dart';
import 'package:sol_ver/application/linear_hand_flow.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/ui/screens/solver_cockpit_screen.dart';
import 'package:sol_ver/ui/theme.dart';

Future<void> tapKey(WidgetTester t, String key) async {
  await t.pump();
  final any = find.descendant(of: find.byKey(const ValueKey('pane-0')), matching: find.byKey(ValueKey(key), skipOffstage: false), skipOffstage: false);
  await t.ensureVisible(any);
  await t.pump();
  await t.tap(find.byKey(ValueKey(key)));
  await t.pump();
}

Future<void> pick(WidgetTester t, String card) async {
  await tapKey(t, 'rank-${card[0]}');
  await tapKey(t, 'suit-${card[1]}');
}

bool has(String k) => find.byKey(ValueKey(k)).evaluate().isNotEmpty;

Future<LinearHandFlow> start(WidgetTester t, String c1, String c2, String pos, {Size size = const Size(412, 1400)}) async {
  await t.binding.setSurfaceSize(size);
  final flow = LinearHandFlow(HandFlowFSM()..configure(stake: Stake.nl50));
  await t.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: SolverCockpitScreen(flow: flow),
    ),
  );
  expect(find.byKey(const ValueKey('picker-dock')), findsOneWidget, reason: '1° mano: teclado abajo');
  expect(t.widget<FilledButton>(find.byKey(ValueKey('pos-$pos'))).onPressed, isNull, reason: 'posición bloqueada hasta tener 2 cartas');
  await pick(t, c1);
  await pick(t, c2);
  expect(find.byKey(const ValueKey('picker-dock')), findsNothing);
  await tapKey(t, 'pos-$pos');
  expect(find.byKey(const ValueKey('preflop-table')), findsOneWidget);
  return flow;
}

/// Si el solver no eligió [want], el usuario usa [Hice otra cosa] y lo marca a mano en su fila.
Future<void> heroDoes(WidgetTester t, LinearHandFlow flow, DecisionAction want, String key) async {
  if (flow.lastHero!.action == want) return;
  await tapKey(t, 'override');
  expect(flow.manualMode, isTrue);
  await tapKey(t, key);
}

void main() {
  testWidgets('Caso 1: AsQs CO OR -> BTN 3-Bet -> turno vuelve a Hero (solver + porqué) -> 4-Bet 18 -> BTN responde -> Flop', (t) async {
    final flow = await start(t, 'As', 'Qs', 'co');
    final fsm = flow.fsm;
    expect(find.text('★ TÚ (CO)'), findsOneWidget);
    for (final p in ['utg', 'mp', 'co', 'btn', 'sb', 'bb']) {
      expect(find.byKey(ValueKey('row-$p')), findsOneWidget);
    }
    expect(has('act-utg-fold'), isFalse, reason: 'cero botón Fold en filas sin abrir');
    /* L1: Hero auto-aplicado sin [Mi turno] */
    expect(fsm.seats[Position.utg]!.alive || fsm.seats[Position.mp]!.alive, isFalse);
    expect(flow.lastHero!.action, DecisionAction.betRaise);
    expect(fsm.currentHighBetBB, 2.5, reason: 'OR 2.5bb auto-aplicado');
    expect(find.text('Fold (auto · toca si entró)'), findsNWidgets(2), reason: 'UTG/MP en blanco = Fold especulativo (tocables)');
    for (final k in ['act-btn-call', 'act-btn-3bet', 'act-btn-min3b', 'act-btn-allin']) {
      expect(has(k), isTrue, reason: k);
    }
    await tapKey(t, 'act-btn-3bet');
    expect(fsm.currentHighBetBB, 7.5);
    // L1: SB/BB en blanco = Fold y Hero responde al 3-Bet al instante (sin [Mi turno]).
    /* L1: Hero auto-aplicado sin [Mi turno] */
    expect(fsm.seats[Position.sb]!.alive || fsm.seats[Position.bb]!.alive, isFalse);
    expect(fsm.actions.last.actor, Position.co, reason: 'Hero re-evaluado vs 3-Bet');
    expect(find.byKey(const ValueKey('why-1')), findsOneWidget, reason: 'porqué en español');
    await heroDoes(t, flow, DecisionAction.betRaise, 'act-co-4bet');
    if (fsm.currentHighBetBB != 18) {
      await tapKey(t, 'override');
      await tapKey(t, 'act-co-4bet');
    }
    expect(fsm.currentHighBetBB, 18);
    expect(fsm.currentActorSeat, Position.btn);
    for (final k in ['act-btn-fold', 'act-btn-call', 'act-btn-5bet']) {
      expect(has(k), isTrue, reason: k);
    }
    await tapKey(t, 'act-btn-call');
    expect(fsm.screenPhase, ScreenPhase.pickFlop);
    expect(fsm.totalPotBB, closeTo(37.5, 1e-9));
    expect(t.takeException(), isNull);
  });

  testWidgets('Caso 2: UTG OR -> MP 3-Bet -> Hero BTN cold 4-Bet -> UTG Fold -> MP 5-Bet All-In -> Hero Call -> Flop', (t) async {
    final flow = await start(t, 'Ah', 'Ad', 'btn');
    final fsm = flow.fsm;
    await tapKey(t, 'act-utg-or');
    await tapKey(t, 'act-mp-3bet');
    /* L1: Hero auto-aplicado sin [Mi turno] */
    expect(fsm.seats[Position.co]!.alive, isFalse);
    await heroDoes(t, flow, DecisionAction.betRaise, 'act-btn-4bet');
    expect(PreflopRaises.of(fsm), 3, reason: 'cold 4-Bet');
    await tapKey(t, 'act-utg-fold');
    expect(fsm.seats[Position.utg]!.alive, isFalse);
    await tapKey(t, 'act-mp-5bet');
    expect(fsm.seats[Position.mp]!.allIn, isTrue);
    await heroDoes(t, flow, DecisionAction.call, 'act-btn-call');
    expect(fsm.screenPhase, ScreenPhase.pickFlop);
    expect(fsm.activeSeats, [Position.mp, Position.btn]);
    for (final c in ['2c', '7d', 'Jh', '3s', '8c']) {
      await pick(t, c);
    }
    expect(fsm.screenPhase, ScreenPhase.handFinished, reason: 'runout All-In -> SHOWDOWN');
    expect(t.takeException(), isNull);
  });

  testWidgets('Caso 3: UTG Limp -> MP OR 3.5 -> CO Call -> Hero BTN -> BB Call -> UTG Call -> Flop BB ➔ UTG ➔ MP ➔ CO ➔ BTN', (t) async {
    final flow = await start(t, 'Th', '9h', 'btn');
    final fsm = flow.fsm;
    await tapKey(t, 'act-utg-limp');
    await tapKey(t, 'act-mp-or');
    expect(fsm.currentHighBetBB, 3.5);
    await tapKey(t, 'act-co-call');
    expect(flow.lastHeroStreet, Street.preflop, reason: 'Hero evaluado en spot multiway');
    await heroDoes(t, flow, DecisionAction.call, 'act-btn-call');
    await tapKey(t, 'act-bb-call');
    expect(fsm.seats[Position.sb]!.alive, isFalse);
    await tapKey(t, 'act-utg-call');
    expect(fsm.screenPhase, ScreenPhase.pickFlop);
    expect(fsm.activeSeats, [Position.bb, Position.utg, Position.mp, Position.co, Position.btn]);
    expect(t.takeException(), isNull);
  });

  testWidgets('Layout 390x844: teclado de cartas anclado abajo y 0 overflows', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    final flow = LinearHandFlow(HandFlowFSM()..configure(stake: Stake.nl50));
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: SolverCockpitScreen(flow: flow),
      ),
    );
    final dock = find.byKey(const ValueKey('picker-dock'));
    expect(t.getBottomLeft(dock).dy, closeTo(844, 1));
    expect(t.getTopLeft(find.byKey(const ValueKey('rank-A'))).dy, greaterThan(844 / 2), reason: 'zona del pulgar');
    await tapKey(t, 'rank-A');
    expect(t.getBottomLeft(dock).dy, closeTo(844, 1));
    await tapKey(t, 'suit-s');
    await pick(t, 'Kd');
    await tapKey(t, 'pos-co');
    await tapKey(t, 'act-utg-or');
    /* L1: Hero auto-aplicado sin [Mi turno] */
    expect(flow.lastHero, isNotNull);
    expect(t.takeException(), isNull);
  });
}

class PreflopRaises {
  static int of(HandFlowFSM fsm) => fsm.actions.where((a) => a.street == Street.preflop && a.isAggressive).length;
}
