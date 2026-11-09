import 'dart:typed_data';

import '../evaluators/board_analyzer.dart';
import '../evaluators/hand_evaluator.dart';
import '../models/decision_output.dart';
import '../models/game_state.dart';
import '../preflop/range_notation.dart';
import 'hand_tier.dart';

/// Botes 4-bet (SPR 1.0-2.5): rangos de llegada propios, c-bet pequeño de alta frecuencia en boards secos/altos
/// y umbrales de commit/call-off para overpairs JJ+ y TPTK.
class FourBetPotSolver {
  FourBetPotSolver._();

  /// 4-bettor: valor + blockers (A5s-A4s IP/OOP, KQs como blocker de AK/KK).
  static const fourBettor = 'QQ+,AKs,AKo,A5s,A4s,KQs:0.5';

  /// Caller del 4-bet (3-bettor que paga): pares altos/medios, AK, AQs, KQs.
  static const fourBetCaller = 'QQ-JJ,TT:0.5,AKs,AKo,AQs,KQs:0.5';

  static Float32List get fourBettorRange => RangeNotation.parse(fourBettor);
  static Float32List get callerRange => RangeNotation.parse(fourBetCaller);

  static const smallCbetPct = 22.0;

  static bool dryOrHigh(List<Card> flop) {
    final m = BoardAnalyzer.analyze(flop, pfa: Position.btn, defender: Position.bb);
    return m.connectivity.index <= Connectivity.semiWet.index || m.height == BoardHeight.high;
  }

  /// Commit / call-off: overpair JJ+ o top pair top kicker (AK en A/K-high), o mejor.
  static bool commitHand(HoleCards hero, List<Card> board, HandTierResult h) {
    if (h.tier == HandTier.nutsMonster) return true;
    final top = board.map((c) => c.rank.value).reduce((a, b) => a > b ? a : b);
    if (hero.isPair && hero.high.rank.value >= Rank.jack.value && hero.high.rank.value > top) return true;
    final ranks = {hero.high.rank.value, hero.low.rank.value};
    final tptk = ranks.contains(top) && (ranks.contains(Rank.ace.value) || (top == Rank.ace.value && ranks.contains(Rank.king.value)));
    return tptk;
  }

  static DecisionOutput decide(GameState s, HandTierResult h,
      {required double pot, required double stack, required double toCall, required double potBeforeBet, required bool heroIsPfa}) {
    final spr = stack / (toCall > 0 ? potBeforeBet + toCall : pot);
    final commit = commitHand(s.hero!, s.board, h);
    final tag = '4BP | SPR ${spr.toStringAsFixed(2)} | ${h.tier.name}${commit ? ' | commit (JJ+/TPTK+)' : ''}';
    if (toCall > 0) {
      if (commit) {
        final jam = spr <= 2.5;
        return DecisionOutput(
          action: jam ? DecisionAction.betRaise : DecisionAction.call,
          sizing: Sizing(bb: jam ? stack : toCall, potPct: (jam ? stack : toCall) / potBeforeBet * 100),
          justificacionGto: '$tag | call-off: SPR <= 2.5 compromete el stack con overpair JJ+/TPTK',
          ajusteExplotativoRead: jam ? 'Jam (SPR comprometido).' : 'Call.',
        );
      }
      final eqOuts = h.flushDraw || h.oesd;
      final odds = toCall / (potBeforeBet + 2 * toCall);
      return eqOuts && odds < 0.36
          ? DecisionOutput(
              action: DecisionAction.call,
              sizing: Sizing(bb: toCall, potPct: toCall / potBeforeBet * 100),
              justificacionGto: '$tag | draw con pot odds ${(odds * 100).round()}% (SPR bajo: equity directa)',
              ajusteExplotativoRead: 'Call.')
          : DecisionOutput(
              action: DecisionAction.fold,
              justificacionGto: '$tag | sin commit ni equity suficiente vs rango 4BP (QQ+/AK)',
              ajusteExplotativoRead: 'Fold.');
    }
    if (s.street == Street.flop && heroIsPfa) {
      final small = dryOrHigh(s.board.sublist(0, 3));
      final bet = small ? h.tier != HandTier.airGiveUp || h.flushSuitBlocker : (commit || h.flushDraw || h.oesd);
      final size = small ? smallCbetPct : 40.0;
      final bb = (pot * size / 100).clamp(0, stack).toDouble();
      return bet
          ? DecisionOutput(
              action: DecisionAction.betRaise,
              sizing: Sizing(bb: bb, potPct: bb / pot * 100),
              freqGto: {DecisionAction.betRaise: small ? 0.85 : 0.5, DecisionAction.check: small ? 0.15 : 0.5},
              freqSource: FreqSource.modelCalibrated,
              justificacionGto: '$tag | c-bet ${size.round()}% ${small ? 'de alta frecuencia (board seco/alto: RA+NA del 4-bettor)' : 'polar en board dinámico'}',
              ajusteExplotativoRead: 'SPR bajo: sizing pequeño compromete stacks en 2 calles.')
          : DecisionOutput(
              action: DecisionAction.check,
              justificacionGto: '$tag | check (sin valor/equity en board ${small ? 'seco' : 'dinámico'})',
              ajusteExplotativoRead: 'Check.');
    }
    final cat = HandEvaluator.category(HandEvaluator.evaluate([s.hero!.high.id, s.hero!.low.id, for (final c in s.board) c.id]));
    if (commit || cat >= HandEvaluator.twoPair) {
      return DecisionOutput(
          action: DecisionAction.betRaise,
          sizing: Sizing(bb: stack, potPct: stack / pot * 100),
          justificacionGto: '$tag | jam: mano de commit con SPR <= 2.5',
          ajusteExplotativoRead: 'All-in.');
    }
    return DecisionOutput(action: DecisionAction.check, justificacionGto: '$tag | check/fold sin commit', ajusteExplotativoRead: 'Check.');
  }
}
