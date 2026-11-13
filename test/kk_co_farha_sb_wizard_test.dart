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

Finder step(String name) => find.byKey(ValueKey('wizard-$name'));

void main() {
  for (final size in const [Size(360, 780), Size(412, 915)]) {
    testWidgets('KK en CO vs UTG open: 3-Bet auto, SB Farha + UTG call -> Flop 3-way SB ➔ UTG ➔ CO (${size.width.round()})', (t) async {
      await t.binding.setSurfaceSize(size);
      final flow = LinearHandFlow(HandFlowFSM()..configure(stake: Stake.nl50));
      await t.pumpWidget(MaterialApp(theme: buildTheme(), home: SolverCockpitScreen(flow: flow)));
      final fsm = flow.fsm;

      // PASO 1: mano + posición.
      expect(step('handAndSeat'), findsOneWidget);
      await pick(t, 'Ks');
      await pick(t, 'Kh');
      await tapKey(t, 'pos-co');
      expect(fsm.startingStackBb, 100);

      // PASO 2: antes de Hero (MP no se toca => Fold).
      expect(step('before'), findsOneWidget);
      expect(step('handAndSeat'), findsNothing, reason: 'One_Step_Per_Screen');
      expect(find.text('¿Quién entró a la mano antes de CO?'), findsOneWidget);
      expect(find.byKey(const ValueKey('who-btn')), findsNothing, reason: 'solo asientos previos a Hero');
      await tapKey(t, 'who-utg');
      expect(find.text('Tamaño de apuesta de UTG: 2.5 bb'), findsOneWidget);
      await tapKey(t, 'see-solver');
      expect(fsm.seats[Position.mp]!.alive, isFalse);

      // PASO 3: jugada auto-aplicada + quién entró después.
      expect(step('heroAndAfter'), findsOneWidget);
      expect(flow.lastHero!.action, DecisionAction.betRaise);
      expect(fsm.currentHighBetBB, closeTo(7.5, 1e-9), reason: '3-Bet ~7.5bb IP');
      expect(find.textContaining('✓ El solver asume que hiciste esta jugada'), findsOneWidget);
      expect(find.byKey(const ValueKey('override')), findsOneWidget);
      expect(find.textContaining('Después de tu Raise a 7.5 bb'), findsOneWidget);
      for (final p in ['utg', 'btn', 'sb', 'bb']) {
        expect(find.byKey(ValueKey('paid-$p')), findsOneWidget, reason: p);
      }
      await tapKey(t, 'paid-sb');
      await tapKey(t, 'paid-utg');
      expect(find.text('Ir al Flop (3 Jugadores) ➔'), findsOneWidget);
      await tapKey(t, 'go-flop');

      // PASO 4: cartas del flop.
      expect(step('boardCards'), findsOneWidget);
      expect(fsm.activeSeats, [Position.sb, Position.utg, Position.co]);
      expect(fsm.totalPotBB, closeTo(23.5, 1e-9));
      expect(fsm.seats[Position.btn]!.alive || fsm.seats[Position.bb]!.alive, isFalse);
      for (final c in ['9d', '5c', '2s']) {
        await pick(t, c);
      }

      // PASO 5: SB -> UTG -> Hero.
      expect(step('streetAction'), findsOneWidget);
      expect(find.textContaining('Turno de SB'), findsOneWidget);
      await tapKey(t, 'v-check');
      expect(find.textContaining('Turno de UTG'), findsOneWidget);
      await tapKey(t, 'v-check');
      expect(flow.lastHeroStreet, Street.flop, reason: 'turno de Hero (CO) auto-ejecutado');
      expect(fsm.actions.last.actor, Position.co);
      if (flow.lastHero!.action == DecisionAction.betRaise) {
        expect(find.textContaining('Turno de SB'), findsOneWidget, reason: 'pregunta qué respondió SB a tu apuesta');
        expect(find.byKey(const ValueKey('v-fold')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('action-dock')), findsNothing, reason: 'dock eliminado');
      expect(t.takeException(), isNull);
    });
  }
}
