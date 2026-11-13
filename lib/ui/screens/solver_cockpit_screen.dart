import 'package:flutter/material.dart' hide Card;

import '../../application/dual_table_session_manager.dart';
import '../../application/hand_flow_fsm.dart';
import '../../application/linear_hand_flow.dart';
import '../../core/models/decision_output.dart';
import '../../core/models/game_state.dart';
import '../../core/reads/gg_smarthud_analyzer.dart';
import '../../core/reads/villain_archetypes.dart';
import '../services/tactical_feedback_service.dart';
import '../theme.dart';
import '../theme/obsidian_theme.dart';
import '../widgets/blocker_xray.dart';
import '../widgets/decision_and_why_panel.dart';
import '../widgets/live_line_breadcrumb.dart';
import '../widgets/peek_169_heatmap.dart';
import '../widgets/playing_card_widget.dart';
import '../widgets/smarthud_quick_sheet.dart';
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
                  if (fsm.phase != HandPhase.setup && fsm.street != Street.preflop && flow.liveVillains.isNotEmpty) _liveBar(),
                  if (fsm.board.isNotEmpty || (fsm.awaitingCards && fsm.phase != HandPhase.setup)) _boardRow(),
                  if (fsm.awaitingCards) _picker(),
                  if (flow.preflopUntouched && !flow.atHeroTurn) _step2(),
                  if (_mainVillain() != null && fsm.phase != HandPhase.setup) _villainLabels(),
                  if (flow.lastHero != null) _result(flow.lastHero!),
                  if (fsm.phase != HandPhase.setup && !fsm.awaitingCards) _next(),
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
          TextButton(
            key: const ValueKey('new-hand'),
            onPressed: () => _do(() {
              pendingMode = null;
              limpers.clear();
              flow.newHand();
            }),
            child: const Text(
              'Nueva mano ↺',
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
                        setup ? () => _do(() => flow.setPosition(p)) : null,
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

  /// Cabecera multiway: villanos vivos en orden posicional con etiqueta HUD individual y [X Foldeó].
  Widget _liveBar() {
    final order = [
      for (final p in HandFlowFSM.postflopOrder)
        if ((fsm.seats[p]?.alive ?? false)) p,
    ];
    final chips = <Widget>[];
    for (var i = 0; i < order.length; i++) {
      final p = order[i];
      final isHero = p == fsm.heroPosition;
      final rel = isHero ? 'Hero' : (i == 0 ? 'OOP' : (i == order.length - 1 ? 'IP' : 'MID'));
      final tag = isHero ? null : fsm.hudOf(p)?.tag;
      if (i > 0) chips.add(const Text('➔', style: TextStyle(color: AppColors.muted, fontSize: 12)));
      chips.add(
        GestureDetector(
          key: ValueKey('live-${p.name}'),
          onLongPress: isHero ? null : () => SmartHudQuickSheet.show(context, fsm, p),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: fsm.currentActor == p ? Obsidian.amberCheck.withValues(alpha: .25) : AppColors.bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isHero ? Obsidian.emeraldRaise : AppColors.border),
            ),
            child: Text(
              '${p.name.toUpperCase()} ($rel)${tag == null ? '' : ' · ${tag.name}'}',
              style: const TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
      if (!isHero && fsm.currentActor == p && order.length > 2) {
        chips.add(_btn('✕ Foldeó', Obsidian.crimsonFold, () => _do(() => flow.villainFolded(p)), 'fold-${p.name}', small: true));
      }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(key: const ValueKey('live-bar'), spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: chips),
    );
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
        }),
      ),
    );
  }

  Widget _step2() {
    final chips = <Widget>[];
    if (pendingMode == null) {
      chips.add(_btn('Limpia (todos foldearon)', AppColors.surfaceHi, () => _do(flow.scenarioClean), 'scn-clean', small: true));
      for (final o in flow.openersBeforeHero) {
        chips.add(_btn('Open de ${o.name.toUpperCase()}', AppColors.surfaceHi, () => _do(() => flow.scenarioOpen(o)), 'scn-open-${o.name}', small: true));
      }
      if (flow.openersBeforeHero.length >= 2) {
        chips.add(
          _btn('Open + ¿Quién más pagó? (Cold Callers)', AppColors.surfaceHi, () => setState(() => pendingMode = 'squeeze'), 'scn-squeeze', small: true),
        );
      }
      if (flow.openersBeforeHero.isNotEmpty) {
        chips.add(_btn('1+ limpers', AppColors.surfaceHi, () => setState(() => pendingMode = 'limp'), 'scn-limp', small: true));
      }
      if (flow.seatsAfterHero.isNotEmpty) {
        chips.add(_btn('Enfrento 3-bet', AppColors.surfaceHi, () => setState(() => pendingMode = '3bet'), 'scn-3bet', small: true));
      }
    } else if (pendingMode == 'squeeze') {
      for (final o in flow.openersBeforeHero.take(flow.openersBeforeHero.length - 1)) {
        chips.add(
          _btn(
            'Abrió ${o.name.toUpperCase()}',
            AppColors.surfaceHi,
            () => setState(() {
              squeezeOpener = o;
              pendingMode = 'squeeze-caller';
            }),
            'sq-open-${o.name}',
            small: true,
          ),
        );
      }
    } else if (pendingMode == 'squeeze-caller') {
      for (final c in flow.coldCallerCandidates(squeezeOpener!)) {
        chips.add(
          _btn(
            '${coldCallers.contains(c) ? '✓ ' : ''}${c.name.toUpperCase()}',
            coldCallers.contains(c) ? Obsidian.cyanCall : AppColors.surfaceHi,
            () => setState(() => coldCallers.contains(c) ? coldCallers.remove(c) : coldCallers.add(c)),
            'sq-call-${c.name}',
            small: true,
          ),
        );
      }
      chips.add(
        _btn(
          'Listo (${coldCallers.length} caller${coldCallers.length == 1 ? '' : 's'})',
          Obsidian.emeraldRaise,
          () => _do(() {
            pendingMode = null;
            flow.scenarioOpen(squeezeOpener!, callers: coldCallers.toList());
            coldCallers.clear();
          }),
          'sq-done',
          small: true,
        ),
      );
    } else if (pendingMode == 'limp') {
      for (final l in flow.openersBeforeHero) {
        chips.add(
          _btn(
            '${limpers.contains(l) ? '✓ ' : ''}Limp ${l.name.toUpperCase()}',
            AppColors.surfaceHi,
            () => setState(() => limpers.contains(l) ? limpers.remove(l) : limpers.add(l)),
            'limp-${l.name}',
            small: true,
          ),
        );
      }
      chips.add(
        _btn(
          'Listo',
          Obsidian.emeraldRaise,
          limpers.isEmpty
              ? null
              : () => _do(() {
                  pendingMode = null;
                  flow.scenarioLimpers(List.of(limpers)..sort((a, b) => a.index.compareTo(b.index)));
                  limpers.clear();
                }),
          'limp-done',
          small: true,
        ),
      );
    } else if (pendingMode == '3bet') {
      for (final t in flow.seatsAfterHero) {
        chips.add(
          _btn(
            '3-bet de ${t.name.toUpperCase()}',
            AppColors.surfaceHi,
            () => _do(() {
              pendingMode = null;
              flow.scenarioFacing3Bet(t);
            }),
            'scn-3bet-${t.name}',
            small: true,
          ),
        );
      }
    }
    if (pendingMode != null) {
      chips.add(
        _btn(
          '↩',
          AppColors.surfaceHi,
          () => setState(() {
            pendingMode = null;
            coldCallers.clear();
          }),
          'scn-back',
          small: true,
        ),
      );
    }
    if (pendingMode == 'squeeze-caller') {
      return _section('+ ¿QUIÉN MÁS PAGÓ ANTES DE TI? (COLD CALLERS)', Wrap(spacing: 6, runSpacing: 6, children: chips));
    }
    return _section('2 · ¿QUÉ PASÓ ANTES DE TU TURNO?', Wrap(spacing: 6, runSpacing: 6, children: chips));
  }

  Position? _mainVillain() {
    final last = fsm.actions.reversed.where((a) => a.actor != fsm.heroPosition && a.isAggressive).firstOrNull?.actor;
    if (last != null && (fsm.seats[last]?.alive ?? false)) return last;
    return fsm.currentActor != null && fsm.currentActor != fsm.heroPosition ? fsm.currentActor : null;
  }

  Widget _villainLabels() {
    final v = _mainVillain()!;
    const tags = [
      (VillainTag.poolDefault, 'Pool'),
      (VillainTag.fishStation, 'Fish'),
      (VillainTag.nitPassive, 'Nit'),
      (VillainTag.scaredReg, 'Scared'),
      (VillainTag.agroManiac, 'Maniac'),
    ];
    final cur = fsm.hudOf(v)?.tag;
    return _section(
      'RIVAL ${v.name.toUpperCase()} · etiqueta (mantén pulsado para HUD)',
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final (t, l) in tags)
            GestureDetector(
              onLongPress: () => SmartHudQuickSheet.show(context, fsm, v),
              child: _btn(
                l,
                cur == t ? Obsidian.cyanCall : AppColors.surfaceHi,
                () => _do(() => fsm.setHud(v, SmartHudStats.preset(t), manualTag: t)),
                'tag-${t.name}',
                small: true,
              ),
            ),
        ],
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
          if (!flow.manualMode && fsm.canUndo)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey('override'),
                onPressed: () => _do(flow.overrideHero),
                child: const Text('Cambiar mi acción (no hice lo del solver)', style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ),
            ),
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

  Widget _next() {
    final p = fsm.currentActor;
    if (fsm.phase == HandPhase.handOver || p == null) {
      return _section('MANO TERMINADA', _btn('Nueva mano ↺', Obsidian.emeraldRaise, () => _do(flow.newHand), 'end-new-hand'));
    }
    if (flow.preflopUntouched && !flow.atHeroTurn) return const SizedBox.shrink();
    final s = fsm.seats[p]!;
    final toCall = fsm.currentBet - s.committed;
    double clampTo(double x) => x < fsm.minRaiseTo ? fsm.minRaiseTo : (x > s.committed + s.stack ? s.committed + s.stack : x);
    ActionType agg() => fsm.currentBet == 0 ? ActionType.bet : ActionType.raise;
    if (p == fsm.heroPosition) {
      final buttons = <Widget>[
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
      ];
      return _section('TU TURNO — elige tu acción', Wrap(spacing: 6, runSpacing: 6, children: buttons));
    }
    if (fsm.street == Street.preflop && toCall > 0 && flow.lastHero != null) return _flopCallers();
    final multiway = fsm.street != Street.preflop && flow.liveVillains.length >= 2;
    if (multiway) return _multiwayResponse(p, toCall, clampTo);
    // Respuesta del villano en 1 toque.
    final pending = <Position>[
      for (final q in HandFlowFSM.preflopOrder)
        if (q != fsm.heroPosition && (fsm.seats[q]?.alive ?? false) && !(fsm.seats[q]?.allIn ?? true)) q,
    ];
    final chips = <Widget>[];
    if (toCall > 0) {
      chips.add(_btn(pending.length > 1 ? 'Todos foldean' : 'Villano foldeó', Obsidian.crimsonFold, () => _do(flow.allFold), 'resp-allfold', small: true));
      for (final v in pending) {
        chips.add(
          _btn('${v.name.toUpperCase()} paga', Obsidian.cyanCall, () => _do(() => flow.villain(v, ActionType.call)), 'resp-call-${v.name}', small: true),
        );
        chips.add(
          _btn(
            '${v.name.toUpperCase()} resube',
            Obsidian.emeraldRaise,
            () => _do(() => flow.villain(v, ActionType.raise, amount: clampTo(fsm.currentBet * (fsm.street == Street.preflop ? 3 : 2.5)))),
            'resp-raise-${v.name}',
            small: true,
          ),
        );
      }
    } else {
      chips.add(_btn('${p.name.toUpperCase()} pasó', Obsidian.amberCheck, () => _do(() => flow.villain(p, ActionType.check)), 'resp-check', small: true));
      for (final (l, x) in [('33%', .33), ('50%', .5), ('75%', .75)]) {
        chips.add(
          _btn('Apostó $l', Obsidian.emeraldRaise, () => _do(() => flow.villain(p, ActionType.bet, amount: clampTo(fsm.pot * x))), 'resp-bet$l', small: true),
        );
      }
      chips.add(_btn('Apostó 1bb', Obsidian.emeraldRaise, () => _do(() => flow.villain(p, ActionType.bet, amount: clampTo(1))), 'resp-bet1bb', small: true));
    }
    return _section('¿QUÉ HIZO EL RIVAL? (turno de ${p.name.toUpperCase()})', Wrap(spacing: 6, runSpacing: 6, children: chips));
  }

  /// Preflop tras la acción de Hero: `¿Quiénes pagaron al Flop?` (toggles) ➔ [IR A FLOP (N-Way)] | [3-Bet de X].
  Widget _flopCallers() {
    final pending = flow.pendingOwing;
    flopCallers.removeWhere((x) => !pending.contains(x));
    final n = flow.liveVillains.where((v) => !pending.contains(v)).length + flopCallers.length + 1;
    final chips = <Widget>[
      for (final v in pending)
        _btn(
          '${flopCallers.contains(v) ? '✓ ' : ''}${v.name.toUpperCase()}',
          flopCallers.contains(v) ? Obsidian.cyanCall : AppColors.surfaceHi,
          () => setState(() => flopCallers.contains(v) ? flopCallers.remove(v) : flopCallers.add(v)),
          'fc-${v.name}',
          small: true,
        ),
      _btn(
        n == 1 ? 'Todos foldean' : 'IR A FLOP (${n == 2 ? 'HU' : '$n-Way'}) ➔',
        n == 1 ? Obsidian.crimsonFold : Obsidian.emeraldRaise,
        () => _do(() {
          final cs = Set.of(flopCallers);
          flopCallers.clear();
          flow.goToFlop(cs);
        }),
        'go-flop',
        small: true,
      ),
      for (final v in pending)
        if (fsm.canRaise(v))
          _btn(
            '3-Bet de ${v.name.toUpperCase()}',
            AppColors.surfaceHi,
            () => _do(() {
              flopCallers.clear();
              flow.threeBetBy(v);
            }),
            'fc-3bet-${v.name}',
            small: true,
          ),
    ];
    return _section('¿QUIÉNES PAGARON AL FLOP?', Wrap(spacing: 6, runSpacing: 6, children: chips));
  }

  /// Postflop multiway: solo actúa el villano en turno (el resto sigue vivo).
  Widget _multiwayResponse(Position p, double toCall, double Function(double) clampTo) {
    final n = p.name.toUpperCase();
    final chips = <Widget>[
      if (toCall > 0) ...[
        _btn('$n foldeó', Obsidian.crimsonFold, () => _do(() => flow.villainAct(ActionType.fold)), 'resp-allfold', small: true),
        _btn('$n paga', Obsidian.cyanCall, () => _do(() => flow.villainAct(ActionType.call)), 'resp-call-${p.name}', small: true),
        if (fsm.canRaise(p))
          _btn(
            '$n resube',
            Obsidian.emeraldRaise,
            () => _do(() => flow.villainAct(ActionType.raise, amount: clampTo(fsm.currentBet * 2.5))),
            'resp-raise-${p.name}',
            small: true,
          ),
      ] else ...[
        _btn('$n pasó', Obsidian.amberCheck, () => _do(() => flow.villainAct(ActionType.check)), 'resp-check', small: true),
        for (final (l, x) in [('33%', .33), ('50%', .5), ('75%', .75)])
          _btn('Apostó $l', Obsidian.emeraldRaise, () => _do(() => flow.villainAct(ActionType.bet, amount: clampTo(fsm.pot * x))), 'resp-bet$l', small: true),
      ],
    ];
    return _section('MULTIWAY · ¿QUÉ HIZO $n?', Wrap(spacing: 6, runSpacing: 6, children: chips));
  }
}
