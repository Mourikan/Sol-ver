// ignore_for_file: avoid_print
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/preflop/preflop_solver_engine.dart';
import 'package:sol_ver/core/preflop/range_notation.dart';

void main() {
  const e = PreflopSolverEngine();
  String c(int x) => '${'23456789TJQKA'[x >> 2]}${'cdhs'[x & 3]}';
  for (final st in [Stake.nl10, Stake.nl100]) {
    for (final op in [Position.utg, Position.co, Position.btn, Position.sb]) {
      for (final size in [2.0, 2.5, 3.0]) {
        var call = 0, tb = 0;
        for (var i = 0; i < 169; i++) {
          final cc = Matrix169.concreteCombos(i).first;
          final d = e.decide(GameState(stake: st, heroPosition: Position.bb, effectiveStackBb: 100,
              hero: HoleCards.parse(c(cc.$1) + c(cc.$2)),
              actions: [PlayerAction(Street.preflop, op, ActionType.raise, size)]));
          if (d.action == DecisionAction.call) call += Matrix169.combos(i);
          if (d.action == DecisionAction.betRaise) tb += Matrix169.combos(i);
        }
        print('${st.name} BB vs ${op.name} ${size}bb: call ${(call / 13.26).toStringAsFixed(1)}% 3b ${(tb / 13.26).toStringAsFixed(1)}%');
      }
    }
  }
}
