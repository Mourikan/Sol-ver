import 'package:flutter/material.dart' hide Card;

import '../../application/hand_flow_fsm.dart';
import '../../application/linear_hand_flow.dart';
import '../../core/models/game_state.dart';
import '../theme/obsidian_theme.dart';
import 'bet_size_scrubber_bar.dart';

/// Dock inferior de memoria muscular (Fase 13.0): barra deslizadora + matriz FIJA 2x3 (52dp) que registra
/// la acción del villano en turno. Los botones nunca cambian de lugar; solo se habilitan/deshabilitan.
class FixedActionDock extends StatelessWidget {
  const FixedActionDock({super.key, required this.flow, required this.scrub, required this.onScrub, required this.act});
  final LinearHandFlow flow;
  final double scrub;
  final ValueChanged<double> onScrub;
  final void Function(VoidCallback f) act;

  static const rowHeight = 52.0;

  HandFlowFSM get fsm => flow.fsm;

  /// Rango de la barra para el asiento en turno (o Hero).
  static double maxFor(HandFlowFSM fsm) {
    final p = fsm.currentActorSeat ?? fsm.heroPosition;
    final s = fsm.seats[p];
    return s == null ? fsm.startingStackBb : s.committed + s.stack;
  }

  @override
  Widget build(BuildContext context) {
    final p = fsm.currentActorSeat;
    final villain = p != null && p != fsm.heroPosition && !fsm.awaitingCards;
    final s = villain ? fsm.seats[p]! : null;
    final toCall = s == null ? 0.0 : fsm.currentBet - s.committed;
    final cap = s == null ? 0.0 : s.committed + s.stack;
    final canRaise = villain && fsm.canRaise(p);

    VoidCallback? sized(double to) {
      if (!villain) return null;
      if (to >= cap - 1e-9) return () => flow.seatAct(p, ActionType.allIn);
      if (!canRaise) return null;
      final x = BetSizeScrubberBar.snap(to < fsm.minRaiseTo ? fsm.minRaiseTo : to);
      final t = fsm.currentBet == 0 ? ActionType.bet : ActionType.raise;
      return () => flow.seatAct(p, x >= cap - 1e-9 ? ActionType.allIn : t, amount: x >= cap ? 0 : x);
    }

    double potPct(double f) => fsm.currentBet + f * (fsm.pot + toCall);
    final barAllIn = villain && scrub >= cap - 1e-9;
    final cells = <(String, String, VoidCallback?)>[
      ('Fold', 'dock-fold', villain && toCall > 0 ? () => flow.seatAct(p, ActionType.fold) : null),
      (
        toCall > 0 ? 'Call ${toCall.toStringAsFixed(1)}' : 'Check / Call',
        'dock-passive',
        villain ? () => flow.seatAct(p, toCall > 0 ? ActionType.call : ActionType.check) : null,
      ),
      ('1bb / Min 🐟', 'dock-min', sized(fsm.currentBet == 0 ? 1.0 : fsm.minRaiseTo)),
      ('Bet/Raise 33%', 'dock-33', sized(potPct(.33))),
      ('Bet/Raise 75%', 'dock-75', sized(potPct(.75))),
      (barAllIn ? 'All-In' : 'Barra ${scrub.toStringAsFixed(1)}bb', 'dock-bar', sized(scrub)),
    ];
    Widget cell((String, String, VoidCallback?) c) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: SizedBox(
          height: rowHeight,
          child: FilledButton(
            key: ValueKey(c.$2),
            style: FilledButton.styleFrom(
              backgroundColor: Obsidian.buttonDefault,
              foregroundColor: Obsidian.buttonDefaultText,
              disabledBackgroundColor: Obsidian.surfacePanel,
              disabledForegroundColor: Obsidian.textMuted,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Obsidian.borderFine),
              ),
            ),
            onPressed: c.$3 == null ? null : () => act(c.$3!),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(c.$1, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
        ),
      ),
    );
    return Container(
      key: const ValueKey('action-dock'),
      color: Obsidian.surfacePanel,
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BetSizeScrubberBar(value: scrub, max: maxFor(fsm), potBb: fsm.street == Street.preflop ? null : fsm.pot, onChanged: onScrub),
          Row(children: [for (final c in cells.take(3)) cell(c)]),
          Row(children: [for (final c in cells.skip(3)) cell(c)]),
        ],
      ),
    );
  }
}
