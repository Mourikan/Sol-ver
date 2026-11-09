import 'dart:typed_data';

import '../models/game_state.dart';
import 'hand_normalizer.dart';
import 'preflop_ranges_db.dart';
import 'range_notation.dart';

/// Ajustes de estructura: dinero muerto (ante / straddle) y stacks ultra-profundos (> 200bb, hasta 500bb).
class StructureModifier {
  StructureModifier._();

  static const maxStackBb = 500.0;
  static const ultraDeepBb = 200.0;

  /// Expansión de RFI en CO/BTN/SB por dinero muerto: 4% + 3% x (muerto extra / ciegas), acotado a [4%, 7%].
  static double rfiExpansion(GameState s, Position hero) {
    if (s.extraDeadMoneyBb <= 0) return 0;
    if (hero != Position.co && hero != Position.btn && hero != Position.sb) return 0;
    return (0.04 + 0.03 * (s.extraDeadMoneyBb / 1.5)).clamp(0.04, 0.07);
  }

  static final _cache = <String, Float32List>{};

  /// RFI expandido: añade, por orden de equity vs el rango top, las mejores manos fuera del rango hasta +[expansion] combos.
  static Float32List expandedRfi(Position hero, RakeTier tier, double expansion) {
    return _cache.putIfAbsent('${hero.name}|${tier.name}|${expansion.toStringAsFixed(3)}', () {
      final base = Float32List.fromList(PreflopRangesDb.rfi(hero, tier).weights[PreflopAction.raise]!);
      final candidates = [for (var i = 0; i < 169; i++) if (base[i] < 1) i]
        ..sort((a, b) => HandProps.equity('MR_RFI_utg', b)!.compareTo(HandProps.equity('MR_RFI_utg', a)!));
      var added = 0.0;
      for (final i in candidates) {
        if (added >= expansion * 1326) break;
        added += (1 - base[i]) * Matrix169.combos(i);
        base[i] = 1;
      }
      return base;
    });
  }

  /// Open size con straddle (x2) y ante (+ 1 ante por jugador en el bote inicial / 6).
  static double openSize(GameState s, double base) => base * (s.hasStraddle ? 2 : 1) + s.anteBb * 3;

  /// EQR ultra-deep (> 200bb): premia nut-suited (A2s-A5s, suited connectors), penaliza offsuit de un par (AKo, AQo).
  static double ultraDeepEqr(int i, double? stack) {
    if (stack == null || stack <= ultraDeepBb) return 1.0;
    final suited = Matrix169.isSuited(i);
    final h = Matrix169.highRank(i), l = Matrix169.lowRank(i);
    if (suited && ((h == 12 && l <= 3) || (h - l <= 2 && h < 10))) return 1.08;
    if (!suited && !Matrix169.isPair(i) && h == 12 && l >= 10) return 0.93;
    return 1.0;
  }

  /// Stack-off preflop ultra-deep: solo AA/KK salvo lecturas Maniac.
  static String stackOffRange(double? stack, VillainProfile vp, String normal) =>
      stack != null && stack > ultraDeepBb && vp != VillainProfile.maniac && vp != VillainProfile.regAgro ? 'KK+' : normal;
}
