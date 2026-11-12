import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/core/evaluators/reverse_implied_odds_guard.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/postflop/bait_induce_engine.dart';
import 'package:sol_ver/core/postflop/hand_tier.dart';
import 'package:sol_ver/core/postflop/next_street_runout_predictor.dart';
import 'package:sol_ver/core/postflop/postflop_heuristic_engine.dart';
import 'package:sol_ver/core/postflop/turn_river_solver.dart';
import 'package:sol_ver/core/reads/gg_profiler.dart';
import 'package:sol_ver/core/reads/range_funnel.dart';

PlayerAction a(Street s, Position p, ActionType t, [double x = 0]) => PlayerAction(s, p, t, x);
const srp = [PlayerAction(Street.preflop, Position.btn, ActionType.raise, 2.5), PlayerAction(Street.preflop, Position.bb, ActionType.call, 2.5)];
const post = PostflopHeuristicEngine();
final xx = [a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.check), a(Street.turn, Position.bb, ActionType.check),
  a(Street.turn, Position.btn, ActionType.check), a(Street.river, Position.bb, ActionType.check)];

GameState riverXX(String h) => GameState(stake: Stake.nl10, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 90, potBb: 5.5,
    villainProfile: VillainProfile.poolDefault, hero: HoleCards.parse(h), board: Card.parseMany('Kc8d3h2s6c'), actions: [...srp, ...xx]);

HandTierResult tier(GameState g) => HandTierClassifier.classify(g.hero!.high.id, g.hero!.low.id, [for (final c in g.board) c.id]);

void main() {
  final tilt = ReadProfile.fromVillainProfile(VillainProfile.poolDefault).withMental(VillainMentalState.steamingTilt);

  test('RunoutForecast: la carta que completa color es Peligro sin el color; Kill con el color', () {
    GameState flop(String h) => GameState(stake: Stake.nl10, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 97.5, potBb: 5.5,
        hero: HoleCards.parse(h), board: Card.parseMany('Qs7s2c'), actions: [...srp, a(Street.flop, Position.bb, ActionType.check)]);
    final no = NextStreetRunoutPredictor.forecast(flop('AhKd'))!;
    expect(no.abortDangerCards, contains('♠ Flush'));
    expect(no.barrelKillCards, containsAll(['A', 'K']));
    final yes = NextStreetRunoutPredictor.forecast(flop('AsKd'))!;
    expect(yes.barrelKillCards, contains('♠ Flush'));
    expect(yes.abortDangerCards, isNot(contains('♠ Flush')));
    final d = post.decide(flop('AhKd'));
    expect(d.runoutForecast, isNotNull);
    expect(d.toJson().containsKey('runout_forecast'), isTrue);
  });

  test('Tilt: 0% farol puro de Hero en River y anzuelo 25% con Nuts cuando EV_Bait > EV_Big', () {
    final air = riverXX('Jd9d');
    expect(TurnRiverSolver.exploitBluffFactor(tilt, RangeFunnel.track(air), Street.river, 5.5), 0);
    expect(post.decide(air, read: tilt).action, DecisionAction.check);
    final nuts = riverXX('3c3d');
    // Con el prior por defecto (30% de spazz-raise) la mejor apuesta grande rinde más: el anzuelo NO se aplica.
    final e = BaitInduceEngine.evaluate(nuts.copyWith(villainProfile: tilt.engineProfile), tilt, tier(nuts), pot: 5.5)!;
    expect(BaitInduceEngine.plan(nuts.copyWith(villainProfile: tilt.engineProfile), tilt, tier(nuts), pot: 5.5, toCall: 0) != null, e.$2 > e.$1);
    expect(post.decide(nuts, read: tilt).ajusteExplotativoRead.startsWith('Unmapped_Spot Bait_Induce'), e.$2 > e.$1);
    // Si el usuario calibra un rival que sube de farol con frecuencia alta, el anzuelo se activa y se certifica con Δ > 0.
    final prior = BaitInduceEngine.inducedRaiseFreq;
    BaitInduceEngine.inducedRaiseFreq = 0.9;
    try {
      final d = post.decide(nuts, read: tilt);
      expect(d.action, DecisionAction.betRaise);
      expect(d.sizing!.potPct, closeTo(BaitInduceEngine.baitPct, 0.5));
      expect(d.justificacionGto, contains('ANZUELO INDUCTOR'));
      expect(d.exploitDeltaEV!, greaterThan(0));
      expect(d.justification!.evWhyExplanation, contains('Sizing anzuelo (25% Pot)'));
    } finally {
      BaitInduceEngine.inducedRaiseFreq = prior;
    }
    // Sin tilt (pool normal) el anzuelo no aplica.
    expect(BaitInduceEngine.plan(nuts, ReadProfile.fromVillainProfile(VillainProfile.poolDefault), tier(nuts), pot: 5.5, toCall: 0), isNull);
  });

  test('RIO: AJo en A-8-3-2 vs doble barril de Nit/Pool => badge RIESGO RIO (fold salvo veto del EV_Sanity_Guard)', () {
    for (final vp in [VillainProfile.nit, VillainProfile.poolDefault]) {
      final g = GameState(stake: Stake.nl10, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 95.5, potBb: 9.1, villainProfile: vp,
          hero: HoleCards.parse('AcJd'), board: Card.parseMany('Ah8d3s2c'),
          actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 3.6), a(Street.flop, Position.bb, ActionType.call, 3.6),
            a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 9)]);
      final share = ReverseImpliedOddsGuard.dominationShare(g, ReadProfile.fromVillainProfile(vp), tier(g))!;
      expect(share, greaterThanOrEqualTo(ReverseImpliedOddsGuard.threshold));
      final d = post.decide(g);
      expect(d.justification!.activeReadBadge, contains('[⚠️ RIESGO RIO: KICKER DOMINADO]'));
      expect(d.action == DecisionAction.fold || d.justification!.activeCloserRule == 'EV_Sanity_Guard', isTrue);
    }
    // Reg_GTO (ancla) nunca recibe el guardia.
    final reg = GameState(stake: Stake.nl10, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 95.5, potBb: 9.1,
        hero: HoleCards.parse('AcJd'), board: Card.parseMany('Ah8d3s2c'),
        actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 3.6), a(Street.flop, Position.bb, ActionType.call, 3.6),
          a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 9)]);
    expect(ReverseImpliedOddsGuard.dominationShare(reg, ReadProfile.fromVillainProfile(VillainProfile.gtoBase), tier(reg)), isNull);
  });

  test('Latencia: evaluación completa (ancla + RIO/anzuelo + runout + inspector + narrativa) < 1.8 ms en caliente', () {
    final states = [riverXX('3c3d'), riverXX('Jd9d'),
      GameState(stake: Stake.nl10, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 95.5, potBb: 9.1, villainProfile: VillainProfile.poolDefault,
          hero: HoleCards.parse('AhKd'), board: Card.parseMany('Qs7s2c4h'),
          actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8), a(Street.flop, Position.bb, ActionType.call, 1.8),
            a(Street.turn, Position.bb, ActionType.check)])];
    for (final g in states) {
      post.decide(g, read: tilt);
    }
    // Mínimo de 5 rondas: filtra picos de carga del runner paralelo (debug), no el coste del motor.
    var best = double.infinity;
    for (var round = 0; round < 5; round++) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        for (final g in states) {
          post.decide(g, read: tilt);
        }
      }
      final ms = sw.elapsedMicroseconds / 60 / 1000;
      if (ms < best) best = ms;
    }
    expect(best, lessThan(1.8));
  });
}
