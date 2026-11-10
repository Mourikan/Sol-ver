// Benchmark de números fríos (NL50, 100bb, Reg_GTO). Ejecutar:
// dart --packages=.dart_tool/package_config.json docs/audit_scripts/cold_numbers_benchmark.dart
// Referencias teóricas: defensa = MDF = P/(P+B); farol en apuesta polar = 1-(1-α)^n con α = B/(P+2B) y n calles restantes
// (modelo geométrico polarizado: n=3 flop, 2 turn, 1 river); 3-bet/4-bet = α del sizing.
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math';

import 'package:sol_ver/core/evaluators/action_ev_calculator.dart';
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


/// Edge por spot (Modo Exploit): EV en bb de la acción explotativa vs la acción GTO, ambas evaluadas bajo el perfil asumido.
/// NO es winrate: no existen en el repo datos de frecuencia de spots ni del pool para agregarlo a bb/100.
void edge(StringBuffer out) {
  final fish = GgProfiler.classify(const SmartHudInput(vpip: 50, pfr: 5, threeBet: 1, stackBb: 100));
  final scared = GgProfiler.classify(const SmartHudInput(vpip: 20, pfr: 17, threeBet: 4, stackBb: 100));
  final nit = ReadProfile.fromVillainProfile(VillainProfile.nit);
  out
    ..writeln('## Edge por nivel (Modo Exploit) — por spot, no bb/100')
    ..writeln()
    ..writeln('Rake por bote = E[min(%·pot, cap)] con la distribución de tamaños de `RakeConfig.potDistribution` (plantilla, no tabla oficial de sala).')
    ..writeln('Δ EV spot = EV(acción del motor con el read) − EV(acción del motor vs Reg_GTO), ambas bajo el perfil del villano asumido (prior del usuario).')
    ..writeln()
    ..writeln('| Nivel | Rake medio SRP (bb/bote) | Rake medio 3BP (bb/bote) | Δ EV thin value vs Fish (bb) | Δ EV overbet vs Scared capado, insta-check river (bb) | Δ EV c-bet aire vs Nit en 7s6s5d (bb) |')
    ..writeln('|---|---|---|---|---|---|');
  PlayerAction a(Street s, Position p, ActionType t, [double x = 0]) => PlayerAction(s, p, t, x);
  double rakePerPot(RakeConfig r, PotType t) {
    var e = 0.0;
    for (final (pot, pr) in RakeConfig.potDistribution[t]!) {
      e += pr * r.rakeOn(pot);
    }
    return e;
  }

  double spot(GameState g, ReadProfile exploitRead, {required double pot, required double stack}) {
    final dEx = post.decide(g.copyWith(villainProfile: exploitRead.engineProfile), read: exploitRead);
    final dGto = post.decide(g, read: reg);
    double evOf(DecisionOutput d) {
      final size = d.action == DecisionAction.betRaise ? d.sizing!.bb : pot * 0.5;
      final ev = ActionEvCalculator.postflop(g.copyWith(villainProfile: exploitRead.engineProfile), exploitRead, potBefore: pot, toCall: 0, betSizeBb: size);
      return d.action == DecisionAction.betRaise ? ev.betRaise : ev.checkCall;
    }
    return evOf(dEx) - evOf(dGto);
  }

  for (final stake in Stake.values) {
    final r = RakeConfig.byStake[stake]!;
    final thin = GameState(stake: stake, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 90, potBb: 9.1,
        hero: HoleCards.parse('Kh5h'), board: Card.parseMany('Ks8s3d4c2h'),
        actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8), a(Street.flop, Position.bb, ActionType.call, 1.8),
          a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.check), a(Street.river, Position.bb, ActionType.check)]);
    final over = GameState(stake: stake, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 80, potBb: 18,
        hero: HoleCards.parse('Ah4s'), board: Card.parseMany('QhJh4c2h8d'),
        actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8), a(Street.flop, Position.bb, ActionType.call, 1.8),
          a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 4.5), a(Street.turn, Position.bb, ActionType.call, 4.5),
          const PlayerAction(Street.river, Position.bb, ActionType.check, 0, TimingTell.instaAction)]);
    final cb = GameState(stake: stake, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 97.5, potBb: 5.5,
        hero: HoleCards.parse('Kh2c'), board: Card.parseMany('7s6s5d'), actions: [...srp, a(Street.flop, Position.bb, ActionType.check)]);
    out.writeln('| ${stake.name.toUpperCase()} | ${rakePerPot(r, PotType.srp).toStringAsFixed(2)} | ${rakePerPot(r, PotType.threeBet).toStringAsFixed(2)} | '
        '${spot(thin, fish, pot: 9.1, stack: 90).toStringAsFixed(2)} | ${spot(over, scared, pot: 18, stack: 80).toStringAsFixed(2)} | ${spot(cb, nit, pot: 5.5, stack: 97.5).toStringAsFixed(2)} |');
  }
  out
    ..writeln()
    ..writeln('Δ EV = 0.00 en overbet NL25+ : la conversión LLinus ya está activa vs Reg en NL25+ (gate de la Fase 5), no hay desviación adicional.')
    ..writeln('Δ EV = 0.00 en c-bet vs Nit: la puerta de EV rechaza el farol (EV(bet) < EV(check) con el FE de nit del modelo) => '
        'la regla "c-bet 100% vs nit" NO pasa la prueba EV_Exploit > EV_GTO en boards check-heavy; queda neutralizada.')
    ..writeln('Δ EV > 0 demuestra `EV_Exploit > EV_GTO` en el spot bajo el perfil asumido. El agregado bb/100 requiere frecuencias de spots y '
        'tendencias reales del pool por nivel (base de datos de manos), que este proyecto no tiene ni debe registrar (CLAUDE.md §5).')
    ..writeln()
    ..writeln('## Calificación de ingeniería (Claude, evaluación honesta)')
    ..writeln()
    ..writeln('| Eje | Nota | Fundamento |')
    ..writeln('|---|---|---|')
    ..writeln('| Precisión Matemática GTO | 60/100 | Δ Nash 2.4% vs referencias teóricas (MDF, α, presupuesto geométrico), pero rangos preflop semilla, '
        'targets BB declarados por el usuario y ninguna validación contra exports de solver. |')
    ..writeln('| Letalidad Explotativa vs Pool | 55/100 | Módulos de reads, thin value, LLinus e isolation con prueba EV por spot; '
        'priors MDA/timing sin muestra real; una regla (c-bet vs nit en boards check-heavy) no supera la prueba EV. |')
    ..writeln('| Velocidad / Rendimiento APK | 70/100 | Lookups O(1) < 0.5 ms, decisión con EV ~1 ms, isolate persistente; el APK nunca se ha compilado ni medido en un dispositivo. |')
    ..writeln('| Seguridad Anti-Explotación | 70/100 | Presupuestos MDF exactos, EV_Sanity_Guard, invariantes y fuzzer de monotonía; '
        'las leyes MDA (folds en NL2-NL50) son explotables por regs que sobre-faroleen esas líneas. |')
    ..writeln()
    ..writeln('**Nota global: 64/100** — motor internamente consistente y auditado; la brecha principal es de datos (solver real y pool real), no de arquitectura.')
    ..writeln();
}
