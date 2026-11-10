import 'dart:math' as math;

import '../models/game_state.dart';
import '../postflop/defense_budget.dart';
import '../postflop/geometry.dart';
import '../postflop/hand_tier.dart';
import '../preflop/range_notation.dart';
import '../reads/gg_profiler.dart';
import '../reads/mda_consensus_db.dart';
import 'board_history.dart';
import 'timing_tells_matrix.dart';

enum AuditVerdict { heroFoldDisciplined, heroCallApproved, foldNegativeEv, callWithinThreshold }

enum VillainLineNode { standard, riverRaise, turnCheckRaise, tripleBarrelOverbet, xcXcThenAggressionRiver }

class BluffAudit {
  const BluffAudit({
    required this.verdict,
    required this.potOddsReq,
    required this.availableBluffs,
    required this.realBluffRatio,
    required this.valueCombos,
    required this.bluffCombos,
    required this.categories,
    required this.node,
    required this.reasons,
  });

  final AuditVerdict verdict;
  final double potOddsReq;

  /// Bluff_Ratio_Effective (tras card removal de Hero, ajustes MDA/timing con piso y read).
  final double availableBluffs;

  /// Active_Bluff_Combos / (Active_Value_Combos + Active_Bluff_Combos) sin selección del villano.
  final double realBluffRatio;
  final double valueCombos;
  final double bluffCombos;
  final List<String> categories;
  final VillainLineNode node;
  final List<String> reasons;

  bool get allowsCall => verdict == AuditVerdict.heroCallApproved || verdict == AuditVerdict.callWithinThreshold;
}

/// Bluff_Combo_Audit (SOLO RIVER): conteo real de combos del rango del villano filtrado por su línea.
class BluffCatchAuditor {
  BluffCatchAuditor._();

  /// Sub-farol MDA del pool NL2-NL50 en nodos agresivos (12-18% => punto medio), aplicado a combos de farol.
  static const mdaUnderBluff = MDAParameters.riverRaiseBluffDeficit;
  static const adjustmentFloor = 0.5;
  static const collapseThreshold = 0.6;
  static const agroRatioMultiplier = 1.4;
  static const agroFloorOverOdds = 0.05;

  static VillainLineNode lineOf(GameState s) {
    final v = s.villainPosition!, h = s.heroPosition;
    List<PlayerAction> on(Street st, Position p) => s.actions.where((a) => a.street == st && a.actor == p).toList();
    bool xc(Street st) {
      final va = on(st, v);
      return va.length >= 2 && va.first.type == ActionType.check && va.any((a) => a.type == ActionType.call);
    }
    bool aggr(Street st, Position p) => on(st, p).any((a) => a.isAggressive);

    final street = s.street;
    if (street == Street.river && xc(Street.flop) && xc(Street.turn) && aggr(Street.river, v)) {
      return VillainLineNode.xcXcThenAggressionRiver;
    }
    if (street == Street.river && aggr(Street.river, h) && aggr(Street.river, v)) return VillainLineNode.riverRaise;
    if (street == Street.turn && on(Street.turn, v).firstOrNull?.type == ActionType.check && aggr(Street.turn, v)) {
      return VillainLineNode.turnCheckRaise;
    }
    if (street == Street.river && aggr(Street.flop, v) && aggr(Street.turn, v)) {
      final rb = on(Street.river, v).where((a) => a.isAggressive).lastOrNull;
      if (rb != null && rb.amountBb >= (s.potBb ?? double.infinity)) return VillainLineNode.tripleBarrelOverbet;
    }
    return VillainLineNode.standard;
  }

  /// Peso de supervivencia de un combo según la acción del villano en una calle (filtro de RangeFunnel por combos).
  static double _lineWeight(HandTier t, {required bool bet, required bool called, required bool checkedThrough}) {
    if (bet) {
      return switch (t) {
        HandTier.marginalMadeShowdown || HandTier.airGiveUp => 0.4,
        HandTier.backdoorBlockerBluff => 0.6,
        _ => 1.0,
      };
    }
    if (called) {
      return switch (t) {
        HandTier.airGiveUp => 0.0,
        HandTier.backdoorBlockerBluff => 0.5,
        HandTier.nutsMonster => 0.6,
        _ => 1.0,
      };
    }
    if (checkedThrough) return t == HandTier.nutsMonster ? 0.5 : 1.0;
    return 1.0;
  }

  static BluffAudit audit(GameState s, ReadProfile read, {required double pot, required double call, required bool heroHasNuts}) {
    if (s.street != Street.river) throw StateError('Bluff_Combo_Audit es exclusivo del River');
    final vRange = DefenseBudget.villainPreflopRange(s);
    final hist = BoardHistory(s.board, villainRange: vRange);
    final node = lineOf(s);
    final potOdds = PotGeometry.potOdds(call, pot + call);
    final gto = call / (pot + 2 * call);
    final reasons = <String>[];
    final v = s.villainPosition!;
    final ids = [for (final c in s.board) c.id];
    final boardDead = ids.fold<int>(0, (m, c) => m | (1 << c));
    final heroMask = (1 << s.hero!.high.id) | (1 << s.hero!.low.id);
    final riverBet = s.actions.where((a) => a.street == Street.river && a.actor == v && a.isAggressive).lastOrNull;
    final isRaise = node == VillainLineNode.riverRaise || node == VillainLineNode.xcXcThenAggressionRiver;
    final bigBet = riverBet != null && riverBet.amountBb > pot * 0.75;

    var vB = 0.0, bB = 0.0, vW = 0.0, bW = 0.0, missFd = 0.0, missSd = 0.0, air = 0.0;
    final bluffList = <(double, double, bool)>[];
    for (var i = 0; i < 169; i++) {
      final w0 = vRange[i];
      if (w0 <= 0) continue;
      for (final (a, b) in Matrix169.concreteCombos(i)) {
        final m = (1 << a) | (1 << b);
        if (boardDead & m != 0) continue;
        var w = w0.toDouble();
        HandTierResult? turnTier;
        for (final st in [Street.flop, Street.turn]) {
          final acts = s.actions.where((x) => x.street == st).toList();
          if (acts.isEmpty) continue;
          final t = HandTierClassifier.classify(a, b, ids.sublist(0, st == Street.flop ? 3 : 4));
          if (st == Street.turn) turnTier = t;
          final vActs = acts.where((x) => x.actor == v).toList();
          w *= _lineWeight(t.tier,
              bet: vActs.any((x) => x.isAggressive),
              called: vActs.any((x) => x.type == ActionType.call),
              checkedThrough: !acts.any((x) => x.isAggressive));
          if (w == 0) break;
        }
        if (w == 0) continue;
        final rt = HandTierClassifier.classify(a, b, ids).tier;
        final isValue = rt == HandTier.nutsMonster || (rt == HandTier.strongTopPairOverpair && !isRaise && !bigBet);
        final isBluff = rt == HandTier.airGiveUp || rt == HandTier.backdoorBlockerBluff || rt == HandTier.highEquityComboDraw;
        final blocked = heroMask & m != 0;
        if (isValue) {
          vB += w;
          if (!blocked) vW += w;
        } else if (isBluff) {
          bB += w;
          final tt = turnTier;
          final prio = tt != null && tt.flushDraw ? 3.0 : (tt != null && (tt.oesd || tt.gutshot) ? 2.0 : (rt == HandTier.backdoorBlockerBluff ? 1.5 : 1.0));
          bluffList.add((prio + ((a * 31 + b) % 97) / 1000, w, blocked));
          if (!blocked) {
            bW += w;
            if (prio >= 3) {
              missFd += w;
            } else if (prio >= 2) {
              missSd += w;
            } else {
              air += w;
            }
          }
        }
      }
    }

    final real = (bW + vW) == 0 ? 0.0 : bW / (bW + vW);
    final targetBluffs = math.min(bB, vB * gto / (1 - gto));
    bluffList.sort((x, y) => y.$1.compareTo(x.$1));
    var acc = 0.0, selectedUnblocked = 0.0;
    for (final (_, w, blocked) in bluffList) {
      if (acc >= targetBluffs) break;
      acc += w;
      if (!blocked) selectedUnblocked += w;
    }
    var adj = 1.0;
    final micro = s.stake.index <= Stake.nl50.index;
    final mdaNode = node != VillainLineNode.standard;
    final agro = read.archetype == GgArchetype.agroSpewy;
    if (micro && mdaNode && !agro) {
      adj *= 1 - mdaUnderBluff;
      reasons.add('MDA NL2-NL50: ${node.name} sub-faroleado ${(mdaUnderBluff * 100).round()}% (sobre combos)');
    }
    final t = TimingTellsMatrix.lastVillain(s);
    if (t.villainBluffMultiplier != 1.0 && !agro) {
      adj *= t.villainBluffMultiplier;
      reasons.add(t.note);
    }
    if (adj < adjustmentFloor) {
      adj = adjustmentFloor;
      reasons.add('Piso de ajuste ${(adjustmentFloor * 100).round()}% (sin multiplicadores ciegos)');
    }
    final b2 = selectedUnblocked * adj;
    var eff = (b2 + vW) == 0 ? 0.0 : b2 / (b2 + vW);
    reasons.add('Combos: valor ${vW.toStringAsFixed(1)} / farol ${bW.toStringAsFixed(1)} (real ${(real * 100).toStringAsFixed(1)}%) '
        '=> farol efectivo ${(eff * 100).toStringAsFixed(1)}% vs pot odds ${(potOdds * 100).toStringAsFixed(1)}%');
    if (hist.flushCompleted) reasons.add('Color completado: proyectos de color convertidos en valor');
    if (hist.straightCompleted) reasons.add('Escalera completada para OESD/gutshots reales del rango');
    if (node == VillainLineNode.xcXcThenAggressionRiver) reasons.add('Línea X/C -> X/C -> agresión river');
    if (agro) {
      eff = math.max(eff * agroRatioMultiplier, potOdds + agroFloorOverOdds);
      reasons.add('Read Agro_Spewy: max(real x$agroRatioMultiplier, pot odds + ${(agroFloorOverOdds * 100).round()}%)');
    }

    final cats = [
      if (missFd > 0) 'Missed_FD',
      if (missSd > 0) 'Missed_OESD',
      if (air > 0) 'Air_From_Flop',
    ];
    final hero = s.hero!;
    final blocksNuts = hist.heroBlocksNuts(hero);
    AuditVerdict verdict;
    if (eff < potOdds * collapseThreshold && !heroHasNuts && !blocksNuts) {
      verdict = AuditVerdict.heroFoldDisciplined;
      reasons.add('Faroles colapsan: efectivos < ${(collapseThreshold * 100).round()}% de pot odds => FOLD DISCIPLINADO (no inmolación)');
    } else if (eff + 1e-9 >= potOdds || heroHasNuts) {
      final unblocks = hist.drawSuit < 0 || ![hero.high, hero.low].any((c) => c.suit.index == hist.drawSuit);
      final valueBlocker = _valueBlocker(s);
      if (hist.brickOut && unblocks && valueBlocker != null) {
        verdict = AuditVerdict.heroCallApproved;
        reasons.add('Hero call: brick out + 0 cartas del proyecto fallido + blocker de valor $valueBlocker');
      } else {
        verdict = AuditVerdict.callWithinThreshold;
      }
    } else {
      verdict = AuditVerdict.foldNegativeEv;
      reasons.add('Faroles efectivos < pot odds: bluff-catcher -EV');
    }
    return BluffAudit(
      verdict: verdict,
      potOddsReq: potOdds,
      availableBluffs: eff,
      realBluffRatio: real,
      valueCombos: vW,
      bluffCombos: bW,
      categories: cats,
      node: node,
      reasons: reasons,
    );
  }

  static String? _valueBlocker(GameState s) {
    final ranks = {for (final c in s.board) c.rank.value}.toList()..sort((a, b) => b.compareTo(a));
    final top2 = ranks.take(2).toSet();
    for (final c in [s.hero!.high, s.hero!.low]) {
      if (top2.contains(c.rank.value)) return c.toString();
    }
    return null;
  }
}
