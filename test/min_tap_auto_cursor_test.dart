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
  await t.ensureVisible(find.descendant(of: find.byKey(const ValueKey('pane-0')), matching: find.byKey(ValueKey(key), skipOffstage: false), skipOffstage: false));
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
  testWidgets('Velocidad extrema: BTN vs CO open -> 3-Bet auto -> CO call -> flop HU en 7 toques (tabla ordenada)', (t) async {
    final flow = await boot(t);
    final fsm = flow.fsm;
    await pick(t, 'Ah');
    await pick(t, 'Kd');
    await tapKey(t, 'pos-btn');
    expect(taps, 5);
    expect(fsm.currentActorSeat, Position.sb, reason: 'L1: OR de Hero auto-aplicado al elegir posición; cursor en SB');
    expect(find.byKey(const ValueKey('all-fold')), findsOneWidget, reason: 'steal: [Todos Foldearon]');
    await tapKey(t, 'act-co-or');
    /* L1: Hero auto-aplicado sin [Mi turno] */
    expect(fsm.seats[Position.utg]!.alive, isFalse);
    expect(fsm.seats[Position.mp]!.alive, isFalse);
    expect(flow.lastHero!.action, DecisionAction.betRaise, reason: 'Law_2: 0 toques en el turno de Hero');
    expect(fsm.currentHighBetBB, closeTo(7.5, 1e-9));
    expect(fsm.currentActorSeat, Position.sb);
    expect(fsm.pendingToAct, containsAll([Position.sb, Position.bb, Position.co]));
    expect(find.textContaining('✓ El solver asume'), findsOneWidget);
    await tapKey(t, 'act-co-call');
    
    expect(taps, 7);
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
    /* L1: Hero auto-aplicado sin [Mi turno] */
    expect(flow.lastHero!.action, DecisionAction.betRaise);
    await tapKey(t, 'act-bb-call');
    
    expect(fsm.seats[Position.sb]!.alive, isFalse);
    expect(fsm.phase, HandPhase.flopCards);
    for (final c in ['Kh', '7c', '2d']) {
      await pick(t, c);
    }
    expect(fsm.currentActorSeat, Position.bb, reason: 'el cursor arranca solo en BB');
    await tapKey(t, 'v-check');
    expect(flow.lastHeroStreet, Street.flop);
    expect(flow.lastHero!.action, DecisionAction.betRaise, reason: 'Hero auto c-bet');
    expect(fsm.currentActorSeat, Position.bb, reason: 'el cursor regresa solo a BB');
    for (final k in ['v-fold', 'v-call', 'v-r3x']) {
      expect(t.widget<FilledButton>(find.byKey(ValueKey(k))).onPressed, isNotNull, reason: k);
    }
    final heroBet = fsm.currentHighBetBB;
    await scrubTo(t, (heroBet * 3 * 2).roundToDouble() / 2);
    await tapKey(t, 'v-bar');
    expect(flow.lastHeroStreet, Street.flop);
    expect(fsm.actions.last.actor, Position.btn, reason: 'Hero respondió al check-raise con 0 toques');
    expect(fsm.currentHighBetBB, greaterThanOrEqualTo(heroBet * 3 - .3));
    expect(flow.lastHero!.action, DecisionAction.call, reason: 'TPTK vs check-raise: call');
    expect(fsm.phase, HandPhase.turnCards, reason: 'Turn abierto automáticamente');
    expect(find.byKey(const ValueKey('rank-A')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
