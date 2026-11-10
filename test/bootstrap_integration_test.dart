import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/core/evaluators/action_ev_calculator.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/preflop/full_tree_preflop.dart';
import 'package:sol_ver/core/preflop/hand_normalizer.dart';
import 'package:sol_ver/core/preflop/preflop_ranges_db.dart';
import 'package:sol_ver/core/preflop/range_notation.dart';
import 'package:sol_ver/core/reads/gg_profiler.dart';
import 'package:sol_ver/core/reads/mda_consensus_db.dart';
import 'package:sol_ver/data/open_source_parser.dart';
import 'package:sol_ver/data/packed_layout.dart';
import 'package:sol_ver/data/packed_lookup_repository.dart';

PlayerAction a(Street s, Position p, ActionType t, [double x = 0]) => PlayerAction(s, p, t, x);
const srp = [PlayerAction(Street.preflop, Position.btn, ActionType.raise, 2.5), PlayerAction(Street.preflop, Position.bb, ActionType.call, 2.5)];

void main() {
  final json = File('test/fixtures/texassolver_btn_rfi.json').readAsStringSync();
  final table = BootstrapDataParser.parse(json);

  tearDown(PreflopRangesDb.clearOverrides);

  test('Parser: lee el JSON comprimido y rellena los 169 combos (Zero-Hole Fallback)', () {
    expect(table.interpolated, isNotEmpty);
    expect(table.meta['source'], 'TexasSolver (simulado)');
    for (var i = 0; i < 169; i++) {
      expect(table.raise[i] + table.call[i] + table.fold[i], closeTo(1, 1e-6));
    }
    expect(table.raise[Matrix169.indexOf('AA')], 1);
  });

  test('Relleno lógico: cada hueco queda entre sus vecinos de equity y respeta la monotonía de pares', () {
    double eq(int i) => HandProps.equity(BootstrapDataParser.smoothingEquityKey, i)!;
    final known = [for (var i = 0; i < 169; i++) if (!table.interpolated.contains(i)) i];
    for (final i in table.interpolated) {
      final below = known.where((k) => eq(k) <= eq(i)).toList()..sort((x, y) => eq(y).compareTo(eq(x)));
      final above = known.where((k) => eq(k) > eq(i)).toList()..sort((x, y) => eq(x).compareTo(eq(y)));
      final lo = below.isEmpty ? null : table.raise[below.first];
      final hi = above.isEmpty ? null : table.raise[above.first];
      final mn = [?lo, ?hi].reduce((x, y) => x < y ? x : y);
      final mx = [?lo, ?hi].reduce((x, y) => x > y ? x : y);
      expect(table.raise[i], inInclusiveRange(mn - 1e-6, mx + 1e-6), reason: Matrix169.label(i));
    }
    for (var r = 12; r > 0; r--) {
      final lower = Matrix169.index(r, r, suited: false), higher = Matrix169.index(r - 1, r - 1, suited: false);
      expect(table.raise[higher], greaterThanOrEqualTo(table.raise[lower] - 1e-6));
    }
  });

  test('Packed O(1): compila a Uint8List y marca origen bootstrapGTO', () {
    final repo = PackedLookupRepository.load().withBootstrapRfi({(RakeTier.midRake, Position.btn): table});
    for (var i = 0; i < 169; i++) {
      expect(repo.rfi(Position.btn, RakeTier.midRake, i), closeTo(table.raise[i], 1 / 255));
    }
    expect(repo.sourceOf(RakeTier.midRake, PackedLayout.rfiNode(Position.btn)), RangeSource.bootstrapGTO);
    expect(repo.sourceOf(RakeTier.midRake, PackedLayout.rfiNode(Position.co)), RangeSource.calibratedHeuristicBase);
  });

  test('Motor preflop usa la tabla bootstrap (freq_source bootstrapGTO)', () {
    PreflopRangesDb.registerOverride(table.toRangeNode(PreflopRangesDb.rfiId(Position.btn, RakeTier.midRake)));
    final mix = table.interpolated.firstWhere((i) => table.raise[i] > 0 && table.raise[i] < 1, orElse: () => table.interpolated.first);
    final (x, y) = Matrix169.concreteCombos(mix).first;
    String cs(int id) => '${'23456789TJQKA'[id >> 2]}${'cdhs'[id & 3]}';
    final d = const FullTreePreflop().decide(GameState(stake: Stake.nl100, heroPosition: Position.btn, hero: HoleCards.parse(cs(x) + cs(y))));
    expect(d.frequencies[DecisionAction.betRaise] ?? 0, closeTo(table.raise[mix], 1e-6));
    if (table.raise[mix] > 0 && table.raise[mix] < 1) expect(d.freqSource, FreqSource.bootstrapGTO);
  });

  test('ActionEVCalculator con MDA_Consensus_DB: FE fijo vs pool por defecto (no alfa)', () {
    const pool = ReadProfile(GgArchetype.poolDefault, []);
    const reg = ReadProfile(GgArchetype.unknownReg, []);
    expect(ActionEvCalculator.foldEquity(0.30, 0.43, pool, VillainProfile.poolDefault, river: false, capped: false, secondBarrel: true),
        MDAParameters.turnOverfoldVsDoubleBarrel);
    expect(ActionEvCalculator.foldEquity(0.30, 0.2, pool, VillainProfile.poolDefault, river: true, capped: false, betFraction: 0.33),
        closeTo(1 - MDAParameters.riverCallEfficiencyVsSmallBet, 1e-12));
    expect(ActionEvCalculator.foldEquity(0.30, 0.43, reg, VillainProfile.gtoBase, river: false, capped: false, secondBarrel: true), 0.30);
    final turn = GameState(stake: Stake.nl25, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 95.7, potBb: 9.1,
        hero: HoleCards.parse('QhJd'), board: Card.parseMany('7d5c2s9h'),
        actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8),
          a(Street.flop, Position.bb, ActionType.call, 1.8), a(Street.turn, Position.bb, ActionType.check)]);
    final evPool = ActionEvCalculator.postflop(turn.copyWith(villainProfile: VillainProfile.poolDefault), pool, potBefore: 9.1, toCall: 0, betSizeBb: 6.8);
    final evReg = ActionEvCalculator.postflop(turn, reg, potBefore: 9.1, toCall: 0, betSizeBb: 6.8);
    expect(evPool.foldEquity, greaterThanOrEqualTo(MDAParameters.turnOverfoldVsDoubleBarrel - 1e-9));
    expect(evPool.betRaise, greaterThanOrEqualTo(evReg.betRaise - 1e-9));
    expect(ActionEvCalculator.foldEquity(0.80, 0.43, pool, VillainProfile.poolDefault, river: false, capped: false, secondBarrel: true), 0.80);
  });
}
