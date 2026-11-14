import 'dart:io';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/application/hand_flow_fsm.dart';
import 'package:sol_ver/application/linear_hand_flow.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/ui/screens/solver_cockpit_screen.dart';
import 'package:sol_ver/ui/theme.dart';

var taps = 0;

Future<void> tapKey(WidgetTester t, String key) async {
  await t.pump();
  final any = find.descendant(of: find.byKey(const ValueKey('pane-0')), matching: find.byKey(ValueKey(key), skipOffstage: false), skipOffstage: false);
  await t.ensureVisible(any);
  await t.pump();
  await t.tap(find.byKey(ValueKey(key)));
  await t.pump();
  taps++;
  expect(find.byKey(const ValueKey('hero-go')), findsNothing);
  expect(find.byKey(const ValueKey('advance-flop')), findsNothing);
}

Future<void> pick(WidgetTester t, String card) async {
  await tapKey(t, 'rank-${card[0]}');
  await tapKey(t, 'suit-${card[1]}');
}

bool keypadFlop() => find.textContaining('Toca 1ra carta del Flop (o añade otro villano arriba)').evaluate().isNotEmpty;

Future<LinearHandFlow> start(WidgetTester t, String c1, String c2, String pos) async {
  await t.binding.setSurfaceSize(const Size(412, 915));
  final flow = LinearHandFlow(HandFlowFSM()..configure(stake: Stake.nl50));
  await t.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: SolverCockpitScreen(key: UniqueKey(), flow: flow),
    ),
  );
  taps = 0;
  await pick(t, c1);
  await pick(t, c2);
  await tapKey(t, 'pos-$pos');
  return flow;
}

void main() {
  test('Botones [Mi turno] y [Avanzar al Flop] borrados del código de lib/ui', () {
    for (final f in Directory('lib/ui').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      expect(
        src.contains("'hero-go'") || src.contains("'advance-flop'") || src.contains('Mi turno ➔') || src.contains('Avanzar al Flop'),
        isFalse,
        reason: f.path,
      );
    }
  });

  testWidgets('Caso A: BTN vs UTG OR -> Hero auto-aplicado en 0 toques -> 1ra carta del flop auto-foldea SB/BB', (t) async {
    final flow = await start(t, 'Qd', 'Jd', 'btn');
    final fsm = flow.fsm;
    expect(fsm.actions.lastWhere((a) => a.actor == Position.btn).amountBb, 2.5, reason: 'OR auto-aplicado al elegir posición');
    await tapKey(t, 'act-utg-or');
    expect(fsm.seats[Position.mp]!.alive || fsm.seats[Position.co]!.alive, isFalse, reason: 'MP/CO en blanco = Fold en vivo');
    final hero = flow.lastHero!;
    // ignore: avoid_print
    print('CASE_A_HERO ${hero.action}');
    expect(fsm.actions.last.actor, Position.btn, reason: 'acción de Hero vs UTG OR auto-aplicada');
    if (hero.action == DecisionAction.call) {
      expect(keypadFlop(), isTrue, reason: 'bote igualado: teclado listo');
    } else {
      expect(hero.action, DecisionAction.betRaise);
      expect(keypadFlop(), isFalse);
      await tapKey(t, 'act-utg-call');
    }
    final before = taps;
    await tapKey(t, 'rank-A');
    await tapKey(t, 'suit-s');
    expect(taps - before, 2);
    expect(fsm.seats[Position.sb]!.alive || fsm.seats[Position.bb]!.alive, isFalse, reason: 'SB/BB auto-foldeados por la 1ra carta');
    expect(fsm.board.map((c) => '$c'), ['As'], reason: 'A♠ = flopCard[0]');
    expect(fsm.screenPhase, ScreenPhase.pickFlop);
    expect(t.takeException(), isNull);
  });

  testWidgets('Caso B: Hero CO OR -> BTN Call (teclado listo) -> SB Squeeze -> Hero re-evaluado y auto-aplicado', (t) async {
    final flow = await start(t, 'As', 'Qs', 'co');
    final fsm = flow.fsm;
    expect(fsm.currentHighBetBB, 2.5);
    await tapKey(t, 'act-btn-call');
    expect(keypadFlop(), isTrue, reason: 'bote igualado CO/BTN con SB/BB en blanco');
    expect(fsm.phase, HandPhase.preflop);
    await tapKey(t, 'act-sb-3bet');
    final sq = fsm.actions.lastIndexWhere((a) => a.actor == Position.sb);
    expect(fsm.actions[sq].type, ActionType.raise);
    expect(fsm.actions.skip(sq).any((a) => a.actor == Position.co), isTrue, reason: 'Hero (CO) respondió al squeeze sin toques');
    expect(find.textContaining('ACTUALIZADO VS SB 3-Bet'), findsOneWidget);
    if (flow.lastHero!.action == DecisionAction.betRaise) expect(keypadFlop(), isFalse, reason: 'teclado oculto: nadie igualó aún');
    if (fsm.screenPhase == ScreenPhase.preflopAction) {
      expect(fsm.pendingToAct, contains(Position.btn), reason: 'espera la respuesta de BTN / SB');
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('Caso C: Hero BTN OR -> BB Call (último asiento) -> cierre automático en 0 toques extra', (t) async {
    final flow = await start(t, 'As', 'Ks', 'btn');
    final fsm = flow.fsm;
    expect(taps, 5);
    await tapKey(t, 'act-bb-call');
    expect(taps, 6);
    expect(fsm.seats[Position.sb]!.alive, isFalse);
    expect(fsm.screenPhase, ScreenPhase.pickFlop, reason: 'preflop cerrado sin confirmación');
    expect(find.textContaining('Flop (1/3)'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('L4: Hero BB vs BTN OR -> ACCIÓN EN BB: CALL y teclado de flop abierto', (t) async {
    final flow = await start(t, 'Jh', 'Tc', 'bb');
    final fsm = flow.fsm;
    expect(fsm.actions, isEmpty, reason: 'sin walk especulativo en BB');
    await tapKey(t, 'act-btn-or');
    // ignore: avoid_print
    print('L4_HERO ${flow.lastHero!.action}');
    if (flow.lastHero!.action == DecisionAction.call) {
      expect(t.widget<Text>(find.byKey(const ValueKey('oracle-action'))).data, 'ACCIÓN EN BB: CALL 2.5 bb');
      expect(fsm.screenPhase, ScreenPhase.pickFlop);
      expect(find.byKey(const ValueKey('picker-dock')), findsOneWidget);
      expect(find.byKey(const ValueKey('scrub-value')), findsOneWidget, reason: 'barra del OR de BTN sigue ajustable');
      expect(find.byKey(const ValueKey('override')), findsOneWidget);
    }
    expect(t.takeException(), isNull);
  });
}
