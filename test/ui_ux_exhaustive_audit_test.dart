import 'dart:io';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/application/hand_flow_fsm.dart';
import 'package:sol_ver/application/linear_hand_flow.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/ui/screens/solver_cockpit_screen.dart';
import 'package:sol_ver/ui/theme.dart';
import 'package:sol_ver/ui/theme/obsidian_theme.dart';

var taps = 0;
final smallFound = <String>{};

const _targets = [
  'act-',
  'v-',
  'pos-',
  'rank-',
  'suit-',
  'hero-go',
  'advance-flop',
  'override',
  'undo',
  'new-hand',
  'tab-',
  'rush-reset',
  'end-new-hand',
  'hud-',
  'resize-',
  'scrub-plus',
  'scrub-minus',
];

/// U8: todo control interactivo visible >= 42dp en ambos ejes.
void auditTargets(WidgetTester t) {
  for (final e
      in find.byWidgetPredicate((w) => w.key is ValueKey<String> && _targets.any((p) => (w.key! as ValueKey<String>).value.startsWith(p))).evaluate()) {
    final k = (e.widget.key! as ValueKey<String>).value;
    if (e.widget is Text || e.widget is RichText) continue;
    final ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
    final s = ro.size;
    if (s.height < 42 - 1e-6 || s.width < 42 - 1e-6) smallFound.add('$k ${s.width.toStringAsFixed(0)}x${s.height.toStringAsFixed(0)}');
  }
}

/// U3: nunca un estado sin salida (deadlock) mientras la mano sigue.
void auditNoDeadlock(LinearHandFlow f) {
  final fsm = f.fsm;
  if (fsm.screenPhase == ScreenPhase.handFinished || fsm.awaitingCards || fsm.phase == HandPhase.setup) return;
  final any =
      [
        'hero-go',
        'advance-flop',
        'v-check',
        'v-fold',
        'v-call',
        'hero-passive',
        'hero-fold',
        'pos-',
      ].any((k) => find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith(k)).evaluate().isNotEmpty) ||
      find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('act-')).evaluate().isNotEmpty;
  expect(any, isTrue, reason: 'deadlock: sin controles en ${fsm.screenPhase} actor=${fsm.currentActorSeat}');
}

LinearHandFlow? _cur;

Future<void> tapKey(WidgetTester t, String key) async {
  await t.pump();
  final any = find.descendant(of: find.byKey(const ValueKey('pane-0')), matching: find.byKey(ValueKey(key), skipOffstage: false), skipOffstage: false);
  await t.ensureVisible(any);
  await t.pump();
  await t.tap(find.byKey(ValueKey(key)));
  await t.pump();
  taps++;
  auditTargets(t);
  if (_cur != null) auditNoDeadlock(_cur!);
}

Future<void> pick(WidgetTester t, String card) async {
  await tapKey(t, 'rank-${card[0]}');
  await tapKey(t, 'suit-${card[1]}');
}

bool has(String k) => find.byKey(ValueKey(k)).evaluate().isNotEmpty;
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

Future<LinearHandFlow> start(WidgetTester t, String c1, String c2, String pos, {Size size = const Size(412, 915)}) async {
  await t.binding.setSurfaceSize(size);
  final flow = LinearHandFlow(HandFlowFSM()..configure(stake: Stake.nl50));
  _cur = flow;
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

Future<void> heroDoes(WidgetTester t, LinearHandFlow flow, DecisionAction want, String key) async {
  if (flow.lastHero!.action == want) return;
  await tapKey(t, 'override');
  await tapKey(t, key);
}

void main() {
  tearDown(() => _cur = null);

  test('U1 Monochrome Titanium: cero colores saturados hardcodeados en lib/ui', () {
    final neon = RegExp(
      r'(?<!App)Colors\.(red|green|blue|amber|orange|purple|cyan|teal|yellow|pink|indigo|lime|deepOrange|deepPurple|lightBlue|lightGreen|redAccent|greenAccent|blueAccent)\b',
    );
    final hex = RegExp(r'Color\(0x([0-9A-Fa-f]{8})\)');
    final bad = <String>[];
    for (final f in Directory('lib/ui').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      for (final m in neon.allMatches(src)) {
        bad.add('${f.path}: ${m[0]}');
      }
      for (final m in hex.allMatches(src)) {
        final c = Color(int.parse(m[1]!, radix: 16));
        if (!Obsidian.isMonochrome(c)) bad.add('${f.path}: ${m[0]}');
      }
    }
    expect(bad, isEmpty);
    for (final c in [Obsidian.bgPrimary, Obsidian.surfacePanel, Obsidian.buttonDefault, Obsidian.buttonActive, ...Obsidian.rangeScale]) {
      expect(Obsidian.isMonochrome(c), isTrue);
    }
    expect(Obsidian.bgPrimary, const Color(0xFF0C0D10));
    expect(Obsidian.buttonDefault, const Color(0xFF1E2128));
  });

  testWidgets('U2 Setup 1° mano -> 2° posición + teclado abajo con palos solo símbolo', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    final flow = LinearHandFlow(HandFlowFSM()..configure(stake: Stake.nl50));
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: SolverCockpitScreen(flow: flow),
      ),
    );
    expect(t.widget<FilledButton>(find.byKey(const ValueKey('pos-btn'))).onPressed, isNull);
    expect(t.getBottomLeft(find.byKey(const ValueKey('picker-dock'))).dy, closeTo(844, 1));
    await tapKey(t, 'rank-A');
    for (final (k, g) in [('s', '♠'), ('h', '♥'), ('d', '♦'), ('c', '♣')]) {
      final texts = find.descendant(of: find.byKey(ValueKey('suit-$k')), matching: find.byType(Text)).evaluate().map((e) => (e.widget as Text).data).toList();
      expect(texts, [g]);
    }
    for (final w in ['Picas', 'Corazones', 'Diamantes', 'Tréboles']) {
      expect(find.textContaining(w), findsNothing);
    }
    expect(t.getBottomLeft(find.byKey(const ValueKey('picker-dock'))).dy, closeTo(844, 1));
    await tapKey(t, 'suit-s');
    await pick(t, 'Kd');
    expect(t.widget<FilledButton>(find.byKey(const ValueKey('pos-btn'))).onPressed, isNotNull);
    expect(find.byKey(const ValueKey('picker-dock')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('U3 Hero OR -> 3-Bet de la BB -> turno de Hero reabierto (sin toques extra)', (t) async {
    final flow = await start(t, 'Ac', 'Jc', 'btn');
    final fsm = flow.fsm;
    /* L1: Hero auto-aplicado sin [Mi turno] */
    expect(flow.lastHero!.action, DecisionAction.betRaise);
    await tapKey(t, 'act-bb-3bet');
    expect(fsm.seats[Position.sb]!.alive, isFalse);
    expect(fsm.actions.last.actor, Position.btn, reason: 'Hero re-evaluado al instante vs 3-Bet de la BB');
    expect(fsm.screenPhase == ScreenPhase.preflopAction || fsm.screenPhase == ScreenPhase.pickFlop || fsm.screenPhase == ScreenPhase.handFinished, isTrue);
    expect(t.takeException(), isNull);
  });

  testWidgets('U3 Escalada OR -> 3B -> 4B -> 5B -> Call sin deadlocks', (t) async {
    final flow = await start(t, 'Kc', 'Kd', 'co');
    final fsm = flow.fsm;
    await tapKey(t, 'act-utg-or');
    await tapKey(t, 'act-mp-3bet');
    expect(fsm.actions.last.actor, Position.co);
    await heroDoes(t, flow, DecisionAction.betRaise, 'act-co-4bet');
    expect(fsm.actions.where((a) => a.street == Street.preflop && a.isAggressive).length, 3);
    await tapKey(t, 'act-mp-5bet');
    expect(fsm.seats[Position.utg]!.alive || fsm.seats[Position.btn]!.alive, isFalse);
    expect(fsm.actions.last.actor, Position.co, reason: 'turno de Hero reabierto vs 5-Bet');
    await heroDoes(t, flow, DecisionAction.call, 'act-co-call');
    expect(fsm.screenPhase, ScreenPhase.pickFlop);
    expect(t.takeException(), isNull);
  });

  testWidgets('U4 Barra contextual: Min-3B a 5bb y re-ajuste a 6bb recalculan a Hero; bet postflop 3.5bb', (t) async {
    final flow = await start(t, 'Qh', 'Jh', 'co');
    final fsm = flow.fsm;
    /* L1: Hero auto-aplicado sin [Mi turno] */
    expect(fsm.currentHighBetBB, 2.5);
    await tapKey(t, 'act-btn-min3b');
    expect(fsm.currentHighBetBB, 4.0, reason: 'min-3B legal = 2.5 + 1.5');
    expect(find.text('Ajustar tamaño de BTN: 4.0 bb'), findsOneWidget, reason: 'barra junto a la acción ajustada');
    await scrubTo(t, 5.0);
    expect(fsm.currentHighBetBB, 5.0, reason: 'Min-3Bet re-ajustado a 5bb');
    /* L1: Hero auto-aplicado sin [Mi turno] */
    expect(fsm.actions.last.actor, Position.co, reason: 'Hero evaluado vs 3-Bet de 5bb');
    final d1 = flow.lastHero;
    final pot1 = fsm.totalPotBB;
    await scrubTo(t, 6.0);
    expect(fsm.currentHighBetBB, greaterThanOrEqualTo(6.0));
    expect(identical(flow.lastHero, d1), isFalse, reason: 're-evaluación del solver con el nuevo tamaño');
    expect(fsm.totalPotBB, isNot(pot1));
    // Si Hero pagó, el flop llega; BTN apuesta 3.5bb exactos con la barra.
    if (fsm.screenPhase == ScreenPhase.pickFlop) {
      for (final c in ['8s', '5d', '2c']) {
        await pick(t, c);
      }
      if (fsm.currentActorSeat == Position.co) return;
      await scrubTo(t, 3.5);
      final before = fsm.totalPotBB;
      await tapKey(t, 'v-bar');
      final bet = fsm.actions.lastWhere((a) => a.actor == Position.btn && a.street == Street.flop);
      expect(bet.amountBb, 3.5, reason: 'bet raro 3.5bb inyectado al motor');
      expect(fsm.totalPotBB, greaterThanOrEqualTo(before + 3.5 - 1e-9), reason: 'bote actualizado');
      expect(flow.lastHeroStreet, Street.flop, reason: 'Hero evaluado vs bet de 3.5bb');
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('U5 Oráculo visible al cerrar la calle + [Hice otra cosa]', (t) async {
    final flow = await start(t, 'As', 'Qs', 'co');
    /* L1: Hero auto-aplicado sin [Mi turno] */
    await tapKey(t, 'act-btn-3bet');
    /* L1: Hero auto-aplicado sin [Mi turno] */
    final fsm = flow.fsm;
    if (fsm.screenPhase == ScreenPhase.pickFlop) {
      expect(find.byKey(const ValueKey('hero-result')), findsOneWidget, reason: 'oráculo NO desaparece al pedir el flop');
      expect(find.byKey(const ValueKey('why-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('picker-dock')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('override')), findsOneWidget);
    final why = t.widget<RichText>(find.byKey(const ValueKey('why-2')));
    expect(why.maxLines, isNull, reason: 'porqué sin truncar');
    expect(why.overflow, TextOverflow.clip);
    expect(t.takeException(), isNull);
  });

  testWidgets('U6 Multiway 4-way: fold a mitad del flop + check-raise en turn sin corromper el orden', (t) async {
    final flow = await start(t, '9s', '9h', 'btn');
    final fsm = flow.fsm;
    await tapKey(t, 'act-mp-or');
    await tapKey(t, 'act-co-call');
    await heroDoes(t, flow, DecisionAction.call, 'act-btn-call');
    await tapKey(t, 'act-bb-call');
    expect(fsm.screenPhase, ScreenPhase.pickFlop);
    expect(fsm.activeSeats, [Position.bb, Position.mp, Position.co, Position.btn]);
    for (final c in ['Kd', '7c', '2h']) {
      await pick(t, c);
    }
    expect(find.textContaining('Turno BB'), findsOneWidget);
    await tapKey(t, 'v-check');
    expect(find.textContaining('Turno MP'), findsOneWidget);
    await tapKey(t, 'v-b50');
    expect(find.textContaining('Turno CO'), findsOneWidget);
    await tapKey(t, 'v-fold');
    expect(fsm.activeSeats, [Position.bb, Position.mp, Position.btn]);
    // Hero responde solo; luego BB.
    if (fsm.screenPhase == ScreenPhase.postflopStreetAction && fsm.currentActorSeat == Position.bb) await tapKey(t, 'v-call');
    if (fsm.screenPhase == ScreenPhase.postflopStreetAction && fsm.currentActorSeat == Position.mp) await tapKey(t, 'v-call');
    if (fsm.screenPhase == ScreenPhase.handFinished) return;
    expect(fsm.screenPhase, ScreenPhase.pickTurn);
    await pick(t, '4s');
    final order = fsm.activeSeats;
    expect(order.first, Position.bb);
    await tapKey(t, 'v-check');
    if (fsm.currentActorSeat == Position.mp) await tapKey(t, 'v-check');
    if (flow.lastHeroStreet == Street.turn && flow.lastHero!.action == DecisionAction.betRaise && fsm.currentActorSeat == Position.bb) {
      await tapKey(t, 'v-r3x');
      expect(fsm.currentActorSeat, isNot(Position.bb));
      expect(fsm.activeSeats.where((p) => p != Position.bb).every(order.contains), isTrue);
      expect(fsm.pendingToAct.contains(Position.mp) || !fsm.seats[Position.mp]!.alive, isTrue, reason: 'el check-raise reabre a MP');
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('U7 Single-Table: sin pestañas, [↶ Deshacer] y [⚡ Nueva Mano] físicos >= 44dp', (t) async {
    final flow = await start(t, 'As', 'Ad', 'btn');
    expect(find.byKey(const ValueKey('dual-tabs')), findsNothing);
    expect(find.byKey(const ValueKey('tab-1')), findsNothing);
    for (final k in ['undo', 'new-hand']) {
      expect(t.getSize(find.byKey(ValueKey(k))).height, greaterThanOrEqualTo(44), reason: k);
    }
    /* L1: Hero auto-aplicado sin [Mi turno] */
    final n = flow.fsm.actions.length;
    await tapKey(t, 'undo');
    expect(flow.fsm.actions.length, lessThan(n), reason: 'Deshacer físico funciona');
    await tapKey(t, 'new-hand');
    expect(flow.fsm.phase, HandPhase.setup);
    expect(t.takeException(), isNull);
  });

  for (final size in const [Size(360, 780), Size(390, 844), Size(412, 915)]) {
    testWidgets('U8 Geometría ${size.width.round()}x${size.height.round()}: 0 overflows + targets >= 42dp en todas las fases', (t) async {
      smallFound.clear();
      final flow = await start(t, 'Ah', 'Kh', 'btn', size: size);
      final fsm = flow.fsm;
      await tapKey(t, 'act-co-or');
      await tapKey(t, 'act-co-call');
      for (final c in ['Ad', '9c', '4s']) {
        await pick(t, c);
      }
      await tapKey(t, 'v-check');
      if (fsm.currentActorSeat == Position.co) await tapKey(t, 'v-call');
      await pick(t, '2d');
      await tapKey(t, 'v-check');
      if (fsm.currentActorSeat == Position.co) await tapKey(t, 'v-fold');
      if (fsm.screenPhase == ScreenPhase.pickRiver) {
        await pick(t, '7h');
        await tapKey(t, 'v-check');
        if (fsm.currentActorSeat == Position.co) await tapKey(t, 'v-call');
      }
      expect(fsm.screenPhase, ScreenPhase.handFinished);
      auditTargets(t);
      expect(smallFound, isEmpty, reason: smallFound.join(', '));
      expect(t.takeException(), isNull);
      // ignore: avoid_print
      print('TAPS_FULL_HAND ${size.width.round()} $taps');
    });
  }

  testWidgets('Tap-count benchmark', (t) async {
    // Steal preflop: mano + posición + [Mi turno] + [Todos foldearon].
    var flow = await start(t, 'Ah', 'Td', 'btn');
    /* L1: Hero auto-aplicado sin [Mi turno] */
    await tapKey(t, 'all-fold');
    expect(flow.fsm.screenPhase, ScreenPhase.handFinished);
    // ignore: avoid_print
    print('TAPS_STEAL $taps');
    // Defensa vs 3-Bet: Hero CO abre, BTN 3-Bet, SB/BB sin tocar.
    flow = await start(t, 'Ah', 'Qd', 'co');
    /* L1: Hero auto-aplicado sin [Mi turno] */
    await tapKey(t, 'act-btn-3bet');
    /* L1: Hero auto-aplicado sin [Mi turno] */
    expect(flow.fsm.actions.last.actor, Position.co);
    // ignore: avoid_print
    print('TAPS_DEF3B $taps');

  });
}
