import 'dart:typed_data';

import '../core/models/game_state.dart';
import '../core/postflop/flop_lookup_table.dart';
import '../core/preflop/preflop_ranges_db.dart';
import 'open_source_parser.dart';
import 'generated/packed_tables.g.dart';
import 'packed_layout.dart';

enum PackedAction { raise, call }

/// Tablas preflop (169 x nodos x tier) y buckets de flop empaquetadas en Uint8List. Cero I/O durante la mano.
class PackedLookupRepository {
  PackedLookupRepository._(this._preflop, this._flop, [Map<int, RangeSource>? sources]) : _sources = sources ?? const {};

  static PackedLookupRepository? _instance;
  static PackedLookupRepository get instance => _instance ??= load();

  /// Cold start: copia las constantes compiladas a memoria contigua.
  static PackedLookupRepository load() =>
      PackedLookupRepository._(Uint8List.fromList(packedPreflop), Uint8List.fromList(packedFlopBuckets));

  final Uint8List _preflop;
  final Uint8List _flop;
  final Map<int, RangeSource> _sources;

  /// Origen del nodo empaquetado (calibratedHeuristicBase por defecto; bootstrapGTO si se compiló desde JSON open-source).
  RangeSource sourceOf(RakeTier t, int node) => _sources[t.index * PackedLayout.nodesPerTier + node] ?? RangeSource.calibratedHeuristicBase;

  static int _q(double w) => (w.clamp(0.0, 1.0) * 255).round();

  /// Compila tablas bootstrap (RFI por posición/tier) a la memoria Uint8List O(1), marcando su origen.
  PackedLookupRepository withBootstrapRfi(Map<(RakeTier, Position), BootstrapTable> tables) {
    final bytes = Uint8List.fromList(_preflop);
    final src = Map<int, RangeSource>.from(_sources);
    for (final e in tables.entries) {
      final (tier, pos) = e.key;
      final node = PackedLayout.rfiNode(pos);
      for (var i = 0; i < 169; i++) {
        bytes[PackedLayout.offset(tier, node, PackedAction.raise.index, i)] = _q(e.value.raise[i]);
        bytes[PackedLayout.offset(tier, node, PackedAction.call.index, i)] = _q(e.value.call[i]);
      }
      src[tier.index * PackedLayout.nodesPerTier + node] = RangeSource.bootstrapGTO;
    }
    return PackedLookupRepository._(bytes, _flop, src);
  }

  int get bytes => _preflop.lengthInBytes + _flop.lengthInBytes;

  double _w(RakeTier t, int node, PackedAction a, int hand) =>
      _preflop[PackedLayout.offset(t, node, a.index, hand)] / 255;

  double rfi(Position p, RakeTier t, int hand) => _w(t, PackedLayout.rfiNode(p), PackedAction.raise, hand);

  double vsRfi(Position hero, Position opener, RakeTier t, PackedAction a, int hand) =>
      _w(t, PackedLayout.vsRfiNode(hero, opener), a, hand);

  double vs3Bet(Position hero, {required bool ip, required RakeTier tier, required PackedAction action, required int hand}) =>
      _w(tier, PackedLayout.vs3BetNode(hero, ip), action, hand);

  /// Bucket de flop en O(1) (rangos ordenados + patrón de palos).
  FlopBucket flopBucket(List<Card> flop) {
    final r = [for (final c in flop) c.rank.index]..sort((a, b) => b - a);
    final s = <int>{for (final c in flop) c.suit.index}.length;
    final pattern = s == 3 ? 0 : (s == 2 ? 1 : 2);
    final v = _flop[PackedLayout.flopIndex(r[0], r[1], r[2], pattern)];
    if (v == PackedLayout.invalid) throw ArgumentError('Flop inválido: $flop');
    return FlopBucket.values[v];
  }

  NodeStrategy flopStrategy(List<Card> flop, HuNode node) => FlopLookupTable.strategy(flopBucket(flop), node);
}
