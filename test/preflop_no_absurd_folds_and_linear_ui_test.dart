import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/application/hand_flow_fsm.dart';
import 'package:sol_ver/application/linear_hand_flow.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/preflop/full_tree_preflop.dart';
import 'package:sol_ver/ui/screens/solver_cockpit_screen.dart';
import 'package:sol_ver/ui/theme.dart';
import 'package:sol_ver/ui/widgets/blocker_xray.dart';
import 'package:sol_ver/ui/widgets/two_step_card_picker.dart';

Future<void> pick(WidgetTester t, String card) async {
  await t.pump();
  await t.ensureVisible(find.byKey(ValueKey('rank-${card[0]}')));
  await t.pump();
  await t.tap(find.byKey(ValueKey('rank-${card[0]}')));
  await t.pump();
  await t.ensureVisible(find.byKey(ValueKey('suit-${card[1]}')));
  await t.pump();
  await t.tap(find.byKey(ValueKey('suit-${card[1]}')));
  await t.pump();
}

Future<void> tapKey(WidgetTester t, String key) async {
  await t.ensureVisible(find.byKey(ValueKey(key)));
  await t.pump();
  await t.tap(find.byKey(ValueKey(key)));
  await t.pump();
}

Future<LinearHandFlow> boot(WidgetTester t, Size size, {Position hero = Position.btn}) async {
  await t.binding.setSurfaceSize(size);
  final flow = LinearHandFlow(HandFlowFSM()..configure(stake: Stake.nl25, hero: hero));
  await t.pumpWidget(MaterialApp(theme: buildTheme(), home: SolverCockpitScreen(flow: flow)));
  return flow;
}

void main() {
  test('TT, 99, 88, AQs, KQs vs UTG open 2.5bb: 0% fold en MP/CO/BTN/SB/BB y NL2..NL200', () {
    for (final st in Stake.values) {
      for (final hero in [Position.mp, Position.co, Position.btn, Position.sb, Position.bb]) {
        for (final h in ['TcTd', '9c9d', '8c8d', 'AcQc', 'KcQc']) {
          final d = const FullTreePreflop().decide(GameState(stake: st, heroPosition: hero, villainPosition: Position.utg, effectiveStackBb: 100,
              hero: HoleCards.parse(h), actions: const [PlayerAction(Street.preflop, Position.utg, ActionType.raise, 2.5)]));
          expect(d.action, isNot(DecisionAction.fold), reason: '${st.name} ${hero.name} $h');
          expect(d.freqGto?[DecisionAction.fold] ?? 0, 0, reason: '${st.name} ${hero.name} $h');
        }
      }
    }
  });

  testWidgets('TwoStepCardPicker: Rango -> Palo en 2 toques y bloqueo de cartas usadas', (t) async {
    final picked = <Card>[];
    await t.pumpWidget(MaterialApp(
        home: Scaffold(body: TwoStepCardPicker(dead: {Card.parse('As').id}, onPick: picked.add))));
    await t.tap(find.byKey(const ValueKey('rank-A')));
    await t.pump();
    final spade = t.widget<InkWell>(find.descendant(of: find.byKey(const ValueKey('suit-s')), matching: find.byType(InkWell)));
    expect(spade.onTap, isNull, reason: 'As ya usada');
    await t.tap(find.byKey(const ValueKey('suit-h')));
    await t.pump();
    expect(picked, [Card.parse('Ah')]);
    expect(find.byKey(const ValueKey('rank-A')), findsOneWidget, reason: 'vuelve al paso de rango');
  });

  testWidgets('Auto-commit: Open de UTG -> solución asumida -> respuesta del villano en 1 toque -> flop en 2 toques/carta', (t) async {
    // Lienzo alto: el test valida el flujo (no el scroll; los desbordes se validan en los tests de resolución).
    final flow = await boot(t, const Size(412, 1800));
    await pick(t, 'Tc');
    await pick(t, 'Td');
    await tapKey(t, 'act-utg-open25');
    await tapKey(t, 'hero-row-go');
    expect(flow.lastHero, isNotNull);
    expect(flow.lastHero!.action, isNot(DecisionAction.fold));
    expect(flow.fsm.currentActor, isNot(Position.btn), reason: 'la acción de Hero ya se asumió ejecutada');
    expect(find.byKey(const ValueKey('hero-result')), findsOneWidget);
    expect(find.byKey(const ValueKey('override')), findsOneWidget);
    // Override manual disponible: deshace el auto-commit.
    await tapKey(t, 'override');
    expect(flow.fsm.currentActor, Position.btn);
    expect(flow.manualMode, isTrue);
    await tapKey(t, 'hero-passive');
    expect(flow.manualMode, isFalse);
    await tapKey(t, 'resolve-street');
    expect(flow.fsm.phase, HandPhase.flopCards);
    for (final c in ['Kc', '7d', '2h']) {
      await pick(t, c);
    }
    expect(flow.fsm.phase, HandPhase.flop);
    expect(find.byKey(const ValueKey('act-utg-check')), findsOneWidget, reason: 'UTG actúa primero: 1 toque');
    await tapKey(t, 'act-utg-check');
    expect(flow.lastHeroStreet, Street.flop);
    expect(t.takeException(), isNull);
  });

  for (final size in const [Size(360, 780), Size(390, 844), Size(412, 915)]) {
    testWidgets('0 overflows ${size.width.round()}x${size.height.round()}: picker, escenarios, solución, heatmap, rewind', (t) async {
      final flow = await boot(t, size, hero: Position.bb);
      await pick(t, 'Ah');
      await pick(t, 'Kd');
      await tapKey(t, 'act-btn-open25');
      await tapKey(t, 'hero-row-go');
      expect(flow.lastHero, isNotNull);
      final pot = 1.5 + 2.5;
      await tapKey(t, 'peek-169');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('heatmap')), findsOneWidget);
      Navigator.of(t.element(find.byKey(const ValueKey('heatmap')))).pop();
      await t.pumpAndSettle();
      // Rewind: el chip del paso de Hero vuelve al estado exacto antes de su acción.
      final idx = flow.fsm.stepLabels.lastIndexWhere((l) => l.startsWith('BB'));
      await t.ensureVisible(find.byKey(ValueKey('crumb-$idx')));
      await t.pump();
      await t.tap(find.byKey(ValueKey('crumb-$idx')));
      await t.pump();
      expect(flow.fsm.currentActor, Position.bb);
      expect(flow.fsm.totalPotBB, closeTo(pot, 1e-9));
      expect(flow.fsm.street, Street.preflop);
      expect(BlockerXRay.of(Card.parse('As'), Card.parseMany('Ks9s4s')), XRay.nutBlocker);
      expect(t.takeException(), isNull);
      // ignore: avoid_print
      print('OVERFLOW_OK ${size.width.round()}x${size.height.round()}');
    });
  }
}
