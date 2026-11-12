import 'dart:math' as math;

import '../evaluators/board_analyzer.dart';
import '../evaluators/hand_evaluator.dart';
import '../models/decision_output.dart';
import '../models/game_state.dart';
import '../reads/gg_profiler.dart';
import '../reads/range_funnel.dart';
import 'geometry.dart';
import 'defense_budget.dart';
import 'exploit_modifier.dart';
import 'hand_tier.dart';
import 'geometric_2e_planner.dart';
import 'monotone_fourflush_solver.dart';

enum CardShift { brickTotal, rankShift, flushOrStraightCompletes }

enum LateNode { barrel, tripleBarrel, probeBet, delayedCbet, checkedTo }

enum HandRole { value, thinValue, bluff, thinBluff, check }

class LateStreetPlan {
  const LateStreetPlan({
    required this.node,
    required this.shift,
    required this.sizePct,
    required this.bluffShareGto,
    required this.exploitFactor,
    required this.role,
    required this.line,
    required this.roleReason,
    this.allIn = false,
    this.executedBluffShare = 0,
    this.valueCombos = 0,
    this.bluffCombos = 0,
    this.heroTier = HandTier.airGiveUp,
    this.thinBluffShare = 0,
    this.villainState = VillainRangeState.uncapped,
    this.street = Street.turn,
    this.fishRead = false,
  });

  final HandTier heroTier;

  /// Cuota de faroles del grupo thin/block 33% (<= α_33 x factor).
  final double thinBluffShare;
  final VillainRangeState villainState;
  final Street street;
  final bool fishRead;

  static const condensed = {VillainRangeState.cappedMedium, VillainRangeState.cappedMediumShowdown, VillainRangeState.condensedDrawsAndPairs};

  /// River: thin-value / block (25-33%) vs rango condensado en manos medias; 50-66% vs fish inelástico; polar solo monsters+faroles.
  double thinValuePct(double polarPct) {
    if (street != Street.river) return polarPct.clamp(50, 66).toDouble();
    if (fishRead) return polarPct.clamp(50, 66).toDouble();
    if (condensed.contains(villainState)) return 33;
    return 50;
  }

  final LateNode node;
  final CardShift shift;
  final double sizePct;
  final double bluffShareGto;
  final double exploitFactor;
  final HandRole role;
  final String line;
  final String roleReason;
  final bool allIn;

  /// Share objetivo = GTO x factor (acotado a 1).
  double get targetBluffShare => math.min(bluffShareGto * exploitFactor, 1.0);

  /// Share EJECUTADO por el rango de Hero en el nodo (lo que se reporta).
  final double executedBluffShare;
  final double valueCombos;
  final double bluffCombos;
  double get bluffShare => executedBluffShare;
  double get valueShare => 1 - bluffShare;
}

class CardShiftMatrix {
  CardShiftMatrix._();

  static CardShift classify(List<Card> prev, Card next) {
    final f = BoardAnalyzer.analyze(prev.length > 3 ? prev.sublist(0, 3) : prev, pfa: Position.btn, defender: Position.bb);
    final before = _counts(prev), after = _counts([...prev, next]);
    final flushNow = after.$1 >= 3 && before.$1 < 3;
    final straightNow = after.$2 > before.$2;
    if (flushNow || straightNow) return CardShift.flushOrStraightCompletes;
    final top = prev.map((c) => c.rank.value).reduce(math.max);
    if (next.rank.value >= Rank.king.value && next.rank.value > top && f.height != BoardHeight.high) return CardShift.rankShift;
    return CardShift.brickTotal;
  }

  /// (max cartas de un palo, ventanas de escalera con >=3 rangos).
  static (int, int) _counts(List<Card> b) {
    final suits = List<int>.filled(4, 0);
    var mask = 0;
    for (final c in b) {
      suits[c.suit.index]++;
      mask |= 1 << c.rank.value;
    }
    if (mask & (1 << 14) != 0) mask |= 2;
    var w = 0;
    for (var lo = 1; lo <= 10; lo++) {
      var n = 0, m = mask & (0x1F << lo);
      while (m != 0) {
        m &= m - 1;
        n++;
      }
      if (n >= 3) w++;
    }
    return (suits.reduce(math.max), w);
  }
}

class TurnRiverSolver {
  const TurnRiverSolver();

  /// TwoStreetGeometricBudget: farol en Turn = 1 - (1 - α_turn)(1 - α_river), α_river con sizing polar de river 75%.
  /// (Modelo geométrico polarizado: tras abandonar faroles en River, el rango llega con α_river de faroles.)
  static double twoStreetTurnShare(double turnSizePct, {double riverSizePct = 75}) =>
      1 - (1 - bluffShareGto(turnSizePct)) * (1 - bluffShareGto(riverSizePct));

  /// Sizing de River thin/block y su cuota de faroles estricta α_33.
  static const thinRiverPct = 33.0;

  /// Bluff_Share_GTO = B / (P + 2B), con B como fracción del bote.
  static double bluffShareGto(double sizePct) {
    final b = sizePct / 100;
    return b / (1 + 2 * b);
  }

  static double exploitBluffFactor(ReadProfile r, FunnelResult f, Street street, double potBb) {
    switch (r.archetype) {
      case GgArchetype.recPassiveFish:
        return street == Street.river ? 0.0 : 0.5;
      case GgArchetype.trapperLimpReraiser:
        return 0.0;
      case GgArchetype.scaredMoneyReg:
        if (f.isCapped && potBb > ReadProfile.scaredBigPotBb) return 2.0;
        return street == Street.turn ? scaredTurnBarrelFactor : 1.0;
      case GgArchetype.agroSpewy:
        return 0.5;
      case GgArchetype.unknownReg:
        return 1.0;
      case GgArchetype.poolDefault:
        return street == Street.turn ? overFolderFactor(ExploitModifier.poolTurnBluffFactor()) : 1.0;
    }
  }

  /// Over-Folder: Exploit_Bluff_Factor acotado a [1.6, 2.2] (CLAUDE.md §9).
  static const overFolderMin = 1.6, overFolderMax = 2.2;

  /// TAG_SCARED_REG: Turn_Barrel_Bluff_Factor (prior del usuario, dentro de [1.6, 2.2]).
  static const scaredTurnBarrelFactor = 1.8;
  static double overFolderFactor(double raw) => raw.clamp(overFolderMin, overFolderMax).toDouble();

  LateStreetPlan plan(GameState s, ReadProfile read, {required bool heroHadInitiative, required double pot, required double stack}) {
    final street = s.street;
    final prev = s.board.sublist(0, s.board.length - 1);
    final shift = CardShiftMatrix.classify(prev, s.board.last);
    final funnel = RangeFunnel.track(s);
    final h = HandTierClassifier.classify(s.hero!.high.id, s.hero!.low.id, [for (final c in s.board) c.id]);
    final heroIp = s.heroPosition.isInPositionVs(s.villainPosition!);
    final heroIsPfa = s.preflopAggressor == s.heroPosition;
    var factor = exploitBluffFactor(read, funnel, street, pot);
    final spr = PotGeometry.spr(stack, pot);

    final node = heroHadInitiative
        ? (street == Street.river && _betEveryStreet(s) ? LateNode.tripleBarrel : LateNode.barrel)
        : (heroIsPfa ? LateNode.delayedCbet : (heroIp ? LateNode.checkedTo : LateNode.probeBet));
    // Delayed_Turn_Probe: vs tight/scared (over-folder) el farol se traslada del flop húmedo al turn tras check-check.
    final delayedProbe = read.archetype == GgArchetype.scaredMoneyReg && street == Street.turn &&
        (node == LateNode.delayedCbet || node == LateNode.probeBet) && factor < overFolderMin;
    if (delayedProbe) factor = overFolderMin;

    var size = 0.0;
    var line = '';
    final capped = funnel.isCapped;
    if (shift == CardShift.flushOrStraightCompletes) {
      size = 100; // sizing único del nodo polar (valor y faroles comparten tamaño => ratio α balanceado por sizing)
      line = 'Flush_Or_Straight_Completes: línea polarizada 75-120% (nut blocker / nuts)';
    } else if (shift == CardShift.rankShift && street == Street.turn && heroHadInitiative) {
      size = 33;
      line = 'Rank_Shift: overcard A/K favorece al PFA => High_Frequency_Turn_Barrel 33%';
    } else if (capped && (shift == CardShift.brickTotal || !heroHadInitiative)) {
      size = street == Street.turn ? 80 : 125;
      line = 'Villano ${funnel.state.name} + brick: Geometric_Overbet_Line (turn 75-85% -> river 125%/all-in)';
    } else {
      size = street == Street.turn
          ? PotGeometry.geometricFraction(pot, stack, 2).clamp(0.66, 0.75) * 100
          : 75;
      line = 'Brick vs rango ${funnel.state.name}: barrel geométrico';
    }
    final greedy = read.archetype == GgArchetype.recPassiveFish && street == Street.river &&
        (h.tier == HandTier.nutsMonster || h.tier == HandTier.strongTopPairOverpair);
    if (greedy) {
      size = size.clamp(80, 125).toDouble();
      line = '$line | Greedy_Value_Sizing vs Inelastic-Caller (80-125%, TPGK+)';
    }
    if (delayedProbe) line = '$line | Delayed_Turn_Probe vs Over-Folder (factor ${overFolderMin}x)';
    // Geo-2E: Turn con SPR 1.6-3.8 => sizing geométrico de 2 calles (River all-in limpio). Nunca en barrel de rango 33%.
    final geo = street == Street.turn && !(shift == CardShift.rankShift && heroHadInitiative) ? Geometric2EPlanner.plan(pot, stack) : null;
    if (geo != null) {
      size = geo.$1;
      line = '$line | ${Geometric2EPlanner.note(geo.$1, geo.$2)}';
    }
    final allIn = pot * size / 100 >= stack * 0.9 || (street == Street.river && spr <= 1.25);
    if (allIn) size = stack / pot * 100;

    final gtoShare = street == Street.turn ? twoStreetTurnShare(size) : bluffShareGto(size);
    final target = math.min(gtoShare * factor, 1.0);
    final rangeBet = shift == CardShift.rankShift && street == Street.turn && heroHadInitiative;
    final sel = _selection(s, read, funnel, shift, factor, street, heroHadInitiative, target, rangeBet);
    final heroKey = _key(s.hero!);
    final vr = _valueRole(s, h, read, funnel, shift, street, heroHadInitiative);
    final HandRole role;
    final String why;
    if (vr != null) {
      (role, why) = vr;
    } else if (sel.selected.contains(heroKey) && MonotoneFourFlushSolver.killNoSuitBluff(s, read)) {
      role = HandRole.check;
      why = 'Four_To_A_Flush: 0% farol sin carta del palo.';
    } else if (sel.selected.contains(heroKey)) {
      role = sel.thinGroup.contains(heroKey) ? HandRole.thinBluff : HandRole.bluff;
      why = rangeBet
          ? 'Rank_Shift: barrel de rango (incluye manos sin equidad).'
          : 'Farol seleccionado (${_why(s, h, street)}); ${sel.bluff.toStringAsFixed(0)} combos de farol para ${sel.value.toStringAsFixed(0)} de valor.';
    } else {
      role = HandRole.check;
      why = factor == 0
          ? 'Exploit_Bluff_Factor 0.0: sin faroles vs ${read.archetype.name}.'
          : 'Fuera del cupo de faroles (${(target * 100).toStringAsFixed(1)}%): check.';
    }
    final executed = (sel.value + sel.bluff) == 0 ? 0.0 : sel.bluff / (sel.value + sel.bluff);
    return LateStreetPlan(
      node: node,
      shift: shift,
      sizePct: size,
      bluffShareGto: gtoShare,
      exploitFactor: factor,
      role: role,
      line: line,
      roleReason: why,
      allIn: allIn,
      executedBluffShare: executed,
      thinBluffShare: (sel.thinValue + sel.thinBluff) == 0 ? 0 : sel.thinBluff / (sel.thinValue + sel.thinBluff),
      valueCombos: sel.value,
      bluffCombos: sel.bluff,
      heroTier: h.tier,
      villainState: funnel.state,
      street: street,
      fishRead: read.archetype == GgArchetype.recPassiveFish,
    );
  }

  static int _key(HoleCards h) {
    final a = h.high.id, b = h.low.id;
    return a < b ? a * 52 + b : b * 52 + a;
  }

  static final _selCache = <String, ({Set<int> selected, double value, double bluff, Set<int> thinGroup, double thinValue, double thinBluff})>{};

  /// L9: cuenta combos de valor del rango de Hero y selecciona exactamente Value x share/(1-share) faroles
  /// por prioridad Retained_Equity -> Nut_Blocker -> Unblockers_To_Folds.
  ({Set<int> selected, double value, double bluff, Set<int> thinGroup, double thinValue, double thinBluff}) _selection(GameState s,
      ReadProfile read, FunnelResult f, CardShift shift, double factor, Street street, bool init, double target, bool rangeBet) {
    final key = [
      s.board.join(),
      s.heroPosition.name,
      s.villainPosition?.name,
      s.stake.name,
      read.archetype.name,
      target.toStringAsFixed(4),
      rangeBet,
      for (final a in s.actions) '${a.street.index}${a.actor.index}${a.type.index}${a.amountBb}${a.timing.index}',
    ].join('|');
    return _selCache.putIfAbsent(key, () {
      if (_selCache.length > 256) _selCache.clear();
      final range = DefenseBudget.heroRangeAtStreet(s, read);
      final ids = [for (final c in s.board) c.id];
      var value = 0.0, thinValue = 0.0;
      final thinNode = street == Street.river && read.archetype != GgArchetype.recPassiveFish && LateStreetPlan.condensed.contains(f.state);
      final cands = <(int, double, double)>[];
      for (final e in range.entries) {
        final a = e.key ~/ 52, b = e.key % 52;
        final hc = HoleCards(_card(a), _card(b));
        final gs = s.copyWith(hero: hc);
        final h = HandTierClassifier.classify(a, b, ids);
        final vr = _valueRole(gs, h, read, f, shift, street, init);
        if (vr != null) {
          if (vr.$1 == HandRole.value || vr.$1 == HandRole.thinValue) {
            if (thinNode && h.tier != HandTier.nutsMonster) {
              thinValue += e.value;
            } else {
              value += e.value;
            }
          }
          continue;
        }
        if (factor == 0 && !rangeBet) continue;
        final p = _priority(gs, h, street, factor);
        if (p == null) continue;
        cands.add((e.key, e.value, p + ((e.key * 2654435761) & 0xFFFF) / 1e7));
      }
      cands.sort((x, y) => y.$3.compareTo(x.$3));
      final want = rangeBet ? double.infinity : (target >= 1 ? double.infinity : value * target / (1 - target));
      final sel = <int>{};
      final thinGroup = <int>{};
      var acc = 0.0;
      var i = 0;
      for (; i < cands.length; i++) {
        if (acc >= want) break;
        sel.add(cands[i].$1);
        acc += cands[i].$2;
      }
      // Grupo thin/block 33%: cuota estricta α_33 x factor sobre todo el valor fino (Strong_TopPair + Marginal).
      var thinAcc = 0.0;
      final thinFactor = read.archetype == GgArchetype.poolDefault ? ExploitModifier.poolRiverSmallBetBluffFactor() * factor : factor;
      if (thinNode && thinFactor > 0) {
        final a33 = math.min(bluffShareGto(thinRiverPct) * thinFactor, 1.0);
        final thinWant = thinValue * a33 / (1 - a33);
        for (; i < cands.length; i++) {
          if (thinAcc + cands[i].$2 > thinWant + 1e-9) break;
          sel.add(cands[i].$1);
          thinGroup.add(cands[i].$1);
          thinAcc += cands[i].$2;
        }
      }
      return (selected: sel, value: value + thinValue, bluff: acc + thinAcc, thinGroup: thinGroup, thinValue: thinValue, thinBluff: thinAcc);
    });
  }

  static Card _card(int id) => Card(Rank.values[id >> 2], Suit.values[id & 3]);

  /// Prioridad de farol; null = no elegible.
  double? _priority(GameState s, HandTierResult h, Street street, double factor) {
    const eligible = {HandTier.highEquityComboDraw, HandTier.backdoorBlockerBluff, HandTier.airGiveUp};
    final marginalOk = factor >= 2 && street == Street.turn && h.tier == HandTier.marginalMadeShowdown;
    if (!eligible.contains(h.tier) && !marginalOk) return null;
    final outs = street == Street.river
        ? 0.0
        : (h.flushDraw ? 9 : 0) + (h.oesd ? 8 : (h.gutshot ? 4 : 0)) + (h.overcards ? 3 : 0) + (h.backdoorFlush ? 1.5 : 0);
    final kb = street == Street.river ? keyBlockers(s, h) : (h.flushSuitBlocker, false, '');
    return outs * 10 + (kb.$1 ? 5 : 0) + (kb.$2 ? 0 : 2);
  }

  String _why(GameState s, HandTierResult h, Street street) {
    final d = _draws(h);
    if (street == Street.turn && d.isNotEmpty) return 'Equity_Retained: $d';
    if (street == Street.river) {
      final kb = keyBlockers(s, h);
      if (kb.$1) return kb.$3;
    }
    return h.flushSuitBlocker ? 'nut blocker' : 'unblocker de folds';
  }

  bool _betEveryStreet(GameState s) {
    for (final st in [Street.flop, Street.turn]) {
      if (!s.actions.any((a) => a.street == st && a.actor == s.heroPosition && a.isAggressive)) return false;
    }
    return true;
  }

  /// Rol de valor (value/thinValue/check forzado) o null si la mano es candidata a farol / check.
  (HandRole, String)? _valueRole(GameState s, HandTierResult h, ReadProfile read, FunnelResult f, CardShift shift,
      Street street, bool init) {
    final tier = h.tier;
    final fish = read.archetype == GgArchetype.recPassiveFish;
    if (tier == HandTier.nutsMonster) return (HandRole.value, 'Nuts_Monster: valor.');
    if (tier == HandTier.strongTopPairOverpair) {
      if (shift == CardShift.flushOrStraightCompletes && !fish) return (HandRole.check, '1 par en carta que completa: control de bote.');
      if (fish || f.isCapped) return (HandRole.value, 'Top pair/overpair vs rango capado/inelástico: valor.');
      return street == Street.turn && init
          ? (HandRole.check, 'Top pair en brick: check-call (protege rango de check).')
          : (HandRole.thinValue, 'Top pair river: thin value.');
    }
    if (tier == HandTier.marginalMadeShowdown) {
      if (fish && street == Street.river && _pairPos(s) <= 1) {
        return (HandRole.thinValue, 'Fish inelástico: thin value con top pair débil / 2do par.');
      }
      return null;
    }
    return null;
  }

  /// (bloquea su rango de call, bloquea su rango de fold, descripción).
  static (bool, bool, String) keyBlockers(GameState s, HandTierResult h) {
    final board = s.board;
    final suits = List<int>.filled(4, 0);
    for (final c in board) {
      suits[c.suit.index]++;
    }
    final hero = [s.hero!.high, s.hero!.low];
    final flushDone = suits.any((n) => n >= 3);
    if (flushDone) {
      final fs = suits.indexOf(suits.reduce(math.max));
      final onBoard = {for (final c in board) if (c.suit.index == fs) c.rank.value};
      final topFree = [for (var r = 14; r >= 2; r--) if (!onBoard.contains(r)) r];
      final holds = hero.where((c) => c.suit.index == fs && topFree.take(2).contains(c.rank.value));
      if (holds.isNotEmpty) return (true, false, 'Key blocker ${holds.first} al color (nut/2nd nut)');
    }
    final flop = board.sublist(0, 3);
    final fsCount = List<int>.filled(4, 0);
    for (final c in flop) {
      fsCount[c.suit.index]++;
    }
    final missedSuit = !flushDone ? fsCount.indexWhere((n) => n >= 2) : -1;
    final blocksFold = missedSuit >= 0 && hero.any((c) => c.suit.index == missedSuit);

    var mask = 0;
    for (final c in board) {
      mask |= 1 << (c.rank.value - 2);
    }
    for (final c in hero) {
      final r = c.rank.value - 2;
      if (mask & (1 << r) != 0) continue;
      for (var o = 0; o < 13; o++) {
        if (o == r || mask & (1 << o) != 0) continue;
        if (HandEvaluator.straightHigh(mask | (1 << r) | (1 << o)) >= 0) {
          return (true, blocksFold, 'Blocker de escalera ${c.rank.symbol}');
        }
      }
    }
    final top = board.map((c) => c.rank.value).reduce(math.max);
    if (hero.any((c) => c.rank.value == top)) return (true, blocksFold, 'Bloquea top pair');
    return (false, blocksFold, '');
  }

  int _pairPos(GameState s) {
    final ranks = {for (final c in s.board) c.rank.value}.toList()..sort((a, b) => b.compareTo(a));
    for (final c in [s.hero!.high, s.hero!.low]) {
      final i = ranks.indexOf(c.rank.value);
      if (i >= 0) return i;
    }
    return 99;
  }

  String _draws(HandTierResult h) => [
        if (h.flushDraw) 'FD',
        if (h.oesd) 'OESD',
        if (h.gutshot) 'gutshot',
        if (h.overcards) 'overcards',
      ].join('+');

  DecisionOutput toDecision(LateStreetPlan p, double pot, double stack, List<KeyMetric> m, ReadProfile read) {
    final metrics = [
      ...m,
      KeyMetric(MetricType.bluffShare, p.bluffShare, 'GTO ${(p.bluffShareGto * 100).toStringAsFixed(1)}% x factor ${p.exploitFactor}'),
      KeyMetric(MetricType.valueShare, p.valueShare),
    ];
    final gto = '${p.node.name} | ${p.shift.name} | ${p.line} | bluff share B/(P+2B) = ${(p.bluffShareGto * 100).toStringAsFixed(1)}%';
    final readTxt = '${read.archetype.name}: factor ${p.exploitFactor} => bluffs ${(p.bluffShare * 100).toStringAsFixed(1)}% | ${p.roleReason}';
    if (p.role == HandRole.check) {
      return DecisionOutput(action: DecisionAction.check, metrics: metrics, justificacionGto: gto, ajusteExplotativoRead: readTxt);
    }
    var pct = p.sizePct;
    final thin = p.role == HandRole.thinValue || (p.street == Street.river && p.role == HandRole.value && p.heroTier != HandTier.nutsMonster);
    if (thin) pct = p.thinValuePct(pct);
    if (p.role == HandRole.thinBluff) pct = thinRiverPct;
    final bb = p.allIn && !thin && p.role != HandRole.thinBluff ? stack : math.min(stack, pot * pct / 100);
    return DecisionOutput(
      action: DecisionAction.betRaise,
      sizing: Sizing(bb: bb, potPct: bb / pot * 100),
      metrics: metrics,
      justificacionGto: gto,
      ajusteExplotativoRead: readTxt,
    );
  }
}
