import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/application/hand_flow_fsm.dart';
import 'package:sol_ver/application/linear_hand_flow.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/ui/screens/solver_cockpit_screen.dart';
import 'package:sol_ver/ui/theme.dart';

LinearHandFlow? _flow;

/// R1: en cuanto hay mano + posición, el Oráculo fijo nunca es null.
void expectOracle(WidgetTester t, [String why = '']) {
  final f = _flow!;
  if (f.fsm.heroCards.length < 2 || f.fsm.phase == HandPhase.setup) return;
  expect(find.byKey(const ValueKey('pinned-oracle')), findsOneWidget, reason: 'oráculo ausente $why ${f.fsm.screenPhase}');
  expect(oracle(t), startsWith('ACCIÓN: '), reason: why);
}

String oracle(WidgetTester t) => t.widget<Text>(find.byKey(const ValueKey('oracle-action'))).data!;
String ctx(WidgetTester t) => t.widget<Text>(find.byKey(const ValueKey('oracle-context'))).data!;

Future<void> tapKey(WidgetTester t, String key, {bool check = true}) async {
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
  if (_flow!.fsm.positionChosenProxy) expectOracle(t, 'picker');
}

double scrubValue(WidgetTester t) => double.parse(t.widget<Text>(find.byKey(const ValueKey('scrub-value'))).data!.split('bb').first);

Future<void> scrubTo(WidgetTester t, double v) async {
  for (var i = 0; i < 400 && (scrubValue(t) - v).abs() > 1e-9; i++) {
    final k = find.byKey(ValueKey(scrubValue(t) < v ? 'scrub-plus' : 'scrub-minus'));
    await t.ensureVisible(k);
    await t.tap(k);
    await t.pump();
  }
  expect(scrubValue(t), v);
}

Future<LinearHandFlow> start(WidgetTester t, String c1, String c2, String pos) async {
  await t.binding.setSurfaceSize(const Size(412, 915));
  final flow = LinearHandFlow(HandFlowFSM()..configure(stake: Stake.nl50));
  _flow = flow;
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

extension on HandFlowFSM {
  bool get positionChosenProxy => actions.isNotEmpty;
}

void main() {
  testWidgets('1+2: AsKs BTN -> OR 2.5 sin tocar nada; UTG OR -> 3-BET en vivo; MP 3-Bet -> 4-BET/CALL en vivo', (t) async {
    final flow = await start(t, 'As', 'Ks', 'btn');
    final fsm = flow.fsm;
    expectOracle(t, 'tras posición');
    expect(oracle(t), 'ACCIÓN: OR a 2.5 bb');
    expect(fsm.actions.lastWhere((a) => a.actor == Position.btn).amountBb, 2.5, reason: 'L1: OR auto-aplicado sin [Mi turno]');
    expect(find.byKey(const ValueKey('hero-go')), findsNothing);
    await tapKey(t, 'act-utg-or');
    expect(oracle(t), 'ACCIÓN: 3-BET a 7.5 bb', reason: 'vs UTG OR, sin tocar MP/CO ni [Mi turno]');
    expect(ctx(t), contains('BTN vs UTG OR 2.5bb'));
    expect(find.text('ACTUALIZADO VS UTG OR 2.5bb'), findsOneWidget);
    expect(fsm.actions.lastWhere((a) => a.actor == Position.btn).amountBb, 7.5, reason: 'L1: 3-Bet re-aplicado en vivo');
    await tapKey(t, 'act-mp-3bet');
    expect(oracle(t), anyOf(startsWith('ACCIÓN: 4-BET'), startsWith('ACCIÓN: CALL'), startsWith('ACCIÓN: ALL-IN')));
    expect(ctx(t), contains('MP 3-Bet 7.5bb'));
    expect(find.text('ACTUALIZADO VS MP 3-Bet 7.5bb'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('3+4: AQs CO OR 2.5 -> BTN 3-Bet 7.5 (sin [Mi turno]) -> CALL 7.5; barra a 22bb -> recálculo', (t) async {
    final flow = await start(t, 'As', 'Qs', 'co');
    final fsm = flow.fsm;
    expect(oracle(t), 'ACCIÓN: OR a 2.5 bb');
    expect(find.byKey(const ValueKey('act-btn-3bet')), findsOneWidget, reason: 'fila detrás de Hero tocable con la proyección');
    await tapKey(t, 'act-btn-3bet');
    expect(fsm.actions.firstWhere((a) => a.actor == Position.co).amountBb, 2.5, reason: 'OR de Hero asumido');
    expect(fsm.currentHighBetBB, 7.5);
    expect(oracle(t), 'ACCIÓN: CALL 7.5 bb');
    expect(find.text('ACTUALIZADO VS BTN 3-Bet 7.5bb'), findsOneWidget);
    final before = oracle(t);
    await scrubTo(t, 22.0);
    expect(fsm.currentHighBetBB, 22.0);
    expect(find.text('ACTUALIZADO VS BTN 3-Bet 22.0bb'), findsOneWidget, reason: 'recalculado al nuevo tamaño');
    expectOracle(t, 'tras barra');
    // ignore: avoid_print
    print('ORACLE_22 $before -> ${oracle(t)}');
    expect(t.takeException(), isNull);
  });

  testWidgets('5: persistencia Flop -> Turn -> River (selector, check, bet, check-raise): nunca null', (t) async {
    final flow = await start(t, 'Ah', 'Kh', 'btn');
    final fsm = flow.fsm;
    expect(oracle(t), 'ACCIÓN: OR a 2.5 bb');
    await tapKey(t, 'act-co-or');
    expect(oracle(t), startsWith('ACCIÓN: 3-BET'));
    expectOracle(t, 'tras auto-commit');
    await tapKey(t, 'act-co-call');
    expect(fsm.screenPhase, ScreenPhase.pickFlop);
    expectOracle(t, 'eligiendo flop');
    expect(ctx(t), startsWith('[PREFLOP'));
    for (final c in ['Ad', '9c', '4s']) {
      await pick(t, c);
      expectOracle(t, 'carta flop');
    }
    expect(ctx(t), startsWith('[FLOP A♦9♣4♠'), reason: 'pre-evaluación IP mientras CO (OOP) no habla');
    await tapKey(t, 'v-check');
    expectOracle(t, 'tras check CO');
    if (fsm.currentActorSeat == Position.co) {
      await tapKey(t, 'v-call');
      expectOracle(t, 'tras call CO');
    }
    expect(fsm.screenPhase, ScreenPhase.pickTurn);
    expectOracle(t, 'eligiendo turn');
    await pick(t, 'Kd');
    await tapKey(t, 'v-check');
    expectOracle(t, 'turn tras check');
    if (fsm.currentActorSeat == Position.co) {
      await tapKey(t, 'v-r3x');
      expectOracle(t, 'tras check-raise');
      expect(flow.lastHeroStreet, Street.turn);
    }
    while (fsm.screenPhase == ScreenPhase.postflopStreetAction && fsm.currentActorSeat == Position.co) {
      await tapKey(t, fsm.currentBet - fsm.seats[Position.co]!.committed > 0 ? 'v-call' : 'v-check');
      expectOracle(t, 'loop');
    }
    if (fsm.screenPhase == ScreenPhase.pickRiver) {
      await pick(t, '7h');
      expectOracle(t, 'river');
    }
    expect(t.takeException(), isNull);
  });
}
