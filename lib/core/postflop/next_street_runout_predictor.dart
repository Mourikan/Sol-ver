import '../models/decision_insight.dart';
import '../models/game_state.dart';
import 'hand_tier.dart';
import 'turn_river_solver.dart';

/// Predictor de la siguiente calle: 13 rangos en versión brick offsuit + la carta que completa color (si hay proyecto).
/// Reglas: mejora de Hero a monstruo => Kill; color completado sin carta del palo => Peligro; dobla una carta no-top del
/// board => Peligro (trips del par medio rival); escalera completada o dobla la top => Freno; overcard A/K con iniciativa o
/// brick => Kill (mantiene el rango rival capado).
class NextStreetRunoutPredictor {
  NextStreetRunoutPredictor._();

  static const _sym = '23456789TJQKA';

  static RunoutForecast? forecast(GameState s) {
    if (s.hero == null || (s.street != Street.flop && s.street != Street.turn)) return null;
    final board = s.board;
    final dead = {for (final c in [...board, s.hero!.high, s.hero!.low]) c.id};
    final suitCount = List<int>.filled(4, 0);
    for (final c in board) {
      suitCount[c.suit.index]++;
    }
    final drawSuit = suitCount.indexWhere((n) => n >= 2);
    final heroSuited = drawSuit >= 0 && (s.hero!.high.suit.index == drawSuit || s.hero!.low.suit.index == drawSuit);
    final heroInit = s.actions.where((a) => a.street == s.street || a.street.index == s.street.index - 1).where((a) => a.isAggressive).lastOrNull?.actor ==
        s.heroPosition;
    final top = board.map((c) => c.rank.value).reduce((a, b) => a > b ? a : b);
    final boardRanks = {for (final c in board) c.rank.value};
    final kill = <String>[], ctrl = <String>[], abort = <String>[];
    for (var ri = 12; ri >= 0; ri--) {
      final rank = Rank.values[ri];
      // Brick offsuit: palo que no completa ni crea proyecto y no está muerto.
      Card? brick;
      for (final su in Suit.values) {
        if (su.index == drawSuit) continue;
        final c = Card(rank, su);
        if (!dead.contains(c.id)) {
          brick = c;
          break;
        }
      }
      if (brick == null) continue;
      final next = [...board, brick];
      final heroTier = HandTierClassifier.classify(s.hero!.high.id, s.hero!.low.id, [for (final c in next) c.id]).tier;
      final shift = CardShiftMatrix.classify(board, brick);
      final label = _sym[ri];
      if (heroTier == HandTier.nutsMonster) {
        kill.add(label);
      } else if (boardRanks.contains(rank.value) && rank.value != top) {
        abort.add(label);
      } else if (shift == CardShift.flushOrStraightCompletes || boardRanks.contains(rank.value)) {
        ctrl.add(label);
      } else if (shift == CardShift.rankShift) {
        (heroInit ? kill : ctrl).add(label);
      } else {
        kill.add(label);
      }
    }
    if (drawSuit >= 0) {
      final glyph = const ['♣', '♦', '♥', '♠'][drawSuit];
      final label = suitCount[drawSuit] >= 3 ? '$glyph 4ª color' : '$glyph Flush';
      (heroSuited ? kill : abort).add(label);
    }
    return RunoutForecast(barrelKillCards: kill, potControlCards: ctrl, abortDangerCards: abort);
  }
}
