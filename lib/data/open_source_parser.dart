import 'dart:convert';
import 'dart:typed_data';

import '../core/preflop/hand_normalizer.dart';
import '../core/preflop/preflop_ranges_db.dart';
import '../core/preflop/range_notation.dart';

/// Tabla preflop de baja resolución (TexasSolver / transcripción manual) ya completada a 169 manos.
class BootstrapTable {
  BootstrapTable(this.raise, this.call, this.interpolated, this.meta);
  final Float32List raise;
  final Float32List call;

  /// Índices 169 rellenados por el Zero-Hole Fallback (no presentes en el JSON).
  final Set<int> interpolated;
  final Map<String, Object?> meta;

  Float32List get fold {
    final f = Float32List(169);
    for (var i = 0; i < 169; i++) {
      f[i] = (1 - raise[i] - call[i]).clamp(0.0, 1.0);
    }
    return f;
  }

  RangeNode toRangeNode(String id) => RangeNode.fromWeights(
        id,
        {PreflopAction.raise: raise, if (call.any((x) => x > 0)) PreflopAction.call: call},
        source: RangeSource.bootstrapGTO,
      );
}

/// Ingesta de JSON comprimido `{"combo": "A5s", "rfi": 80, "fold": 20}` (lista, o `{"combos": [...]}`).
/// Acepta clases 169 (`A5s`, `AKo`, `77`) o combos exactos (`AhKh`, promediados por clase); porcentajes 0-100 o 0-1.
class BootstrapDataParser {
  BootstrapDataParser._();

  static const raiseKeys = {'rfi', 'raise', 'bet', '3bet', '4bet', 'open'};
  static const callKeys = {'call', 'limp', 'flat'};

  /// Tabla de equity usada para el suavizado (equity vs rango top).
  static const smoothingEquityKey = 'MR_RFI_utg';

  static BootstrapTable parse(String json) {
    final decoded = jsonDecode(json);
    final list = decoded is List ? decoded : (decoded as Map)['combos'] as List;
    final meta = decoded is Map ? (Map<String, Object?>.from(decoded)..remove('combos')) : <String, Object?>{};
    final sumR = Float64List(169), sumC = Float64List(169), n = Float64List(169);
    for (final raw in list) {
      final e = raw as Map;
      final label = e['combo'] as String;
      final idx = _index(label);
      var r = 0.0, c = 0.0;
      for (final kv in e.entries) {
        final k = (kv.key as String).toLowerCase();
        if (kv.value is! num) continue;
        final v = (kv.value as num).toDouble();
        if (raiseKeys.contains(k)) r += v;
        if (callKeys.contains(k)) c += v;
      }
      final scale = (r > 1 || c > 1 || (e['fold'] is num && (e['fold'] as num) > 1)) ? 100.0 : 1.0;
      sumR[idx] += r / scale;
      sumC[idx] += c / scale;
      n[idx] += 1;
    }
    final raise = Float32List(169), call = Float32List(169);
    final known = <int>[];
    for (var i = 0; i < 169; i++) {
      if (n[i] == 0) continue;
      raise[i] = (sumR[i] / n[i]).clamp(0.0, 1.0);
      call[i] = (sumC[i] / n[i]).clamp(0.0, 1.0 - raise[i]);
      known.add(i);
    }
    final missing = {for (var i = 0; i < 169; i++) if (n[i] == 0) i};
    _zeroHoleFallback(raise, call, known, missing);
    return BootstrapTable(raise, call, missing, meta);
  }

  static int _index(String label) {
    final t = label.trim();
    if (t.length == 4 && RegExp(r'^[2-9TJQKA][cdhs][2-9TJQKA][cdhs]$', caseSensitive: false).hasMatch(t)) {
      return HandNormalizer.parse(t).index;
    }
    return Matrix169.indexOf(t.toUpperCase().replaceAll('S', 's').replaceAll('O', 'o'));
  }

  /// Zero-Hole Fallback: interpola linealmente la frecuencia de cada mano faltante en función de su equity cruda
  /// entre la mano conocida inmediatamente inferior y superior en equity (suavizado monotónico por equity).
  static void _zeroHoleFallback(Float32List raise, Float32List call, List<int> known, Set<int> missing) {
    if (known.isEmpty) return;
    double eq(int i) => HandProps.equity(smoothingEquityKey, i)!;
    final pts = [...known]..sort((a, b) => eq(a).compareTo(eq(b)));
    for (final i in missing) {
      final e = eq(i);
      int? lo, hi;
      for (final k in pts) {
        if (eq(k) <= e) {
          lo = k;
        } else {
          hi = k;
          break;
        }
      }
      double interp(Float32List f) {
        if (lo == null) return f[hi!];
        if (hi == null) return f[lo];
        final span = eq(hi) - eq(lo);
        final t = span <= 0 ? 0.5 : (e - eq(lo)) / span;
        return f[lo] + (f[hi] - f[lo]) * t;
      }
      raise[i] = interp(raise).clamp(0.0, 1.0);
      call[i] = interp(call).clamp(0.0, 1.0 - raise[i]);
    }
  }
}
