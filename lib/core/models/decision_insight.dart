/// Radiografía del rango que el motor asigna al villano en el nodo actual (combos reales ponderados).
class VillainPerceivedRange {
  const VillainPerceivedRange({
    required this.totalActiveCombos,
    required this.isCapped,
    required this.nutsAndMonstersPct,
    required this.mediumShowdownPct,
    required this.drawsAndSemibluffsPct,
    required this.pureAirAndBluffsPct,
    required this.topRepresentativeHands,
    required this.predictedFoldFreq,
    required this.predictedBluffFreq,
    this.heroBlockedNutsCombos = 0,
    this.activePresets = const [],
    this.classWeights = const [],
  });

  static const empty = VillainPerceivedRange(
      totalActiveCombos: 0,
      isCapped: false,
      nutsAndMonstersPct: 0,
      mediumShowdownPct: 0,
      drawsAndSemibluffsPct: 0,
      pureAirAndBluffsPct: 0,
      topRepresentativeHands: [],
      predictedFoldFreq: 0,
      predictedBluffFreq: 0);

  final int totalActiveCombos;
  final bool isCapped;
  final double nutsAndMonstersPct, mediumShowdownPct, drawsAndSemibluffsPct, pureAirAndBluffsPct;
  final List<String> topRepresentativeHands;
  final double predictedFoldFreq, predictedBluffFreq;

  /// Combos de nuts/monsters del villano eliminados por las cartas de Hero (blocker).
  final double heroBlockedNutsCombos;

  /// Presets de lectura sin HUD activos (Equilibrium_Deviation_Read).
  final List<String> activePresets;

  /// Peso relativo (0..1, normalizado al máximo) de cada una de las 169 clases que sobreviven en el nodo (índice Matrix169).
  final List<double> classWeights;

  Map<String, Object> toJson() => {
        'totalActiveCombos': totalActiveCombos,
        'isCapped': isCapped,
        'Morphology_Buckets': {
          'nutsAndMonstersPct': nutsAndMonstersPct,
          'mediumShowdownPct': mediumShowdownPct,
          'drawsAndSemibluffsPct': drawsAndSemibluffsPct,
          'pureAirAndBluffsPct': pureAirAndBluffsPct,
        },
        'topRepresentativeHands': topRepresentativeHands,
        'predictedFoldFreq': predictedFoldFreq,
        'predictedBluffFreq': predictedBluffFreq,
        'heroBlockedNutsCombos': heroBlockedNutsCombos,
        'activePresets': activePresets,
      };
}

/// Qué lee el motor y por qué la acción maximiza EV (determinista, 1 línea por campo).
class DecisionJustification {
  const DecisionJustification({
    required this.activeReadBadge,
    required this.mathRationale,
    required this.activeCloserRule,
    this.villainReadExplanation = '',
    this.evWhyExplanation = '',
    this.nextStreetPlan = '',
  });
  final String activeReadBadge, mathRationale, activeCloserRule;

  /// ProCoachNarrativeBuilder: ¿qué tiene el rival y por qué? / ¿por qué esta acción gana más? / plan siguiente calle.
  final String villainReadExplanation, evWhyExplanation, nextStreetPlan;

  Map<String, String> toJson() => {
        'activeReadBadge': activeReadBadge,
        'mathRationale': mathRationale,
        'activeCloserRule': activeCloserRule,
        'villainReadExplanation': villainReadExplanation,
        'evWhyExplanation': evWhyExplanation,
        'nextStreetPlan': nextStreetPlan,
      };
}

/// Pronóstico de la siguiente calle (13 rangos x {brick offsuit, carta que completa color}).
class RunoutForecast {
  const RunoutForecast({required this.barrelKillCards, required this.potControlCards, required this.abortDangerCards});
  final List<String> barrelKillCards, potControlCards, abortDangerCards;

  Map<String, List<String>> toJson() => {'barrelKill': barrelKillCards, 'potControl': potControlCards, 'abortDanger': abortDangerCards};
}
