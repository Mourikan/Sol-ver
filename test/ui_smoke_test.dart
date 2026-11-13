import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/application/hand_flow_fsm.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/main.dart';
import 'package:sol_ver/ui/poker_table_screen.dart';
import 'package:sol_ver/ui/screens/solver_cockpit_screen.dart';
import 'package:sol_ver/ui/theme.dart';

void main() {
  testWidgets('Flujo táctil: hero BTN, AhKh, folds rápidos, veredicto y ejecución', (t) async {
    await t.binding.setSurfaceSize(const Size(360, 740));
    final fsm = HandFlowFSM();
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: PokerTableScreen(fsm: fsm)));
    await t.tap(find.byKey(const ValueKey('seat-btn')));
    await t.pump();
    expect(fsm.heroPosition, Position.btn);
    await t.tap(find.byKey(const ValueKey('card-Ah')));
    await t.tap(find.byKey(const ValueKey('card-Kh')));
    await t.pump();
    expect(fsm.phase, HandPhase.preflop);
    for (var i = 0; i < 3; i++) {
      await t.tap(find.byKey(const ValueKey('fold')));
      await t.pump();
    }
    expect(fsm.currentActor, Position.btn);
    expect(find.byKey(const ValueKey('verdict')), findsOneWidget);
    expect(find.textContaining('BET / RAISE'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('execute')));
    await t.pump();
    expect(fsm.currentActor, Position.sb);
    await t.tap(find.byKey(const ValueKey('reset')));
    await t.pump();
    expect(fsm.phase, HandPhase.setup);
  });

  testWidgets('App arranca en dark mode con el flujo lineal y el selector Rango -> Palo', (t) async {
    await t.binding.setSurfaceSize(const Size(360, 740));
    await t.pumpWidget(const SolVerApp());
    expect(find.byType(SolverCockpitScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('rank-A')), findsOneWidget);
    expect(Theme.of(t.element(find.byType(SolverCockpitScreen))).brightness, Brightness.dark);
  });
}
