import '../models/game_state.dart';
import '../postflop/geometry.dart';
import '../reads/gg_profiler.dart';
import 'board_history.dart';
import 'timing_tells_matrix.dart';

enum AuditVerdict { heroFoldDisciplined, heroCallApproved, foldNegativeEv, callWithinThreshold }

enum VillainLineNode { standard, riverRaise, turnCheckRaise, tripleBarrelOverbet, xcXcThenAggressionRiver }

class BluffAudit {
  const BluffAudit({
    required this.verdict,
    required this.potOddsReq,
    required this.availableBluffs,
    required this.categories,
    required this.node,
    required this.reasons,
  });

  final AuditVerdict verdict;
  final double potOddsReq;

  /// Fracción estimada de faroles en el rango de apuesta del villano.
  final double availableBluffs;
  final List<String> categories;
  final VillainLineNode node;
  final List<String> reasons;

  bool get allowsCall => verdict == AuditVerdict.heroCallApproved || verdict == AuditVerdict.callWithinThreshold;
}

/// Bluff_Combo_Audit: filtro obligatorio para todo call en turn/river.
class BluffCatchAuditor {
  BluffCatchAuditor._();

  /// Sub-farol MDA del pool NL2-NL50 en nodos agresivos (12-18% => punto medio).
  static const mdaUnderBluff = 0.15;
  static const collapseThreshold = 0.6;
  static const agroBluffMultiplier = 1.5;

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

  static BluffAudit audit(GameState s, ReadProfile read, {required double pot, required double call, required bool heroHasNuts}) {
    final hist = BoardHistory(s.board);
    final node = lineOf(s);
    final potOdds = PotGeometry.potOdds(call, pot + call);
    final base = call / (pot + 2 * call);
    final reasons = <String>[];

    final cats = <String>[
      if (hist.missedFlushDraw) 'Missed_FD',
      if (hist.missedStraightDraw) 'Missed_OESD',
      if (node != VillainLineNode.xcXcThenAggressionRiver) 'Air_From_Flop',
    ];
    var bluffs = base * cats.length / 3;
    if (hist.flushCompleted) reasons.add('Color completado: Missed_FD colapsa');
    if (hist.straightCompleted) reasons.add('Escalera completada: Missed_OESD colapsa');
    if (node == VillainLineNode.xcXcThenAggressionRiver) reasons.add('Línea X/C -> X/C -> agresión river: sin aire');

    final micro = s.stake.index <= Stake.nl50.index;
    final mdaNode = node != VillainLineNode.standard;
    final agro = read.archetype == GgArchetype.agroSpewy;
    if (micro && mdaNode && !agro) {
      bluffs *= 1 - mdaUnderBluff;
      reasons.add('MDA NL2-NL50: ${node.name} sub-faroleado ${(mdaUnderBluff * 100).round()}%');
    }
    final t = TimingTellsMatrix.lastVillain(s);
    if (t.villainBluffMultiplier != 1.0) {
      bluffs *= t.villainBluffMultiplier;
      reasons.add(t.note);
    }
    if (agro) {
      bluffs *= agroBluffMultiplier;
      reasons.add('Read Agro_Spewy: sobre-farolea (x$agroBluffMultiplier)');
    }

    final hero = s.hero!;
    final blocksNuts = hist.heroBlocksNuts(hero);
    AuditVerdict v;
    if (bluffs < potOdds * collapseThreshold && !heroHasNuts && !blocksNuts) {
      v = AuditVerdict.heroFoldDisciplined;
      reasons.add('Faroles disponibles ${(bluffs * 100).toStringAsFixed(1)}% < ${(collapseThreshold * 100).round()}% de pot odds ${(potOdds * 100).toStringAsFixed(1)}% => FOLD DISCIPLINADO (no inmolación)');
    } else {
      final unblocks = hist.drawSuit < 0 || ![hero.high, hero.low].any((c) => c.suit.index == hist.drawSuit);
      final valueBlocker = _valueBlocker(s);
      if (hist.brickOut && unblocks && valueBlocker != null) {
        v = AuditVerdict.heroCallApproved;
        reasons.add('Hero call: brick out + 0 cartas del proyecto fallido + blocker de valor $valueBlocker');
      } else if (hist.brickOut && !unblocks) {
        v = AuditVerdict.foldNegativeEv;
        reasons.add('Bloqueamos sus faroles (cartas del proyecto fallido) => fold');
      } else if (micro && mdaNode && !agro && !heroHasNuts) {
        v = AuditVerdict.foldNegativeEv;
        reasons.add('Bluff-catcher puro en nodo MDA: -EV por defecto');
      } else if (bluffs >= potOdds * collapseThreshold) {
        v = AuditVerdict.callWithinThreshold;
        reasons.add('Faroles ${(bluffs * 100).toStringAsFixed(1)}% vs pot odds ${(potOdds * 100).toStringAsFixed(1)}%: call permitido');
      } else {
        v = AuditVerdict.foldNegativeEv;
      }
    }
    return BluffAudit(verdict: v, potOddsReq: potOdds, availableBluffs: bluffs, categories: cats, node: node, reasons: reasons);
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
