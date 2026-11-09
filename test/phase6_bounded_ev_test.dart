import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/core/discipline/board_history.dart';
import 'package:sol_ver/core/discipline/bluff_catch_auditor.dart';
import 'package:sol_ver/core/discipline/ev_sanity_guard.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/postflop/defense_budget.dart';
import 'package:sol_ver/core/postflop/hand_tier.dart';
import 'package:sol_ver/core/postflop/postflop_heuristic_engine.dart';
import 'package:sol_ver/core/postflop/postflop_ranges.dart';
import 'package:sol_ver/core/postflop/turn_river_solver.dart';
import 'package:sol_ver/core/preflop/full_tree_preflop.dart';
import 'package:sol_ver/core/preflop/range_notation.dart';
import 'package:sol_ver/core/reads/gg_profiler.dart';

const post = PostflopHeuristicEngine();
const tree = FullTreePreflop();
PlayerAction a(Street s, Position p, ActionType t, [double x = 0, TimingTell tt = TimingTell.none]) => PlayerAction(s, p, t, x, tt);
PlayerAction p(Position x, ActionType t, [double amt = 0]) => a(Street.preflop, x, t, amt);
const srp = [PlayerAction(Street.preflop, Position.btn, ActionType.raise, 2.5), PlayerAction(Street.preflop, Position.bb, ActionType.call, 2.5)];
String cs(int id) => '${'23456789TJQKA'[id >> 2]}${'cdhs'[id & 3]}';

final maniac = GgProfiler.classify(const SmartHudInput(vpip: 45, pfr: 35, threeBet: 15, stackBb: 100));
final fish = GgProfiler.classify(const SmartHudInput(vpip: 50, pfr: 5, threeBet: 1, stackBb: 100));
const reg = ReadProfile(GgArchetype.unknownReg, []);

double pct(bool Function(String) f) {
  var c = 0;
  for (var i = 0; i < 169; i++) {
    final (x, y) = Matrix169.concreteCombos(i).first;
    if (f(cs(x) + cs(y))) c += Matrix169.combos(i);
  }
  return c / 1326;
}

void main() {
  group('L1/L10 DefenseBudget', () {
    test('Turn: continuación del rango BB vs barrel 75% dentro de 48-63% (MDF 57%)', () {
      final (_, bbR) = PostflopRanges.forPot(Position.btn, Position.bb, PotType.srp, RakeTier.midRake);
      final b = Card.parseMany('As7d2c5h');
      final dead = b.fold<int>(0, (m, c) => m | c.bit);
      double tot = 0, cont = 0;
      for (var i = 0; i < 169; i++) {
        if (bbR[i] <= 0) continue;
        for (final (x, y) in Matrix169.concreteCombos(i)) {
          if (dead & ((1 << x) | (1 << y)) != 0) continue;
          final g = GameState(stake: Stake.nl100, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 95.7, potBb: 9.1,
              hero: HoleCards.parse(cs(x) + cs(y)), board: b,
              actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8),
                a(Street.flop, Position.bb, ActionType.call, 1.8), a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 6.8)]);
          final range = DefenseBudget.heroRangeAtStreet(g, reg);
          final key = x < y ? x * 52 + y : y * 52 + x;
          if (!range.containsKey(key)) continue;
          tot++;
          if (post.decide(g, read: reg).action != DecisionAction.fold) cont++;
        }
      }
      expect(cont / tot, inInclusiveRange(0.48, 0.63));
    });
    test('Factores: 1.0 reg, 1.15 agro, 0.82 passive/scared <= NL50', () {
      expect(DefenseBudget.factor(reg, Stake.nl10), 1.0);
      expect(DefenseBudget.factor(maniac, Stake.nl100), 1.15);
      expect(DefenseBudget.factor(fish, Stake.nl25), 0.82);
      expect(DefenseBudget.factor(fish, Stake.nl100), 1.0);
    });
    test('MDF multiway compartido: 1 - (1 - MDF)^(1/N)', () {
      expect(DefenseBudget.perPlayerMdf(0.75, 2), 0.75);
      expect(DefenseBudget.perPlayerMdf(0.75, 3), closeTo(0.5, 1e-12));
    });
    test('Bluff_Combo_Audit es exclusivo del River', () {
      final g = GameState(stake: Stake.nl50, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 90, potBb: 9,
          hero: HoleCards.parse('AhKd'), board: Card.parseMany('As7d2c5h'), actions: srp);
      expect(() => BluffCatchAuditor.audit(g, reg, pot: 9, call: 6, heroHasNuts: false), throwsStateError);
    });
  });

  group('L2/L3 auditor por combos', () {
    test('Set 33 vs Maniac (X/C, X/C, donk river) => call/raise', () {
      final g = GameState(stake: Stake.nl100, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 85, potBb: 21.5,
          hero: HoleCards.parse('3h3c'), board: Card.parseMany('Ts7s3d2c9s'),
          actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 2), a(Street.flop, Position.bb, ActionType.call, 2),
            a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 6), a(Street.turn, Position.bb, ActionType.call, 6),
            a(Street.river, Position.bb, ActionType.bet, 10)]);
      expect(post.decide(g, read: maniac).action, isNot(DecisionAction.fold));
    });
    test('straightCompleted solo con OESD/gutshot reales que completan', () {
      expect(BoardHistory(Card.parseMany('Ts9s6dKh2c')).straightCompleted, isFalse);
      expect(BoardHistory(Card.parseMany('Ts9s3d2c8h')).straightCompleted, isTrue);
    });
  });

  group('L4/L5/L11 preflop', () {
    test('BB vs open CO + call BTN: continuación 30-38%', () {
      final c = pct((h) => tree.decide(GameState(stake: Stake.nl100, heroPosition: Position.bb, effectiveStackBb: 100, hero: HoleCards.parse(h),
          actions: [p(Position.co, ActionType.raise, 2.5), p(Position.btn, ActionType.call, 2.5), p(Position.sb, ActionType.fold)])).action != DecisionAction.fold);
      expect(c, inInclusiveRange(0.30, 0.38));
    });
    test('Iso vs 1 limper fish desde BTN: 28-35%', () {
      final c = pct((h) => tree.decide(GameState(stake: Stake.nl10, heroPosition: Position.btn, hero: HoleCards.parse(h),
          actions: [p(Position.mp, ActionType.call, 1)]), read: fish).action == DecisionAction.betRaise);
      expect(c, inInclusiveRange(0.28, 0.35));
    });
  });

  group('Candado A5s', () {
    GameState facing5(String h, {double stack = 100}) => GameState(stake: Stake.nl100, heroPosition: Position.co, effectiveStackBb: stack, hero: HoleCards.parse(h),
        actions: [p(Position.co, ActionType.raise, 2.5), p(Position.btn, ActionType.raise, 8), p(Position.co, ActionType.raise, 20), p(Position.btn, ActionType.allIn, stack)]);
    test('5-bet all-in 100bb: A5s fold, AA call', () {
      expect(FullTreePreflop.classify(facing5('AhAd')).scenario, TreeScenario.facing5Bet);
      expect(tree.decide(facing5('Ah5h')).action, DecisionAction.fold);
      expect(tree.decide(facing5('AhAd')).action, DecisionAction.call);
    });
    test('Stacks cortos (pot odds <= 28%): call', () {
      expect(tree.decide(facing5('Ah5h', stack: 24)).action, DecisionAction.call);
    });
    test('4-bet all-in tras 3-bet: A5s fold', () {
      final g = GameState(stake: Stake.nl100, heroPosition: Position.btn, effectiveStackBb: 100, hero: HoleCards.parse('Ah5h'),
          actions: [p(Position.co, ActionType.raise, 2.5), p(Position.btn, ActionType.raise, 8), p(Position.co, ActionType.allIn, 100)]);
      expect(FullTreePreflop.classify(g).scenario, TreeScenario.facing4Bet);
      expect(tree.decide(g).action, DecisionAction.fold);
    });
    test('Sin 4-bet bluff vs fish / fold-to-4bet < 45%', () {
      GameState g() => GameState(stake: Stake.nl100, heroPosition: Position.co, effectiveStackBb: 100, hero: HoleCards.parse('Ah5h'),
          actions: [p(Position.co, ActionType.raise, 2.5), p(Position.btn, ActionType.raise, 8)]);
      expect(tree.decide(g()).action, DecisionAction.betRaise);
      expect(tree.decide(g(), read: fish).action, isNot(DecisionAction.betRaise));
      final lowF4 = GgProfiler.classify(const SmartHudInput(vpip: 24, pfr: 20, threeBet: 9, foldTo4Bet: 35, stackBb: 100));
      expect(tree.decide(g(), read: lowF4).action, isNot(DecisionAction.betRaise));
    });
    test('Sanity guard preflop: call-off all-in con A5s => fold', () {
      final g = GameState(stake: Stake.nl100, heroPosition: Position.co, effectiveStackBb: 100, hero: HoleCards.parse('Ah5h'), actions: srp);
      const d = DecisionOutput(action: DecisionAction.call, sizing: Sizing(bb: 95, potPct: 100), justificacionGto: '', ajusteExplotativoRead: '');
      final f = EvSanityGuard.preflop(g, d, 'A5s', callBb: 95, potBb: 120);
      expect(f.action, DecisionAction.fold);
      expect(f.ajusteExplotativoRead, contains('[SANITY_GUARD_APPLIED]'));
    });
  });

  group('L6/L7/L8 perfiles y gates', () {
    test('Trapper => trapperPremium; no c-bet con aire', () {
      final t = GgProfiler.classify(const SmartHudInput(vpip: 45, pfr: 4, stackBb: 100), {ActionTag.limpReraisePreflop});
      expect(t.engineProfile, VillainProfile.trapperPremium);
      final g = GameState(stake: Stake.nl10, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 95, potBb: 5.5,
          hero: HoleCards.parse('5h4d'), board: Card.parseMany('Kd8h3s'), actions: srp);
      expect(post.decide(g, read: t).action, DecisionAction.check);
    });
    test('Pot-donk de reg desconocido NL50: QQ defiende', () {
      final g = GameState(stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 95, potBb: 5.5,
          hero: HoleCards.parse('QhQd'), board: Card.parseMany('Ts8c3d'), actions: [...srp, a(Street.flop, Position.bb, ActionType.bet, 5)]);
      expect(DonkTellDecoder.classify(donkBb: 5, potBb: 5.5, read: reg, stake: Stake.nl50), DonkTell.standard);
      expect(post.decide(g, read: reg).action, isNot(DecisionAction.fold));
      expect(DonkTellDecoder.classify(donkBb: 5, potBb: 5.5, read: reg, stake: Stake.nl25), DonkTell.nuttedUnbalancedValue);
    });
    test('Insta-call turn + brick vs fish: sin farol', () {
      final g = GameState(stake: Stake.nl10, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 85, potBb: 17.1,
          hero: HoleCards.parse('AhQd'), board: Card.parseMany('Ts9s6dKh2c'),
          actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8), a(Street.flop, Position.bb, ActionType.call, 1.8),
            a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 4), a(Street.turn, Position.bb, ActionType.call, 4, TimingTell.instaAction),
            a(Street.river, Position.bb, ActionType.check)]);
      expect(post.decide(g, read: fish).action, DecisionAction.check);
    });
  });

  group('L9/L12/L13', () {
    test('bluffShare reportado = ejecutado (combos)', () {
      final scared = GgProfiler.classify(const SmartHudInput(vpip: 20, pfr: 17, threeBet: 4, stackBb: 100));
      final g = GameState(stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 82.5, potBb: 35.5,
          hero: HoleCards.parse('KhKs'), board: Card.parseMany('Kd7s2s4h'),
          actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 15), a(Street.flop, Position.bb, ActionType.call, 15),
            a(Street.turn, Position.bb, ActionType.check)]);
      final pl = const TurnRiverSolver().plan(g, scared, heroHadInitiative: true, pot: 35.5, stack: 82.5);
      expect(pl.bluffShare, closeTo(pl.bluffCombos / (pl.bluffCombos + pl.valueCombos), 1e-12));
      expect(pl.bluffShare, closeTo(pl.targetBluffShare, 0.05));
    });
    test('Nut-Raise Gate: set en board con 4-flush => no raise', () {
      final g = GameState(stake: Stake.nl100, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 80, potBb: 20,
          hero: HoleCards.parse('7c7d'), board: Card.parseMany('7h9h2hKh4s'),
          actions: [...srp, a(Street.river, Position.bb, ActionType.check), a(Street.river, Position.btn, ActionType.bet, 12)]);
      expect(post.decide(g, read: reg).action, isNot(DecisionAction.betRaise));
    });
    test('Bote limpeado soportado', () {
      final g = GameState(stake: Stake.nl10, heroPosition: Position.bb, villainPosition: Position.sb, effectiveStackBb: 99, potBb: 2,
          hero: HoleCards.parse('Kh8d'), board: Card.parseMany('Kd7c2s'), actions: [p(Position.sb, ActionType.call, 1), p(Position.bb, ActionType.check)]);
      expect(g.missingForPostflop(), isEmpty);
      expect(post.decide(g).action, isIn([DecisionAction.betRaise, DecisionAction.check]));
    });
    test('Multiway (3 jugadores): PFA no c-betea aire ni marginal', () {
      final g = GameState(stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 95, potBb: 8,
          hero: HoleCards.parse('5h4d'), board: Card.parseMany('Kd8h3s'), actions: srp, activePlayers: 3);
      expect(post.decide(g).action, DecisionAction.check);
    });
  });

  group('EV_Sanity_Guard', () {
    test('Fold de set en board seguro con pot odds < 35% => call', () {
      final g = GameState(stake: Stake.nl50, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 80, potBb: 20,
          hero: HoleCards.parse('3h3s'), board: Card.parseMany('Kd8s3c2h9d'), actions: srp);
      final h = HandTierClassifier.classify(Card.parse('3h').id, Card.parse('3s').id, [for (final c in g.board) c.id]);
      const d = DecisionOutput(action: DecisionAction.fold, justificacionGto: '', ajusteExplotativoRead: '');
      final f = EvSanityGuard.postflop(g, reg, d, h, toCall: 10, potBeforeBet: 20);
      expect(f.action, DecisionAction.call);
      expect(f.ajusteExplotativoRead, contains('[SANITY_GUARD_APPLIED]'));
    });
    test('Farol river vs station => check', () {
      final g = GameState(stake: Stake.nl10, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 80, potBb: 20,
          hero: HoleCards.parse('QsJs'), board: Card.parseMany('Ks8s3d4c2h'), actions: srp);
      final h = HandTierClassifier.classify(Card.parse('Qs').id, Card.parse('Js').id, [for (final c in g.board) c.id]);
      const d = DecisionOutput(action: DecisionAction.betRaise, sizing: Sizing(bb: 15, potPct: 75), justificacionGto: '', ajusteExplotativoRead: '');
      expect(EvSanityGuard.postflop(g, fish, d, h, toCall: 0, potBeforeBet: 20).action, DecisionAction.check);
    });
  });
}
