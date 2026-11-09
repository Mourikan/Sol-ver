// ignore_for_file: avoid_print
import 'dart:math';
import 'package:sol_ver/core/discipline/board_history.dart';
import 'package:sol_ver/core/discipline/bluff_catch_auditor.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/postflop/postflop_heuristic_engine.dart';
import 'package:sol_ver/core/postflop/postflop_ranges.dart';
import 'package:sol_ver/core/preflop/range_notation.dart';
import 'package:sol_ver/core/reads/gg_profiler.dart';

String cs(int id) => '${'23456789TJQKA'[id >> 2]}${'cdhs'[id & 3]}';
PlayerAction a(Street s, Position p, ActionType t, [double x = 0]) => PlayerAction(s, p, t, x);
const pre = [PlayerAction(Street.preflop, Position.btn, ActionType.raise, 2.5), PlayerAction(Street.preflop, Position.bb, ActionType.call, 2.5)];
const post = PostflopHeuristicEngine();

void main() {
  final reads = {
    'unknownReg': const ReadProfile(GgArchetype.unknownReg, []),
    'agro': const ReadProfile(GgArchetype.agroSpewy, []),
    'scared/ABC': const ReadProfile(GgArchetype.scaredMoneyReg, []),
  };
  final runouts = ['As7d2c5h9s', 'Kd8s3s4cJs', '9h8h4c2sTd', 'Qc7h2dKs3c', 'Ts9s6dKh2c'];
  for (final st in [Stake.nl10, Stake.nl100]) {
    final (_, bbR) = PostflopRanges.forPot(Position.btn, Position.bb, PotType.srp, st.rakeTier);
    for (final ro in runouts) {
      for (final re in reads.entries) {
        final b = Card.parseMany(ro);
        final dead = b.fold<int>(0, (m, c) => m | c.bit);
        double tot = 0, cF = 0, cT = 0, cR = 0;
        for (var i = 0; i < 169; i++) {
          if (bbR[i] <= 0) continue;
          for (final (x, y) in Matrix169.concreteCombos(i)) {
            if (dead & ((1 << x) | (1 << y)) != 0) continue;
            final h = HoleCards.parse(cs(x) + cs(y));
            tot++;
            final fl = [a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8)];
            final d1 = post.decide(GameState(stake: st, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 97.5, potBb: 5.5, hero: h, board: b.sublist(0, 3), actions: [...pre, ...fl]), read: re.value);
            if (d1.action == DecisionAction.fold) continue;
            cF++;
            final tu = [a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 6.8)];
            final fl2 = [...fl, a(Street.flop, Position.bb, ActionType.call, 1.8)];
            final d2 = post.decide(GameState(stake: st, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 95.7, potBb: 9.1, hero: h, board: b.sublist(0, 4), actions: [...pre, ...fl2, ...tu]), read: re.value);
            if (d2.action == DecisionAction.fold) continue;
            cT++;
            final tu2 = [...tu, a(Street.turn, Position.bb, ActionType.call, 6.8)];
            final d3 = post.decide(GameState(stake: st, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 88.9, potBb: 22.7, hero: h, board: b, actions: [...pre, ...fl2, ...tu2, a(Street.river, Position.bb, ActionType.check), a(Street.river, Position.btn, ActionType.bet, 22.7)]), read: re.value);
            if (d3.action != DecisionAction.fold) cR++;
          }
        }
        print('${st.name} $ro ${re.key.padRight(10)} flop33 cont ${(cF / tot * 100).toStringAsFixed(1)}% (MDF 75) | turn75 cont ${(cT / max(cF, 1) * 100).toStringAsFixed(1)}% (MDF 57) | river100 cont ${(cR / max(cT, 1) * 100).toStringAsFixed(1)}% (MDF 50) | total ${(cR / tot * 100).toStringAsFixed(1)}%');
      }
    }
  }

  // Runout stats
  final rnd = Random(7);
  var n = 0, fc = 0, sc = 0, brick = 0, zeroCats = 0, oneCat = 0, foldDisc = 0;
  for (var k = 0; k < 4000; k++) {
    final deck = List.generate(52, (i) => i)..shuffle(rnd);
    final b = [for (final id in deck.take(5)) Card(Rank.values[id >> 2], Suit.values[id & 3])];
    final hb = BoardHistory(b);
    n++;
    if (hb.flushCompleted) fc++;
    if (hb.straightCompleted) sc++;
    if (hb.brickOut) brick++;
    final cats = (hb.missedFlushDraw ? 1 : 0) + (hb.missedStraightDraw ? 1 : 0);
    if (cats == 0) zeroCats++;
    if (cats == 1) oneCat++;
    final heroIds = deck.skip(5).take(2).toList();
    final hc = HoleCards(Card(Rank.values[heroIds[0] >> 2], Suit.values[heroIds[0] & 3]), Card(Rank.values[heroIds[1] >> 2], Suit.values[heroIds[1] & 3]));
    final s = GameState(stake: Stake.nl25, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 85, potBb: 21.5, hero: hc, board: b,
        actions: [...pre, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 2), a(Street.flop, Position.bb, ActionType.call, 2),
          a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 6), a(Street.turn, Position.bb, ActionType.call, 6),
          a(Street.river, Position.bb, ActionType.bet, 16)]);
    if (BluffCatchAuditor.audit(s, const ReadProfile(GgArchetype.agroSpewy, []), pot: 21.5, call: 16, heroHasNuts: false).verdict == AuditVerdict.heroFoldDisciplined) foldDisc++;
  }
  print('RUNOUTS n=$n flushCompleted ${(fc / n * 100).toStringAsFixed(1)}% straightCompleted ${(sc / n * 100).toStringAsFixed(1)}% brickOut ${(brick / n * 100).toStringAsFixed(1)}% drawCats0 ${(zeroCats / n * 100).toStringAsFixed(1)}% drawCats1 ${(oneCat / n * 100).toStringAsFixed(1)}%');
  print('XC-XC-donk river vs AGRO (75% pot): heroFoldDisciplined en ${(foldDisc / n * 100).toStringAsFixed(1)}% de runouts aleatorios');
}
