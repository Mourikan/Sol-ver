import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/hand_flow_fsm.dart';
import '../../core/models/game_state.dart';
import '../theme.dart';

/// Solo acciones legales del jugador en turno (preflop / postflop).
class ActionPad extends StatelessWidget {
  const ActionPad({super.key, required this.fsm, required this.onError});
  final HandFlowFSM fsm;
  final ValueChanged<String> onError;

  void _do(ActionType t, [double amount = 0]) {
    final p = fsm.currentActor;
    if (p == null) return;
    try {
      fsm.act(p, t, amountBb: amount);
    } on IllegalAction catch (e) {
      onError(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = fsm.currentActor;
    if (p == null) return const SizedBox.shrink();
    final legal = fsm.legalActions();
    final seat = fsm.seats[p]!;
    final toCall = fsm.currentBet - seat.committed;
    final maxTo = seat.committed + seat.stack;
    final buttons = <Widget>[];
    void add(String label, Color c, VoidCallback f, {String? key}) => buttons.add(_Btn(label, c, f, key: key == null ? null : ValueKey(key)));

    if (legal.contains(ActionType.fold)) add('Fold', AppColors.danger, () => _do(ActionType.fold), key: 'fold');
    if (legal.contains(ActionType.check)) add('Check', AppColors.muted, () => _do(ActionType.check), key: 'check');
    if (legal.contains(ActionType.call)) {
      add('${fsm.street == Street.preflop && fsm.currentBet <= 1 ? 'Limp' : 'Call'} ${toCall.toStringAsFixed(1)}', AppColors.call,
          () => _do(ActionType.call), key: 'call');
    }
    double clamp(double to) => math.min(math.max(to, fsm.minRaiseTo), maxTo);
    if (legal.contains(ActionType.raise) || legal.contains(ActionType.bet)) {
      final t = fsm.currentBet == 0 ? ActionType.bet : ActionType.raise;
      if (fsm.street == Street.preflop) {
        final limpers = fsm.actions.where((a) => a.street == Street.preflop && a.type == ActionType.call).length;
        if (fsm.currentBet <= 1) {
          add(limpers > 0 ? 'Iso ${(3.5 + limpers).toStringAsFixed(1)}' : 'Open 2.5', AppColors.raise,
              () => _do(ActionType.raise, clamp(limpers > 0 ? 3.5 + limpers : (p == Position.sb ? 3.0 : 2.5))), key: 'open');
        } else {
          final callers = fsm.actions.where((a) => a.street == Street.preflop && a.type == ActionType.call && a.amountBb >= fsm.currentBet).length;
          final ip = p != Position.sb && p != Position.bb;
          final geo = fsm.currentBet * (ip ? 3.0 : 4.0) + fsm.currentBet * callers;
          add('${callers > 0 ? 'Squeeze' : '3-Bet'} ${geo.toStringAsFixed(1)}', AppColors.raise, () => _do(t, clamp(geo)), key: 'geo');
          add('3x', AppColors.raise, () => _do(t, clamp(fsm.currentBet * 3)));
          add('4x', AppColors.raise, () => _do(t, clamp(fsm.currentBet * 4)));
        }
      } else {
        if (fsm.currentBet == 0) add('Min-Donk 1bb', AppColors.raise, () => _do(t, clamp(1)));
        final potAfterCall = fsm.pot + toCall;
        for (final pct in [25, 33, 50, 75, 100, 125]) {
          add(pct == 125 ? '125% OB' : '$pct%', AppColors.raise, () => _do(t, clamp(fsm.currentBet + potAfterCall * pct / 100)), key: 'bet$pct');
        }
      }
    }
    add('All-in ${maxTo.toStringAsFixed(0)}', AppColors.danger, () => _do(ActionType.allIn), key: 'allin');

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Turno: ${p.name.toUpperCase()}${p == fsm.heroPosition ? ' (HERO)' : ''}',
              style: const TextStyle(color: AppColors.turn, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, children: buttons),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn(this.label, this.color, this.onTap, {super.key});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 44,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color, width: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
          onPressed: onTap,
          child: Text(label),
        ),
      );
}
