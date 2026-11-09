import '../models/game_state.dart';

enum Connectivity { dry, semiWet, wet, dynamic }

enum SuitTexture { rainbow, twoTone, monotone }

enum BoardHeight { high, medium, low }

enum Advantage { pfaStrong, pfaSlight, neutral, defender }

class BoardMetrics {
  const BoardMetrics({
    required this.connectivity,
    required this.suitTexture,
    required this.isPaired,
    required this.height,
    required this.straightWindows,
    required this.drawWindows,
    required this.maxSuitCount,
    required this.rangeAdvantage,
    required this.nutAdvantage,
  });

  final Connectivity connectivity;
  final SuitTexture suitTexture;
  final bool isPaired;
  final BoardHeight height;

  /// Ventanas de 5 rangos con >=3 rangos del board (escalera posible con 2 cartas).
  final int straightWindows;

  /// Ventanas con exactamente 2 rangos del board (potencial de proyecto).
  final int drawWindows;
  final int maxSuitCount;
  final Advantage rangeAdvantage;
  final Advantage nutAdvantage;

  bool get isLowConnected =>
      height == BoardHeight.low && connectivity.index >= Connectivity.wet.index;
}

class BoardAnalyzer {
  const BoardAnalyzer._();

  static BoardMetrics analyze(
    List<Card> board, {
    required Position pfa,
    required Position defender,
    PotType potType = PotType.srp,
  }) {
    if (board.length < 3 || board.length > 5) {
      throw ArgumentError('Board requiere 3-5 cartas');
    }
    if (board.toSet().length != board.length) throw ArgumentError('Cartas duplicadas');

    final suitCounts = List<int>.filled(4, 0);
    final rankCounts = List<int>.filled(15, 0);
    var rankMask = 0;
    for (final c in board) {
      suitCounts[c.suit.index]++;
      rankCounts[c.rank.value]++;
      rankMask |= 1 << c.rank.value;
    }
    if (rankMask & (1 << 14) != 0) rankMask |= 1 << 1;

    final maxSuit = suitCounts.reduce((a, b) => a > b ? a : b);
    final suit = maxSuit >= 3
        ? SuitTexture.monotone
        : maxSuit == 2
            ? SuitTexture.twoTone
            : SuitTexture.rainbow;
    final paired = rankCounts.any((n) => n >= 2);

    var s3 = 0, s2 = 0;
    for (var low = 1; low <= 10; low++) {
      final n = _popCount(rankMask & (0x1F << low));
      if (n >= 3) {
        s3++;
      } else if (n == 2) {
        s2++;
      }
    }

    final Connectivity conn;
    if (s3 >= 2 || (s3 >= 1 && suit != SuitTexture.rainbow)) {
      conn = Connectivity.dynamic;
    } else if (s3 == 1 || suit == SuitTexture.monotone || (suit == SuitTexture.twoTone && s2 >= 3)) {
      conn = Connectivity.wet;
    } else if (suit == SuitTexture.twoTone || s2 >= 3) {
      conn = Connectivity.semiWet;
    } else {
      conn = Connectivity.dry;
    }

    final top = board.map((c) => c.rank.value).reduce((a, b) => a > b ? a : b);
    final height = top >= Rank.king.value
        ? BoardHeight.high
        : top >= Rank.ten.value
            ? BoardHeight.medium
            : BoardHeight.low;

    final adv = _advantage(
      height: height,
      conn: conn,
      suit: suit,
      paired: paired,
      pfa: pfa,
      defender: defender,
      potType: potType,
    );

    return BoardMetrics(
      connectivity: conn,
      suitTexture: suit,
      isPaired: paired,
      height: height,
      straightWindows: s3,
      drawWindows: s2,
      maxSuitCount: maxSuit,
      rangeAdvantage: adv.$1,
      nutAdvantage: adv.$2,
    );
  }

  /// Escala ordinal (no frecuencias). Principios:
  /// - Board alto: PFA concentra Ax/Kx fuertes y AA/KK/AK; el defensor llega capado (3-betea su top).
  /// - Board bajo/conectado: el defensor (BB sobre todo) contiene más suited connectors, pares bajos y dobles parejas.
  /// - Board pareado: reduce combos de dos pares/escaleras; favorece al rango con más overpairs (PFA).
  /// - Monotono: equaliza equity; no altera NA de forma direccional sin datos de suitedness.
  /// - 3BP/4BP: el rango del agresor es más condensado en overpairs/broadways.
  /// - PFA de EP (UTG/MP): rango más fuerte, mayor RA/NA en boards altos.
  static (Advantage, Advantage) _advantage({
    required BoardHeight height,
    required Connectivity conn,
    required SuitTexture suit,
    required bool paired,
    required Position pfa,
    required Position defender,
    required PotType potType,
  }) {
    var ra = 0, na = 0;
    final connected = conn.index >= Connectivity.wet.index;

    switch (height) {
      case BoardHeight.high:
        ra += 2;
        na += 1;
        if (conn == Connectivity.dry) ra += 1;
        if (conn != Connectivity.dynamic) na += 1;
      case BoardHeight.medium:
        ra += 1;
      case BoardHeight.low:
        ra += connected ? -1 : 1;
        if (connected) na -= 1;
    }

    if (conn == Connectivity.dynamic) {
      ra -= 1;
      na -= 1;
    }
    if (paired) ra += 1;
    if (suit == SuitTexture.monotone) ra -= 1;

    if (potType == PotType.threeBet || potType == PotType.fourBetPlus) {
      ra += 1;
      if (!(connected && height != BoardHeight.high)) na += 1;
    }

    if (pfa == Position.utg || pfa == Position.mp) {
      if (height != BoardHeight.low) ra += 1;
      if (height == BoardHeight.high) na += 1;
    }

    if (defender == Position.bb && height != BoardHeight.high && connected) na -= 1;

    return (_map(ra), _map(na));
  }

  static Advantage _map(int s) => s >= 3
      ? Advantage.pfaStrong
      : s >= 1
          ? Advantage.pfaSlight
          : s == 0
              ? Advantage.neutral
              : Advantage.defender;

  static int _popCount(int x) {
    var c = 0;
    while (x != 0) {
      x &= x - 1;
      c++;
    }
    return c;
  }
}
