import 'package:flutter/material.dart' hide Card;

import '../../application/hand_flow_fsm.dart';
import '../../application/linear_hand_flow.dart';
import '../../core/models/game_state.dart';
import '../theme/obsidian_theme.dart';
import '../theme.dart';
import 'bet_size_scrubber_bar.dart';
import 'smarthud_quick_sheet.dart';

/// Single-Focus Stepper Wizard (Fase 14.0): una sola pregunta en pantalla a la vez.
enum WizardStep { handAndSeat, preflopTable, boardCards, streetAction, heroManual, handOver }

class WizardSteps {
  WizardSteps._();

  static bool heroActed(HandFlowFSM fsm, Street s) => fsm.actions.any((a) => a.street == s && a.actor == fsm.heroPosition);

  /// Paso visible derivado 100% del estado de la FSM (Law_1: la UI nunca pregunta "¿quién sigue?").
  static WizardStep of(LinearHandFlow f, {required bool positionChosen}) {
    final fsm = f.fsm;
    if (fsm.phase == HandPhase.setup) return WizardStep.handAndSeat;
    if (fsm.screenPhase == ScreenPhase.handFinished) return WizardStep.handOver;
    if (fsm.awaitingCards) return WizardStep.boardCards;
    if (fsm.street == Street.preflop && fsm.actions.isEmpty && !positionChosen) return WizardStep.handAndSeat;
    if (fsm.street == Street.preflop) return WizardStep.preflopTable;
    if (f.atHeroTurn) return WizardStep.heroManual;
    return WizardStep.streetAction;
  }

  static String actionLabel(PlayerAction a) => switch (a.type) {
    ActionType.fold => 'Fold',
    ActionType.check => 'Check',
    ActionType.call => 'Call ${a.amountBb.toStringAsFixed(1)} bb',
    ActionType.bet => 'Bet ${a.amountBb.toStringAsFixed(1)} bb',
    ActionType.raise => 'Raise a ${a.amountBb.toStringAsFixed(1)} bb',
    ActionType.allIn => 'All-In ${a.amountBb.toStringAsFixed(1)} bb',
  };
}

/// Piezas visuales comunes del wizard (monocromas, botones grandes).
mixin WizardKit<T extends StatefulWidget> on State<T> {
  Widget chip(String label, String key, bool selected, VoidCallback? f, {double h = 46, bool expand = false}) {
    final b = SizedBox(
      height: h,
      child: FilledButton(
        key: ValueKey(key),
        style: FilledButton.styleFrom(
          backgroundColor: selected ? Obsidian.buttonActive : Obsidian.buttonDefault,
          foregroundColor: selected ? Obsidian.buttonActiveText : Obsidian.buttonDefaultText,
          disabledBackgroundColor: Obsidian.surfacePanel,
          disabledForegroundColor: Obsidian.textMuted,
          minimumSize: const Size(48, 46),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Obsidian.borderFine),
          ),
        ),
        onPressed: f,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      ),
    );
    return expand ? Expanded(child: b) : b;
  }

  Widget big(String label, String key, VoidCallback? f, {bool primary = true}) => Row(children: [chip(label, key, primary, f, h: 54, expand: true)]);

  Widget card(String title, String subtitle, List<Widget> body, String key) => Container(
    key: ValueKey(key),
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Obsidian.surfacePanel,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Obsidian.borderFine),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          key: ValueKey('$key-title'),
          style: const TextStyle(color: Obsidian.textPrimary, fontSize: 17, fontWeight: FontWeight.w800),
        ),
        if (subtitle.isNotEmpty) ...[const SizedBox(height: 2), Text(subtitle, style: const TextStyle(color: Obsidian.textSecondary, fontSize: 12))],
        const SizedBox(height: 10),
        ...body,
      ],
    ),
  );

  Widget label(String t) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 4),
    child: Text(
      t,
      style: const TextStyle(color: Obsidian.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );

  /// Barra deslizable contextual: siempre con su etiqueta explícita encima.
  Widget slider(
    String text,
    double value,
    double max,
    ValueChanged<double> onChanged, {
    double? pot,
    ValueChanged<double>? onCommit,
    bool arrowsCommit = true,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          text,
          key: const ValueKey('scrub-label'),
          style: Obsidian.num(size: 13, color: Obsidian.textPrimary, weight: FontWeight.w700),
        ),
      ),
      BetSizeScrubberBar(value: value, max: max, potBb: pot, onChanged: onChanged, onCommit: onCommit, arrowsCommit: arrowsCommit),
    ],
  );
}

double capOf(HandFlowFSM fsm, Position p) => fsm.seats[p]!.committed + fsm.seats[p]!.stack;

void raiseOrShove(LinearHandFlow flow, Position p, double to) {
  final fsm = flow.fsm;
  final cap = capOf(fsm, p);
  final x = to < fsm.minRaiseTo ? fsm.minRaiseTo : to;
  if (x >= cap - 1e-9) {
    flow.seatAct(p, ActionType.allIn);
  } else {
    flow.seatAct(p, fsm.currentBet == 0 ? ActionType.bet : ActionType.raise, amount: x);
  }
}

// ---------------------------------------------------------------- PASO 5 ----
class VillainTurnStep extends StatefulWidget {
  const VillainTurnStep({super.key, required this.flow, required this.scrub, required this.onScrub, required this.act});
  final LinearHandFlow flow;
  final double scrub;
  final ValueChanged<double> onScrub;
  final void Function(VoidCallback f) act;

  @override
  State<VillainTurnStep> createState() => _VillainTurnStepState();
}

class _VillainTurnStepState extends State<VillainTurnStep> with WizardKit {
  LinearHandFlow get flow => widget.flow;
  HandFlowFSM get fsm => flow.fsm;

  /// Opt_3: nº de villanos que hablan antes de Hero sin apuesta en la calle (atajo [Check hasta mí]).
  int get _checkToHero {
    final hero = fsm.heroPosition;
    if (fsm.currentBet > 0 || !fsm.pendingToAct.contains(hero) || !fsm.canTap(hero)) return 0;
    final seats = fsm.activeSeats;
    final ci = seats.indexOf(fsm.currentActorSeat!), hi = seats.indexOf(hero);
    if (ci < 0 || hi <= ci) return 0;
    return seats.sublist(ci, hi).where(fsm.pendingToAct.contains).length;
  }

  @override
  Widget build(BuildContext context) {
    final p = fsm.currentActorSeat!;
    final s = fsm.seats[p]!;
    final toCall = fsm.currentBet - s.committed;
    final pos = p.name.toUpperCase();
    final tag = fsm.hudOf(p)?.tag.name ?? s.profile.name;
    final street = fsm.street.name.toUpperCase();
    final board = fsm.board.map((c) => '${c.rank.symbol}${AppColors.suitGlyph(c.suit)}').join(' ');
    final canRaise = fsm.canRaise(p);
    void to(double x) => widget.act(() => raiseOrShove(flow, p, BetSizeScrubberBar.snap(x)));
    final body = <Widget>[
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: const ValueKey('v-hud'),
          onPressed: () => SmartHudQuickSheet.show(context, fsm, p),
          child: Text(
            '[Perfil: $tag ▾]',
            style: const TextStyle(color: Obsidian.textSecondary, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    ];
    if (toCall <= 0) {
      body.addAll([
        big('Check', 'v-check', () => widget.act(() => flow.seatAct(p, ActionType.check)), primary: false),
        if (_checkToHero >= 2) ...[const SizedBox(height: 6), big('✓ Check hasta mí ($_checkToHero villanos)', 'check-to-me', () => widget.act(flow.heroGo))],
        const SizedBox(height: 6),
        Row(
          children: [
            chip('Bet 33%', 'v-b33', false, canRaise ? () => to(fsm.pot * .33) : null, expand: true),
            const SizedBox(width: 6),
            chip('Bet 50%', 'v-b50', false, canRaise ? () => to(fsm.pot * .5) : null, expand: true),
            const SizedBox(width: 6),
            chip('Bet 75%', 'v-b75', false, canRaise ? () => to(fsm.pot * .75) : null, expand: true),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            chip('Bet 1bb 🐟', 'v-b1', false, canRaise ? () => to(1) : null, expand: true),
            const SizedBox(width: 6),
            chip('All-In', 'v-allin', false, () => widget.act(() => flow.seatAct(p, ActionType.allIn)), expand: true),
          ],
        ),
        slider(
          'Ajustar Bet: ${widget.scrub.toStringAsFixed(1)} bb',
          widget.scrub,
          capOf(fsm, p),
          widget.onScrub,
          pot: fsm.pot,
          arrowsCommit: false,
          onCommit: canRaise ? to : null,
        ),
        big('Bet ${widget.scrub.toStringAsFixed(1)} bb', 'v-bar', canRaise ? () => to(widget.scrub) : null),
      ]);
    } else {
      body.addAll([
        Row(
          children: [
            chip('Fold ❌', 'v-fold', false, () => widget.act(() => flow.seatAct(p, ActionType.fold)), h: 54, expand: true),
            const SizedBox(width: 6),
            chip('Call ${toCall.toStringAsFixed(1)}bb', 'v-call', false, () => widget.act(() => flow.seatAct(p, ActionType.call)), h: 54, expand: true),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            chip('Min-Raise 2x 🐟', 'v-minr', false, canRaise ? () => to(fsm.minRaiseTo) : null, expand: true),
            const SizedBox(width: 6),
            chip('Raise 3x', 'v-r3x', false, canRaise ? () => to(fsm.currentBet * 3) : null, expand: true),
            const SizedBox(width: 6),
            chip('All-In', 'v-allin', false, () => widget.act(() => flow.seatAct(p, ActionType.allIn)), expand: true),
          ],
        ),
        slider(
          'Ajustar Raise a: ${widget.scrub.toStringAsFixed(1)} bb',
          widget.scrub,
          capOf(fsm, p),
          widget.onScrub,
          pot: fsm.pot,
          arrowsCommit: false,
          onCommit: canRaise ? to : null,
        ),
        big('Raise a ${widget.scrub.toStringAsFixed(1)} bb', 'v-bar', canRaise ? () => to(widget.scrub) : null),
        const SizedBox(height: 6),
        big('Resto Foldeó', 'rest-fold', () => widget.act(flow.resolveStreet), primary: false),
      ]);
    }
    return card(
      '$street [$board] · Turno $pos:',
      toCall > 0 ? 'Debe ${toCall.toStringAsFixed(1)} bb' : 'Nadie ha apostado en esta calle',
      body,
      'step-villain',
    );
  }
}
