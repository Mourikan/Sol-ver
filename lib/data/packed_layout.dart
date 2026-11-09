import '../core/models/game_state.dart';

/// Layout determinista de los nodos preflop empaquetados (compartido por generador y repositorio).
class PackedLayout {
  PackedLayout._();

  static const tiers = RakeTier.values;
  static const rfiPositions = [Position.utg, Position.mp, Position.co, Position.btn, Position.sb];
  static const vs3BetKeys = [
    (Position.utg, false),
    (Position.mp, false),
    (Position.co, false),
    (Position.utg, true),
    (Position.mp, true),
    (Position.co, true),
    (Position.btn, true),
    (Position.sb, false),
  ];

  static final List<(Position, Position)> vsRfiPairs = [
    for (final h in [Position.mp, Position.co, Position.btn, Position.sb, Position.bb])
      for (final o in rfiPositions)
        if (o.index < h.index) (h, o),
  ];

  static int get nodesPerTier => rfiPositions.length + vsRfiPairs.length + vs3BetKeys.length;

  /// planos por nodo: 0 = raise, 1 = call.
  static const planes = 2;
  static const handCount = 169;
  static int get preflopBytes => tiers.length * nodesPerTier * planes * handCount;

  static int rfiNode(Position p) => rfiPositions.indexOf(p);
  static int vsRfiNode(Position hero, Position opener) => rfiPositions.length + vsRfiPairs.indexOf((hero, opener));
  static int vs3BetNode(Position hero, bool ip) => rfiPositions.length + vsRfiPairs.length + vs3BetKeys.indexOf((hero, ip));

  static int offset(RakeTier t, int node, int plane, int hand) =>
      (((t.index * nodesPerTier) + node) * planes + plane) * handCount + hand;

  /// Flop: índice O(1) por rangos ordenados (r1>=r2>=r3, 0=deuce) y patrón de palos (0 rainbow, 1 two-tone, 2 monotone).
  static const flopBytes = 13 * 13 * 13 * 3;
  static int flopIndex(int r1, int r2, int r3, int suitPattern) => ((r1 * 13 + r2) * 13 + r3) * 3 + suitPattern;
  static const invalid = 255;
}
