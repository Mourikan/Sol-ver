import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/application/hand_flow_fsm.dart';
import 'package:sol_ver/application/linear_hand_flow.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/ui/screens/solver_cockpit_screen.dart';
import 'package:sol_ver/ui/theme.dart';
import 'package:sol_ver/ui/widgets/two_step_card_picker.dart';

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

Finder step(String n) => find.byKey(ValueKey('wizard-$n'));

/// Setup + preflop: AsKs BTN, CO open 2.5 -> Hero auto 3-Bet 7.5 -> SB/BB fold -> CO call -> Flop Ah 9d 4c.
Future<LinearHandFlow> toFlop(WidgetTester t) async {
  await t.binding.setSurfaceSize(const Size(412, 915));
  final flow = LinearHandFlow(HandFlowFSM()..configure(stake: Stake.nl50));
  await t.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: SolverCockpitScreen(flow: flow),
    ),
  );
  final fsm = flow.fsm;
  expect(fsm.screenPhase, ScreenPhase.setupHero);
  await pick(t, 'As');
  await pick(t, 'Ks');
  await tapKey(t, 'pos-btn');
  expect(fsm.screenPhase, ScreenPhase.preflopAction);
  await tapKey(t, 'who-co');
  await tapKey(t, 'see-solver');
  expect(flow.lastHero!.action, DecisionAction.betRaise);
  expect(fsm.currentHighBetBB, closeTo(7.5, 1e-9));
  await tapKey(t, 'paid-co');
  await tapKey(t, 'go-flop');
  expect(fsm.seats[Position.sb]!.alive || fsm.seats[Position.bb]!.alive, isFalse);
  expect(fsm.screenPhase, ScreenPhase.pickFlop, reason: 'salta sola a pedir 3 cartas');
  expect(find.byKey(const ValueKey('street-current')), findsOneWidget);
  for (final c in ['Ah', '9d', '4c']) {
    await pick(t, c);
  }
  expect(fsm.screenPhase, ScreenPhase.postflopStreetAction);
  expect(find.textContaining('FLOP [A♥ 9♦ 4♣] — Turno de CO: ¿Qué hizo?'), findsOneWidget);
  return flow;
}

/// CO responde: [first] si es su primera acción de la calle; luego paga cualquier apuesta.
Future<void> villainLoop(WidgetTester t, LinearHandFlow flow, String first, {String? facingBet}) async {
  final fsm = flow.fsm;
  final st = fsm.street;
  var n = 0;
  while (fsm.screenPhase == ScreenPhase.postflopStreetAction && fsm.street == st && fsm.currentActorSeat == Position.co && n < 6) {
    final owes = fsm.currentBet - fsm.seats[Position.co]!.committed > 0;
    await tapKey(t, n == 0 && !owes ? first : (owes ? (n == 1 && facingBet != null ? facingBet : 'v-call') : 'v-check'));
    n++;
  }
}

void main() {
  testWidgets('Camino 1: AsKs BTN preflop -> flop -> turn (check-raise) -> river -> SHOWDOWN', (t) async {
    final flow = await toFlop(t);
    final fsm = flow.fsm;
    // FLOP: CO check -> Hero auto -> CO call.
    await villainLoop(t, flow, 'v-check');
    expect(flow.lastHeroStreet, Street.flop);
    expect(fsm.screenPhase, ScreenPhase.pickTurn, reason: 'salta sola a pedir el Turn');
    await pick(t, 'Kd');
    // TURN: CO check -> Hero auto bet -> CO Raise 3x -> Hero auto -> River.
    expect(find.textContaining('TURN ['), findsOneWidget);
    await tapKey(t, 'v-check');
    expect(flow.lastHeroStreet, Street.turn);
    final heroTurn = flow.lastHero!.action;
    expect(heroTurn, DecisionAction.betRaise, reason: 'dobles AK en Turn K: apuesta de valor');
    {
      expect(fsm.currentActorSeat, Position.co);
      await tapKey(t, 'v-r3x');
      expect(fsm.actions.last.actor, Position.btn, reason: 'Hero responde al check-raise con 0 toques');
      expect(flow.lastHero!.action, isNot(DecisionAction.fold));
    }
    await villainLoop(t, flow, 'v-check');
    expect(fsm.screenPhase, ScreenPhase.pickRiver);
    await pick(t, '7h');
    // RIVER: CO check -> Hero auto -> CO iguala -> SHOWDOWN (o runout directo si quedaron All-In).
    final allIn = fsm.seats[Position.btn]!.allIn || fsm.seats[Position.co]!.allIn;
    if (!allIn) {
      await villainLoop(t, flow, 'v-check');
      expect(flow.lastHeroStreet, Street.river);
    }
    expect(fsm.screenPhase, ScreenPhase.handFinished);
    expect(fsm.endReason, HandEndReason.showdown);
    expect(find.text('SHOWDOWN'), findsWidgets);
    expect(find.textContaining('SHOWDOWN — Mano completada hasta el River'), findsOneWidget);
    await tapKey(t, 'end-new-hand');
    expect(fsm.screenPhase, ScreenPhase.setupHero);
    expect(t.takeException(), isNull);
  });

  testWidgets('Camino 1b: sin check-raise -> River con acción de Hero -> CO iguala -> SHOWDOWN', (t) async {
    final flow = await toFlop(t);
    final fsm = flow.fsm;
    await villainLoop(t, flow, 'v-check');
    await pick(t, 'Kd');
    await villainLoop(t, flow, 'v-check');
    expect(fsm.screenPhase, ScreenPhase.pickRiver);
    await pick(t, '7h');
    expect(find.textContaining('RIVER ['), findsOneWidget);
    await villainLoop(t, flow, 'v-check');
    expect(flow.lastHeroStreet, Street.river);
    expect(fsm.endReason, HandEndReason.showdown);
    expect(find.byKey(const ValueKey('finish-title')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('Camino 2: Fold del rival en Turn tras la apuesta de Hero -> MANO GANADA POR FOLD sin River', (t) async {
    final flow = await toFlop(t);
    final fsm = flow.fsm;
    await villainLoop(t, flow, 'v-check');
    await pick(t, 'Kd');
    // Turn: CO check; si Hero apuesta, CO foldea. Si Hero pasa, CO apuesta y la línea se cierra igual (Hero responde).
    await tapKey(t, 'v-check');
    expect(flow.lastHero!.action, DecisionAction.betRaise, reason: 'AK top pair top kicker apuesta el Turn');
    await tapKey(t, 'v-fold');
    expect(fsm.screenPhase, ScreenPhase.handFinished);
    expect(fsm.endReason, HandEndReason.foldWin);
    expect(fsm.board.length, 4, reason: 'no se pide carta de River');
    expect(find.text('MANO GANADA POR FOLD'), findsOneWidget);
    expect(find.textContaining('Ganaste el bote de'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('Selector puro: los botones de palo solo contienen ♠ ♥ ♦ ♣', (t) async {
    await t.binding.setSurfaceSize(const Size(412, 915));
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: SolverCockpitScreen(flow: LinearHandFlow(HandFlowFSM())),
      ),
    );
    await tapKey(t, 'rank-A');
    for (final (k, g) in [('s', '♠'), ('h', '♥'), ('d', '♦'), ('c', '♣')]) {
      final texts = find.descendant(of: find.byKey(ValueKey('suit-$k')), matching: find.byType(Text)).evaluate().map((e) => (e.widget as Text).data).toList();
      expect(texts, [g], reason: 'suit-$k');
    }
    expect(TwoStepCardPicker.suits.length, 4);
    for (final w in ['Picas', 'Corazones', 'Diamantes', 'Tréboles']) {
      expect(find.textContaining(w), findsNothing);
    }
  });
}
