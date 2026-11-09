import 'dart:math' as math;

import '../evaluators/board_analyzer.dart';
import '../evaluators/hand_evaluator.dart';
import '../models/decision_output.dart';
import '../models/game_state.dart';
import '../reads/gg_profiler.dart';
import '../reads/range_funnel.dart';
import 'geometry.dart';
import 'hand_tier.dart';

enum CardShift { brickTotal, rankShift, flushOrStraightCompletes }

enum LateNode { barrel, tripleBarrel, probeBet, delayedCbet, checkedTo }

enum HandRole { value, thinValue, bluff, check }

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
  });

  final LateNode node;
  final CardShift shift;
  final double sizePct;
  final double bluffShareGto;
  final double exploitFactor;
  final HandRole role;
  final String line;
  final String roleReason;
  final bool allIn;

  double get bluffShare => math.min(bluffShareGto * exploitFactor, 1.0);
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
        return f.isCapped && potBb > ReadProfile.scaredBigPotBb ? 2.0 : 1.0;
      case GgArchetype.agroSpewy:
        return 0.5;
      case GgArchetype.unknownReg:
        return 1.0;
    }
  }

  LateStreetPlan plan(GameState s, ReadProfile read, {required bool heroHadInitiative, required double pot, required double stack}) {
    final street = s.street;
    final prev = s.board.sublist(0, s.board.length - 1);
    final shift = CardShiftMatrix.classify(prev, s.board.last);
    final funnel = RangeFunnel.track(s);
    final h = HandTierClassifier.classify(s.hero!.high.id, s.hero!.low.id, [for (final c in s.board) c.id]);
    final heroIp = s.heroPosition.isInPositionVs(s.villainPosition!);
    final heroIsPfa = s.preflopAggressor == s.heroPosition;
    final factor = exploitBluffFactor(read, funnel, street, pot);
    final spr = PotGeometry.spr(stack, pot);

    final node = heroHadInitiative
        ? (street == Street.river && _betEveryStreet(s) ? LateNode.tripleBarrel : LateNode.barrel)
        : (heroIsPfa ? LateNode.delayedCbet : (heroIp ? LateNode.checkedTo : LateNode.probeBet));

    var size = 0.0;
    var line = '';
    final capped = funnel.isCapped;
    if (shift == CardShift.flushOrStraightCompletes) {
      size = h.flushSuitBlocker || h.tier == HandTier.nutsMonster ? 100 : 75;
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
    final allIn = pot * size / 100 >= stack * 0.9 || (street == Street.river && spr <= 1.25);
    if (allIn) size = stack / pot * 100;

    final gtoShare = bluffShareGto(size);
    final (role, why) = _role(s, h, read, funnel, shift, factor, street, heroHadInitiative, node);
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
    );
  }

  bool _betEveryStreet(GameState s) {
    for (final st in [Street.flop, Street.turn]) {
      if (!s.actions.any((a) => a.street == st && a.actor == s.heroPosition && a.isAggressive)) return false;
    }
    return true;
  }

  (HandRole, String) _role(GameState s, HandTierResult h, ReadProfile read, FunnelResult f, CardShift shift,
      double factor, Street street, bool init, LateNode node) {
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
      if (factor >= 2 && street == Street.turn) return (HandRole.bluff, 'Par bajo convertido en farol vs rango capado (factor 2.0).');
      return (HandRole.check, 'Showdown marginal: check.');
    }
    if (factor == 0) return (HandRole.check, 'Exploit_Bluff_Factor 0.0: sin faroles vs ${read.archetype.name}.');
    if (read.archetype == GgArchetype.agroSpewy) return (HandRole.check, 'Agro: no farolear; inducir.');

    if (street == Street.turn) {
      final equity = tier == HandTier.highEquityComboDraw || h.gutshot && h.overcards || h.oesd || h.flushDraw;
      if (equity) return (HandRole.bluff, 'Semi-bluff con Equity_Retained (${_draws(h)}).');
      if (shift == CardShift.rankShift && init) return (HandRole.bluff, 'Rank_Shift: barrel de alta frecuencia sin equidad (presión a pares medios).');
      if (factor >= 2 && (tier == HandTier.backdoorBlockerBluff)) return (HandRole.bluff, 'Capado + factor 2.0: barrel con backdoors/blockers.');
      if (shift == CardShift.flushOrStraightCompletes && h.flushSuitBlocker && (f.isCapped || read.archetype == GgArchetype.scaredMoneyReg)) {
        return (HandRole.bluff, 'Nut blocker en carta que completa vs rango débil: farol polarizado.');
      }
      return (HandRole.check, 'Sin equidad ni blockers: give up.');
    }

    final kb = keyBlockers(s, h);
    if (kb.$1 && !kb.$2) return (HandRole.bluff, 'Farol river: ${kb.$3}; no bloquea su rango de fold.');
    if (factor >= 2 && !kb.$2) return (HandRole.bluff, 'Factor 2.0 vs capado: bottom del rango sin bloquear sus folds.');
    return (HandRole.check, kb.$2 ? 'Bloqueamos su rango de fold (proyecto fallido): no farol.' : 'Sin key blockers: give up.');
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
    if (p.role == HandRole.thinValue) pct = math.min(math.max(pct, 50), 66);
    final bb = p.allIn && p.role != HandRole.thinValue ? stack : math.min(stack, pot * pct / 100);
    return DecisionOutput(
      action: DecisionAction.betRaise,
      sizing: Sizing(bb: bb, potPct: bb / pot * 100),
      metrics: metrics,
      justificacionGto: gto,
      ajusteExplotativoRead: readTxt,
    );
  }
}
