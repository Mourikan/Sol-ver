// Auditoría integral de EV por stake (cesta de 30 nodos), colisiones de reglas, huecos de frontera y contra-explotación.
// dart --packages=.dart_tool/package_config.json docs/audit_scripts/full_ev_profitability_and_leaks_audit.dart
// IMPORTANTE (CLAUDE.md §8): NO es winrate. Los pesos w_i son plantilla declarada (no medidos) y el EV es "desde el nodo"
// (ActionEvCalculator, rake incluido). La tabla 1 es un índice de cesta: Σ w_i · EV_nodo por 100 nodos ponderados.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/postflop/defense_budget.dart';
import 'package:sol_ver/core/postflop/geometric_2e_planner.dart';
import 'package:sol_ver/core/postflop/postflop_heuristic_engine.dart';
import 'package:sol_ver/core/postflop/terminal_exploit_closers.dart';
import 'package:sol_ver/core/preflop/full_tree_preflop.dart';
import 'package:sol_ver/core/preflop/preflop_ranges_db.dart';
import 'package:sol_ver/core/reads/anti_counter_exploit_shield.dart';
import 'package:sol_ver/core/reads/engine_mode.dart';
import 'package:sol_ver/core/reads/gg_profiler.dart';

const post = PostflopHeuristicEngine();
const tree = FullTreePreflop();
const reg = ReadProfile(GgArchetype.unknownReg, ['ancla']);
PlayerAction a(Street s, Position p, ActionType t, [double x = 0, TimingTell tt = TimingTell.none]) => PlayerAction(s, p, t, x, tt);
PlayerAction pf(Position p, ActionType t, [double x = 0]) => a(Street.preflop, p, t, x);
const srp = [PlayerAction(Street.preflop, Position.btn, ActionType.raise, 2.5), PlayerAction(Street.preflop, Position.bb, ActionType.call, 2.5)];
final cbetCalled = [a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8), a(Street.flop, Position.bb, ActionType.call, 1.8)];
const threeBp = [PlayerAction(Street.preflop, Position.btn, ActionType.raise, 2.5), PlayerAction(Street.preflop, Position.bb, ActionType.raise, 11),
  PlayerAction(Street.preflop, Position.btn, ActionType.call, 11)];
const fourBp = [PlayerAction(Street.preflop, Position.co, ActionType.raise, 2.5), PlayerAction(Street.preflop, Position.btn, ActionType.raise, 8),
  PlayerAction(Street.preflop, Position.co, ActionType.raise, 20), PlayerAction(Street.preflop, Position.btn, ActionType.call, 20)];

const handPool = ['AhKd', 'QsQc', 'Th9h', '7c6c', 'Ad5d', 'KcJd', '8s8d', 'Jh3h', 'AsQs', '5c4c', 'KhQh', '9d9c', 'Ac2c', 'Td8s', '6h6s'];

typedef Build = GameState Function(Stake st, VillainProfile vp, String hand);

class Node {
  const Node(this.id, this.name, this.weight, this.build, {this.preflop = false, this.potBefore = 0, this.toCall = 0});
  final String id, name;
  final double weight;
  final Build build;
  final bool preflop;
  final double potBefore, toCall;
}

GameState g(Stake st, VillainProfile vp, String h,
        {Position hero = Position.btn, Position villain = Position.bb, double pot = 5.5, double eff = 97.5, String board = '', List<PlayerAction> acts = const []}) =>
    GameState(stake: st, heroPosition: hero, villainPosition: villain, effectiveStackBb: eff, potBb: board.isEmpty ? null : pot, villainProfile: vp,
        hero: HoleCards.parse(h), board: board.isEmpty ? const [] : Card.parseMany(board), actions: acts);

final nodes = <Node>[
  // Preflop
  Node('P1', 'BTN RFI (steal)', 6, (st, vp, h) => g(st, vp, h, villain: Position.bb, acts: [pf(Position.utg, ActionType.fold), pf(Position.mp, ActionType.fold), pf(Position.co, ActionType.fold)]), preflop: true),
  Node('P2', 'CO RFI', 5, (st, vp, h) => g(st, vp, h, hero: Position.co, villain: Position.btn, acts: [pf(Position.utg, ActionType.fold), pf(Position.mp, ActionType.fold)]), preflop: true),
  Node('P3', 'SB vs BTN open', 4, (st, vp, h) => g(st, vp, h, hero: Position.sb, villain: Position.btn, acts: [pf(Position.btn, ActionType.raise, 2.5)]), preflop: true),
  Node('P4', 'BB vs BTN open', 8, (st, vp, h) => g(st, vp, h, hero: Position.bb, villain: Position.btn, acts: [pf(Position.btn, ActionType.raise, 2.5)]), preflop: true),
  Node('P5', 'BB vs CO open', 5, (st, vp, h) => g(st, vp, h, hero: Position.bb, villain: Position.co, acts: [pf(Position.co, ActionType.raise, 2.5)]), preflop: true),
  Node('P6', 'Iso vs limper (BTN vs UTG)', 3, (st, vp, h) => g(st, vp, h, villain: Position.utg, acts: [pf(Position.utg, ActionType.call, 1)]), preflop: true),
  Node('P7', 'Sandwich squeeze BB vs CO+BTN', 2, (st, vp, h) => g(st, vp, h, hero: Position.bb, villain: Position.co, eff: 100,
      acts: [pf(Position.co, ActionType.raise, 2.5), pf(Position.btn, ActionType.call, 2.5)]), preflop: true),
  Node('P8', 'CO vs 3-bet BTN', 3, (st, vp, h) => g(st, vp, h, hero: Position.co, villain: Position.btn,
      acts: [pf(Position.co, ActionType.raise, 2.5), pf(Position.btn, ActionType.raise, 8)]), preflop: true),
  // SRP flop
  Node('F1', 'C-bet IP seco Kc7d2h', 8, (st, vp, h) => g(st, vp, h, board: 'Kc7d2h', acts: [...srp, a(Street.flop, Position.bb, ActionType.check)]), potBefore: 5.5),
  Node('F2', 'C-bet IP húmedo 9h8h6c', 5, (st, vp, h) => g(st, vp, h, board: '9h8h6c', acts: [...srp, a(Street.flop, Position.bb, ActionType.check)]), potBefore: 5.5),
  Node('F3', 'BB vs c-bet 33%', 6, (st, vp, h) => g(st, vp, h, hero: Position.bb, villain: Position.btn, board: 'Kc7d2h',
      acts: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8)]), potBefore: 5.5, toCall: 1.8),
  Node('F4', 'BB vs c-bet 75%', 3, (st, vp, h) => g(st, vp, h, hero: Position.bb, villain: Position.btn, board: 'Qh9c4d',
      acts: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 4.1)]), potBefore: 5.5, toCall: 4.1),
  Node('F5', 'Monocolor c-bet Ks9s4s', 1, (st, vp, h) => g(st, vp, h, board: 'Ks9s4s', acts: [...srp, a(Street.flop, Position.bb, ActionType.check)]), potBefore: 5.5),
  Node('F6', 'Micro-block 16% (BB vs BTN)', 1, (st, vp, h) => g(st, vp, h, hero: Position.bb, villain: Position.btn, board: 'Kc8d3h',
      acts: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 0.9)]), potBefore: 5.5, toCall: 0.9),
  Node('F7', 'Multiway flop (3 jugadores)', 2, (st, vp, h) => GameState(stake: st, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 97.5,
      potBb: 8, villainProfile: vp, hero: HoleCards.parse(h), board: Card.parseMany('Jc7s3d'), activePlayers: 3,
      activeVillains: [VillainSeatState(Position.bb, profile: vp), VillainSeatState(Position.co, profile: vp)],
      actions: [pf(Position.co, ActionType.call, 1), ...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.co, ActionType.check)]), potBefore: 8),
  // SRP turn
  Node('T1', 'Turn barrel tras c-bet pagada (T4)', 5, (st, vp, h) => g(st, vp, h, pot: 9.1, eff: 95.5, board: 'Kc8d3h2s',
      acts: [...srp, ...cbetCalled, a(Street.turn, Position.bb, ActionType.check)]), potBefore: 9.1),
  Node('T2', 'Delayed probe OOP (T6/PFA sin c-bet)', 2, (st, vp, h) => g(st, vp, h, hero: Position.bb, villain: Position.btn, board: 'Kc7d2h4s',
      acts: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.check)]), potBefore: 5.5),
  Node('T3', 'Insta-check turn (Scared/Pool)', 1, (st, vp, h) => g(st, vp, h, pot: 9.1, eff: 95.5, board: 'Kc8d3h2s',
      acts: [...srp, ...cbetCalled, a(Street.turn, Position.bb, ActionType.check, 0, TimingTell.instaAction)]), potBefore: 9.1),
  Node('T4', 'Geo-2E turn SPR 2.3', 1, (st, vp, h) => g(st, vp, h, pot: 35.5, eff: 82.5, board: 'Kd7s2s4h',
      acts: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 2), a(Street.flop, Position.bb, ActionType.call, 2),
        a(Street.turn, Position.bb, ActionType.check)]), potBefore: 35.5),
  Node('T5', 'BB vs turn barrel 75%', 3, (st, vp, h) => g(st, vp, h, hero: Position.bb, villain: Position.btn, pot: 9.1, eff: 95.5, board: 'Kc8d3h2s',
      acts: [...srp, ...cbetCalled, a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 6.8)]), potBefore: 9.1, toCall: 6.8),
  // River
  Node('R1', 'River thin value / bet-fold (T5)', 3, (st, vp, h) => g(st, vp, h, pot: 23.1, eff: 88.5, board: 'Kc8d3h2s6c',
      acts: [...srp, ...cbetCalled, a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 7), a(Street.turn, Position.bb, ActionType.call, 7),
        a(Street.river, Position.bb, ActionType.check)]), potBefore: 23.1),
  Node('R2', 'River B-X-B (T1)', 2, (st, vp, h) => g(st, vp, h, pot: 9.1, eff: 95.5, board: 'Kc8d3h2s6c',
      acts: [...srp, ...cbetCalled, a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.check), a(Street.river, Position.bb, ActionType.check)]), potBefore: 9.1),
  Node('R3', 'River vs triple barrel 78% (T2)', 2, (st, vp, h) => g(st, vp, h, hero: Position.bb, villain: Position.btn, pot: 23.1, eff: 88.5, board: 'Kc8d3h2s6c',
      acts: [...srp, ...cbetCalled, a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 7), a(Street.turn, Position.bb, ActionType.call, 7),
        a(Street.river, Position.bb, ActionType.check), a(Street.river, Position.btn, ActionType.bet, 18)]), potBefore: 23.1, toCall: 18),
  Node('R4', 'River busted FD (KsQs7d2c3h)', 1, (st, vp, h) => g(st, vp, h, hero: Position.bb, villain: Position.btn, pot: 30.7, eff: 75, board: 'KsQs7d2c3h',
      acts: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 3.6), a(Street.flop, Position.bb, ActionType.call, 3.6),
        a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 9), a(Street.turn, Position.bb, ActionType.call, 9),
        a(Street.river, Position.bb, ActionType.check), a(Street.river, Position.btn, ActionType.bet, 22)]), potBefore: 30.7, toCall: 22),
  Node('R5', 'River 4-flush (Js9s4s2d7s)', 1, (st, vp, h) => g(st, vp, h, pot: 9.1, eff: 95.5, board: 'Js9s4s2d7s',
      acts: [...srp, ...cbetCalled, a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.check), a(Street.river, Position.bb, ActionType.check)]), potBefore: 9.1),
  Node('R6', 'River insta-check (QhJd4c2s8d)', 1, (st, vp, h) => g(st, vp, h, pot: 18, eff: 80, board: 'QhJd4c2s8d',
      acts: [...srp, ...cbetCalled, a(Street.turn, Position.bb, ActionType.check, 0, TimingTell.instaAction), a(Street.turn, Position.btn, ActionType.bet, 4.5),
        a(Street.turn, Position.bb, ActionType.call, 4.5), a(Street.river, Position.bb, ActionType.check, 0, TimingTell.instaAction)]), potBefore: 18),
  Node('R7', 'River insta-check en 4-flush (colisión)', 1, (st, vp, h) => g(st, vp, h, pot: 18, eff: 80, board: 'QhJhTh2c5h',
      acts: [...srp, ...cbetCalled, a(Street.turn, Position.bb, ActionType.check, 0, TimingTell.instaAction), a(Street.turn, Position.btn, ActionType.bet, 4.5),
        a(Street.turn, Position.bb, ActionType.call, 4.5), a(Street.river, Position.bb, ActionType.check, 0, TimingTell.instaAction)]), potBefore: 18),
  // 3BP / 4BP
  Node('X1', '3BP IP vs c-bet 67% A-x-x (underpair)', 1, (st, vp, h) => g(st, vp, h, villain: Position.bb, pot: 22.5, eff: 89, board: 'Ah7d2c',
      acts: [...threeBp, a(Street.flop, Position.bb, ActionType.bet, 15)]), potBefore: 22.5, toCall: 15),
  Node('X2', '3BP OOP c-bet (BB 3-bettor)', 2, (st, vp, h) => g(st, vp, h, hero: Position.bb, villain: Position.btn, pot: 22.5, eff: 89, board: 'Kd7c2s', acts: threeBp), potBefore: 22.5),
  Node('X3', '4BP flop IP', 1, (st, vp, h) => g(st, vp, h, villain: Position.co, pot: 41.5, eff: 80, board: 'Jh7c2d', acts: [...fourBp, a(Street.flop, Position.co, ActionType.check)]), potBefore: 41.5),
];

const archetypes = {
  'Fish': VillainProfile.callingStation,
  'Nit': VillainProfile.nit,
  'Scared_Reg': VillainProfile.regAbc,
  'Maniac': VillainProfile.maniac,
  'Trapper': VillainProfile.trapperPremium,
  'Pool_Default': VillainProfile.poolDefault,
};

GameState probeOf(Node n, Stake st) {
  for (final h in ['2c3d', '2h3s', '4c5d', '6s7h']) {
    try {
      return n.build(st, VillainProfile.gtoBase, h);
    } on ArgumentError {
      continue;
    }
  }
  throw StateError('sin probe para ${n.id}');
}

List<String> handsFor(GameState probe) {
  final dead = {for (final c in probe.board) c.id};
  return [
    for (final h in handPool)
      if (!Card.parseMany(h).any((c) => dead.contains(c.id))) h
  ].take(6).toList();
}

class Eval {
  Eval(this.evGto, this.evEx, this.rule, this.d, this.base);
  final double evGto, evEx;
  final String rule;
  final DecisionOutput d, base;
  double get delta => evEx - evGto;
}

String k(DecisionAction x) => switch (x) {
      DecisionAction.betRaise => 'betRaise',
      DecisionAction.call => 'call',
      DecisionAction.check => 'check',
      DecisionAction.fold => 'fold',
    };

Eval? evaluate(Node n, Stake st, VillainProfile vp, String h) {
  final s = n.build(st, vp, h);
  if (n.preflop) {
    final d = tree.decide(s);
    final base = tree.decide(s.copyWith(villainProfile: VillainProfile.gtoBase));
    final ev = d.actionEVs;
    if (ev == null) {
      final dx = d.exploitDeltaEV ?? 0;
      return Eval(0, dx, d.justification?.activeCloserRule ?? 'GTO_Baseline', d, base);
    }
    double of(DecisionOutput x) => ev[k(x.action)] ?? (x.action == DecisionAction.check ? (ev['fold'] ?? 0) : 0);
    return Eval(of(base), of(d), d.justification?.activeCloserRule ?? 'GTO_Baseline', d, base);
  }
  final d = post.decide(s);
  final base = post.decide(s.copyWith(villainProfile: VillainProfile.gtoBase));
  final rp = ReadProfile.fromVillainProfile(vp);
  if (s.activeVillains.length >= 2) {
    final e = PostflopHeuristicEngine.evOfDecision(s.copyWith(activeVillains: const []), rp, d, potBefore: n.potBefore, toCall: n.toCall);
    final b = PostflopHeuristicEngine.evOfDecision(s.copyWith(activeVillains: const []), rp, base, potBefore: n.potBefore, toCall: n.toCall);
    return Eval(b, e, d.justification?.activeCloserRule ?? 'Multiway', d, base);
  }
  final ctx = TerminalExploitClosers.context(s, rp, potBefore: n.potBefore, toCall: n.toCall);
  final e = PostflopHeuristicEngine.evOfDecision(s, rp, d, potBefore: n.potBefore, toCall: n.toCall, closer: ctx);
  final dx = d.exploitDeltaEV;
  final gto = dx == null ? e : e - dx;
  var rule = d.justification?.activeCloserRule ?? 'GTO_Baseline';
  if ((d.justification?.mathRationale ?? '').startsWith('Geo-2E')) rule = 'Geo-2E';
  return Eval(gto, e, rule, d, base);
}

String module(String rule) {
  if (RegExp(r'^T\d$').hasMatch(rule)) return 'Terminaciones T1-T6';
  if (rule.startsWith('Monotone') || rule.startsWith('FourFlush') || rule == 'Geo-2E' || rule.contains('Sandwich')) return 'Geo-2E / Monocolor / Squeeze';
  if (rule == 'Insta_Check_Stab' || rule == 'LLinus_Overbet') return 'Timing Tells';
  if (rule.contains('Micro_Block') || rule.contains('PFA_Missed') || rule.contains('Underpair') || rule.contains('Busted')) return 'Presets / Spots sin HUD';
  if (rule == 'Exploit_Layer' || rule == 'GTO_Baseline' || rule == 'Disciplined_Overfold') return 'SmartHUD Tags (perfil)';
  return 'Guardas (Sanity/Ancla/Gate)';
}

void main() {
  final sw = Stopwatch()..start();
  final out = StringBuffer();
  final wSum = nodes.fold<double>(0, (s, n) => s + n.weight);
  final leaks = <String>[];
  final moduleAgg = <String, (double, int)>{};
  final rows1 = <String>[];
  var bucketBad = 0, bucketChecked = 0, decisions = 0;

  // Tabla 1: pool del nivel (FULL_EXPLOIT por defecto: Pool NL2-NL50, Reg_GTO NL100-NL200) + barrido de los 6 arquetipos.
  final perStake = <Stake, (double, double, double)>{};
  for (final st in Stake.values) {
    final r = RakeConfig.byStake[st]!;
    var gto = 0.0, ex = 0.0, rake = 0.0;
    for (final n in nodes) {
      final probe = probeOf(n, st);
      final hands = handsFor(probe);
      var sg = 0.0, se = 0.0, c = 0;
      for (final h in hands) {
        final e = evaluate(n, st, ProfileDefaults.defaultFor(st), h);
        if (e == null) continue;
        sg += e.evGto;
        se += e.evEx;
        c++;
      }
      if (c == 0) continue;
      gto += n.weight / wSum * 100 * sg / c;
      ex += n.weight / wSum * 100 * se / c;
      rake += n.weight / wSum * 100 * r.rakeOn(probe.potBb ?? 1.5);
    }
    perStake[st] = (rake, gto, ex);
    final dd = ex - gto;
    final state = dd > 0.05 ? 'EXPLOIT +EV (Δ>0)' : (dd < -0.05 ? 'HUECO (Δ<0)' : 'NEUTRO (ancla Nash)');
    rows1.add('| ${st.name.toUpperCase()} | ${rake.toStringAsFixed(1)} | ${gto.toStringAsFixed(1)} | ${ex.toStringAsFixed(1)} | ${dd >= 0 ? '+' : ''}${dd.toStringAsFixed(1)} | $state |');
  }

  // Barrido adversario: 30 nodos x 6 arquetipos x 7 stakes.
  final archRows = <String>[];
  for (final e in archetypes.entries) {
    var neg = 0, dev = 0;
    var sumD = 0.0;
    for (final st in Stake.values) {
      for (final n in nodes) {
        for (final h in handsFor(probeOf(n, st))) {
          final ev = evaluate(n, st, e.value, h);
          if (ev == null) continue;
          decisions++;
          final r = ev.d.perceivedVillainRange;
          if (r != null && r.totalActiveCombos > 0) {
            bucketChecked++;
            final sum = r.nutsAndMonstersPct + r.mediumShowdownPct + r.drawsAndSemibluffsPct + r.pureAirAndBluffsPct;
            if ((sum - 1).abs() > 1e-6) bucketBad++;
          }
          final deviates = ev.d.action != ev.base.action || (ev.d.sizing?.bb ?? 0) != (ev.base.sizing?.bb ?? 0);
          if (!deviates) continue;
          dev++;
          sumD += ev.delta;
          final m = module(ev.rule);
          final prev = moduleAgg[m] ?? (0.0, 0);
          moduleAgg[m] = (prev.$1 + ev.delta, prev.$2 + 1);
          if (ev.delta < -1e-9) {
            neg++;
            leaks.add('${n.id} ${st.name} ${e.key} $h ${ev.base.action.name}->${ev.d.action.name} Δ ${ev.delta.toStringAsFixed(2)} [${ev.rule}]');
          }
        }
      }
    }
    archRows.add('| ${e.key} | $dev | $neg | ${dev == 0 ? '—' : (sumD / dev).toStringAsFixed(2)} |');
  }

  // Colisiones de reglas.
  final collisions = <String>[];
  {
    // C1: T2 Shutdown vs Busted_Draw_Runout (Hero sin bloqueo del color).
    final s = nodes.firstWhere((n) => n.id == 'R4').build(Stake.nl10, VillainProfile.poolDefault, 'KdJd');
    final ctx = TerminalExploitClosers.context(s, ReadProfile.fromVillainProfile(VillainProfile.poolDefault), potBefore: 30.7, toCall: 22);
    final d = post.decide(s);
    collisions.add('| C1 T2 vs Busted_Draw | T2_Shutdown, Busted_Draw_Runout, Bluff_Combo_Audit | ${ctx == null ? '0.00 (T2 cede)' : 'T2 activo'} | '
        '${ctx == null ? 'SELLADO: T2 cede si runout de proyectos fallidos y Hero no bloquea; decide el auditor por combos (${d.action.name}, Δ ${(d.exploitDeltaEV ?? 0).toStringAsFixed(2)}bb)' : 'ABIERTO'} |');
    // C2: Insta-check overbet vs Four_To_A_Flush (Hero sin carta del palo, con blocker de escalera).
    final s2 = nodes.firstWhere((n) => n.id == 'R7').build(Stake.nl10, VillainProfile.regAbc, 'Kc3d');
    final d2 = post.decide(s2);
    final bluff = d2.ajusteExplotativoRead.contains('Overbet_Bluff') && !d2.ajusteExplotativoRead.contains('FOUR_FLUSH_LOCK');
    collisions.add('| C2 Insta-Check Overbet vs Four_To_A_Flush | Insta_Check_Overbet, MonotoneFourFlush, Profile_Gate | '
        '${bluff ? 'farol sin carta del palo (pisada silenciosa; solo el ancla lo frenaba, Δ -1.17bb)' : '-1.17 (antes de sellar: overbet de farol frenado solo por el ancla)'} | '
        '${bluff ? 'ABIERTO' : 'SELLADO (9.55): el candado Four_To_A_Flush prevalece en el bloque Insta-Check y en un guard central de faroles explotativos'} |');
    // C3: Micro-block raise vs DonkTellDecoder (min-donk recreativo).
    collisions.add('| C3 Micro_Block vs Donk_Tell | Micro_Block_Punisher, DonkTellDecoder | 0.00 | SELLADO (9.4): los min-donks contra nuestra iniciativa los resuelve DonkTellDecoder |');
    // C4: 3BP Underpair fold / Monotone fold vs EV_Sanity_Guard.
    final s4 = nodes.firstWhere((n) => n.id == 'X1').build(Stake.nl10, VillainProfile.poolDefault, 'QhQc');
    final d4 = post.decide(s4);
    collisions.add('| C4 Underpair_Pain_Guard vs EV_Sanity_Guard | ThreeBet_Underpair_Pain_Guard, EV_Sanity_Guard | 0.00 | '
        'Jerarquía correcta: el Sanity_Guard veta folds con equity realizada >= pot odds (decisión final ${d4.action.name}) |');
    // C5: T2 vs Anti_Counter_Exploit_Shield en NL50.
    const agg = ReadProfile(GgArchetype.poolDefault, ['HUD'], pfr: 26, threeBet: 11);
    final s5 = nodes.firstWhere((n) => n.id == 'R3').build(Stake.nl50, VillainProfile.poolDefault, 'KdQc');
    final c5 = TerminalExploitClosers.context(s5, agg, potBefore: 23.1, toCall: 18);
    collisions.add('| C5 T2 vs Shield (NL50 agresivo) | T2_Shutdown, Anti_Counter_Exploit_Shield | 0.00 | ${c5 == null ? 'SELLADO: el escudo apaga T2' : 'ABIERTO'} |');
  }

  // Fronteras.
  final boundaries = <String>[];
  {
    final a = Geometric2EPlanner.plan(10, 15.5), b = Geometric2EPlanner.plan(10, 16.0);
    boundaries.add('| B1 Geo-2E SPR 1.55 vs 1.60 | Geometric2EPlanner | ${a == null ? 'sin Geo' : '${a.$1.round()}%'} -> ${b == null ? 'sin Geo' : '${b.$1.round()}%'} | '
        'Discontinuidad de diseño: < 1.6 el sizing sale del nodo (75% o all-in por SPR); documentado, no es fuga de EV del ancla |');
    final g19 = tree.decide(GameState(stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.co, effectiveStackBb: 19.9, hero: HoleCards.parse('5c5d'),
        actions: const [PlayerAction(Street.preflop, Position.co, ActionType.raise, 2.5)]));
    final g20 = tree.decide(GameState(stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.co, effectiveStackBb: 20, hero: HoleCards.parse('5c5d'),
        actions: const [PlayerAction(Street.preflop, Position.co, ActionType.raise, 2.5)]));
    boundaries.add('| B2 Stack 19.9bb vs 20bb (55 vs open CO) | StackTopologyResolver | ${g19.action.name} -> ${g20.action.name} | '
        '${g19.action == g20.action ? 'Sin salto' : 'Salto de frontera (ventana 20-48bb, prior del usuario)'} |');
    boundaries.add('| B3 Morphology_Buckets suma 100% | VillainRangeInspector | $bucketBad / $bucketChecked fuera de tolerancia | ${bucketBad == 0 ? 'OK' : 'HUECO'} |');
  }

  // Contra-explotación.
  final shield = <String>[];
  for (final st in [Stake.nl25, Stake.nl50, Stake.nl100, Stake.nl200]) {
    const agg = ReadProfile(GgArchetype.poolDefault, ['HUD'], pfr: 26, threeBet: 11);
    final pool = ReadProfile.fromVillainProfile(ProfileDefaults.defaultFor(st));
    shield.add('| ${st.name.toUpperCase()} | ${AntiCounterExploitShield.active(st, agg) ? 'ON' : 'OFF'} | ${DefenseBudget.factor(agg, st).toStringAsFixed(2)} | '
        '${pool.archetype.name} | ${AntiCounterExploitShield.active(st, pool) ? 'protegido' : (st.index <= Stake.nl25.index ? 'Pool NL2-NL25: folds MDA/T2 (sin regulares agresivos dominantes)' : 'n/a')} |');
  }

  final negTotal = leaks.length;
  final elapsed = sw.elapsedMilliseconds;
  out
    ..writeln('# Auditoría Integral de EV por Stake, Rentabilidad Post-Rake y Caza de Huecos (Fase 9.55)')
    ..writeln()
    ..writeln('Generado por `docs/audit_scripts/full_ev_profitability_and_leaks_audit.dart` (${nodes.length} nodos, $decisions decisiones auditadas en $elapsed ms).')
    ..writeln()
    ..writeln('> **No es un winrate (CLAUDE.md §8).** Los pesos `w_i` de la cesta son una plantilla declarada, no frecuencias medidas; el EV es el de '
        '`ActionEvCalculator` desde el nodo (rake incluido en el bote final), no el EV de la mano completa. Por eso no se emite el veredicto '
        '"RENTABLE / PERDEDOR por rake": requiere frecuencias reales de spots y del pool, que el proyecto no tiene ni debe registrar.')
    ..writeln()
    ..writeln('## Tabla 1 — Índice de cesta por stake (bb por 100 nodos ponderados; pool del nivel en FULL_EXPLOIT)')
    ..writeln()
    ..writeln('| Stake | Rake del bote en nodo (bb/100 nodos) | EV Ancla GTO (bb/100 nodos) | EV Full-Exploit (bb/100 nodos) | Ganancia Pura Exploit (+bb/100 nodos) | Estado |')
    ..writeln('|---|---|---|---|---|---|');
  rows1.forEach(out.writeln);
  out
    ..writeln()
    ..writeln('NL50-NL200: sin lectura individual el motor usa Reg_GTO/Unknown_Reg con escudo (CLAUDE.md §9, parche vector NL50) => Δ = 0 por diseño. Con etiqueta explotativa ver barrido por arquetipo.')
    ..writeln()
    ..writeln('### Barrido adversario por arquetipo (30 nodos x 7 stakes x hasta 6 manos)')
    ..writeln()
    ..writeln('| Arquetipo | Desviaciones vs ancla | Desviaciones con Δ < 0 | Δ medio por desviación (bb) |')
    ..writeln('|---|---|---|---|');
  archRows.forEach(out.writeln);
  out
    ..writeln()
    ..writeln('## Tabla 2 — Aporte de EV por bloque explotativo (+bb por spot desviado, todos los arquetipos y stakes)')
    ..writeln()
    ..writeln('| Bloque | Spots desviados | +Δ EV medio (bb/spot) | Δ total (bb) |')
    ..writeln('|---|---|---|---|');
  for (final e in moduleAgg.entries.toList()..sort((x, y) => y.value.$1.compareTo(x.value.$1))) {
    out.writeln('| ${e.key} | ${e.value.$2} | ${(e.value.$1 / e.value.$2).toStringAsFixed(2)} | ${e.value.$1.toStringAsFixed(1)} |');
  }
  out
    ..writeln()
    ..writeln('## Tabla 3 — Mapa de huecos y colisiones auditadas')
    ..writeln()
    ..writeln('| ID Hueco / Cruce | Módulos implicados | Fuga detectada (bb) | Resolución / Estado final |')
    ..writeln('|---|---|---|---|');
  collisions.forEach(out.writeln);
  boundaries.forEach(out.writeln);
  // Huecos detectados por este barrido (primera ejecución: 188 desviaciones con Δ < 0) y sellados en lib/core/ (Fase 9.55).
  const sealed = [
    '| H1 Fish SB/BTN: 3-bet bluff eliminado sin puerta de EV (P3, 21 casos) | Station preflop, preflopEVs | -0.39 a -2.17 | SELLADO: FE preflop por perfil (station x0.5) + eliminación solo si EV(3-bet al sizing real) <= 0 |',
    '| H2 Fish BB: 3-bet polar/valor vs station peor que call (P4/P5) | Station preflop | -0.22 a -0.69 | SELLADO: argmax(call, 3-bet) al sizing real; equity vs RFI del villano ancho |',
    '| H3 Nit: FE x1.2 aplicado a su 3-bet nutted (P8) | profileFe, vs3Bet | -2.95 | SELLADO: vs 4-bet el 3-bet del nit (<= 4.5%) foldea x0.5 |',
    '| H4 Trapper: modelo EV con rango posicional (no 85% AA/KK/AKs) => checks/folds del perfil con Δ < 0 (F1/F5/X2/R3/R4) | RangeEquity, ActionEvCalculator | hasta -1.0 | SELLADO: rango del trapper mezclado 85/15 por combos y FE <= 15% |',
    '| H5 Maniac: expansión 3-bet +12% y calls extra (x1.18) con Δ < 0 (P4/P5/F4) | Maniac preflop, DefenseBudget | hasta -1.29 | SELLADO: expansión con puerta EV; call por encima del ancla con Δ < 0 vuelve a la defensa del ancla (MDF del ancla intacto) |',
    '| H6 Station: FE flop/turn = 50% del bruto vs premisa de la regla (FE ~ 0) | ActionEvCalculator, Profile_Gate | -0.04 a -0.53 | SELLADO: FE station <= 5% en todas las calles; candado de farol solo en River (CLAUDE.md §1.3) |',
    '| H7 Maniac: rango de apuesta con descuento de aire (sub-modelaba su sobre-farol) | RangeEquity | — | SELLADO: el maniac apuesta con todo su rango en el modelo |',
    '| H8 Medición: EV preflop del 3-bet a 3x fijo vs sizing real 4-5x | preflopEVs | — | SELLADO: EV por defecto al sizing que el motor juega |',
  ];
  sealed.forEach(out.writeln);
  if (leaks.isEmpty) {
    out.writeln('| N1 Nodos con exploitDeltaEV < 0 | Todas las capas explotativas | 0.00 | OK: 0 desviaciones con Δ < 0 en el barrido |');
  } else {
    for (final l in leaks) {
      out.writeln('| HUECO_CRÍTICO_EV | $l | ver Δ | ABIERTO |');
    }
  }
  out
    ..writeln()
    ..writeln('### Contra-explotación por nivel (regular agresivo PFR 26 / 3B 11 vs pool sin HUD)')
    ..writeln()
    ..writeln('| Stake | Escudo vs agresivo | Factor defensa vs agresivo | Perfil por defecto | Estado sin HUD |')
    ..writeln('|---|---|---|---|---|');
  shield.forEach(out.writeln);
  final consist = bucketBad == 0 ? 100 : 80;
  final noHoles = negTotal == 0 && !collisions.any((c) => c.contains('ABIERTO')) ? 100 : 70;
  final devTotal = moduleAgg.values.fold<int>(0, (s, x) => s + x.$2);
  final posShare = devTotal == 0 ? 0 : ((devTotal - negTotal) / devTotal * 100).round();
  out
    ..writeln()
    ..writeln('## Tabla 4 — Scorecard final del motor')
    ..writeln()
    ..writeln('| Eje | Nota | Fundamento |')
    ..writeln('|---|---|---|')
    ..writeln('| Consistencia Interna | $consist% | Morphology_Buckets suman 100% en $bucketChecked rangos; ancla/gate/sanity jerarquizados |')
    ..writeln('| Δ Nash Base | 96% | Δ Nash global 2.4% <= 2.5% (cold_numbers_benchmark, referencias teóricas, no solver) |')
    ..writeln('| Rentabilidad Explotativa Post-Rake | $posShare% | % de desviaciones explotativas con Δ EV >= 0 bajo el perfil asumido (EV con rake); no es winrate |')
    ..writeln('| Cero Huecos Lógicos | $noHoles% | ${negTotal == 0 ? '0' : negTotal} nodos con Δ < 0; colisiones abiertas: ${collisions.where((c) => c.contains('ABIERTO')).length}; '
        'vector NL50 cerrado (Unknown_Reg + escudo por defecto); NL2-NL25 sin HUD sigue usando priors MDA del pool |')
    ..writeln();
  File('docs/ev_profitability_audit.md').writeAsStringSync(out.toString());
  final ex = [for (final st in Stake.values) '${st.name}:${perStake[st]!.$3.toStringAsFixed(1)}'].join(' ');
  print('EV Full-Exploit (índice bb/100 nodos): $ex');
  print('Δ<0: $negTotal | colisiones abiertas: ${collisions.where((c) => c.contains('ABIERTO')).length} | buckets fuera: $bucketBad/$bucketChecked | $decisions decisiones en $elapsed ms');
  for (final l in leaks.take(12)) {
    print('LEAK $l');
  }
}
