import 'cards.dart';
import 'decision_output.dart';

/// Mezclador determinista: roll 0..99 a partir de las cartas exactas (con palos), el board y el bote.
/// Misma situación => misma acción; combos isomorfos distintos => rolls distintos (mezcla real por combo).
class DeterministicActionMixer {
  DeterministicActionMixer._();

  static const order = [DecisionAction.betRaise, DecisionAction.call, DecisionAction.check, DecisionAction.fold];

  static int roll(List<Card> heroExact, List<Card> board, double potBb) {
    var h = 0x811C9DC5;
    void mix(int v) => h = ((h ^ v) * 0x01000193) & 0xFFFFFFFF;
    for (final c in heroExact) {
      mix(c.id + 1);
    }
    mix(0xFF);
    for (final c in board) {
      mix(c.id + 1);
    }
    final p = (potBb * 100).round();
    mix(p & 0xFF);
    mix((p >> 8) & 0xFF);
    mix((p >> 16) & 0xFF);
    h ^= h >> 15;
    h = (h * 0x2C1B3C6D) & 0xFFFFFFFF;
    h ^= h >> 12;
    return h % 100;
  }

  /// Normaliza [weights] (suma 1) y selecciona la acción cuyo tramo acumulado contiene el roll.
  static (DecisionAction, int, Map<DecisionAction, double>) select(
      List<Card> heroExact, List<Card> board, double potBb, Map<DecisionAction, double> weights) {
    final clean = {for (final e in weights.entries) if (e.value > 1e-9) e.key: e.value};
    final total = clean.values.fold<double>(0, (a, b) => a + b);
    final norm = total <= 0 ? {DecisionAction.fold: 1.0} : {for (final e in clean.entries) e.key: e.value / total};
    final r = roll(heroExact, board, potBb);
    var acc = 0.0;
    for (final a in order) {
      final w = norm[a];
      if (w == null) continue;
      acc += w * 100;
      if (r < acc - 1e-9) return (a, r, norm);
    }
    return (norm.keys.last, r, norm);
  }
}
