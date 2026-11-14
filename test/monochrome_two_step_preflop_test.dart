import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/application/hand_flow_fsm.dart';
import 'package:sol_ver/application/linear_hand_flow.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/ui/screens/solver_cockpit_screen.dart';
import 'package:sol_ver/ui/theme.dart';
import 'package:sol_ver/ui/theme/obsidian_theme.dart';

Future<void> tapKey(WidgetTester t, String key) async {
  await t.pump();
  // Mesa 1 activa: incluye hijos del ListView fuera del viewport (cache extent) para poder hacer scroll hasta ellos.
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

Future<LinearHandFlow> boot(WidgetTester t, Size size) async {
  await t.binding.setSurfaceSize(size);
  final flow = LinearHandFlow(HandFlowFSM()..configure(stake: Stake.nl50));
  await t.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: SolverCockpitScreen(flow: flow),
    ),
  );
  return flow;
}

bool mono(Color c) => Obsidian.isMonochrome(c);

void main() {
  for (final size in const [Size(360, 780), Size(412, 915)]) {
    testWidgets('HU ${size.width.round()}: CO Open -> Hero BTN 3-Bet (auto) -> Pagó CO -> Flop + barra 6.5bb postflop', (t) async {
      final flow = await boot(t, size);
      final fsm = flow.fsm;
      await pick(t, 'Ah');
      await pick(t, 'Kd');
      await tapKey(t, 'pos-btn');
      expect(find.byKey(const ValueKey('preflop-table')), findsOneWidget);
      await tapKey(t, 'act-co-or');
      /* L1: Hero auto-aplicado sin [Mi turno] */
      expect(flow.lastHero!.action, DecisionAction.betRaise, reason: 'Auto-Commit del 3-Bet');
      expect(find.byKey(const ValueKey('preflop-table')), findsOneWidget);
      expect(find.textContaining('✓ El solver asume'), findsOneWidget);
      await tapKey(t, 'act-co-call');
      
      expect(fsm.phase, HandPhase.flopCards);
      expect(fsm.activeSeats, [Position.co, Position.btn]);
      for (final c in ['Qs', '7d', '2c']) {
        await pick(t, c);
      }
      expect(fsm.currentActorSeat, Position.co);
      await scrubTo(t, 6.5);
      await tapKey(t, 'v-bar');
      final bet = fsm.actions.firstWhere((a) => a.street == Street.flop && a.actor == Position.co);
      expect(bet.type, ActionType.bet);
      expect(bet.amountBb, 6.5);
      expect(flow.lastHeroStreet, Street.flop, reason: 'Hero responde con 0 toques');
      expect(t.takeException(), isNull, reason: '0 RenderFlex overflows');
    });
  }

  testWidgets('Multiway: UTG Open + MP Call -> Hero BTN Call -> Pagó BB -> Flop 4-Way', (t) async {
    final flow = await boot(t, const Size(412, 1400));
    final fsm = flow.fsm;
    await pick(t, '9h');
    await pick(t, '9c');
    await tapKey(t, 'pos-btn');
    await tapKey(t, 'act-utg-or');
    await tapKey(t, 'act-mp-call');
    /* L1: Hero auto-aplicado sin [Mi turno] */
    expect(fsm.seats[Position.co]!.alive, isFalse);
    expect(flow.lastHero, isNotNull);
    await tapKey(t, 'override');
    expect(flow.manualMode, isTrue);
    await tapKey(t, 'act-btn-call');
    await tapKey(t, 'act-bb-call');
    
    expect(fsm.phase, HandPhase.flopCards);
    expect(fsm.activeSeats, [Position.bb, Position.utg, Position.mp, Position.btn]);
    expect(fsm.totalPotBB, closeTo(10.5, 1e-9));
    expect(t.takeException(), isNull);
  });

  testWidgets('Barra deslizadora preflop: CO abre a 4.5bb exactos', (t) async {
    final flow = await boot(t, const Size(412, 915));
    await pick(t, 'Qh');
    await pick(t, 'Qd');
    await tapKey(t, 'pos-bb');
    await tapKey(t, 'act-co-or');
    expect(scrubValue(t), 2.5);
    await scrubTo(t, 4.5);
    /* L1: Hero auto-aplicado sin [Mi turno] */
    final open = flow.fsm.actions.firstWhere((a) => a.actor == Position.co);
    expect(open.type, ActionType.raise);
    expect(open.amountBb, 4.5);
    expect(flow.lastHero, isNotNull, reason: 'el solver respondió al open de 4.5bb');
  });

  test('Monochrome Titanium: paleta exacta y cero colores saturados', () {
    expect(Obsidian.bgPrimary, const Color(0xFF0C0D10));
    expect(Obsidian.surfacePanel, const Color(0xFF15171C));
    expect(Obsidian.borderFine, const Color(0xFF262932));
    expect(Obsidian.buttonDefault, const Color(0xFF1E2128));
    expect(Obsidian.buttonActive, const Color(0xFFE2E8F0));
    expect(Obsidian.buttonActiveText, const Color(0xFF0C0D10));
    expect(Obsidian.textPrimary, const Color(0xFFF8FAFC));
    expect(Obsidian.textSecondary, const Color(0xFF94A3B8));
    expect(Obsidian.textMuted, const Color(0xFF64748B));
    expect(Obsidian.rangeScale, const [Color(0xFFF8FAFC), Color(0xFFCBD5E1), Color(0xFF64748B), Color(0xFF334155)]);
    final all = [
      Obsidian.emeraldRaise,
      Obsidian.cyanCall,
      Obsidian.amberCheck,
      Obsidian.crimsonFold,
      Obsidian.violetExploit,
      AppColors.accent,
      AppColors.turn,
      AppColors.danger,
      AppColors.raise,
      AppColors.call,
      AppColors.emerald,
      AppColors.cyan,
      AppColors.amber,
      AppColors.crimson,
      AppColors.violet,
      AppColors.bg,
      AppColors.surface,
      AppColors.border,
      ...Obsidian.rangeScale,
    ];
    for (final c in all) {
      expect(mono(c), isTrue, reason: c.toString());
    }
    expect(mono(const Color(0xFF16A34A)), isFalse, reason: 'el verde antiguo sí se detecta como saturado');
  });
}
