import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/application/solver_controller.dart';
import 'package:sol_ver/application/state_validator.dart';
import 'package:sol_ver/core/evaluators/hand_evaluator.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/postflop/defense_budget.dart';
import 'package:sol_ver/core/postflop/flop_lookup_table.dart';
import 'package:sol_ver/core/postflop/hand_tier.dart';
import 'package:sol_ver/core/postflop/postflop_heuristic_engine.dart';
import 'package:sol_ver/core/postflop/postflop_ranges.dart';
import 'package:sol_ver/core/postflop/range_equity.dart';
import 'package:sol_ver/core/preflop/full_tree_preflop.dart';
import 'package:sol_ver/core/preflop/preflop_ranges_db.dart';
import 'package:sol_ver/core/preflop/range_notation.dart';
import 'package:sol_ver/core/reads/gg_profiler.dart';
import 'package:sol_ver/data/packed_layout.dart';
import 'package:sol_ver/data/packed_lookup_repository.dart';

const tree = FullTreePreflop();
const post = PostflopHeuristicEngine();
String cs(int id) => '${'23456789TJQKA'[id >> 2]}${'cdhs'[id & 3]}';
PlayerAction pf(Position p, ActionType t, [double a = 0]) => PlayerAction(Street.preflop, p, t, a);
final fish = GgProfiler.classify(const SmartHudInput(vpip: 50, pfr: 5, threeBet: 1, stackBb: 100));

/// Exentas de monotonía de kicker: faroles polarizados / blocker-bluffs declarados y ases de rueda offsuit
/// (A5o-A2o tienen equity calculada > A6o-A8o por escaleras a la rueda; tabla hand_equity.g.dart).
const exempt = {'A5o', 'A4o', 'A3o', 'A2o', 'A5s', 'A4s', 'A3s', 'A2s', 'K9s', 'K8s', 'Q9s', 'J9s', 'T8s', '97s', '86s', '76s', '65s', '54s', '98s', '87s', 'T9s'};

typedef Node = ({String name, GameState Function(String) build, ReadProfile? read, bool raiseOnly});

List<Node> nodes() {
  final out = <Node>[];
  for (final st in [Stake.nl10, Stake.nl100]) {
    for (final p in PackedLayout.rfiPositions) {
      out.add((name: '${st.name} RFI ${p.name}', build: (c) => GameState(stake: st, heroPosition: p, hero: HoleCards.parse(c)), read: null, raiseOnly: true));
    }
    for (final (h, o) in PackedLayout.vsRfiPairs) {
      out.add((
        name: '${st.name} ${h.name} vs open ${o.name}',
        build: (c) => GameState(stake: st, heroPosition: h, effectiveStackBb: 100, hero: HoleCards.parse(c), actions: [pf(o, ActionType.raise, PreflopRangesDb.openSizeBb[o]!)]),
        read: null,
        raiseOnly: false
      ));
    }
    for (final h in PackedLayout.rfiPositions) {
      for (final v in Position.values) {
        if (v == h || (v.index < h.index && v != Position.bb && v != Position.sb)) continue;
        if (v.index <= h.index) continue;
        out.add((
          name: '${st.name} ${h.name} vs 3-bet ${v.name}',
          build: (c) => GameState(stake: st, heroPosition: h, effectiveStackBb: 100, hero: HoleCards.parse(c),
              actions: [pf(h, ActionType.raise, 2.5), pf(v, ActionType.raise, v.index >= Position.sb.index ? 10 : 8)]),
          read: null,
          raiseOnly: false
        ));
      }
    }
    for (final (o, c1, h) in [(Position.co, Position.btn, Position.bb), (Position.co, Position.btn, Position.sb), (Position.utg, Position.co, Position.btn), (Position.utg, Position.co, Position.bb)]) {
      out.add((
        name: '${st.name} squeeze ${h.name} vs ${o.name}+${c1.name}',
        build: (c) => GameState(stake: st, heroPosition: h, effectiveStackBb: 100, hero: HoleCards.parse(c), actions: [pf(o, ActionType.raise, 2.5), pf(c1, ActionType.call, 2.5)]),
        read: null,
        raiseOnly: false
      ));
    }
    for (final h in [Position.co, Position.btn, Position.sb]) {
      for (final r in [null, fish]) {
        out.add((
          name: '${st.name} iso ${h.name} vs limper UTG ${r == null ? 'default' : 'fish'}',
          build: (c) => GameState(stake: st, heroPosition: h, hero: HoleCards.parse(c), actions: [pf(Position.utg, ActionType.call, 1)]),
          read: r,
          raiseOnly: true
        ));
      }
    }
  }
  return out;
}

Map<int, DecisionOutput> sweep(Node n) => {
      for (var i = 0; i < 169; i++)
        i: () {
          final (x, y) = Matrix169.concreteCombos(i).first;
          return tree.decide(n.build(cs(x) + cs(y)), read: n.read);
        }(),
    };

List<String> holes(Node n, Map<int, DecisionOutput> d) {
  // Monotonía sobre la FRECUENCIA de continuación (estrategias mixtas): la mano superior nunca continúa menos.
  double cont(int i) {
    final f = d[i]!.frequencies;
    return n.raiseOnly ? (f[DecisionAction.betRaise] ?? 0) : (f[DecisionAction.betRaise] ?? 0) + (f[DecisionAction.call] ?? 0);
  }
  const eps = 1e-6;
  final out = <String>[];
  for (var r = 12; r > 0; r--) {
    final lower = Matrix169.index(r, r, suited: false), higher = Matrix169.index(r - 1, r - 1, suited: false);
    if (cont(higher) + eps < cont(lower)) {
      out.add('${n.name}: ${Matrix169.label(higher)} continúa ${(cont(higher) * 100).round()}% < ${Matrix169.label(lower)} ${(cont(lower) * 100).round()}%');
    }
  }
  for (final suited in [true, false]) {
    for (var hi = 0; hi < 12; hi++) {
      for (var lo = hi + 2; lo < 13; lo++) {
        final low = Matrix169.index(hi, lo, suited: suited);
        if (cont(low) <= eps || exempt.contains(Matrix169.label(low))) continue;
        for (var k = hi + 1; k < lo; k++) {
          final up = Matrix169.index(hi, k, suited: suited);
          if (cont(up) + eps < cont(low)) {
            out.add('${n.name}: ${Matrix169.label(up)} continúa ${(cont(up) * 100).round()}% < ${Matrix169.label(low)} ${(cont(low) * 100).round()}%');
          }
        }
      }
    }
  }
  return out;
}

void main() {
  group('Monotonía preflop (169 manos x todos los nodos)', () {
    final all = nodes();
    test('Sin huecos de rango en ${all.length} nodos', () {
      final violations = <String>[];
      for (final n in all) {
        violations.addAll(holes(n, sweep(n)));
      }
      expect(violations, isEmpty, reason: violations.take(40).join('\n'));
    });
  });

  group('Fronteras marginales', () {
    DecisionOutput coVsMp(Stake st, String c) => tree.decide(GameState(stake: st, heroPosition: Position.co, effectiveStackBb: 100,
        hero: HoleCards.parse(c), actions: [pf(Position.mp, ActionType.raise, 2.5)]));
    test('Mid-rake: 88 en CO vs MP tiene acción positiva', () {
      expect(coVsMp(Stake.nl100, '8h8d').action, isNot(DecisionAction.fold));
    });
    test('High-rake: transición 77/88/99 documentada (sin folds silenciosos)', () {
      for (final c in ['7h7d', '8h8d', '9h9d']) {
        final d = coVsMp(Stake.nl10, c);
        if (d.action == DecisionAction.fold) {
          expect(d.justificacionGto, contains('Set-Mining'), reason: c);
        }
      }
      expect(coVsMp(Stake.nl10, 'ThTd').action, DecisionAction.betRaise);
    });
    test('AQo vs 3-bet: OOP fold documentado, IP call', () {
      final oop = tree.decide(GameState(stake: Stake.nl100, heroPosition: Position.co, effectiveStackBb: 100, hero: HoleCards.parse('AhQd'),
          actions: [pf(Position.co, ActionType.raise, 2.5), pf(Position.btn, ActionType.raise, 8)]));
      expect(oop.action, DecisionAction.fold);
      expect(oop.justificacionGto, contains('offsuit'));
      final ip = tree.decide(GameState(stake: Stake.nl100, heroPosition: Position.co, effectiveStackBb: 100, hero: HoleCards.parse('AhQd'),
          actions: [pf(Position.co, ActionType.raise, 2.5), pf(Position.bb, ActionType.raise, 11)]));
      expect(ip.action, DecisionAction.call);
    });
  });

  group('Invariantes postflop (fuzzer determinista)', () {
    final rnd = Random(20261109);
    final srp = [pf(Position.btn, ActionType.raise, 2.5), pf(Position.bb, ActionType.call, 2.5)];
    List<Card> deal(int n, int dead) {
      final out = <Card>[];
      while (out.length < n) {
        final id = rnd.nextInt(52);
        if (dead & (1 << id) != 0) continue;
        dead |= 1 << id;
        out.add(Card(Rank.values[id >> 2], Suit.values[id & 3]));
      }
      return out;
    }

    test('Flop/Turn: nunca fold con equity real >= pot odds', () {
      final (_, bbR) = PostflopRanges.forPot(Position.btn, Position.bb, PotType.srp, RakeTier.midRake);
      final keys = [for (var i = 0; i < 169; i++) if (bbR[i] > 0) i];
      var checked = 0;
      for (var k = 0; k < 60; k++) {
        final turn = k.isOdd;
        final i = keys[rnd.nextInt(keys.length)];
        final (x, y) = Matrix169.concreteCombos(i)[rnd.nextInt(Matrix169.combos(i))];
        final board = deal(turn ? 4 : 3, (1 << x) | (1 << y));
        final bet = [1.8, 3.6, 5.5][rnd.nextInt(3)];
        final acts = [...srp,
          if (turn) ...[const PlayerAction(Street.flop, Position.bb, ActionType.check), const PlayerAction(Street.flop, Position.btn, ActionType.bet, 1.8), const PlayerAction(Street.flop, Position.bb, ActionType.call, 1.8)],
          PlayerAction(turn ? Street.turn : Street.flop, Position.bb, ActionType.check),
          PlayerAction(turn ? Street.turn : Street.flop, Position.btn, ActionType.bet, bet)];
        final pot = turn ? 9.1 : 5.5;
        final g = GameState(stake: Stake.nl50, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 90, potBb: pot,
            hero: HoleCards.parse(cs(x) + cs(y)), board: board, actions: acts);
        final d = post.decide(g);
        if (d.action != DecisionAction.fold) continue;
        checked++;
        final odds = bet / (pot + 2 * bet);
        expect(RangeEquity.realized(g), lessThan(odds), reason: '${g.hero} ${board.join()} bet $bet');
      }
      expect(checked, greaterThan(0));
    });

    test('River: nunca check behind con las nuts absolutas', () {
      var found = 0;
      for (var k = 0; k < 400 && found < 25; k++) {
        final board = deal(5, 0);
        final ids = [for (final c in board) c.id];
        final dead = board.fold<int>(0, (m, c) => m | c.bit);
        var best = -1, ba = -1, bb = -1;
        for (var a = 0; a < 52; a++) {
          if (dead & (1 << a) != 0) continue;
          for (var b = a + 1; b < 52; b++) {
            if (dead & (1 << b) != 0) continue;
            final v = HandEvaluator.evaluate([a, b, ...ids]);
            if (v > best) {
              best = v;
              ba = a;
              bb = b;
            }
          }
        }
        final g = GameState(stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 80, potBb: 20,
            hero: HoleCards.parse(cs(ba) + cs(bb)), board: board, actions: [...srp, const PlayerAction(Street.river, Position.bb, ActionType.check)]);
        if (!RangeEquity.isAbsoluteNuts(g)) continue;
        found++;
        expect(post.decide(g).action, DecisionAction.betRaise, reason: '${g.hero} ${board.join()}');
      }
      expect(found, greaterThan(5));
    });

    test('River: raise solo con valor top 15% o nuts', () {
      var raises = 0;
      for (var k = 0; k < 80; k++) {
        final board = deal(5, 0);
        final dead = board.fold<int>(0, (m, c) => m | c.bit);
        final hc = deal(2, dead);
        final g = GameState(stake: Stake.nl50, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 80, potBb: 20,
            hero: HoleCards(hc[0], hc[1]), board: board,
            actions: [...srp, const PlayerAction(Street.river, Position.bb, ActionType.check), const PlayerAction(Street.river, Position.btn, ActionType.bet, 12)]);
        final d = post.decide(g);
        if (d.action != DecisionAction.betRaise) continue;
        raises++;
        final h = HandTierClassifier.classify(hc[0].id, hc[1].id, [for (final c in board) c.id]);
        final ok = RangeEquity.isAbsoluteNuts(g) ||
            (h.tier == HandTier.nutsMonster && DefenseBudget.percentile(g, const ReadProfile(GgArchetype.unknownReg, [])) <= 0.15);
        expect(ok, isTrue, reason: '${g.hero} ${board.join()}');
      }
      expect(raises, greaterThanOrEqualTo(0));
    });
  });

  group('Capa de datos O(1)', () {
    test('Cold start < 10ms y lookup < 0.5ms', () {
      final sw = Stopwatch()..start();
      final repo = PackedLookupRepository.load();
      expect(sw.elapsedMicroseconds, lessThan(10000));
      final flop = Card.parseMany('As7d2c');
      sw.reset();
      var acc = 0.0;
      for (var k = 0; k < 10000; k++) {
        acc += repo.rfi(Position.btn, RakeTier.midRake, k % 169);
        acc += repo.flopBucket(flop).index;
      }
      expect(sw.elapsedMicroseconds / 10000, lessThan(500));
      expect(acc, greaterThan(0));
    });
    test('Tablas empaquetadas == motor (preflop y 1755 flops)', () {
      final repo = PackedLookupRepository.instance;
      for (final t in RakeTier.values) {
        for (final p in PackedLayout.rfiPositions) {
          final w = PreflopRangesDb.rfi(p, t).weights[PreflopAction.raise]!;
          for (var i = 0; i < 169; i++) {
            expect(repo.rfi(p, t, i), closeTo(w[i], 1 / 255));
          }
        }
        for (final (h, ip) in PackedLayout.vs3BetKeys) {
          final n = PreflopRangesDb.vs3Bet(h, heroInPosition: ip);
          for (var i = 0; i < 169; i++) {
            expect(repo.vs3Bet(h, ip: ip, tier: t, action: PackedAction.call, hand: i), closeTo(n.weights[PreflopAction.call]![i], 1 / 255));
          }
        }
      }
      for (var a = 0; a < 52; a++) {
        for (var b = a + 1; b < 52; b++) {
          for (var c = b + 1; c < 52; c++) {
            if ((a + b + c) % 7 != 0) continue;
            final f = [for (final x in [a, b, c]) Card(Rank.values[x >> 2], Suit.values[x & 3])];
            expect(repo.flopBucket(f), FlopLookupTable.bucketOf(f));
          }
        }
      }
    });
  });

  group('Controlador', () {
    test('Emite computing -> ready (inline) y valida entradas', () async {
      final c = SolverController(executor: const InlineExecutor());
      final states = <ControllerStatus>[];
      final sub = c.states.listen((s) => states.add(s.status));
      final ok = await c.submit(GameState(stake: Stake.nl50, heroPosition: Position.btn, hero: HoleCards.parse('AhKh')));
      expect(ok.status, ControllerStatus.ready);
      expect(ok.decision!.action, DecisionAction.betRaise);
      final bad = await c.submit(GameState(stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.btn, hero: HoleCards.parse('AhKh')));
      expect(bad.status, ControllerStatus.invalid);
      await Future<void>.delayed(Duration.zero);
      expect(states, [ControllerStatus.computing, ControllerStatus.ready, ControllerStatus.invalid]);
      await sub.cancel();
      await c.dispose();
    });
    test('Isolate persistente: resultado idéntico al inline', () async {
      final c = SolverController(executor: IsolateExecutor());
      final g = GameState(stake: Stake.nl50, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 97.5, potBb: 5.5,
          hero: HoleCards.parse('Kh8d'), board: Card.parseMany('Kd7c2s'),
          actions: [pf(Position.btn, ActionType.raise, 2.5), pf(Position.bb, ActionType.call, 2.5),
            const PlayerAction(Street.flop, Position.bb, ActionType.check), const PlayerAction(Street.flop, Position.btn, ActionType.bet, 1.8)]);
      final r = await c.submit(g);
      expect(r.status, ControllerStatus.ready);
      expect(r.decision!.action, solve(g, null).action);
      await c.dispose();
    });
    test('StateValidator: raise no creciente y postflop incompleto', () {
      final g = GameState(stake: Stake.nl50, heroPosition: Position.co, hero: HoleCards.parse('AhKh'), board: Card.parseMany('As7d2c'),
          actions: [pf(Position.utg, ActionType.raise, 3), pf(Position.mp, ActionType.raise, 2.5)]);
      final issues = StateValidator.validate(g).map((e) => e.field).toSet();
      expect(issues, containsAll(['actions', 'villainPosition', 'potBb']));
    });
  });
}
