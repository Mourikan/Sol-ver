import 'package:flutter/material.dart' hide Card;

import '../../application/solver_controller.dart';
import '../../application/hand_flow_fsm.dart';
import '../../application/linear_hand_flow.dart';
import '../../core/models/decision_output.dart';
import '../../core/models/game_state.dart';
import '../services/tactical_feedback_service.dart';
import '../theme.dart';
import '../theme/obsidian_theme.dart';
import '../widgets/blocker_xray.dart';
import '../widgets/decision_and_why_panel.dart';
import '../widgets/peek_169_heatmap.dart';
import '../widgets/pinned_oracle_header.dart';
import '../widgets/playing_card_widget.dart';
import '../widgets/bet_size_scrubber_bar.dart';
import '../widgets/preflop_ordered_table_view.dart';
import '../widgets/speculative_hero_controller.dart';
import '../widgets/wizard_step_views.dart';
import '../widgets/two_step_card_picker.dart';

/// Single-Table (Fase 17.0): una única FSM + SolverController, modo inmersivo y Oráculo reactivo fijo arriba.
class SolverCockpitScreen extends StatefulWidget {
  const SolverCockpitScreen({super.key, this.fsm, this.flow});
  final HandFlowFSM? fsm;
  final LinearHandFlow? flow;

  @override
  State<SolverCockpitScreen> createState() => _SolverCockpitScreenState();
}

class _SolverCockpitScreenState extends State<SolverCockpitScreen> {
  late final LinearHandFlow flow = widget.flow ?? LinearHandFlow(widget.fsm);
  final controller = SolverController(executor: InlineExecutor());

  @override
  void initState() {
    super.initState();
    TacticalFeedback.keepScreenOn(true);
  }

  @override
  void dispose() {
    TacticalFeedback.keepScreenOn(false);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    body: SafeArea(
      child: TablePane(key: const ValueKey('pane-0'), flow: flow),
    ),
  );
}

/// Una mesa: flujo lineal completo (estado, breadcrumb y perfiles HUD propios).
class TablePane extends StatefulWidget {
  const TablePane({super.key, required this.flow});
  final LinearHandFlow flow;

  @override
  State<TablePane> createState() => _TablePaneState();
}

class _TablePaneState extends State<TablePane> {
  LinearHandFlow get flow => widget.flow;
  HandFlowFSM get fsm => flow.fsm;
  bool positionChosen = false;
  double scrub = 2.5;
  String _scrubCtx = '';

  /// L1 (Fase 17.5): auto-aplicación especulativa de Hero sin [Mi turno].
  late final spec = SpeculativeHeroController(flow);

  /// [↶ Deshacer]: deshace la especulación + el último toque real del usuario (si solo había especulación,
  /// vuelve a la elección de posición).
  void _undo() {
    if (spec.active) {
      spec.rollback();
      if (fsm.actions.isNotEmpty && fsm.canUndo) {
        fsm.undo();
      } else {
        positionChosen = false;
      }
      flow.manualMode = false;
    } else {
      flow.undoLast();
    }
  }

  /// L3: bote preflop ya igualado entre Hero y >= 1 villano con asientos en blanco pendientes => teclado de flop listo.
  bool get _flopReady {
    if (fsm.phase != HandPhase.preflop || fsm.awaitingCards || fsm.screenPhase == ScreenPhase.handFinished) return false;
    final hero = fsm.heroPosition;
    if (fsm.pendingToAct.contains(hero) || !WizardSteps.heroActed(fsm, Street.preflop)) return false;
    final cur = fsm.currentActorSeat;
    if (cur == null || cur == hero) return false;
    return fsm.activeSeats.any((p) => p != hero && (fsm.seats[p]!.allIn || fsm.seats[p]!.committed >= fsm.currentBet - 1e-9));
  }

  final coldCallers = <Position>{};
  final flopCallers = <Position>{};
  String? error;
  String? pendingMode; // 'squeeze' | 'limp' | 'squeeze-caller'
  Position? squeezeOpener;
  final limpers = <Position>[];
  final scroll = ScrollController();
  bool _wasAwaiting = false;

  /// Al abrirse una calle (pedir cartas) la vista vuelve arriba al selector: 0 scroll manual.
  void _autoScroll() {
    final awaiting = fsm.awaitingCards;
    if (awaiting && !_wasAwaiting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) scroll.jumpTo(0);
      });
    }
    _wasAwaiting = awaiting;
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void _do(VoidCallback f) {
    setState(() {
      try {
        f();
        spec.maybeSpeculate(positionChosen: positionChosen);
        error = null;
      } on Object catch (e) {
        error = e.toString();
      }
    });
    TacticalFeedback.onDecision(flow.lastHero);
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.bg,
    child: ListenableBuilder(
      listenable: flow,
      builder: (context, _) {
        _autoScroll();
        _syncScrub();
        if (fsm.phase == HandPhase.setup) {
          positionChosen = false; // cada mano: 1° mano -> 2° posición
          spec.reset();
        }
        var step = WizardSteps.of(flow, positionChosen: positionChosen);
        // Fold especulativo de Hero: la tabla sigue abierta para añadir villanos en blanco (re-evaluación en vivo).
        if (spec.active && step == WizardStep.handOver) step = WizardStep.preflopTable;
        if (step != _lastStep) {
          _lastStep = step;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (scroll.hasClients) scroll.jumpTo(0);
          });
        }
        return Column(
          children: [
            _header(),
            _ribbon(),
            if (step != WizardStep.handAndSeat) _pinnedOracle(),
            Expanded(
              child: ListView(
                key: const ValueKey('linear-flow'),
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
                children: [
                  KeyedSubtree(key: ValueKey('wizard-${step.name}'), child: _stepView(step)),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(error!, style: const TextStyle(color: AppColors.crimson, fontSize: 12)),
                    ),
                ],
              ),
            ),
            // Bottom-Docked Thumb Keypad: el teclado de cartas siempre anclado abajo.
            if (fsm.awaitingCards || _flopReady)
              Container(key: const ValueKey('picker-dock'), color: Obsidian.surfacePanel, padding: const EdgeInsets.fromLTRB(4, 0, 4, 6), child: _picker()),
          ],
        );
      },
    ),
  );

  WizardStep? _lastStep;

  void _setScrub(double v) => setState(() => scrub = v);

  /// One_Step_Per_Screen: solo la tarjeta del paso actual.
  Widget _stepView(WizardStep step) {
    return switch (step) {
      WizardStep.handAndSeat => _step1(),
      WizardStep.preflopTable => Column(
        children: [PreflopOrderedTableView(flow: flow, act: _do, spec: spec)],
      ),
      // Si la acción de Hero cerró la calle, su jugada + porqué siguen visibles mientras se piden las cartas.
      WizardStep.boardCards => Column(
        children: [
          if (fsm.board.isEmpty) PreflopOrderedTableView(flow: flow, act: _do, resizeOnly: true),
          _boardRow(),
        ],
      ),
      WizardStep.streetAction => Column(
        children: [
          _boardRow(),
          VillainTurnStep(flow: flow, scrub: scrub, onScrub: _setScrub, act: _do),
        ],
      ),
      WizardStep.heroManual => Column(children: [if (fsm.board.isNotEmpty) _boardRow(), _section('TU TURNO — ¿qué hiciste tú?', _heroManual())]),
      WizardStep.handOver => Column(children: [_handOver()]),
    };
  }

  /// Fila 2 de estado vivo: `[PREFLOP] ➔ [FLOP] ➔ [TURN] ➔ [RIVER] ➔ [SHOWDOWN]` + `Bote | SPR | Vivos`.
  Widget _ribbon() {
    final sp = fsm.screenPhase;
    final idx = switch (sp) {
      ScreenPhase.setupHero || ScreenPhase.preflopAction => 0,
      ScreenPhase.pickFlop => 1,
      ScreenPhase.pickTurn => 2,
      ScreenPhase.pickRiver => 3,
      ScreenPhase.postflopStreetAction => fsm.street.index,
      ScreenPhase.handFinished => 4,
    };
    const names = ['PREFLOP', 'FLOP', 'TURN', 'RIVER', 'SHOWDOWN'];
    final cards = fsm.heroCards.length == 2 ? '${fsm.heroCards[0]}${fsm.heroCards[1]} ' : '';
    final alive = fsm.phase == HandPhase.setup ? '6' : fsm.activeSeats.map((p) => p.name.toUpperCase()).join(' ');
    TextStyle st(bool on) => Obsidian.num(size: 11, color: on ? Obsidian.buttonActiveText : Obsidian.textMuted, weight: FontWeight.w800);
    return Container(
      color: Obsidian.surfacePanel,
      padding: const EdgeInsets.fromLTRB(10, 3, 10, 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              key: const ValueKey('street-progress'),
              children: [
                for (var i = 0; i < names.length; i++) ...[
                  if (i > 0) const Text(' ➔ ', style: TextStyle(color: Obsidian.textMuted, fontSize: 11)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: i == idx ? Obsidian.buttonActive : Obsidian.buttonDefault, borderRadius: BorderRadius.circular(5)),
                    child: Text(names[i], key: i == idx ? const ValueKey('street-current') : null, style: st(i == idx)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$cards${fsm.heroPosition.name.toUpperCase()} | Bote: ${fsm.totalPotBB.toStringAsFixed(1)} bb | SPR: ${fsm.currentSPR?.toStringAsFixed(1) ?? '—'} | Vivos: [ $alive ]',
              key: const ValueKey('ribbon'),
              style: Obsidian.num(size: 12, color: Obsidian.textPrimary, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  /// Valor por defecto de la barra al cambiar el contexto (calle / nueva acción).
  void _syncScrub() {
    final ctx = '${fsm.phase.index}-${fsm.actions.length}-${fsm.board.length}';
    if (ctx == _scrubCtx) return;
    _scrubCtx = ctx;
    final raw = fsm.street == Street.preflop ? (fsm.currentBet <= 1 ? 2.5 : fsm.currentBet * 3) : (fsm.currentBet == 0 ? fsm.pot * .5 : fsm.currentBet * 3);
    final hp = fsm.currentActorSeat ?? fsm.heroPosition;
    final hs = fsm.seats[hp];
    final hi = hs == null ? fsm.startingStackBb : hs.committed + hs.stack;
    scrub = BetSizeScrubberBar.snap(raw).clamp(1.0, hi < 1 ? 1.0 : hi).toDouble();
  }

  Widget _header() => SizedBox(
    height: 44,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Sol-ver',
                    style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<Stake>(
                    key: const ValueKey('stake'),
                    value: fsm.stake,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    dropdownColor: AppColors.surface,
                    style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 14),
                    items: [for (final s in Stake.values) DropdownMenuItem(value: s, child: Text(s.name.toUpperCase()))],
                    onChanged: fsm.phase == HandPhase.setup ? (s) => _do(() => flow.setStake(s!)) : null,
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('undo'),
            tooltip: 'Deshacer último toque',
            onPressed: fsm.canUndo ? () => _do(_undo) : null,
            icon: const Text(
              '↶',
              style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          TextButton(
            key: const ValueKey('new-hand'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
            onPressed: () => _do(() {
              pendingMode = null;
              limpers.clear();
              flow.newHand();
            }),
            child: const Text(
              '⚡ Nueva Mano',
              style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _section(String title, Widget child) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .3),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    ),
  );

  Widget _btn(String label, Color c, VoidCallback? f, String key, {bool small = false}) => SizedBox(
    height: small ? 40 : 48,
    child: FilledButton(
      key: ValueKey(key),
      style: FilledButton.styleFrom(
        backgroundColor: f == null ? AppColors.bg : c,
        foregroundColor: Obsidian.onColor(f == null ? AppColors.bg : c),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: f,
      child: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: small ? 13 : 14),
      ),
    ),
  );

  Widget _step1() {
    final setup = fsm.phase == HandPhase.setup;
    final hero = [...fsm.heroCards, ...List<Card?>.filled(2 - fsm.heroCards.length, null)];
    return _section(
      fsm.heroCards.length < 2 ? 'Tu mano:' : 'Tu posición:',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var i = 0; i < 2; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 56,
                        child: PlayingCardWidget(hero[i], focus: setup && fsm.heroCards.length == i, key: ValueKey('slot-hero-$i')),
                      ),
                      SizedBox(height: 16, child: hero[i] == null ? null : BlockerXRayBadge(BlockerXRay.of(hero[i]!, fsm.board), key: ValueKey('xray-$i'))),
                    ],
                  ),
                ),
            ],
          ),
          // Cuadrícula fija 3x2 a ancho completo (targets >= 46dp en 360px).
          Column(
            key: const ValueKey('pos-grid'),
            children: [
              for (final row in [HandFlowFSM.preflopOrder.sublist(0, 3), HandFlowFSM.preflopOrder.sublist(3)])
                Row(children: [for (final p in row) Expanded(child: _posBtn(p, fsm.heroCards.length == 2 && (flow.preflopUntouched || spec.onlySpec)))]),
            ],
          ),
        ],
      ),
    );
  }

  /// Botón de posición en cuadrícula fija 2x3 (misma coordenada siempre).
  Widget _posBtn(Position p, bool enabled) {
    final sel = p == fsm.heroPosition;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: SizedBox(
        height: 46,
        child: FilledButton(
          key: ValueKey('pos-${p.name}'),
          style: FilledButton.styleFrom(
            backgroundColor: sel ? Obsidian.buttonActive : Obsidian.buttonDefault,
            foregroundColor: sel ? Obsidian.buttonActiveText : Obsidian.buttonDefaultText,
            disabledBackgroundColor: sel ? Obsidian.buttonActive : Obsidian.surfacePanel,
            disabledForegroundColor: sel ? Obsidian.buttonActiveText : Obsidian.textMuted,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Obsidian.borderFine),
            ),
          ),
          onPressed: enabled
              ? () => _do(() {
                  if (spec.onlySpec) spec.rollback();
                  flow.setPosition(p);
                  positionChosen = true;
                })
              : null,
          child: Text(p.name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        ),
      ),
    );
  }

  /// `Bote: 8.5 bb | 3 Jugadores (BB, CO, BTN) | SPR: 11.2`
  String _potPill() {
    final alive = [
      for (final p in HandFlowFSM.postflopOrder)
        if (fsm.seats[p]?.alive ?? false) p.name.toUpperCase(),
    ];
    return 'Bote: ${fsm.totalPotBB.toStringAsFixed(1)} bb | ${alive.length} Jugadores (${alive.join(', ')}) | '
        'SPR: ${fsm.currentSPR?.toStringAsFixed(1) ?? '—'}';
  }

  Widget _boardRow() {
    final board = [...fsm.board, ...List<Card?>.filled(5 - fsm.board.length, null)];
    return _section(
      _potPill(),
      Row(
        children: [
          for (var i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: SizedBox(height: 56, child: PlayingCardWidget(board[i], key: ValueKey('slot-board-$i'))),
            ),
        ],
      ),
    );
  }

  Widget _picker() {
    final l3 = _flopReady;
    final title = l3
        ? 'Toca 1ra carta del Flop (o añade otro villano arriba)'
        : switch (fsm.phase) {
            HandPhase.setup => 'Tu mano (${fsm.heroCards.length + 1}/2)',
            HandPhase.flopCards => 'Flop (${fsm.board.length + 1}/3)',
            HandPhase.turnCards => 'Turn',
            _ => 'River',
          };
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: TwoStepCardPicker(
        dead: fsm.deadCardIds,
        title: title,
        onPick: (c) => _do(() {
          TacticalFeedback.tap();
          // L3: la 1ra carta del flop cierra preflop implícitamente (asientos en blanco = Fold).
          if (fsm.phase == HandPhase.preflop && !fsm.awaitingCards) flow.resolveStreet();
          if (fsm.awaitingCards) flow.pickCard(c);
        }),
      ),
    );
  }

  /// Fuente única del Oráculo (R1-R4): manual/turno de Hero -> proyección viva -> decisión vigente.
  (DecisionOutput, bool)? _oracleDecision() {
    if (fsm.heroCards.length < 2) return null;
    final finished = fsm.screenPhase == ScreenPhase.handFinished;
    if (!finished) {
      if (fsm.currentActorSeat == fsm.heroPosition && fsm.activeRecommendation != null) return (fsm.activeRecommendation!, false);
      final p = fsm.projectedHeroDecision;
      if (p != null) return (p, false);
    }
    final last = flow.lastHero;
    return last == null ? null : (last, true);
  }

  static String _street(Street s) => switch (s) {
    Street.preflop => 'PREFLOP',
    Street.flop => 'FLOP',
    Street.turn => 'TURN',
    Street.river => 'RIVER',
  };

  String _villainActLabel(PlayerAction a) {
    if (a.street != Street.preflop) {
      final bet = a.type == ActionType.bet;
      if (a.type == ActionType.allIn) return 'All-In ${a.amountBb.toStringAsFixed(1)}bb';
      return '${bet ? 'Bet' : 'Raise'} ${a.amountBb.toStringAsFixed(1)}bb';
    }
    var lvl = 0;
    for (final x in fsm.actions) {
      if (x.street == Street.preflop && x.isAggressive) lvl++;
      if (identical(x, a)) break;
    }
    final n = a.type == ActionType.allIn
        ? 'All-In'
        : switch (lvl) {
            1 => 'OR',
            2 => '3-Bet',
            3 => '4-Bet',
            _ => '5-Bet',
          };
    return '$n ${a.amountBb.toStringAsFixed(1)}bb';
  }

  /// `ACCIÓN: 3-BET a 7.5 bb` / `ACCIÓN: CALL 7.5 bb` / `ACCIÓN: FOLD`.
  String _actionText(DecisionOutput d, bool applied, Street st) {
    final heroAct = applied ? fsm.actions.reversed.where((a) => a.actor == fsm.heroPosition && a.street == st).firstOrNull : null;
    final hero = fsm.seats[fsm.heroPosition];
    switch (d.action) {
      case DecisionAction.fold:
        return 'ACCIÓN: FOLD';
      case DecisionAction.check:
        return 'ACCIÓN: CHECK';
      case DecisionAction.call:
        final amt = heroAct?.amountBb ?? (hero == null ? 0.0 : fsm.currentBet);
        final bb = st == Street.preflop && fsm.heroPosition == Position.bb;
        return 'ACCIÓN${bb ? ' EN BB' : ''}: CALL ${amt.toStringAsFixed(1)} bb';
      case DecisionAction.betRaise:
        final to = heroAct?.amountBb ?? d.sizing?.bb ?? 0;
        if (st == Street.preflop) {
          final aggr = fsm.actions.where((a) => a.street == Street.preflop && a.isAggressive).toList();
          var lvl = aggr.length;
          if (heroAct != null && heroAct.isAggressive) lvl = aggr.indexOf(heroAct);
          final limps = fsm.actions.any((a) => a.street == Street.preflop && a.type == ActionType.call);
          final n = switch (lvl) {
            0 => limps ? 'ISO' : 'OR',
            1 => '3-BET',
            2 => '4-BET',
            3 => '5-BET',
            _ => 'ALL-IN',
          };
          return 'ACCIÓN: $n a ${to.toStringAsFixed(1)} bb';
        }
        final facing = heroAct != null ? heroAct.type == ActionType.raise : fsm.currentHighBetBB > 0;
        return 'ACCIÓN: ${facing ? 'RAISE a' : 'BET'} ${to.toStringAsFixed(1)} bb${d.sizing == null ? '' : ' (${d.sizing!.potPct.round()}%)'}';
    }
  }

  Widget _pinnedOracle() {
    final o = _oracleDecision();
    if (o == null) return const SizedBox.shrink();
    final (d, applied) = o;
    final st = applied ? (flow.lastHeroStreet ?? fsm.street) : fsm.street;
    final board = fsm.board
        .take(switch (st) {
          Street.preflop => 0,
          Street.flop => 3,
          Street.turn => 4,
          Street.river => 5,
        })
        .map((c) => '${c.rank.symbol}${AppColors.suitGlyph(c.suit)}')
        .join('');
    final vAgg = fsm.actions.reversed.where((a) => a.street == st && a.actor != fsm.heroPosition && a.isAggressive).firstOrNull;
    final vs = vAgg == null ? (st == Street.preflop ? 'limpia' : 'sin apuesta') : '${vAgg.actor.name.toUpperCase()} ${_villainActLabel(vAgg)}';
    final ctx = '[${_street(st)}${board.isEmpty ? '' : ' $board'} • ${fsm.heroPosition.name.toUpperCase()} vs $vs]';
    final last = fsm.actions.isEmpty ? null : fsm.actions.last;
    // R3: banner cuando la decisión vigente responde a una agresión del villano (proyectada o ya auto-aplicada).
    PlayerAction? trigger;
    if (!applied) {
      trigger = last;
    } else {
      final hi = fsm.actions.lastIndexWhere((a) => a.actor == fsm.heroPosition && a.street == st);
      for (var i = hi - 1; i >= 0; i--) {
        if (fsm.actions[i].type == ActionType.fold) continue;
        trigger = fsm.actions[i];
        break;
      }
    }
    final banner = trigger != null && trigger.actor != fsm.heroPosition && trigger.isAggressive
        ? 'ACTUALIZADO VS ${trigger.actor.name.toUpperCase()} ${_villainActLabel(trigger)}'
        : null;
    final ev = d.actionEVs ?? const <String, double>{};
    final evKey = switch (d.action) {
      DecisionAction.betRaise => 'betRaise',
      DecisionAction.call => 'call',
      DecisionAction.check => 'check',
      DecisionAction.fold => 'fold',
    };
    final evLine =
        'EV ${ev[evKey] == null ? '—' : '${ev[evKey]! >= 0 ? '+' : ''}${ev[evKey]!.toStringAsFixed(2)} bb'}'
        '${d.exploitDeltaEV == null ? '' : ' · Δ ${d.exploitDeltaEV! >= 0 ? '+' : ''}${d.exploitDeltaEV!.toStringAsFixed(2)}'}';
    final canOverride = applied && !flow.manualMode && fsm.canUndo && fsm.actions.any((a) => a.actor == fsm.heroPosition);
    final status = flow.manualMode && fsm.currentActorSeat == fsm.heroPosition
        ? 'Elige tu acción abajo'
        : (applied ? '✓ El solver asume que hiciste esta jugada' : '◷ En vivo: asientos sin tocar = Fold');
    return PinnedOracleHeader(
      contextLine: ctx,
      action: _actionText(d, applied, st),
      evLine: evLine,
      status: status,
      updatedBanner: banner,
      onOverride: canOverride ? () => _do(flow.overrideHero) : null,
      body: _oracleBody(d),
    );
  }

  /// Porqué en español (Lectura / EV / Plan) + rango percibido, sin truncar.
  Widget _oracleBody(DecisionOutput d) {
    final j = d.justification;
    final r = d.perceivedVillainRange;
    return Column(
      key: const ValueKey('hero-result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (j != null) ...[
          _why('Lectura', j.villainReadExplanation, 'why-1'),
          _why('EV', j.evWhyExplanation, 'why-2'),
          _why('Plan', j.nextStreetPlan, 'why-3'),
        ],
        if (r != null && r.totalActiveCombos > 0) ...[
          SizedBox(height: 20, child: RangeBar(r)),
          Row(
            children: [
              Expanded(
                child: Text('Top: ${r.topRepresentativeHands.join('  ')}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ),
              if (r.classWeights.isNotEmpty)
                TextButton(
                  key: const ValueKey('peek-169'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
                  onPressed: () => Peek169Heatmap.show(context, r.classWeights),
                  child: const Text('Ver 13x13'),
                ),
            ],
          ),
        ],
        if (d.runoutForecast != null) SizedBox(height: 22, child: RunoutStrip(d.runoutForecast!)),
      ],
    );
  }

  Widget _why(String t, String body, String key) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: RichText(
      key: ValueKey(key),
      text: TextSpan(
        children: [
          TextSpan(
            text: '$t: ',
            style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text: body,
            style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.3),
          ),
        ],
      ),
    ),
  );

  /// Ventana 7_HAND_FINISHED: cómo terminó, bote final, última lectura del rival y [⚡ Empezar Nueva Mano].
  Widget _handOver() {
    final pot = fsm.totalPotBB.toStringAsFixed(1);
    final (title, detail) = switch (fsm.endReason) {
      HandEndReason.foldWin => ('MANO GANADA POR FOLD', 'Rivales foldearon — Ganaste el bote de $pot bb'),
      HandEndReason.heroFolded => ('FOLDEASTE', 'Mano terminada para ti en ${fsm.street.name.toUpperCase()} · bote $pot bb'),
      _ => ('SHOWDOWN', 'SHOWDOWN — Mano completada hasta el River · bote $pot bb'),
    };
    final r = flow.lastHero?.perceivedVillainRange;
    return _section(
      'MANO TERMINADA',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            key: const ValueKey('finish-title'),
            style: Obsidian.num(size: 22, color: Obsidian.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            key: const ValueKey('finish-detail'),
            style: const TextStyle(color: Obsidian.textSecondary, fontSize: 13),
          ),
          if (r != null && r.totalActiveCombos > 0) ...[const SizedBox(height: 8), SizedBox(height: 22, child: RangeBar(r))],
          const SizedBox(height: 12),
          SizedBox(height: 60, child: _btn('⚡ Empezar Nueva Mano', Obsidian.emeraldRaise, () => _do(flow.newHand), 'end-new-hand')),
        ],
      ),
    );
  }

  /// Botones manuales de Hero (tras [Cambiar mi acción]).
  Widget _heroManual() {
    final p = fsm.heroPosition;
    final s = fsm.seats[p]!;
    final toCall = fsm.currentBet - s.committed;
    double clampTo(double x) => x < fsm.minRaiseTo ? fsm.minRaiseTo : (x > s.committed + s.stack ? s.committed + s.stack : x);
    ActionType agg() => fsm.currentBet == 0 ? ActionType.bet : ActionType.raise;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (toCall > 0) _btn('Fold', Obsidian.crimsonFold, () => _do(() => flow.heroManual(ActionType.fold)), 'hero-fold', small: true),
        _btn(
          toCall > 0 ? 'Call ${toCall.toStringAsFixed(1)}' : 'Check',
          toCall > 0 ? Obsidian.cyanCall : Obsidian.amberCheck,
          () => _do(() => flow.heroManual(toCall > 0 ? ActionType.call : ActionType.check)),
          'hero-passive',
          small: true,
        ),
        for (final (l, x) in fsm.street == Street.preflop ? [('Raise 2.5x', 2.5), ('Raise 3x', 3.0)] : [('Bet/Raise 50%', .5), ('75%', .75)])
          _btn(
            l,
            Obsidian.emeraldRaise,
            fsm.canRaise(p)
                ? () => _do(
                    () => flow.heroManual(agg(), amount: clampTo(fsm.street == Street.preflop ? fsm.currentBet * x : fsm.currentBet + x * (fsm.pot + toCall))),
                  )
                : null,
            'hero-agg-$l',
            small: true,
          ),
      ],
    );
  }
}
