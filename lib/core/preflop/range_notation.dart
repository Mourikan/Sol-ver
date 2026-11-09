import 'dart:typed_data';

import '../models/cards.dart';

/// Utilidades de la matriz 13x13 (índice 0 = AA, fila/col 0 = A; suited sobre diagonal).
class Matrix169 {
  Matrix169._();

  static const _symbols = 'AKQJT98765432';

  static int index(int highRow, int lowRow, {required bool suited}) {
    if (highRow == lowRow) return highRow * 13 + highRow;
    return suited ? highRow * 13 + lowRow : lowRow * 13 + highRow;
  }

  static int row(Rank r) => 12 - r.index;

  static String label(int i) {
    final r = i ~/ 13, c = i % 13;
    if (r == c) return '${_symbols[r]}${_symbols[r]}';
    return c > r ? '${_symbols[r]}${_symbols[c]}s' : '${_symbols[c]}${_symbols[r]}o';
  }

  static int indexOf(String label) {
    final h = _symbols.indexOf(label[0]), l = _symbols.indexOf(label[1]);
    if (h < 0 || l < 0) throw FormatException('Mano inválida: $label');
    if (h == l) return h * 13 + h;
    final hi = h < l ? h : l, lo = h < l ? l : h;
    return index(hi, lo, suited: label.length > 2 && label[2] == 's');
  }

  static bool isPair(int i) => i ~/ 13 == i % 13;
  static bool isSuited(int i) => i % 13 > i ~/ 13;
  static int combos(int i) => isPair(i) ? 6 : (isSuited(i) ? 4 : 12);

  /// Rank (0 = deuce .. 12 = A) de la carta alta / baja.
  static int highRank(int i) => 12 - (isSuited(i) || isPair(i) ? i ~/ 13 : i % 13);
  static int lowRank(int i) => 12 - (isSuited(i) || isPair(i) ? i % 13 : i ~/ 13);

  static double percent(Float32List w) {
    var s = 0.0;
    for (var i = 0; i < 169; i++) {
      s += w[i] * combos(i);
    }
    return s / 1326 * 100;
  }

  /// Combos concretos (c1, c2) con cartas como rank*4+suit.
  static List<(int, int)> concreteCombos(int i) {
    final h = highRank(i), l = lowRank(i);
    final out = <(int, int)>[];
    if (h == l) {
      for (var a = 0; a < 4; a++) {
        for (var b = a + 1; b < 4; b++) {
          out.add((h * 4 + a, h * 4 + b));
        }
      }
    } else if (isSuited(i)) {
      for (var s = 0; s < 4; s++) {
        out.add((h * 4 + s, l * 4 + s));
      }
    } else {
      for (var a = 0; a < 4; a++) {
        for (var b = 0; b < 4; b++) {
          if (a != b) out.add((h * 4 + a, l * 4 + b));
        }
      }
    }
    return out;
  }
}

/// Parser de notación compacta: `22+, A2s+, K9s+, ATo+, 77-TT, A5s-A2s, AK, QJs:0.5`.
class RangeNotation {
  RangeNotation._();

  static const _s = 'AKQJT98765432';

  static Float32List parse(String notation) {
    final w = Float32List(169);
    for (var raw in notation.split(',')) {
      raw = raw.trim();
      if (raw.isEmpty) continue;
      var freq = 1.0;
      final colon = raw.indexOf(':');
      if (colon > 0) {
        freq = double.parse(raw.substring(colon + 1));
        raw = raw.substring(0, colon);
      }
      for (final i in _expand(raw)) {
        w[i] = freq;
      }
    }
    return w;
  }

  static Float32List union(Iterable<String> parts) => parse(parts.where((p) => p.isNotEmpty).join(','));

  static Iterable<int> _expand(String t) sync* {
    if (t.contains('-')) {
      final p = t.split('-');
      final a = _parseToken(p[0]), b = _parseToken(p[1]);
      if (a.$1 == a.$2) {
        final lo = a.$1 < b.$1 ? a.$1 : b.$1, hi = a.$1 < b.$1 ? b.$1 : a.$1;
        for (var r = lo; r <= hi; r++) {
          yield Matrix169.index(r, r, suited: false);
        }
      } else {
        if (a.$1 != b.$1) throw FormatException('Rango inválido: $t');
        final lo = a.$2 < b.$2 ? a.$2 : b.$2, hi = a.$2 < b.$2 ? b.$2 : a.$2;
        for (var c = lo; c <= hi; c++) {
          yield* _cells(a.$1, c, a.$3);
        }
      }
      return;
    }
    final plus = t.endsWith('+');
    final tok = _parseToken(plus ? t.substring(0, t.length - 1) : t);
    if (tok.$1 == tok.$2) {
      final end = plus ? 0 : tok.$1;
      for (var r = tok.$1; r >= end; r--) {
        yield Matrix169.index(r, r, suited: false);
      }
    } else if (plus) {
      for (var c = tok.$2; c > tok.$1; c--) {
        yield* _cells(tok.$1, c, tok.$3);
      }
    } else {
      yield* _cells(tok.$1, tok.$2, tok.$3);
    }
  }

  static Iterable<int> _cells(int hi, int lo, String kind) sync* {
    if (kind != 'o') yield Matrix169.index(hi, lo, suited: true);
    if (kind != 's') yield Matrix169.index(hi, lo, suited: false);
  }

  /// (filaAlta, filaBaja, tipo) con fila 0 = A; tipo 's' | 'o' | '' (ambos).
  static (int, int, String) _parseToken(String t) {
    if (t.length < 2) throw FormatException('Token inválido: $t');
    final a = _s.indexOf(t[0].toUpperCase()), b = _s.indexOf(t[1].toUpperCase());
    if (a < 0 || b < 0) throw FormatException('Token inválido: $t');
    final kind = t.length > 2 ? t[2].toLowerCase() : '';
    return (a < b ? a : b, a < b ? b : a, kind);
  }
}
