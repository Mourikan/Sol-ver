import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/core/evaluators/action_ev_calculator.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/postflop/four_bet_pot_solver.dart';
import 'package:sol_ver/core/postflop/hand_tier.dart';
import 'package:sol_ver/core/postflop/postflop_heuristic_engine.dart';
import 'package:sol_ver/core/postflop/postflop_ranges.dart';
import 'package:sol_ver/core/postflop/range_equity.dart';
import 'package:sol_ver/core/preflop/full_tree_preflop.dart';
import 'package:sol_ver/core/preflop/preflop_ranges_db.dart';
import 'package:sol_ver/core/preflop/range_notation.dart';
import 'package:sol_ver/core/preflop/structure_modifier.dart';
import 'package:sol_ver/core/reads/multiway_threat_aggregator.dart';

const post = PostflopHeuristicEngine();
const tree = FullTreePreflop();
PlayerAction a(Street s, Position p, ActionType t, [double x = 0]) => PlayerAction(s, p, t, x);
PlayerAction pf(Position p, ActionType t, [double x = 0]) => a(Street.preflop, p, t, x);
const srp = [PlayerAction(Street.preflop, Position.btn, ActionType.raise, 2.5), PlayerAction(Street.preflop, Position.bb, ActionType.call, 2.5)];
const fourBet = [
  PlayerAction(Street.preflop, Position.co, ActionType.raise, 2.5),
  PlayerAction(Street.preflop, Position.btn, ActionType.raise, 8),
  PlayerAction(Street.preflop, Position.co, ActionType.raise, 22),
  PlayerAction(Street.preflop, Position.btn, ActionType.call, 22),
];

void main() {
  group('4BP propio (SPR 1-2.5)', () {
    test('Rangos de llegada 4BP propios (no 3BP)', () {
      final (pfa, call) = PostflopRanges.forPot(Position.co, Position.btn, PotType.fourBetPlus, RakeTier.midRake);
      expect(pfa[Matrix169.indexOf('AA')], 1);
      expect(pfa[Matrix169.indexOf('A5s')], 1);
      expect(pfa[Matrix169.indexOf('99')], 0);
      expect(call[Matrix169.indexOf('JJ')], 1);
    });
    GameState g(String h, String b, {List<PlayerAction> street = const []}) => GameState(stake: Stake.nl100, heroPosition: Position.co,
        villainPosition: Position.btn, effectiveStackBb: 78, potBb: 45, hero: HoleCards.parse(h), board: Card.parseMany(b), actions: [...fourBet, ...street]);
    test('C-bet pequeño 20-25% en board seco/alto', () {
      final d = post.decide(g('KhKd', 'Qs7d2c'));
      expect(d.action, DecisionAction.betRaise);
      expect(d.sizing!.potPct, inInclusiveRange(20, 25));
    });
    test('Commit / call-off con overpair JJ+ y TPTK vs apuesta', () {
      for (final h in ['JhJd', 'AhKd']) {
        final d = post.decide(GameState(stake: Stake.nl100, heroPosition: Position.btn, villainPosition: Position.co, effectiveStackBb: 78, potBb: 45,
            hero: HoleCards.parse(h), board: Card.parseMany(h == 'AhKd' ? 'Ks7d2c' : 'Ts7d2c'), actions: [...fourBet, a(Street.flop, Position.co, ActionType.bet, 10)]));
        expect(d.action, isNot(DecisionAction.fold), reason: h);
      }
      final tt = HoleCards.parse('TcTd');
      final tb = Card.parseMany('Qs7d2c');
      expect(FourBetPotSolver.commitHand(tt, tb, HandTierClassifier.classify(tt.high.id, tt.low.id, [for (final c in tb) c.id])), isFalse);
    });
  });

  group('Multiway con villanos separados', () {
    test('Bluff_Gate: un station activo bloquea faroles puros (0%)', () {
      const vs = [VillainSeatState(Position.bb), VillainSeatState(Position.co, profile: VillainProfile.callingStation)];
      final g = GameState(stake: Stake.nl25, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 90, potBb: 20,
          hero: HoleCards.parse('AsJs'), board: Card.parseMany('Ks8s3d4c2h'), activePlayers: 3, activeVillains: vs,
          actions: [...srp, a(Street.river, Position.bb, ActionType.check), a(Street.river, Position.co, ActionType.check)]);
      expect(MultiwayThreatAggregator.assess(g).bluffFactor, 0);
      expect(post.decide(g).action, isNot(DecisionAction.betRaise));
    });
    test('Factor = min x 0.5^(N-1) con regs', () {
      final g = GameState(stake: Stake.nl25, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 90, potBb: 20,
          hero: HoleCards.parse('AsJs'), board: Card.parseMany('Ks8s3d4c2h'), activePlayers: 4,
          activeVillains: const [VillainSeatState(Position.bb), VillainSeatState(Position.co), VillainSeatState(Position.sb)], actions: srp);
      expect(MultiwayThreatAggregator.assess(g).bluffFactor, closeTo(0.25, 1e-12));
    });
    test('Retrocompatible: sin activeVillains el modo HU no cambia', () {
      final g = GameState(stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 97.5, potBb: 5.5,
          hero: HoleCards.parse('AhKd'), board: Card.parseMany('As7d2c'), actions: [...srp, a(Street.flop, Position.bb, ActionType.check)]);
      expect(post.decide(g).action, DecisionAction.betRaise);
    });
  });

  group('Ante / straddle / deep stacks', () {
    test('Dinero muerto entra en el bote y expande RFI de BTN +4-7%', () {
      final g = GameState(stake: Stake.nl50, heroPosition: Position.btn, effectiveStackBb: 100, anteBb: 0.12, hero: HoleCards.parse('Ah5h'));
      expect(g.extraDeadMoneyBb, closeTo(0.72, 1e-9));
      final exp = StructureModifier.rfiExpansion(g, Position.btn);
      expect(exp, inInclusiveRange(0.04, 0.07));
      final base = PreflopRangesDb.rfi(Position.btn, RakeTier.midRake).percent(PreflopAction.raise);
      expect(Matrix169.percent(StructureModifier.expandedRfi(Position.btn, RakeTier.midRake, exp)) - base, inInclusiveRange(4, 8));
      expect(StructureModifier.rfiExpansion(g, Position.utg), 0);
    });
    test('Straddle: open x2', () {
      final d = tree.decide(GameState(stake: Stake.nl50, heroPosition: Position.btn, effectiveStackBb: 100, hasStraddle: true, hero: HoleCards.parse('AhKh')));
      expect(d.sizing!.bb, closeTo(5.0, 1e-9));
    });
    test('> 200bb: stack-off preflop solo AA/KK (QQ foldea 5-bet all-in), salvo Maniac', () {
      GameState g(String h, VillainProfile vp) => GameState(stake: Stake.nl100, heroPosition: Position.co, effectiveStackBb: 300, hero: HoleCards.parse(h), villainProfile: vp,
          actions: [pf(Position.co, ActionType.raise, 2.5), pf(Position.btn, ActionType.raise, 8), pf(Position.co, ActionType.raise, 20), pf(Position.btn, ActionType.allIn, 300)]);
      expect(tree.decide(g('QhQd', VillainProfile.gtoBase)).action, DecisionAction.fold);
      expect(tree.decide(g('KhKd', VillainProfile.gtoBase)).action, DecisionAction.call);
      expect(tree.decide(g('QhQd', VillainProfile.maniac)).action, DecisionAction.call);
      expect(StructureModifier.ultraDeepEqr(Matrix169.indexOf('A5s'), 300), greaterThan(StructureModifier.ultraDeepEqr(Matrix169.indexOf('AKo'), 300)));
    });
  });

  group('Rake por tamaño de bote y EV 2 calles', () {
    test('Rake efectivo monotónico NL2 -> NL200', () {
      final rates = [for (final st in Stake.values) RakeConfig.byStake[st]!.effectiveRate(PotType.srp)];
      for (var i = 1; i < rates.length; i++) {
        expect(rates[i], lessThanOrEqualTo(rates[i - 1]));
      }
      expect(rates.first, greaterThan(rates.last));
    });
    test('Future_Bluff_Capture_EV > 0 vs reg en flop/turn y 0 vs fish o en river', () {
      final g = GameState(stake: Stake.nl50, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 97.5, potBb: 5.5,
          hero: HoleCards.parse('8h7h'), board: Card.parseMany('Ks8d3c'),
          actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8)]);
      final vc = RangeEquity.villainCombos(g);
      expect(ActionEvCalculator.futureBluffCapture(g, vc, 0.5, potAfterCall: 9.1), greaterThan(0));
      final fishG = g.copyWith(villainProfile: VillainProfile.callingStation);
      expect(ActionEvCalculator.futureBluffCapture(fishG, vc, 0.5, potAfterCall: 9.1), 0);
    });
  });
}

