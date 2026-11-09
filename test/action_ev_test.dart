import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/core/evaluators/action_ev_calculator.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/postflop/postflop_heuristic_engine.dart';
import 'package:sol_ver/core/preflop/full_tree_preflop.dart';
import 'package:sol_ver/core/preflop/preflop_ranges_db.dart';
import 'package:sol_ver/core/reads/gg_profiler.dart';

const post = PostflopHeuristicEngine();
PlayerAction a(Street s, Position p, ActionType t, [double x = 0]) => PlayerAction(s, p, t, x);
const srp = [PlayerAction(Street.preflop, Position.btn, ActionType.raise, 2.5), PlayerAction(Street.preflop, Position.bb, ActionType.call, 2.5)];
const reg = ReadProfile(GgArchetype.unknownReg, []);

GameState flopBtn(String h, String b) => GameState(stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 97.5,
    potBb: 5.5, hero: HoleCards.parse(h), board: Card.parseMany(b), actions: [...srp, a(Street.flop, Position.bb, ActionType.check)]);

void main() {
  test('EV(fold)=0, mapa actionEVs expuesto en postflop y preflop', () {
    final d = post.decide(flopBtn('AhKd', 'As7d2c'));
    expect(d.actionEVs, isNotNull);
    expect(d.actionEVs!['fold'], 0);
    expect(d.toJson().containsKey('action_evs_bb'), isTrue);
    final p = const FullTreePreflop().decide(GameState(stake: Stake.nl50, heroPosition: Position.bb, effectiveStackBb: 100,
        hero: HoleCards.parse('KhQh'), actions: const [PlayerAction(Street.preflop, Position.btn, ActionType.raise, 2.5)]));
    expect(p.actionEVs, isNotNull);
    expect(p.actionEVs!.keys, containsAll(['fold', 'call', 'betRaise']));
  });

  test('Fórmulas: EV(check) = eq x EQR x (pot - rake); station en river => FE 0.05; scared capado => min(0.85, alpha x 1.35)', () {
    final g = flopBtn('AhKd', 'As7d2c');
    final ev = ActionEvCalculator.postflop(g, reg, potBefore: 5.5, toCall: 0, betSizeBb: 1.8);
    expect(ev.checkCall, closeTo(ev.equity * ev.eqr * (5.5 - RakeConfig.byStake[Stake.nl50]!.rakeOn(5.5)), 1e-9));
    final fish = GgProfiler.classify(const SmartHudInput(vpip: 50, pfr: 5, threeBet: 1, stackBb: 100));
    expect(ActionEvCalculator.foldEquity(0.6, 0.4, fish, VillainProfile.callingStation, river: true, capped: false), 0.05);
    final scared = GgProfiler.classify(const SmartHudInput(vpip: 20, pfr: 17, threeBet: 4, stackBb: 100));
    expect(ActionEvCalculator.foldEquity(0.2, 0.5, scared, VillainProfile.regAbc, river: true, capped: true), closeTo(0.675, 1e-9));
    expect(ActionEvCalculator.foldEquity(0.2, 0.7, scared, VillainProfile.regAbc, river: true, capped: true), 0.85);
  });

  test('Puerta de EV: ninguna apuesta propia queda por debajo del check más allá de la banda (salvo intervención documentada)', () {
    var bets = 0;
    for (final b in ['As7d2c', 'Kd8h3s', 'Qc7h2d', '9h8h4c', 'Jh9s8d', '7s6s5d']) {
      for (final h in ['AhKd', 'QhQd', '5h4d', 'JcTc', '8c8d', '6h5h', 'KcQc', 'Ad5d']) {
        if ({for (final c in Card.parseMany(h)) c.id}.intersection({for (final c in Card.parseMany(b)) c.id}).isNotEmpty) continue;
        final g = flopBtn(h, b);
        final d = post.decide(g);
        if (d.action != DecisionAction.betRaise) continue;
        bets++;
        final ev = d.actionEVs!;
        final text = '${d.justificacionGto} ${d.ajusteExplotativoRead}';
        if (PostflopHeuristicEngine.protectedMarkers.any(text.contains)) continue;
        expect(ev['check']! - ev['betRaise']!, lessThanOrEqualTo(PostflopHeuristicEngine.evTolerance(5.5) + 1e-9), reason: '$h $b $ev');
      }
    }
    expect(bets, greaterThan(0));
  });

  test('Latencia: decisión postflop con EV < 5ms tras warm-up y cálculo de EV < 1ms', () {
    final g = flopBtn('AhQd', 'Kd8h3s');
    post.decide(g);
    ActionEvCalculator.postflop(g, reg, potBefore: 5.5, toCall: 0, betSizeBb: 1.8);
    final sw = Stopwatch()..start();
    for (var k = 0; k < 50; k++) {
      ActionEvCalculator.postflop(g, reg, potBefore: 5.5, toCall: 0, betSizeBb: 1.8);
    }
    expect(sw.elapsedMicroseconds / 50, lessThan(1000));
    sw.reset();
    for (var k = 0; k < 20; k++) {
      post.decide(g);
    }
    expect(sw.elapsedMicroseconds / 20, lessThan(5000));
  });

  test('Rake por stake: 7 niveles con cap en bb', () {
    expect(RakeConfig.byStake.length, 7);
    expect(RakeConfig.byStake[Stake.nl2]!.capBb, greaterThan(RakeConfig.byStake[Stake.nl200]!.capBb));
  });
}
