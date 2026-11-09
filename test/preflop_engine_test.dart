import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/core/evaluators/hand_evaluator.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/preflop/hand_normalizer.dart';
import 'package:sol_ver/core/preflop/preflop_ranges_db.dart';
import 'package:sol_ver/core/preflop/preflop_solver_engine.dart';
import 'package:sol_ver/core/preflop/range_notation.dart';

const engine = PreflopSolverEngine();

PlayerAction pf(Position p, ActionType t, [double amt = 0]) => PlayerAction(Street.preflop, p, t, amt);

DecisionOutput vsOpen(Stake st, Position hero, Position opener, String cards,
    {double open = 2.5, VillainProfile vp = VillainProfile.gtoBase}) =>
    engine.decide(GameState(
      stake: st,
      heroPosition: hero,
      effectiveStackBb: 100,
      hero: HoleCards.parse(cards),
      villainProfile: vp,
      actions: [pf(opener, ActionType.raise, open)],
    ));

DecisionOutput vs3b(Stake st, Position hero, Position villain, String cards,
    {double open = 2.5, double threeBet = 8.0, VillainProfile vp = VillainProfile.gtoBase}) =>
    engine.decide(GameState(
      stake: st,
      heroPosition: hero,
      effectiveStackBb: 100,
      hero: HoleCards.parse(cards),
      villainProfile: vp,
      actions: [pf(hero, ActionType.raise, open), pf(villain, ActionType.raise, threeBet)],
    ));

int card(String s) {
  final c = Card.parse(s);
  return c.rank.index * 4 + c.suit.index;
}

int ev(String s) => HandEvaluator.evaluate([for (final c in Card.parseMany(s)) c.rank.index * 4 + c.suit.index]);

void main() {
  group('1. Suited vs Offsuit: BTN vs CO open', () {
    for (final st in [Stake.nl10, Stake.nl100]) {
      test('${st.name}: A5s 3-bet bluff polar (mezcla 75% raise), A5o fold', () {
        final s = vsOpen(st, Position.btn, Position.co, 'Ah5h');
        final o = vsOpen(st, Position.btn, Position.co, 'Ah5d');
        expect(s.frequencies[DecisionAction.betRaise], closeTo(0.75, 1e-6));
        expect(s.majorityAction, DecisionAction.betRaise);
        expect(s.justificacionGto, contains('POLAR'));
        expect(o.action, DecisionAction.fold);
        expect(HandProps.eqr[HandNormalizer.parse('Ah5h').index],
            greaterThan(HandProps.eqr[HandNormalizer.parse('Ah5d').index]));
      });
    }
    test('Sizing 3-bet IP: 3.2x high-rake, 3.0x mid-rake', () {
      expect(vsOpen(Stake.nl10, Position.btn, Position.co, 'AhKh').sizing!.bb, closeTo(8.0, 1e-9));
      expect(vsOpen(Stake.nl100, Position.btn, Position.co, 'AhKh').sizing!.bb, closeTo(7.5, 1e-9));
    });
  });

  group('2. Rake Tier: MP/CO vs UTG open', () {
    test('NL10: 0% cold call en MP y CO (169 manos)', () {
      for (final h in [Position.mp, Position.co]) {
        expect(PreflopRangesDb.vsRfi(h, Position.utg, RakeTier.microHighRake).percent(PreflopAction.call), 0);
      }
      for (final c in ['8h8d', 'KhQd']) {
        expect(vsOpen(Stake.nl10, Position.co, Position.utg, c).action, DecisionAction.fold);
        expect(vsOpen(Stake.nl10, Position.mp, Position.utg, c).action, DecisionAction.fold);
      }
    });
    test('NL100: CO flat 88 IP (alta EQR), KQo sigue fold (dominada)', () {
      expect(vsOpen(Stake.nl100, Position.co, Position.utg, '8h8d').action, DecisionAction.call);
      expect(vsOpen(Stake.nl100, Position.co, Position.utg, 'KhQd').action, DecisionAction.fold);
    });
    test('NL10: BTN cold call ultra-selectivo < 4%', () {
      expect(PreflopRangesDb.vsRfi(Position.btn, Position.utg, RakeTier.microHighRake).percent(PreflopAction.call),
          lessThan(4));
      expect(vsOpen(Stake.nl10, Position.btn, Position.utg, '8h8d').action, DecisionAction.call);
    });
  });

  group('3. CO vs 3-bet BTN (OOP)', () {
    for (final st in [Stake.nl10, Stake.nl100]) {
      test('${st.name}: KQs call, KQo fold', () {
        final s = vs3b(st, Position.co, Position.btn, 'KhQh');
        final o = vs3b(st, Position.co, Position.btn, 'KhQd');
        expect(s.action, DecisionAction.call);
        expect(o.action, DecisionAction.fold);
        expect(o.justificacionGto, contains('OOP'));
      });
    }
    test('IP vs blinds: KQo defiende', () {
      expect(vs3b(Stake.nl100, Position.co, Position.bb, 'KhQd', threeBet: 11).action, DecisionAction.call);
    });
  });

  group('Matemática y exploits', () {
    test('Pot odds y equity requerida (fórmula)', () {
      expect(engine.potOddsRequired(1.5, 4.0), closeTo(1.5 / 5.5, 1e-12));
      expect(engine.requiredEquity(0.3, 1.0, true), closeTo(0.3 / 1.10, 1e-12));
      expect(engine.requiredEquity(0.3, 1.0, false), closeTo(0.3 / 0.85, 1e-12));
    });

    double bbDefend(Stake st, double open) {
      var combos = 0;
      for (var i = 0; i < 169; i++) {
        final cc = Matrix169.concreteCombos(i).first;
        String c(int x) => '${'23456789TJQKA'[x >> 2]}${'cdhs'[x & 3]}';
        final d = vsOpen(st, Position.bb, Position.btn, c(cc.$1) + c(cc.$2), open: open);
        if (d.action != DecisionAction.fold) combos += Matrix169.combos(i);
      }
      return combos / 1326 * 100;
    }

    test('BB defensa: más ancha vs 2bb que vs 4bb; mid-rake >= high-rake', () {
      final d2 = bbDefend(Stake.nl100, 2.0), d25 = bbDefend(Stake.nl100, 2.5), d4 = bbDefend(Stake.nl100, 4.0);
      expect(d2, greaterThan(d25));
      expect(d25, greaterThan(d4));
      expect(bbDefend(Stake.nl100, 2.5), greaterThanOrEqualTo(bbDefend(Stake.nl10, 2.5)));
    });

    test('Nit en ciegas: BTN roba 100% (72o)', () {
      final d = engine.decide(GameState(
          stake: Stake.nl25, heroPosition: Position.btn, hero: HoleCards.parse('7h2d'),
          villainProfile: VillainProfile.nit, actions: [pf(Position.utg, ActionType.fold)]));
      expect(d.action, DecisionAction.betRaise);
      final g = engine.decide(GameState(stake: Stake.nl25, heroPosition: Position.btn, hero: HoleCards.parse('7h2d')));
      expect(g.action, DecisionAction.fold);
    });

    test('Nit 3-bet: A5s pierde el 4-bet bluff (degrada a call por nut-flush mining si call <= 10% stack)', () {
      expect(vs3b(Stake.nl100, Position.co, Position.btn, 'Ah5h').action, DecisionAction.betRaise);
      expect(vs3b(Stake.nl100, Position.co, Position.btn, 'Ah5h', vp: VillainProfile.nit).action, DecisionAction.call);
      expect(vs3b(Stake.nl100, Position.co, Position.btn, 'Ah5h', vp: VillainProfile.nit, threeBet: 14).action, DecisionAction.fold);
    });

    test('Reg agro: TT 4-bet por valor', () {
      expect(vs3b(Stake.nl100, Position.co, Position.btn, 'ThTd').action, DecisionAction.call);
      expect(vs3b(Stake.nl100, Position.co, Position.btn, 'ThTd', vp: VillainProfile.regAgro).action,
          DecisionAction.betRaise);
    });

    test('Station: sin 3-bet bluff, AJo 3-bet de valor a 4x IP', () {
      expect(vsOpen(Stake.nl10, Position.btn, Position.co, 'Ah5h', vp: VillainProfile.callingStation).action,
          DecisionAction.fold);
      final v = vsOpen(Stake.nl10, Position.btn, Position.co, 'AhJd', vp: VillainProfile.callingStation);
      expect(v.action, DecisionAction.betRaise);
      expect(v.sizing!.bb, closeTo(10.0, 1e-9));
    });

    test('Min 3-bet amplía la defensa por pot odds', () {
      expect(vs3b(Stake.nl100, Position.co, Position.btn, 'KhQd').action, DecisionAction.fold);
      expect(vs3b(Stake.nl100, Position.co, Position.btn, 'KhQd', threeBet: 5.0).action, DecisionAction.call);
    });

    test('vs 3-bet sin stack efectivo => MissingInputs', () {
      expect(
          () => engine.decide(GameState(
              stake: Stake.nl50, heroPosition: Position.co, hero: HoleCards.parse('AhKh'),
              actions: [pf(Position.co, ActionType.raise, 2.5), pf(Position.btn, ActionType.raise, 8)])),
          throwsA(isA<MissingInputs>()));
    });

    test('Output contiene claves obligatorias y freq_gto poblado', () {
      final j = vsOpen(Stake.nl50, Position.btn, Position.co, 'AhKh').toJson();
      expect(j.keys, containsAll(['accion', 'sizing_bb_o_pct', 'freq_gto', 'justificacion_gto', 'ajuste_explotativo_read']));
      expect(j['freq_gto'], isNotNull);
    });
  });

  group('Datos', () {
    test('RFI % dentro de objetivo', () {
      double p(Position x, RakeTier t) => PreflopRangesDb.rfi(x, t).percent(PreflopAction.raise);
      const hr = RakeTier.microHighRake, mr = RakeTier.midRake;
      expect(p(Position.utg, hr), inInclusiveRange(14, 17));
      expect(p(Position.mp, hr), inInclusiveRange(17.5, 20.5));
      expect(p(Position.co, hr), inInclusiveRange(25.5, 28.5));
      expect(p(Position.btn, hr), inInclusiveRange(42, 46));
      expect(p(Position.sb, hr), inInclusiveRange(38.5, 41.5));
      for (final x in [Position.co, Position.btn, Position.sb]) {
        expect(p(x, mr) - p(x, hr), inInclusiveRange(3, 5));
      }
    });

    test('Normalización 169 e isomorfismo', () {
      expect(HandNormalizer.parse('AsKh').label, 'AKo');
      expect(HandNormalizer.parse('TdTc').label, 'TT');
      expect(HandNormalizer.parse('9s8s').label, '98s');
      expect(HandNormalizer.parse('9s8s').index, HandNormalizer.parse('9h8h').index);
      expect(HandNormalizer.parse('9s8s').cards.high, Card.parse('9s'));
      for (var i = 0; i < 169; i++) {
        expect(Matrix169.indexOf(Matrix169.label(i)), i);
      }
    });

    test('Blocker weight y EQR', () {
      double b(String l) => HandProps.blockerWeight[Matrix169.indexOf(l)];
      double e(String l) => HandProps.eqr[Matrix169.indexOf(l)];
      expect(b('AKs'), greaterThan(b('A5s')));
      expect(b('A5s'), greaterThan(b('T9s')));
      expect(b('T9s'), 0);
      expect(e('KJs'), greaterThan(e('KJo')));
      expect(e('T9s'), greaterThan(e('QTo')));
      expect(e('A5s'), greaterThan(e('A9o')));
    });

    test('Equity generada coherente', () {
      final aa = HandProps.equity('MR_RFI_btn', Matrix169.indexOf('AA'))!;
      final t72 = HandProps.equity('MR_RFI_btn', Matrix169.indexOf('72o'))!;
      expect(aa, inInclusiveRange(0.82, 0.87));
      expect(t72, lessThan(0.35));
    });

    test('Evaluador 7 cartas', () {
      expect(HandEvaluator.category(ev('AhKhQhJhTh2c3d')), HandEvaluator.straightFlush);
      expect(HandEvaluator.category(ev('Ah2d3c4s5h9cKd')), HandEvaluator.straight);
      expect(HandEvaluator.category(ev('AhAdAcKsKh2c3d')), HandEvaluator.fullHouse);
      expect(HandEvaluator.category(ev('AhAdKcKsQhQc3d')), HandEvaluator.twoPair);
      expect(ev('AhAdKcKsQhQc3d'), greaterThan(ev('AhAdKcKs3h4c2d')));
      expect(ev('6h5d4c3s2h9cKd'), greaterThan(ev('Ah2d3c4s5h9cKd')));
      expect(HandEvaluator.category(ev('2h7h9hJhKh2c3d')), HandEvaluator.flush);
      expect(card('2c'), 0);
    });
  });
}
