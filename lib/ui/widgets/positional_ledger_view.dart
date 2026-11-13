import 'package:flutter/material.dart' hide Card;

import '../../application/hand_flow_fsm.dart';
import '../../application/linear_hand_flow.dart';
import '../../core/models/decision_output.dart';
import '../../core/models/game_state.dart';
import '../theme.dart';
import '../theme/obsidian_theme.dart';
import 'smarthud_quick_sheet.dart';

/// [MIN_TAP_AUTO_CURSOR_UX] (Fase 12.5): filas de asientos vivos en orden de la calle con cursor autónomo.
/// La fila del cursor muestra botones grandes + Drag-Scrubber; en preflop las filas posteriores permiten salto en 1 toque.
/// Sin botones de confirmación: la calle se cierra sola. Único atajo: [Todos Foldearon] tras la acción de Hero.
class PositionalLedgerView extends StatefulWidget {
  const PositionalLedgerView({super.key, required this.flow, required this.act, this.heroManual});
  final LinearHandFlow flow;
  final void Function(VoidCallback f) act;
  final Widget? heroManual;

  static const steel = Color(0xFF2563EB);

  @override
  State<PositionalLedgerView> createState() => _PositionalLedgerViewState();
}

class _PositionalLedgerViewState extends State<PositionalLedgerView> {
  LinearHandFlow get flow => widget.flow;
  HandFlowFSM get fsm => flow.fsm;
  double? _scrub;
  Position? _scrubSeat;

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

  Widget _b(String label, Color c, String key, VoidCallback f, {bool big = false}) => SizedBox(
    height: big ? 44 : 34,
    child: FilledButton(
      key: ValueKey(key),
      style: FilledButton.styleFrom(
        backgroundColor: c,
        foregroundColor: Colors.white,
        minimumSize: Size(big ? 48 : 40, big ? 44 : 34),
        padding: EdgeInsets.symmetric(horizontal: big ? 11 : 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: () => widget.act(f),
      child: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: big ? 13 : 12),
      ),
    ),
  );

  /// Botones legales; [big] = fila del cursor (set completo), si no versión compacta de salto preflop.
  List<Widget> _buttons(Position p, {required bool big}) {
    final s = fsm.seats[p]!;
    final n = p.name;
    final toCall = fsm.currentBet - s.committed;
    final cap = s.committed + s.stack;
    final out = <Widget>[];
    void put(String label, Color c, String code, ActionType t, [double amt = 0]) =>
        out.add(_b(label, c, 'act-$n-$code', () => flow.seatAct(p, t, amount: amt), big: big));
    void raise(String label, String code, double to) {
      if (!fsm.canRaise(p)) return;
      final x = to < fsm.minRaiseTo ? fsm.minRaiseTo : to;
      if (x >= cap - 1e-9) return;
      put(label, Obsidian.emeraldRaise, code, fsm.currentBet == 0 ? ActionType.bet : ActionType.raise, (x * 10).roundToDouble() / 10);
    }

    if (toCall > 0) put('Fold ❌', Obsidian.crimsonFold, 'fold', ActionType.fold);
    if (fsm.street == Street.preflop) {
      final raises = fsm.actions.where((a) => a.street == Street.preflop && a.isAggressive).length;
      if (raises == 0) {
        final limps = fsm.actions.where((a) => a.street == Street.preflop && a.type == ActionType.call).length;
        if (toCall > 0) {
          put('Limp 1bb', Obsidian.cyanCall, 'limp', ActionType.call);
        } else {
          put('Check', Obsidian.amberCheck, 'check', ActionType.check);
        }
        final isoTo = limps > 0 ? 3.5 + limps : 2.5;
        raise(limps > 0 ? 'Iso ${isoTo.toStringAsFixed(1)}bb' : 'Open 2.5bb', 'open25', isoTo);
        if (big && limps == 0) raise('Open 3bb', 'open3', 3.0);
        if (big) raise('Min 🐟', 'minr', fsm.minRaiseTo);
      } else {
        if (toCall > 0) put('Call ${toCall.toStringAsFixed(1)}bb', Obsidian.cyanCall, 'call', ActionType.call);
        if (toCall <= 0) put('Check', Obsidian.amberCheck, 'check', ActionType.check);
        final lbl = switch (raises) {
          1 => '3-Bet',
          2 => '4-Bet',
          _ => '${raises + 2}-Bet',
        };
        final mult = raises == 1 ? ((p == Position.sb || p == Position.bb) ? 4.0 : 3.0) : 2.3;
        final to = fsm.currentBet * mult;
        raise('$lbl ${((to * 10).roundToDouble() / 10).toStringAsFixed(1)}bb', 'raise', to);
        if (big) raise('Min-Raise 🐟', 'minr', fsm.minRaiseTo);
      }
    } else if (toCall <= 0) {
      put('Check', Obsidian.amberCheck, 'check', ActionType.check);
      for (final (l, x) in [('33', .33), ('50', .5), ('75', .75)]) {
        raise('Bet $l%', 'b$l', fsm.pot * x);
      }
      raise('1bb 🐟', 'b1bb', 1);
    } else {
      put('Call ${toCall.toStringAsFixed(1)}bb', Obsidian.cyanCall, 'call', ActionType.call);
      raise('Raise 3x', 'r3x', fsm.currentBet * 3);
      raise('Min-Raise 🐟', 'minr', fsm.minRaiseTo);
    }
    if (big && (fsm.canRaise(p) || s.stack <= toCall)) put('All-In', const Color(0xFF7C3AED), 'allin', ActionType.allIn);
    return out;
  }

  /// Drag-Scrubber: ajusta bb exactas de la apuesta/subida del asiento en turno.
  Widget _scrubber(Position p) {
    final s = fsm.seats[p]!;
    final lo = fsm.minRaiseTo, hi = s.committed + s.stack;
    if (!fsm.canRaise(p) || hi <= lo + .1) return const SizedBox.shrink();
    if (_scrubSeat != p || _scrub == null || _scrub! < lo || _scrub! > hi) {
      _scrubSeat = p;
      _scrub = lo;
    }
    final v = _scrub!;
    return Row(
      children: [
        Expanded(
          child: Slider(
            key: ValueKey('scrub-${p.name}'),
            value: v,
            min: lo,
            max: hi,
            activeColor: PositionalLedgerView.steel,
            onChanged: (x) => setState(() => _scrub = (x * 2).roundToDouble() / 2 < lo ? lo : (x * 2).roundToDouble() / 2),
          ),
        ),
        _b(
          '${fsm.currentBet == 0 ? 'Bet' : 'Raise'} ${v.toStringAsFixed(1)}',
          Obsidian.emeraldRaise,
          'act-${p.name}-scrub',
          () => flow.seatAct(p, v >= hi - 1e-9 ? ActionType.allIn : (fsm.currentBet == 0 ? ActionType.bet : ActionType.raise), amount: v),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, Position p) {
    final hero = p == fsm.heroPosition;
    final cur = fsm.currentActorSeat == p;
    final last = _last(p);
    final tappable = fsm.canTap(p);
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
    if (hero) {
      final pending = fsm.pendingToAct.contains(p);
      if (flow.manualMode && cur && widget.heroManual != null) {
        children.add(widget.heroManual!);
      } else if (pending && tappable) {
        children.add(_b('⭐ TU TURNO (HERO - ${p.name.toUpperCase()})', Obsidian.emeraldRaise, 'hero-row-go', flow.heroGo, big: true));
      } else if (last != null && !flow.manualMode && fsm.canUndo) {
        children.add(
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('override'),
              onPressed: () => widget.act(flow.overrideHero),
              child: const Text('Cambiar mi jugada', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ),
          ),
        );
      }
    } else if (cur) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(spacing: 5, runSpacing: 5, children: _buttons(p, big: true)),
        ),
      );
      children.add(_scrubber(p));
    } else if (tappable && fsm.street == Street.preflop) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(spacing: 4, runSpacing: 4, children: _buttons(p, big: false)),
        ),
      );
    }
    return Container(
      key: ValueKey('row-${p.name}'),
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: cur ? PositionalLedgerView.steel.withValues(alpha: .18) : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cur ? PositionalLedgerView.steel : (hero ? Obsidian.emeraldRaise : AppColors.border), width: cur ? 2 : 1),
        boxShadow: cur ? const [BoxShadow(color: Color(0x552563EB), blurRadius: 8, offset: Offset(0, 2))] : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  @override
  Widget build(BuildContext context) {
    final seats = fsm.activeSeats;
    final heroPending = fsm.pendingToAct.contains(fsm.heroPosition);
    final allFold = fsm.currentActorSeat != null && fsm.currentActorSeat != fsm.heroPosition && !heroPending && flow.lastHero != null;
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
        if (allFold)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _b('Todos Foldearon ➔ Cerrar Calle / Fin', AppColors.surfaceHi, 'all-fold', flow.resolveStreet, big: true),
          ),
      ],
    );
  }
}
