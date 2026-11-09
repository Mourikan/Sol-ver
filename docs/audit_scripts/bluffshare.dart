// ignore_for_file: avoid_print
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/postflop/hand_tier.dart';
import 'package:sol_ver/core/postflop/postflop_heuristic_engine.dart';
import 'package:sol_ver/core/preflop/preflop_ranges_db.dart';
import 'package:sol_ver/core/preflop/range_notation.dart';
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
  final r = PreflopRangesDb.rfi(Position.btn, RakeTier.midRake).weights[PreflopAction.raise]!;
  final b = Card.parseMany('Kd7s2s4h');
  final dead = b.fold<int>(0, (m, c) => m | c.bit);
  for (final e in reads.entries) {
    double v = 0, bl = 0, tot = 0;
    String? reported;
    for (var i = 0; i < 169; i++) {
      if (r[i] <= 0) continue;
      for (final (x, y) in Matrix169.concreteCombos(i)) {
        if (dead & ((1 << x) | (1 << y)) != 0) continue;
        tot++;
        final s = GameState(stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 82.5, potBb: 35.5,
            hero: HoleCards.parse(cs(x) + cs(y)), board: b,
            actions: [const PlayerAction(Street.preflop, Position.btn, ActionType.raise, 2.5), const PlayerAction(Street.preflop, Position.bb, ActionType.call, 2.5),
              a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 15), a(Street.flop, Position.bb, ActionType.call, 15),
              a(Street.turn, Position.bb, ActionType.check)]);
        final d = post.decide(s, read: e.value);
        reported ??= d.metrics.where((m) => m.type == MetricType.bluffShare).map((m) => m.value.toStringAsFixed(3)).firstOrNull;
        if (d.action != DecisionAction.betRaise) continue;
        final t = HandTierClassifier.classify(x, y, [for (final c in b) c.id]).tier;
        if (t == HandTier.nutsMonster || t == HandTier.strongTopPairOverpair) {
          v++;
        } else {
          bl++;
        }
      }
    }
    print('${e.key.padRight(8)} turn Kd7s2s-4h (BTN RFI llega completo): bet ${((v + bl) / tot * 100).toStringAsFixed(1)}% | bluff share EJECUTADO ${(bl / (v + bl) * 100).toStringAsFixed(1)}% vs REPORTADO ${reported}');
  }
}
