import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/application/hand_flow_fsm.dart';
import 'package:sol_ver/application/linear_hand_flow.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/ui/screens/solver_cockpit_screen.dart';
import 'package:sol_ver/ui/theme.dart';

late LinearHandFlow _flow;
final _seen = <String>[];

Future<void> tapKey(WidgetTester t, String key) async {
  await t.pump();
  final any = find.descendant(of: find.byKey(const ValueKey('pane-0')), matching: find.byKey(ValueKey(key), skipOffstage: false), skipOffstage: false);
  if (any.evaluate().isEmpty) fail('falta el control "$key" en ${_flow.fsm.screenPhase} actor=${_flow.fsm.currentActorSeat}');
  await t.ensureVisible(any);
  await t.pump();
  await t.tap(find.byKey(ValueKey(key)));
  await t.pump();
  syncCheck(t);
}

/// Law_1: si Hero decide en este nodo, el Oráculo muestra una decisión con la firma ACTUAL.
void syncCheck(WidgetTester t) {
  final fsm = _flow.fsm;
  if (fsm.heroCards.length < 2 || fsm.phase == HandPhase.setup || find.byKey(const ValueKey('wizard-handAndSeat')).evaluate().isNotEmpty) return;
  expect(find.byKey(const ValueKey('pinned-oracle')), findsOneWidget, reason: 'oráculo ausente en ${fsm.screenPhase}');
  final live = fsm.liveOracle;
  if (live != null) expect(live.signature, fsm.stateSignature, reason: 'decisión congelada (firma vieja)');
  _seen.add(oracle(t));
}

String oracle(WidgetTester t) => t.widget<Text>(find.byKey(const ValueKey('oracle-action'))).data!;

Future<void> pick(WidgetTester t, String card) async {
  await tapKey(t, 'rank-${card[0]}');
  await tapKey(t, 'suit-${card[1]}');
}

double scrubValue(WidgetTester t) => double.parse(t.widget<Text>(find.byKey(const ValueKey('scrub-value'))).data!.split('bb').first);

Future<void> scrubTo(WidgetTester t, double v) async {
  for (var i = 0; i < 400 && (scrubValue(t) - v).abs() > 1e-9; i++) {
    final k = find.byKey(ValueKey(scrubValue(t) < v ? 'scrub-plus' : 'scrub-minus'));
    await t.ensureVisible(k);
    await t.tap(k);
    await t.pump();
  }
  expect(scrubValue(t), v);
}

Future<LinearHandFlow> start(WidgetTester t, String c1, String c2, String pos) async {
  await t.binding.setSurfaceSize(const Size(412, 1400));
  final flow = LinearHandFlow(HandFlowFSM()..configure(stake: Stake.nl50));
  _flow = flow;
  _seen.clear();
  await t.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: SolverCockpitScreen(key: UniqueKey(), flow: flow),
    ),
  );
  await pick(t, c1);
  await pick(t, c2);
  await tapKey(t, 'pos-$pos');
  return flow;
}

/// Villano en turno: check si puede, si no call; hasta que le toque a Hero o cierre la calle.
Future<void> villainsPassive(WidgetTester t) async {
  final fsm = _flow.fsm;
  for (var i = 0; i < 8 && fsm.screenPhase == ScreenPhase.postflopStreetAction && fsm.currentActorSeat != fsm.heroPosition; i++) {
    final p = fsm.currentActorSeat!;
    await tapKey(t, fsm.currentBet - fsm.seats[p]!.committed > 0 ? 'v-call' : 'v-check');
  }
}

/// Recorre Flop -> Turn -> River verificando que Hero recibe decisión fresca en cada calle.
Future<void> playOut(WidgetTester t, List<String> board) async {
  final fsm = _flow.fsm;
  var bi = 0;
  for (final n in [3, 1, 1]) {
    if (fsm.screenPhase == ScreenPhase.handFinished) return;
    for (var k = 0; k < n; k++) {
      await pick(t, board[bi++]);
    }
    final st = fsm.street;
    await villainsPassive(t);
    if (fsm.screenPhase == ScreenPhase.handFinished) return;
    expect(_flow.lastHeroStreet, st, reason: 'Hero sin decisión en $st (congelado)');
    await villainsPassive(t);
  }
}

/// Turn y River tras un flop ya jugado.
Future<void> playRest(WidgetTester t, List<String> cards) async {
  final fsm = _flow.fsm;
  for (final c in cards) {
    if (fsm.screenPhase == ScreenPhase.handFinished) return;
    await pick(t, c);
    final st = fsm.street;
    await villainsPassive(t);
    if (fsm.screenPhase == ScreenPhase.handFinished) return;
    expect(_flow.lastHeroStreet, st, reason: 'Hero sin decisión en $st (congelado)');
    await villainsPassive(t);
  }
}

/// 169 clases de mano con cartas de ejemplo.
List<(String, Card, Card)> handClasses() {
  const r = 'AKQJT98765432';
  final out = <(String, Card, Card)>[];
  for (var i = 0; i < 13; i++) {
    for (var j = i; j < 13; j++) {
      if (i == j) {
        out.add(('${r[i]}${r[i]}', Card.parse('${r[i]}s'), Card.parse('${r[i]}h')));
      } else {
        out.add(('${r[i]}${r[j]}s', Card.parse('${r[i]}s'), Card.parse('${r[j]}s')));
        out.add(('${r[i]}${r[j]}o', Card.parse('${r[i]}s'), Card.parse('${r[j]}h')));
      }
    }
  }
  return out;
}

void main() {
  testWidgets('Flujo ROL: AJs CO OR 2.5 -> UTG Limp => ROL/ISO; 1A Limp-Call -> Flop/Turn/River con decisión viva', (t) async {
    final flow = await start(t, 'Ah', 'Jh', 'co');
    final fsm = flow.fsm;
    expect(oracle(t), 'ACCIÓN: OR a 2.5 bb');
    await tapKey(t, 'act-utg-limp');
    expect(oracle(t), startsWith('ACCIÓN: ROL / ISO-RAISE a '), reason: 'Bug_1: debe cambiar a ROL');
    final iso = fsm.actions.lastWhere((a) => a.actor == Position.co).amountBb;
    expect(iso, greaterThanOrEqualTo(3.5));
    expect(iso, isNot(2.5));
    await tapKey(t, 'act-utg-call');
    expect(fsm.potTypeNow, PotType.srp);
    await playOut(t, ['Kd', '7c', '2s', '4h', '9d']);
    expect(fsm.screenPhase, ScreenPhase.handFinished);
    expect(t.takeException(), isNull);
  });

  testWidgets('Flujo ROL 1B: tras el ROL de Hero, BTN 3-Bet => Hero re-evaluado vs 3-Bet', (t) async {
    final flow = await start(t, 'Ah', 'Jh', 'co');
    final fsm = flow.fsm;
    await tapKey(t, 'act-utg-limp');
    final rol = oracle(t);
    expect(rol, startsWith('ACCIÓN: ROL / ISO-RAISE'));
    await tapKey(t, 'act-btn-3bet');
    expect(fsm.actions.last.actor == Position.co || fsm.currentActorSeat == Position.utg || fsm.screenPhase == ScreenPhase.pickFlop, isTrue);
    expect(fsm.actions.where((a) => a.actor == Position.co).length, 2, reason: 'Law_3: Hero vuelve a decidir vs 3-Bet');
    expect(find.textContaining('ACTUALIZADO VS BTN 3-Bet'), findsOneWidget);
    expect(oracle(t), isNot(rol));
    expect(t.takeException(), isNull);
  });

  testWidgets('Flujo Hero 3-Bet (QQ BTN vs UTG OR): UTG con Fold/Call/4-Bet/All-In; 4-Bet 19 -> respuesta viva', (t) async {
    final flow = await start(t, 'Qh', 'Qd', 'btn');
    final fsm = flow.fsm;
    await tapKey(t, 'act-utg-or');
    expect(oracle(t), 'ACCIÓN: 3-BET a 7.5 bb');
    for (final k in ['act-utg-fold', 'act-utg-call', 'act-utg-4bet', 'act-utg-allin']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: 'Bug_2: $k');
    }
    await tapKey(t, 'act-utg-4bet');
    await scrubTo(t, 19.0);
    await tapKey(t, 'resize-utg');
    expect(fsm.actions.lastWhere((a) => a.actor == Position.utg).amountBb, 19.0);
    expect(fsm.actions.last.actor == Position.btn || fsm.screenPhase != ScreenPhase.preflopAction, isTrue, reason: 'Hero vs 4-Bet re-evaluado');
    expect(find.textContaining('ACTUALIZADO VS UTG 4-Bet 19.0bb'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('Flujo Hero 3-Bet manual (98s BTN) -> UTG Call -> 3-Bet pot 16.5 con decisión viva en Flop/Turn/River', (t) async {
    final flow = await start(t, '9s', '8s', 'btn');
    final fsm = flow.fsm;
    await tapKey(t, 'act-utg-or');
    if (fsm.actions.lastWhere((a) => a.actor == Position.btn).type != ActionType.raise) {
      await tapKey(t, 'override');
      await tapKey(t, 'act-btn-3bet');
    }
    expect(fsm.currentHighBetBB, 7.5);
    expect(find.byKey(const ValueKey('act-utg-call')), findsOneWidget);
    await tapKey(t, 'act-utg-call');
    await pick(t, 'Ks');
    expect(fsm.seats[Position.sb]!.alive || fsm.seats[Position.bb]!.alive, isFalse);
    expect(fsm.totalPotBB, closeTo(16.5, 1e-9));
    expect(fsm.potTypeNow, PotType.threeBet);
    await pick(t, '7d');
    await pick(t, '2c');
    final st = fsm.street;
    await villainsPassive(t);
    expect(flow.lastHeroStreet, st, reason: 'Bug_3: tras override, el solver vuelve a decidir en el flop del 3-Bet pot');
    await villainsPassive(t);
    await playRest(t, ['Th', '4s']);
    expect(t.takeException(), isNull);
  }, skip: false);

  testWidgets('Flujo Squeeze: Hero MP OR -> CO Call -> SB 3-Bet 11 => turno de Hero (MP) y luego CO', (t) async {
    final flow = await start(t, 'Ac', 'Qc', 'mp');
    final fsm = flow.fsm;
    expect(oracle(t), 'ACCIÓN: OR a 2.5 bb');
    await tapKey(t, 'act-co-call');
    await tapKey(t, 'act-sb-3bet');
    await scrubTo(t, 11.0);
    await tapKey(t, 'resize-sb');
    expect(fsm.actions.lastWhere((a) => a.actor == Position.sb).amountBb, 11.0);
    final sq = fsm.actions.lastIndexWhere((a) => a.actor == Position.sb);
    expect(fsm.actions.skip(sq).any((a) => a.actor == Position.mp), isTrue, reason: 'no se salta el squeeze: Hero decide');
    expect(find.textContaining('ACTUALIZADO VS SB 3-Bet 11.0bb'), findsOneWidget);
    if (fsm.screenPhase == ScreenPhase.preflopAction) expect(fsm.pendingToAct, contains(Position.co), reason: 'luego pregunta a CO');
    expect(t.takeException(), isNull);
  });

  test('Barrido 169 manos x 6 posiciones: OR / ROL / vs OR / vs 3-Bet => decisión fresca, nunca null ni congelada', () {
    final classes = handClasses();
    expect(classes.length, 169);
    var n = 0;
    for (final (hc, c1, c2) in classes) {
      final cards = (c1, c2);
      for (final pos in Position.values) {
        final fsm = HandFlowFSM()..configure(stake: Stake.nl50, hero: pos);
        fsm.addCard(cards.$1);
        fsm.addCard(cards.$2);
        final order = HandFlowFSM.preflopOrder;
        final before = order.sublist(0, order.indexOf(pos));
        final after = order.sublist(order.indexOf(pos) + 1);
        String? lastSig;
        void check(String spot) {
          final o = fsm.liveOracle;
          expect(o, isNotNull, reason: '$hc $pos $spot: null');
          expect(o!.signature, fsm.stateSignature, reason: '$hc $pos $spot: firma vieja');
          expect(o.signature, isNot(lastSig), reason: '$hc $pos $spot: estado no cambió');
          lastSig = o.signature;
          n++;
        }

        if (pos != Position.bb) check('OR');
        if (before.isNotEmpty) {
          fsm.act(before.first, ActionType.call); // Limp => ROL
          check('ROL');
          fsm.undo();
          fsm.act(before.first, ActionType.raise, amountBb: 2.5); // OR => vs OR
          check('vs OR');
          if (before.length >= 2) {
            fsm.act(before[1], ActionType.raise, amountBb: 7.5); // 3-Bet antes de Hero => vs 3-Bet
            check('vs 3-Bet');
          }
        } else if (after.isNotEmpty) {
          // Hero UTG: OR propio y 3-Bet detrás.
          fsm.act(pos, ActionType.raise, amountBb: 2.5);
          fsm.act(after.first, ActionType.raise, amountBb: 7.5);
          check('vs 3-Bet');
        }
      }
    }
    expect(n, greaterThan(169 * 6 * 2));
  });

  test('Bug_4 barrido postflop: ROL / SRP / 3-Bet / 4-Bet pot en todas las parejas de posiciones => decisión en el flop', () {
    final fails = <String>[];
    var n = 0;
    final order = HandFlowFSM.preflopOrder;
    for (final hero in order) {
      for (final v in order) {
        if (v == hero) continue;
        final first = order.indexOf(v) < order.indexOf(hero) ? v : hero;
        final second = first == v ? hero : v;
        final lines = <String, List<(Position, ActionType, double)>>{
          'SRP': [(first, ActionType.raise, 2.5), (second, ActionType.call, 0)],
          'ROL': [(first, ActionType.call, 0), (second, ActionType.raise, 4.5), (first, ActionType.call, 0)],
          '3BP': [(first, ActionType.raise, 2.5), (second, ActionType.raise, 9), (first, ActionType.call, 0)],
          '4BP': [(first, ActionType.raise, 2.5), (second, ActionType.raise, 9), (first, ActionType.raise, 22), (second, ActionType.call, 0)],
        };
        for (final e in lines.entries) {
          final fsm = HandFlowFSM()..configure(stake: Stake.nl50, hero: hero);
          fsm.addCard(Card.parse('Ah'));
          fsm.addCard(Card.parse('Jh'));
          try {
            for (final (p, t, a) in e.value) {
              if (fsm.phase != HandPhase.preflop) break;
              fsm.act(p, t, amountBb: a);
            }
            while (fsm.phase == HandPhase.preflop && fsm.currentActor != null) {
              fsm.act(fsm.currentActor!, fsm.currentBet - fsm.seats[fsm.currentActor!]!.committed > 0 ? ActionType.fold : ActionType.check);
            }
            final runout = ['Kd', '7c', '2s', '9h', '4d'];
            var ci = 0;
            // Flop -> Turn -> River: Hero siempre con decisión válida; villano pasivo (check/call).
            for (var guard = 0; guard < 40 && fsm.phase != HandPhase.handOver; guard++) {
              if (fsm.awaitingCards) {
                fsm.addCard(Card.parse(runout[ci++]));
                continue;
              }
              final a = fsm.currentActor!;
              if (a == hero) {
                n++;
                if (fsm.activeRecommendation == null) {
                  fails.add('${e.key} hero=$hero v=$v ${fsm.street}: ${fsm.recommendationError}');
                  break;
                }
                fsm.executeRecommendation();
              } else {
                fsm.act(a, fsm.currentBet - fsm.seats[a]!.committed > 0 ? ActionType.call : ActionType.check);
              }
            }
          } on Object catch (x) {
            fails.add('${e.key} hero=$hero v=$v: $x');
          }
        }
      }
    }
    expect(fails, isEmpty);
    expect(n, greaterThan(300));
  });
}

extension on HandFlowFSM {
  PotType get potTypeNow => buildGameState().potType;
}
