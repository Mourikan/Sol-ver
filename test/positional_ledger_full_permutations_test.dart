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
  await t.ensureVisible(find.descendant(of: find.byKey(const ValueKey('pane-0')), matching: find.byKey(ValueKey(key), skipOffstage: false), skipOffstage: false));
  await t.pump();
  await t.tap(find.byKey(ValueKey(key)));
  await t.pump();
}

Future<void> pick(WidgetTester t, String card) async {
  await tapKey(t, 'rank-${card[0]}');
  await tapKey(t, 'suit-${card[1]}');
}

LinearHandFlow _flow(Position hero, String cards) {
  final f = LinearHandFlow(HandFlowFSM()..configure(stake: Stake.nl25, hero: hero));
  f.pickCard(Card.parse(cards.substring(0, 2)));
  f.pickCard(Card.parse(cards.substring(2, 4)));
  return f;
}

void _flop(LinearHandFlow f, [List<String> cs = const ['Qh', '7d', '2c']]) {
  for (final c in cs) {
    f.pickCard(Card.parse(c));
  }
}

/// MP abre (manual), BTN y BB pagan => flop BB ➔ MP(Hero) ➔ BTN.
LinearHandFlow _threeWayFlop() {
  final f = _flow(Position.mp, 'AsKs')..manualMode = true;
  f.heroGo();
  f.heroManual(ActionType.raise, amount: 2.5);
  f.seatAct(Position.btn, ActionType.call);
  f.seatAct(Position.bb, ActionType.call);
  _flop(f);
  return f;
}

void main() {
  testWidgets('1 · Salto implícito + multiway tras Hero: AsKs MP -> BTN call, BB call -> flop BB ➔ MP ➔ BTN', (t) async {
    await t.binding.setSurfaceSize(const Size(412, 2400));
    final flow = LinearHandFlow(HandFlowFSM()..configure(stake: Stake.nl25));
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: SolverCockpitScreen(flow: flow)));
    await pick(t, 'As');
    await pick(t, 'Ks');
    await tapKey(t, 'pos-mp');
    expect(flow.fsm.heroPosition, Position.mp);
    expect(flow.lastHero, isNull, reason: 'sin auto-commit hasta tocar la fila de Hero');
    expect(find.byKey(const ValueKey('row-utg')), findsOneWidget);
    if (find.byKey(const ValueKey('hero-go')).evaluate().isNotEmpty) await tapKey(t, 'hero-go');
    expect(flow.fsm.seats[Position.utg]!.alive, isFalse);
    expect(flow.lastHero!.action, DecisionAction.betRaise);
    await tapKey(t, 'act-btn-call');
    await tapKey(t, 'act-bb-call');
    if (find.byKey(const ValueKey('advance-flop')).evaluate().isNotEmpty) await tapKey(t, 'advance-flop');
    expect(flow.fsm.seats[Position.co]!.alive, isFalse);
    expect(flow.fsm.seats[Position.sb]!.alive, isFalse);
    expect(flow.fsm.phase, HandPhase.flopCards);
    for (final c in ['Qh', '7d', '2c']) {
      await pick(t, c);
    }
    expect(flow.fsm.activeSeats, [Position.bb, Position.mp, Position.btn]);
    expect(find.textContaining('Turno BB'), findsOneWidget);
    expect(find.byKey(const ValueKey('v-check')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  test('2 · Loop de re-subida: UTG open, MP call, Hero CO call, BTN squeeze 12 -> UTG ➔ MP ➔ Hero', () {
    final f = _flow(Position.co, '7h7d')..manualMode = true;
    f.seatAct(Position.utg, ActionType.raise, amount: 2.5);
    f.seatAct(Position.mp, ActionType.call);
    expect(f.fsm.currentActor, Position.co);
    f.heroManual(ActionType.call);
    f.seatAct(Position.btn, ActionType.raise, amount: 12);
    expect(f.fsm.currentActor, Position.sb);
    expect(f.fsm.canTap(Position.utg), isTrue, reason: 'la ronda se reabre y da la vuelta');
    f.seatAct(Position.utg, ActionType.call);
    expect(f.fsm.seats[Position.sb]!.alive, isFalse);
    expect(f.fsm.seats[Position.bb]!.alive, isFalse);
    expect(f.fsm.activeSeats, isNot(contains(Position.sb)));
    expect(f.fsm.phase, HandPhase.preflop);
    expect(f.fsm.currentActor, Position.mp);
    expect(f.fsm.canTap(Position.btn), isFalse, reason: 'BTN ya igualó: no vuelve a hablar');
    f.manualMode = true;
    f.seatAct(Position.mp, ActionType.call);
    expect(f.fsm.phase, HandPhase.preflop, reason: 'Hero no igualó los 12bb: prohibido pasar al flop');
    expect(f.fsm.currentActor, Position.co);
    expect(f.fsm.activeRecommendation, isNotNull);
    f.heroManual(ActionType.call);
    expect(f.fsm.phase, HandPhase.flopCards);
    expect(f.fsm.activeSeats, [Position.utg, Position.mp, Position.co, Position.btn]);
  });

  test('3 · Eliminación dinámica postflop: BB check, Hero bet 50%, BTN call, BB fold -> Turn HU', () {
    final f = _threeWayFlop();
    expect(f.fsm.activeSeats, [Position.bb, Position.mp, Position.btn]);
    f.manualMode = true;
    f.seatAct(Position.bb, ActionType.check);
    expect(f.fsm.currentActor, Position.mp);
    f.heroManual(ActionType.bet, amount: f.fsm.pot * .5);
    f.seatAct(Position.btn, ActionType.call);
    expect(f.fsm.currentActor, Position.bb, reason: 'el turno vuelve a BB');
    f.seatAct(Position.bb, ActionType.fold);
    expect(f.fsm.phase, HandPhase.turnCards);
    expect(f.fsm.activeSeats, [Position.mp, Position.btn]);
  });

  test('4 · Check-raise postflop: el turno vuelve a Hero (BTN) con recomendación antes del Turn', () {
    final f = _flow(Position.btn, 'Ah9h')..manualMode = true;
    f.heroGo();
    f.heroManual(ActionType.raise, amount: 2.5);
    f.seatAct(Position.bb, ActionType.call);
    expect(f.fsm.activeSeats, [Position.bb, Position.btn]);
    _flop(f, ['Kc', '7d', '2h']);
    f.manualMode = true;
    f.seatAct(Position.bb, ActionType.check);
    final bet = (f.fsm.pot * .33 * 100).roundToDouble() / 100;
    f.heroManual(ActionType.bet, amount: bet);
    f.manualMode = true;
    f.seatAct(Position.bb, ActionType.raise, amount: bet * 3.2);
    expect(f.fsm.phase, HandPhase.flop);
    expect(f.fsm.currentActor, Position.btn);
    expect(f.fsm.activeRecommendation, isNotNull);
    expect(f.fsm.awaitingCards, isFalse);
    // Auto-commit: la recomendación vs check-raise se asume y solo entonces se cierra la calle.
    f.manualMode = false;
    f.undoLast();
    f.seatAct(Position.bb, ActionType.raise, amount: bet * 3.2);
    expect(f.lastHeroStreet, Street.flop);
    expect(f.fsm.actions.last.actor, Position.btn);
  });
}
