import '../models/game_state.dart';
import 'engine_mode.dart';
import 'gg_profiler.dart';

/// 6 etiquetas de jugador (manual 1-tap o inferidas por SmartHUD).
enum VillainTag { fishStation, nitPassive, scaredReg, agroManiac, trapper, poolDefault }

/// Vector de explotación por etiqueta. Constantes = priors declarados por el usuario (Fase 9.1), NO frecuencias de solver.
class ExploitVector {
  const ExploitVector({
    required this.tag,
    required this.label,
    required this.profile,
    this.isoRaiseTopPct,
    this.riverBluffFreq,
    this.valueSizingPct,
    this.stealRfiExpansion = 0,
    this.foldToThreeBetDelta = 0,
    this.fourBetBluff = true,
    this.mdfOverrideLateStreets = true,
    this.turnBarrelBluffFactor,
    this.llinusOverbetPct,
    this.threeBetDefExpansion = 0,
    this.defenseFactor,
    this.heroFoldDisciplined = true,
    this.trapCheckNuts,
    this.flopBluffFreq,
    required this.presetStats,
    required this.diagnosis,
  });

  final VillainTag tag;
  final String label;

  /// Perfil del motor que activa las reglas (Pool => depende del stake, ver [profileFor]).
  final VillainProfile profile;
  final double? isoRaiseTopPct;
  final double? riverBluffFreq;
  final (double, double)? valueSizingPct;
  final double stealRfiExpansion;
  final double foldToThreeBetDelta;
  final bool fourBetBluff;
  final bool mdfOverrideLateStreets;
  final double? turnBarrelBluffFactor;
  final double? llinusOverbetPct;
  final double threeBetDefExpansion;
  final double? defenseFactor;
  final bool heroFoldDisciplined;
  final double? trapCheckNuts;
  final double? flopBluffFreq;

  /// Stats promedio pre-cargados al tocar la etiqueta: (vpip, pfr, threeBet, ats).
  final (double, double, double, double) presetStats;
  final String diagnosis;

  VillainProfile profileFor(Stake stake) => tag == VillainTag.poolDefault ? ProfileDefaults.defaultFor(stake) : profile;

  ReadProfile readFor(Stake stake) => ReadProfile.fromVillainProfile(profileFor(stake));
}

class VillainArchetypes {
  VillainArchetypes._();

  static const Map<VillainTag, ExploitVector> vectors = {
    VillainTag.fishStation: ExploitVector(
      tag: VillainTag.fishStation,
      label: 'Fish/CS',
      profile: VillainProfile.callingStation,
      isoRaiseTopPct: 32,
      riverBluffFreq: 0,
      valueSizingPct: (80, 125),
      presetStats: (48, 8, 2, 20),
      diagnosis: 'Pasivo Inelástico -> 0% Bluff River / Max Value 80-125%',
    ),
    VillainTag.nitPassive: ExploitVector(
      tag: VillainTag.nitPassive,
      label: 'Nit',
      profile: VillainProfile.nit,
      stealRfiExpansion: 0.15,
      foldToThreeBetDelta: 0.25,
      fourBetBluff: false,
      mdfOverrideLateStreets: false,
      presetStats: (14, 11, 3, 28),
      diagnosis: 'Nit -> Steal +15% / Fold a su 3-bet / sin MDF vs raises Turn-River',
    ),
    VillainTag.scaredReg: ExploitVector(
      tag: VillainTag.scaredReg,
      label: 'Scared',
      profile: VillainProfile.regAbc,
      turnBarrelBluffFactor: 1.8,
      llinusOverbetPct: 125,
      presetStats: (21, 18, 7, 32),
      diagnosis: 'Fit-or-Fold -> Turn Barrel 1.8x / LLinus 125% vs línea capada',
    ),
    VillainTag.agroManiac: ExploitVector(
      tag: VillainTag.agroManiac,
      label: 'Maniac',
      profile: VillainProfile.maniac,
      threeBetDefExpansion: 0.12,
      defenseFactor: 1.18,
      heroFoldDisciplined: false,
      trapCheckNuts: 0.40,
      presetStats: (40, 32, 14, 62),
      diagnosis: 'Sobre-farolea -> 3-bet Def +12% / MDF x1.18 / sin hero folds / trap 40%',
    ),
    VillainTag.trapper: ExploitVector(
      tag: VillainTag.trapper,
      label: 'Trapper',
      profile: VillainProfile.trapperPremium,
      flopBluffFreq: 0,
      presetStats: (22, 6, 3, 30),
      diagnosis: 'Polar AA/KK 85%+ -> 0% Flop Bluff / solo Set-Mining o 2P+',
    ),
    VillainTag.poolDefault: ExploitVector(
      tag: VillainTag.poolDefault,
      label: 'Pool/Reg',
      profile: VillainProfile.poolDefault,
      presetStats: (24, 20, 8.5, 42),
      diagnosis: 'Sin muestra -> leyes MDA por stake (Pool NL2-NL50 / Reg_GTO NL100+)',
    ),
  };

  static ExploitVector of(VillainTag t) => vectors[t]!;
}
