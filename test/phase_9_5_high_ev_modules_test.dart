import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/postflop/geometric_2e_planner.dart';
import 'package:sol_ver/core/postflop/postflop_heuristic_engine.dart';
import 'package:sol_ver/core/postflop/turn_river_solver.dart';
import 'package:sol_ver/core/preflop/full_tree_preflop.dart';
import 'package:sol_ver/core/preflop/range_notation.dart';
import 'package:sol_ver/core/preflop/sandwich_squeeze_exploit.dart';
import 'package:sol_ver/core/preflop/stack_topology_resolver.dart';
import 'package:sol_ver/core/reads/anti_counter_exploit_shield.dart';
import 'package:sol_ver/core/reads/gg_profiler.dart';

PlayerAction a(Street s, Position p, ActionType t, [double x = 0]) => PlayerAction(s, p, t, x);
const srp = [PlayerAction(Street.preflop, Position.btn, ActionType.raise, 2.5), PlayerAction(Street.preflop, Position.bb, ActionType.call, 2.5)];
const post = PostflopHeuristicEngine();
const tree = FullTreePreflop();
final flop = [a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 2), a(Street.flop, Position.bb, ActionType.call, 2)];

void main() {
  test('Geo-2E: f = (sqrt(1+2SPR)-1)/2 acotado 55-95%, River all-in limpio y nota en mathRationale', () {
    expect(Geometric2EPlanner.geoBetPct(2.32), closeTo((sqrt(1 + 2 * 2.32) - 1) / 2 * 100, 1e-9));
    final p = Geometric2EPlanner.plan(35.5, 82.5)!;
    expect(p.$1, inInclusiveRange(55, 95));
    expect(p.$2, closeTo(p.$1, 0.5)); // geométrico puro: el shove del River es el mismo % del bote
    expect(Geometric2EPlanner.plan(10, 50), isNull); // SPR 5 fuera de ventana
    final g = GameState(stake: Stake.nl25, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 82.5, potBb: 35.5,
        hero: HoleCards.parse('KhKs'), board: Card.parseMany('Kd7s2s4h'), actions: [...srp, ...flop, a(Street.turn, Position.bb, ActionType.check)]);
    final d = post.decide(g);
    expect(d.action, DecisionAction.betRaise);
    expect(d.sizing!.potPct, closeTo(p.$1, 0.5));
    expect(d.justification!.mathRationale, startsWith('Geo-2E Sizing ('));
  });

  test('Short-Stack Topology 35bb: pares bajos sin implícitas => fold; broadways/88+ => 3-bet lineal; amenaza detrás +6%', () {
    GameState g(String h, {Map<Position, double> stacks = const {}, double eff = 35}) => GameState(stake: Stake.nl50, heroPosition: Position.btn,
        villainPosition: Position.co, effectiveStackBb: eff, hero: HoleCards.parse(h), seatStacksBb: stacks,
        actions: const [PlayerAction(Street.preflop, Position.co, ActionType.raise, 2.5)]);
    expect(StackTopologyResolver.eqrMultiplier(Matrix169.indexOf('55'), 35), StackTopologyResolver.cut);
    expect(tree.decide(g('5c5d')).action, DecisionAction.fold);
    expect(tree.decide(g('8c8d')).action, DecisionAction.betRaise);
    expect(tree.decide(g('5c5d', eff: 100)).action, DecisionAction.call);
    expect(StackTopologyResolver.behindSqueezeThreat(g('5c5d', stacks: {Position.bb: 140}, eff: 100)), isTrue);
  });

  test('Monocolor: stab 28% con blocker nut; TP sin palo vs check-raise => fold disciplinado; 4-flush sin palo => 0% farol', () {
    final stab = post.decide(GameState(stake: Stake.nl10, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 97.5, potBb: 5.5,
        villainProfile: VillainProfile.poolDefault, hero: HoleCards.parse('AsQd'), board: Card.parseMany('Ks9s4s'), actions: [...srp, a(Street.flop, Position.bb, ActionType.check)]));
    expect(stab.action, DecisionAction.betRaise);
    expect(stab.sizing!.potPct, closeTo(28, 0.5));
    expect(stab.exploitDeltaEV!, greaterThanOrEqualTo(0));
    final xr = post.decide(GameState(stake: Stake.nl10, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 97.5, potBb: 5.5,
        villainProfile: VillainProfile.poolDefault, hero: HoleCards.parse('KdQc'), board: Card.parseMany('Ks9s4s'),
        actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 2), a(Street.flop, Position.bb, ActionType.raise, 7)]));
    expect(xr.action == DecisionAction.fold || xr.justification!.activeCloserRule == 'EV_Sanity_Guard', isTrue);
    final four = GameState(stake: Stake.nl10, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 95.5, potBb: 9.1,
        villainProfile: VillainProfile.poolDefault, hero: HoleCards.parse('QdJc'), board: Card.parseMany('Ks9s4s2d7s'),
        actions: [...srp, ...flop, a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.check), a(Street.river, Position.bb, ActionType.check)]);
    final plan = const TurnRiverSolver().plan(four, ReadProfile.fromVillainProfile(VillainProfile.poolDefault), heroHadInitiative: false, pot: 9.1, stack: 95.5);
    expect(plan.role == HandRole.bluff || plan.role == HandRole.thinBluff, isFalse);
  });

  test('Sandwich Squeeze: caller capado, FE combinada derivada de tablas y gate FE > alpha', () {
    final g = GameState(stake: Stake.nl10, heroPosition: Position.bb, villainPosition: Position.co, villainProfile: VillainProfile.poolDefault,
        hero: HoleCards.parse('Ah2h'));
    final (fe, alpha, ev) = SandwichSqueezeExploit.evaluate(g, opener: Position.co, caller: Position.btn, sizeBb: 13.75, potBb: 6.5)!;
    expect(fe, inExclusiveRange(0, 1));
    expect(alpha, closeTo(12.75 / (12.75 + 6.5), 1e-9));
    expect(ev > 0, fe > alpha);
    expect(SandwichSqueezeExploit.evaluate(GameState(stake: Stake.nl10, heroPosition: Position.bb, hero: HoleCards.parse('Ah2h')),
        opener: Position.co, caller: Position.btn, sizeBb: 13.75, potBb: 6.5), isNull); // Reg_GTO: sin módulo
  });

  test('Escudo anti-contra-exploit: NL50 + PFR 26/3B 11 => sin T2 (call con TP); NL25 => T2 activo', () {
    const agg = ReadProfile(GgArchetype.poolDefault, ['HUD'], pfr: 26, threeBet: 11);
    GameState g(Stake st) => GameState(stake: st, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 88, potBb: 23.7,
        villainProfile: VillainProfile.poolDefault, hero: HoleCards.parse('KdQc'), board: Card.parseMany('Kc8d3h2s6c'),
        actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8), a(Street.flop, Position.bb, ActionType.call, 1.8),
          a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 7.3), a(Street.turn, Position.bb, ActionType.call, 7.3),
          a(Street.river, Position.bb, ActionType.check), a(Street.river, Position.btn, ActionType.bet, 19)]);
    expect(AntiCounterExploitShield.active(Stake.nl50, agg), isTrue);
    expect(AntiCounterExploitShield.active(Stake.nl25, agg), isFalse);
    expect(post.decide(g(Stake.nl50), read: agg).ajusteExplotativoRead.contains('Terminal_Closer T2'), isFalse);
    expect(post.decide(g(Stake.nl25), read: agg).ajusteExplotativoRead, contains('Terminal_Closer T2'));
  });
}
