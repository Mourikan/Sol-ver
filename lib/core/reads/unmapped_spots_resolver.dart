import '../evaluators/board_analyzer.dart';
import '../models/decision_output.dart';
import '../models/game_state.dart';
import '../postflop/defense_budget.dart';
import '../postflop/hand_tier.dart';
import '../postflop/turn_river_solver.dart';
import 'anti_counter_exploit_shield.dart';
import 'gg_profiler.dart';

/// Hechos de línea (detección O(acciones)) para los 5 spots no cubiertos y los presets sin HUD.
class LineFacts {
  const LineFacts({
    this.microBet = false,
    this.villainBetFrac = 0,
    this.pfaMissedCbet = false,
    this.villainCheckedBackTurnWithInitiative = false,
    this.bustedRunout = false,
    this.villainBetRiver = false,
    this.bigRiverBetMicro = false,
    this.completedDrawAggression = false,
    this.threeBetBigCbetHighBoard = false,
    this.threeBetSmallCbetHighBoard = false,
    this.villainLimpCalled = false,
    this.floatAndStab = false,
  });
  final bool microBet;
  final double villainBetFrac;
  final bool pfaMissedCbet, villainCheckedBackTurnWithInitiative, bustedRunout, villainBetRiver, bigRiverBetMicro;
  final bool completedDrawAggression, threeBetBigCbetHighBoard, threeBetSmallCbetHighBoard, villainLimpCalled, floatAndStab;
}

/// Plan de acción de un spot no cubierto + contexto de EV (prior) compartido con el ancla.
class SpotPlan {
  const SpotPlan(this.name, this.action, this.why, {this.sizePct, this.raiseMult, this.bluffShare, this.foldEquityOverride, this.raiseToBb});
  final String name;
  final DecisionAction action;
  final String why;
  final double? sizePct, raiseMult, bluffShare, foldEquityOverride, raiseToBb;
}

class UnmappedSpotsResolver {
  UnmappedSpotsResolver._();

  static const microLo = 0.10, microHi = 0.22;
  static const microRaiseMult = 3.8; // Raise_Punish 3.5x-4.2x (punto medio)
  static const probePct = 70.0; // Turn_Probe_Attack 66-75%
  static const isoIpBase = 3.5, isoIpPerLimper = 1.2, isoOopBase = 4.5, isoOopPerLimper = 1.5;
  static const limpCallerTop = ['AA', 'KK', 'QQ', 'JJ', 'AKs', 'AKo'];
  static const underpairBigBluffShare = 0.10;

  static double isoSize({required bool ip, required int limpers}) =>
      ip ? isoIpBase + isoIpPerLimper * limpers : isoOopBase + isoOopPerLimper * limpers;

  static List<PlayerAction> _st(GameState s, Street st) => [for (final a in s.actions) if (a.street == st) a];

  static bool villainLimped(GameState s) {
    final v = s.villainPosition;
    if (v == null) return false;
    for (final a in _st(s, Street.preflop)) {
      if (a.isAggressive && a.actor != v) return false;
      if (a.actor == v) return a.type == ActionType.call && a.amountBb <= 1.0;
    }
    return false;
  }

  static bool _highOrDry(List<Card> flop) {
    final m = BoardAnalyzer.analyze(flop, pfa: Position.btn, defender: Position.bb);
    final top = flop.map((c) => c.rank).reduce((a, b) => a.value >= b.value ? a : b);
    return top == Rank.ace || top == Rank.king || m.connectivity == Connectivity.dry;
  }

  static bool _coordinatedFlop(List<Card> flop) {
    final m = BoardAnalyzer.analyze(flop, pfa: Position.btn, defender: Position.bb);
    return m.suitTexture == SuitTexture.twoTone || m.connectivity == Connectivity.wet || m.connectivity == Connectivity.dynamic;
  }

  static bool _brick(GameState s, int len) =>
      CardShiftMatrix.classify(s.board.sublist(0, len - 1), s.board[len - 1]) != CardShift.flushOrStraightCompletes;

  /// Palo del proyecto de color fallido (2 cartas del palo en el flop y ninguna más); -1 si no hay.
  static int missedFlushSuit(GameState s) {
    if (s.board.length < 5) return -1;
    final flopSuits = List<int>.filled(4, 0), all = List<int>.filled(4, 0);
    for (var i = 0; i < 5; i++) {
      if (i < 3) flopSuits[s.board[i].suit.index]++;
      all[s.board[i].suit.index]++;
    }
    for (var k = 0; k < 4; k++) {
      if (flopSuits[k] == 2 && all[k] == 2) return k;
    }
    return -1;
  }

  /// Hero tiene cartas del palo del proyecto fallido => bloquea los faroles del villano.
  static bool heroBlocksBustedDraw(GameState s) {
    final k = missedFlushSuit(s);
    return k >= 0 && s.hero != null && (s.hero!.high.suit.index == k || s.hero!.low.suit.index == k);
  }

  /// Apuesta del villano que lidera contra la iniciativa de Hero en la calle (donk).
  static bool isDonk(GameState s) {
    final cur = _st(s, s.street);
    final first = cur.where((a) => a.isAggressive).firstOrNull;
    if (first == null || first.actor != s.villainPosition) return false;
    final prev = s.street == Street.flop ? Street.preflop : Street.values[s.street.index - 1];
    final heroAgg = prev == Street.preflop
        ? s.preflopAggressor == s.heroPosition
        : _st(s, prev).where((a) => a.isAggressive).lastOrNull?.actor == s.heroPosition;
    return heroAgg && cur.indexOf(first) == cur.indexWhere((a) => a.actor == s.villainPosition);
  }

  static LineFacts facts(GameState s, {required double potBefore, required double toCall}) {
    final v = s.villainPosition!, hero = s.heroPosition;
    final pfa = s.preflopAggressor;
    final st = s.street;
    final frac = toCall > 0 && potBefore > 0 ? toCall / potBefore : 0.0;
    final cur = _st(s, st);
    final vBetNow = cur.where((a) => a.actor == v && a.isAggressive).lastOrNull;
    final flopActs = _st(s, Street.flop);
    final flopChecked = flopActs.isNotEmpty && flopActs.every((a) => a.type == ActionType.check);
    final turnActs = _st(s, Street.turn);
    final flop = s.board.length >= 3 ? s.board.sublist(0, 3) : const <Card>[];
    final pfaMissed = pfa == v && st.index >= Street.turn.index && flopChecked && flop.isNotEmpty && _highOrDry(flop);
    final turnCheckBack = pfa == v && st == Street.river && turnActs.isNotEmpty &&
        turnActs.every((a) => a.type == ActionType.check) && _highOrDry(flop) &&
        flopActs.any((a) => a.actor == v && a.isAggressive);
    final busted = s.board.length == 5 && flop.isNotEmpty && _coordinatedFlop(flop) && _brick(s, 4) && _brick(s, 5) && missedFlushSuit(s) >= 0;
    final betRiver = st == Street.river && vBetNow != null;
    final villainLine = _st(s, Street.flop).any((a) => a.actor == v) && _st(s, Street.turn).any((a) => a.actor == v && a.type != ActionType.check);
    final completes = s.board.length >= 4 && !_brick(s, s.board.length) && vBetNow != null;
    final cbet = flopActs.where((a) => a.actor == v && a.isAggressive).firstOrNull;
    final pots = DefenseBudget.potsByStreet(s);
    final flopPot = pots[Street.flop] ?? 0;
    final cbetFrac = cbet == null || flopPot <= 0 ? 0.0 : cbet.amountBb / flopPot;
    final highAK = flop.isNotEmpty && flop.any((c) => c.rank == Rank.ace || c.rank == Rank.king);
    final threeBp = s.potType == PotType.threeBet && pfa == v && highAK;
    final heroCbetCalled = flopActs.any((a) => a.actor == hero && a.isAggressive) &&
        flopActs.any((a) => a.actor == v && a.type == ActionType.call);
    final float = st == Street.turn && hero == pfa && !hero.isInPositionVs(v) && heroCbetCalled && cbet == null &&
        turnActs.any((a) => a.actor == hero && a.type == ActionType.check) && vBetNow != null;
    return LineFacts(
      microBet: frac >= microLo && frac <= microHi && vBetNow != null,
      villainBetFrac: frac,
      pfaMissedCbet: pfaMissed,
      villainCheckedBackTurnWithInitiative: turnCheckBack,
      bustedRunout: busted && villainLine,
      villainBetRiver: betRiver,
      bigRiverBetMicro: betRiver && frac >= 0.90 && s.stake.index <= Stake.nl50.index,
      completedDrawAggression: completes,
      threeBetBigCbetHighBoard: threeBp && cbetFrac >= 0.65 && s.stake.index <= Stake.nl50.index,
      threeBetSmallCbetHighBoard: threeBp && cbet != null && cbetFrac <= 0.34,
      villainLimpCalled: villainLimped(s),
      floatAndStab: float,
    );
  }

  /// Plan de acción de los 5 spots (nunca vs Reg_GTO ni multiway). null => pipeline normal.
  static SpotPlan? plan(GameState s, ReadProfile r, HandTierResult h, {required double potBefore, required double toCall}) {
    if (r.archetype == GgArchetype.unknownReg || s.activeVillains.length >= 2 || s.potType == PotType.fourBetPlus) return null;
    final f = facts(s, potBefore: potBefore, toCall: toCall);
    final t = h.tier;
    final value = t == HandTier.nutsMonster || t == HandTier.strongTopPairOverpair;
    final micro = s.stake.index <= Stake.nl50.index;
    // 4. ThreeBet_Pot_Underpair_Pain_Guard (TT-QQ bajo A/K en 3BP).
    final under = s.hero!.isPair && s.hero!.high.rank.value >= Rank.ten.value && s.hero!.high.rank.value <= Rank.queen.value &&
        s.board.take(3).any((c) => c.rank.value > s.hero!.high.rank.value);
    if (under && toCall > 0 && s.potType == PotType.threeBet && s.preflopAggressor == s.villainPosition &&
        !AntiCounterExploitShield.active(s.stake, r)) {
      if (s.street == Street.flop && f.threeBetBigCbetHighBoard) {
        return const SpotPlan('ThreeBet_Underpair_Pain_Guard', DecisionAction.fold,
            'Nutted_Ax_Commitment: c-bet >= 65% en A/K-x-x (3BP, NL2-NL50) => aire < 10% => Immediate_Flop_Fold.',
            bluffShare: underpairBigBluffShare);
      }
      if (s.street == Street.flop && f.threeBetSmallCbetHighBoard) {
        return const SpotPlan('ThreeBet_Underpair_Pain_Guard', DecisionAction.call, 'Range_CBet_Wide (<= 33%): call flop y re-evaluar en turn.');
      }
      if (s.street == Street.turn && micro && f.villainBetFrac >= 0.60) {
        return const SpotPlan('ThreeBet_Underpair_Pain_Guard', DecisionAction.fold, '2º barril >= 60% en 3BP (NL2-NL50): fold del underpair.',
            bluffShare: underpairBigBluffShare);
      }
    }
    // 1. Micro_Block_And_MinBet_Punisher (los min-donks contra nuestra iniciativa los resuelve DonkTellDecoder).
    if (f.microBet && !isDonk(s)) {
      final (blocks, _, _) = s.street == Street.flop ? (false, false, '') : TurnRiverSolver.keyBlockers(s, h);
      if (value || t == HandTier.highEquityComboDraw || (blocks && t == HandTier.backdoorBlockerBluff)) {
        return SpotPlan('Micro_Block_Punisher', DecisionAction.betRaise,
            'Apuesta ${(f.villainBetFrac * 100).round()}% pot => Capped_Block_Or_Draw_Price: Raise_Punish ${microRaiseMult}x.',
            raiseMult: microRaiseMult);
      }
    }
    // 3. Busted_Draw_Runout_Analyzer: actúa sobre el rango percibido (preset +/-14pp) y desactiva el truncado de T2; la
    // decisión call/fold la toma el Bluff_Combo_Audit por combos reales (ya cuenta unblockers/blockers del proyecto).
    // 2. PFA_Missed_CBet_Cap_Detector => Turn_Probe_Attack / River_Follow_Up.
    if (toCall == 0 && f.pfaMissedCbet && !s.heroPosition.isInPositionVs(s.villainPosition!) &&
        _st(s, s.street).where((a) => a.actor == s.villainPosition).isEmpty) {
      final follow = s.street == Street.river && _st(s, Street.turn).any((a) => a.actor == s.heroPosition && a.isAggressive);
      final ok = s.street == Street.turn
          ? (value || t == HandTier.highEquityComboDraw || t == HandTier.marginalMadeShowdown)
          : follow && (value || (t != HandTier.marginalMadeShowdown && TurnRiverSolver.keyBlockers(s, h).$1));
      if (ok) {
        return SpotPlan('PFA_Missed_CBet_Cap', DecisionAction.betRaise,
            '${s.street == Street.turn ? 'Turn_Probe_Attack' : 'River_Follow_Up'} ${probePct.round()}%: PFA pasó flop seco/alto => rango capado (nuts x0.2).',
            sizePct: probePct);
      }
    }
    return null;
  }
}
