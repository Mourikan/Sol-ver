/// Priors MDA de consenso público (NL2-NL50), declarados por el usuario. Constantes explícitas, NO derivadas de solver
/// ni de una base de datos propia: se usan solo cuando el perfil es `poolDefault`.
class MDAParameters {
  MDAParameters._();

  /// El pool foldea de más vs double barrel en Turn: FE fija.
  static const turnOverfoldVsDoubleBarrel = 0.62;

  /// El pool paga de más vs sizings pequeños (< 33%) en River: FE = 1 - 0.85.
  static const riverCallEfficiencyVsSmallBet = 0.85;

  /// El pool sub-farolea raises de River (fracción de faroles faltantes respecto al GTO).
  static const riverRaiseBluffDeficit = 0.15;

  /// Las c-bets multiway del pool son desproporcionadamente fuertes: fracción de valor en su rango de c-bet.
  static const flopCbetHonestyMultiway = 0.70;

  static const smallBetMaxFraction = 0.33;
}
