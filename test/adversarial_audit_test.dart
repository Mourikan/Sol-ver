import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/core/discipline/bluff_catch_auditor.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/reads/gg_profiler.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/postflop/flop_lookup_table.dart';
import 'package:sol_ver/core/postflop/geometry.dart';
import 'package:sol_ver/core/postflop/hand_tier.dart';
import 'package:sol_ver/core/postflop/late_streets_heuristic.dart';
import 'package:sol_ver/core/postflop/postflop_heuristic_engine.dart';
import 'package:sol_ver/core/postflop/postflop_ranges.dart';
import 'package:sol_ver/core/preflop/full_tree_preflop.dart';
import 'package:sol_ver/core/preflop/preflop_ranges_db.dart';
import 'package:sol_ver/core/preflop/range_notation.dart';

const tree = FullTreePreflop();
const post = PostflopHeuristicEngine();

PlayerAction pf(Position p, ActionType t, [double a = 0]) => PlayerAction(Street.preflop, p, t, a);
PlayerAction fl(Position p, ActionType t, [double a = 0]) => PlayerAction(Street.flop, p, t, a);

String cardStr(int id) => '${'23456789TJQKA'[id >> 2]}${'cdhs'[id & 3]}';

String comboFor(int i, int deadMask) {
  for (final (a, b) in Matrix169.concreteCombos(i)) {
    if (deadMask & ((1 << a) | (1 << b)) == 0) return cardStr(a) + cardStr(b);
  }
  return '';
}

GameState srpFlop(Position hero, Position villain, Position pfa, String cards, String board,
        {List<PlayerAction> street = const [], VillainProfile vp = VillainProfile.gtoBase, Stake st = Stake.nl50, double pot = 5.5, double stack = 97.5}) =>
    GameState(
      stake: st,
      heroPosition: hero,
      villainPosition: villain,
      effectiveStackBb: stack,
      potBb: pot,
      hero: HoleCards.parse(cards),
      board: Card.parseMany(board),
      villainProfile: vp,
      actions: [pf(pfa, ActionType.raise, 2.5), pf(pfa == hero ? villain : hero, ActionType.call, 2.5), ...street],
    );

int maskOf(String board) => Card.parseMany(board).fold(0, (m, c) => m | c.bit);

void main() {
  group('AUDIT 1: 0% cold call en SB (High Rake)', () {
    for (final opener in [Position.utg, Position.mp, Position.co, Position.btn]) {
      test('SB vs open ${opener.name}: 169 manos, ninguna call', () {
        expect(PreflopRangesDb.vsRfi(Position.sb, opener, RakeTier.microHighRake).percent(PreflopAction.call), 0);
        for (var i = 0; i < 169; i++) {
          final d = tree.decide(GameState(
              stake: Stake.nl10, heroPosition: Position.sb, effectiveStackBb: 100,
              hero: HoleCards.parse(comboFor(i, 0)), actions: [pf(opener, ActionType.raise, 2.5)]));
          expect(d.action, isNot(DecisionAction.call), reason: Matrix169.label(i));
        }
      });
    }
    test('SB en squeeze y cold 4-bet: nunca call', () {
      for (var i = 0; i < 169; i++) {
        final c = comboFor(i, 0);
        final sq = tree.decide(GameState(stake: Stake.nl10, heroPosition: Position.sb, effectiveStackBb: 100, hero: HoleCards.parse(c),
            actions: [pf(Position.co, ActionType.raise, 2.5), pf(Position.btn, ActionType.call, 2.5)]));
        final c4 = tree.decide(GameState(stake: Stake.nl10, heroPosition: Position.sb, effectiveStackBb: 100, hero: HoleCards.parse(c),
            actions: [pf(Position.co, ActionType.raise, 2.5), pf(Position.btn, ActionType.raise, 8)]));
        expect(sq.action, isNot(DecisionAction.call));
        expect(c4.action, isNot(DecisionAction.call));
      }
    });
  });

  group('AUDIT 2: PFA OOP (UTG vs BTN) en 7s6s5d => check alto', () {
    test('Frecuencia de c-bet del rango UTG < 50% (check > 65%)', () {
      final flop = Card.parseMany('7s6s5d');
      expect(FlopLookupTable.bucketOf(flop), FlopBucket.lowVeryConnectedTwoTone);
      final (pfaR, defR) = PostflopRanges.forPot(Position.utg, Position.btn, PotType.srp, RakeTier.midRake);
      final r = FlopLookupTable.evaluate(flop, HuNode.srpOop, pfaRange: pfaR, defenderRange: defR);
      expect(r.strategy, StrategyClass.highCheckWithInitiative);
      expect(r.betFreq, lessThan(0.5));
      expect(r.checkFreq, greaterThan(0.65));
      for (final tier in RakeTier.values) {
        final (u, _) = PostflopRanges.forPot(Position.utg, Position.btn, PotType.srp, tier);
        expect(FlopLookupTable.evaluate(flop, HuNode.srpOop, pfaRange: u).checkFreq, greaterThan(0.65));
      }
    });
    test('Overpair QQ de UTG: check', () {
      final d = post.decide(srpFlop(Position.utg, Position.btn, Position.utg, 'QhQd', '7s6s5d'));
      expect(d.action, DecisionAction.check);
    });
  });

  group('AUDIT 3: BB nunca donkea en As Kd 2c', () {
    test('donk 0% y check 100% del rango de defensa BB', () {
      const board = 'AsKd2c';
      final flop = Card.parseMany(board);
      final (pfaR, defR) = PostflopRanges.forPot(Position.btn, Position.bb, PotType.srp, RakeTier.midRake);
      final r = FlopLookupTable.evaluate(flop, HuNode.srpIp, pfaRange: pfaR, defenderRange: defR);
      expect(r.donkEnabled, isFalse);
      expect(r.donkFreq, 0);
      final dead = maskOf(board);
      for (var i = 0; i < 169; i++) {
        if (defR[i] <= 0) continue;
        final c = comboFor(i, dead);
        if (c.isEmpty) continue;
        final d = post.decide(srpFlop(Position.bb, Position.btn, Position.btn, c, board));
        expect(d.action, DecisionAction.check, reason: Matrix169.label(i));
      }
    });
  });

  group('AUDIT 4: BB en 6d 5c 4h vs BTN contempla donk y check-raise', () {
    test('Donk habilitado con frecuencia > 0', () {
      final flop = Card.parseMany('6d5c4h');
      final (pfaR, defR) = PostflopRanges.forPot(Position.btn, Position.bb, PotType.srp, RakeTier.midRake);
      final r = FlopLookupTable.evaluate(flop, HuNode.srpIp, pfaRange: pfaR, defenderRange: defR);
      expect(r.donkEnabled, isTrue);
      expect(r.donkFreq, greaterThan(0));
      expect(r.strategy, StrategyClass.highCheckWithInitiative);
    });
    test('BB con escalera (7h3h) donkea; enfrentando c-bet hace check-raise', () {
      final lead = post.decide(srpFlop(Position.bb, Position.btn, Position.btn, '7h3h', '6d5c4h'));
      expect(lead.action, DecisionAction.betRaise);
      final xr = post.decide(srpFlop(Position.bb, Position.btn, Position.btn, '7h3h', '6d5c4h',
          street: [fl(Position.bb, ActionType.check), fl(Position.btn, ActionType.bet, 1.8)]));
      expect(xr.frequencies[DecisionAction.betRaise], greaterThanOrEqualTo(0.5));
      expect(xr.action, isNot(DecisionAction.fold));
      if (xr.action == DecisionAction.betRaise) expect(xr.sizing!.bb, greaterThan(1.8 * 2));
    });
    test('BB con combo draw OOP (FD + OESD) enfrentando c-bet: check-raise semi-bluff 100%', () {
      final d = post.decide(srpFlop(Position.bb, Position.btn, Position.btn, '9d8d', '7d6c2d',
          street: [fl(Position.bb, ActionType.check), fl(Position.btn, ActionType.bet, 1.8)]));
      expect(d.action, DecisionAction.betRaise);
    });
  });

  group('AUDIT 5: Squeeze != 3-bet HU', () {
    test('2 callers: (3.5x IP) open + 1x open por caller', () {
      final sq = tree.decide(GameState(stake: Stake.nl25, heroPosition: Position.btn, effectiveStackBb: 100, hero: HoleCards.parse('AhKh'),
          actions: [pf(Position.utg, ActionType.raise, 2.5), pf(Position.mp, ActionType.call, 2.5), pf(Position.co, ActionType.call, 2.5)]));
      final hu = tree.decide(GameState(stake: Stake.nl25, heroPosition: Position.btn, effectiveStackBb: 100, hero: HoleCards.parse('AhKh'),
          actions: [pf(Position.utg, ActionType.raise, 2.5)]));
      expect(FullTreePreflop.classify(GameState(stake: Stake.nl25, heroPosition: Position.btn,
              actions: [pf(Position.utg, ActionType.raise, 2.5), pf(Position.mp, ActionType.call, 2.5), pf(Position.co, ActionType.call, 2.5)]))
          .scenario, TreeScenario.squeeze);
      expect(sq.sizing!.bb, closeTo(2.5 * 3.5 + 2 * 2.5, 1e-9));
      expect(sq.sizing!.bb, isNot(closeTo(hu.sizing!.bb, 0.01)));
    });
    test('OOP (SB) con 2 callers: 4.5x + 2x', () {
      final sq = tree.decide(GameState(stake: Stake.nl100, heroPosition: Position.sb, effectiveStackBb: 100, hero: HoleCards.parse('QhQd'),
          actions: [pf(Position.mp, ActionType.raise, 2.5), pf(Position.co, ActionType.call, 2.5), pf(Position.btn, ActionType.call, 2.5)]));
      expect(sq.sizing!.bb, closeTo(2.5 * 4.5 + 2 * 2.5, 1e-9));
    });
    test('Rango de squeeze sin especulativas bajas (65s, 22, 87s fold)', () {
      for (final c in ['6h5h', '2h2d', '8h7h']) {
        final d = tree.decide(GameState(stake: Stake.nl100, heroPosition: Position.btn, effectiveStackBb: 100, hero: HoleCards.parse(c),
            actions: [pf(Position.co, ActionType.raise, 2.5), pf(Position.utg, ActionType.call, 2.5)]));
        expect(d.action, DecisionAction.fold, reason: c);
      }
    });
  });

  group('PRO: árbol preflop restante', () {
    test('Iso vs limpers (Fase 9.4): 3.5bb + 1.2bb x N IP / 4.5bb + 1.5bb x N OOP', () {
      expect(FullTreePreflop.isoSize(Position.btn, 2), closeTo(5.9, 1e-9));
      expect(FullTreePreflop.isoSize(Position.sb, 3), closeTo(9.0, 1e-9));
      final d = tree.decide(GameState(stake: Stake.nl10, heroPosition: Position.co, hero: HoleCards.parse('AhQd'),
          actions: [pf(Position.utg, ActionType.call, 1), pf(Position.mp, ActionType.call, 1)]));
      expect(d.action, DecisionAction.betRaise);
      expect(d.sizing!.bb, closeTo(5.9, 1e-9));
    });
    test('Iso range lineal: sin bluffs bajos sin EQR', () {
      for (final h in [Position.mp, Position.co, Position.btn, Position.sb]) {
        final r = FullTreePreflop.isoRange(h, RakeTier.midRake, station: false);
        for (final l in ['64s', '75s', '53s', '96s', '86s']) {
          expect(r[Matrix169.indexOf(l)], 0, reason: '$h $l');
        }
      }
    });
    test('1 a 5 limpers soportados', () {
      for (var n = 1; n <= 5; n++) {
        final acts = [for (var k = 0; k < n; k++) pf(Position.values[k], ActionType.call, 1)];
        final spot = FullTreePreflop.classify(GameState(stake: Stake.nl50, heroPosition: Position.bb, actions: acts));
        expect(spot.limpers, n);
        expect(spot.scenario, TreeScenario.isoVsLimpers);
      }
    });
    test('Cold 4-bet: QQ+/AK raise, JJ/AQs fold, 0% call', () {
      GameState g(String c) => GameState(stake: Stake.nl100, heroPosition: Position.bb, effectiveStackBb: 100, hero: HoleCards.parse(c),
          actions: [pf(Position.co, ActionType.raise, 2.5), pf(Position.btn, ActionType.raise, 8)]);
      expect(FullTreePreflop.classify(g('KhKd')).scenario, TreeScenario.cold4Bet);
      for (final c in ['KhKd', 'QhQd', 'AhKd']) {
        expect(tree.decide(g(c)).action, DecisionAction.betRaise, reason: c);
      }
      for (final c in ['JhJd', 'AhQh', 'KhQh', 'ThTd']) {
        expect(tree.decide(g(c)).action, DecisionAction.fold, reason: c);
      }
    });
    test('4-bet estándar (Hero abrió) delega al nodo vs 3-bet', () {
      final s = GameState(stake: Stake.nl100, heroPosition: Position.co, effectiveStackBb: 100, hero: HoleCards.parse('KhQh'),
          actions: [pf(Position.co, ActionType.raise, 2.5), pf(Position.btn, ActionType.raise, 8)]);
      expect(FullTreePreflop.classify(s).scenario, TreeScenario.standard4Bet);
      expect(tree.decide(s).action, DecisionAction.call);
    });
  });

  group('PRO: flops y matemática', () {
    test('1755 flops isomorfos cubiertos por 20 buckets', () {
      final canon = <String>{};
      final hits = <FlopBucket, int>{};
      for (var a = 0; a < 52; a++) {
        for (var b = a + 1; b < 52; b++) {
          for (var c = b + 1; c < 52; c++) {
            final key = _canonical([a, b, c]);
            if (!canon.add(key)) continue;
            final f = [for (final x in [a, b, c]) Card(Rank.values[x >> 2], Suit.values[x & 3])];
            final bk = FlopLookupTable.bucketOf(f);
            hits[bk] = (hits[bk] ?? 0) + 1;
          }
        }
      }
      expect(canon.length, 1755);
      expect(hits.keys.toSet(), FlopBucket.values.toSet());
      expect(FlopLookupTable.table.length, 20);
    });
    test('Range bet pequeño en A72r (SRP IP) y polar en Qh Jh 8d', () {
      final (pfaR, _) = PostflopRanges.forPot(Position.btn, Position.bb, PotType.srp, RakeTier.midRake);
      final a = FlopLookupTable.evaluate(Card.parseMany('As7d2c'), HuNode.srpIp, pfaRange: pfaR);
      expect(a.strategy, StrategyClass.rangeBetSmall);
      expect(a.sizePct, inInclusiveRange(25, 33));
      expect(a.betFreq, greaterThan(0.5));
      final q = FlopLookupTable.evaluate(Card.parseMany('QhJh8d'), HuNode.srpIp, pfaRange: pfaR);
      expect(q.strategy, StrategyClass.polarizedBetLarge);
      expect(q.sizePct, inInclusiveRange(66, 80));
      expect(FlopLookupTable.evaluate(Card.parseMany('KhTd9c'), HuNode.srpIp, pfaRange: pfaR).strategy, StrategyClass.polarizedBetLarge);
    });
    test('Donk solo en boards bajos conectados / pareados bajos; 0 en A/K-high', () {
      for (final b in ['6s5d3c', '7h5d4c', '8h8d6c', '7c7d5h']) {
        expect(FlopLookupTable.donkEnabled(FlopLookupTable.bucketOf(Card.parseMany(b)), HuNode.srpIp), isTrue, reason: b);
      }
      for (final b in ['As7d2c', 'Kd8h3s', 'AhKd2c', 'KsQd2h']) {
        expect(FlopLookupTable.donkEnabled(FlopLookupTable.bucketOf(Card.parseMany(b)), HuNode.srpIp), isFalse, reason: b);
      }
      expect(FlopLookupTable.donkEnabled(FlopLookupTable.bucketOf(Card.parseMany('6s5d3c')), HuNode.srpOop), isFalse);
    });
    test('MDF, alpha y geometría exactas', () {
      expect(PotGeometry.mdf(10, 5), closeTo(2 / 3, 1e-12));
      expect(PotGeometry.alpha(10, 5), closeTo(1 / 3, 1e-12));
      final f = PotGeometry.geometricFraction(10, 100, 3);
      var p = 10.0;
      for (var i = 0; i < 3; i++) {
        p += 2 * f * p;
      }
      expect(p, closeTo(10 + 2 * 100, 1e-9));
    });
    test('HandTiers', () {
      HandTier t(String h, String b) {
        final hc = HoleCards.parse(h);
        return HandTierClassifier.classify(hc.high.id, hc.low.id, [for (final c in Card.parseMany(b)) c.id]).tier;
      }
      expect(t('7h7d', '7s6s5d'), HandTier.nutsMonster);
      expect(t('QhQd', '7s6s5d'), HandTier.strongTopPairOverpair);
      expect(t('AhKd', 'Ks8d3c'), HandTier.strongTopPairOverpair);
      expect(t('Kh4d', 'Ks8d3c'), HandTier.marginalMadeShowdown);
      expect(t('AsJs', 'Ks8s3c'), HandTier.highEquityComboDraw);
      expect(t('9h8h', 'Ts7d2c'), HandTier.highEquityComboDraw);
      expect(t('AhQh', 'Ks8h3c'), HandTier.backdoorBlockerBluff);
      expect(t('3h2d', 'KsJh8c'), HandTier.airGiveUp);
    });
  });

  group('PRO: turn y river', () {
    test('Clasificación de turn', () {
      final flop = Card.parseMany('9s5h2d');
      expect(TurnEngine.classify(flop, Card.parse('3c')), TurnCardClass.drawCompleting);
      expect(TurnEngine.classify(flop, Card.parse('Kc')), TurnCardClass.scareCardPfa);
      expect(TurnEngine.classify(flop, Card.parse('9c')), TurnCardClass.blank);
      expect(TurnEngine.classify(Card.parseMany('9s5s2d'), Card.parse('Js')), TurnCardClass.drawCompleting);
    });
    test('Blank: double barrel 66-75% con monster; color completado: check con top pair', () {
      final barrel = post.decide(GameState(stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.bb,
          effectiveStackBb: 95, potBb: 9, hero: HoleCards.parse('9h9c'), board: Card.parseMany('9s5h2dKc'),
          actions: [pf(Position.btn, ActionType.raise, 2.5), pf(Position.bb, ActionType.call, 2.5),
            fl(Position.bb, ActionType.check), fl(Position.btn, ActionType.bet, 1.8), fl(Position.bb, ActionType.call, 1.8),
            const PlayerAction(Street.turn, Position.bb, ActionType.check)]));
      expect(barrel.action, DecisionAction.betRaise);
      final blank = post.decide(GameState(stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.bb,
          effectiveStackBb: 95, potBb: 9, hero: HoleCards.parse('9h9c'), board: Card.parseMany('9s5h2d3c'),
          actions: [pf(Position.btn, ActionType.raise, 2.5), pf(Position.bb, ActionType.call, 2.5),
            fl(Position.btn, ActionType.bet, 1.8), fl(Position.bb, ActionType.call, 1.8)]));
      expect(blank.action, DecisionAction.betRaise);
      final p = TurnEngine.withInitiative(TurnCardClass.blank,
          HandTierClassifier.classify(Card.parse('9h').id, Card.parse('9c').id, [for (final c in Card.parseMany('9s5h2dTc')) c.id]),
          pot: 9, stack: 95);
      expect(p.sizePct, inInclusiveRange(66, 75));
      final tp = post.decide(GameState(stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.bb,
          effectiveStackBb: 95, potBb: 9, hero: HoleCards.parse('AcKd'), board: Card.parseMany('Ks8s3dJs'),
          actions: [pf(Position.btn, ActionType.raise, 2.5), pf(Position.bb, ActionType.call, 2.5),
            fl(Position.btn, ActionType.bet, 1.8), fl(Position.bb, ActionType.call, 1.8)]));
      expect(tp.action, DecisionAction.check);
    });
    test('River: farol polarizado (75-125%) con blocker de nut flush', () {
      final d = post.decide(GameState(stake: Stake.nl100, heroPosition: Position.btn, villainPosition: Position.bb,
          effectiveStackBb: 80, potBb: 20, hero: HoleCards.parse('AsTd'), board: Card.parseMany('Ks8s3d2h6s'),
          actions: [pf(Position.btn, ActionType.raise, 2.5), pf(Position.bb, ActionType.call, 2.5),
            const PlayerAction(Street.turn, Position.btn, ActionType.bet, 6), const PlayerAction(Street.turn, Position.bb, ActionType.call, 6)]));
      expect(d.action, DecisionAction.betRaise);
      expect(d.sizing!.potPct, inInclusiveRange(75, 125));
    });
    test('River bluff-catch: paga sin bloquear proyectos fallidos, foldea si los bloquea', () {
      GameState g(String h) => GameState(stake: Stake.nl100, heroPosition: Position.bb, villainPosition: Position.btn,
          effectiveStackBb: 80, potBb: 20, hero: HoleCards.parse(h), board: Card.parseMany('Ks8s3d2h4c'),
          actions: [pf(Position.btn, ActionType.raise, 2.5), pf(Position.bb, ActionType.call, 2.5),
            const PlayerAction(Street.river, Position.bb, ActionType.check), const PlayerAction(Street.river, Position.btn, ActionType.bet, 10)]);
      expect(post.decide(g('8h7h')).action, DecisionAction.call);
      final unb = BluffCatchAuditor.audit(g('8h7h'), const ReadProfile(GgArchetype.unknownReg, []), pot: 20, call: 10, heroHasNuts: false);
      final blk = BluffCatchAuditor.audit(g('8d7s'), const ReadProfile(GgArchetype.unknownReg, []), pot: 20, call: 10, heroHasNuts: false);
      expect(unb.availableBluffs, greaterThan(blk.availableBluffs));
    });
    test('DefenseBudget: marginal paga 33% y aire foldea overbet', () {
      GameState g(double bet) => srpFlop(Position.bb, Position.btn, Position.btn, '8h7d', 'Ks8d3c',
          street: [fl(Position.bb, ActionType.check), fl(Position.btn, ActionType.bet, bet)]);
      expect(post.decide(g(1.8)).action, DecisionAction.call);
      expect(post.decide(srpFlop(Position.bb, Position.btn, Position.btn, '6h5h', 'Ks8d3c',
          street: [fl(Position.bb, ActionType.check), fl(Position.btn, ActionType.bet, 7)])).action, DecisionAction.fold);
    });
  });

  group('DEV: contrato y rendimiento', () {
    test('Postflop sin pot/stack => MissingInputs', () {
      expect(() => post.decide(GameState(stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.bb,
          hero: HoleCards.parse('AhKh'), board: Card.parseMany('As7d2c'),
          actions: [pf(Position.btn, ActionType.raise, 2.5), pf(Position.bb, ActionType.call, 2.5)])), throwsA(isA<MissingInputs>()));
    });
    test('Decisión postflop < 5ms (promedio, tras warm-up)', () {
      final s = srpFlop(Position.btn, Position.bb, Position.btn, 'AhQd', 'As7d2c');
      post.decide(s);
      final sw = Stopwatch()..start();
      for (var i = 0; i < 50; i++) {
        post.decide(s);
      }
      expect(sw.elapsedMicroseconds / 50, lessThan(5000));
    });
    test('Exploit: nit => bluff c-bet con air a sizing bajo; station => sin bluff', () {
      final nit = post.decide(srpFlop(Position.btn, Position.bb, Position.btn, '5h4d', 'Kd8h3s', vp: VillainProfile.nit));
      expect(nit.action, DecisionAction.betRaise);
      expect(nit.sizing!.potPct, lessThanOrEqualTo(33.01));
      final st = post.decide(srpFlop(Position.btn, Position.bb, Position.btn, 'QhJd', 'Kd8h3s', vp: VillainProfile.callingStation));
      expect(st.action, DecisionAction.check);
    });
  });
}

String _canonical(List<int> cards) {
  const perms = [
    [0, 1, 2, 3], [0, 1, 3, 2], [0, 2, 1, 3], [0, 2, 3, 1], [0, 3, 1, 2], [0, 3, 2, 1],
    [1, 0, 2, 3], [1, 0, 3, 2], [1, 2, 0, 3], [1, 2, 3, 0], [1, 3, 0, 2], [1, 3, 2, 0],
    [2, 0, 1, 3], [2, 0, 3, 1], [2, 1, 0, 3], [2, 1, 3, 0], [2, 3, 0, 1], [2, 3, 1, 0],
    [3, 0, 1, 2], [3, 0, 2, 1], [3, 1, 0, 2], [3, 1, 2, 0], [3, 2, 0, 1], [3, 2, 1, 0],
  ];
  String? best;
  for (final p in perms) {
    final m = [for (final c in cards) (c >> 2) * 4 + p[c & 3]]..sort();
    final k = m.join(',');
    if (best == null || k.compareTo(best) < 0) best = k;
  }
  return best!;
}
