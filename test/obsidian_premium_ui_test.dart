import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/application/hand_flow_fsm.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/ui/screens/solver_cockpit_screen.dart';
import 'package:sol_ver/ui/theme.dart';
import 'package:sol_ver/ui/widgets/blocker_xray.dart';

final frames = <int>[];

Future<HandFlowFSM> boot(WidgetTester t, Size size, {Position hero = Position.btn}) async {
  await t.binding.setSurfaceSize(size);
  final fsm = HandFlowFSM()..configure(stake: Stake.nl25, hero: hero);
  await t.pumpWidget(MaterialApp(theme: buildTheme(), home: SolverCockpitScreen(fsm: fsm)));
  return fsm;
}

Future<void> pumpTimed(WidgetTester t) async {
  final sw = Stopwatch()..start();
  await t.pump();
  frames.add(sw.elapsedMicroseconds);
}

void main() {
  for (final size in const [Size(390, 844), Size(412, 915)]) {
    testWidgets('Rewind por breadcrumb restaura Pot/Stacks/Street exactos (${size.width.round()}x${size.height.round()})', (t) async {
      final fsm = await boot(t, size);
      await t.tap(find.byKey(const ValueKey('fcm-As')));
      await t.tap(find.byKey(const ValueKey('fcm-Qd')));
      await pumpTimed(t);
      fsm.act(Position.co, ActionType.raise, amountBb: 2.5);
      await pumpTimed(t);
      final pot = fsm.totalPotBB;
      final stacks = {for (final p in HandFlowFSM.preflopOrder) p: fsm.stackOf(p)};
      final street = fsm.street;
      fsm
        ..act(Position.btn, ActionType.raise, amountBb: 8)
        ..act(Position.sb, ActionType.fold)
        ..act(Position.bb, ActionType.fold)
        ..act(Position.co, ActionType.call);
      for (final c in ['Ks', '9s', '4s']) {
        fsm.addCard(Card.parse(c));
      }
      await pumpTimed(t);
      expect(fsm.street, Street.flop);
      expect(find.byKey(const ValueKey('breadcrumb')), findsOneWidget);
      final idx = fsm.stepLabels.indexWhere((l) => l.startsWith('BTN'));
      expect(idx, greaterThan(0));
      await t.ensureVisible(find.byKey(ValueKey('crumb-$idx')));
      await t.pump();
      await t.tap(find.byKey(ValueKey('crumb-$idx')));
      await pumpTimed(t);
      expect(fsm.street, street);
      expect(fsm.totalPotBB, closeTo(pot, 1e-9));
      for (final p in HandFlowFSM.preflopOrder) {
        expect(fsm.stackOf(p), closeTo(stacks[p]!, 1e-9), reason: p.name);
      }
      expect(fsm.currentActor, Position.btn);
      expect(t.takeException(), isNull);
    });

    testWidgets('Peek 13x13: 169 celdas sin overflow (${size.width.round()}x${size.height.round()})', (t) async {
      final fsm = await boot(t, size, hero: Position.bb);
      await t.tap(find.byKey(const ValueKey('fcm-Ah')));
      await t.tap(find.byKey(const ValueKey('fcm-Kd')));
      await pumpTimed(t);
      fsm
        ..act(Position.btn, ActionType.raise, amountBb: 2.5)
        ..act(Position.sb, ActionType.fold);
      await pumpTimed(t);
      final r = fsm.activeRecommendation!.perceivedVillainRange!;
      expect(r.classWeights.length, 169);
      expect(r.classWeights.where((w) => w > 0).length, greaterThan(20));
      await t.tap(find.byKey(const ValueKey('peek-169')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('heatmap')), findsOneWidget);
      final box = t.getSize(find.byKey(const ValueKey('heatmap')));
      expect(box.width, greaterThan(13 * 15));
      expect(box.width, closeTo(box.height, 0.5));
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('Rayos-X: As con 3 picas en el board => NUT BLOCKER; River con color fallido => BLOCKS BLUFFS / UNBLOCKER OK', (t) async {
    final fsm = await boot(t, const Size(390, 844));
    await t.tap(find.byKey(const ValueKey('fcm-As')));
    await t.tap(find.byKey(const ValueKey('fcm-Qd')));
    await t.pump();
    fsm.act(Position.co, ActionType.raise, amountBb: 2.5);
    fsm
      ..act(Position.btn, ActionType.call)
      ..act(Position.sb, ActionType.fold)
      ..act(Position.bb, ActionType.fold);
    for (final c in ['Ks', '9s', '4s']) {
      fsm.addCard(Card.parse(c));
    }
    await t.pump();
    expect(find.byKey(const ValueKey('xray-0')), findsOneWidget);
    expect(find.textContaining('NUT BLOCKER'), findsWidgets);
    expect(BlockerXRay.of(Card.parse('As'), Card.parseMany('Ks9s4s')), XRay.nutBlocker);
    expect(BlockerXRay.of(Card.parse('Qd'), Card.parseMany('Ks9s4s')), isNull);
    expect(BlockerXRay.of(Card.parse('Jh'), Card.parseMany('KhQh7d2c3s')), XRay.blocksBluffs);
    expect(BlockerXRay.of(Card.parse('Jd'), Card.parseMany('KhQh7d2c3s')), anyOf(XRay.unblockerOk, XRay.nutBlocker));
    expect(t.takeException(), isNull);
  });

  final renderOnly = <int>[];
  testWidgets('Render puro (sin solver): rebuild completo del cockpit', (t) async {
    final fsm = await boot(t, const Size(390, 844));
    await t.tap(find.byKey(const ValueKey('fcm-As')));
    await t.tap(find.byKey(const ValueKey('fcm-Qd')));
    await t.pump();
    fsm.act(Position.co, ActionType.raise, amountBb: 2.5);
    await t.pump();
    for (var i = 0; i < 20; i++) {
      fsm.setTiming(Position.co, i.isEven ? TimingTell.instaAction : TimingTell.none);
      final sw = Stopwatch()..start();
      await t.pump();
      renderOnly.add(sw.elapsedMicroseconds);
    }
    expect(t.takeException(), isNull);
  });

  test('Tiempos de rebuild medidos', () {
    frames.sort();
    // ignore: avoid_print
    print('con solver (debug) us: mediana ${frames[frames.length ~/ 2]} p90 ${frames[(frames.length * 0.9).floor()]} n=${frames.length}');
    renderOnly.sort();
    // ignore: avoid_print
    print('render puro (debug) us: mediana ${renderOnly[renderOnly.length ~/ 2]} p90 ${renderOnly[(renderOnly.length * 0.9).floor()]}');
  });
}
