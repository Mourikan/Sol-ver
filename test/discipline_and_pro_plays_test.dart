import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/core/discipline/blocker_bluff_converter.dart';
import 'package:sol_ver/core/discipline/bluff_catch_auditor.dart';
import 'package:sol_ver/core/discipline/board_history.dart';
import 'package:sol_ver/core/discipline/timing_tells_matrix.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/postflop/postflop_heuristic_engine.dart';
import 'package:sol_ver/core/reads/gg_profiler.dart';

const post = PostflopHeuristicEngine();

PlayerAction a(Street s, Position p, ActionType t, [double amt = 0, TimingTell tt = TimingTell.none]) =>
    PlayerAction(s, p, t, amt, tt);

const srpBtn = [
  PlayerAction(Street.preflop, Position.btn, ActionType.raise, 2.5),
  PlayerAction(Street.preflop, Position.bb, ActionType.call, 2.5),
];

final scared = GgProfiler.classify(const SmartHudInput(vpip: 20, pfr: 17, threeBet: 4, stackBb: 100));
final fish = GgProfiler.classify(const SmartHudInput(vpip: 50, pfr: 5, threeBet: 1, stackBb: 100));
final agro = GgProfiler.classify(const SmartHudInput(vpip: 40, pfr: 30, threeBet: 14, stackBb: 100));
const regAbc = ReadProfile(GgArchetype.scaredMoneyReg, ['Reg_ABC / pasivo']);

void main() {
  group('1. Adrián Mateos: Hero Fold disciplinado con AA', () {
    final xcXc = [
      ...srpBtn,
      a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 2),
      a(Street.flop, Position.bb, ActionType.call, 2), a(Street.turn, Position.bb, ActionType.check),
      a(Street.turn, Position.btn, ActionType.bet, 6), a(Street.turn, Position.bb, ActionType.call, 6),
    ];
    GameState checkRaise(String hero) => GameState(stake: Stake.nl25, heroPosition: Position.btn, villainPosition: Position.bb,
        effectiveStackBb: 85, potBb: 21.5, hero: HoleCards.parse(hero), board: Card.parseMany('Ts7s3d2c9s'),
        actions: [...xcXc, a(Street.river, Position.bb, ActionType.check), a(Street.river, Position.btn, ActionType.bet, 12),
          a(Street.river, Position.bb, ActionType.raise, 40, TimingTell.longTank)]);
    GameState potDonk(String hero) => GameState(stake: Stake.nl25, heroPosition: Position.btn, villainPosition: Position.bb,
        effectiveStackBb: 85, potBb: 21.5, hero: HoleCards.parse(hero), board: Card.parseMany('Ts7s3d2c9s'),
        actions: [...xcXc, a(Street.river, Position.bb, ActionType.bet, 21.5, TimingTell.longTank)]);

    test('Check-raise river tras long tank: AA sin pica => 100% fold', () {
      final d = post.decide(checkRaise('AhAd'), read: regAbc);
      expect(d.action, DecisionAction.fold);
      expect(d.ajusteExplotativoRead, contains('FOLD DISCIPLINADO'));
      expect(d.justificacionGto, contains('colapsa'));
    });
    test('Pot donk river tras long tank: AA, KK, top two y set bajo => fold', () {
      for (final h in ['AhAd', 'KhKd', 'Th7h', '3h3c']) {
        expect(post.decide(potDonk(h), read: regAbc).action, DecisionAction.fold, reason: h);
      }
    });
    test('Auditoría: 0 categorías de farol y timing x0.5', () {
      final s = potDonk('AhAd');
      final r = BluffCatchAuditor.audit(s, regAbc, pot: 21.5, call: 21.5, heroHasNuts: false);
      expect(r.node, VillainLineNode.xcXcThenAggressionRiver);
      expect(r.categories, isEmpty);
      expect(r.availableBluffs, lessThan(r.potOddsReq * 0.6));
      expect(r.verdict, AuditVerdict.heroFoldDisciplined);
      expect(TimingTellsMatrix.lastVillain(s).villainBluffMultiplier, 0.5);
    });
    test('Con As (bloquea el nut flush) la auditoría no fuerza el hero fold', () {
      final r = BluffCatchAuditor.audit(potDonk('AsAd'), regAbc, pot: 21.5, call: 21.5, heroHasNuts: false);
      expect(r.verdict, isNot(AuditVerdict.heroFoldDisciplined));
    });
  });

  group('2. Hero Call por unblockers: Ks Qs 7d 2c 3h vs Agro tri-barrel', () {
    GameState g(String hero) => GameState(stake: Stake.nl50, heroPosition: Position.bb, villainPosition: Position.btn,
        effectiveStackBb: 75, potBb: 30, hero: HoleCards.parse(hero), board: Card.parseMany('KsQs7d2c3h'),
        actions: [...srpBtn,
          a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 2),
          a(Street.flop, Position.bb, ActionType.call, 2), a(Street.turn, Position.bb, ActionType.check),
          a(Street.turn, Position.btn, ActionType.bet, 7.5), a(Street.turn, Position.bb, ActionType.call, 7.5),
          a(Street.river, Position.bb, ActionType.check), a(Street.river, Position.btn, ActionType.bet, 22)]);
    test('Brick out total detectado', () {
      final h = BoardHistory(Card.parseMany('KsQs7d2c3h'));
      expect(h.brickOut, isTrue);
      expect(h.missedFlushDraw, isTrue);
      expect(h.missedStraightDraw, isTrue);
    });
    test('Kd Jd: call (0 picas + blocker K)', () {
      final d = post.decide(g('KdJd'), read: agro);
      expect(d.action, DecisionAction.call);
      expect(d.ajusteExplotativoRead, contains('HERO CALL'));
      expect(BluffCatchAuditor.audit(g('KdJd'), agro, pot: 30, call: 22, heroHasNuts: false).verdict, AuditVerdict.heroCallApproved);
    });
    test('As Js: fold (bloquea sus faroles de picas)', () {
      expect(post.decide(g('AsJs'), read: agro).action, DecisionAction.fold);
      expect(BluffCatchAuditor.audit(g('AsJs'), agro, pot: 30, call: 22, heroHasNuts: false).verdict, AuditVerdict.foldNegativeEv);
    });
    test('Kd Jd vs reg no-agro en triple barrel overbet NL50: MDA => fold', () {
      final s = GameState(stake: Stake.nl50, heroPosition: Position.bb, villainPosition: Position.btn,
          effectiveStackBb: 75, potBb: 30, hero: HoleCards.parse('Kd7c'), board: Card.parseMany('KsQs7d2c3h'),
          actions: [...srpBtn,
            a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 2),
            a(Street.flop, Position.bb, ActionType.call, 2), a(Street.turn, Position.bb, ActionType.check),
            a(Street.turn, Position.btn, ActionType.bet, 7.5), a(Street.turn, Position.bb, ActionType.call, 7.5),
            a(Street.river, Position.bb, ActionType.check), a(Street.river, Position.btn, ActionType.bet, 40)]);
      expect(BluffCatchAuditor.lineOf(s), VillainLineNode.tripleBarrelOverbet);
    });
  });

  group('3. LLinusLLove: Ah 4s en Qh Jh 4c 2h 8d', () {
    GameState g(ReadProfile r, {VillainProfile vp = VillainProfile.gtoBase}) => GameState(
        stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 80, potBb: 18,
        hero: HoleCards.parse('Ah4s'), board: Card.parseMany('QhJh4c2h8d'), villainProfile: vp,
        actions: [...srpBtn,
          a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8),
          a(Street.flop, Position.bb, ActionType.call, 1.8), a(Street.turn, Position.bb, ActionType.check),
          a(Street.turn, Position.btn, ActionType.bet, 4.5), a(Street.turn, Position.bb, ActionType.call, 4.5),
          a(Street.river, Position.bb, ActionType.check, 0, TimingTell.instaAction)]);
    test('Scared money: overbet bluff 125% con Ah nut blocker', () {
      final d = post.decide(g(scared), read: scared);
      expect(d.action, DecisionAction.betRaise);
      expect(d.sizing!.potPct, closeTo(125, 1e-9));
      expect(d.justificacionGto, contains('Turn_SDV_Into_Bluff'));
      final c = BlockerBluffConverter.evaluate(g(scared), scared, heroCanBet: true);
      expect(c.mode, ConversionMode.polarizedOverbetBluff);
      expect(c.reasons.join(), contains('Ah'));
    });
    test('CallingStation: gate bloqueado, 100% check behind', () {
      final d = post.decide(g(fish, vp: VillainProfile.callingStation), read: fish);
      expect(d.action, DecisionAction.check);
      expect(BlockerBluffConverter.evaluate(g(fish), fish, heroCanBet: true).gateActive, isFalse);
    });
    test('Sin el As no hay conversión', () {
      final s = GameState(stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 80, potBb: 18,
          hero: HoleCards.parse('Kc4s'), board: Card.parseMany('QhJh4c2h8d'),
          actions: [...g(scared).actions]);
      expect(BlockerBluffConverter.evaluate(s, scared, heroCanBet: true).converts, isFalse);
    });
    test('TT en K-Q-J-9-2 bloquea escalera nuts', () {
      final s = GameState(stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 80, potBb: 18,
          hero: HoleCards.parse('TcTd'), board: Card.parseMany('KhQdJs9c2h'), actions: srpBtn);
      expect(BlockerBluffConverter.nutBlocker(s), contains('escalera'));
    });
  });

  group('4. Timing: insta-call turn -> river 2c brick', () {
    test('IP: river barrel grande 75-100%', () {
      final s = GameState(stake: Stake.nl25, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 85, potBb: 17.1,
          hero: HoleCards.parse('AhQd'), board: Card.parseMany('Ts9s6dKh2c'),
          actions: [...srpBtn,
            a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8),
            a(Street.flop, Position.bb, ActionType.call, 1.8), a(Street.turn, Position.bb, ActionType.check),
            a(Street.turn, Position.btn, ActionType.bet, 4), a(Street.turn, Position.bb, ActionType.call, 4, TimingTell.instaAction),
            a(Street.river, Position.bb, ActionType.check)]);
      expect(TimingTellsMatrix.instaCallTurnIntoRiver(s), (true, true));
      final d = post.decide(s);
      expect(d.action, DecisionAction.betRaise);
      expect(d.sizing!.potPct, inInclusiveRange(75, 100));
      expect(d.ajusteExplotativoRead, contains('Insta-call'));
    });
    test('OOP: check para inducir', () {
      final s = GameState(stake: Stake.nl25, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 90, potBb: 13.5,
          hero: HoleCards.parse('QhTd'), board: Card.parseMany('Ts9s6dKh2c'),
          actions: [...srpBtn,
            a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.check),
            a(Street.turn, Position.bb, ActionType.bet, 4), a(Street.turn, Position.btn, ActionType.call, 4, TimingTell.instaAction)]);
      final d = post.decide(s);
      expect(d.action, DecisionAction.check);
      expect(d.ajusteExplotativoRead, contains('inducir'));
    });
    test('River que completa tras insta-call: 0% farol', () {
      final s = GameState(stake: Stake.nl25, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 85, potBb: 17.1,
          hero: HoleCards.parse('AhQd'), board: Card.parseMany('Ts9s6dKh2s'),
          actions: [...srpBtn,
            a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8),
            a(Street.flop, Position.bb, ActionType.call, 1.8), a(Street.turn, Position.bb, ActionType.check),
            a(Street.turn, Position.btn, ActionType.bet, 4), a(Street.turn, Position.bb, ActionType.call, 4, TimingTell.instaAction),
            a(Street.river, Position.bb, ActionType.check)]);
      expect(post.decide(s).action, DecisionAction.check);
    });
    test('Matriz de tells', () {
      expect(TimingTellsMatrix.of(a(Street.turn, Position.bb, ActionType.check, 0, TimingTell.instaAction), Stake.nl10).capped, isTrue);
      expect(TimingTellsMatrix.of(a(Street.flop, Position.bb, ActionType.call, 2, TimingTell.instaAction), Stake.nl10).removesMonsters, isTrue);
      expect(TimingTellsMatrix.of(a(Street.turn, Position.bb, ActionType.check, 0, TimingTell.longTank), Stake.nl10).minPressureSizePct, 75);
      expect(TimingTellsMatrix.of(a(Street.river, Position.bb, ActionType.bet, 20, TimingTell.longTank), Stake.nl25).villainBluffMultiplier, 0.5);
      expect(TimingTellsMatrix.of(a(Street.river, Position.bb, ActionType.bet, 20, TimingTell.longTank), Stake.nl100).villainBluffMultiplier, 1.0);
    });
  });
}
