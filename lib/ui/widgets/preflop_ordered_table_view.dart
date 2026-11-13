import 'package:flutter/material.dart' hide Card;

import '../../application/hand_flow_fsm.dart';
import '../../application/linear_hand_flow.dart';
import '../../core/models/game_state.dart';
import '../theme/obsidian_theme.dart';
import 'bet_size_scrubber_bar.dart';
import 'smarthud_quick_sheet.dart';
import 'wizard_step_views.dart';

/// Tabla Preflop ordenada UTG ➔ BB (Fase 16.0): filas sin botón Fold obligatorio (no tocar = Fold),
/// botones por nivel de apuesta (Unopened / OR / 3-Bet / 4-Bet / 5-Bet+) y re-apertura del turno de Hero.
class PreflopOrderedTableView extends StatefulWidget {
  const PreflopOrderedTableView({super.key, required this.flow, required this.act});
  final LinearHandFlow flow;
  final void Function(VoidCallback f) act;

  /// Nº de subidas preflop (OR = 1, 3-Bet = 2, 4-Bet = 3, 5-Bet = 4).
  static int raises(HandFlowFSM fsm) => fsm.actions.where((a) => a.street == Street.preflop && a.isAggressive).length;

  @override
  State<PreflopOrderedTableView> createState() => _PreflopOrderedTableViewState();
}

class _PreflopOrderedTableViewState extends State<PreflopOrderedTableView> with WizardKit {
  LinearHandFlow get flow => widget.flow;
  HandFlowFSM get fsm => flow.fsm;
  double? _resize;
  int _resizeIdx = -1;

  /// Botones contextuales del nivel de apuesta para [p]; [apply] ejecuta (villano: seatAct, Hero manual: heroManual).
  List<Widget> _levelButtons(Position p, void Function(ActionType t, double amt) apply) {
    final s = fsm.seats[p]!;
    final n = p.name;
    final toCall = fsm.currentBet - s.committed;
    final cap = s.committed + s.stack;
    final r = PreflopOrderedTableView.raises(fsm);
    final can = fsm.canRaise(p);
    final out = <Widget>[];
    void b(String label, String code, ActionType t, [double amt = 0]) =>
        out.add(chip(label, 'act-$n-$code', false, () => widget.act(() => apply(t, amt)), h: 40));
    void raise(String label, String code, double to) {
      if (!can) return;
      final x = BetSizeScrubberBar.snap(to < fsm.minRaiseTo ? fsm.minRaiseTo : to);
      if (x >= cap - 1e-9) return;
      b('$label ${x.toStringAsFixed(1)}', code, ActionType.raise, x);
    }

    final blind = p == Position.sb || p == Position.bb;
    switch (r) {
      case 0:
        final limps = fsm.actions.where((a) => a.street == Street.preflop && a.type == ActionType.call).length;
        toCall > 0 ? b('Limp', 'limp', ActionType.call) : b('Check', 'check', ActionType.check);
        raise('OR', 'or', LinearHandFlow.openSize(p) + limps);
        b('All-In', 'allin', ActionType.allIn);
      case 1:
        toCall > 0 ? b('Call ${toCall.toStringAsFixed(1)}', 'call', ActionType.call) : b('Check', 'check', ActionType.check);
        raise('3-Bet', '3bet', fsm.currentBet * (blind ? 4 : 3));
        raise('Min-3B 🐟', 'min3b', fsm.minRaiseTo);
        b('All-In', 'allin', ActionType.allIn);
      case 2:
        if (toCall > 0) b('Fold', 'fold', ActionType.fold);
        toCall > 0 ? b('Call ${toCall.toStringAsFixed(1)}', 'call', ActionType.call) : b('Check', 'check', ActionType.check);
        raise('4-Bet', '4bet', fsm.currentBet * 2.4);
        b('All-In', 'allin', ActionType.allIn);
      case 3:
        if (toCall > 0) b('Fold', 'fold', ActionType.fold);
        if (toCall > 0) b('Call ${toCall.toStringAsFixed(1)}', 'call', ActionType.call);
        if (can) b('5-Bet / All-In', '5bet', ActionType.allIn);
      default:
        if (toCall > 0) b('Fold', 'fold', ActionType.fold);
        if (toCall > 0) b('Call All-In ${toCall.toStringAsFixed(1)}', 'call', ActionType.call);
    }
    return out;
  }

  String _status(Position p) {
    final last = fsm.actions.reversed.where((a) => a.street == Street.preflop && a.actor == p).firstOrNull;
    final s = fsm.seats[p]!;
    if (last == null) return s.committed > 0 ? 'ciega ${s.committed.toStringAsFixed(1)}' : '';
    var lvl = 0;
    for (final a in fsm.actions) {
      if (a.street != Street.preflop) continue;
      if (a.isAggressive) lvl++;
      if (identical(a, last)) break;
    }
    final name = switch (last.type) {
      ActionType.fold => 'Fold',
      ActionType.check => 'Check',
      ActionType.call => lvl == 0 ? 'Limp' : 'Call ${last.amountBb.toStringAsFixed(1)}',
      ActionType.allIn => 'All-In ${last.amountBb.toStringAsFixed(1)}',
      _ =>
        '${switch (lvl) {
          1 => 'OR',
          2 => '3-Bet',
          3 => '4-Bet',
          _ => '5-Bet',
        }} ${last.amountBb.toStringAsFixed(1)}',
    };
    final auto = p == fsm.heroPosition && !flow.manualMode && flow.lastHeroStreet == Street.preflop ? ' (Auto)' : '';
    return '$name$auto';
  }

  /// Última subida de un villano que puede re-ajustarse (solo la sigue, si acaso, el auto-commit de Hero).
  int _resizableIdx() {
    final a = fsm.actions;
    for (var i = a.length - 1; i >= 0; i--) {
      if (a[i].street != Street.preflop) return -1;
      if (a[i].actor == fsm.heroPosition) continue;
      if (a[i].type == ActionType.fold) return -1;
      return a[i].type == ActionType.raise ? i : -1;
    }
    return -1;
  }

  void _applyResize(int idx, double to) {
    final p = fsm.actions[idx].actor;
    while (fsm.actions.length > idx && fsm.canUndo) {
      fsm.undo();
    }
    flow.manualMode = false;
    raiseOrShove(flow, p, to);
  }

  Widget _row(Position p, int resizeIdx) {
    final hero = p == fsm.heroPosition;
    final cur = fsm.currentActorSeat == p;
    final tag = hero ? null : (fsm.hudOf(p)?.tag.name ?? fsm.seats[p]!.profile.name);
    final children = <Widget>[
      Row(
        children: [
          Text(
            hero ? '★ TÚ (${p.name.toUpperCase()})' : p.name.toUpperCase(),
            style: TextStyle(color: Obsidian.textPrimary, fontWeight: FontWeight.w800, fontSize: hero ? 15 : 14),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _status(p),
              key: ValueKey('status-${p.name}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Obsidian.num(size: 13, color: Obsidian.textSecondary, weight: FontWeight.w700),
            ),
          ),
          if (tag != null)
            InkWell(
              key: ValueKey('hud-${p.name}'),
              onTap: () => SmartHudQuickSheet.show(context, fsm, p),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(
                  '[$tag ▾]',
                  style: const TextStyle(color: Obsidian.textMuted, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    ];
    final buttons = <Widget>[];
    if (hero) {
      if (flow.manualMode && cur) {
        buttons.addAll(_levelButtons(p, (t, amt) => flow.heroManual(t, amount: amt)));
      } else if (fsm.pendingToAct.contains(p) && fsm.canTap(p) && !cur) {
        buttons.add(
          chip(
            PreflopOrderedTableView.raises(fsm) == 0 ? '★ Mi turno ➔ (nadie más entró)' : '★ Mi turno ➔ (resto sin tocar = Fold)',
            'hero-go',
            true,
            () => widget.act(flow.heroGo),
            h: 46,
          ),
        );
      }
    } else if (fsm.canTap(p)) {
      buttons.addAll(_levelButtons(p, (t, amt) => flow.seatAct(p, t, amount: amt)));
    }
    if (buttons.isNotEmpty) {
      children.add(Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 5, runSpacing: 5, children: buttons)));
    }
    if (!hero && resizeIdx >= 0 && fsm.actions[resizeIdx].actor == p) {
      if (_resizeIdx != resizeIdx) {
        _resizeIdx = resizeIdx;
        _resize = fsm.actions[resizeIdx].amountBb;
      }
      children.add(
        slider('Ajustar tamaño de ${p.name.toUpperCase()}: ${_resize!.toStringAsFixed(1)} bb', _resize!, capOf(fsm, p), (v) => setState(() => _resize = v)),
      );
      if ((_resize! - fsm.actions[resizeIdx].amountBb).abs() > 1e-9) {
        children.add(
          chip('Aplicar ${_resize!.toStringAsFixed(1)} bb', 'resize-${p.name}', true, () => widget.act(() => _applyResize(resizeIdx, _resize!)), h: 40),
        );
      }
    }
    return Container(
      key: ValueKey('row-${p.name}'),
      margin: const EdgeInsets.only(top: 5),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
      decoration: BoxDecoration(
        color: cur || (hero && fsm.pendingToAct.contains(p)) ? Obsidian.buttonDefault : Obsidian.surfacePanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cur ? Obsidian.buttonActive : (hero ? Obsidian.textSecondary : Obsidian.borderFine), width: cur ? 2 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  @override
  Widget build(BuildContext context) {
    final seats = [
      for (final p in HandFlowFSM.preflopOrder)
        if (fsm.seats[p]?.alive ?? false) p,
    ];
    final ri = _resizableIdx();
    final heroPending = fsm.pendingToAct.contains(fsm.heroPosition);
    final heroActed = WizardSteps.heroActed(fsm, Street.preflop);
    final stay = [
      for (final p in seats)
        if (fsm.seats[p]!.allIn || fsm.seats[p]!.committed >= fsm.currentBet - 1e-9) p,
    ].length;
    return Column(
      key: const ValueKey('preflop-table'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            heroActed && !heroPending
                ? 'Toca solo a quien pagó o resubió; el resto se asume Fold'
                : 'Toca la acción de quien entró antes que tú; los que no toques foldearon',
            style: const TextStyle(color: Obsidian.textSecondary, fontSize: 12),
          ),
        ),
        for (final p in seats) _row(p, ri),
        if (heroActed && !heroPending && fsm.currentActorSeat != null && fsm.currentActorSeat != fsm.heroPosition) ...[
          const SizedBox(height: 8),
          big(stay <= 1 ? 'Todos Foldearon (Ganaste el bote)' : '✓ Avanzar al Flop ($stay Jugadores) ➔', 'advance-flop', () => widget.act(flow.resolveStreet)),
        ],
      ],
    );
  }
}
