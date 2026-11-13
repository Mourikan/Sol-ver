import 'package:flutter/material.dart' hide Card;

import '../../application/hand_flow_fsm.dart';
import '../../application/linear_hand_flow.dart';
import '../../core/models/game_state.dart';
import '../theme.dart';
import '../theme/obsidian_theme.dart';
import 'smarthud_quick_sheet.dart';

/// Positional_Sequential_Ledger (Fase 12.0): filas de asientos VIVOS en el orden exacto de la calle.
/// Tocar una fila inferior asume Fold (preflop) de las filas omitidas => desaparecen de la lista.
class PositionalLedgerView extends StatelessWidget {
  const PositionalLedgerView({super.key, required this.flow, required this.act, this.heroManual});
  final LinearHandFlow flow;
  final void Function(VoidCallback f) act;
  final Widget? heroManual;

  HandFlowFSM get fsm => flow.fsm;

  static String _short(PlayerAction a) => switch (a.type) {
    ActionType.fold => 'Fold',
    ActionType.check => 'Check',
    ActionType.call => 'Call ${a.amountBb.toStringAsFixed(1)}',
    ActionType.bet => 'Bet ${a.amountBb.toStringAsFixed(1)}',
    ActionType.raise => 'Raise ${a.amountBb.toStringAsFixed(1)}',
    ActionType.allIn => 'All-In ${a.amountBb.toStringAsFixed(1)}',
  };

  PlayerAction? _last(Position p) => fsm.actions.reversed.where((a) => a.street == fsm.street && a.actor == p).firstOrNull;

  Widget _b(String label, Color c, String key, VoidCallback f) => SizedBox(
    height: 36,
    child: FilledButton(
      key: ValueKey(key),
      style: FilledButton.styleFrom(
        backgroundColor: c,
        foregroundColor: Colors.white,
        minimumSize: const Size(44, 36),
        padding: const EdgeInsets.symmetric(horizontal: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: () => act(f),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
    ),
  );

  /// Botones legales de la fila según el estado de la calle.
  List<Widget> _buttons(Position p) {
    final s = fsm.seats[p]!;
    final n = p.name;
    final toCall = fsm.currentBet - s.committed;
    final cap = s.committed + s.stack;
    final out = <Widget>[];
    void put(String label, Color c, String code, ActionType t, [double amt = 0]) =>
        out.add(_b(label, c, 'act-$n-$code', () => flow.seatAct(p, t, amount: amt)));
    void raise(String label, String code, double to) {
      if (!fsm.canRaise(p)) return;
      final x = to < fsm.minRaiseTo ? fsm.minRaiseTo : to;
      if (x >= cap - 1e-9) return;
      put(label, Obsidian.emeraldRaise, code, fsm.currentBet == 0 ? ActionType.bet : ActionType.raise, x);
    }

    final allIn = fsm.canRaise(p) || s.stack <= toCall;
    if (fsm.street == Street.preflop) {
      final raises = fsm.actions.where((a) => a.street == Street.preflop && a.isAggressive).length;
      final acted = fsm.actions.any((a) => a.street == Street.preflop && a.actor == p);
      if (raises == 0) {
        if (toCall > 0) {
          put('Limp 1bb', Obsidian.cyanCall, 'limp', ActionType.call);
        } else {
          put('Check', Obsidian.amberCheck, 'check', ActionType.check);
        }
        final limps = fsm.actions.where((a) => a.street == Street.preflop && a.type == ActionType.call).length;
        final isoTo = limps > 0 ? 3.5 + limps : 2.5;
        raise(limps > 0 ? 'Iso ${isoTo.toStringAsFixed(1)}bb' : 'Open 2.5bb', 'open25', isoTo);
        if (limps == 0) raise('Open 3bb+', 'open3', 3.0);
      } else {
        if (acted && toCall > 0) put('Fold', Obsidian.crimsonFold, 'fold', ActionType.fold);
        if (toCall > 0) put('Call ${toCall.toStringAsFixed(1)}bb', Obsidian.cyanCall, 'call', ActionType.call);
        if (toCall == 0) put('Check', Obsidian.amberCheck, 'check', ActionType.check);
        final lbl = switch (raises) {
          1 => '3-Bet',
          2 => '4-Bet',
          _ => '${raises + 2}-Bet',
        };
        final mult = raises == 1 ? ((p == Position.sb || p == Position.bb) ? 4.0 : 3.0) : 2.3;
        raise(lbl, 'raise', fsm.currentBet * mult);
        raise('Min-${raises == 1 ? '3B' : 'R'} 🐟', 'minr', fsm.minRaiseTo);
      }
    } else if (toCall <= 0) {
      put('Check', Obsidian.amberCheck, 'check', ActionType.check);
      for (final (l, x) in [('33', .33), ('50', .5), ('75', .75)]) {
        raise('Bet $l%', 'b$l', fsm.pot * x);
      }
      raise('1bb 🐟', 'b1bb', 1);
    } else {
      put('Fold ❌', Obsidian.crimsonFold, 'fold', ActionType.fold);
      put('Call ${toCall.toStringAsFixed(1)}bb', Obsidian.cyanCall, 'call', ActionType.call);
      raise('Raise 3x', 'r3x', fsm.currentBet * 3);
      raise('Min-Raise 🐟', 'minr', fsm.minRaiseTo);
    }
    if (allIn) put('All-In', const Color(0xFF7C3AED), 'allin', ActionType.allIn);
    return out;
  }

  Widget _row(BuildContext context, Position p) {
    final hero = p == fsm.heroPosition;
    final cur = fsm.currentActor == p;
    final last = _last(p);
    final tappable = fsm.canTap(p);
    final tag = fsm.hudOf(p)?.tag.name ?? fsm.seats[p]!.profile.name;
    final children = <Widget>[
      Row(
        children: [
          Text(
            hero ? '⭐ ${p.name.toUpperCase()} (HERO)' : p.name.toUpperCase(),
            style: TextStyle(color: hero ? Obsidian.emeraldRaise : AppColors.text, fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${fsm.seats[p]!.committed.toStringAsFixed(1)}bb${last == null ? '' : ' · ${_short(last)}'}',
              key: ValueKey('status-${p.name}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
          if (!hero)
            InkWell(
              key: ValueKey('hud-${p.name}'),
              onTap: () => SmartHudQuickSheet.show(context, fsm, p),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  '[$tag ▾]',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    ];
    if (hero) {
      final pending = fsm.pendingToAct.contains(p);
      if (flow.manualMode && cur && heroManual != null) {
        children.add(heroManual!);
      } else if (pending && tappable) {
        children.add(_b('⭐ TU TURNO (HERO - ${p.name.toUpperCase()})', Obsidian.emeraldRaise, 'hero-row-go', flow.heroGo));
      } else if (last != null && !flow.manualMode && fsm.canUndo) {
        children.add(
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('override'),
              onPressed: () => act(flow.overrideHero),
              child: const Text('Cambiar mi acción', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ),
          ),
        );
      }
    } else if (tappable) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(spacing: 4, runSpacing: 4, children: _buttons(p)),
        ),
      );
    }
    return Container(
      key: ValueKey('row-${p.name}'),
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: cur ? Obsidian.amberCheck.withValues(alpha: .12) : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cur ? Obsidian.amberCheck : (hero ? Obsidian.emeraldRaise : AppColors.border)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  @override
  Widget build(BuildContext context) {
    final seats = fsm.activeSeats;
    final heroPending = fsm.pendingToAct.contains(fsm.heroPosition);
    final showResolve = fsm.currentActor != null && fsm.currentActor != fsm.heroPosition && !heroPending;
    final street = switch (fsm.street) {
      Street.preflop => 'PREFLOP',
      Street.flop => 'FLOP',
      Street.turn => 'TURN',
      Street.river => 'RIVER',
    };
    return Column(
      key: const ValueKey('ledger'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '$street · TURNOS (${seats.length} vivos)',
            style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        for (final p in seats) _row(context, p),
        if (showResolve)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _b(
              fsm.street == Street.preflop ? '✓ Resolver Preflop ➔ Poner Flop' : '✓ Resto foldea / pasa ➔ Siguiente calle',
              AppColors.surfaceHi,
              'resolve-street',
              flow.resolveStreet,
            ),
          ),
      ],
    );
  }
}
