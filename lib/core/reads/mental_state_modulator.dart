import '../models/decision_output.dart';
import '../models/game_state.dart';
import '../postflop/hand_tier.dart';
import 'gg_profiler.dart';
import 'unmapped_spots_resolver.dart';

/// Estado mental del villano (chip manual). Priors del usuario (Fase 9.8), no frecuencias de solver.
enum VillainMentalState { normal, steamingTilt, scaredDeepProtector }

class MentalStateModulator {
  MentalStateModulator._();

  static const tiltFeMult = 0.60, tiltBluffBoost = 0.18;
  static const protectorFeBoost = 0.16, protectorMinStackBb = 150.0, protectorBigPotBb = 35.0;
  static const tiltThinValuePct = 95.0; // 85-110% (punto medio)

  static bool tilt(ReadProfile r) => r.mentalState == VillainMentalState.steamingTilt;

  /// Protector de stack: solo perfil no-maniac y, si se conoce, stack del villano >= 150bb.
  static bool protector(ReadProfile r, GameState s) {
    if (r.mentalState != VillainMentalState.scaredDeepProtector || r.archetype == GgArchetype.agroSpewy) return false;
    final st = s.villainPosition == null ? null : s.seatStacksBb[s.villainPosition!];
    return st == null || st >= protectorMinStackBb;
  }

  /// FE real modulada: tilt x0.60 (paga con cualquier par/draw); protector +16% (multiplicativo, tope 0.95) en botes > 35bb.
  static double adjustFe(double fe, ReadProfile r, GameState s, double potNow) {
    if (tilt(r)) return fe * tiltFeMult;
    if (protector(r, s) && potNow > protectorBigPotBb) return (fe * (1 + protectorFeBoost)).clamp(0.0, 0.95);
    return fe;
  }

  /// Hero sin faroles puros en Turn/River contra un rival en tilt.
  static bool heroBluffLocked(ReadProfile r, Street st) => tilt(r) && (st == Street.turn || st == Street.river);

  /// Thin value expandido vs tilt (SecondPair_GoodKicker+): 85-110% en Turn/River sin apuesta enfrente.
  static SpotPlan? plan(GameState s, ReadProfile r, HandTierResult h, {required double toCall}) {
    if (!tilt(r) || toCall > 0 || (s.street != Street.turn && s.street != Street.river)) return null;
    final ranks = {for (final c in s.board) c.rank.value}.toList()..sort((a, b) => b.compareTo(a));
    final pairPos = [s.hero!.high, s.hero!.low].map((c) => ranks.indexOf(c.rank.value)).where((i) => i >= 0).fold<int>(99, (a, b) => a < b ? a : b);
    final ok = h.tier == HandTier.strongTopPairOverpair || (h.tier == HandTier.marginalMadeShowdown && pairPos <= 1);
    if (!ok) return null;
    return SpotPlan('Tilt_Thin_Value', DecisionAction.betRaise,
        '[🔥 EN TILT] paga con cualquier par/draw (FE x$tiltFeMult): thin value ${tiltThinValuePct.round()}% con 2º par+ (0% farol puro).',
        sizePct: tiltThinValuePct);
  }
}
