enum Rank {
  two('2', 2),
  three('3', 3),
  four('4', 4),
  five('5', 5),
  six('6', 6),
  seven('7', 7),
  eight('8', 8),
  nine('9', 9),
  ten('T', 10),
  jack('J', 11),
  queen('Q', 12),
  king('K', 13),
  ace('A', 14);

  const Rank(this.symbol, this.value);
  final String symbol;
  final int value;

  static Rank parse(String s) =>
      Rank.values.firstWhere((r) => r.symbol == s.toUpperCase(),
          orElse: () => throw FormatException('Rank inválido: $s'));
}

enum Suit {
  clubs('c'),
  diamonds('d'),
  hearts('h'),
  spades('s');

  const Suit(this.symbol);
  final String symbol;

  static Suit parse(String s) =>
      Suit.values.firstWhere((x) => x.symbol == s.toLowerCase(),
          orElse: () => throw FormatException('Palo inválido: $s'));
}

class Card {
  const Card(this.rank, this.suit);

  factory Card.parse(String s) {
    if (s.length != 2) throw FormatException('Carta inválida: $s');
    return Card(Rank.parse(s[0]), Suit.parse(s[1]));
  }

  static List<Card> parseMany(String s) {
    final t = s.replaceAll(RegExp(r'[\s,]'), '');
    if (t.length.isOdd) throw FormatException('Cartas inválidas: $s');
    return List.unmodifiable(
        [for (var i = 0; i < t.length; i += 2) Card.parse(t.substring(i, i + 2))]);
  }

  final Rank rank;
  final Suit suit;

  /// 0..51, apto para bitmask de 64 bits.
  int get id => rank.index * 4 + suit.index;
  int get bit => 1 << id;

  @override
  bool operator ==(Object other) => other is Card && other.id == id;
  @override
  int get hashCode => id;
  @override
  String toString() => '${rank.symbol}${suit.symbol}';
}

class HoleCards {
  HoleCards(Card a, Card b)
      : high = a.rank.value >= b.rank.value ? a : b,
        low = a.rank.value >= b.rank.value ? b : a {
    if (a == b) throw ArgumentError('Cartas duplicadas: $a');
  }

  factory HoleCards.parse(String s) {
    final c = Card.parseMany(s);
    if (c.length != 2) throw FormatException('Hole cards inválidas: $s');
    return HoleCards(c[0], c[1]);
  }

  final Card high;
  final Card low;

  bool get isPair => high.rank == low.rank;
  bool get isSuited => high.suit == low.suit;
  int get mask => high.bit | low.bit;

  /// Notación 169: 'AKs', 'AKo', '77'.
  String get handClass => isPair
      ? '${high.rank.symbol}${low.rank.symbol}'
      : '${high.rank.symbol}${low.rank.symbol}${isSuited ? 's' : 'o'}';

  /// Índice O(1) en matriz 13x13 (fila/col 0 = A). Suited sobre la diagonal, offsuit debajo.
  int get index169 {
    final h = 12 - high.rank.index, l = 12 - low.rank.index;
    if (isPair) return h * 13 + h;
    return isSuited ? h * 13 + l : l * 13 + h;
  }

  @override
  String toString() => '$high$low';
}
