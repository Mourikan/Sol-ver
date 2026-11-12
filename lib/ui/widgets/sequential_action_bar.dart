import 'package:flutter/material.dart';

import '../../application/hand_flow_fsm.dart';
import '../../core/models/game_state.dart';
import '../theme.dart';
import 'decision_and_why_panel.dart';

/// Control acción por acción: estado del turno, botones contextuales (sin apuesta / enfrentando apuesta), stepper de
/// tamaño libre, aplicar jugada del solver, deshacer y nueva mano.
class SequentialActionBar extends StatefulWidget {
  const SequentialActionBar({super.key, required this.fsm, required this.act});
  final HandFlowFSM fsm;
  final void Function(VoidCallback) act;

  @override
  State<SequentialActionBar> createState() => _SequentialActionBarState();
}

class _SequentialActionBarState extends State<SequentialActionBar> {
  double? custom;

  HandFlowFSM get fsm => widget.fsm;

  double _clampTo(double x, SeatState s) {
    final allIn = s.committed + s.stack;
    if (x >= allIn) return allIn;
    return x < fsm.minRaiseTo ? fsm.minRaiseTo : x;
  }

  void _aggr(Position p, double to) {
    final s = fsm.seats[p]!;
    final allIn = s.committed + s.stack;
    widget.act(() => fsm.act(p, to >= allIn ? ActionType.allIn : (fsm.currentBet == 0 ? ActionType.bet : ActionType.raise), amountBb: to));
  }

  @override
  Widget build(BuildContext context) {
    final p = fsm.currentActor;
    final heroTurn = p != null && p == fsm.heroPosition;
    final status = fsm.phase == HandPhase.setup
        ? 'SETUP — toca el asiento de Hero y elige 2 cartas'
        : fsm.awaitingCards
            ? 'CARTAS — introduce ${fsm.cardsNeeded} carta(s) de la calle'
            : p == null
                ? 'MANO TERMINADA'
                : heroTurn
                    ? '🔥 TU TURNO (${p.name.toUpperCase()}) — Decisión lista'
                    : 'TURNO DE: ${p.name.toUpperCase()} (Villano) — Esperando acción...';
    final buttons = <Widget>[];
    if (p != null && !fsm.awaitingCards) {
      final s = fsm.seats[p]!;
      final toCall = fsm.currentBet - s.committed;
      final pre = fsm.street == Street.preflop;
      if (toCall <= 0) {
        buttons.add(_B('Check', AppColors.amber, () => widget.act(() => fsm.act(p, ActionType.check)), 'act-check'));
        if (pre) {
          for (final (l, k, x) in [('Raise 2.5x', 'act-r25', 2.5), ('Raise 3.2x', 'act-r32', 3.2)]) {
            buttons.add(_B(l, AppColors.emerald, () => _aggr(p, _clampTo(fsm.currentBet * x, s)), k));
          }
        } else {
          for (final (l, k, x) in [('Bet 25%', 'act-bet25', .25), ('Bet 33%', 'act-bet33', .33), ('Bet 50%', 'act-bet50', .5), ('Bet 75%', 'act-bet75', .75), ('Overbet 125%', 'act-ob125', 1.25)]) {
            buttons.add(_B(l, AppColors.emerald, () => _aggr(p, _clampTo(fsm.pot * x, s)), k));
          }
        }
      } else {
        buttons
          ..add(_B('Fold', AppColors.crimson, () => widget.act(() => fsm.act(p, ActionType.fold)), 'act-fold'))
          ..add(_B('Call ${(toCall < s.stack ? toCall : s.stack).toStringAsFixed(1)}bb', AppColors.cyan, () => widget.act(() => fsm.act(p, ActionType.call)), 'act-call'));
        if (s.stack > toCall) {
          for (final (l, k, x) in [('Raise 2.5x', 'act-r25', 2.5), ('Raise 3.2x', 'act-r32', 3.2)]) {
            buttons.add(_B(l, AppColors.emerald, () => _aggr(p, _clampTo(fsm.currentBet * x, s)), k));
          }
        }
      }
      buttons.add(_B(toCall > 0 ? '4-Bet / All-In' : 'All-In', const Color(0xFFF97316), () => widget.act(() => fsm.act(p, ActionType.allIn)), 'act-allin'));
    }
    final s = p == null ? null : fsm.seats[p];
    final val = s == null ? 0.0 : _clampTo(custom ?? fsm.minRaiseTo, s);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
      child: Column(children: [
        SizedBox(
          height: 18,
          child: FittedBox(
            child: Text(status, key: const ValueKey('turn-status'),
                style: TextStyle(color: heroTurn ? AppColors.emerald : AppColors.text, fontWeight: FontWeight.w900, fontSize: 13)),
          ),
        ),
        Expanded(child: Row(children: [for (final b in buttons.take(4)) Expanded(child: b)])),
        Expanded(child: Row(children: [for (final b in buttons.skip(4)) Expanded(child: b)])),
        Expanded(
          child: Row(children: [
            if (s != null && !fsm.awaitingCards) ...[
              SizedBox(width: 34, child: _B('−', AppColors.muted, () => setState(() => custom = val - 0.5), 'act-custom-minus')),
              Expanded(flex: 3, child: _B('${fsm.currentBet == 0 ? 'Bet' : 'Raise'} ${val.toStringAsFixed(1)}', AppColors.emerald, () => _aggr(p!, val), 'act-custom-go')),
              SizedBox(width: 34, child: _B('+', AppColors.muted, () => setState(() => custom = val + 0.5), 'act-custom-plus')),
            ] else
              const Spacer(flex: 3),
            Expanded(flex: 2, child: _B('↺ Deshacer', AppColors.muted, fsm.canUndo ? () => widget.act(fsm.undo) : null, 'undo')),
            Expanded(
                flex: 2,
                child: _B('Nueva Mano', AppColors.cyan, () => widget.act(() => fsm.nextHand()), 'new-hand',
                    onLong: () => widget.act(() => fsm.nextHand(rotateButton: true)))),
          ]),
        ),
        if (heroTurn)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('execute-optimal'),
                  style: FilledButton.styleFrom(
                    backgroundColor: fsm.activeRecommendation == null ? AppColors.surfaceHi : actionColor(fsm.activeRecommendation!.action),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: fsm.activeRecommendation == null ? null : () => widget.act(fsm.executeRecommendation),
                  child: const FittedBox(child: Text('⚡ Aplicar Jugada del Solver', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900))),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _B extends StatelessWidget {
  const _B(this.label, this.color, this.onTap, this.k, {this.onLong});
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final VoidCallback? onLong;
  final String k;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: onTap == null ? AppColors.surface : color.withValues(alpha: .18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AppColors.border)),
          child: InkWell(
            key: ValueKey(k),
            onTap: onTap,
            onLongPress: onLong,
            borderRadius: BorderRadius.circular(8),
            child: Center(
              child: FittedBox(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(label, style: TextStyle(color: onTap == null ? AppColors.muted : color, fontWeight: FontWeight.w800, fontSize: 13)),
                ),
              ),
            ),
          ),
        ),
      );
}
