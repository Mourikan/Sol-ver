// ignore_for_file: avoid_print
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/preflop/preflop_ranges_db.dart';

void main() {
  for (final t in RakeTier.values) {
    for (final p in [Position.utg, Position.mp, Position.co, Position.btn, Position.sb]) {
      print('${t.name} RFI ${p.name}: ${PreflopRangesDb.rfi(p, t).percent(PreflopAction.raise).toStringAsFixed(1)}%');
    }
    for (final h in Position.values) {
      for (final o in Position.values) {
        if (h.index <= o.index || o == Position.bb) continue;
        final n = PreflopRangesDb.vsRfi(h, o, t);
        print('${t.name} ${h.name} vs ${o.name}: 3b ${n.percent(PreflopAction.raise).toStringAsFixed(1)}% call ${n.percent(PreflopAction.call).toStringAsFixed(1)}%');
      }
    }
  }
}
