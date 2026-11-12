import 'dart:typed_data';

import '../discipline/timing_tells_matrix.dart';
import '../evaluators/action_ev_calculator.dart';
import '../models/decision_insight.dart';
import '../models/game_state.dart';
import '../postflop/defense_budget.dart';
import '../postflop/hand_tier.dart';
import '../postflop/range_equity.dart';
import '../postflop/terminal_exploit_closers.dart';
import '../preflop/preflop_ranges_db.dart';
import '../preflop/range_notation.dart';
import 'gg_profiler.dart';
import 'read_presets_catalog.dart';

/// Inspector de rango percibido: radiografía del rango que el motor asigna al villano principal en el nodo
/// (RangeFunnel/line weights + remoción de cartas de Hero + timing + prior de línea T2). Multiway: villano principal.
class VillainRangeInspector {
  VillainRangeInspector._();

  static const cappedNutsShare = 0.035;
  static const polarSizing = 0.75;

  static int _idx169(int a, int b) {
    final ra = a >> 2, rb = b >> 2;
    final h = 12 - (ra > rb ? ra : rb), l = 12 - (ra > rb ? rb : ra);
    if (ra == rb) return h * 13 + h;
    return (a & 3) == (b & 3) ? h * 13 + l : l * 13 + h;
  }

  static VillainPerceivedRange inspect(GameState s, ReadProfile rp,
      {double betFraction = 0.66, double potBefore = 0, double toCall = 0, List<AnonymousReadPreset> manualPresets = const []}) {
    if (s.villainPosition == null || s.hero == null) return VillainPerceivedRange.empty;
    try {
      return s.board.length >= 3 ? _postflop(s, rp, betFraction, potBefore, toCall, manualPresets) : _preflop(s);
    } on Object {
      return VillainPerceivedRange.empty;
    }
  }

  static VillainPerceivedRange _postflop(GameState s, ReadProfile rp, double f, double potBefore, double toCall, List<AnonymousReadPreset> manual) {
    final vc = RangeEquity.villainCombos(s);
    final heroMask = s.hero!.mask;
    final street = s.actions.where((a) => a.street == s.street && a.actor == s.villainPosition).toList();
    final instaCheck = street.any((a) => a.type == ActionType.check && a.timing == TimingTell.instaAction);
    final nutsMult = instaCheck ? 1 - TimingTellsMatrix.instaCheckTrapRemoval : 1.0;
    // Polar_Node: apuesta del villano >= 75% del bote en River => rango polar (valor + faroles); los bluff-catchers medios
    // no apuestan grande (principio de sizing polar, mismo supuesto que el EV de bluff-catcher de T2).
    final vBet = street.where((a) => a.isAggressive).lastOrNull;
    final polar = s.street == Street.river && vBet != null && toCall > 0 && potBefore > 0 && toCall / potBefore >= polarSizing;
    // Equilibrium_Deviation_Read: presets sin HUD (nunca vs Reg_GTO etiquetado). Por tier: min() de multiplicadores, piso.
    // Presets manuales (1 toque en la UI) se respetan también vs Reg_GTO; los automáticos nunca vs Reg_GTO.
    final presets = rp.archetype == GgArchetype.unknownReg
        ? manual
        : ReadPresetsCatalog.detect(s, potBefore: potBefore, toCall: toCall, manual: manual);
    final effects = [for (final p in presets) ReadPresetsCatalog.effect(p, s)];
    final mult = <HandTier, double>{};
    for (final e in effects) {
      e.tierMult.forEach((t, m) => mult[t] = mult[t] == null || m < mult[t]! ? m : mult[t]!);
    }
    mult.updateAll((_, m) => m < ReadPresetsCatalog.floor ? ReadPresetsCatalog.floor : m);
    final dropMedium = polar || effects.any((e) => e.dropMedium);
    var nuts = 0.0, med = 0.0, draws = 0.0, air = 0.0, blockedNuts = 0.0;
    final w = <double>[], t = <HandTier>[], cls = <int>[];
    for (var k = 0; k < vc.combos.length; k++) {
      final (a, b) = vc.combos[k];
      final tier = vc.tiers[k];
      if ((heroMask >> a) & 1 == 1 || (heroMask >> b) & 1 == 1) {
        if (tier == HandTier.nutsMonster) blockedNuts += vc.weights[k];
        continue;
      }
      final medium = tier == HandTier.strongTopPairOverpair || tier == HandTier.marginalMadeShowdown;
      if (dropMedium && medium) continue;
      final pm = mult[tier] ?? 1.0;
      final x = (tier == HandTier.nutsMonster ? vc.weights[k] * nutsMult : vc.weights[k]) * pm;
      w.add(x);
      t.add(tier);
      cls.add(_idx169(a, b));
      switch (tier) {
        case HandTier.nutsMonster:
          nuts += x;
        case HandTier.strongTopPairOverpair || HandTier.marginalMadeShowdown:
          med += x;
        case HandTier.highEquityComboDraw:
          draws += x;
        case HandTier.backdoorBlockerBluff || HandTier.airGiveUp:
          air += x;
      }
    }
    // T2: el rango de apuesta del pool trae como máximo su cuota real de faroles (prior de línea).
    final ctx = TerminalExploitClosers.context(s, rp, potBefore: potBefore, toCall: toCall);
    var airScale = 1.0;
    final share = ctx?.villainBluffShare;
    final tot0 = nuts + med + draws + air;
    if (share != null && tot0 > 0 && air / tot0 > share) {
      final rest = nuts + med + draws;
      airScale = share * rest / ((1 - share) * air);
      air *= airScale;
    }
    // Truncado polar (tope de aire) y desplazamiento por proyectos fallidos.
    final caps = [for (final e in effects) if (e.airCap != null) e.airCap!];
    final shift = effects.fold<double>(0, (a, e) => a + e.airShift);
    if (caps.isNotEmpty || shift != 0) {
      final total = nuts + med + draws + air;
      if (total > 0) {
        var target = air / total + shift;
        if (caps.isNotEmpty) target = target.clamp(0.0, caps.reduce((a, b) => a < b ? a : b));
        target = target.clamp(0.02, 0.95);
        final rest = nuts + med + draws;
        if (air > 0 && rest > 0) {
          final newAir = target * rest / (1 - target);
          airScale *= newAir / air;
          air = newAir;
        }
      }
    }
    final tot = nuts + med + draws + air;
    if (tot <= 0) return VillainPerceivedRange.empty;
    final byClass = <int, double>{};
    var folds = 0.0;
    final river = s.street == Street.river;
    for (var k = 0; k < w.length; k++) {
      final isAir = t[k] == HandTier.airGiveUp || t[k] == HandTier.backdoorBlockerBluff;
      final x = isAir ? w[k] * airScale : w[k];
      byClass.update(cls[k], (v) => v + x, ifAbsent: () => x);
      if (!ActionEvCalculator.continues(t[k], f, river: river, vp: s.villainProfile)) folds += x;
    }
    final nutsPct = nuts / tot;
    final capped = nutsPct < cappedNutsShare || effects.any((e) => e.forceCapped);
    final fe = ctx?.foldEquityOverride ??
        ActionEvCalculator.foldEquity(folds / tot, f / (1 + f), rp, s.villainProfile, river: river, capped: capped, betFraction: f);
    return VillainPerceivedRange(
      totalActiveCombos: tot.round(),
      isCapped: capped,
      nutsAndMonstersPct: nutsPct,
      mediumShowdownPct: med / tot,
      drawsAndSemibluffsPct: draws / tot,
      pureAirAndBluffsPct: air / tot,
      topRepresentativeHands: _top(byClass),
      predictedFoldFreq: fe,
      predictedBluffFreq: air / tot,
      heroBlockedNutsCombos: blockedNuts,
      activePresets: [for (final p in presets) ReadPresetsCatalog.label(p)],
    );
  }

  static List<String> _top(Map<int, double> byClass) =>
      [for (final e in (byClass.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(5)) Matrix169.label(e.key)];

  static VillainPerceivedRange _preflop(GameState s) {
    final v = s.villainPosition!;
    Float32List range;
    if (s.preflopAggressor != null) {
      range = DefenseBudget.villainPreflopRange(s);
    } else {
      range = PreflopRangesDb.rfi(v, s.rakeTier).weights[PreflopAction.raise] ?? Float32List(169);
    }
    final heroMask = s.hero!.mask;
    var nuts = 0.0, med = 0.0, draws = 0.0, air = 0.0;
    final byClass = <int, double>{};
    for (var i = 0; i < 169; i++) {
      if (range[i] <= 0) continue;
      var n = 0;
      for (final (a, b) in Matrix169.concreteCombos(i)) {
        if ((heroMask >> a) & 1 == 0 && (heroMask >> b) & 1 == 0) n++;
      }
      final x = range[i] * n;
      if (x <= 0) continue;
      byClass[i] = x;
      final label = Matrix169.label(i);
      final pair = label.length == 2;
      const bw = 'AKQJT';
      if (['AA', 'KK', 'QQ'].contains(label) || label.startsWith('AK')) {
        nuts += x;
      } else if (pair || (bw.contains(label[0]) && bw.contains(label[1]))) {
        med += x;
      } else if (label.endsWith('s')) {
        draws += x;
      } else {
        air += x;
      }
    }
    final tot = nuts + med + draws + air;
    if (tot <= 0) return VillainPerceivedRange.empty;
    return VillainPerceivedRange(
      totalActiveCombos: tot.round(),
      isCapped: nuts / tot < cappedNutsShare,
      nutsAndMonstersPct: nuts / tot,
      mediumShowdownPct: med / tot,
      drawsAndSemibluffsPct: draws / tot,
      pureAirAndBluffsPct: air / tot,
      topRepresentativeHands: _top(byClass),
      predictedFoldFreq: 0,
      predictedBluffFreq: air / tot,
    );
  }
}
