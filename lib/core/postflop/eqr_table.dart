import '../preflop/range_notation.dart';

enum EqrCategory { pocketPair, suitedAce, suitedBroadway, suitedConnector, suitedOther, offsuitBroadway, offsuitOther }

/// EQR(categoría, IP/OOP, SPR). Parámetros del modelo; anclas del usuario: SC IP SPR>6 ~0.95-1.05 (=> 1.00),
/// offsuit broadway OOP SPR bajo (3BP) ~0.65-0.72 (=> 0.68). Resto interpolado manteniendo el orden suited > offsuit, IP > OOP.
class EqrTable {
  EqrTable._();

  /// [categoría] -> (IP [low, mid, high], OOP [low, mid, high]); SPR low < 3, mid 3-6, high > 6.
  static const table = <EqrCategory, (List<double>, List<double>)>{
    EqrCategory.pocketPair: ([0.95, 1.00, 1.02], [0.85, 0.85, 0.82]),
    EqrCategory.suitedAce: ([0.95, 1.00, 1.05], [0.85, 0.88, 0.90]),
    EqrCategory.suitedBroadway: ([0.98, 1.00, 1.02], [0.82, 0.85, 0.86]),
    EqrCategory.suitedConnector: ([0.90, 0.97, 1.00], [0.75, 0.80, 0.85]),
    EqrCategory.suitedOther: ([0.85, 0.90, 0.92], [0.70, 0.74, 0.76]),
    EqrCategory.offsuitBroadway: ([0.90, 0.90, 0.88], [0.68, 0.72, 0.70]),
    EqrCategory.offsuitOther: ([0.80, 0.80, 0.78], [0.62, 0.62, 0.60]),
  };

  static EqrCategory categoryOf(int i) {
    final h = Matrix169.highRank(i), l = Matrix169.lowRank(i);
    if (Matrix169.isPair(i)) return EqrCategory.pocketPair;
    if (Matrix169.isSuited(i)) {
      if (h == 12) return EqrCategory.suitedAce;
      if (l >= 8) return EqrCategory.suitedBroadway;
      if (h - l <= 2) return EqrCategory.suitedConnector;
      return EqrCategory.suitedOther;
    }
    return l >= 8 ? EqrCategory.offsuitBroadway : EqrCategory.offsuitOther;
  }

  static int sprBucket(double spr) => spr < 3 ? 0 : (spr <= 6 ? 1 : 2);

  static double factor(int index169, {required bool ip, required double spr}) {
    final (ipRow, oopRow) = table[categoryOf(index169)]!;
    return (ip ? ipRow : oopRow)[sprBucket(spr)];
  }
}
