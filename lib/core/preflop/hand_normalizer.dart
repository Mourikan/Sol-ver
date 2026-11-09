import 'dart:typed_data';

import '../models/cards.dart';
import 'data/hand_equity.g.dart';
import 'preflop_ranges_db.dart';
import 'range_notation.dart';

class CanonicalHand {
  const CanonicalHand._(this.index, this.cards);

  final int index;

  /// Cartas exactas retenidas para blockers postflop.
  final HoleCards cards;

  String get label => Matrix169.label(index);
  bool get isPair => Matrix169.isPair(index);
  bool get isSuited => Matrix169.isSuited(index);
  int get combos => Matrix169.combos(index);

  /// Equity vs el rango RFI más tight (UTG, tier Mid): referencia "top range".
  double get rawEquityVsTopRange => HandProps.equity('MR_RFI_utg', index)!;
  double get eqr => HandProps.eqr[index];
  double get blockerWeight => HandProps.blockerWeight[index];
}

class HandNormalizer {
  HandNormalizer._();

  static CanonicalHand normalize(HoleCards h) => CanonicalHand._(h.index169, h);
  static CanonicalHand parse(String cards) => normalize(HoleCards.parse(cards));
}

/// Propiedades intrínsecas por mano (tablas de 169, O(1)).
class HandProps {
  HandProps._();

  static double? equity(String refKey, int index) {
    final row = handEquityPermil[refKey];
    return row == null ? null : row[index] / 1000;
  }

  static final Float32List eqr = _buildEqr();
  static final Float32List blockerWeight = _buildBlockers();

  /// Pendiente equity->EQR: manos débiles sub-realizan, fuertes sobre-realizan.
  static const strengthSlope = 1.0;

  /// Modelo estructural de realización (parámetros explícitos, no frecuencias de solver):
  /// suited y conectividad retienen equity en varias calles; offsuit dominadas la pierden.
  static Float32List _buildEqr() {
    final out = Float32List(169);
    for (var i = 0; i < 169; i++) {
      final h = Matrix169.highRank(i), l = Matrix169.lowRank(i);
      double e;
      if (h == l) {
        e = h >= 9 ? 1.0 : (h >= 5 ? 0.95 : 0.90);
      } else {
        e = 0.88;
        final gap = h - l - 1;
        final suited = Matrix169.isSuited(i);
        if (suited) e += 0.07;
        e += switch (gap) { 0 => 0.04, 1 => 0.02, 2 => 0.0, _ => -0.03 };
        if (h == 12 && l <= 3 && suited) e += 0.06;
        if (l >= 8) e += 0.02;
        if (!suited) {
          if (h == 12 && l <= 7) e -= 0.05;
          if (h < 12 && h >= 8 && gap >= 1 && l < 10) e -= 0.06;
        }
      }
      final topEq = handEquityPermil['MR_RFI_utg']![i] / 1000;
      e += strengthSlope * (topEq - 0.35);
      out[i] = e.clamp(0.55, 1.10);
    }
    return out;
  }

  /// Fracción media de combos del rango de referencia (QQ+, AK) eliminados por la mano.
  static Float32List _buildBlockers() {
    final ref = RangeNotation.parse(PreflopRangesDb.blockerReference);
    final refCombos = <(int, int)>[
      for (var i = 0; i < 169; i++)
        if (ref[i] > 0) ...Matrix169.concreteCombos(i),
    ];
    final out = Float32List(169);
    for (var i = 0; i < 169; i++) {
      final mine = Matrix169.concreteCombos(i);
      var blocked = 0;
      for (final m in mine) {
        final mask = (1 << m.$1) | (1 << m.$2);
        for (final r in refCombos) {
          if (mask & ((1 << r.$1) | (1 << r.$2)) != 0) blocked++;
        }
      }
      out[i] = blocked / (mine.length * refCombos.length);
    }
    return out;
  }
}
