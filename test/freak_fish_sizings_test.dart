import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/application/hand_flow_fsm.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/postflop/postflop_heuristic_engine.dart';
import 'package:sol_ver/core/preflop/full_tree_preflop.dart';
import 'package:sol_ver/core/reads/freak_fish_sizing_decoder.dart';

PlayerAction a(Street s, Position p, ActionType t, [double x = 0]) => PlayerAction(s, p, t, x);
PlayerAction pf(Position p, ActionType t, [double x = 0]) => a(Street.preflop, p, t, x);
const srp = [PlayerAction(Street.preflop, Position.btn, ActionType.raise, 2.5), PlayerAction(Street.preflop, Position.bb, ActionType.call, 2.5)];
const post = PostflopHeuristicEngine();

void main() {
  GameState clickBack(String h) => GameState(stake: Stake.nl10, heroPosition: Position.utg, villainPosition: Position.btn, effectiveStackBb: 100,
      villainProfile: VillainProfile.poolDefault, hero: HoleCards.parse(h),
      actions: [pf(Position.utg, ActionType.raise, 2.5), pf(Position.mp, ActionType.call, 2.5), pf(Position.co, ActionType.fold),
        pf(Position.btn, ActionType.raise, 5.0), pf(Position.sb, ActionType.fold), pf(Position.bb, ActionType.fold)]);

  test('1. UTG 2.5 -> MP call -> BTN min-3bet 5.0: odds 2.5/14 = 17.9%; 77/87s call 100%; AA/KK 4-bet grande', () {
    final cb = FreakFishSizingDecoder.clickBack(clickBack('7c7d'))!;
    expect(cb.callCostBb, 2.5);
    expect(cb.potBb + cb.callCostBb, 14.0);
    expect(cb.directPotOdds, closeTo(2.5 / 14.0, 1e-9));
    for (final h in ['7c7d', '8h7h']) {
      final d = const FullTreePreflop().decide(clickBack(h));
      expect(d.action, DecisionAction.call, reason: h);
      expect(d.freqGto, {DecisionAction.call: 1.0});
      expect(d.justification!.evWhyExplanation, contains('Min-3Bet de recreativo'));
    }
    for (final h in ['AhAd', 'KhKd']) {
      final d = const FullTreePreflop().decide(clickBack(h));
      expect(d.action, DecisionAction.betRaise, reason: h);
      expect(d.sizing!.bb, inInclusiveRange(18, 20));
    }
    final r = const FullTreePreflop().decide(clickBack('7c7d')).perceivedVillainRange!;
    expect(r.topRepresentativeHands.any((x) => x == 'AA' || x == 'KK'), isTrue, reason: 'rango bifurcado: 35% AA/KK');
  });

  test('2. 1bb en bote de 15bb (6.7%): TPGK sube al ~80% del bote total (11-13bb), no 3bb', () {
    final g = GameState(stake: Stake.nl10, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 90, potBb: 15,
        villainProfile: VillainProfile.poolDefault, hero: HoleCards.parse('KdQc'), board: Card.parseMany('Kc7d2h'),
        actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1)]);
    final d = post.decide(g);
    expect(d.action, DecisionAction.betRaise);
    expect(d.sizing!.bb, inInclusiveRange(11, 13));
    final r = d.perceivedVillainRange!;
    expect(r.isCapped, isTrue);
    expect(r.nutsAndMonstersPct, lessThan(0.04));
  });

  test('3. Min-raise de Fish en River (NL25): top pair => fold con explicación en español', () {
    final g = GameState(stake: Stake.nl25, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 80, potBb: 20,
        villainProfile: VillainProfile.callingStation, hero: HoleCards.parse('KdQc'), board: Card.parseMany('Kc7d2h4s9c'),
        actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8), a(Street.flop, Position.bb, ActionType.call, 1.8),
          a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 6.4), a(Street.turn, Position.bb, ActionType.call, 6.4),
          a(Street.river, Position.bb, ActionType.check), a(Street.river, Position.btn, ActionType.bet, 10), a(Street.river, Position.bb, ActionType.raise, 20)]);
    expect(FreakFishSizingDecoder.minRaise(g), (10.0, 20.0));
    final d = post.decide(g);
    expect(d.action, DecisionAction.fold);
    expect(d.justification!.evWhyExplanation, contains('Min-raise en Turn/River'));
  });

  test('4. All-in incompleto: no reabre la subida para quien ya actuó; bote y coste de call exactos', () {
    final fsm = HandFlowFSM()..configure(stake: Stake.nl10, hero: Position.btn);
    fsm.setStack(Position.co, 3.0);
    fsm
      ..addCard(Card.parse('Ah'))
      ..addCard(Card.parse('Kd'))
      ..act(Position.utg, ActionType.raise, amountBb: 2.5)
      ..act(Position.mp, ActionType.fold)
      ..act(Position.co, ActionType.allIn);
    expect(fsm.currentHighBetBB, 3.0);
    expect(fsm.reopensBettingForPriorActors, isFalse);
    expect(fsm.currentActor, Position.btn);
    expect(fsm.canRaise(Position.btn), isTrue, reason: 'BTN no había actuado');
    fsm
      ..act(Position.btn, ActionType.call)
      ..act(Position.sb, ActionType.fold)
      ..act(Position.bb, ActionType.fold);
    expect(fsm.currentActor, Position.utg);
    expect(fsm.canRaise(Position.utg), isFalse);
    expect(fsm.legalActions(), {ActionType.fold, ActionType.call});
    expect(fsm.currentBet - fsm.seats[Position.utg]!.committed, closeTo(0.5, 1e-9));
    expect(() => fsm.act(Position.utg, ActionType.raise, amountBb: 9), throwsA(isA<IllegalAction>()));
    expect(fsm.totalPotBB, closeTo(0.5 + 1 + 2.5 + 3 + 3, 1e-9));
    fsm.act(Position.utg, ActionType.call);
    expect(fsm.phase, HandPhase.flopCards);
    expect(fsm.totalPotBB, closeTo(10.5, 1e-9));
  });
}
