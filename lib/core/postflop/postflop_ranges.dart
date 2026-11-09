import 'dart:typed_data';

import '../models/decision_output.dart';
import '../models/game_state.dart';
import '../preflop/preflop_ranges_db.dart';
import '../preflop/preflop_solver_engine.dart';
import '../preflop/range_notation.dart';

/// Rangos de llegada al flop HU derivados del árbol preflop (mismas tablas que el motor preflop).
class PostflopRanges {
  PostflopRanges._();

  static final _cache = <String, Float32List>{};

  static Float32List defendVsOpen(Position defender, Position opener, RakeTier tier) {
    if (defender != Position.bb) {
      final c = PreflopRangesDb.vsRfi(defender, opener, tier).weights[PreflopAction.call];
      if (c != null && Matrix169.percent(c) > 0) return c;
      final mid = PreflopRangesDb.vsRfi(defender, opener, RakeTier.midRake).weights[PreflopAction.call];
      if (mid != null && Matrix169.percent(mid) > 0) return mid;
    }
    return _cache.putIfAbsent('BBDEF_${opener.name}_${tier.name}', () {
      const e = PreflopSolverEngine();
      final out = Float32List(169);
      final stake = tier == RakeTier.microHighRake ? Stake.nl10 : Stake.nl100;
      for (var i = 0; i < 169; i++) {
        final (a, b) = Matrix169.concreteCombos(i).first;
        final d = e.decide(GameState(
          stake: stake,
          heroPosition: Position.bb,
          effectiveStackBb: 100,
          hero: HoleCards(_card(a), _card(b)),
          actions: [PlayerAction(Street.preflop, opener, ActionType.raise, PreflopRangesDb.openSizeBb[opener]!)],
        ));
        if (d.action == DecisionAction.call) out[i] = 1;
      }
      return out;
    });
  }

  /// (rango PFA, rango defensor) para el bote HU.
  static (Float32List, Float32List) forPot(Position pfa, Position defender, PotType potType, RakeTier tier) {
    if (potType == PotType.threeBet || potType == PotType.fourBetPlus) {
      final opener = defender, threeBettor = pfa;
      final tb = threeBettor.index > opener.index
          ? PreflopRangesDb.vsRfi(threeBettor, opener, tier).weights[PreflopAction.raise]!
          : RangeNotation.parse(PreflopRangesDb.threeBetValue[opener] ?? 'QQ+,AKs,AKo');
      final call = PreflopRangesDb.vs3Bet(opener, heroInPosition: opener.isInPositionVs(threeBettor))
          .weights[PreflopAction.call]!;
      return (tb, call);
    }
    return (
      PreflopRangesDb.rfi(pfa, tier).weights[PreflopAction.raise]!,
      defendVsOpen(defender, pfa, tier),
    );
  }

  static Card _card(int id) => Card(Rank.values[id >> 2], Suit.values[id & 3]);
}
