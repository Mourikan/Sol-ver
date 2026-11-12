import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/postflop/postflop_heuristic_engine.dart';
import 'package:sol_ver/core/preflop/full_tree_preflop.dart';
import 'package:sol_ver/core/reads/read_presets_catalog.dart';
import 'package:sol_ver/core/reads/unmapped_spots_resolver.dart';

PlayerAction a(Street s, Position p, ActionType t, [double x = 0]) => PlayerAction(s, p, t, x);
const srp = [PlayerAction(Street.preflop, Position.btn, ActionType.raise, 2.5), PlayerAction(Street.preflop, Position.bb, ActionType.call, 2.5)];
const post = PostflopHeuristicEngine();

void main() {
  test('1. Micro_Block (16% pot): rango capado < 4% nuts, preset MINBET, raise de castigo o ancla', () {
    GameState g(VillainProfile vp, String h) => GameState(stake: Stake.nl10, heroPosition: Position.bb, villainPosition: Position.btn,
        effectiveStackBb: 97.5, potBb: 5.5, villainProfile: vp, hero: HoleCards.parse(h), board: Card.parseMany('Kc8d3h'),
        actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 0.9)]);
    final d = post.decide(g(VillainProfile.poolDefault, 'KdQc'));
    final base = post.decide(g(VillainProfile.gtoBase, 'KdQc')).perceivedVillainRange!;
    final r = d.perceivedVillainRange!;
    expect(r.isCapped, isTrue);
    expect(r.nutsAndMonstersPct, lessThan(0.04));
    expect(r.nutsAndMonstersPct, lessThan(base.nutsAndMonstersPct));
    expect(r.activePresets, contains('PRESET_MINBET_WEAKNESS'));
    expect(d.action, DecisionAction.betRaise);
    expect(d.justification!.activeReadBadge, contains('PRESET_MINBET_WEAKNESS'));
    expect(d.justification!.mathRationale, contains('Top:'));
  });

  test('2. PFA_Missed_CBet: check-back flop seco => preset capado y Turn_Probe 70% con Δ > 0', () {
    final d = post.decide(GameState(stake: Stake.nl10, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 97.5,
        potBb: 5.5, villainProfile: VillainProfile.poolDefault, hero: HoleCards.parse('9d9c'), board: Card.parseMany('Kc7d2h4s'),
        actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.check)]));
    expect(d.action, DecisionAction.betRaise);
    expect(d.sizing!.potPct, closeTo(UnmappedSpotsResolver.probePct, 0.5));
    expect(d.exploitDeltaEV!, greaterThan(0));
    expect(d.perceivedVillainRange!.activePresets, contains('PRESET_CAPPED_BY_CHECKBACK'));
    expect(d.perceivedVillainRange!.isCapped, isTrue);
    expect(d.justification!.activeCloserRule, 'PFA_Missed_CBet_Cap');
  });

  test('3. Busted_Draw_Runout: sin bloqueo del color => +aire y call; con bloqueo => -aire y fold', () {
    GameState g(String h) => GameState(stake: Stake.nl10, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 75,
        potBb: 30.7, villainProfile: VillainProfile.poolDefault, hero: HoleCards.parse(h), board: Card.parseMany('KsQs7d2c3h'),
        actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 3.6),
          a(Street.flop, Position.bb, ActionType.call, 3.6), a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 9),
          a(Street.turn, Position.bb, ActionType.call, 9), a(Street.river, Position.bb, ActionType.check), a(Street.river, Position.btn, ActionType.bet, 22)]);
    final un = post.decide(g('KdJd')), bl = post.decide(g('AsJs'));
    expect(un.perceivedVillainRange!.activePresets, contains('PRESET_BUSTED_FD_BLUFF_HEAVY'));
    expect(un.perceivedVillainRange!.pureAirAndBluffsPct, greaterThan(bl.perceivedVillainRange!.pureAirAndBluffsPct + 0.14));
    expect(un.action, DecisionAction.call);
    expect(bl.action, DecisionAction.fold);
    expect(un.justification!.mathRationale, contains('>= Pot Odds'));
    expect(bl.justification!.mathRationale, contains('< Pot Odds'));
  });

  test('4. 3BP Underpair QQ en A-x-x: c-bet 33% => call; c-bet 67% => aire <= 10% y fold salvo veto del EV_Sanity_Guard', () {
    const tb = [PlayerAction(Street.preflop, Position.btn, ActionType.raise, 2.5), PlayerAction(Street.preflop, Position.bb, ActionType.raise, 11),
      PlayerAction(Street.preflop, Position.btn, ActionType.call, 11)];
    GameState g(double b) => GameState(stake: Stake.nl10, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 89,
        potBb: 22.5, villainProfile: VillainProfile.poolDefault, hero: HoleCards.parse('QhQc'), board: Card.parseMany('Ah7d2c'),
        actions: [...tb, a(Street.flop, Position.bb, ActionType.bet, b)]);
    final small = post.decide(g(7.4)), big = post.decide(g(15));
    expect(small.action, DecisionAction.call);
    expect(small.ajusteExplotativoRead, contains('ThreeBet_Underpair_Pain_Guard'));
    expect(big.perceivedVillainRange!.activePresets, contains('PRESET_3BP_BIG_SIZING_HONESTY'));
    expect(big.perceivedVillainRange!.pureAirAndBluffsPct, lessThanOrEqualTo(0.10 + 1e-9));
    expect('${big.justificacionGto} ${big.ajusteExplotativoRead}', contains('Immediate_Flop_Fold'));
    // Jerarquía: el EV_Sanity_Guard (equity realizada >= pot odds) prevalece sobre la heurística de fold.
    expect(big.action == DecisionAction.fold || big.justification!.activeCloserRule == 'EV_Sanity_Guard', isTrue);
  });

  test('5. Multi_Limper: iso 3.5+1.2N IP / 4.5+1.5N OOP; limp-caller sin AA-JJ/AK en el rango percibido', () {
    expect(FullTreePreflop.isoSize(Position.btn, 3), closeTo(7.1, 1e-9));
    expect(FullTreePreflop.isoSize(Position.bb, 2), closeTo(7.5, 1e-9));
    final d = post.decide(GameState(stake: Stake.nl10, heroPosition: Position.bb, villainPosition: Position.sb, effectiveStackBb: 99, potBb: 2,
        villainProfile: VillainProfile.poolDefault, hero: HoleCards.parse('9h8h'), board: Card.parseMany('Kc6d2h'),
        actions: [const PlayerAction(Street.preflop, Position.sb, ActionType.call, 1), const PlayerAction(Street.preflop, Position.bb, ActionType.check),
          a(Street.flop, Position.sb, ActionType.check)]));
    final r = d.perceivedVillainRange!;
    expect(r.activePresets, contains('PRESET_LIMP_CALL_CAPPED'));
    for (final p in UnmappedSpotsResolver.limpCallerTop) {
      expect(r.topRepresentativeHands, isNot(contains(p)));
    }
    expect(d.justification!.activeReadBadge, contains('PRESET_LIMP_CALL_CAPPED'));
  });

  test('Catálogo: 8 presets con etiqueta única', () {
    expect({for (final p in AnonymousReadPreset.values) ReadPresetsCatalog.label(p)}.length, 8);
  });
}
