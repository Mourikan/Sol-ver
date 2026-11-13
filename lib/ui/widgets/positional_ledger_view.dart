import 'package:flutter/material.dart' hide Card;

import '../../application/hand_flow_fsm.dart';
import '../../application/linear_hand_flow.dart';
import '../../core/models/decision_output.dart';
import '../../core/models/game_state.dart';
import '../theme.dart';
import '../theme/obsidian_theme.dart';
import 'smarthud_quick_sheet.dart';

/// [MIN_TAP_AUTO_CURSOR_UX]: filas de asientos vivos (postflop) en orden de la calle con cursor autónomo resaltado.
/// Las acciones del villano en turno se registran en el dock fijo inferior (FixedActionDock).
class PositionalLedgerView extends StatefulWidget {
  const PositionalLedgerView({super.key, required this.flow, required this.act, this.heroManual});
  final LinearHandFlow flow;
  final void Function(VoidCallback f) act;
  final Widget? heroManual;

  @override
  State<PositionalLedgerView> createState() => _PositionalLedgerViewState();
}

class _PositionalLedgerViewState extends State<PositionalLedgerView> {
  LinearHandFlow get flow => widget.flow;
  HandFlowFSM get fsm => flow.fsm;

  static String _short(PlayerAction a) => switch (a.type) {
    ActionType.fold => 'Fold',
    ActionType.check => 'Check',
    ActionType.call => 'Call ${a.amountBb.toStringAsFixed(1)}',
    ActionType.bet => 'Bet ${a.amountBb.toStringAsFixed(1)}',
    ActionType.raise => 'Raise ${a.amountBb.toStringAsFixed(1)}',
    ActionType.allIn => 'All-In ${a.amountBb.toStringAsFixed(1)}',
  };

  static String heroLabel(DecisionOutput d, Street st) {
    final bb = d.sizing?.bb;
    return switch (d.action) {
      DecisionAction.fold => 'Fold',
      DecisionAction.check => 'Check',
      DecisionAction.call => 'Call',
      DecisionAction.betRaise => '${st == Street.preflop ? 'Raise' : 'Bet/Raise'}${bb == null ? '' : ' ${bb.toStringAsFixed(1)}bb'}',
    };
  }

  PlayerAction? _last(Position p) => fsm.actions.reversed.where((a) => a.street == fsm.street && a.actor == p).firstOrNull;

  Widget _row(BuildContext context, Position p) {
    final hero = p == fsm.heroPosition;
    final cur = fsm.currentActorSeat == p;
    final last = _last(p);
    final tag = fsm.hudOf(p)?.tag.name ?? fsm.seats[p]!.profile.name;
    final heroAuto = hero && last != null && flow.lastHero != null && flow.lastHeroStreet == fsm.street && !flow.manualMode;
    final status = heroAuto
        ? '${heroLabel(flow.lastHero!, fsm.street)} (Auto-Aplicado)'
        : '${fsm.seats[p]!.committed.toStringAsFixed(1)}bb${last == null ? '' : ' · ${_short(last)}'}';
    final children = <Widget>[
      Row(
        children: [
          Flexible(
            flex: 3,
            child: Text(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              cur ? '▶ TURNO DE: ${p.name.toUpperCase()}${hero ? ' (HERO)' : ''}' : (hero ? '★ HERO (${p.name.toUpperCase()})' : p.name.toUpperCase()),
              key: cur ? const ValueKey('cursor-label') : null,
              style: TextStyle(color: cur ? Colors.white : (hero ? Obsidian.emeraldRaise : AppColors.text), fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: Text(
              status,
              key: ValueKey('status-${p.name}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: heroAuto ? Obsidian.emeraldRaise : AppColors.muted,
                fontSize: 12,
                fontWeight: heroAuto ? FontWeight.w700 : FontWeight.w400,
              ),
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
    return Container(
      key: ValueKey('row-${p.name}'),
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: cur ? Obsidian.buttonDefault : Obsidian.surfacePanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cur ? Obsidian.buttonActive : Obsidian.borderFine, width: cur ? 2 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  @override
  Widget build(BuildContext context) {
    final seats = fsm.activeSeats;
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
            '$street · ${seats.length} vivos',
            style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        for (final p in seats) _row(context, p),
      ],
    );
  }
}
