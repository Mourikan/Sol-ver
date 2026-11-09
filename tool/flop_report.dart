// ignore_for_file: avoid_print
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/postflop/flop_lookup_table.dart';
import 'package:sol_ver/core/postflop/postflop_ranges.dart';

void main() {
  final cases = [
    ('7s6s5d', Position.utg, Position.btn, HuNode.srpOop),
    ('As7d2c', Position.btn, Position.bb, HuNode.srpIp),
    ('6d5c4h', Position.btn, Position.bb, HuNode.srpIp),
    ('AsKd2c', Position.btn, Position.bb, HuNode.srpIp),
    ('QhJh8d', Position.btn, Position.bb, HuNode.srpIp),
    ('8h8d6c', Position.btn, Position.bb, HuNode.srpIp),
  ];
  for (final (b, pfa, d, n) in cases) {
    final (p, def) = PostflopRanges.forPot(pfa, d, PotType.srp, RakeTier.midRake);
    final r = FlopLookupTable.evaluate(Card.parseMany(b), n, pfaRange: p, defenderRange: def);
    print('$b ${r.bucket.name} ${r.strategy.name} bet ${(r.betFreq * 100).toStringAsFixed(1)}% donk ${(r.donkFreq * 100).toStringAsFixed(1)}% '
        '${r.tierShare.map((k, v) => MapEntry(k.name.substring(0, 6), (v * 100).round()))}');
  }
}
