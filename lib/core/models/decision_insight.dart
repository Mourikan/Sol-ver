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
  const DecisionJustification({required this.activeReadBadge, required this.mathRationale, required this.activeCloserRule});
  final String activeReadBadge, mathRationale, activeCloserRule;

  Map<String, String> toJson() => {'activeReadBadge': activeReadBadge, 'mathRationale': mathRationale, 'activeCloserRule': activeCloserRule};
}
