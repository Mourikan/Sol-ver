import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/core/models/action_mixer.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/postflop/defense_budget.dart';
import 'package:sol_ver/core/postflop/eqr_table.dart';
import 'package:sol_ver/core/postflop/flop_lookup_table.dart';
import 'package:sol_ver/core/postflop/postflop_heuristic_engine.dart';
import 'package:sol_ver/core/postflop/postflop_ranges.dart';
import 'package:sol_ver/core/postflop/turn_river_solver.dart';
import 'package:sol_ver/core/preflop/full_tree_preflop.dart';
import 'package:sol_ver/core/preflop/preflop_solver_engine.dart';
import 'package:sol_ver/core/preflop/range_notation.dart';
import 'package:sol_ver/core/reads/gg_profiler.dart';

const tree = FullTreePreflop();
const post = PostflopHeuristicEngine();
String cs(int id) => '${'23456789TJQKA'[id >> 2]}${'cdhs'[id & 3]}';
PlayerAction a(Street s, Position p, ActionType t, [double x = 0]) => PlayerAction(s, p, t, x);
PlayerAction pf(Position p, ActionType t, [double x = 0]) => a(Street.preflop, p, t, x);
const srp = [PlayerAction(Street.preflop, Position.btn, ActionType.raise, 2.5), PlayerAction(Street.preflop, Position.bb, ActionType.call, 2.5)];

void expectValidFreq(DecisionOutput d) {
  final f = d.frequencies;
  expect(f, isNotEmpty);
  expect(f.values.fold<double>(0, (x, y) => x + y), closeTo(1, 1e-6));
  expect(f[d.action] ?? (d.action == DecisionAction.check ? f[DecisionAction.fold] : null), isNotNull, reason: '${d.action} no está en $f');
  expect((d.toJson()['freq_gto'] as Map), isNotEmpty);
}

void main() {
  group('freq_gto poblado al 100%', () {
    test('Preflop: 169 manos x nodos (RFI, vs RFI, vs 3-bet, squeeze, iso, cold 4-bet)', () {
      final builders = <GameState Function(String)>[
        (c) => GameState(stake: Stake.nl50, heroPosition: Position.co, hero: HoleCards.parse(c)),
        (c) => GameState(stake: Stake.nl100, heroPosition: Position.bb, effectiveStackBb: 100, hero: HoleCards.parse(c), actions: [pf(Position.btn, ActionType.raise, 2.5)]),
        (c) => GameState(stake: Stake.nl10, heroPosition: Position.btn, effectiveStackBb: 100, hero: HoleCards.parse(c), actions: [pf(Position.co, ActionType.raise, 2.5)]),
        (c) => GameState(stake: Stake.nl100, heroPosition: Position.co, effectiveStackBb: 100, hero: HoleCards.parse(c),
            actions: [pf(Position.co, ActionType.raise, 2.5), pf(Position.btn, ActionType.raise, 8)]),
        (c) => GameState(stake: Stake.nl100, heroPosition: Position.bb, effectiveStackBb: 100, hero: HoleCards.parse(c),
            actions: [pf(Position.co, ActionType.raise, 2.5), pf(Position.btn, ActionType.call, 2.5)]),
        (c) => GameState(stake: Stake.nl25, heroPosition: Position.btn, hero: HoleCards.parse(c), actions: [pf(Position.mp, ActionType.call, 1)]),
        (c) => GameState(stake: Stake.nl100, heroPosition: Position.bb, effectiveStackBb: 100, hero: HoleCards.parse(c),
            actions: [pf(Position.co, ActionType.raise, 2.5), pf(Position.btn, ActionType.raise, 8)]),
      ];
      var mixed = 0;
      for (final b in builders) {
        for (var i = 0; i < 169; i++) {
          final (x, y) = Matrix169.concreteCombos(i).first;
          final d = tree.decide(b(cs(x) + cs(y)));
          expectValidFreq(d);
          if (d.frequencies.length > 1) mixed++;
        }
      }
      expect(mixed, greaterThan(0));
    });

    test('Postflop: flop/turn/river aleatorios', () {
      final rnd = Random(85);
      for (var k = 0; k < 60; k++) {
        final ids = <int>{};
        while (ids.length < 7) {
          ids.add(rnd.nextInt(52));
        }
        final cards = [for (final id in ids) Card(Rank.values[id >> 2], Suit.values[id & 3])];
        final n = 3 + k % 3;
        final st = [Street.flop, Street.turn, Street.river][k % 3];
        final facing = k.isEven;
        final d = post.decide(GameState(stake: Stake.nl50, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 90, potBb: 6,
            hero: HoleCards(cards[0], cards[1]), board: cards.sublist(2, 2 + n),
            actions: [...srp, a(st, Position.bb, ActionType.check), if (facing) a(st, Position.btn, ActionType.bet, 3)]));
        expectValidFreq(d);
      }
    });
  });

  group('Mezclas preflop y mezclador determinista', () {
    DecisionOutput vs(Stake st, Position h, Position o, String c) =>
        tree.decide(GameState(stake: st, heroPosition: h, effectiveStackBb: 100, hero: HoleCards.parse(c), actions: [pf(o, ActionType.raise, 2.5)]));
    test('BTN vs CO A5s: [75,25,0] mid / [75,0,25] micro', () {
      final mid = vs(Stake.nl100, Position.btn, Position.co, 'Ah5h').frequencies;
      expect(mid[DecisionAction.betRaise], closeTo(.75, 1e-6));
      expect(mid[DecisionAction.call], closeTo(.25, 1e-6));
      final micro = vs(Stake.nl10, Position.btn, Position.co, 'Ah5h').frequencies;
      expect(micro[DecisionAction.betRaise], closeTo(.75, 1e-6));
      expect(micro[DecisionAction.fold], closeTo(.25, 1e-6));
    });
    test('CO vs MP 88: [35,65,0] mid / [35,0,65] micro', () {
      final mid = vs(Stake.nl100, Position.co, Position.mp, '8h8d').frequencies;
      expect(mid[DecisionAction.betRaise], closeTo(.35, 1e-6));
      expect(mid[DecisionAction.call], closeTo(.65, 1e-6));
      final micro = vs(Stake.nl10, Position.co, Position.mp, '8h8d').frequencies;
      expect(micro[DecisionAction.betRaise], closeTo(.35, 1e-6));
      expect(micro[DecisionAction.fold], closeTo(.65, 1e-6));
    });
    test('BB vs BTN: fronteras mezcladas (bluffs polares 3-bet/call y calls marginales)', () {
      final mixes = <String>[];
      for (var i = 0; i < 169; i++) {
        final (x, y) = Matrix169.concreteCombos(i).first;
        final d = vs(Stake.nl100, Position.bb, Position.btn, cs(x) + cs(y));
        if (d.frequencies.length > 1) mixes.add(Matrix169.label(i));
      }
      expect(mixes, containsAll(['K9s', 'J9s', 'T8s', '76s']));
      expect(mixes.length, greaterThan(8));
    });
    test('Mezclador: determinista por cartas exactas y fiel a los pesos agregados', () {
      final w = {DecisionAction.betRaise: .35, DecisionAction.call: .65};
      final c1 = Card.parseMany('8h8d');
      expect(DeterministicActionMixer.select(c1, const [], 5.5, w).$1, DeterministicActionMixer.select(c1, const [], 5.5, w).$1);
      var raises = 0, n = 0;
      for (var x = 0; x < 52; x++) {
        for (var y = x + 1; y < 52; y++) {
          n++;
          final c = [Card(Rank.values[x >> 2], Suit.values[x & 3]), Card(Rank.values[y >> 2], Suit.values[y & 3])];
          if (DeterministicActionMixer.select(c, const [], 5.5, w).$1 == DecisionAction.betRaise) raises++;
        }
      }
      expect(raises / n, closeTo(.35, .04));
    });
  });

  group('Stacks efectivos 40-200bb', () {
    test('Set-mining exige implícitas >= 12x', () {
      expect(PreflopSolverEngine.setMiningOk(5.5, 66), isTrue);
      expect(PreflopSolverEngine.setMiningOk(5.5, 60), isFalse);
    });
    test('EQR por profundidad: suited premiado deep, pares/high cards en short', () {
      final sc = Matrix169.indexOf('76s'), kq = Matrix169.indexOf('KQo');
      expect(PreflopSolverEngine.stackEqrMultiplier(sc, 150), greaterThan(PreflopSolverEngine.stackEqrMultiplier(sc, 40)));
      expect(PreflopSolverEngine.stackEqrMultiplier(kq, 40), greaterThan(PreflopSolverEngine.stackEqrMultiplier(kq, 150)));
    });
    test('Commit threshold 3-bet: a 25bb el 3-bet es all-in', () {
      final d = tree.decide(GameState(stake: Stake.nl50, heroPosition: Position.btn, effectiveStackBb: 25, hero: HoleCards.parse('AhKh'),
          actions: [pf(Position.co, ActionType.raise, 2.5)]));
      expect(d.action, DecisionAction.betRaise);
      expect(d.sizing!.bb, 25);
    });
  });

  group('Flop multisizing, trap y check-raise', () {
    test('Rango de check del PFA contiene Nuts_Monster en boards dinámicos', () {
      final (pr, _) = PostflopRanges.forPot(Position.btn, Position.bb, PotType.srp, RakeTier.midRake);
      for (final b in ['Jh9s8d', '9h8h4c', '7s6s5d']) {
        final r = FlopLookupTable.evaluate(Card.parseMany(b), HuNode.srpIp, pfaRange: pr);
        expect(r.trapActive, isTrue, reason: b);
        expect(r.monsterShareOfCheck, greaterThan(0), reason: b);
      }
    });
    test('Check-raise global BB vs c-bet 33% en 10-14%', () {
      final (_, bbR) = PostflopRanges.forPot(Position.btn, Position.bb, PotType.srp, RakeTier.midRake);
      var tot = 0.0, xr = 0.0;
      for (final b in ['As7d2c', 'Kd8h3s', 'Qc7h2d', '9h8h4c', 'Jh9s8d', '7s6s5d', 'Td6c2h', 'Ks8s3d']) {
        final dead = Card.parseMany(b).fold<int>(0, (m, c) => m | c.bit);
        for (var i = 0; i < 169; i++) {
          if (bbR[i] <= 0) continue;
          for (final (x, y) in Matrix169.concreteCombos(i)) {
            if (dead & ((1 << x) | (1 << y)) != 0) continue;
            final d = post.decide(GameState(stake: Stake.nl100, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 97.5, potBb: 5.5,
                hero: HoleCards.parse(cs(x) + cs(y)), board: Card.parseMany(b),
                actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8)]));
            tot++;
            xr += d.frequencies[DecisionAction.betRaise] ?? 0;
          }
        }
      }
      expect(xr / tot, inInclusiveRange(0.10, 0.14));
    });
    test('Rango de llegada fiel: tras X/C flop OOP los monsters pesan menos (parte fue X/R)', () {
      final g = GameState(stake: Stake.nl100, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 95.7, potBb: 9.1,
          hero: HoleCards.parse('2h2s'), board: Card.parseMany('9h8h4c3d'),
          actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8), a(Street.flop, Position.bb, ActionType.call, 1.8)]);
      final range = DefenseBudget.heroRangeAtStreet(g, const ReadProfile(GgArchetype.unknownReg, []));
      final x = Card.parse('4s').id, y = Card.parse('4d').id;
      final set = x < y ? x * 52 + y : y * 52 + x;
      expect(range[set], lessThan(1));
      expect(range[set], greaterThan(0));
    });
  });

  group('EQR calibrado y sizing de River', () {
    test('Anclas EQR: SC IP SPR>6 en 0.95-1.05; offsuit broadway OOP SPR bajo en 0.65-0.72', () {
      expect(EqrTable.factor(Matrix169.indexOf('87s'), ip: true, spr: 8), inInclusiveRange(0.95, 1.05));
      expect(EqrTable.factor(Matrix169.indexOf('KQo'), ip: false, spr: 2.5), inInclusiveRange(0.65, 0.72));
    });
    GameState river(String h) => GameState(stake: Stake.nl100, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 80, potBb: 9.1,
        hero: HoleCards.parse(h), board: Card.parseMany('Ks8s3d4cTh'),
        actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8), a(Street.flop, Position.bb, ActionType.call, 1.8),
          a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.check), a(Street.river, Position.bb, ActionType.check)]);
    test('Top pair vs rango condensado: block/thin value 25-33%; monster mantiene polar', () {
      final tp = post.decide(river('AhKd'));
      expect(tp.action, DecisionAction.betRaise);
      expect(tp.sizing!.potPct, inInclusiveRange(25, 33.5));
      final p = const TurnRiverSolver().plan(river('AhKd'), const ReadProfile(GgArchetype.unknownReg, []), heroHadInitiative: false, pot: 9.1, stack: 80);
      expect(TurnRiverPlanInfo.condensed(p), isTrue);
      final set = post.decide(river('8h8d'));
      expect(set.action, DecisionAction.betRaise);
      expect(set.sizing!.potPct, greaterThanOrEqualTo(75));
    });
  });
}

class TurnRiverPlanInfo {
  static bool condensed(LateStreetPlan p) => LateStreetPlan.condensed.contains(p.villainState);
}
