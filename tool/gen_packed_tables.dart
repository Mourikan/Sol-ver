// Genera lib/data/generated/packed_tables.g.dart (tablas constantes O(1)). Uso: dart run tool/gen_packed_tables.dart
import 'dart:io';

import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/postflop/flop_lookup_table.dart';
import 'package:sol_ver/core/postflop/postflop_ranges.dart';
import 'package:sol_ver/core/preflop/preflop_ranges_db.dart';
import 'package:sol_ver/data/packed_layout.dart';

void main() {
  final pre = List<int>.filled(PackedLayout.preflopBytes, 0);
  void put(RakeTier t, int node, int plane, List<double> w) {
    for (var i = 0; i < 169; i++) {
      pre[PackedLayout.offset(t, node, plane, i)] = (w[i].clamp(0, 1) * 255).round();
    }
  }

  for (final t in PackedLayout.tiers) {
    for (final p in PackedLayout.rfiPositions) {
      put(t, PackedLayout.rfiNode(p), 0, PreflopRangesDb.rfi(p, t).weights[PreflopAction.raise]!);
    }
    for (final (h, o) in PackedLayout.vsRfiPairs) {
      final n = PreflopRangesDb.vsRfi(h, o, t);
      put(t, PackedLayout.vsRfiNode(h, o), 0, n.weights[PreflopAction.raise]!);
      final call = h == Position.bb ? PostflopRanges.defendVsOpen(h, o, t) : n.weights[PreflopAction.call];
      if (call != null) put(t, PackedLayout.vsRfiNode(h, o), 1, call);
    }
    for (final (h, ip) in PackedLayout.vs3BetKeys) {
      final n = PreflopRangesDb.vs3Bet(h, heroInPosition: ip);
      put(t, PackedLayout.vs3BetNode(h, ip), 0, n.weights[PreflopAction.raise]!);
      put(t, PackedLayout.vs3BetNode(h, ip), 1, n.weights[PreflopAction.call]!);
    }
  }

  final flop = List<int>.filled(PackedLayout.flopBytes, PackedLayout.invalid);
  for (var r1 = 0; r1 < 13; r1++) {
    for (var r2 = 0; r2 <= r1; r2++) {
      for (var r3 = 0; r3 <= r2; r3++) {
        final distinct = {r1, r2, r3}.length;
        for (var sp = 0; sp < 3; sp++) {
          final List<int> suits;
          if (sp == 0) {
            suits = [0, 1, 2];
          } else if (sp == 1) {
            suits = r1 == r2 ? [0, 1, 0] : [0, 0, 1];
          } else {
            if (distinct < 3) continue;
            suits = [0, 0, 0];
          }
          if (distinct == 1 && sp != 0) continue;
          final cards = [
            Card(Rank.values[r1], Suit.values[suits[0]]),
            Card(Rank.values[r2], Suit.values[suits[1]]),
            Card(Rank.values[r3], Suit.values[suits[2]]),
          ];
          if (cards.toSet().length < 3) continue;
          flop[PackedLayout.flopIndex(r1, r2, r3, sp)] = FlopLookupTable.bucketOf(cards).index;
        }
      }
    }
  }

  final out = StringBuffer()
    ..writeln('// GENERADO por tool/gen_packed_tables.dart. No editar.')
    ..writeln('// ignore_for_file: lines_longer_than_80_chars')
    ..writeln('const List<int> packedPreflop = [${pre.join(',')}];')
    ..writeln('const List<int> packedFlopBuckets = [${flop.join(',')}];');
  File('lib/data/generated/packed_tables.g.dart').writeAsStringSync(out.toString());
  stdout.writeln('preflop ${pre.length} bytes, flop ${flop.length} bytes');
}
