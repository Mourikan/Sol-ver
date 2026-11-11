import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/postflop/postflop_heuristic_engine.dart';
import 'package:sol_ver/core/preflop/full_tree_preflop.dart';

PlayerAction a(Street s, Position p, ActionType t, [double x = 0, TimingTell tt = TimingTell.none]) => PlayerAction(s, p, t, x, tt);
const srp = [PlayerAction(Street.preflop, Position.btn, ActionType.raise, 2.5), PlayerAction(Street.preflop, Position.bb, ActionType.call, 2.5)];
const post = PostflopHeuristicEngine();
final flop = [a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8), a(Street.flop, Position.bb, ActionType.call, 1.8)];

GameState c1(String h) => GameState(stake: Stake.nl25, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 95.5, potBb: 9.1,
    villainProfile: VillainProfile.regAbc, hero: HoleCards.parse(h), board: Card.parseMany('Kc8d3h2s'),
    actions: [...srp, ...flop, a(Street.turn, Position.bb, ActionType.check, 0, TimingTell.instaAction)]);

GameState c3(String h) => GameState(stake: Stake.nl25, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 95.5, potBb: 9.1,
    villainProfile: VillainProfile.poolDefault, hero: HoleCards.parse(h), board: Card.parseMany('QsJs4d2c9s'),
    actions: [...srp, ...flop, a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.check), a(Street.river, Position.bb, ActionType.check)]);

void main() {
  test('Caso 1: Scared X/C flop + Insta_Check turn => rango capado, T4 explicado por pares medios que foldean', () {
    final d = post.decide(c1('5c4d'));
    final r = d.perceivedVillainRange!;
    expect(r.isCapped, isTrue);
    expect(r.nutsAndMonstersPct, lessThan(0.035));
    expect(r.mediumShowdownPct, greaterThan(r.pureAirAndBluffsPct));
    expect(d.action, DecisionAction.betRaise);
    expect(d.justification!.activeCloserRule, 'T4');
    expect(d.justification!.activeReadBadge, contains('Rango Capado'));
    expect(d.justification!.mathRationale, allOf(contains('FE Real'), contains('Pares Medios')));
  });

  test('Caso 2: Triple barrel 80% NL25 => rango polar nutted, T2 Hero-Fold con bluff real < pot odds', () {
    final g = GameState(stake: Stake.nl25, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 88, potBb: 23.7,
        villainProfile: VillainProfile.poolDefault, hero: HoleCards.parse('KdQc'), board: Card.parseMany('Kc8d3h2s6c'),
        actions: [...srp, ...flop, a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 7.3),
          a(Street.turn, Position.bb, ActionType.call, 7.3), a(Street.river, Position.bb, ActionType.check), a(Street.river, Position.btn, ActionType.bet, 19)]);
    final d = post.decide(g);
    final r = d.perceivedVillainRange!;
    expect(r.nutsAndMonstersPct, greaterThan(0.75));
    expect(r.pureAirAndBluffsPct, lessThanOrEqualTo(0.12 + 1e-9));
    expect(d.action, DecisionAction.fold);
    expect(d.justification!.activeCloserRule, 'T2');
    expect(r.predictedBluffFreq, lessThan(19 / (23.7 + 38)));
    expect(d.justification!.mathRationale, allOf(contains('< Pot Odds'), contains('T2_Shutdown')));
  });

  test('Caso 3: AsKs en QsJs4d2c9s bloquea el nut flush => menos nuts del villano y blocker en mathRationale', () {
    final blk = post.decide(c3('AsKs')), plain = post.decide(c3('AhKd'));
    expect(blk.perceivedVillainRange!.nutsAndMonstersPct, lessThan(plain.perceivedVillainRange!.nutsAndMonstersPct));
    expect(blk.perceivedVillainRange!.heroBlockedNutsCombos, greaterThan(plain.perceivedVillainRange!.heroBlockedNutsCombos));
    expect(blk.perceivedVillainRange!.mediumShowdownPct + blk.perceivedVillainRange!.pureAirAndBluffsPct,
        greaterThan(plain.perceivedVillainRange!.mediumShowdownPct + plain.perceivedVillainRange!.pureAirAndBluffsPct));
    expect(blk.justification!.mathRationale, contains('Blockers Hero'));
  });

  test('100% de decisiones con rango percibido y justificación (preflop/flop/turn/river) + JSON', () {
    final pre = const FullTreePreflop().decide(GameState(stake: Stake.nl10, heroPosition: Position.bb, villainPosition: Position.btn,
        hero: HoleCards.parse('AhKd'), actions: const [PlayerAction(Street.preflop, Position.btn, ActionType.raise, 2.5)]));
    final rfi = const FullTreePreflop().decide(GameState(stake: Stake.nl10, heroPosition: Position.co, hero: HoleCards.parse('AhKd')));
    for (final d in [pre, rfi, post.decide(c1('AhAd')), post.decide(c3('AsKs'))]) {
      expect(d.perceivedVillainRange, isNotNull);
      expect(d.justification, isNotNull);
      expect(d.toJson().containsKey('VillainPerceivedRange'), isTrue);
    }
    expect(pre.perceivedVillainRange!.totalActiveCombos, greaterThan(0));
  });

  test('Latencia: decisión postflop completa (ancla + inspector + justificador) < 1.5 ms en caliente', () {
    final hands = ['5c4d', 'AhAd', 'QhJh', 'Td9c'];
    for (final h in hands) {
      post.decide(c1(h));
    }
    final sw = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      for (final h in hands) {
        post.decide(c1(h));
      }
    }
    expect(sw.elapsedMicroseconds / 80 / 1000, lessThan(1.5));
  });
}
