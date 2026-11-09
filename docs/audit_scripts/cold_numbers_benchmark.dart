// Benchmark de números fríos (NL50, 100bb, Reg_GTO). Ejecutar:
// dart --packages=.dart_tool/package_config.json docs/audit_scripts/cold_numbers_benchmark.dart
// Referencias teóricas: defensa = MDF = P/(P+B); farol en apuesta polar = 1-(1-α)^n con α = B/(P+2B) y n calles restantes
// (modelo geométrico polarizado: n=3 flop, 2 turn, 1 river); 3-bet/4-bet = α del sizing.
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math';

import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/postflop/defense_budget.dart';
import 'package:sol_ver/core/postflop/hand_tier.dart';
import 'package:sol_ver/core/postflop/postflop_heuristic_engine.dart';
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

  for (final (opener, hand) in [(Position.btn, 'Kh9d'), (Position.co, 'Ah9d')]) {
    final acts = [pf(opener, ActionType.raise, 2.5)];
    final v = weighted(Position.bb, acts, cont);
    rows.add(Row('Preflop', 'BB vs open ${opener.name.toUpperCase()} 2.5x — $hand', one(Position.bb, hand, acts), v, 1 - 2.5 / (2.5 + 1.5)));
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

double bluffShareOfBets(GameState g0) {
  var v = 0.0, bl = 0.0;
  final range = DefenseBudget.heroRangeAtStreet(g0, reg);
  for (final e in range.entries) {
    final a = e.key ~/ 52, b = e.key % 52;
    final d = post.decide(g0.copyWith(hero: HoleCards.parse(cs(a) + cs(b))), read: reg);
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
    rows.add(Row('River', 'BTN river bet ${size.round()}% $b (farol/apuestas) — $h', d, bluffShareOfBets(g), polarBluffShare(size / 100 * 22.7, 22.7, 1)));
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
    ..writeln('**Promedio global Δ Nash: ${(global * 100).toStringAsFixed(1)}%**');
  File('docs/cold_numbers_audit.md').writeAsStringSync(out.toString());
  for (final e in means.entries) {
    print('${e.key}: ${(e.value * 100).toStringAsFixed(1)}%');
  }
  print('GLOBAL: ${(global * 100).toStringAsFixed(1)}%');
}
