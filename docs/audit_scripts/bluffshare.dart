// ignore_for_file: avoid_print
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/postflop/hand_tier.dart';
import 'package:sol_ver/core/postflop/postflop_heuristic_engine.dart';
import 'package:sol_ver/core/postflop/defense_budget.dart';
import 'package:sol_ver/core/reads/gg_profiler.dart';

String cs(int id) => '${'23456789TJQKA'[id >> 2]}${'cdhs'[id & 3]}';
PlayerAction a(Street s, Position p, ActionType t, [double x = 0]) => PlayerAction(s, p, t, x);

void main() {
  const post = PostflopHeuristicEngine();
  final reads = {
    'scared': GgProfiler.classify(const SmartHudInput(vpip: 20, pfr: 17, threeBet: 4, stackBb: 100)),
    'unknown': GgProfiler.classify(const SmartHudInput(stackBb: 100)),
    'fish': GgProfiler.classify(const SmartHudInput(vpip: 50, pfr: 5, threeBet: 1, stackBb: 100)),
    'agro': GgProfiler.classify(const SmartHudInput(vpip: 40, pfr: 30, threeBet: 14, stackBb: 100)),
  };
  final b = Card.parseMany('Kd7s2s4h');
  for (final e in reads.entries) {
    double v = 0, bl = 0, tot = 0;
    String? reported;
    final g0 = GameState(stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 82.5, potBb: 35.5,
        hero: HoleCards.parse('QcJc'), board: b,
        actions: [const PlayerAction(Street.preflop, Position.btn, ActionType.raise, 2.5), const PlayerAction(Street.preflop, Position.bb, ActionType.call, 2.5),
          a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 15), a(Street.flop, Position.bb, ActionType.call, 15),
          a(Street.turn, Position.bb, ActionType.check)]);
    // Rango de llegada ponderado (misma base que el selector de faroles).
    final range = DefenseBudget.heroRangeAtStreet(g0, e.value);
    for (final en in range.entries) {
      final x = en.key ~/ 52, y = en.key % 52;
      tot += en.value;
      final d = post.decide(g0.copyWith(hero: HoleCards.parse(cs(x) + cs(y))), read: e.value);
      reported ??= d.metrics.where((m) => m.type == MetricType.bluffShare).map((m) => m.value.toStringAsFixed(3)).firstOrNull;
      if (d.action != DecisionAction.betRaise) continue;
      final t = HandTierClassifier.classify(x, y, [for (final c in b) c.id]).tier;
      if (t == HandTier.nutsMonster || t == HandTier.strongTopPairOverpair) {
        v += en.value;
      } else {
        bl += en.value;
      }
    }
    print('${e.key.padRight(8)} turn Kd7s2s-4h (rango de llegada ponderado): bet ${((v + bl) / tot * 100).toStringAsFixed(1)}% | bluff share EJECUTADO ${(bl / (v + bl) * 100).toStringAsFixed(1)}% vs REPORTADO $reported');
  }
}
