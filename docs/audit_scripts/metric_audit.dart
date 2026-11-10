// Auditoría métrica final (Δ Nash). Ejecutar: dart --packages=.dart_tool/package_config.json docs/audit_scripts/metric_audit.dart
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math';

import 'package:sol_ver/core/models/decision_output.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/postflop/defense_budget.dart';
import 'package:sol_ver/core/postflop/flop_lookup_table.dart';
import 'package:sol_ver/core/postflop/hand_tier.dart';
import 'package:sol_ver/core/postflop/postflop_heuristic_engine.dart';
import 'package:sol_ver/core/postflop/postflop_ranges.dart';
import 'package:sol_ver/core/postflop/turn_river_solver.dart';
import 'package:sol_ver/core/preflop/full_tree_preflop.dart';
import 'package:sol_ver/core/preflop/preflop_ranges_db.dart';
import 'package:sol_ver/core/preflop/range_notation.dart';
import 'package:sol_ver/core/reads/gg_profiler.dart';

String cs(int id) => '${'23456789TJQKA'[id >> 2]}${'cdhs'[id & 3]}';
PlayerAction a(Street s, Position p, ActionType t, [double x = 0, TimingTell tt = TimingTell.none]) => PlayerAction(s, p, t, x, tt);
PlayerAction pf(Position p, ActionType t, [double x = 0]) => a(Street.preflop, p, t, x);
const srp = [PlayerAction(Street.preflop, Position.btn, ActionType.raise, 2.5), PlayerAction(Street.preflop, Position.bb, ActionType.call, 2.5)];
const post = PostflopHeuristicEngine();
const tree = FullTreePreflop();

const reg = ReadProfile(GgArchetype.unknownReg, []);
final fish = GgProfiler.classify(const SmartHudInput(vpip: 50, pfr: 5, threeBet: 1, stackBb: 100));
final scared = GgProfiler.classify(const SmartHudInput(vpip: 20, pfr: 17, threeBet: 4, stackBb: 100));
final maniac = GgProfiler.classify(const SmartHudInput(vpip: 45, pfr: 35, threeBet: 15, stackBb: 100));

class Row {
  Row(this.section, this.spot, this.profile, this.theory, this.engine, this.delta, {this.justified = '', this.alert = ''});
  final String section, spot, profile, theory, engine, justified, alert;
  final double delta;
}

final rows = <Row>[];
String p(double x) => '${(x * 100).toStringAsFixed(1)}%';
double band(double v, double lo, double hi) => v < lo ? lo - v : (v > hi ? v - hi : 0);

HoleCards placeholder(String board) {
  final used = Card.parseMany(board).map((c) => c.id).toSet();
  final free = [for (var i = 0; i < 52; i++) if (!used.contains(i)) i];
  return HoleCards.parse(cs(free[0]) + cs(free[1]));
}

Iterable<(String, int)> combos(List<double> w, int dead) sync* {
  for (var i = 0; i < 169; i++) {
    if (w[i] <= 0) continue;
    for (final (x, y) in Matrix169.concreteCombos(i)) {
      if (dead & ((1 << x) | (1 << y)) != 0) continue;
      yield (cs(x) + cs(y), i);
    }
  }
}

void preflop() {
  for (final st in [Stake.nl10, Stake.nl100]) {
    var def = 0;
    for (var i = 0; i < 169; i++) {
      final (x, y) = Matrix169.concreteCombos(i).first;
      final d = tree.decide(GameState(stake: st, heroPosition: Position.bb, effectiveStackBb: 100, hero: HoleCards.parse(cs(x) + cs(y)),
          actions: [pf(Position.btn, ActionType.raise, 2.5)]));
      if (d.action != DecisionAction.fold) def += Matrix169.combos(i);
    }
    final v = def / 1326;
    rows.add(Row('Preflop', 'BB defensa vs BTN 2.5x', '${st.name} (${st.rakeTier.name})', '45–55% (MDF ajustado EQR+rake)', p(v), band(v, .45, .55)));
  }
  // 4-bet value/bluff por nodo (CO vs 3-bet BTN OOP; BTN vs 3-bet BB IP)
  final nodes = [
    ('CO vs 3-bet BTN (OOP 2.5x)', Position.co, Position.btn, 8.0, 1.5, 2.5),
    ('BTN vs 3-bet BB (IP 2.2x)', Position.btn, Position.bb, 10.0, 0.5, 2.2),
    ('UTG vs 3-bet CO (OOP 2.5x)', Position.utg, Position.co, 8.0, 1.5, 2.5),
  ];
  for (final (name, hero, vill, tb, dead, mult) in nodes) {
    final fourBet = tb * mult;
    final potAfter = 2.5 + tb + dead + (fourBet - 2.5);
    final callV = fourBet - tb;
    final alpha = callV / (potAfter + callV);
    for (final (rn, rp) in [('Reg/GTO', reg), ('Fish', fish)]) {
      var val = 0, bl = 0;
      for (var i = 0; i < 169; i++) {
        final (x, y) = Matrix169.concreteCombos(i).first;
        final d = tree.decide(GameState(stake: Stake.nl100, heroPosition: hero, effectiveStackBb: 100, hero: HoleCards.parse(cs(x) + cs(y)),
            actions: [pf(hero, ActionType.raise, 2.5), pf(vill, ActionType.raise, tb)]), read: rp);
        if (d.action != DecisionAction.betRaise) continue;
        if (PreflopRangesDb.isBluff4Bet(i)) {
          bl += Matrix169.combos(i);
        } else {
          val += Matrix169.combos(i);
        }
      }
      final share = bl / max(1, val + bl);
      final fishRow = rp == fish;
      rows.add(Row('Preflop', '4-bet farol/(valor+farol): $name', rn, fishRow ? '0% (Recreativo)' : 'α = ${p(alpha)}',
          '${p(share)} ($bl farol / $val valor)', fishRow ? share : (share - alpha).abs()));
    }
  }
}

void flop() {
  for (final b in ['As7d2c', 'AsKd2c', 'Kd7c2h', 'KsQd2h']) {
    final (pr, dr) = PostflopRanges.forPot(Position.btn, Position.bb, PotType.srp, RakeTier.midRake);
    final r = FlopLookupTable.evaluate(Card.parseMany(b), HuNode.srpIp, pfaRange: pr, defenderRange: dr);
    rows.add(Row('Flop', 'Range bet 33% BTN vs BB ($b, ${r.bucket.name})', 'SRP IP', '≥60% (definición range-bet)', p(r.betFreq), band(r.betFreq, .60, 1.0)));
  }
  for (final (st, rn, rp, just) in [
    (Stake.nl100, 'Reg', reg, ''),
    (Stake.nl10, 'Reg', reg, ''),
    (Stake.nl25, 'Scared', scared, 'Scared ≤NL50 factor 0.90'),
    (Stake.nl25, 'Fish', fish, 'Regla Fish (factor 0.82)'),
    (Stake.nl100, 'Maniac', maniac, 'Regla Maniac (factor 1.15)'),
  ]) {
    for (final b in ['As7d2c', 'Qc7h2d', '9h8h4c']) {
      final (_, bbR) = PostflopRanges.forPot(Position.btn, Position.bb, PotType.srp, st.rakeTier);
      final dead = Card.parseMany(b).fold<int>(0, (m, c) => m | c.bit);
      var tot = 0, cont = 0, inv = 0;
      for (final (h, _) in combos(bbR, dead)) {
        tot++;
        final d = post.decide(GameState(stake: st, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 97.5, potBb: 5.5,
            hero: HoleCards.parse(h), board: Card.parseMany(b), actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8)]), read: rp);
        if (d.action != DecisionAction.fold) cont++;
        if (d.ajusteExplotativoRead.contains('Equity real (realizada)')) inv++;
      }
      final v = cont / tot;
      final budgetOnly = (cont - inv) / tot;
      final invJust = v > 0.753 + 0.08 && (budgetOnly - 0.753).abs() <= 0.08
          ? 'Invariante Equity_Real ≥ Pot Odds: +${p(inv / tot)} de calls +EV directos sobre el presupuesto MDF (${p(budgetOnly)})'
          : '';
      rows.add(Row('Flop', 'Defensa BB vs c-bet 33% ($b)', '${st.name} $rn', 'MDF 75.3%', p(v), (v - 0.753).abs(),
          justified: [just, invJust].where((x) => x.isNotEmpty).join('; '), alert: v < 0.70 ? 'ALERTA <70%' : ''));
    }
  }
}

void turn() {
  // Double barrel: ratio de faroles seleccionados (semi vs puro) vs α del sizing
  for (final (rn, rp) in [('Reg', reg), ('Scared (pot>35bb, capado)', scared), ('Fish', fish)]) {
    final g0 = GameState(stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 82.5, potBb: 35.5,
        hero: placeholder('Kd7s2s4h'), board: Card.parseMany('Kd7s2s4h'),
        actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 15), a(Street.flop, Position.bb, ActionType.call, 15),
          a(Street.turn, Position.bb, ActionType.check)]);
    final range = DefenseBudget.heroRangeAtStreet(g0, rp);
    var val = 0.0, semi = 0.0, pure = 0.0;
    double? size;
    final ids = [for (final c in g0.board) c.id];
    for (final e in range.entries) {
      final x = e.key ~/ 52, y = e.key % 52;
      final d = post.decide(g0.copyWith(hero: HoleCards.parse(cs(x) + cs(y))), read: rp);
      if (d.action != DecisionAction.betRaise) continue;
      final t = HandTierClassifier.classify(x, y, ids);
      if (t.tier == HandTier.nutsMonster || t.tier == HandTier.strongTopPairOverpair) {
        val += e.value;
        size ??= d.sizing!.potPct;
      } else if (t.flushDraw || t.oesd || t.gutshot) {
        semi += e.value;
      } else {
        pure += e.value;
      }
    }
    final s = (size ?? 80) / 100;
    // Turn: presupuesto geométrico de 2 calles (CLAUDE.md [NASH_DELTA_AND_POOL_EDGE_HUNTER]).
    final alpha = TurnRiverSolver.twoStreetTurnShare(s * 100);
    final share = (semi + pure) / max(1e-9, val + semi + pure);
    final factor = rp == scared ? 2.0 : (rp == fish ? 0.5 : 1.0);
    rows.add(Row('Turn', 'Double barrel ${(s * 100).round()}% Kd7s2s-4h (semi ${semi.round()} / puro ${pure.round()} / valor ${val.round()})', rn,
        'geo2 = ${p(alpha)}${factor != 1 ? ' x $factor = ${p(min(1, alpha * factor))}' : ''}', p(share), (share - min(1, alpha * factor)).abs(),
        justified: factor != 1 ? 'Exploit_Bluff_Factor $factor (${rp.archetype.name})' : ''));
  }
  // Fold de Hero vs double barrel 75% (proyectos no completan)
  for (final (st, rn, rp, just) in [
    (Stake.nl100, 'Reg', reg, ''),
    (Stake.nl10, 'Reg', reg, ''),
    (Stake.nl25, 'Scared', scared, 'Scared ≤NL50 factor 0.90'),
    (Stake.nl100, 'Maniac', maniac, 'Regla Maniac (factor 1.15)'),
  ]) {
    for (final b in ['As7d2c5h', 'Qc7h2dKs', 'Kd8s3s4c']) {
      final g0 = GameState(stake: st, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 95.7, potBb: 9.1,
          hero: placeholder(b), board: Card.parseMany(b),
          actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8),
            a(Street.flop, Position.bb, ActionType.call, 1.8), a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 6.8)]);
      final range = DefenseBudget.heroRangeAtStreet(g0, rp);
      var tot = 0.0, fold = 0.0;
      for (final e in range.entries) {
        final x = e.key ~/ 52, y = e.key % 52;
        final g = GameState(stake: st, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 95.7, potBb: 9.1,
            hero: HoleCards.parse(cs(x) + cs(y)), board: g0.board, actions: g0.actions);
        tot += e.value;
        if (post.decide(g, read: rp).action == DecisionAction.fold) fold += e.value;
      }
      final v = fold / tot;
      final mdfFold = 1 - 9.1 / 15.9;
      rows.add(Row('Turn', 'Fold BB vs barrel 75% ($b)', '${st.name} $rn', '1-MDF = ${p(mdfFold)}', p(v), (v - mdfFold).abs(),
          justified: just, alert: v > mdfFold + 0.08 && just.isEmpty ? 'SOBRE-FOLD' : ''));
    }
  }
}

void river() {
  // Bluff-catching vs pot (MDF 50%): continuación y prioridad de unblockers
  for (final (st, rn, rp, just) in [
    (Stake.nl100, 'Reg', reg, ''),
    (Stake.nl10, 'Reg (MDA: triple barrel overbet)', reg, 'Ley MDA NL2-NL50 (CLAUDE.md §4)'),
    (Stake.nl100, 'Maniac', maniac, 'Regla Maniac (piso agro + factor 1.15)'),
  ]) {
    for (final b in ['Kd8s3s4c2h', 'As7d2c5h9s', 'Qc7h2dKs3c']) {
      final acts = [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8), a(Street.flop, Position.bb, ActionType.call, 1.8),
        a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 6.8), a(Street.turn, Position.bb, ActionType.call, 6.8),
        a(Street.river, Position.bb, ActionType.check), a(Street.river, Position.btn, ActionType.bet, 22.7)];
      final g0 = GameState(stake: st, heroPosition: Position.bb, villainPosition: Position.btn, effectiveStackBb: 88.9, potBb: 22.7,
          hero: placeholder(b), board: Card.parseMany(b), actions: acts);
      final range = DefenseBudget.heroRangeAtStreet(g0, rp);
      var tot = 0.0, cont = 0.0, unbT = 0.0, unbC = 0.0, blkT = 0.0, blkC = 0.0;
      final ids = [for (final c in g0.board) c.id];
      final flopSuits = List<int>.filled(4, 0);
      for (final c in g0.board.sublist(0, 4)) {
        flopSuits[c.suit.index]++;
      }
      final drawSuit = flopSuits.indexWhere((n) => n >= 2);
      for (final e in range.entries) {
        final x = e.key ~/ 52, y = e.key % 52;
        final d = post.decide(g0.copyWith(hero: HoleCards.parse(cs(x) + cs(y))), read: rp);
        tot += e.value;
        final c = d.action != DecisionAction.fold;
        if (c) cont += e.value;
        final t = HandTierClassifier.classify(x, y, ids).tier;
        if (drawSuit >= 0 && (t == HandTier.marginalMadeShowdown || t == HandTier.strongTopPairOverpair)) {
          final blocks = (x & 3) == drawSuit || (y & 3) == drawSuit;
          if (blocks) {
            blkT += e.value;
            if (c) blkC += e.value;
          } else {
            unbT += e.value;
            if (c) unbC += e.value;
          }
        }
      }
      final v = cont / tot;
      final prio = drawSuit < 0 ? 'n/a (sin proyecto de color)' : 'unblockers ${p(unbC / max(1e-9, unbT))} vs blockers ${p(blkC / max(1e-9, blkT))}';
      rows.add(Row('River', 'Bluff-catch vs pot ($b) — $prio', '${st.name} $rn', 'MDF 50.0%', p(v), (v - 0.5).abs(),
          justified: just, alert: drawSuit >= 0 && unbC / max(1e-9, unbT) + 1e-9 < blkC / max(1e-9, blkT) ? 'PRIORIDAD INVERTIDA' : ''));
    }
  }
  // Conversión LLinus vs rango capado
  for (final (rn, rp, vp) in [('Scared', scared, VillainProfile.regAbc), ('Reg NL50', reg, VillainProfile.gtoBase), ('CallingStation', fish, VillainProfile.callingStation)]) {
    final g0 = GameState(stake: Stake.nl50, heroPosition: Position.btn, villainPosition: Position.bb, effectiveStackBb: 80, potBb: 18,
        hero: HoleCards.parse('Ah4s'), board: Card.parseMany('QhJh4c2h8d'), villainProfile: vp,
        actions: [...srp, a(Street.flop, Position.bb, ActionType.check), a(Street.flop, Position.btn, ActionType.bet, 1.8), a(Street.flop, Position.bb, ActionType.call, 1.8),
          a(Street.turn, Position.bb, ActionType.check), a(Street.turn, Position.btn, ActionType.bet, 4.5), a(Street.turn, Position.bb, ActionType.call, 4.5),
          a(Street.river, Position.bb, ActionType.check, 0, TimingTell.instaAction)]);
    final range = DefenseBudget.heroRangeAtStreet(g0, rp);
    final ids = [for (final c in g0.board) c.id];
    var nonValue = 0.0, conv = 0.0;
    for (final e in range.entries) {
      final x = e.key ~/ 52, y = e.key % 52;
      final t = HandTierClassifier.classify(x, y, ids).tier;
      if (t == HandTier.nutsMonster || t == HandTier.strongTopPairOverpair) continue;
      nonValue += e.value;
      final d = post.decide(g0.copyWith(hero: HoleCards.parse(cs(x) + cs(y))), read: rp);
      if (d.action == DecisionAction.betRaise && d.sizing!.potPct >= 100) conv += e.value;
    }
    final v = conv / max(1e-9, nonValue);
    final station = vp == VillainProfile.callingStation;
    rows.add(Row('River', 'Conversión LLinus (overbet/all-in de no-valor) QhJh4c2h8d capado', rn, station ? '0% estricto' : '>0%', p(v),
        station ? v : (v > 0 ? 0 : 1), justified: station ? 'Gate Fish/Station' : 'Regla LLinus (rango capado)'));
  }
}

void main() {
  preflop();
  flop();
  turn();
  river();
  final out = StringBuffer()
    ..writeln('# Final Metrics Audit — Δ Nash por calles')
    ..writeln()
    ..writeln('Generado por `docs/audit_scripts/metric_audit.dart` simulando el motor combo a combo. '
        'Δ Nash = |métrica del motor − referencia teórica| en puntos porcentuales (o distancia fuera de banda). '
        'Umbral: Δ > 8% sin justificación explotativa ⇒ fallo.')
    ..writeln();
  var failures = 0;
  for (final sec in ['Preflop', 'Flop', 'Turn', 'River']) {
    out
      ..writeln('## $sec')
      ..writeln()
      ..writeln('| Spot/Nodo | Stake/Perfil | Métrica Teórica (MDF/α) | Métrica del Motor | Explotabilidad (Δ Nash %) | Estado |')
      ..writeln('|---|---|---|---|---|---|');
    for (final r in rows.where((r) => r.section == sec)) {
      final over = r.delta > 0.08;
      final fail = over && r.justified.isEmpty;
      if (fail) failures++;
      final state = fail ? '**FALLO**' : (over ? 'Justificado: ${r.justified}' : 'OK${r.justified.isNotEmpty ? ' (${r.justified})' : ''}');
      out.writeln('| ${r.spot} | ${r.profile} | ${r.theory} | ${r.engine} | ${(r.delta * 100).toStringAsFixed(1)} | $state${r.alert.isNotEmpty ? ' · ${r.alert}' : ''} |');
    }
    out.writeln();
  }
  out.writeln('**Nodos con Δ > 8% sin justificación: $failures**');
  File('docs/final_metrics_audit.md').writeAsStringSync(out.toString());
  print('rows=${rows.length} failures=$failures');
  for (final r in rows.where((r) => r.delta > 0.08)) {
    print('${r.section} | ${r.spot} | ${r.profile} | ${r.engine} | Δ ${(r.delta * 100).toStringAsFixed(1)} | ${r.justified}');
  }
}
