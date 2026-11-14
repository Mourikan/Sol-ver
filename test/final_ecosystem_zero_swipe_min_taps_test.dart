import 'dart:io';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/application/hand_flow_fsm.dart';
import 'package:sol_ver/application/linear_hand_flow.dart';
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
}

Future<void> pick(WidgetTester t, String card) async {
  await tapKey(t, 'rank-${card[0]}');
  await tapKey(t, 'suit-${card[1]}');
}

String oracle(WidgetTester t) => t.widget<Text>(find.byKey(const ValueKey('oracle-action'))).data!;

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
  test('Zero swipe: ningún gesto de arrastre/deslizamiento de navegación en lib/ui', () {
    final bad = RegExp(r'onHorizontalDrag|onVerticalDrag|onPanUpdate|onPanEnd|Dismissible\(|PageView\(');
    for (final f in Directory('lib/ui').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      expect(bad.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
    }
  });

  testWidgets('Robo preflop: 6 toques (4 cartas + posición + Nueva Mano); botones superiores >= 46dp', (t) async {
    final flow = await start(t, 'As', 'Ks', 'btn');
    expect(oracle(t), 'ACCIÓN: OR a 2.5 bb');
    for (final k in ['undo', 'new-hand']) {
      expect(t.getSize(find.byKey(ValueKey(k))).height, greaterThanOrEqualTo(46), reason: k);
    }
    final undoPos = t.getTopLeft(find.byKey(const ValueKey('undo')));
    await tapKey(t, 'new-hand');
    expect(taps, 6);
    expect(flow.fsm.phase, HandPhase.setup);
    expect(t.getTopLeft(find.byKey(const ValueKey('undo'))), undoPos, reason: 'misma coordenada siempre');
    expect(t.takeException(), isNull);
  });

  testWidgets('Open + 1 caller: 6 toques con [Call ➔ Flop] y teclado pidiendo la 1ra carta', (t) async {
    final flow = await start(t, 'Ah', 'Qh', 'co');
    final fsm = flow.fsm;
    expect(find.byKey(const ValueKey('act-btn-callflop')), findsOneWidget);
    expect(find.text('+Call'), findsWidgets);
    await tapKey(t, 'act-btn-callflop');
    expect(taps, 6);
    expect(fsm.screenPhase, ScreenPhase.pickFlop);
    expect(fsm.activeSeats, [Position.co, Position.btn]);
    expect(fsm.totalPotBB, closeTo(6.5, 1e-9));
    expect(find.byKey(const ValueKey('picker-dock')), findsOneWidget);
    expect(find.textContaining('Flop (1/3)'), findsOneWidget);
    expect(find.byKey(const ValueKey('pinned-oracle')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('Multiway: [+Call] SB y BB -> flop 3-way -> 1 toque [Check hasta mí] resuelve SB/BB y auto-ejecuta a Hero', (t) async {
    final flow = await start(t, 'As', 'Kd', 'btn');
    final fsm = flow.fsm;
    await tapKey(t, 'act-sb-call');
    expect(fsm.phase, HandPhase.preflop, reason: '[+Call] no cierra: BB aún puede entrar');
    await tapKey(t, 'act-bb-call');
    for (final c in ['Kh', '8c', '3d']) {
      await pick(t, c);
    }
    expect(fsm.activeSeats, [Position.sb, Position.bb, Position.btn]);
    expect(find.text('✓ Check hasta mí (2 villanos)'), findsOneWidget);
    final before = taps;
    await tapKey(t, 'check-to-me');
    expect(taps - before, 1);
    final flop = fsm.actions.where((a) => a.street == Street.flop).toList();
    expect(flop.take(2).map((a) => (a.actor, a.type)), [(Position.sb, ActionType.check), (Position.bb, ActionType.check)]);
    expect(flop.length, greaterThanOrEqualTo(3));
    expect(flop[2].actor, Position.btn, reason: 'Hero auto-ejecutado');
    expect(flow.lastHeroStreet, Street.flop);
    if (flop[2].isAggressive) expect(fsm.currentActorSeat, Position.sb, reason: 'turno listo en el primer villano que responde');
    expect(find.byKey(const ValueKey('check-to-me')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('Barra onChangeEnd: soltar el deslizador aplica el tamaño y actualiza el Oráculo sin botón', (t) async {
    final flow = await start(t, 'As', 'Qs', 'co');
    final fsm = flow.fsm;
    await tapKey(t, 'act-btn-3bet');
    expect(fsm.currentHighBetBB, 7.5);
    expect(oracle(t), 'ACCIÓN: CALL 7.5 bb');
    final sigBefore = fsm.stateSignature;
    expect(find.textContaining('Aplicar'), findsNothing, reason: 'sin botón de confirmación');
    final slider = find.byKey(const ValueKey('scrub-slider'));
    await t.ensureVisible(slider);
    await t.pump();
    await t.drag(slider, const Offset(60, 0));
    await t.pump();
    final nb = fsm.actions.lastWhere((a) => a.actor == Position.btn).amountBb;
    expect(nb, greaterThan(7.5), reason: 'tamaño aplicado al soltar');
    expect(fsm.stateSignature, isNot(sigBefore));
    expect(find.text('ACTUALIZADO VS BTN 3-Bet ${nb.toStringAsFixed(1)}bb'), findsOneWidget);
    expect(find.byKey(const ValueKey('pinned-oracle')), findsOneWidget);
    // Flecha +0.5bb también auto-aplica.
    final plus = find.byKey(const ValueKey('scrub-plus'));
    if (plus.evaluate().isNotEmpty) {
      await t.ensureVisible(plus);
      await t.tap(plus);
      await t.pump();
      expect(fsm.actions.lastWhere((a) => a.actor == Position.btn).amountBb, nb + .5);
    }
    expect(t.takeException(), isNull);
  });
}
