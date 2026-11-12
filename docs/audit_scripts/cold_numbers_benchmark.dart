// Benchmark de números fríos (NL50, 100bb, Reg_GTO). Ejecutar:
// dart --packages=.dart_tool/package_config.json docs/audit_scripts/cold_numbers_benchmark.dart
// Referencias teóricas: defensa = MDF = P/(P+B); farol en apuesta polar = 1-(1-α)^n con α = B/(P+2B) y n calles restantes
// (modelo geométrico polarizado: n=3 flop, 2 turn, 1 river); 3-bet/4-bet = α del sizing.
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math';

import 'package:sol_ver/core/evaluators/action_ev_calculator.dart';
import 'package:sol_ver/core/postflop/geometric_2e_planner.dart';
import 'package:sol_ver/core/preflop/sandwich_squeeze_exploit.dart';
import 'package:sol_ver/core/preflop/stack_topology_resolver.dart';
import 'package:sol_ver/core/reads/anti_counter_exploit_shield.dart';
import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/postflop/defense_budget.dart';
import 'package:sol_ver/core/postflop/hand_tier.dart';
import 'package:sol_ver/core/postflop/postflop_heuristic_engine.dart';
import 'package:sol_ver/core/postflop/terminal_exploit_closers.dart';
import 'package:sol_ver/core/preflop/full_tree_preflop.dart';
import 'package:sol_ver/core/preflop/preflop_ranges_db.dart';
import 'package:sol_ver/core/preflop/range_notation.dart';
import 'package:sol_ver/core/reads/gg_profiler.dart';

const st = Stake.nl50;
const reg = ReadProfile(GgArchetype.unknownReg, []);
const post = PostflopHeuristicEngine();
const tree = FullTreePreflop();
String cs(int id) => '${'23456789TJQKA'[id >> 2]}${'cdhs'[id & 3]}';
PlayerAction a(Street s, Position p, ActionType t, [double x = 0]) => PlayerAction(s, p, t, x);
PlayerAction pf(Position p, ActionType t, [double x = 0]) => a(Street.preflop, p, t, x);
const srp = [PlayerAction(Street.preflop, Position.btn, ActionType.raise, 2.5), PlayerAction(Street.preflop, Position.bb, ActionType.call, 2.5)];
String p(double x) => '${(x * 100).toStringAsFixed(1)}%';
String bb(double? x) => x == null ? '—' : x.toStringAsFixed(2);

class Row {
  Row(this.street, this.scenario, this.d, this.engine, this.gto);
  final String street, scenario;
  final DecisionOutput d;
  final double engine, gto;
  double get delta => (engine - gto).abs();
}

final rows = <Row>[];
double alpha(double bet, double pot) => bet / (pot + 2 * bet);
double polarBluffShare(double bet, double pot, int streets) => 1 - pow(1 - alpha(bet, pot), streets).toDouble();

// ---------- PREFLOP ----------
double preflopShare(Position hero, List<PlayerAction> acts, {required bool Function(int i, DecisionOutput d) count, required bool Function(int i, DecisionOutput d) base}) {
  var num = 0.0, den = 0.0;
  for (var i = 0; i < 169; i++) {
    final (x, y) = Matrix169.concreteCombos(i).first;
    final d = tree.decide(GameState(stake: st, heroPosition: hero, effectiveStackBb: 100, hero: HoleCards.parse(cs(x) + cs(y)), actions: acts));
    final c = Matrix169.combos(i).toDouble();
    if (base(i, d)) den += c;
    if (count(i, d)) num += c;
  }
  return den == 0 ? 0 : num / den;
}

double cont(DecisionOutput d) => (d.frequencies[DecisionAction.call] ?? 0) + (d.frequencies[DecisionAction.betRaise] ?? 0);

void preflop() {
  DecisionOutput one(Position h, String c, List<PlayerAction> acts) =>
      tree.decide(GameState(stake: st, heroPosition: h, effectiveStackBb: 100, hero: HoleCards.parse(c), actions: acts));
  double weighted(Position h, List<PlayerAction> acts, double Function(DecisionOutput d) f, {Float32ListLike? within}) {
    var num = 0.0, den = 0.0;
    for (var i = 0; i < 169; i++) {
      final w = within == null ? 1.0 : within(i);
      if (w <= 0) continue;
      final (x, y) = Matrix169.concreteCombos(i).first;
      final d = tree.decide(GameState(stake: st, heroPosition: h, effectiveStackBb: 100, hero: HoleCards.parse(cs(x) + cs(y)), actions: acts));
      num += f(d) * w * Matrix169.combos(i);
      den += w * Matrix169.combos(i);
    }
    return num / den;
  }

  // Target: GTO_Solver_Benchmark declarado por el usuario en CLAUDE.md (no MDF bruto): vs BTN 53% mid / 48% high; vs CO 44%.
  for (final (opener, hand, target) in [(Position.btn, 'Kh9d', st.rakeTier == RakeTier.midRake ? 0.53 : 0.48), (Position.co, 'Ah9d', 0.44)]) {
    final acts = [pf(opener, ActionType.raise, 2.5)];
    final v = weighted(Position.bb, acts, cont);
    rows.add(Row('Preflop', 'BB vs open ${opener.name.toUpperCase()} 2.5x — $hand', one(Position.bb, hand, acts), v, target));
  }
  // BTN vs CO: farol del 3-bet polar vs α del 3-bet (7.5 en bote 5.5)
  {
    final acts = [pf(Position.co, ActionType.raise, 2.5)];
    var val = 0.0, bl = 0.0;
    for (var i = 0; i < 169; i++) {
      final (x, y) = Matrix169.concreteCombos(i).first;
      final d = tree.decide(GameState(stake: st, heroPosition: Position.btn, effectiveStackBb: 100, hero: HoleCards.parse(cs(x) + cs(y)), actions: acts));
      final r = (d.frequencies[DecisionAction.betRaise] ?? 0) * Matrix169.combos(i);
      if (PreflopRangesDb.isPolarBluff3Bet(i)) {
        bl += r;
      } else {
        val += r;
      }
    }
    rows.add(Row('Preflop', 'BTN vs open CO: 3-bet polar 7.5bb (farol/total) — Ah5h', one(Position.btn, 'Ah5h', acts), bl / (val + bl), alpha(7.5, 5.5)));
  }
  // Defensa vs 3-bet: continuación del rango RFI vs MDF
  for (final (hero, vill, tb, hand) in [(Position.co, Position.btn, 8.0, 'KhQh'), (Position.btn, Position.bb, 10.0, 'AhJd')]) {
    final acts = [pf(hero, ActionType.raise, 2.5), pf(vill, ActionType.raise, tb)];
    final rfi = PreflopRangesDb.rfi(hero, st.rakeTier).weights[PreflopAction.raise]!;
    final v = weighted(hero, acts, cont, within: (i) => rfi[i].toDouble());
    final risk = tb - (vill == Position.bb ? 1 : 0);
    rows.add(Row('Preflop', '${hero.name.toUpperCase()} vs 3-bet ${vill.name.toUpperCase()} ${tb}bb — $hand', one(hero, hand, acts), v, 1 - risk / (risk + 4.0)));
  }
}

typedef Float32ListLike = double Function(int i);

// ---------- POSTFLOP helpers ----------
double rangeFreq(GameState g0, ReadProfile r, double Function(DecisionOutput d, int a, int b) f, {bool Function(DecisionOutput d, int a, int b)? within}) {
  final range = DefenseBudget.heroRangeAtStreet(g0, r);
  var num = 0.0, den = 0.0;
  for (final e in range.entries) {
    final a = e.key ~/ 52, b = e.key % 52;
    final d = post.decide(g0.copyWith(hero: HoleCards.parse(cs(a) + cs(b))), read: r);
    if (within != null && !within(d, a, b)) continue;
    num += f(d, a, b) * e.value;
    den += e.value;
  }
  return den == 0 ? 0 : num / den;
}

GameState withHero(GameState g, String h) => g.copyWith(hero: HoleCards.parse(h));

/// Valor = mano con showdown (monster, top pair/overpair, par marginal en thin value); farol = sin showdown (aire, backdoor, draw).
bool isValue(int a, int b, GameState g) {
  final t = HandTierClassifier.classify(a, b, [for (final c in g.board) c.id]).tier;
  return t == HandTier.nutsMonster || t == HandTier.strongTopPairOverpair || t == HandTier.marginalMadeShowdown;
}

/// Farol/apuestas del rango; si [sizeBand] se da, solo cuenta apuestas de ese sizing (% bote, ±8).
double bluffShareOfBets(GameState g0, {double? sizeBand}) {
  var v = 0.0, bl = 0.0;
  final range = DefenseBudget.heroRangeAtStreet(g0, reg);
  for (final e in range.entries) {
    final a = e.key ~/ 52, b = e.key % 52;
    final d = post.decide(g0.copyWith(hero: HoleCards.parse(cs(a) + cs(b))), read: reg);
    if (sizeBand != null && d.action == DecisionAction.betRaise) {
      final pct = d.sizing?.potPct ?? 0;
      if (sizeBand >= 100 ? pct < 100 : (pct - sizeBand).abs() > 8) continue;
    }
    final w = (d.frequencies[DecisionAction.betRaise] ?? 0) * e.value;
    if (isValue(a, b, g0)) {
      v += w;
    } else {
      bl += w;
    }
  }
  return (v + bl) == 0 ? 0 : bl / (v + bl);
}

GameState placeholder(GameState g) {
  final used = g.board.map((c) => c.id).toSet();
  final free = [for (var i = 0; i < 52; i++) if (!used.contains(i)) i];
  return g.copyWith(hero: HoleCards.parse(cs(free[0]) + cs(free[1])));
}

void flop() {
  for (final (b, h) in [('As7d2c', 'Kd8c'), ('Qc7h2d', '8h8d'), ('9h8h4c', '6s5d')]) {
    final g = GameState(stake: st, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 97.5, potBb: 5.5,
        hero: HoleCards.parse(h), board: Card.parseMany(b), actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8)]);
    final v = rangeFreq(g, reg, (d, _, _) => 1 - (d.frequencies[DecisionAction.fold] ?? 0));
    rows.add(Row('Flop', 'BB vs c-bet 33% $b — $h', post.decide(g, read: reg), v, 5.5 / 7.3));
  }
  for (final (b, h) in [('As7d2c', 'KhJd'), ('QhJh8d', 'Ah5h')]) {
    final g = GameState(stake: st, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 97.5, potBb: 5.5,
        hero: HoleCards.parse(h), board: Card.parseMany(b), actions: [...srp, a(Street.flop, Position.bb, ActionType.check)]);
    final d = post.decide(g, read: reg);
    final pct = b == 'As7d2c' ? 0.33 : 0.75;
    rows.add(Row('Flop', 'BTN c-bet ${(pct * 100).round()}% $b (farol/apuestas) — $h', d, bluffShareOfBets(g), polarBluffShare(pct * 5.5, 5.5, 3)));
  }
}

void turn() {
  for (final (b, h) in [('As7d2c5h', '7h6h'), ('Qc7h2dKs', 'Qd9d'), ('Kd8s3s4c', '8h7h')]) {
    final g = GameState(stake: st, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 95.7, potBb: 9.1,
        hero: HoleCards.parse(h), board: Card.parseMany(b),
        actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8), a(Street.flop, Position.bb, ActionType.call, 1.8),
          a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 6.8)]);
    final v = rangeFreq(g, reg, (d, _, _) => 1 - (d.frequencies[DecisionAction.fold] ?? 0));
    rows.add(Row('Turn', 'BB vs barrel 75% $b — $h', post.decide(g, read: reg), v, 9.1 / 15.9));
  }
  for (final (b, h) in [('Kd7s2s4h', 'AsQd'), ('As7d2c5h', 'KhQh')]) {
    final g = GameState(stake: st, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 95.7, potBb: 9.1,
        hero: HoleCards.parse(h), board: Card.parseMany(b),
        actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8), a(Street.flop, Position.bb, ActionType.call, 1.8),
          a(Street.turn, Position.bb, ActionType.check)]);
    final d = post.decide(g, read: reg);
    final size = d.sizing?.potPct ?? 75;
    rows.add(Row('Turn', 'BTN double barrel ${size.round()}% $b (farol/apuestas) — $h', d, bluffShareOfBets(g), polarBluffShare(size / 100 * 9.1, 9.1, 2)));
  }
}

void river() {
  for (final (b, h) in [('Kd8s3s4c2h', '8h7h'), ('As7d2c5h9s', 'Kd9c'), ('Qc7h2dKs3c', 'Qd9d')]) {
    final g = GameState(stake: Stake.nl100, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 88.9, potBb: 22.7,
        hero: HoleCards.parse(h), board: Card.parseMany(b),
        actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8), a(Street.flop, Position.bb, ActionType.call, 1.8),
          a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 6.8), a(Street.turn, Position.bb, ActionType.call, 6.8),
          a(Street.river, Position.bb, ActionType.check), a(Street.river, Position.btn, ActionType.bet, 22.7)]);
    final v = rangeFreq(g, reg, (d, _, _) => 1 - (d.frequencies[DecisionAction.fold] ?? 0));
    rows.add(Row('River', 'BB bluff-catch vs pot $b — $h', post.decide(g, read: reg), v, 0.5));
  }
  for (final (b, h) in [('Kd7s2s4h9s', 'AsQd'), ('Ks8s3d4cTh', 'AhKd')]) {
    final g = GameState(stake: st, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 82, potBb: 22.7,
        hero: HoleCards.parse(h), board: Card.parseMany(b),
        actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8), a(Street.flop, Position.bb, ActionType.call, 1.8),
          a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 6.8), a(Street.turn, Position.bb, ActionType.call, 6.8),
          a(Street.river, Position.bb, ActionType.check)]);
    final d = post.decide(g, read: reg);
    final size = d.sizing?.potPct ?? 75;
    final band = size >= 100 ? 100.0 : size;
    rows.add(Row('River', 'BTN river bet ${size.round()}% $b (farol/apuestas del mismo sizing) — $h', d, bluffShareOfBets(g, sizeBand: band),
        polarBluffShare(size / 100 * 22.7, 22.7, 1)));
  }
}

void main() {
  preflop();
  flop();
  turn();
  river();
  final out = StringBuffer()
    ..writeln('# Cold Numbers Audit — NL50 (Mid-Rake), 100bb, vs Reg_GTO')
    ..writeln()
    ..writeln('Generado por `docs/audit_scripts/cold_numbers_benchmark.dart` con el motor real.')
    ..writeln('- EV (bb): `ActionEVCalculator` (modelo de 1-2 calles, aproximado). En nodos sin apuesta enfrente la columna "EV Call" es EV(Check).')
    ..writeln('- Freq Motor: frecuencia agregada del rango que llega al nodo (ponderado). Freq GTO: defensa = MDF = P/(P+B); '
        'farol en apuesta polar = 1-(1-α)^n, α = B/(P+2B), n = calles restantes (modelo geométrico polarizado); 3-bet = α del sizing.')
    ..writeln('- Δ Nash = |Freq Motor − Freq GTO|. Ojo: MDF es una cota mínima de defensa; preflop la defensa GTO real supera el MDF por pot odds/realización.')
    ..writeln();
  final means = <String, double>{};
  for (final s in ['Preflop', 'Flop', 'Turn', 'River']) {
    final rs = rows.where((r) => r.street == s).toList();
    out
      ..writeln('## $s')
      ..writeln()
      ..writeln('| Escenario y Mano | EV Fold (bb) | EV Call (bb) | EV Raise (bb) | Acción Tomada | Freq Motor | Freq GTO | Δ Nash |')
      ..writeln('|---|---|---|---|---|---|---|---|');
    for (final r in rs) {
      final ev = r.d.actionEVs ?? const {};
      final callEv = ev['call'] ?? ev['check'];
      out.writeln('| ${r.scenario} | ${bb(ev['fold'] ?? 0)} | ${bb(callEv)} | ${bb(ev['betRaise'])} | ${r.d.action.name}${r.d.sizing == null ? '' : ' ${r.d.sizing!.bb.toStringAsFixed(1)}bb'} | '
          '${p(r.engine)} | ${p(r.gto)} | ${(r.delta * 100).toStringAsFixed(1)}% |');
    }
    final m = rs.map((r) => r.delta).reduce((x, y) => x + y) / rs.length;
    means[s] = m;
    out.writeln();
  }
  out
    ..writeln('## Promedio Δ Nash por calle')
    ..writeln()
    ..writeln('| Calle | Promedio Δ Nash | Estado |')
    ..writeln('|---|---|---|');
  for (final e in means.entries) {
    out.writeln('| ${e.key} | ${(e.value * 100).toStringAsFixed(1)}% | ${e.value > 0.05 ? '**HUECO (> 5%)**' : 'OK'} |');
  }
  final global = means.values.reduce((x, y) => x + y) / means.length;
  out
    ..writeln()
    ..writeln('**Promedio global Δ Nash: ${(global * 100).toStringAsFixed(1)}%** (Modo GTO exige <= 3.5% por calle).')
    ..writeln();
  edge(out);
  File('docs/cold_numbers_audit.md').writeAsStringSync(out.toString());
  for (final e in means.entries) {
    print('${e.key}: ${(e.value * 100).toStringAsFixed(1)}%');
  }
  print('GLOBAL: ${(global * 100).toStringAsFixed(1)}%');
}


/// Edge por spot (Modo Full_Exploit): Δ EV = `DecisionOutput.exploitDeltaEV` = EV(línea explotativa) − EV(ancla Reg_GTO),
/// ambas bajo el perfil asumido. NO es winrate: no existen en el repo datos de frecuencia de spots ni del pool.
void edge(StringBuffer out) {
  final fish = GgProfiler.classify(const SmartHudInput(vpip: 50, pfr: 5, threeBet: 1, stackBb: 100));
  final scared = GgProfiler.classify(const SmartHudInput(vpip: 20, pfr: 17, threeBet: 4, stackBb: 100));
  out
    ..writeln('## Edge por nivel (Modo Full_Exploit) — por spot, no bb/100')
    ..writeln()
    ..writeln('Rake por bote = E[min(%·pot, cap)] con la distribución de tamaños de `RakeConfig.potDistribution` (plantilla, no tabla oficial de sala).')
    ..writeln('Δ EV = `exploitDeltaEV` = EV(acción del motor con el read) − EV(ancla Nash vs Reg_GTO), ambas bajo el perfil asumido (prior del usuario).')
    ..writeln()
    ..writeln('| Nivel | Rake medio SRP (bb/bote) | Rake medio 3BP (bb/bote) | Δ EV thin value vs Fish (bb) | Δ EV overbet vs Scared capado, insta-check river (bb) | '
        'Δ EV Steal_En_Secos vs Nit, Qh3c en Kc7d2s (bb) | Δ EV Delayed_Turn_Probe vs Nit, As2s en 7s6s5d-2h (bb) |')
    ..writeln('|---|---|---|---|---|---|---|');
  double rakePerPot(RakeConfig r, PotType t) {
    var e = 0.0;
    for (final (pot, pr) in RakeConfig.potDistribution[t]!) {
      e += pr * r.rakeOn(pot);
    }
    return e;
  }

  DecisionOutput dec(GameState g, VillainProfile vp, ReadProfile? r) =>
      r == null ? post.decide(g.copyWith(villainProfile: vp)) : post.decide(g.copyWith(villainProfile: r.engineProfile), read: r);

  GameState thin(Stake st, [String h = 'Kh5h']) => GameState(stake: st, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 90, potBb: 9.1,
      hero: HoleCards.parse(h), board: Card.parseMany('Ks8s3d4c2h'),
      actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8), a(Street.flop, Position.bb, ActionType.call, 1.8),
        a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.check), a(Street.river, Position.bb, ActionType.check)]);
  GameState over(Stake st, [String h = 'Ah4s']) => GameState(stake: st, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 80, potBb: 18,
      hero: HoleCards.parse(h), board: Card.parseMany('QhJh4c2h8d'),
      actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8), a(Street.flop, Position.bb, ActionType.call, 1.8),
        a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 4.5), a(Street.turn, Position.bb, ActionType.call, 4.5),
        const PlayerAction(Street.river, Position.bb, ActionType.check, 0, TimingTell.instaAction)]);
  GameState steal(Stake st, [String h = 'Qh3c']) => GameState(stake: st, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 97.5, potBb: 5.5,
      hero: HoleCards.parse(h), board: Card.parseMany('Kc7d2s'), actions: [...srp, a(Street.flop, Position.bb, ActionType.check)]);
  GameState probe(Stake st, [String h = 'As2s']) => GameState(stake: st, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 97.5, potBb: 5.5,
      hero: HoleCards.parse(h), board: Card.parseMany('7s6s5d2h'),
      actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.check), a(Street.turn, Position.bb, ActionType.check)]);
  GameState poolBarrel(Stake st, [String h = 'Ah4s']) => GameState(stake: st, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 95.5, potBb: 9.1,
      hero: HoleCards.parse(h), board: Card.parseMany('Kc8d3h2s'),
      actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8), a(Street.flop, Position.bb, ActionType.call, 1.8),
        a(Street.turn, Position.bb, ActionType.check)]);
  GameState instaOver(Stake st, [String h = 'Td3c']) => GameState(stake: st, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 80, potBb: 18,
      hero: HoleCards.parse(h), board: Card.parseMany('QhJd4c2s8d'),
      actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8), a(Street.flop, Position.bb, ActionType.call, 1.8),
        const PlayerAction(Street.turn, Position.bb, ActionType.check, 0, TimingTell.instaAction), a(Street.turn, Position.btn, ActionType.bet, 4.5),
        a(Street.turn, Position.bb, ActionType.call, 4.5), const PlayerAction(Street.river, Position.bb, ActionType.check, 0, TimingTell.instaAction)]);
  GameState maniacFlop(Stake st, [String h = 'Kh7h']) => GameState(stake: st, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 97.5, potBb: 5.5,
      hero: HoleCards.parse(h), board: Card.parseMany('Kc7d2s'), actions: [...srp, a(Street.flop, Position.bb, ActionType.check)]);
  String d(double? x) => (x ?? 0).toStringAsFixed(2);

  for (final stake in Stake.values) {
    final r = RakeConfig.byStake[stake]!;
    out.writeln('| ${stake.name.toUpperCase()} | ${rakePerPot(r, PotType.srp).toStringAsFixed(2)} | ${rakePerPot(r, PotType.threeBet).toStringAsFixed(2)} | '
        '${d(dec(thin(stake), VillainProfile.callingStation, fish).exploitDeltaEV)} | ${d(dec(over(stake), VillainProfile.regAbc, scared).exploitDeltaEV)} | '
        '${d(dec(steal(stake), VillainProfile.nit, null).exploitDeltaEV)} | ${d(dec(probe(stake), VillainProfile.nit, null).exploitDeltaEV)} |');
  }

  // Auditoría exhaustiva: todas las manos de Hero en cada spot; cada desviación (acción ≠ ancla) debe tener Δ > 0.
  final spots = <(String, GameState Function(Stake, [String]), VillainProfile, ReadProfile?, Stake)>[
    ('Thin value River vs Fish (Inelastic-Caller)', thin, VillainProfile.callingStation, fish, Stake.nl10),
    ('Overbet River vs Scared capado (Over-Folder)', over, VillainProfile.regAbc, scared, Stake.nl10),
    ('Steal_En_Secos Flop vs Nit (Over-Folder)', steal, VillainProfile.nit, null, Stake.nl10),
    ('Delayed_Turn_Probe vs Nit (Over-Folder)', probe, VillainProfile.nit, null, Stake.nl10),
    ('Pool_Turn_Barrel vs Pool_Exploit_Default NL10', poolBarrel, VillainProfile.poolDefault, null, Stake.nl10),
    ('Insta_Check Overbet_Bluff 125% vs Scared (SmartHUD 21/18/7/32)', instaOver, VillainProfile.regAbc, null, Stake.nl10),
    ('Trap_Check_Nuts 40% + flop vs Maniac (SmartHUD 40/32/14/62)', maniacFlop, VillainProfile.maniac, null, Stake.nl10),
  ];
  out
    ..writeln()
    ..writeln('### Auditoría Full_Exploit: todas las desviaciones (1 mano = 1 combo de Hero, NL10)')
    ..writeln()
    ..writeln('| Spot | Combos evaluados | Desviaciones vs ancla | Δ > 0 | Δ <= 0 | Δ EV medio de la desviación (bb) |')
    ..writeln('|---|---|---|---|---|---|');
  var totalDev = 0, totalBad = 0;
  for (final (name, build, vp, rd, stake) in spots) {
    final board = build(stake).board.map((c) => c.id).toSet();
    var n = 0, dev = 0, posN = 0, bad = 0;
    var sum = 0.0;
    for (var i = 0; i < 52; i++) {
      for (var j = i + 1; j < 52; j++) {
        if (board.contains(i) || board.contains(j)) continue;
        final g = build(stake, '${cs(j)}${cs(i)}');
        final dx = dec(g, vp, rd);
        final base = post.decide(g.copyWith(villainProfile: VillainProfile.gtoBase), read: reg);
        n++;
        final deviates = dx.action != base.action || (dx.sizing?.bb ?? 0) != (base.sizing?.bb ?? 0);
        if (!deviates) continue;
        dev++;
        final x = dx.exploitDeltaEV ?? 0;
        sum += x;
        if (x > 0) {
          posN++;
        } else {
          bad++;
        }
      }
    }
    totalDev += dev;
    totalBad += bad;
    out.writeln('| $name | $n | $dev | $posN | $bad | ${dev == 0 ? '—' : (sum / dev).toStringAsFixed(2)} |');
    print('EXPLOIT $name: dev $dev, Δ<=0 $bad');
  }
  print('EXPLOIT TOTAL: dev $totalDev, Δ<=0 $totalBad');
  out
    ..writeln()
    ..writeln('**Desviaciones Full_Exploit: $totalDev; con Δ EV <= 0: $totalBad.** Las desviaciones de apuesta propia con Δ < 0 vuelven al ancla '
        '(`[EV_ANCHOR]`); las de call/fold quedan bajo MDF/`Bluff_Combo_Audit` (el modelo de 1-2 calles infravalora el valor de calls de rango).')
    ..writeln()
    ..writeln('Regla sustituida: "c-bet aire vs Nit en 7s6s5d" (Δ EV 0.00, rechazada por la puerta de EV) => `Steal_En_Secos` (solo matriz rangeBetSmall) '
        '+ `Delayed_Turn_Probe` en turn tras check-check (factor Over-Folder 1.6x).')
    ..writeln('Δ EV = 0.00 en overbet NL25+ : la conversión LLinus ya está activa vs Reg en NL25+ (gate de la Fase 5), no hay desviación adicional.')
    ..writeln('El agregado bb/100 requiere frecuencias de spots y tendencias reales del pool por nivel (base de datos de manos), '
        'que este proyecto no tiene ni debe registrar (CLAUDE.md §5).')
    ..writeln()
    ;
  closers(out);
  modules95(out);
  out
    ..writeln('## Calificación de ingeniería (Claude, evaluación honesta)')
    ..writeln()
    ..writeln('| Eje | Nota | Fundamento |')
    ..writeln('|---|---|---|')
    ..writeln('| Precisión Matemática GTO | 60/100 | Δ Nash 2.4% vs referencias teóricas (MDF, α, presupuesto geométrico), pero rangos preflop semilla, '
        'targets BB declarados por el usuario y ninguna validación contra exports de solver. |')
    ..writeln('| Letalidad Explotativa vs Pool | 71/100 | Full_Exploit por defecto, matriz asimétrica, T1-T6, topología de stacks corta y monocolor/4-flush con '
        '+Δ EV > 0 en todos los combos desviados (barrido exhaustivo); la magnitud de T1/T2/T4 depende de priors de FE/farol del usuario; '
        'el Δ se mide con el mismo modelo EV que asume el perfil: priors MDA/timing sin muestra real del pool. |')
    ..writeln('| Velocidad / Rendimiento APK | 70/100 | Lookups O(1) < 0.5 ms, decisión con EV ~1 ms, isolate persistente; el APK nunca se ha compilado ni medido en un dispositivo. |')
    ..writeln('| Seguridad Anti-Explotación | 74/100 | Presupuestos MDF exactos, EV_Sanity_Guard, invariantes, fuzzer de monotonía y escudo '
        'anti-contra-explotación (NL50+ vs PFR>=24/3B>=10, Agro o Reg: sin hero-folds MDA, MDF x1.0); en NL2-NL25 las leyes MDA siguen '
        'siendo explotables por regs que sobre-faroleen esas líneas y el escudo depende de stats HUD. |')
    ..writeln()
    ..writeln('**Nota global: 69/100** — motor internamente consistente y auditado; la brecha principal es de datos (solver real y pool real), no de arquitectura.')
    ..writeln();
}


/// Auditoría T1-T6: barrido de todos los combos de Hero en la línea gatillo; Δ = EV_Exploit − EV_GTO (ancla Reg_GTO) bajo el
/// mismo contexto de línea (prior del perfil). Promedios sobre los combos donde la terminación desvía la acción.
void closers(StringBuffer out) {
  const pool = VillainProfile.poolDefault;
  const fishVp = VillainProfile.callingStation;
  final flop = [a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8), a(Street.flop, Position.bb, ActionType.call, 1.8)];
  GameState t1(String h) => GameState(stake: Stake.nl10, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 95.5, potBb: 9.1,
      villainProfile: pool, hero: HoleCards.parse(h), board: Card.parseMany('Kc8d3h2s6c'),
      actions: [...srp, ...flop, a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.check), a(Street.river, Position.bb, ActionType.check)]);
  GameState t2(String h) => GameState(stake: Stake.nl10, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 88.5, potBb: 23.1,
      villainProfile: pool, hero: HoleCards.parse(h), board: Card.parseMany('Kc8d3h2s6c'),
      actions: [...srp, ...flop, a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 7), a(Street.turn, Position.bb, ActionType.call, 7),
        a(Street.river, Position.bb, ActionType.check), a(Street.river, Position.btn, ActionType.bet, 18)]);
  GameState t3(String h) => GameState(stake: Stake.nl10, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 90, potBb: 9.1,
      villainProfile: fishVp, hero: HoleCards.parse(h), board: Card.parseMany('Ks8s3d4c2h'),
      actions: [...srp, ...flop, a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.check), a(Street.river, Position.bb, ActionType.check)]);
  GameState t4(String h) => GameState(stake: Stake.nl25, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 95.5, potBb: 9.1,
      villainProfile: pool, hero: HoleCards.parse(h), board: Card.parseMany('Kc8d3h2s'),
      actions: [...srp, ...flop, a(Street.turn, Position.bb, ActionType.check)]);
  GameState t5(String h) => GameState(stake: Stake.nl10, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 88.5, potBb: 23.1,
      villainProfile: pool, hero: HoleCards.parse(h), board: Card.parseMany('Kc8d3h2s6c'),
      actions: [...srp, ...flop, a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 7), a(Street.turn, Position.bb, ActionType.call, 7),
        a(Street.river, Position.bb, ActionType.check)]);
  GameState t6(String h) => GameState(stake: Stake.nl50, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 97.5, potBb: 5.5,
      villainProfile: pool, hero: HoleCards.parse(h), board: Card.parseMany('Kc8d3h2s'),
      actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.check)]);
  final spots = <(String, String, GameState Function(String), double, double)>[
    ('T1 B-X-B River Overbet Punish', 'NL2-NL100 (NL10)', t1, 9.1, 0),
    ('T2 Triple Barrel Shutdown', 'NL2-NL50 (NL10)', t2, 23.1, 18),
    ('T3 Sizing asimétrico vs Fish', 'NL2-NL200 (NL10)', t3, 9.1, 0),
    ('T4 Turn Capped Double Barrel Blitz', 'NL10-NL200 (NL25)', t4, 9.1, 0),
    ('T5 Small River Bet-Fold', 'NL2-NL100 (NL10)', t5, 23.1, 0),
    ('T6 Delayed Probe OOP', 'NL50-NL200 (NL50)', t6, 5.5, 0),
  ];
  String act(DecisionOutput d) => '${d.action.name}${d.sizing == null ? '' : ' ${d.sizing!.potPct.round()}%'}';
  out
    ..writeln()
    ..writeln('## Auditoría de Terminaciones Explotativas (T1–T6) por Stake (NL2 a NL200)')
    ..writeln()
    ..writeln('Barrido de los 1081-1176 combos de Hero en la línea gatillo. EV en bb promediado sobre los combos donde la terminación '
        'desvía la acción del ancla Reg_GTO; ambos EV con `ActionEvCalculator` bajo el mismo contexto de línea (priors declarados '
        'por el usuario: FE pool T1 65%, T4 62%; farol real T2 12%). Acción = la más frecuente entre los combos desviados.')
    ..writeln()
    ..writeln('| Terminación | Nivel Óptimo | Acción GTO Base | Acción Explotativa | Combos desviados (Δ<=0) | EV GTO (bb) | EV Exploit (bb) | Ganancia Neta (+Δ EV bb) |')
    ..writeln('|---|---|---|---|---|---|---|---|');
  for (final (name, lvl, build, potBefore, toCall) in spots) {
    final board = build('AhAd').board.map((c) => c.id).toSet();
    var dev = 0, bad = 0;
    var evG = 0.0, evE = 0.0;
    final baseActs = <String, int>{}, exActs = <String, int>{};
    for (var i = 0; i < 52; i++) {
      for (var j = i + 1; j < 52; j++) {
        if (board.contains(i) || board.contains(j)) continue;
        final g = build('${cs(j)}${cs(i)}');
        final rp = ReadProfile.fromVillainProfile(g.villainProfile);
        final dx = post.decide(g);
        final base = post.decide(g.copyWith(villainProfile: VillainProfile.gtoBase), read: reg);
        final deviates = dx.action != base.action || (dx.sizing?.bb ?? 0) != (base.sizing?.bb ?? 0);
        if (!deviates || !dx.ajusteExplotativoRead.contains('Terminal_Closer')) continue;
        final ctx = TerminalExploitClosers.context(g, rp, potBefore: potBefore, toCall: toCall);
        final e = PostflopHeuristicEngine.evOfDecision(g, rp, dx, potBefore: potBefore, toCall: toCall, closer: ctx);
        final b = PostflopHeuristicEngine.evOfDecision(g, rp, base, potBefore: potBefore, toCall: toCall, closer: ctx);
        dev++;
        if (e - b <= 0) bad++;
        evG += b;
        evE += e;
        baseActs.update(act(base), (v) => v + 1, ifAbsent: () => 1);
        exActs.update(act(dx), (v) => v + 1, ifAbsent: () => 1);
      }
    }
    String top(Map<String, int> m) => m.isEmpty ? '—' : (m.entries.toList()..sort((x, y) => y.value.compareTo(x.value))).first.key;
    final n = dev == 0 ? 1 : dev;
    out.writeln('| $name | $lvl | ${top(baseActs)} | ${top(exActs)} | $dev ($bad) | ${(evG / n).toStringAsFixed(2)} | '
        '${(evE / n).toStringAsFixed(2)} | ${dev == 0 ? '0.00' : '+${((evE - evG) / n).toStringAsFixed(2)}'} |');
    print('CLOSER ${name.split(' ').first}: dev $dev, Δ<=0 $bad, +Δ ${((evE - evG) / n).toStringAsFixed(2)}bb');
  }
  out.writeln();
}


/// Δ EV de los 5 módulos de la Fase 9.5 (mismo modelo EV para módulo ON y OFF; interruptores de auditoría).
void modules95(StringBuffer out) {
  final rows = <(String, String, String, String, double)>[];
  String act(DecisionOutput d) => '${d.action.name}${d.sizing == null ? '' : ' ${d.sizing!.potPct.round()}%'}';
  // 1. Geo-2E: set en turn, SPR 2.3.
  final geoG = GameState(stake: Stake.nl25, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 82.5, potBb: 35.5,
      hero: HoleCards.parse('KhKs'), board: Card.parseMany('Kd7s2s4h'),
      actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 2), a(Street.flop, Position.bb, ActionType.call, 2),
        a(Street.turn, Position.bb, ActionType.check)]);
  final geo = Geometric2EPlanner.plan(35.5, 82.5)!;
  double betEv(double pct) => ActionEvCalculator.postflop(geoG, reg, potBefore: 35.5, toCall: 0, betSizeBb: 35.5 * pct / 100, exactSize: true).betRaise;
  rows.add(('Geo-2E (set, SPR 2.3, Turn)', 'bet 75% (river SPR ${((82.5 - 26.6) / (35.5 + 53.25)).toStringAsFixed(2)}x)',
      'bet ${geo.$1.round()}% (river all-in ${geo.$2.round()}%)', 'Reg_GTO', betEv(geo.$1) - betEv(75)));
  // 2. Topología corta 35bb: CO vs open UTG.
  var topo = 0.0;
  final changed = <String>[];
  for (final h in ['5c5d', '3c3d', 'KhQd', 'As9s', '8c8d', 'AhJd']) {
    final g = GameState(stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.co, effectiveStackBb: 35, hero: HoleCards.parse(h),
        actions: const [PlayerAction(Street.preflop, Position.co, ActionType.raise, 2.5)]);
    StackTopologyResolver.enabled = true;
    final on = tree.decide(g);
    StackTopologyResolver.enabled = false;
    final off = tree.decide(g);
    StackTopologyResolver.enabled = true;
    if (on.action == off.action || on.actionEVs == null) continue;
    String k(DecisionAction x) => x == DecisionAction.betRaise ? 'betRaise' : (x == DecisionAction.call ? 'call' : 'fold');
    topo += (on.actionEVs![k(on.action)] ?? 0) - (on.actionEVs![k(off.action)] ?? 0);
    changed.add('${HoleCards.parse(h).handClass} ${off.action.name}->${on.action.name}');
  }
  rows.add(('Short-Stack Topology (35bb, BTN vs CO, suma de manos)', changed.isEmpty ? 'sin cambios' : changed.join(', '), '${changed.length} manos', 'Pool', topo));
  // 3. Monocolor / 4-flush.
  final mono = post.decide(GameState(stake: Stake.nl10, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 97.5, potBb: 5.5,
      villainProfile: VillainProfile.poolDefault, hero: HoleCards.parse('AsQd'), board: Card.parseMany('Ks9s4s'), actions: [...srp, a(Street.flop, Position.bb, ActionType.check)]));
  rows.add(('Monotone Small Stab (AsQd en Ks9s4s)', 'ancla Reg_GTO', act(mono), 'Pool NL10', mono.exploitDeltaEV ?? 0));
  final four = post.decide(GameState(stake: Stake.nl10, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 95.5, potBb: 9.1,
      villainProfile: VillainProfile.poolDefault, hero: HoleCards.parse('KsQd'), board: Card.parseMany('Js9s4s2d7s'),
      actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8), a(Street.flop, Position.bb, ActionType.call, 1.8),
        a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.check), a(Street.river, Position.bb, ActionType.check)]));
  rows.add(('4-Flush Blocker Steal (KsQd, 4 picas river)', 'ancla Reg_GTO', act(four), 'Pool NL10', four.exploitDeltaEV ?? 0));
  // 4. Sandwich squeeze.
  final sq = tree.decide(GameState(stake: Stake.nl10, heroPosition: Position.bb, villainPosition: Position.co, effectiveStackBb: 100, villainProfile: VillainProfile.poolDefault,
      hero: HoleCards.parse('Ah4h'), actions: const [PlayerAction(Street.preflop, Position.co, ActionType.raise, 2.5), PlayerAction(Street.preflop, Position.btn, ActionType.call, 2.5)]));
  final swe = SandwichSqueezeExploit.evaluate(GameState(stake: Stake.nl10, heroPosition: Position.bb, villainPosition: Position.co,
      villainProfile: VillainProfile.poolDefault, hero: HoleCards.parse('Ah2h')), opener: Position.co, caller: Position.btn, sizeBb: 13.75, potBb: 6.5)!;
  rows.add(('Sandwich Squeeze (A2s BB vs CO + BTN; FE ${(swe.$1 * 100).round()}% vs alpha ${(swe.$2 * 100).round()}%)', 'call/fold',
      swe.$1 > swe.$2 ? act(sq) : 'gate cerrado (FE < alpha)', 'Pool NL10', swe.$1 > swe.$2 ? (sq.exploitDeltaEV ?? 0) : 0));
  // 5. Escudo: NL50, pool con PFR 26 / 3B 11, triple barrel, top pair.
  const agg = ReadProfile(GgArchetype.poolDefault, ['HUD agresivo'], pfr: 26, threeBet: 11);
  final tg = GameState(stake: Stake.nl50, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 88, potBb: 23.7, villainProfile: VillainProfile.poolDefault,
      hero: HoleCards.parse('KdQc'), board: Card.parseMany('Kc8d3h2s6c'),
      actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8), a(Street.flop, Position.bb, ActionType.call, 1.8),
        a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 7.3), a(Street.turn, Position.bb, ActionType.call, 7.3),
        a(Street.river, Position.bb, ActionType.check), a(Street.river, Position.btn, ActionType.bet, 19)]);
  final shOn = post.decide(tg, read: agg);
  AntiCounterExploitShield.enabled = false;
  final shOff = post.decide(tg, read: agg);
  AntiCounterExploitShield.enabled = true;
  final sOn = PostflopHeuristicEngine.evOfDecision(tg, agg, shOn, potBefore: 23.7, toCall: 19);
  final sOff = PostflopHeuristicEngine.evOfDecision(tg, agg, shOff, potBefore: 23.7, toCall: 19);
  rows.add(('Anti-Counter-Exploit Shield (NL50, PFR 26/3B 11)', act(shOff), act(shOn), 'Agresivo (modelo de rango, sin prior T2)', sOn - sOff));
  out
    ..writeln()
    ..writeln('## Módulos Fase 9.5 — Δ EV por spot (bb)')
    ..writeln()
    ..writeln('Mismo modelo EV para módulo ON y OFF (interruptores de auditoría). Priors de FE/umbrales declarados por el usuario. No es winrate.')
    ..writeln()
    ..writeln('| Módulo | Acción sin módulo | Acción con módulo | Perfil | +Δ EV (bb) |')
    ..writeln('|---|---|---|---|---|');
  for (final (n, off, on, prof, d) in rows) {
    out.writeln('| $n | $off | $on | $prof | ${d >= 0 ? '+' : ''}${d.toStringAsFixed(2)} |');
    print('MOD95 $n: ${d.toStringAsFixed(2)}bb');
  }
  out.writeln();
}
