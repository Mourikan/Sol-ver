import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/core/postflop/geometric_2e_planner.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/postflop/postflop_heuristic_engine.dart';
import 'package:sol_ver/core/postflop/turn_river_solver.dart';
import 'package:sol_ver/core/preflop/full_tree_preflop.dart';
import 'package:sol_ver/core/reads/gg_profiler.dart';
import 'package:sol_ver/core/reads/range_funnel.dart';

const tree = FullTreePreflop();
const post = PostflopHeuristicEngine();
const solver = TurnRiverSolver();

PlayerAction a(Street s, Position p, ActionType t, [double amt = 0]) => PlayerAction(s, p, t, amt);
PlayerAction pf(Position p, ActionType t, [double amt = 0]) => a(Street.preflop, p, t, amt);

final fish = GgProfiler.classify(const SmartHudInput(vpip: 50, pfr: 5, threeBet: 1, stackBb: 100));
final scared = GgProfiler.classify(const SmartHudInput(vpip: 20, pfr: 17, threeBet: 4, stackBb: 100));

const srp = [
  PlayerAction(Street.preflop, Position.btn, ActionType.raise, 2.5),
  PlayerAction(Street.preflop, Position.bb, ActionType.call, 2.5),
];

void main() {
  group('Perfilador GGPoker', () {
    test('Arquetipos por SmartHUD + tags', () {
      expect(fish.archetype, GgArchetype.recPassiveFish);
      expect(scared.archetype, GgArchetype.scaredMoneyReg);
      expect(GgProfiler.classify(const SmartHudInput(vpip: 40, pfr: 30, threeBet: 14, stackBb: 100)).archetype, GgArchetype.agroSpewy);
      expect(GgProfiler.classify(const SmartHudInput(vpip: 25, pfr: 20, threeBet: 8, stackBb: 70, autoRebuy: false)).archetype,
          GgArchetype.recPassiveFish);
      expect(GgProfiler.classify(const SmartHudInput(vpip: 24, pfr: 20, threeBet: 8, stackBb: 100), {ActionTag.openLimp}).archetype,
          GgArchetype.recPassiveFish);
      expect(GgProfiler.classify(const SmartHudInput(vpip: 45, pfr: 4, stackBb: 100), {ActionTag.limpReraisePreflop}).archetype,
          GgArchetype.trapperLimpReraiser);
      expect(GgProfiler.classify(const SmartHudInput(vpip: 24, pfr: 20, threeBet: 8, stackBb: 100)).archetype, GgArchetype.unknownReg);
    });
    test('Donk tells', () {
      expect(DonkTellDecoder.classify(donkBb: 1, potBb: 10, read: fish, stake: Stake.nl10), DonkTell.blockingBetWeakOrDraw);
      expect(DonkTellDecoder.classify(donkBb: 8, potBb: 10, read: fish, stake: Stake.nl25), DonkTell.nuttedUnbalancedValue);
      expect(DonkTellDecoder.classify(donkBb: 5, potBb: 10, read: fish, stake: Stake.nl25), DonkTell.standard);
    });
  });

  group('AUDIT 1: Limp-reraise VPIP 45 / PFR 4', () {
    final trapper = GgProfiler.classify(const SmartHudInput(vpip: 45, pfr: 4, stackBb: 100), {ActionTag.limpReraisePreflop});
    GameState g(String c, {double stack = 100}) => GameState(
        stake: Stake.nl10, heroPosition: Position.co, effectiveStackBb: stack, hero: HoleCards.parse(c),
        actions: [pf(Position.utg, ActionType.call, 1), pf(Position.co, ActionType.raise, 5.5), pf(Position.utg, ActionType.raise, 25)]);
    test('Alerta 85%+ AA/KK y fold con AQo / KJs', () {
      expect(FullTreePreflop.isLimpReraise(g('AhQd')), isTrue);
      for (final c in ['AhQd', 'KhJh']) {
        final d = tree.decide(g(c), read: trapper);
        expect(d.action, DecisionAction.fold, reason: c);
        expect(d.ajusteExplotativoRead, contains('Rango 85%+ AA/KK'));
      }
    });
    test('AA jam; set-mining solo si call < 10% stack', () {
      expect(tree.decide(g('AhAd'), read: trapper).action, DecisionAction.betRaise);
      expect(tree.decide(g('5h5d'), read: trapper).action, DecisionAction.fold);
      expect(tree.decide(g('5h5d', stack: 250), read: trapper).action, DecisionAction.call);
      expect(tree.decide(g('JhJd'), read: trapper).action, DecisionAction.fold);
    });
  });

  group('AUDIT 2: Min-donk 1bb en 10bb, Ts 8s 3d, recreativo', () {
    GameState g(String c, double donk, {Stake st = Stake.nl10}) => GameState(
        stake: st, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 95, potBb: 10,
        hero: HoleCards.parse(c), board: Card.parseMany('Ts8s3d'), actions: [...srp, a(Street.flop, Position.bb, ActionType.bet, donk)]);
    test('ATs top pair: raise a 4.5-5bb', () {
      final d = post.decide(g('AhTh', 1), read: fish);
      expect(d.action, DecisionAction.betRaise);
      expect(d.sizing!.bb, inInclusiveRange(4.5, 5.0));
      expect(d.justificacionGto, contains('Blocking_Bet_Weak_Or_Draw'));
    });
    test('Combo draw (9s7s): raise semi-bluff 4.5-5bb', () {
      final d = post.decide(g('9s7s', 1), read: fish);
      expect(d.action, DecisionAction.betRaise);
      expect(d.sizing!.bb, inInclusiveRange(4.5, 5.0));
    });
    test('Pot-donk en NL25: over-fold de overpair sin redraw', () {
      expect(post.decide(g('QhQd', 9, st: Stake.nl25), read: fish).action, DecisionAction.fold);
      expect(post.decide(g('8h8c', 9, st: Stake.nl25), read: fish).action, isNot(DecisionAction.fold));
    });
  });

  group('AUDIT 3: Scared_Money capado (X/C flop, X turn) en bote grande', () {
    final flopLine = [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 15),
      a(Street.flop, Position.bb, ActionType.call, 15)];
    GameState turn(String c) => GameState(stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.bb,
        effectiveStackBb: 82.5, potBb: 35.5, hero: HoleCards.parse(c), board: Card.parseMany('Kd7s2s4h'),
        actions: [...flopLine, a(Street.turn, Position.bb, ActionType.check)]);
    GameState river(String c) => GameState(stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.bb,
        effectiveStackBb: 54.1, potBb: 92.3, hero: HoleCards.parse(c), board: Card.parseMany('Kd7s2s4h9s'),
        actions: [...flopLine, a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 28.4),
          a(Street.turn, Position.bb, ActionType.call, 28.4), a(Street.river, Position.bb, ActionType.check)]);

    test('Embudo: rango cappedMedium (sin KK/77/22, sin aire)', () {
      final f = RangeFunnel.track(turn('KhKs'));
      expect(f.state, VillainRangeState.cappedMedium);
      expect(f.removed, containsAll(['KK', '77', '22']));
    });
    test('Turn: línea de valor (set) + farol con blocker As, overbet geométrico 75-85%, factor 2.0', () {
      final p = solver.plan(turn('KhKs'), scared, heroHadInitiative: true, pot: 35.5, stack: 82.5);
      expect(p.exploitFactor, 2.0);
      // Fase 9.5: SPR 2.3 en ventana Geo-2E => sizing geométrico de 2 calles (sustituye el 75-85%).
      expect(p.sizePct, closeTo(Geometric2EPlanner.plan(35.5, 82.5)!.$1, 1e-9));
      // Turn: presupuesto geométrico de 2 calles x factor 2.0 (acotado a 100%: se usan todos los candidatos disponibles).
      expect(p.targetBluffShare, closeTo(min(1.0, TurnRiverSolver.twoStreetTurnShare(p.sizePct) * 2), 1e-12));
      expect(p.bluffShare, lessThanOrEqualTo(p.targetBluffShare + 0.05));
      expect(p.bluffShare, greaterThan(TurnRiverSolver.bluffShareGto(p.sizePct)));
      final v = post.decide(turn('KhKs'), read: scared);
      final b = post.decide(turn('AsQd'), read: scared);
      expect(v.action, DecisionAction.betRaise);
      expect(b.action, DecisionAction.betRaise);
      expect(b.sizing!.potPct, closeTo(Geometric2EPlanner.plan(35.5, 82.5)!.$1, 0.01));
      expect(v.sizing!.bb, closeTo(b.sizing!.bb, 1e-9));
    });
    test('River: valor + farol con key blocker (As al color) all-in/presión máxima', () {
      final v = post.decide(river('KhKc'), read: scared);
      final b = post.decide(river('AsQd'), read: scared);
      expect(v.action, DecisionAction.betRaise);
      expect(b.action, DecisionAction.betRaise);
      expect(b.ajusteExplotativoRead, contains('Key blocker As'));
      expect(b.sizing!.bb, closeTo(54.1, 1e-9));
      final p = solver.plan(river('AsQd'), scared, heroHadInitiative: true, pot: 92.3, stack: 54.1);
      expect(p.node, LateNode.tripleBarrel);
      expect(p.allIn, isTrue);
    });
    test('Mismo spot vs reg desconocido: factor 1.0', () {
      final p = solver.plan(turn('KhKs'), GgProfiler.classify(const SmartHudInput(stackBb: 100)), heroHadInitiative: true, pot: 35.5, stack: 82.5);
      expect(p.exploitFactor, 1.0);
    });
  });

  group('AUDIT 4: River vs CallingStation', () {
    GameState g(String c) => GameState(stake: Stake.nl10, heroPosition: Position.btn, villainPosition: Position.bb,
        effectiveStackBb: 90, potBb: 9.1, hero: HoleCards.parse(c), board: Card.parseMany('Ks8s3d4c2h'),
        actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8),
          a(Street.flop, Position.bb, ActionType.call, 1.8), a(Street.turn, Position.bb, ActionType.check),
          a(Street.turn, Position.btn, ActionType.check), a(Street.river, Position.bb, ActionType.check)]);
    test('Proyecto de color fallido: 0% farol (check)', () {
      final d = post.decide(g('QsJs'), read: fish);
      expect(d.action, DecisionAction.check);
      expect(solver.plan(g('QsJs'), fish, heroHadInitiative: false, pot: 9.1, stack: 90).bluffShare, 0);
    });
    test('Top pair mal kicker: Block-Thin-Value 25-33% (T3, Fase 9.2); buen kicker: value bet', () {
      final d = post.decide(g('Kh5h'), read: fish);
      expect(d.action, DecisionAction.betRaise);
      expect(d.sizing!.potPct, inInclusiveRange(25, 33));
      expect(post.decide(g('AhKd'), read: fish).action, DecisionAction.betRaise);
    });
    test('2do par: thin value vs fish', () {
      expect(post.decide(g('8h7h'), read: fish).action, DecisionAction.betRaise);
    });
  });

  group('Geometría de faroles y embudo', () {
    test('Bluff_Share = B/(P+2B): 33% -> 20%, 75% -> 30%, 125% -> 35.7%', () {
      expect(TurnRiverSolver.bluffShareGto(33), closeTo(0.33 / 1.66, 1e-12));
      expect(TurnRiverSolver.bluffShareGto(33), closeTo(0.20, 0.002));
      expect(TurnRiverSolver.bluffShareGto(75), closeTo(0.30, 1e-12));
      expect(TurnRiverSolver.bluffShareGto(125), closeTo(1.25 / 3.5, 1e-12));
    });
    test('Ejemplo 1: X/C en K-7-2r => Capped_Medium', () {
      final s = GameState(stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 95,
          potBb: 9.1, hero: HoleCards.parse('AhQh'), board: Card.parseMany('Kd7c2s5h'),
          actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8),
            a(Street.flop, Position.bb, ActionType.call, 1.8)]);
      final f = RangeFunnel.track(s);
      expect(f.state, VillainRangeState.cappedMedium);
      expect(f.removed, containsAll(['KK', '77', 'aire total']));
    });
    test('Ejemplo 2: PFA check behind en Q-J-8 two-tone => Capped_Medium_Showdown y probe/overbet OOP en turn blank', () {
      final s = GameState(stake: Stake.nl50, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 97.5,
          potBb: 5.5, hero: HoleCards.parse('Td9d'), board: Card.parseMany('QhJh8d2c'),
          actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.check)]);
      expect(RangeFunnel.track(s).state, VillainRangeState.cappedMediumShowdown);
      final p = solver.plan(s, GgProfiler.classify(const SmartHudInput(stackBb: 100)), heroHadInitiative: false, pot: 5.5, stack: 97.5);
      expect(p.node, LateNode.probeBet);
      expect(p.sizePct, inInclusiveRange(75, 85));
      expect(post.decide(s).action, DecisionAction.betRaise);
    });
    test('Rank shift: K en turn tras c-bet en board bajo => barrel alta frecuencia 33% incluso sin equidad', () {
      final s = GameState(stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 95,
          potBb: 9.1, hero: HoleCards.parse('QhJd'), board: Card.parseMany('7d5c2sKh'),
          actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8),
            a(Street.flop, Position.bb, ActionType.call, 1.8), a(Street.turn, Position.bb, ActionType.check)]);
      final p = solver.plan(s, GgProfiler.classify(const SmartHudInput(stackBb: 100)), heroHadInitiative: true, pot: 9.1, stack: 95);
      expect(p.shift, CardShift.rankShift);
      expect(p.sizePct, 33);
      expect(post.decide(s).action, DecisionAction.betRaise);
    });
    test('Agro: no farolea y check-call con par medio (inducir)', () {
      final agro = GgProfiler.classify(const SmartHudInput(vpip: 40, pfr: 30, threeBet: 14, stackBb: 100));
      final s = GameState(stake: Stake.nl50, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 90,
          potBb: 9.1, hero: HoleCards.parse('8h7h'), board: Card.parseMany('Ks8d3c4c2h'),
          actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8),
            a(Street.flop, Position.bb, ActionType.call, 1.8), a(Street.turn, Position.bb, ActionType.check),
            a(Street.turn, Position.btn, ActionType.check), a(Street.river, Position.bb, ActionType.check),
            a(Street.river, Position.btn, ActionType.bet, 9)]);
      expect(post.decide(s, read: agro).action, DecisionAction.call);
    });
  });
}
