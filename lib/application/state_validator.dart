import '../core/models/game_state.dart';

class ValidationIssue {
  const ValidationIssue(this.field, this.message);
  final String field;
  final String message;
  @override
  String toString() => '$field: $message';
}

/// Validación estricta de entrada antes de tocar los motores.
class StateValidator {
  StateValidator._();

  static List<ValidationIssue> validate(GameState s) {
    final out = <ValidationIssue>[];
    if (s.hero == null) out.add(const ValidationIssue('hero', 'Cartas de Hero obligatorias'));
    if (s.villainPosition != null && s.villainPosition == s.heroPosition) {
      out.add(const ValidationIssue('villainPosition', 'Hero y villano no pueden compartir posición'));
    }
    if (s.effectiveStackBb != null && s.effectiveStackBb! <= 0) out.add(const ValidationIssue('effectiveStackBb', 'Debe ser > 0'));
    if (s.potBb != null && s.potBb! <= 0) out.add(const ValidationIssue('potBb', 'Debe ser > 0'));
    if (s.activePlayers < 2 || s.activePlayers > 6) out.add(const ValidationIssue('activePlayers', 'Rango 2-6'));
    for (final st in Street.values) {
      var last = 0.0;
      for (final a in s.actions.where((a) => a.street == st)) {
        if (a.amountBb < 0) out.add(ValidationIssue('actions', 'Monto negativo en ${st.name}'));
        if (a.isAggressive) {
          if (a.amountBb <= last && a.type != ActionType.allIn) {
            out.add(ValidationIssue('actions', 'Raise no creciente en ${st.name} (${a.amountBb} <= $last)'));
          }
          last = a.amountBb;
        }
      }
      if (st.index > s.street.index && s.actions.any((a) => a.street == st)) {
        out.add(ValidationIssue('actions', 'Acciones en ${st.name} sin cartas de esa calle'));
      }
    }
    if (s.street != Street.preflop) {
      out.addAll([for (final f in s.missingForPostflop()) ValidationIssue(f, 'Obligatorio postflop')]);
    }
    return out;
  }
}
