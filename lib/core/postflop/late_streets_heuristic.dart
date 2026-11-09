import '../evaluators/board_analyzer.dart';
import '../models/game_state.dart';
import 'geometry.dart';
import 'hand_tier.dart';

enum TurnCardClass { blank, scareCardPfa, drawCompleting }

enum LateAction { check, bet }

class LatePlan {
  const LatePlan(this.action, this.sizePct, this.reason, {this.allIn = false});
  final LateAction action;
  final double sizePct;
  final String reason;
  final bool allIn;
}

class TurnEngine {
  TurnEngine._();

  static TurnCardClass classify(List<Card> flop, Card turn) {
    final f = BoardAnalyzer.analyze(flop, pfa: Position.btn, defender: Position.bb);
    final t = BoardAnalyzer.analyze([...flop, turn], pfa: Position.btn, defender: Position.bb);
    final flushNow = t.maxSuitCount >= 3 && f.maxSuitCount < 3;
    final straightNow = t.straightWindows > f.straightWindows;
    if (flushNow || straightNow) return TurnCardClass.drawCompleting;
    final top = flop.map((c) => c.rank.value).reduce((a, b) => a > b ? a : b);
    if (turn.rank.value >= Rank.king.value && turn.rank.value > top) return TurnCardClass.scareCardPfa;
    return TurnCardClass.blank;
  }

  /// Hero con iniciativa (apostó flop) y sin apuesta enfrente.
  static LatePlan withInitiative(TurnCardClass c, HandTierResult h, {required double pot, required double stack}) {
    final tier = h.tier;
    switch (c) {
      case TurnCardClass.blank:
        final g = PotGeometry.geometricFraction(pot, stack, 2).clamp(0.66, 0.75) * 100;
        final barrel = tier == HandTier.nutsMonster || tier == HandTier.highEquityComboDraw;
        return barrel
            ? LatePlan(LateAction.bet, g, 'Blank: ventaja del flop intacta; double barrel geométrico (2 calles) con value + draws de alta equity.')
            : LatePlan(LateAction.check, 0, 'Blank: 1 par/air sin equity => check (pot control / give up).');
      case TurnCardClass.scareCardPfa:
        final bet = tier != HandTier.airGiveUp && tier != HandTier.marginalMadeShowdown;
        return bet
            ? const LatePlan(LateAction.bet, 33, 'Scare card A/K: mejora el rango del PFA (más Ax/Kx); barrel pequeño de rango.')
            : const LatePlan(LateAction.check, 0, 'Scare card: showdown marginal/air sin equity => check.');
      case TurnCardClass.drawCompleting:
        final polar = tier == HandTier.nutsMonster || h.nutFlushDraw;
        return polar
            ? const LatePlan(LateAction.bet, 75, 'Carta completa proyectos: apuesta solo polarizada (nuts / nut draw).')
            : const LatePlan(LateAction.check, 0, 'Carta completa proyectos: check con 1 par (control de bote; el rango del caller mejora).');
    }
  }
}

class RiverEngine {
  RiverEngine._();

  static bool flushCompleted(List<Card> board) {
    final c = List<int>.filled(4, 0);
    for (final x in board) {
      c[x.suit.index]++;
    }
    return c.any((n) => n >= 3);
  }

  /// Hero sin apuesta enfrente.
  static LatePlan act(HandTierResult h, List<Card> board,
      {required double pot, required double stack, required bool hadInitiative, required bool inPosition, required VillainProfile vp}) {
    final spr = PotGeometry.spr(stack, pot);
    final fc = flushCompleted(board);
    switch (h.tier) {
      case HandTier.nutsMonster:
        if (spr <= 1.25) return const LatePlan(LateAction.bet, 0, 'Monster con SPR <= 1.25 => all-in.', allIn: true);
        if (fc && hadInitiative) {
          return const LatePlan(LateAction.bet, 125, 'Monster en board de color completado con iniciativa: overbet 125% polar.');
        }
        return LatePlan(LateAction.bet, vp == VillainProfile.callingStation ? 100 : 75, 'Monster: value bet polar.');
      case HandTier.strongTopPairOverpair:
        return inPosition || vp == VillainProfile.callingStation
            ? const LatePlan(LateAction.bet, 50, 'Top pair/overpair: thin value (rango del rival llega con peores pares).')
            : const LatePlan(LateAction.check, 0, 'Top pair OOP: check (bluff-catch) para no aislarse vs mejores.');
      case HandTier.marginalMadeShowdown:
        return const LatePlan(LateAction.check, 0, 'Showdown marginal: check.');
      case HandTier.highEquityComboDraw:
      case HandTier.backdoorBlockerBluff:
      case HandTier.airGiveUp:
        final blockerBluff = hadInitiative && fc && h.flushSuitBlocker && vp != VillainProfile.callingStation;
        if (blockerBluff) {
          return spr <= 1.25
              ? const LatePlan(LateAction.bet, 0, 'Bluff con blocker de nut flush y SPR bajo: all-in.', allIn: true)
              : const LatePlan(LateAction.bet, 125, 'Bluff overbet 125%: bloqueamos el nut flush (reduce combos de call del rival).');
        }
        return const LatePlan(LateAction.check, 0, 'Air sin blockers relevantes: give up.');
    }
  }

  /// Bluff-catch: pagar si no bloqueamos los proyectos fallidos del rival.
  static bool blocksVillainBluffs(HandTierResult h, List<Card> board) =>
      !flushCompleted(board) && h.heroFlushSuitCards > 0;
}
