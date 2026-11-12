import '../models/game_state.dart';
import '../postflop/hand_tier.dart';
import 'unmapped_spots_resolver.dart';

/// 8 presets de lectura sin HUD (Equilibrium_Deviation_Read). Multiplicadores por tier = priors declarados por el usuario
/// (Fase 9.4), NO frecuencias de solver. Se combinan por tier con min() (sin cascada) y piso [floor].
enum AnonymousReadPreset {
  cappedByCheckback,
  minbetWeakness,
  polarNuttedBarrel,
  bustedFdBluffHeavy,
  completedDrawDanger,
  threeBetPotBigSizingHonesty,
  limpCallCapped,
  floatAndStab,
}

class PresetEffect {
  const PresetEffect({this.tierMult = const {}, this.airCap, this.airShift = 0, this.dropMedium = false, this.forceCapped = false});

  /// Multiplicador por tier (combinado con min entre presets activos).
  final Map<HandTier, double> tierMult;

  /// Tope de la cuota de aire (truncado polar).
  final double? airCap;

  /// Desplazamiento absoluto de la cuota de aire (+14pp / -14pp por runout de proyectos fallidos).
  final double airShift;

  /// Nodo polar: los bluff-catchers medios no apuestan grande.
  final bool dropMedium;
  final bool forceCapped;
}

class ReadPresetsCatalog {
  ReadPresetsCatalog._();

  static const floor = 0.05;
  static const compressionNuts = 0.10, compressionAir = 0.15; // Sizing_Compression_Law (< 25% pot)
  static const inactionNuts = 0.20; // Inaction_Cap_Law
  static const polarAirCapMicro = 0.12; // Polarization_Truncated_Law (>= 90% river NL2-NL50)
  static const threeBetBigAirCap = 0.10; // Nutted_Ax_Commitment
  static const bustedShift = 0.14;
  static const completedDangerMedium = 0.5;

  static String label(AnonymousReadPreset p) => switch (p) {
        AnonymousReadPreset.cappedByCheckback => 'PRESET_CAPPED_BY_CHECKBACK',
        AnonymousReadPreset.minbetWeakness => 'PRESET_MINBET_WEAKNESS',
        AnonymousReadPreset.polarNuttedBarrel => 'PRESET_POLAR_NUTTED_BARREL',
        AnonymousReadPreset.bustedFdBluffHeavy => 'PRESET_BUSTED_FD_BLUFF_HEAVY',
        AnonymousReadPreset.completedDrawDanger => 'PRESET_COMPLETED_DRAW_DANGER',
        AnonymousReadPreset.threeBetPotBigSizingHonesty => 'PRESET_3BP_BIG_SIZING_HONESTY',
        AnonymousReadPreset.limpCallCapped => 'PRESET_LIMP_CALL_CAPPED',
        AnonymousReadPreset.floatAndStab => 'PRESET_FLOAT_AND_STAB',
      };

  static PresetEffect effect(AnonymousReadPreset p, GameState s) => switch (p) {
        AnonymousReadPreset.cappedByCheckback => const PresetEffect(
            tierMult: {HandTier.nutsMonster: inactionNuts, HandTier.strongTopPairOverpair: inactionNuts}, forceCapped: true),
        AnonymousReadPreset.minbetWeakness => const PresetEffect(
            tierMult: {HandTier.nutsMonster: compressionNuts, HandTier.airGiveUp: compressionAir, HandTier.backdoorBlockerBluff: compressionAir},
            forceCapped: true),
        AnonymousReadPreset.polarNuttedBarrel => const PresetEffect(dropMedium: true, airCap: polarAirCapMicro),
        AnonymousReadPreset.bustedFdBluffHeavy =>
          PresetEffect(airShift: UnmappedSpotsResolver.heroBlocksBustedDraw(s) ? -bustedShift : bustedShift),
        AnonymousReadPreset.completedDrawDanger => const PresetEffect(
            tierMult: {HandTier.strongTopPairOverpair: completedDangerMedium, HandTier.marginalMadeShowdown: completedDangerMedium}),
        AnonymousReadPreset.threeBetPotBigSizingHonesty => const PresetEffect(airCap: threeBetBigAirCap),
        AnonymousReadPreset.limpCallCapped => const PresetEffect(), // truncado aplicado en el rango preflop (AA-JJ, AK fuera)
        AnonymousReadPreset.floatAndStab => const PresetEffect(tierMult: {HandTier.nutsMonster: inactionNuts}),
      };

  /// Presets activos por la línea de la mano (o forzados manualmente).
  static List<AnonymousReadPreset> detect(GameState s, {double potBefore = 0, double toCall = 0, List<AnonymousReadPreset> manual = const []}) {
    if (s.villainPosition == null || s.board.length < 3) return manual;
    final out = <AnonymousReadPreset>{...manual};
    final u = UnmappedSpotsResolver.facts(s, potBefore: potBefore, toCall: toCall);
    if (u.villainLimpCalled) out.add(AnonymousReadPreset.limpCallCapped);
    if (u.pfaMissedCbet || u.villainCheckedBackTurnWithInitiative) out.add(AnonymousReadPreset.cappedByCheckback);
    if (u.microBet) out.add(AnonymousReadPreset.minbetWeakness);
    if (u.bustedRunout && u.villainBetRiver) out.add(AnonymousReadPreset.bustedFdBluffHeavy);
    if (u.bigRiverBetMicro && !u.bustedRunout) out.add(AnonymousReadPreset.polarNuttedBarrel);
    if (u.completedDrawAggression) out.add(AnonymousReadPreset.completedDrawDanger);
    if (u.threeBetBigCbetHighBoard) out.add(AnonymousReadPreset.threeBetPotBigSizingHonesty);
    if (u.floatAndStab) out.add(AnonymousReadPreset.floatAndStab);
    return out.toList();
  }
}
