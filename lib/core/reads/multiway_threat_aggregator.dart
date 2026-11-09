import 'dart:math' as math;

import '../models/game_state.dart';
import 'gg_profiler.dart';
import 'range_funnel.dart';

class MultiwayAssessment {
  const MultiwayAssessment({required this.mainThreat, required this.bluffFactor, required this.villains, required this.notes});
  final VillainSeatState mainThreat;

  /// Exploit_Bluff_Factor multiway = min(factor_i) x 0.5^(N-1); 0 si algún villano es Fish/Station/Trapper.
  final double bluffFactor;
  final List<VillainSeatState> villains;
  final List<String> notes;
  bool get bluffBlocked => bluffFactor <= 0;
}

/// Evalúa cada villano activo por separado y consolida (Bluff_Gate_Multiway + max_threat_funnel).
class MultiwayThreatAggregator {
  MultiwayThreatAggregator._();

  static double villainBluffFactor(VillainProfile vp) {
    final r = ReadProfile.fromVillainProfile(vp);
    return switch (r.archetype) {
      GgArchetype.recPassiveFish || GgArchetype.trapperLimpReraiser => 0.0,
      GgArchetype.agroSpewy => 0.5,
      _ => 1.0,
    };
  }

  static int _threat(VillainRangeState s) => switch (s) {
        VillainRangeState.polarizedNutsOrAir => 3,
        VillainRangeState.uncapped => 2,
        VillainRangeState.condensedDrawsAndPairs => 1,
        _ => 0,
      };

  static MultiwayAssessment assess(GameState s) {
    final vs = s.activeVillains;
    final n = vs.length;
    final factor = vs.map((v) => villainBluffFactor(v.profile)).reduce(math.min) * math.pow(0.5, n - 1);
    VillainSeatState best = vs.first;
    var bestScore = -1;
    final notes = <String>[];
    for (final v in vs) {
      final st = s.board.length >= 3 ? RangeFunnel.track(s.copyWith(villainPosition: v.position)).state : VillainRangeState.uncapped;
      final lastAgg = s.actions.lastWhere((a) => a.isAggressive, orElse: () => const PlayerAction(Street.preflop, Position.utg, ActionType.check)).actor == v.position;
      final score = _threat(st) * 2 + (lastAgg ? 1 : 0);
      notes.add('${v.position.name}: ${v.profile.name} / ${st.name}');
      if (score > bestScore) {
        bestScore = score;
        best = v;
      }
    }
    return MultiwayAssessment(mainThreat: best, bluffFactor: factor.toDouble(), villains: vs, notes: notes);
  }
}
