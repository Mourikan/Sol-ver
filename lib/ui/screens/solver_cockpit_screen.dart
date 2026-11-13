import 'package:flutter/material.dart' hide Card;

import '../../application/dual_table_session_manager.dart';
import '../../application/hand_flow_fsm.dart';
import '../../application/linear_hand_flow.dart';
import '../../core/models/decision_output.dart';
import '../../core/models/game_state.dart';
import '../services/tactical_feedback_service.dart';
import '../theme.dart';
import '../theme/obsidian_theme.dart';
import '../widgets/blocker_xray.dart';
import '../widgets/decision_and_why_panel.dart';
import '../widgets/live_line_breadcrumb.dart';
import '../widgets/peek_169_heatmap.dart';
import '../widgets/playing_card_widget.dart';
import '../widgets/positional_ledger_view.dart';
import '../widgets/two_step_card_picker.dart';

/// Matte Linear Flow (Fase 11.0): sin mesa. Paso 1 mano+posición -> Paso 2 qué pasó antes (1 toque) ->
/// Paso 3 solución + por qué + AUTO-COMMIT -> respuesta del villano / cartas de la siguiente calle en 1 toque.
/// Fase 11.5: Dual-Table (Mesa 1 / Mesa 2) con IndexedStack => cada mesa conserva su estado al cambiar.
class SolverCockpitScreen extends StatefulWidget {
  const SolverCockpitScreen({super.key, this.fsm, this.flow, this.manager});
  final HandFlowFSM? fsm;
  final LinearHandFlow? flow;
  final DualTableSessionManager? manager;

  @override
  State<SolverCockpitScreen> createState() => _SolverCockpitScreenState();
}

class _SolverCockpitScreenState extends State<SolverCockpitScreen> {
  late final DualTableSessionManager manager =
      widget.manager ?? DualTableSessionManager(flowA: widget.flow ?? (widget.fsm == null ? null : LinearHandFlow(widget.fsm)));

  @override
  void initState() {
    super.initState();
    TacticalFeedback.keepScreenOn(true);
  }

  @override
  void dispose() {
    TacticalFeedback.keepScreenOn(false);
    super.dispose();
  }

  Widget _tab(int i) {
    final slot = manager.slots[i];
    final on = manager.activeIndex == i;
    final c = i == 0 ? Obsidian.cyanCall : const Color(0xFF7C3AED);
    return Expanded(
      child: Material(
        color: on ? c.withValues(alpha: .22) : AppColors.surface,
        child: InkWell(
          key: ValueKey('tab-$i'),
          onTap: () => manager.switchTo(i),
          child: Container(
            height: 44,
            padding: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: on ? c : AppColors.border, width: on ? 3 : 1),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${i == 0 ? '🔵' : '🟣'} ${slot.label}: ${slot.summary}',
                      key: ValueKey('tab-summary-$i'),
                      style: TextStyle(color: on ? AppColors.text : AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey('rush-reset-$i'),
                  tooltip: 'Rush Reset',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
                  onPressed: () {
                    TacticalFeedback.tap();
                    manager.rushReset(i);
                  },
                  icon: const Text('⚡', style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    body: SafeArea(
      child: ListenableBuilder(
        listenable: manager,
        builder: (context, _) => Column(
          children: [
            Row(key: const ValueKey('dual-tabs'), children: [_tab(0), _tab(1)]),
            Expanded(
              child: IndexedStack(
                index: manager.activeIndex,
                children: [for (var i = 0; i < 2; i++) TablePane(key: ValueKey('pane-$i'), flow: manager.slots[i].flow)],
              ),
            ),
          ],
        ),
      ),
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

  /// Law_2: si Hero abre la acción (UTG) y ya eligió mano + posición, el solver actúa con 0 toques.
  void _heroFirstIn() {
    if (positionChosen && flow.preflopUntouched && flow.atHeroTurn && flow.lastHero == null) flow.heroGo();
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
        return Column(
          children: [
            _header(),
            LiveLineBreadcrumb(fsm: fsm, act: _do),
            Expanded(
              child: ListView(
                key: const ValueKey('linear-flow'),
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 12),
                children: [
                  _step1(),
                  if (fsm.board.isNotEmpty || (fsm.awaitingCards && fsm.phase != HandPhase.setup)) _boardRow(),
                  if (fsm.awaitingCards) _picker(),
                  if (fsm.phase != HandPhase.setup && !fsm.awaitingCards && fsm.phase != HandPhase.handOver)
                    PositionalLedgerView(flow: flow, act: _do, heroManual: _heroManual()),
                  if (flow.lastHero != null) _result(flow.lastHero!),
                  if (fsm.phase == HandPhase.handOver) _handOver(),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(error!, style: const TextStyle(color: AppColors.crimson, fontSize: 12)),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

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
            onPressed: fsm.canUndo ? () => _do(flow.undoLast) : null,
            icon: const Text(
              '↶',
              style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          TextButton(
            key: const ValueKey('new-hand'),
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
        foregroundColor: Colors.white,
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
      '1 · TU MANO Y TU POSICIÓN',
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
                        height: 64,
                        child: PlayingCardWidget(hero[i], focus: setup && fsm.heroCards.length == i, key: ValueKey('slot-hero-$i')),
                      ),
                      SizedBox(height: 16, child: hero[i] == null ? null : BlockerXRayBadge(BlockerXRay.of(hero[i]!, fsm.board), key: ValueKey('xray-$i'))),
                    ],
                  ),
                ),
              const SizedBox(width: 6),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in HandFlowFSM.preflopOrder)
                      _btn(
                        p.name.toUpperCase(),
                        p == fsm.heroPosition ? Obsidian.emeraldRaise : AppColors.surfaceHi,
                        setup || flow.preflopUntouched
                            ? () => _do(() {
                                flow.setPosition(p);
                                positionChosen = true;
                                _heroFirstIn();
                              })
                            : null,
                        'pos-${p.name}',
                        small: true,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
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
    final title = switch (fsm.phase) {
      HandPhase.setup => 'Tu mano (${fsm.heroCards.length + 1}/2)',
      HandPhase.flopCards => 'Flop (${fsm.board.length + 1}/3)',
      HandPhase.turnCards => 'Turn',
      _ => 'River',
    };
    return _section(
      title.toUpperCase(),
      TwoStepCardPicker(
        dead: fsm.deadCardIds,
        title: title,
        onPick: (c) => _do(() {
          TacticalFeedback.tap();
          flow.pickCard(c);
          _heroFirstIn();
        }),
      ),
    );
  }

  Widget _result(DecisionOutput d) {
    final c = actionColor(d.action);
    final sz = d.sizing;
    final label = switch (d.action) {
      DecisionAction.betRaise => 'BET / RAISE',
      DecisionAction.call => 'CALL',
      DecisionAction.check => 'CHECK',
      DecisionAction.fold => 'FOLD',
    };
    final ev = d.actionEVs ?? const <String, double>{};
    final evKey = switch (d.action) {
      DecisionAction.betRaise => 'betRaise',
      DecisionAction.call => 'call',
      DecisionAction.check => 'check',
      DecisionAction.fold => 'fold',
    };
    final j = d.justification;
    final r = d.perceivedVillainRange;
    return _section(
      '3 · SOLUCIÓN (${flow.lastHeroStreet?.name.toUpperCase() ?? ''}) — ${flow.manualMode ? 'elige tu acción abajo' : 'asumida como ejecutada'}',
      Column(
        key: const ValueKey('hero-result'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: c.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label${sz == null ? '' : '  ${sz.bb.toStringAsFixed(1)} bb (${sz.potPct.round()}%)'}',
                  key: const ValueKey('hero-action'),
                  style: Obsidian.num(size: 22, color: AppColors.text, weight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  'EV ${ev[evKey] == null ? '—' : '${ev[evKey]! >= 0 ? '+' : ''}${ev[evKey]!.toStringAsFixed(2)} bb'}'
                  '${d.exploitDeltaEV == null ? '' : '  ·  Δ Exploit ${d.exploitDeltaEV! >= 0 ? '+' : ''}${d.exploitDeltaEV!.toStringAsFixed(2)} bb'}'
                  '  ·  ${j?.activeCloserRule ?? 'GTO_Baseline'}',
                  style: Obsidian.num(size: 12, color: AppColors.muted, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
          if (j != null) ...[
            const SizedBox(height: 8),
            _why('Lectura del rival', j.villainReadExplanation, 'why-1'),
            _why('Por qué gana más EV', j.evWhyExplanation, 'why-2'),
            _why('Plan siguiente calle', j.nextStreetPlan, 'why-3'),
          ],
          if (r != null && r.totalActiveCombos > 0) ...[
            const SizedBox(height: 8),
            SizedBox(height: 20, child: RangeBar(r)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text('Top: ${r.topRepresentativeHands.join('  ')}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ),
                if (r.classWeights.isNotEmpty)
                  TextButton(key: const ValueKey('peek-169'), onPressed: () => Peek169Heatmap.show(context, r.classWeights), child: const Text('Ver 13x13')),
              ],
            ),
          ],
          if (d.runoutForecast != null) ...[const SizedBox(height: 6), SizedBox(height: 22, child: RunoutStrip(d.runoutForecast!))],
        ],
      ),
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

  Widget _handOver() => _section('MANO TERMINADA', _btn('Nueva mano ↺', Obsidian.emeraldRaise, () => _do(flow.newHand), 'end-new-hand'));

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
