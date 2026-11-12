import 'dart:math' as math;

/// Planificador geométrico de 2 calles (Turn -> River all-in): f = (sqrt(1 + 2*SPR) - 1) / 2, acotado a [55%, 95%].
class Geometric2EPlanner {
  Geometric2EPlanner._();

  static bool enabled = true; // interruptor de auditoría (Δ EV del módulo)
  static const minSpr = 1.6, maxSpr = 3.8, lo = 55.0, hi = 95.0;

  static double geoBetPct(double spr) => (math.sqrt(1 + 2 * spr) - 1) / 2 * 100;

  /// (sizing Turn % pot, shove River resultante % pot) o null fuera de la ventana de SPR.
  static (double, double)? plan(double pot, double stack) {
    if (!enabled || pot <= 0) return null;
    final spr = stack / pot;
    if (spr < minSpr || spr > maxSpr) return null;
    final f = geoBetPct(spr).clamp(lo, hi) / 100;
    final river = (spr - f) / (1 + 2 * f);
    return (f * 100, river * 100);
  }

  static String note(double sizePct, double riverPct) =>
      'Geo-2E Sizing (${sizePct.round()}% Pot) -> Prepara River All-In exacto de ${riverPct.round()}% Pot (+EV Max)';
}
