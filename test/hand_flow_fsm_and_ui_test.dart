import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/application/hand_flow_fsm.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/reads/gg_smarthud_analyzer.dart';
import 'package:sol_ver/core/reads/villain_archetypes.dart';
import 'package:sol_ver/ui/screens/solver_cockpit_screen.dart';
import 'package:sol_ver/ui/theme.dart';

final micros = <int>[];

void heroOrVillain(HandFlowFSM fsm) {
  final p = fsm.currentActor!;
  final toCall = fsm.currentBet - fsm.seats[p]!.committed;
  if (p == fsm.heroPosition) {
    final d = fsm.activeRecommendation!;
    expect(d.perceivedVillainRange, isNotNull);
    expect(d.justification, isNotNull);
    micros.add(fsm.solverMicros);
    if (d.action == DecisionAction.fold) {
      fsm.act(p, toCall > 0 ? ActionType.call : ActionType.check);
    } else {
      fsm.executeRecommendation();
    }
  } else {
    fsm.act(p, toCall > 0 ? ActionType.call : ActionType.check);
  }
}

void playStreet(HandFlowFSM fsm) {
  var guard = 0;
  while (fsm.currentActor != null && guard++ < 20) {
    heroOrVillain(fsm);
  }
}

void main() {
  test('Mano completa: BTN AsKs, CO open 2.5 (fast-forward UTG/MP), 3-bet, call, flop->turn->river', () {
    final fsm = HandFlowFSM()..configure(stake: Stake.nl25, hero: Position.btn);
    fsm
      ..addCard(Card.parse('As'))
      ..addCard(Card.parse('Ks'));
    expect(fsm.currentPotBB, 1.5);
    fsm.act(Position.co, ActionType.raise, amountBb: 2.5);
    expect(fsm.seats[Position.utg]!.alive, isFalse);
    expect(fsm.seats[Position.mp]!.alive, isFalse);
    expect(fsm.currentActor, Position.btn);
    expect(fsm.activeRecommendation, isNotNull);
    expect(fsm.activeRecommendation!.perceivedVillainRange!.totalActiveCombos, greaterThan(0));
    fsm
      ..act(Position.btn, ActionType.raise, amountBb: 8)
      ..act(Position.sb, ActionType.fold)
      ..act(Position.bb, ActionType.fold)
      ..act(Position.co, ActionType.call);
    expect(fsm.phase, HandPhase.flopCards);
    expect(fsm.currentPotBB, closeTo(17.5, 1e-9));
    expect(fsm.currentSPR, closeTo(92 / 17.5, 1e-9));
    for (final c in ['Qh', '7d', '2c']) {
      fsm.addCard(Card.parse(c));
    }
    expect(fsm.phase, HandPhase.flop);
    expect(fsm.currentActor, Position.co);
    playStreet(fsm);
    for (final (cards, phase) in [(['5s'], HandPhase.turn), (['Jd'], HandPhase.river)]) {
      if (fsm.phase == HandPhase.handOver) break;
      final potBefore = fsm.currentPotBB;
      fsm.addCard(Card.parse(cards.first));
      expect(fsm.phase, phase);
      expect(fsm.currentPotBB, greaterThanOrEqualTo(potBefore));
      playStreet(fsm);
    }
    expect(fsm.phase, HandPhase.handOver);
    expect(fsm.board.length, 5);
    expect(micros, isNotEmpty);
    // ignore: avoid_print
    print('solver us por decisión de Hero: $micros');
  });

  test('Nueva Mano ↺: bote y cartas a cero, SmartHUD de villanos intacto (también con rotación del botón)', () {
    final fsm = HandFlowFSM()..configure(hero: Position.btn);
    fsm.setHud(Position.co, SmartHudStats.preset(VillainTag.agroManiac), manualTag: VillainTag.agroManiac);
    fsm
      ..addCard(Card.parse('Ah'))
      ..addCard(Card.parse('Kd'));
    fsm.act(Position.co, ActionType.raise, amountBb: 2.5);
    fsm.nextHand();
    expect(fsm.phase, HandPhase.setup);
    expect(fsm.currentPotBB, 0);
    expect(fsm.heroCards, isEmpty);
    expect(fsm.board, isEmpty);
    expect(fsm.actions, isEmpty);
    expect(fsm.hudOf(Position.co)!.tag, VillainTag.agroManiac);
    fsm
      ..addCard(Card.parse('Qh'))
      ..addCard(Card.parse('Qd'));
    expect(fsm.seats[Position.co]!.profile, VillainProfile.maniac);
    expect(fsm.seats[Position.co]!.hud!.tag, VillainTag.agroManiac);
    fsm.nextHand(rotateButton: true);
    expect(fsm.heroPosition, Position.co);
    expect(fsm.hudOf(Position.mp)!.tag, VillainTag.agroManiac);
    expect(fsm.hudOf(Position.co), isNull);
  });

  testWidgets('Cockpit 360x740: mano táctil sin overflow, oráculo + barra de rango, Nueva Mano conserva HUD', (t) async {
    await t.binding.setSurfaceSize(const Size(360, 740));
    final fsm = HandFlowFSM()..configure(stake: Stake.nl25);
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: SolverCockpitScreen(fsm: fsm)));
    await t.tap(find.byKey(const ValueKey('cockpit-seat-btn')));
    await t.pump();
    expect(fsm.heroPosition, Position.btn);
    fsm.setHud(Position.co, SmartHudStats.preset(VillainTag.scaredReg), manualTag: VillainTag.scaredReg);
    await t.tap(find.byKey(const ValueKey('fcm-As')));
    await t.tap(find.byKey(const ValueKey('fcm-Ks')));
    await t.pump();
    expect(fsm.phase, HandPhase.preflop);
    fsm.act(Position.co, ActionType.raise, amountBb: 2.5);
    final sw = Stopwatch()..start();
    await t.pump();
    final frameUs = sw.elapsedMicroseconds;
    expect(find.byKey(const ValueKey('oracle')), findsOneWidget);
    expect(find.byKey(const ValueKey('execute-optimal')), findsOneWidget);
    expect(find.byKey(const ValueKey('read-badge')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('act-r32')));
    await t.pump();
    expect(fsm.currentActor, Position.sb);
    await t.tap(find.byKey(const ValueKey('act-fold')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('act-fold')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('act-call')));
    await t.pump();
    expect(fsm.phase, HandPhase.flopCards);
    expect(find.byKey(const ValueKey('fcm-As')), findsOneWidget);
    for (final c in ['Qh', '7d', '2c']) {
      await t.tap(find.byKey(ValueKey('fcm-$c')));
      await t.pump();
    }
    expect(fsm.phase, HandPhase.flop);
    await t.tap(find.byKey(const ValueKey('act-check')));
    await t.pump();
    expect(fsm.currentActor, Position.btn);
    expect(find.byKey(const ValueKey('range-bar')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('execute-optimal')));
    await t.pump();
    expect(t.takeException(), isNull);
    await t.tap(find.byKey(const ValueKey('new-hand')));
    await t.pump();
    expect(fsm.phase, HandPhase.setup);
    expect(fsm.hudOf(Position.co)!.tag, VillainTag.scaredReg);
    // ignore: avoid_print
    print('frame (rebuild completo tras acción + solver) us: $frameUs');
  });
}
