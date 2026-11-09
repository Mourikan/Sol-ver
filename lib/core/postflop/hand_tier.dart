import '../evaluators/hand_evaluator.dart';

enum HandTier {
  nutsMonster,
  strongTopPairOverpair,
  marginalMadeShowdown,
  highEquityComboDraw,
  backdoorBlockerBluff,
  airGiveUp,
}

class HandTierResult {
  const HandTierResult(this.tier,
      {required this.flushDraw,
      required this.nutFlushDraw,
      required this.oesd,
      required this.gutshot,
      required this.backdoorFlush,
      required this.overcards,
      required this.flushSuitBlocker,
      required this.heroFlushSuitCards});

  final HandTier tier;
  final bool flushDraw;
  final bool nutFlushDraw;
  final bool oesd;
  final bool gutshot;
  final bool backdoorFlush;
  final bool overcards;

  /// Hero tiene el As (o la carta más alta libre) del palo con >=2 cartas en el board.
  final bool flushSuitBlocker;

  /// Cartas de Hero del palo dominante del board (bloquea proyectos fallidos del rival).
  final int heroFlushSuitCards;
}

/// Cartas como enteros rank*4+suit (rank 0 = deuce), mismo encoding que Card.id.
class HandTierClassifier {
  HandTierClassifier._();

  static HandTierResult classify(int h1, int h2, List<int> board) {
    final n = board.length;
    final all = [h1, h2, ...board];
    final score = HandEvaluator.evaluate(all);
    final cat = HandEvaluator.category(score);
    final boardCat = HandEvaluator.category(HandEvaluator.evaluate(board));

    final r1 = h1 >> 2, r2 = h2 >> 2;
    final hi = r1 > r2 ? r1 : r2, lo = r1 > r2 ? r2 : r1;
    final boardRanks = board.map((c) => c >> 2).toList()..sort((a, b) => b.compareTo(a));
    final top = boardRanks.first;
    final distinct = boardRanks.toSet().toList()..sort((a, b) => b.compareTo(a));
    var boardMask = 0;
    for (final r in boardRanks) {
      boardMask |= 1 << r;
    }
    final allMask = boardMask | (1 << r1) | (1 << r2);

    final suitAll = List<int>.filled(4, 0), suitBoard = List<int>.filled(4, 0), suitBoardMask = List<int>.filled(4, 0);
    for (final c in board) {
      suitBoard[c & 3]++;
      suitBoardMask[c & 3] |= 1 << (c >> 2);
    }
    for (final c in all) {
      suitAll[c & 3]++;
    }
    var domSuit = 0;
    for (var s = 1; s < 4; s++) {
      if (suitBoard[s] > suitBoard[domSuit]) domSuit = s;
    }

    final river = n >= 5;
    var flushDraw = false, nutFd = false, bdf = false;
    for (var s = 0; s < 4; s++) {
      final heroIn = ((h1 & 3) == s ? 1 : 0) + ((h2 & 3) == s ? 1 : 0);
      if (heroIn == 0) continue;
      if (!river && suitAll[s] == 4 && cat < HandEvaluator.flush) {
        flushDraw = true;
        final hr = [if ((h1 & 3) == s) r1, if ((h2 & 3) == s) r2].reduce((a, b) => a > b ? a : b);
        nutFd = nutFd || hr == _highestFree(suitBoardMask[s]);
      }
      if (n == 3 && suitAll[s] == 3) bdf = true;
    }

    var outRanks = 0;
    if (!river && cat < HandEvaluator.straight) {
      final cur = HandEvaluator.straightHigh(allMask);
      for (var r = 0; r < 13; r++) {
        if (allMask & (1 << r) != 0) continue;
        final withR = HandEvaluator.straightHigh(allMask | (1 << r));
        if (withR >= 0 && withR > cur && HandEvaluator.straightHigh(boardMask | (1 << r)) < 0) outRanks++;
      }
    }
    final oesd = outRanks >= 2, gutshot = outRanks == 1;
    final overcards = lo > top;

    final heroDom = ((h1 & 3) == domSuit ? 1 : 0) + ((h2 & 3) == domSuit ? 1 : 0);
    var blocker = false;
    if (suitBoard[domSuit] >= 2) {
      final free = _highestFree(suitBoardMask[domSuit]);
      blocker = ((h1 & 3) == domSuit && r1 == free) || ((h2 & 3) == domSuit && r2 == free);
    }

    HandTier tier;
    final improves = cat > boardCat;
    if (cat >= HandEvaluator.straight && improves) {
      tier = HandTier.nutsMonster;
    } else if (cat == HandEvaluator.trips && improves) {
      final set = r1 == r2;
      final kicker = boardRanks.contains(r1) ? r2 : r1;
      tier = set || kicker >= 8 ? HandTier.nutsMonster : HandTier.strongTopPairOverpair;
    } else if (cat == HandEvaluator.twoPair && r1 != r2 && boardMask & (1 << r1) != 0 && boardMask & (1 << r2) != 0) {
      tier = (hi == distinct[0] && distinct.length > 1 && lo == distinct[1]) || n == 3
          ? HandTier.nutsMonster
          : HandTier.strongTopPairOverpair;
    } else {
      tier = _pairTier(r1, r2, hi, lo, top, boardMask);
    }

    if ((tier == HandTier.marginalMadeShowdown || tier == HandTier.airGiveUp) && (flushDraw || oesd)) {
      tier = HandTier.highEquityComboDraw;
    } else if (tier == HandTier.airGiveUp &&
        (gutshot || bdf || (overcards && !river) || blocker)) {
      tier = HandTier.backdoorBlockerBluff;
    }

    return HandTierResult(tier,
        flushDraw: flushDraw,
        nutFlushDraw: nutFd,
        oesd: oesd,
        gutshot: gutshot,
        backdoorFlush: bdf,
        overcards: overcards,
        flushSuitBlocker: blocker,
        heroFlushSuitCards: suitBoard[domSuit] >= 2 ? heroDom : 0);
  }

  static HandTier _pairTier(int r1, int r2, int hi, int lo, int top, int boardMask) {
    if (r1 == r2) {
      if (boardMask & (1 << r1) != 0) return HandTier.nutsMonster;
      return r1 > top ? HandTier.strongTopPairOverpair : HandTier.marginalMadeShowdown;
    }
    final p1 = boardMask & (1 << r1) != 0, p2 = boardMask & (1 << r2) != 0;
    if (!p1 && !p2) return HandTier.airGiveUp;
    final pr = p1 && (!p2 || r1 > r2) ? r1 : r2;
    final kicker = pr == r1 ? r2 : r1;
    if (pr == top) return kicker >= 8 ? HandTier.strongTopPairOverpair : HandTier.marginalMadeShowdown;
    return HandTier.marginalMadeShowdown;
  }

  static int _highestFree(int suitMask) {
    for (var r = 12; r >= 0; r--) {
      if (suitMask & (1 << r) == 0) return r;
    }
    return -1;
  }
}
