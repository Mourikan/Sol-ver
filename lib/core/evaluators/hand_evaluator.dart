import 'dart:typed_data';

/// Evaluador 5-7 cartas. Carta = rank*4 + suit (rank 0 = deuce). Score mayor = mano mejor.
class HandEvaluator {
  HandEvaluator._();

  static const int highCard = 0, pair = 1, twoPair = 2, trips = 3, straight = 4;
  static const int flush = 5, fullHouse = 6, quads = 7, straightFlush = 8;

  static final Int8List _counts = Int8List(13);
  static final Int32List _suitMask = Int32List(4);

  static int category(int score) => score >> 20;

  static int evaluate(List<int> cards, [int? length]) {
    final n = length ?? cards.length;
    _counts.fillRange(0, 13, 0);
    _suitMask.fillRange(0, 4, 0);
    var rankMask = 0;
    for (var i = 0; i < n; i++) {
      final c = cards[i];
      final r = c >> 2;
      _counts[r]++;
      _suitMask[c & 3] |= 1 << r;
      rankMask |= 1 << r;
    }

    var flushMask = 0;
    for (var s = 0; s < 4; s++) {
      if (_bits(_suitMask[s]) >= 5) flushMask = _suitMask[s];
    }
    if (flushMask != 0) {
      final sf = straightHigh(flushMask);
      if (sf >= 0) return straightFlush << 20 | sf;
    }

    var q = -1, t1 = -1, t2 = -1, p1 = -1, p2 = -1;
    for (var r = 12; r >= 0; r--) {
      switch (_counts[r]) {
        case 4:
          q = r;
        case 3:
          if (t1 < 0) {
            t1 = r;
          } else if (t2 < 0) {
            t2 = r;
          }
        case 2:
          if (p1 < 0) {
            p1 = r;
          } else if (p2 < 0) {
            p2 = r;
          }
      }
    }

    if (q >= 0) return quads << 20 | q << 16 | _top(rankMask & ~(1 << q), 1);
    if (t1 >= 0 && (t2 >= 0 || p1 >= 0)) {
      final pr = t2 > p1 ? t2 : p1;
      return fullHouse << 20 | t1 << 16 | pr << 12;
    }
    if (flushMask != 0) return flush << 20 | _top(flushMask, 5);
    final st = straightHigh(rankMask);
    if (st >= 0) return straight << 20 | st;
    if (t1 >= 0) return trips << 20 | t1 << 16 | _top(rankMask & ~(1 << t1), 2);
    if (p2 >= 0) {
      return twoPair << 20 | p1 << 16 | p2 << 12 | _top(rankMask & ~(1 << p1) & ~(1 << p2), 1);
    }
    if (p1 >= 0) return pair << 20 | p1 << 16 | _top(rankMask & ~(1 << p1), 3);
    return highCard << 20 | _top(rankMask, 5);
  }

  /// Rank alto (0..12) de la mejor escalera en la máscara, -1 si no hay. Rueda = 3.
  static int straightHigh(int mask) {
    final m = (mask << 1) | ((mask >> 12) & 1);
    for (var hi = 13; hi >= 4; hi--) {
      if ((m >> (hi - 4)) & 0x1F == 0x1F) return hi - 1;
    }
    return -1;
  }

  /// Empaqueta los k rangos más altos en los 4k bits bajos.
  static int _top(int mask, int k) {
    var out = 0, shift = 4 * k, got = 0;
    for (var r = 12; r >= 0 && got < k; r--) {
      if (mask & (1 << r) != 0) {
        shift -= 4;
        out |= r << shift;
        got++;
      }
    }
    return out;
  }

  static int _bits(int x) {
    var c = 0;
    while (x != 0) {
      x &= x - 1;
      c++;
    }
    return c;
  }
}
