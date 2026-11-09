import 'dart:math' as math;

class PotGeometry {
  PotGeometry._();

  static double spr(double stack, double pot) => stack / pot;
  static double mdf(double pot, double bet) => pot / (pot + bet);
  static double alpha(double pot, double bet) => bet / (pot + bet);
  static double potOdds(double call, double potIncludingBet) => call / (potIncludingBet + call);

  /// Fracción de bote f tal que apostar f*bote en n calles mete el stack: P(1+2f)^n = P + 2S.
  static double geometricFraction(double pot, double stack, int streets) {
    if (streets <= 0 || stack <= 0) return 0;
    return (math.pow(1 + 2 * stack / pot, 1 / streets) - 1) / 2;
  }
}
