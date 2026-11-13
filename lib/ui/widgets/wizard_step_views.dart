import 'package:flutter/material.dart' hide Card;

import '../../application/hand_flow_fsm.dart';
import '../../application/linear_hand_flow.dart';
import '../../core/models/game_state.dart';
import '../theme/obsidian_theme.dart';
import '../theme.dart';
import 'bet_size_scrubber_bar.dart';
import 'smarthud_quick_sheet.dart';

/// Single-Focus Stepper Wizard (Fase 14.0): una sola pregunta en pantalla a la vez.
enum WizardStep { handAndSeat, before, heroAndAfter, boardCards, streetAction, heroManual, handOver }

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
    if (f.atHeroTurn) return heroActed(fsm, fsm.street) || f.manualMode || fsm.street != Street.preflop ? WizardStep.heroManual : WizardStep.before;
    if (fsm.street == Street.preflop) return heroActed(fsm, Street.preflop) ? WizardStep.heroAndAfter : WizardStep.before;
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
mixin _WizardKit<T extends StatefulWidget> on State<T> {
  Widget chip(String label, String key, bool selected, VoidCallback? f, {double h = 44, bool expand = false}) {
    final b = SizedBox(
      height: h,
      child: FilledButton(
        key: ValueKey(key),
        style: FilledButton.styleFrom(
          backgroundColor: selected ? Obsidian.buttonActive : Obsidian.buttonDefault,
          foregroundColor: selected ? Obsidian.buttonActiveText : Obsidian.buttonDefaultText,
          disabledBackgroundColor: Obsidian.surfacePanel,
          disabledForegroundColor: Obsidian.textMuted,
          minimumSize: const Size(48, 44),
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
  Widget slider(String text, double value, double max, ValueChanged<double> onChanged, {double? pot}) => Column(
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
      BetSizeScrubberBar(value: value, max: max, potBb: pot, onChanged: onChanged),
    ],
  );
}

double _cap(HandFlowFSM fsm, Position p) => fsm.seats[p]!.committed + fsm.seats[p]!.stack;

void _raiseOrShove(LinearHandFlow flow, Position p, double to) {
  final fsm = flow.fsm;
  final cap = _cap(fsm, p);
  final x = to < fsm.minRaiseTo ? fsm.minRaiseTo : to;
  if (x >= cap - 1e-9) {
    flow.seatAct(p, ActionType.allIn);
  } else {
    flow.seatAct(p, fsm.currentBet == 0 ? ActionType.bet : ActionType.raise, amount: x);
  }
}

// ---------------------------------------------------------------- PASO 2 ----
class BeforeHeroStep extends StatefulWidget {
  const BeforeHeroStep({super.key, required this.flow, required this.scrub, required this.onScrub, required this.act});
  final LinearHandFlow flow;
  final double scrub;
  final ValueChanged<double> onScrub;
  final void Function(VoidCallback f) act;

  @override
  State<BeforeHeroStep> createState() => _BeforeHeroStepState();
}

class _BeforeHeroStepState extends State<BeforeHeroStep> with _WizardKit {
  LinearHandFlow get flow => widget.flow;
  HandFlowFSM get fsm => flow.fsm;
  Position? opener;
  String kind = 'open';
  final mids = <Position, String>{}; // 'call' | '3bet'

  void _go() {
    final o = opener!;
    switch (kind) {
      case 'limp':
        flow.seatAct(o, ActionType.call);
      case 'allin':
        flow.seatAct(o, ActionType.allIn);
      default:
        _raiseOrShove(flow, o, widget.scrub);
    }
    for (final p in flow.coldCallerCandidates(o)) {
      final m = mids[p];
      if (m == null || fsm.currentActorSeat == null || fsm.currentActorSeat == fsm.heroPosition) continue;
      if (m == '3bet' && fsm.canRaise(p)) {
        _raiseOrShove(flow, p, fsm.currentBet * 3);
      } else {
        flow.seatAct(p, fsm.currentBet - fsm.seats[p]!.committed > 0 ? ActionType.call : ActionType.check);
      }
    }
    if (!WizardSteps.heroActed(fsm, Street.preflop) && fsm.currentActorSeat != null) flow.heroGo();
  }

  @override
  Widget build(BuildContext context) {
    final hero = fsm.heroPosition.name.toUpperCase();
    final prev = flow.openersBeforeHero;
    final between = opener == null ? const <Position>[] : flow.coldCallerCandidates(opener!);
    mids.removeWhere((k, _) => !between.contains(k));
    final o = opener?.name.toUpperCase();
    return card('¿Quién entró a la mano antes de $hero?', 'Los asientos que no toques se asumen Fold', [
      big('Nadie entró (Llegó limpia a mí)', 'nobody-in', () => widget.act(flow.heroGo)),
      if (prev.isNotEmpty) label('Si alguien entró, toca su asiento:'),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final p in prev)
            chip(
              p.name.toUpperCase(),
              'who-${p.name}',
              opener == p,
              () => setState(() {
                opener = opener == p ? null : p;
                kind = 'open';
                if (opener != null) widget.onScrub(LinearHandFlow.openSize(p));
              }),
            ),
        ],
      ),
      if (opener != null) ...[
        label('¿Qué hizo $o?'),
        Row(
          children: [
            chip('Open', 'op-open', kind == 'open', () => setState(() => kind = 'open'), expand: true),
            const SizedBox(width: 6),
            chip('Limp 1bb', 'op-limp', kind == 'limp', () => setState(() => kind = 'limp'), expand: true),
            const SizedBox(width: 6),
            chip('All-In', 'op-allin', kind == 'allin', () => setState(() => kind = 'allin'), expand: true),
          ],
        ),
        if (kind == 'open') slider('Tamaño de apuesta de $o: ${widget.scrub.toStringAsFixed(1)} bb', widget.scrub, _cap(fsm, opener!), widget.onScrub),
        for (final p in between) ...[
          label('${p.name.toUpperCase()} (entre $o y tú):'),
          Row(
            children: [
              chip(
                'Pagó (Call)',
                'mid-${p.name}-call',
                mids[p] == 'call',
                () => setState(() => mids[p] == 'call' ? mids.remove(p) : mids[p] = 'call'),
                expand: true,
              ),
              const SizedBox(width: 6),
              chip(
                'Hizo 3-Bet',
                'mid-${p.name}-3bet',
                mids[p] == '3bet',
                () => setState(() => mids[p] == '3bet' ? mids.remove(p) : mids[p] = '3bet'),
                expand: true,
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        big('Ver mi jugada del Solver ➔', 'see-solver', () => widget.act(_go)),
      ],
    ], 'step-before');
  }
}

// ---------------------------------------------------------------- PASO 3 ----
class AfterHeroStep extends StatefulWidget {
  const AfterHeroStep({super.key, required this.flow, required this.scrub, required this.onScrub, required this.act});
  final LinearHandFlow flow;
  final double scrub;
  final ValueChanged<double> onScrub;
  final void Function(VoidCallback f) act;

  @override
  State<AfterHeroStep> createState() => _AfterHeroStepState();
}

class _AfterHeroStepState extends State<AfterHeroStep> with _WizardKit {
  LinearHandFlow get flow => widget.flow;
  HandFlowFSM get fsm => flow.fsm;
  final paid = <Position>{};
  bool reraise = false;
  Position? raiser;

  @override
  Widget build(BuildContext context) {
    final pending = flow.pendingOwing;
    paid.removeWhere((x) => !pending.contains(x));
    if (raiser != null && !pending.contains(raiser)) raiser = null;
    final already = flow.liveVillains.where((v) => !pending.contains(v)).length;
    final n = already + paid.length + 1;
    final h = fsm.actions.lastWhere((a) => a.street == Street.preflop && a.actor == fsm.heroPosition);
    return card('Después de tu ${WizardSteps.actionLabel(h)}, ¿quiénes entraron al bote?', 'Toca solo a los que pagaron o resubieron; el resto se asume Fold', [
      big('Todos Foldearon (Ganaste el bote)', 'all-fold', () => widget.act(flow.resolveStreet), primary: false),
      label('¿Quiénes pagaron?'),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final p in pending)
            chip('${p.name.toUpperCase()}: Pagó', 'paid-${p.name}', paid.contains(p), () => setState(() => paid.contains(p) ? paid.remove(p) : paid.add(p))),
        ],
      ),
      const SizedBox(height: 8),
      big(
        'Ir al Flop ($n Jugadores) ➔',
        'go-flop',
        paid.isEmpty && already == 0
            ? null
            : () => widget.act(() {
                final cs = Set.of(paid);
                paid.clear();
                flow.goToFlop(cs);
              }),
      ),
      const SizedBox(height: 8),
      big('Alguien me hizo 4-Bet / Squeeze', 're-raise-open', () => setState(() => reraise = !reraise), primary: reraise),
      if (reraise) ...[
        label('¿Quién te resubió?'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in pending)
              if (fsm.canRaise(p))
                chip(
                  p.name.toUpperCase(),
                  'rr-${p.name}',
                  raiser == p,
                  () => setState(() {
                    raiser = p;
                    widget.onScrub(BetSizeScrubberBar.snap(fsm.currentBet * 2.5));
                  }),
                ),
          ],
        ),
        if (raiser != null) ...[
          slider(
            'Tamaño de la resubida de ${raiser!.name.toUpperCase()}: ${widget.scrub.toStringAsFixed(1)} bb',
            widget.scrub,
            _cap(fsm, raiser!),
            widget.onScrub,
          ),
          big(
            'Recalcular mi jugada ➔',
            'rr-go',
            () => widget.act(() {
              final r = raiser!;
              setState(() {
                reraise = false;
                raiser = null;
                paid.clear();
              });
              _raiseOrShove(flow, r, widget.scrub);
            }),
          ),
        ],
      ],
    ], 'step-after');
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

class _VillainTurnStepState extends State<VillainTurnStep> with _WizardKit {
  LinearHandFlow get flow => widget.flow;
  HandFlowFSM get fsm => flow.fsm;

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
    void to(double x) => widget.act(() => _raiseOrShove(flow, p, BetSizeScrubberBar.snap(x)));
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
        slider('Ajustar Bet: ${widget.scrub.toStringAsFixed(1)} bb', widget.scrub, _cap(fsm, p), widget.onScrub, pot: fsm.pot),
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
        slider('Ajustar Raise a: ${widget.scrub.toStringAsFixed(1)} bb', widget.scrub, _cap(fsm, p), widget.onScrub, pot: fsm.pot),
        big('Raise a ${widget.scrub.toStringAsFixed(1)} bb', 'v-bar', canRaise ? () => to(widget.scrub) : null),
        const SizedBox(height: 6),
        big('Resto Foldeó', 'rest-fold', () => widget.act(flow.resolveStreet), primary: false),
      ]);
    }
    return card(
      '$street [$board] — Turno de $pos: ¿Qué hizo?',
      toCall > 0 ? 'Debe ${toCall.toStringAsFixed(1)} bb' : 'Nadie ha apostado en esta calle',
      body,
      'step-villain',
    );
  }
}
