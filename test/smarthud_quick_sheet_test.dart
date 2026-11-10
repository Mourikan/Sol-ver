import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:sol_ver/application/hand_flow_fsm.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/reads/villain_archetypes.dart';
import 'package:sol_ver/ui/theme.dart';
import 'package:sol_ver/ui/widgets/smarthud_quick_sheet.dart';

void main() {
  testWidgets('SmartHUD sheet: 1-tap tag, stepper con diagnóstico en vivo y timing', (t) async {
    await t.binding.setSurfaceSize(const Size(360, 740));
    final fsm = HandFlowFSM()..configure(hero: Position.btn);
    fsm
      ..addCard(Card.parse('Ah'))
      ..addCard(Card.parse('Kh'));
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: SmartHudQuickSheet(fsm: fsm, seat: Position.bb))));
    await t.tap(find.byKey(const ValueKey('hud-tag-agroManiac')));
    await t.pump();
    expect(fsm.seats[Position.bb]!.profile, VillainProfile.maniac);
    expect(fsm.seats[Position.bb]!.hud!.tag, VillainTag.agroManiac);
    await t.tap(find.byKey(const ValueKey('hud-tag-fishStation')));
    await t.pump();
    expect(find.textContaining('Pasivo Inelástico'), findsOneWidget);
    final pfr = find.descendant(of: find.byKey(const ValueKey('hud-step-PFR')), matching: find.text('+5'));
    for (var i = 0; i < 2; i++) {
      await t.tap(pfr);
      await t.pump();
    }
    expect(fsm.seats[Position.bb]!.hud!.stats.pfr, 18);
    await t.tap(find.byKey(const ValueKey('hud-timing-1')));
    await t.pump();
    expect(fsm.seats[Position.bb]!.nextTiming, TimingTell.instaAction);
  });
}
