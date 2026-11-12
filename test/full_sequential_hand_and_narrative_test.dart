import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/application/hand_flow_fsm.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/reads/anti_counter_exploit_shield.dart';
import 'package:sol_ver/core/reads/engine_mode.dart';
import 'package:sol_ver/core/reads/gg_profiler.dart';
import 'package:sol_ver/ui/screens/solver_cockpit_screen.dart';
import 'package:sol_ver/ui/theme.dart';

final narrativeStreets = <Street>{};

void heroNarrative(HandFlowFSM fsm) {
  expect(fsm.currentActor, fsm.heroPosition);
  final j = fsm.activeRecommendation!.justification!;
  expect(j.villainReadExplanation, isNotEmpty);
  expect(j.evWhyExplanation, isNotEmpty);
  expect(j.nextStreetPlan, isNotEmpty);
  expect(j.villainReadExplanation, contains('Rival'));
  narrativeStreets.add(fsm.street);
}

void main() {
  test('Parche NL50: sin HUD => Unknown_Reg con escudo activo; NL25 => Pool', () {
    expect(ProfileDefaults.defaultFor(Stake.nl50), VillainProfile.gtoBase);
    final fsm = HandFlowFSM()..configure(stake: Stake.nl50, hero: Position.bb);
    final read = ReadProfile.fromVillainProfile(fsm.effectiveProfile(Position.btn));
    expect(read.archetype, GgArchetype.unknownReg);
    expect(AntiCounterExploitShield.active(Stake.nl50, read), isTrue);
    expect(ProfileDefaults.defaultFor(Stake.nl25), VillainProfile.poolDefault);
  });

  test('Mano completa acción por acción con loops de re-subida (preflop y flop), bote/SPR exactos y narrativa en 4 calles', () {
    final fsm = HandFlowFSM()..configure(stake: Stake.nl25, hero: Position.bb);
    fsm
      ..addCard(Card.parse('Ah'))
      ..addCard(Card.parse('Ad'));
    // Preflop: CO open (fast-forward UTG/MP) -> BTN 3-bet -> SB fold -> BB cold 4-bet -> CO fold -> BTN call.
    fsm.act(Position.co, ActionType.raise, amountBb: 2.5);
    expect(fsm.seats[Position.utg]!.alive || fsm.seats[Position.mp]!.alive, isFalse);
    fsm
      ..act(Position.btn, ActionType.raise, amountBb: 8)
      ..act(Position.sb, ActionType.fold);
    heroNarrative(fsm);
    fsm.act(Position.bb, ActionType.raise, amountBb: 20);
    expect(fsm.currentActor, Position.co, reason: 'el turno vuelve al opener tras el 4-bet');
    expect(fsm.isBettingRoundClosed, isFalse);
    fsm.act(Position.co, ActionType.fold);
    expect(fsm.currentActor, Position.btn);
    expect(fsm.isBettingRoundClosed, isFalse);
    fsm.act(Position.btn, ActionType.call);
    expect(fsm.phase, HandPhase.flopCards);
    expect(fsm.totalPotBB, closeTo(43.0, 0.005));
    expect(() => fsm.act(Position.bb, ActionType.check), throwsA(isA<IllegalAction>()), reason: 'acciones bloqueadas hasta poner el flop');
    for (final c in ['Kc', '7d', '2s']) {
      fsm.addCard(Card.parse(c));
    }
    // Flop: BB check -> BTN bet 33% -> BB check-raise 3.2x -> BTN call.
    heroNarrative(fsm);
    fsm.act(Position.bb, ActionType.check);
    fsm.act(Position.btn, ActionType.bet, amountBb: 14.19);
    expect(fsm.currentActor, Position.bb);
    heroNarrative(fsm);
    fsm.act(Position.bb, ActionType.raise, amountBb: 45.41);
    expect(fsm.currentActor, Position.btn, reason: 'el turno regresa al apostador tras el check-raise');
    expect(fsm.phase, HandPhase.flop);
    expect(fsm.currentHighBetBB, closeTo(45.41, 1e-9));
    expect(fsm.streetInvestedBB[Position.btn], closeTo(14.19, 1e-9));
    expect(fsm.isBettingRoundClosed, isFalse);
    fsm.act(Position.btn, ActionType.call);
    expect(fsm.phase, HandPhase.turnCards);
    expect(fsm.totalPotBB, closeTo(133.82, 0.005));
    expect(fsm.stackOf(Position.bb), closeTo(34.59, 0.005));
    expect(fsm.currentSPR, closeTo(34.59 / 133.82, 0.0005));
    // Turn: X-X.
    fsm.addCard(Card.parse('5h'));
    heroNarrative(fsm);
    fsm
      ..act(Position.bb, ActionType.check)
      ..act(Position.btn, ActionType.check);
    expect(fsm.phase, HandPhase.riverCards);
    // River: BB check -> BTN all-in -> BB call.
    fsm.addCard(Card.parse('9c'));
    heroNarrative(fsm);
    fsm
      ..act(Position.bb, ActionType.check)
      ..act(Position.btn, ActionType.allIn);
    heroNarrative(fsm);
    expect(fsm.activeRecommendation!.action == DecisionAction.call || fsm.activeRecommendation!.action == DecisionAction.fold, isTrue);
    fsm.act(Position.bb, ActionType.call);
    expect(fsm.phase, HandPhase.handOver);
    expect(fsm.totalPotBB, closeTo(203.0, 0.005));
    expect(narrativeStreets, {Street.preflop, Street.flop, Street.turn, Street.river});
    // Undo vuelve al estado previo exacto.
    fsm.undo();
    expect(fsm.phase, HandPhase.river);
    expect(fsm.currentActor, Position.bb);
    expect(fsm.totalPotBB, closeTo(133.82 + 34.59, 0.005));
  });

  testWidgets('Cockpit PRO 360x740: mesa GPU, tarjeta "Por qué" con 3 bloques y barra secuencial', (t) async {
    await t.binding.setSurfaceSize(const Size(360, 740));
    final fsm = HandFlowFSM()..configure(stake: Stake.nl25);
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: SolverCockpitScreen(fsm: fsm)));
    expect(find.byKey(const ValueKey('pro-table')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('cockpit-seat-bb')));
    await t.pump();
    expect(fsm.heroPosition, Position.bb);
    await t.tap(find.byKey(const ValueKey('fcm-Ah')));
    await t.tap(find.byKey(const ValueKey('fcm-Ad')));
    await t.pump();
    expect(find.textContaining('TURNO DE: UTG'), findsOneWidget);
    fsm.act(Position.co, ActionType.raise, amountBb: 2.5);
    await t.pump();
    await t.tap(find.byKey(const ValueKey('act-fold'))); // BTN
    await t.pump();
    await t.tap(find.byKey(const ValueKey('act-fold'))); // SB
    await t.pump();
    expect(find.textContaining('TU TURNO'), findsOneWidget);
    for (final k in ['why-1', 'why-2', 'why-3', 'range-bar', 'oracle-evs', 'execute-optimal', 'undo']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    await t.tap(find.byKey(const ValueKey('undo')));
    await t.pump();
    expect(fsm.currentActor, Position.sb);
    expect(t.takeException(), isNull);
  });
}
