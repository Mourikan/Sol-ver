import 'package:flutter/material.dart' hide Card;

import '../../application/hand_flow_fsm.dart';
import '../../application/linear_hand_flow.dart';
import '../../core/models/decision_output.dart';
import '../../core/models/game_state.dart';
import '../theme/obsidian_theme.dart';
import 'bet_size_scrubber_bar.dart';
import 'smarthud_quick_sheet.dart';
import 'speculative_hero_controller.dart';
import 'wizard_step_views.dart';

/// Tabla Preflop ordenada UTG ➔ BB (Fase 16.0): filas sin botón Fold obligatorio (no tocar = Fold),
/// botones por nivel de apuesta (Unopened / OR / 3-Bet / 4-Bet / 5-Bet+) y re-apertura del turno de Hero.
class PreflopOrderedTableView extends StatefulWidget {
  const PreflopOrderedTableView({super.key, required this.flow, required this.act, this.resizeOnly = false, this.spec});
  final LinearHandFlow flow;

  /// L1: controlador de la auto-aplicación especulativa de Hero (filas en blanco auto-foldeadas siguen tocables).
  final SpeculativeHeroController? spec;

  /// true => solo la barra de re-ajuste de la última subida del villano (p. ej. cuando el Call de Hero cerró la calle).
  final bool resizeOnly;
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

  LevelView _viewNow() => levelViewOf(fsm);

  /// Proyección del nivel tras la jugada recomendada de Hero (para tocar filas posteriores sin [Mi turno]).
  LevelView _viewAfterHero(DecisionOutput d) {
    final v = _viewNow();
    if (d.action != DecisionAction.betRaise || d.sizing == null) return v;
    final to = d.sizing!.bb;
    final inc = to - v.bet > v.minTo - v.bet ? to - v.bet : v.minTo - v.bet;
    return (r: v.r + 1, bet: to, minTo: to + inc, limps: v.limps);
  }

  /// Especificación de botones por nivel: (etiqueta, código, tipo, monto).
  List<(String, String, ActionType, double)> _specs(Position p, LevelView v) {
    final s = fsm.seats[p]!;
    final toCall = v.bet - s.committed;
    final cap = s.committed + s.stack;
    final can = fsm.canRaise(p);
    final out = <(String, String, ActionType, double)>[];
    void b(String label, String code, ActionType t, [double amt = 0]) => out.add((label, code, t, amt));
    void raise(String label, String code, double to) {
      if (!can) return;
      final x = BetSizeScrubberBar.snap(to < v.minTo ? v.minTo : to);
      if (x >= cap - 1e-9) return;
      b('$label ${x.toStringAsFixed(1)}', code, ActionType.raise, x);
    }

    final blind = p == Position.sb || p == Position.bb;
    switch (v.r) {
      case 0:
        toCall > 0 ? b('Limp', 'limp', ActionType.call) : b('Check', 'check', ActionType.check);
        raise('OR', 'or', LinearHandFlow.openSize(p) + v.limps);
        b('All-In', 'allin', ActionType.allIn);
      case 1:
        toCall > 0 ? b('Call ${toCall.toStringAsFixed(1)}', 'call', ActionType.call) : b('Check', 'check', ActionType.check);
        // Branch_2: tras un ROL / Iso-Raise (limp previo) el 3-Bet está disponible para todos, incluido el limper (Limp-3Bet).
        raise(_isRol ? (_limped(p) ? 'Limp-3Bet' : '3-Bet (vs ROL)') : '3-Bet', '3bet', v.bet * (blind ? 4 : 3));
        raise('Min-3B 🐟', 'min3b', v.minTo);
        b('All-In', 'allin', ActionType.allIn);
      case 2:
        // Branch_1: asiento sin fichas voluntarias frente a OR + 3-Bet => Farha (cold-call) / Cold 4-Bet.
        final cold = !_voluntary(p);
        if (toCall > 0) b('Fold', 'fold', ActionType.fold);
        toCall > 0
            ? b(cold ? 'Call ${toCall.toStringAsFixed(1)} (Farha)' : 'Call ${toCall.toStringAsFixed(1)}', 'call', ActionType.call)
            : b('Check', 'check', ActionType.check);
        raise(cold ? '4-Bet (Cold 4B)' : '4-Bet', '4bet', v.bet * 2.4);
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

  /// Botones contextuales del nivel actual para [p]; [apply] ejecuta (villano: seatAct, Hero manual: heroManual).
  List<Widget> _levelButtons(Position p, void Function(ActionType t, double amt) apply) => [
    for (final (label, code, t, amt) in _specs(p, _viewNow())) ...[
      // Opt_1: frente a una subida de Hero, [Call ➔ Flop] cierra el preflop en 1 toque (resto = Fold); [+Call] añade callers.
      if (code == 'call' && p != fsm.heroPosition && _heroRaisedLast)
        chip(
          'Call ➔ Flop',
          'act-${p.name}-callflop',
          true,
          () => widget.act(() {
            apply(t, amt);
            if (fsm.phase == HandPhase.preflop && !fsm.pendingToAct.contains(fsm.heroPosition)) flow.resolveStreet();
          }),
          h: 46,
        ),
      chip(
        code == 'call' && p != fsm.heroPosition && _heroRaisedLast ? (label.contains('Farha') ? '+Call (Farha)' : '+Call') : label,
        'act-${p.name}-$code',
        false,
        () => widget.act(() => apply(t, amt)),
        h: 46,
      ),
    ],
  ];

  /// Hubo limp(s) antes de la 1ra subida preflop (ROL / Iso-Raise).
  bool get _isRol {
    for (final a in fsm.actions) {
      if (a.street != Street.preflop) continue;
      if (a.isAggressive) return false;
      if (a.type == ActionType.call) return true;
    }
    return false;
  }

  bool _limped(Position p) {
    for (final a in fsm.actions) {
      if (a.street != Street.preflop || a.isAggressive) return false;
      if (a.actor == p && a.type == ActionType.call) return true;
    }
    return false;
  }

  /// El asiento puso fichas voluntariamente en preflop (limp/call/raise; las ciegas no cuentan).
  bool _voluntary(Position p) => fsm.actions.any((a) => a.street == Street.preflop && a.actor == p && a.type != ActionType.fold);

  /// La última subida preflop es de Hero y Hero ya no debe actuar (los villanos responden a su OR/ROL/3-Bet/4-Bet).
  bool get _heroRaisedLast {
    // Hero ya actuó en la órbita y no debe responder: cualquier Call puede cerrar el preflop (resto = Fold).
    final heroIn = fsm.actions.any((x) => x.street == Street.preflop && x.actor == fsm.heroPosition && x.type != ActionType.fold);
    final raised = fsm.actions.any((x) => x.street == Street.preflop && x.isAggressive);
    return heroIn && raised && !fsm.pendingToAct.contains(fsm.heroPosition);
  }

  /// Filas DETRÁS de Hero mientras Hero aún no ha hablado: al tocar, se asume la jugada del solver para Hero
  /// (asientos previos sin tocar = Fold) y se aplica la acción del villano con montos reales del nuevo estado.
  List<Widget> _postHeroButtons(Position p, DecisionOutput d) => [
    for (final (label, code, _, _) in _specs(p, _viewAfterHero(d)))
      chip(
        label,
        'act-${p.name}-$code',
        false,
        () => widget.act(() {
          flow.heroGo();
          if (!fsm.canTap(p)) return;
          for (final (_, c2, t2, amt2) in _specs(p, _viewNow())) {
            if (c2 == code) {
              flow.seatAct(p, t2, amount: amt2);
              return;
            }
          }
        }),
        h: 46,
      ),
  ];

  String _status(Position p) {
    if (widget.spec != null && widget.spec!.active && widget.spec!.folded.contains(p)) return 'Fold (auto · toca si entró)';
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
      if (a[i].type == ActionType.fold) continue; // folds a esa subida: se conservan al re-ajustar
      return a[i].type == ActionType.raise ? i : -1;
    }
    return -1;
  }

  void _applyResize(int idx, double to) {
    final p = fsm.actions[idx].actor;
    final folded = [
      for (final a in fsm.actions.skip(idx + 1))
        if (a.type == ActionType.fold && a.actor != fsm.heroPosition) a.actor,
    ];
    final heroWasIn = fsm.actions.skip(idx + 1).any((a) => a.actor == fsm.heroPosition);
    while (fsm.actions.length > idx && fsm.canUndo) {
      fsm.undo();
    }
    flow.manualMode = false;
    raiseOrShove(flow, p, to);
    // Restaura los folds frente a esa subida y re-evalúa a Hero con el nuevo tamaño.
    for (final f in folded) {
      if (fsm.canTap(f)) flow.seatAct(f, ActionType.fold);
    }
    if (heroWasIn && fsm.pendingToAct.contains(fsm.heroPosition) && fsm.canTap(fsm.heroPosition)) flow.heroGo();
  }

  Widget _row(Position p, int resizeIdx) {
    final spec = widget.spec;
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
              child: Container(
                constraints: const BoxConstraints(minHeight: 46, minWidth: 46),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 4),
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
      }
    } else if (spec != null && spec.active && spec.folded.contains(p) && spec.view != null) {
      // Asiento en blanco auto-foldeado: tocarlo deshace la especulación y re-aplica a Hero en vivo.
      for (final (label, code, _, _) in _specs(p, spec.view!)) {
        buttons.add(
          chip(
            label,
            'act-${p.name}-$code',
            false,
            () => widget.act(() {
              spec.rollback();
              for (final (_, c2, t2, amt2) in _specs(p, _viewNow())) {
                if (c2 == code) {
                  flow.seatAct(p, t2, amount: amt2);
                  return;
                }
              }
            }),
            h: 46,
          ),
        );
      }
    } else if (fsm.canTap(p)) {
      buttons.addAll(_levelButtons(p, (t, amt) => flow.seatAct(p, t, amount: amt)));
    } else if (fsm.pendingToAct.contains(p) && fsm.pendingToAct.contains(fsm.heroPosition) && fsm.canTap(fsm.heroPosition) && !flow.manualMode) {
      final d = fsm.projectedHeroDecision;
      if (d != null) buttons.addAll(_postHeroButtons(p, d));
    }
    if (buttons.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(spacing: 5, runSpacing: 5, children: buttons),
        ),
      );
    }
    if (!hero && resizeIdx >= 0 && fsm.actions[resizeIdx].actor == p) children.addAll(_resizeBar(p, resizeIdx));
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

  /// Barra contextual para re-ajustar la última subida del villano; Hero se re-evalúa al aplicar.
  List<Widget> _resizeBar(Position p, int resizeIdx) {
    if (_resizeIdx != resizeIdx) {
      _resizeIdx = resizeIdx;
      _resize = fsm.actions[resizeIdx].amountBb;
    }
    // Opt_2 Zero_Apply_Button: soltar el deslizador (o tocar una flecha) aplica el tamaño y re-evalúa a Hero.
    return [
      slider(
        'Ajustar tamaño de ${p.name.toUpperCase()}: ${_resize!.toStringAsFixed(1)} bb',
        _resize!,
        capOf(fsm, p),
        (v) => setState(() => _resize = v),
        rangePot: fsm.totalPotBB,
        onCommit: (v) {
          if ((v - fsm.actions[resizeIdx].amountBb).abs() > 1e-9) widget.act(() => _applyResize(resizeIdx, v));
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.resizeOnly) {
      final ri = _resizableIdx();
      if (ri < 0) return const SizedBox.shrink();
      return Column(key: const ValueKey('resize-only'), crossAxisAlignment: CrossAxisAlignment.stretch, children: _resizeBar(fsm.actions[ri].actor, ri));
    }
    final spec = widget.spec;
    final specOn = spec != null && spec.active;
    final seats = [
      for (final p in HandFlowFSM.preflopOrder)
        if ((fsm.seats[p]?.alive ?? false) || (specOn && spec.folded.contains(p))) p,
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
            heroActed && !heroPending ? 'Responder a tu ${_status(fsm.heroPosition).replaceAll(' (Auto)', '')}:' : 'Antes de ti:',
            style: const TextStyle(color: Obsidian.textSecondary, fontSize: 12),
          ),
        ),
        for (final p in seats) _row(p, ri),
        // Sin botones de confirmación: solo [Todos Foldearon] si nadie igualó a Hero (con bote igualado, el teclado de flop cierra).
        if (heroActed && !heroPending && stay <= 1 && fsm.currentActorSeat != null && fsm.currentActorSeat != fsm.heroPosition) ...[
          const SizedBox(height: 8),
          big('Todos Foldearon (Ganaste el bote)', 'all-fold', () => widget.act(flow.resolveStreet), primary: false),
        ],
      ],
    );
  }
}
