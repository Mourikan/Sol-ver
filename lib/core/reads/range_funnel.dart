import '../evaluators/board_analyzer.dart';
import '../models/game_state.dart';

enum VillainRangeState { uncapped, cappedMedium, cappedMediumShowdown, polarizedNutsOrAir, condensedDrawsAndPairs }

class FunnelResult {
  const FunnelResult(this.state, this.removed, this.trace);
  final VillainRangeState state;
  final List<String> removed;
  final List<String> trace;

  bool get isCapped => state == VillainRangeState.cappedMedium || state == VillainRangeState.cappedMediumShowdown;
}

/// Embudo de rango del villano calle por calle a partir de sus acciones.
class RangeFunnel {
  RangeFunnel._();

  static final _memo = <String, FunnelResult>{};

  /// Memo O(1): el embudo es determinista por (board, posiciones, tipo de bote, acciones).
  static FunnelResult track(GameState s) {
    final key = '${s.board.join()}|${s.heroPosition.index}|${s.villainPosition?.index}|${s.potType.index}|'
        '${s.actions.map((a) => '${a.street.index}${a.actor.index}${a.type.index}${a.amountBb}${a.timing.index}').join(',')}';
    final hit = _memo[key];
    if (hit != null) return hit;
    if (_memo.length > 512) _memo.clear();
    return _memo[key] = _track(s);
  }

  static FunnelResult _track(GameState s) {
    final villain = s.villainPosition!;
    final pfa = s.preflopAggressor;
    var state = VillainRangeState.uncapped;
    final removed = <String>[];
    final trace = <String>[];

    for (final street in [Street.flop, Street.turn, Street.river]) {
      if (street.index > s.street.index) break;
      final acts = s.actions.where((a) => a.street == street).toList();
      if (acts.isEmpty) continue;
      final boardLen = street == Street.flop ? 3 : (street == Street.turn ? 4 : 5);
      if (s.board.length < boardLen) break;
      final board = s.board.sublist(0, boardLen);
      final m = BoardAnalyzer.analyze(board.sublist(0, 3), pfa: pfa ?? villain, defender: villain);
      final dry = m.connectivity.index <= Connectivity.semiWet.index;

      final vActs = acts.where((a) => a.actor == villain).toList();
      final heroBet = acts.any((a) => a.actor != villain && a.isAggressive);
      final vChecked = vActs.isNotEmpty && vActs.first.type == ActionType.check;
      final vCalled = vActs.any((a) => a.type == ActionType.call);
      final vAgg = vActs.where((a) => a.isAggressive).toList();
      final current = street == s.street;

      if (vAgg.isNotEmpty) {
        final a = vAgg.last;
        final raise = vChecked && heroBet;
        final big = a.amountBb >= 0.75 * (s.potBb ?? a.amountBb);
        state = raise || big ? VillainRangeState.polarizedNutsOrAir : VillainRangeState.uncapped;
        trace.add('${street.name}: ${raise ? 'check-raise' : 'bet'} => ${state.name}');
      } else if (vChecked && vCalled) {
        if (dry) {
          state = VillainRangeState.cappedMedium;
          removed.addAll([..._sets(board.sublist(0, 3)), 'aire total']);
        } else {
          state = VillainRangeState.condensedDrawsAndPairs;
          removed.add('sets/2P fuertes (X/R por protección)');
        }
        trace.add('${street.name}: check-call => ${state.name}');
      } else if (vCalled) {
        state = dry ? VillainRangeState.cappedMedium : VillainRangeState.condensedDrawsAndPairs;
        trace.add('${street.name}: call => ${state.name}');
      } else if (vChecked && !current) {
        final wasPfaBehind = villain == pfa && villain.isInPositionVs(s.heroPosition);
        if (wasPfaBehind && street == Street.flop) {
          state = VillainRangeState.cappedMediumShowdown;
          removed.add('overpairs/sets/top-two (habrían c-beteado)');
          trace.add('flop: PFA check behind => cappedMediumShowdown');
        } else if (state == VillainRangeState.cappedMedium || state == VillainRangeState.condensedDrawsAndPairs) {
          trace.add('${street.name}: check tras X/C => se mantiene capado');
        } else if (state == VillainRangeState.uncapped) {
          state = VillainRangeState.cappedMedium;
          trace.add('${street.name}: check => cappedMedium');
        }
      } else if (vChecked && current) {
        trace.add('${street.name}: check (nodo actual)');
      }
    }
    return FunnelResult(state, removed, trace);
  }

  static List<String> _sets(List<Card> flop) {
    final ranks = {for (final c in flop) c.rank.symbol};
    return [for (final r in ranks) '$r$r'];
  }
}
