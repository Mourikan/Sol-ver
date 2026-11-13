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
  await t.ensureVisible(find.byKey(ValueKey(key)));
  await t.pump();
  await t.tap(find.byKey(ValueKey(key)));
  await t.pump();
  taps++;
}

Future<void> pick(WidgetTester t, String card) async {
  await tapKey(t, 'rank-${card[0]}');
  await tapKey(t, 'suit-${card[1]}');
}

Future<void> scrubTo(WidgetTester t, double v) async {
  for (var i = 0; i < 400; i++) {
    final cur = double.parse((t.widget<Text>(find.byKey(const ValueKey('scrub-value'))).data!).split('bb').first);
    if ((cur - v).abs() < 1e-9) return;
    await t.tap(find.byKey(ValueKey(cur < v ? 'scrub-plus' : 'scrub-minus')));
    await t.pump();
  }
}

Future<LinearHandFlow> boot(WidgetTester t) async {
  await t.binding.setSurfaceSize(const Size(412, 2400));
  final flow = LinearHandFlow(HandFlowFSM()..configure(stake: Stake.nl50));
  await t.pumpWidget(MaterialApp(theme: buildTheme(), home: SolverCockpitScreen(flow: flow)));
  taps = 0;
  return flow;
}

void main() {
  testWidgets('Velocidad extrema: BTN vs CO open -> 3-Bet auto -> CO call -> flop HU en 9 toques (2 tarjetas)', (t) async {
    final flow = await boot(t);
    final fsm = flow.fsm;
    await pick(t, 'Ah');
    await pick(t, 'Kd');
    await tapKey(t, 'pos-btn');
    expect(taps, 5);
    expect(fsm.currentActorSeat, Position.utg, reason: 'Law_1: el cursor arranca solo en UTG');
    expect(find.byKey(const ValueKey('all-fold')), findsNothing);
    await tapKey(t, 'who-co');
    await tapKey(t, 'act-open');
    expect(fsm.seats[Position.utg]!.alive, isFalse);
    expect(fsm.seats[Position.mp]!.alive, isFalse);
    expect(flow.lastHero!.action, DecisionAction.betRaise, reason: 'Law_2: 0 toques en el turno de Hero');
    expect(fsm.currentHighBetBB, closeTo(7.5, 1e-9));
    expect(fsm.currentActorSeat, Position.sb);
    expect(fsm.pendingToAct, containsAll([Position.sb, Position.bb, Position.co]));
    expect(find.textContaining('(Auto-Aplicado)'), findsOneWidget);
    await tapKey(t, 'paid-co');
    await tapKey(t, 'go-flop');
    expect(taps, 9);
    expect(fsm.seats[Position.sb]!.alive, isFalse);
    expect(fsm.seats[Position.bb]!.alive, isFalse);
    expect(fsm.phase, HandPhase.flopCards, reason: 'Law_3: cierre automático sin botón');
    expect(fsm.totalPotBB, closeTo(16.5, 1e-9));
    expect(find.byKey(const ValueKey('rank-A')), findsOneWidget, reason: 'selector de flop abierto');
    expect(t.takeException(), isNull);
  });

  testWidgets('Re-raise loop postflop: BB check -> Hero auto bet -> BB raise 3x -> Hero auto vs check-raise -> Turn', (t) async {
    final flow = await boot(t);
    final fsm = flow.fsm;
    await pick(t, 'As');
    await pick(t, 'Kd');
    await tapKey(t, 'pos-btn');
    await tapKey(t, 'nobody-in');
    expect(flow.lastHero!.action, DecisionAction.betRaise);
    await tapKey(t, 'paid-bb');
    await tapKey(t, 'go-flop');
    expect(fsm.seats[Position.sb]!.alive, isFalse);
    expect(fsm.phase, HandPhase.flopCards);
    for (final c in ['Kh', '7c', '2d']) {
      await pick(t, c);
    }
    expect(fsm.currentActorSeat, Position.bb, reason: 'el cursor arranca solo en BB');
    await tapKey(t, 'dock-passive');
    expect(flow.lastHeroStreet, Street.flop);
    expect(flow.lastHero!.action, DecisionAction.betRaise, reason: 'Hero auto c-bet');
    expect(fsm.currentActorSeat, Position.bb, reason: 'el cursor regresa solo a BB');
    for (final k in ['dock-fold', 'dock-passive', 'dock-bar']) {
      expect(t.widget<FilledButton>(find.byKey(ValueKey(k))).onPressed, isNotNull, reason: k);
    }
    final heroBet = fsm.currentHighBetBB;
    await scrubTo(t, (heroBet * 3 * 2).roundToDouble() / 2);
    await tapKey(t, 'dock-bar');
    expect(flow.lastHeroStreet, Street.flop);
    expect(fsm.actions.last.actor, Position.btn, reason: 'Hero respondió al check-raise con 0 toques');
    expect(fsm.currentHighBetBB, greaterThanOrEqualTo(heroBet * 3 - .3));
    expect(flow.lastHero!.action, DecisionAction.call, reason: 'TPTK vs check-raise: call');
    expect(fsm.phase, HandPhase.turnCards, reason: 'Turn abierto automáticamente');
    expect(find.byKey(const ValueKey('rank-A')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
