import '../models/game_state.dart';
import 'range_notation.dart';

/// Topología asimétrica de stacks (priors del usuario, Fase 9.5): con stack efectivo 20-48bb se recorta el EQR de
/// pares bajos / suited connectors bajos (-50%, sin implícitas) y se bonifica el de broadways/pares altos (+25%).
class StackTopologyResolver {
  StackTopologyResolver._();

  static bool enabled = true; // interruptor de auditoría
  static const lo = 20.0, hi = 48.0;
  static const cut = 0.5, bonus = 1.25;
  static const behindStackBb = 100.0, behindMargin = 0.06;
  static final _small = RangeNotation.parse('22-66,54s,65s,76s,87s');
  static final _broad = RangeNotation.parse('88+,ATo+,KQo,A9s+,KTs+');

  static bool shortMid(double? stack) => enabled && stack != null && stack >= lo && stack <= hi;

  /// Multiplicador de EQR en la ventana corta; null => sin cambio (fuera de ventana o mano neutra).
  static double? eqrMultiplier(int i, double? stack) {
    if (!shortMid(stack)) return null;
    if (_small[i] > 0) return cut;
    if (_broad[i] > 0) return bonus;
    return null;
  }

  /// Amenaza de squeeze detrás: ciega (no Hero) que aún no actuó con stack >= 100bb.
  static bool behindSqueezeThreat(GameState s) {
    if (!enabled) return false;
    final acted = {for (final a in s.actions) if (a.street == Street.preflop) a.actor};
    for (final p in [Position.sb, Position.bb]) {
      if (p == s.heroPosition || acted.contains(p)) continue;
      if ((s.seatStacksBb[p] ?? 0) >= behindStackBb) return true;
    }
    return false;
  }
}
