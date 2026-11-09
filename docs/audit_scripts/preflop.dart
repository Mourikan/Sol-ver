// ignore_for_file: avoid_print
import 'package:sol_ver/core/discipline/bluff_catch_auditor.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/postflop/postflop_heuristic_engine.dart';
import 'package:sol_ver/core/preflop/full_tree_preflop.dart';
import 'package:sol_ver/core/preflop/hand_normalizer.dart';
import 'package:sol_ver/core/preflop/preflop_solver_engine.dart';
import 'package:sol_ver/core/preflop/range_notation.dart';
import 'package:sol_ver/core/reads/gg_profiler.dart';

String cs(int id) => '${'23456789TJQKA'[id >> 2]}${'cdhs'[id & 3]}';
PlayerAction p(Position x, ActionType t, [double a = 0]) => PlayerAction(Street.preflop, x, t, a);
const tree = FullTreePreflop();

double pct(bool Function(String) f) {
  var c = 0;
  for (var i = 0; i < 169; i++) {
    final (x, y) = Matrix169.concreteCombos(i).first;
    if (f(cs(x) + cs(y))) c += Matrix169.combos(i);
  }
  return c / 13.26;
}

void main() {
  for (final st in [Stake.nl10, Stake.nl100]) {
    for (final o in [Position.utg, Position.co, Position.btn, Position.sb]) {
      final open = o == Position.sb ? 3.0 : 2.5;
      final def = pct((c) => tree.decide(GameState(stake: st, heroPosition: Position.bb, effectiveStackBb: 100, hero: HoleCards.parse(c), actions: [p(o, ActionType.raise, open)])).action != DecisionAction.fold);
      print('${st.name} BB defend total vs ${o.name} ${open}bb: ${def.toStringAsFixed(1)}%');
    }
    final sq = pct((c) => tree.decide(GameState(stake: st, heroPosition: Position.bb, effectiveStackBb: 100, hero: HoleCards.parse(c),
        actions: [p(Position.co, ActionType.raise, 2.5), p(Position.btn, ActionType.call, 2.5), p(Position.sb, ActionType.fold)])).action != DecisionAction.fold);
    print('${st.name} BB vs CO open + BTN call (squeeze node) continue: ${sq.toStringAsFixed(1)}%  (pot odds call 1.5 into 6.5 => 18.8%)');
    final isoFish = pct((c) => tree.decide(GameState(stake: st, heroPosition: Position.btn, hero: HoleCards.parse(c), villainProfile: VillainProfile.callingStation,
        actions: [p(Position.mp, ActionType.call, 1)])).action == DecisionAction.betRaise);
    final isoStd = pct((c) => tree.decide(GameState(stake: st, heroPosition: Position.btn, hero: HoleCards.parse(c),
        actions: [p(Position.mp, ActionType.call, 1)])).action == DecisionAction.betRaise);
    print('${st.name} BTN iso vs 1 limper: station ${isoFish.toStringAsFixed(1)}% | default ${isoStd.toStringAsFixed(1)}%');
  }
  // rake model check
  const e = PreflopSolverEngine();
  print('raked odds BB vs 2.5 BTN micro ${e.rakedPotOdds(1.5, 4.0, RakeTier.microHighRake).toStringAsFixed(4)} mid ${e.rakedPotOdds(1.5, 4.0, RakeTier.midRake).toStringAsFixed(4)} raw ${e.potOddsRequired(1.5, 4.0).toStringAsFixed(4)}');
  print('EQR 72o ${HandProps.eqr[Matrix169.indexOf('72o')].toStringAsFixed(2)} K5o ${HandProps.eqr[Matrix169.indexOf('K5o')].toStringAsFixed(2)} 54s ${HandProps.eqr[Matrix169.indexOf('54s')].toStringAsFixed(2)} AA ${HandProps.eqr[Matrix169.indexOf('AA')].toStringAsFixed(2)}');

  // Read collisions
  const post = PostflopHeuristicEngine();
  final trapper = GgProfiler.classify(const SmartHudInput(vpip: 45, pfr: 4, stackBb: 100), {ActionTag.limpReraisePreflop});
  final s = GameState(stake: Stake.nl10, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 95, potBb: 5.5,
      hero: HoleCards.parse('5h4d'), board: Card.parseMany('Kd8h3s'),
      actions: [p(Position.btn, ActionType.raise, 2.5), p(Position.bb, ActionType.call, 2.5)]);
  print('trapper->engineProfile=${trapper.engineProfile.name}; c-bet con aire vs trapper: ${post.decide(s, read: trapper).action.name}');
  // Pot donk vs reg
  final reg = const ReadProfile(GgArchetype.unknownReg, []);
  final d = GameState(stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 95, potBb: 5.5,
      hero: HoleCards.parse('QhQd'), board: Card.parseMany('Ts8c3d'),
      actions: [p(Position.btn, ActionType.raise, 2.5), p(Position.bb, ActionType.call, 2.5), const PlayerAction(Street.flop, Position.bb, ActionType.bet, 5)]);
  print('pot-donk 5bb/5.5 por REG desconocido NL50, QQ en T83r: ${post.decide(d, read: reg).action.name}');
  // insta-call + fish bluff
  final f = GgProfiler.classify(const SmartHudInput(vpip: 50, pfr: 5, threeBet: 1, stackBb: 100));
  final ic = GameState(stake: Stake.nl10, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 85, potBb: 17.1,
      hero: HoleCards.parse('AhQd'), board: Card.parseMany('Ts9s6dKh2c'),
      actions: [p(Position.btn, ActionType.raise, 2.5), p(Position.bb, ActionType.call, 2.5),
        const PlayerAction(Street.flop, Position.bb, ActionType.check), const PlayerAction(Street.flop, Position.btn, ActionType.bet, 1.8),
        const PlayerAction(Street.flop, Position.bb, ActionType.call, 1.8), const PlayerAction(Street.turn, Position.bb, ActionType.check),
        const PlayerAction(Street.turn, Position.btn, ActionType.bet, 4), const PlayerAction(Street.turn, Position.bb, ActionType.call, 4, TimingTell.instaAction),
        const PlayerAction(Street.river, Position.bb, ActionType.check)]);
  print('insta-call turn + brick vs FISH con A-high aire: ${post.decide(ic, read: f).action.name}');
  // set fold vs maniac XC XC jam on flush
  final m = GgProfiler.classify(const SmartHudInput(vpip: 45, pfr: 35, threeBet: 15, stackBb: 100));
  final setFold = GameState(stake: Stake.nl100, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 85, potBb: 21.5,
      hero: HoleCards.parse('3h3c'), board: Card.parseMany('Ts7s3d2c9s'),
      actions: [p(Position.btn, ActionType.raise, 2.5), p(Position.bb, ActionType.call, 2.5),
        const PlayerAction(Street.flop, Position.bb, ActionType.check), const PlayerAction(Street.flop, Position.btn, ActionType.bet, 2), const PlayerAction(Street.flop, Position.bb, ActionType.call, 2),
        const PlayerAction(Street.turn, Position.bb, ActionType.check), const PlayerAction(Street.turn, Position.btn, ActionType.bet, 6), const PlayerAction(Street.turn, Position.bb, ActionType.call, 6),
        const PlayerAction(Street.river, Position.bb, ActionType.bet, 10)]);
  final au = BluffCatchAuditor.audit(setFold, m, pot: 21.5, call: 10, heroHasNuts: false);
  print('Set 33 vs MANIAC NL100 donk 47% river (XC-XC): ${post.decide(setFold, read: m).action.name} | bluffs ${au.availableBluffs.toStringAsFixed(3)} potOdds ${au.potOddsReq.toStringAsFixed(3)}');
}
