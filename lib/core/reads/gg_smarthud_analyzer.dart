import 'villain_archetypes.dart';

/// Stats GGPoker SmartHUD (0..100).
class SmartHudStats {
  const SmartHudStats({required this.vpip, required this.pfr, required this.threeBet, required this.ats, this.hands = 100});
  final double vpip, pfr, threeBet, ats;
  final int hands;

  SmartHudStats copyWith({double? vpip, double? pfr, double? threeBet, double? ats, int? hands}) => SmartHudStats(
      vpip: vpip ?? this.vpip, pfr: pfr ?? this.pfr, threeBet: threeBet ?? this.threeBet, ats: ats ?? this.ats, hands: hands ?? this.hands);

  static SmartHudStats preset(VillainTag t) {
    final (v, p, b, a) = VillainArchetypes.of(t).presetStats;
    return SmartHudStats(vpip: v, pfr: p, threeBet: b, ats: a);
  }
}

/// Referencia 6-Max declarada por el usuario (prior, no export de solver).
class GtoRef {
  GtoRef._();
  static const vpip = 24.0, pfr = 20.0, gap = 4.0, threeBet = 8.5, ats = 42.0;
  static const minHands = 15;
}

class SmartHudDeviation {
  const SmartHudDeviation({
    required this.stats,
    required this.vpipPfrGap,
    required this.aggressionRatio,
    required this.stealDeviation,
    required this.threeBetDeviation,
    required this.tag,
    required this.autoInferred,
    required this.reasons,
  });

  final SmartHudStats stats;
  final double vpipPfrGap, aggressionRatio, stealDeviation, threeBetDeviation;
  final VillainTag tag;
  final bool autoInferred;
  final List<String> reasons;

  bool get passiveFish => vpipPfrGap > 12;
  bool get tightGap => vpipPfrGap <= 4;
  bool get wideStealer => stealDeviation > 12;
  bool get nitStealer => stealDeviation < -12;
  bool get linearNutted3B => stats.threeBet < 4.5;
  bool get agroBluff3B => stats.threeBet > 12;

  ExploitVector get vector => VillainArchetypes.of(tag);

  /// Badge en vivo para el HUD.
  String get badge {
    final g = vpipPfrGap - GtoRef.gap;
    return 'Diagnóstico: ${vector.label} (Gap ${g >= 0 ? '+' : ''}${g.toStringAsFixed(0)}%) -> ${vector.diagnosis}';
  }

  Map<String, Object> toJson() => {
        'Input_Stats': {'vpip': stats.vpip, 'pfr': stats.pfr, 'threeBet': stats.threeBet, 'ats': stats.ats},
        'Derived_Metrics': {
          'vpip_pfr_gap': vpipPfrGap,
          'aggression_ratio': aggressionRatio,
          'steal_deviation': stealDeviation,
          'threebet_deviation': threeBetDeviation,
        },
        'tag': tag.name,
        'auto': autoInferred,
      };
}

/// Analizador determinista de desviación SmartHUD vs referencia 6-Max. Jerarquía: etiqueta manual > Trapper (limp-reraise)
/// > Maniac (4 umbrales agresivos; un VPIP alto agresivo no es pasivo) > Fish > Nit > Scared > Pool (sin datos / < 15 manos / sin señal).
class GgSmartHudAnalyzer {
  GgSmartHudAnalyzer._();

  static SmartHudDeviation analyze(SmartHudStats s, {VillainTag? manualTag, bool limpReraiseSeen = false}) {
    final gap = s.vpip - s.pfr;
    final ar = s.pfr / (s.vpip < 1 ? 1 : s.vpip);
    final sd = s.ats - GtoRef.ats, td = s.threeBet - GtoRef.threeBet;
    final (tag, why) = manualTag != null
        ? (manualTag, ['Etiqueta manual (prioridad sobre stats)'])
        : _infer(s, gap, limpReraiseSeen);
    return SmartHudDeviation(
      stats: s,
      vpipPfrGap: gap,
      aggressionRatio: ar,
      stealDeviation: sd,
      threeBetDeviation: td,
      tag: tag,
      autoInferred: manualTag == null,
      reasons: why,
    );
  }

  static (VillainTag, List<String>) _infer(SmartHudStats s, double gap, bool limpReraise) {
    if (limpReraise) return (VillainTag.trapper, ['Limp-ReRaise detectado']);
    if (s.hands < GtoRef.minHands) return (VillainTag.poolDefault, ['Muestra < ${GtoRef.minHands} manos']);
    if (s.vpip >= 32 && s.pfr >= 26 && s.threeBet >= 12 && s.ats >= 55) {
      return (VillainTag.agroManiac, ['VPIP>=32 / PFR>=26 / 3B>=12 / ATS>=55']);
    }
    if (s.vpip >= 36 || gap >= 14) {
      return (VillainTag.fishStation, ['VPIP ${s.vpip.round()} >= 36 o Gap ${gap.round()} >= 14']);
    }
    if (s.vpip <= 17 && s.pfr <= 14 && s.threeBet <= 4.5) return (VillainTag.nitPassive, ['VPIP<=17 / PFR<=14 / 3B<=4.5']);
    if (s.vpip >= 19 && s.vpip <= 24 && s.pfr >= 16 && s.pfr <= 21 && s.threeBet >= 6 && s.threeBet <= 8 && s.ats <= 38) {
      return (VillainTag.scaredReg, ['VPIP 19-24 / PFR 16-21 / 3B 6-8 / ATS<=38']);
    }
    return (VillainTag.poolDefault, ['Sin desviación clasificable: Pool por stake']);
  }
}
