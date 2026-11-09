import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/core/evaluators/board_analyzer.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';

BoardMetrics srpBtnVsBb(String b) =>
    BoardAnalyzer.analyze(Card.parseMany(b), pfa: Position.btn, defender: Position.bb);

void main() {
  group('BoardAnalyzer', () {
    test('As7d2c: seco, alto, rainbow, RA/NA para PFA', () {
      final m = srpBtnVsBb('As7d2c');
      expect(m.connectivity, Connectivity.dry);
      expect(m.suitTexture, SuitTexture.rainbow);
      expect(m.height, BoardHeight.high);
      expect(m.isPaired, isFalse);
      expect(m.straightWindows, 0);
      expect(m.rangeAdvantage, Advantage.pfaStrong);
      expect(m.nutAdvantage, isIn([Advantage.pfaStrong, Advantage.pfaSlight]));
    });

    test('Jh9s8d: dinámico, NA para defensor BB', () {
      final m = srpBtnVsBb('Jh9s8d');
      expect(m.connectivity, Connectivity.dynamic);
      expect(m.height, BoardHeight.medium);
      expect(m.straightWindows, greaterThanOrEqualTo(2));
      expect(m.nutAdvantage, Advantage.defender);
    });

    test('JhTs9s two-tone: dinámico', () {
      expect(srpBtnVsBb('JhTs9s').connectivity, Connectivity.dynamic);
    });

    test('8s7s6d: bajo conectado, RA y NA defensor', () {
      final m = srpBtnVsBb('8s7s6d');
      expect(m.isLowConnected, isTrue);
      expect(m.rangeAdvantage, Advantage.defender);
      expect(m.nutAdvantage, Advantage.defender);
    });

    test('KsKd4h: pareado seco, RA PFA', () {
      final m = srpBtnVsBb('KsKd4h');
      expect(m.isPaired, isTrue);
      expect(m.connectivity, Connectivity.dry);
      expect(m.rangeAdvantage, Advantage.pfaStrong);
    });

    test('Monotono', () {
      final m = srpBtnVsBb('Ah8h3h');
      expect(m.suitTexture, SuitTexture.monotone);
      expect(m.connectivity, isNot(Connectivity.dry));
    });

    test('Rechaza boards inválidos', () {
      expect(() => srpBtnVsBb('AsKd'), throwsArgumentError);
      expect(() => srpBtnVsBb('AsAsKd'), throwsArgumentError);
    });
  });

  group('Modelos', () {
    test('Normalización 169 e índice O(1)', () {
      expect(HoleCards.parse('KhAh').handClass, 'AKs');
      expect(HoleCards.parse('AdKc').handClass, 'AKo');
      expect(HoleCards.parse('7c7d').handClass, '77');
      expect(HoleCards.parse('AhAs').index169, 0);
      expect(HoleCards.parse('AhKh').index169, 1);
      expect(HoleCards.parse('AhKd').index169, 13);
      expect(HoleCards.parse('2h2d').index169, 168);
    });

    test('GameState: pot type, PFA, SPR y variables faltantes', () {
      final gs = GameState(
        stake: Stake.nl10,
        heroPosition: Position.bb,
        villainPosition: Position.btn,
        effectiveStackBb: 97.5,
        potBb: 5.5,
        hero: HoleCards.parse('9h8h'),
        board: Card.parseMany('Jh9s8d'),
        actions: const [
          PlayerAction(Street.preflop, Position.btn, ActionType.raise, 2.5),
          PlayerAction(Street.preflop, Position.bb, ActionType.call, 2.5),
        ],
      );
      expect(gs.rakeTier, RakeTier.microHighRake);
      expect(gs.potType, PotType.srp);
      expect(gs.preflopAggressor, Position.btn);
      expect(gs.heroInPosition, isFalse);
      expect(gs.spr, closeTo(17.73, 0.01));
      expect(gs.street, Street.flop);
      expect(gs.missingForPostflop(), isEmpty);

      final partial = GameState(stake: Stake.nl100, heroPosition: Position.co);
      expect(partial.rakeTier, RakeTier.midRake);
      expect(partial.missingForPostflop(), containsAll(['hero', 'potBb', 'effectiveStackBb']));
    });

    test('DecisionOutput: claves obligatorias', () {
      const d = DecisionOutput(
        action: DecisionAction.betRaise,
        sizing: Sizing(bb: 1.8, potPct: 33),
        metrics: [KeyMetric(MetricType.spr, 17.7)],
        justificacionGto: 'x',
        ajusteExplotativoRead: 'y',
      );
      expect(d.toJson().keys, containsAll(
          ['accion', 'sizing_bb_o_pct', 'freq_gto', 'justificacion_gto', 'ajuste_explotativo_read']));
      expect(d.toJson()['freq_gto'], {'betRaise': 100.0});
    });

    test('Rechaza cartas duplicadas entre hero y board', () {
      expect(
          () => GameState(
              stake: Stake.nl2,
              heroPosition: Position.btn,
              hero: HoleCards.parse('AsKs'),
              board: Card.parseMany('As7d2c')),
          throwsArgumentError);
    });
  });
}
