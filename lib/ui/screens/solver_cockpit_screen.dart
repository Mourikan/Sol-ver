import 'package:flutter/material.dart' hide Card;

import '../../application/hand_flow_fsm.dart';
import '../../core/models/game_state.dart';
import '../../core/reads/gg_profiler.dart';
import '../../core/reads/read_presets_catalog.dart';
import '../../core/reads/villain_archetypes.dart';
import '../theme.dart';
import '../services/tactical_feedback_service.dart';
import '../theme/obsidian_theme.dart';
import '../widgets/blocker_xray.dart';
import '../widgets/decision_and_why_panel.dart';
import '../widgets/live_line_breadcrumb.dart';
import '../widgets/fast_card_matrix_picker.dart';
import '../widgets/playing_card_widget.dart';
import '../widgets/pro_poker_table_painter.dart';
import '../widgets/sequential_action_bar.dart';
import '../widgets/smarthud_quick_sheet.dart';

/// Cockpit de un solo lienzo (Obsidian): cabecera | mesa GPU | cartas + tells | oráculo + "Por qué" | acción secuencial.
class SolverCockpitScreen extends StatefulWidget {
  const SolverCockpitScreen({super.key, this.fsm});
  final HandFlowFSM? fsm;

  @override
  State<SolverCockpitScreen> createState() => _SolverCockpitScreenState();
}

class _SolverCockpitScreenState extends State<SolverCockpitScreen> {
  late final HandFlowFSM fsm = widget.fsm ?? HandFlowFSM();
  String? error;

  @override
  void initState() {
    super.initState();
    fsm.addListener(_onFsm);
    TacticalFeedback.keepScreenOn(true);
  }

  @override
  void dispose() {
    fsm.removeListener(_onFsm);
    TacticalFeedback.keepScreenOn(false);
    super.dispose();
  }

  /// Háptica al publicarse la recomendación del turno de Hero.
  void _onFsm() => TacticalFeedback.onDecision(fsm.currentActor == fsm.heroPosition ? fsm.activeRecommendation : null);

  /// Tap en el villano en turno: acción pasiva por defecto (preflop: fold / check de BB; postflop: check o call).
  void _seatTap(Position p) => _do(() {
        TacticalFeedback.tap();
        if (fsm.phase == HandPhase.setup) {
          fsm.configure(hero: p);
          return;
        }
        if (p == fsm.heroPosition) return;
        fsm.selectedVillain = p;
        if (fsm.currentActor == p && !fsm.awaitingCards) {
          final owes = fsm.currentBet - fsm.seats[p]!.committed > 0;
          fsm.act(p, fsm.street == Street.preflop ? (owes ? ActionType.fold : ActionType.check) : (owes ? ActionType.call : ActionType.check));
        }
      });

  void _seatSwipeDown(Position p) => _do(() {
        if (fsm.seats[p]?.alive ?? false) fsm.act(p, ActionType.fold);
      });

  void _do(VoidCallback f) {
    setState(() {
      try {
        f();
        error = null;
      } on Object catch (e) {
        error = e.toString();
      }
    });
  }

  String _tag(Position p) {
    final m = switch (fsm.mentalOf(p)) {
      VillainMentalState.steamingTilt => '🔥',
      VillainMentalState.scaredDeepProtector => '🛡️',
      VillainMentalState.normal => '',
    };
    return '$m${_baseTag(p)}';
  }

  String _baseTag(Position p) {
    final hud = fsm.hudOf(p);
    if (hud != null) return VillainArchetypes.of(hud.tag).label;
    return switch (fsm.effectiveProfile(p)) {
      VillainProfile.callingStation => 'Fish',
      VillainProfile.nit => 'Nit',
      VillainProfile.regAbc => 'Scared',
      VillainProfile.maniac || VillainProfile.regAgro => 'Maniac',
      VillainProfile.trapperPremium => 'Trapper',
      VillainProfile.poolDefault => 'Pool',
      VillainProfile.gtoBase => 'Reg',
    };
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: fsm,
            builder: (context, _) => Column(children: [
              SizedBox(height: 32, child: _Header(fsm: fsm, act: _do)),
              LiveLineBreadcrumb(fsm: fsm, act: _do),
              Expanded(
                flex: 27,
                child: ProPokerTable(
                  fsm: fsm,
                  tagOf: _tag,
                  geoActive: fsm.activeRecommendation?.justification?.mathRationale.startsWith('Geo-2E') ?? false,
                  onTap: _seatTap,
                  onSwipeDown: _seatSwipeDown,
                  onLongPress: (p) => SmartHudQuickSheet.show(context, fsm, p),
                ),
              ),
              Expanded(flex: 13, child: _CardsAndTells(fsm: fsm, act: _do)),
              Expanded(
                flex: 36,
                child: fsm.awaitingCards
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: FastCardMatrixPicker(
                            dead: fsm.deadCardIds,
                            onPick: (c) => _do(() {
                                  TacticalFeedback.tap();
                                  fsm.addCard(c);
                                })),
                      )
                    : DecisionAndWhyPanel(fsm: fsm, error: error),
              ),
              Expanded(flex: 24, child: SequentialActionBar(fsm: fsm, act: _do)),
            ]),
          ),
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.fsm, required this.act});
  final HandFlowFSM fsm;
  final void Function(VoidCallback) act;

  @override
  Widget build(BuildContext context) {
    final setup = fsm.phase == HandPhase.setup;
    Widget toggle(String l, bool on, VoidCallback? f) => Padding(
          padding: const EdgeInsets.only(left: 6),
          child: InkWell(
            onTap: f,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(border: Border.all(color: on ? AppColors.emerald : AppColors.border), borderRadius: BorderRadius.circular(6)),
              child: Text(l, style: TextStyle(color: on ? AppColors.emerald : AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(children: [
          DropdownButton<Stake>(
            key: const ValueKey('stake'),
            value: fsm.stake,
            isDense: true,
            underline: const SizedBox.shrink(),
            dropdownColor: AppColors.surface,
            style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 13),
            items: [for (final s in Stake.values) DropdownMenuItem(value: s, child: Text(s.name.toUpperCase()))],
            onChanged: setup ? (s) => act(() => fsm.configure(stake: s)) : null,
          ),
          toggle('Ante', fsm.anteBb > 0, setup ? () => act(() => fsm.setDeadMoney(ante: fsm.anteBb > 0 ? 0 : 0.12)) : null),
          toggle('Straddle', fsm.hasStraddle, setup ? () => act(() => fsm.setDeadMoney(straddle: !fsm.hasStraddle)) : null),
          const SizedBox(width: 10),
          Text('${fsm.street.name.toUpperCase()} · solver ${(fsm.solverMicros / 1000).toStringAsFixed(2)} ms',
              style: Obsidian.num(size: 11, color: Obsidian.muted, weight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class _CardsAndTells extends StatelessWidget {
  const _CardsAndTells({required this.fsm, required this.act});
  final HandFlowFSM fsm;
  final void Function(VoidCallback) act;

  @override
  Widget build(BuildContext context) {
    final hero = [...fsm.heroCards, ...List<Card?>.filled(2 - fsm.heroCards.length, null)];
    final board = [...fsm.board, ...List<Card?>.filled(5 - fsm.board.length, null)];
    final next = fsm.phase == HandPhase.setup ? fsm.heroCards.length : (fsm.awaitingCards ? 2 + fsm.board.length : -1);
    final v = fsm.selectedVillain;
    Widget chip(String l, VoidCallback? f, String k, {bool on = false}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Material(
              color: on ? AppColors.amber.withValues(alpha: .2) : AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: const BorderSide(color: AppColors.border)),
              child: InkWell(
                key: ValueKey(k),
                onTap: f,
                child: Center(child: FittedBox(child: Text(' $l ', style: TextStyle(color: f == null ? AppColors.muted : AppColors.text, fontSize: 11, fontWeight: FontWeight.w800)))),
              ),
            ),
          ),
        );
    final seatOk = v != null && fsm.seats[v] != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(children: [
        Expanded(
          flex: 3,
          child: Row(children: [
            for (var i = 0; i < 2; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Column(children: [
                    Expanded(child: Center(child: PlayingCardWidget(hero[i], focus: next == i, key: ValueKey('slot-hero-$i')))),
                    SizedBox(
                      height: 13,
                      child: hero[i] == null
                          ? null
                          : BlockerXRayBadge(BlockerXRay.of(hero[i]!, fsm.board), key: ValueKey('xray-$i')),
                    ),
                  ]),
                ),
              ),
            const SizedBox(width: 10),
            for (var i = 0; i < 5; i++)
              Expanded(
                  child: Padding(
                      padding: const EdgeInsets.all(2), child: Center(child: PlayingCardWidget(board[i], focus: next == 2 + i, key: ValueKey('slot-board-$i'))))),
          ]),
        ),
        Expanded(
          flex: 2,
          child: Row(children: [
            chip('⚡Insta-Check', seatOk ? () => act(() => fsm.setTiming(v, TimingTell.instaAction)) : null, 'tell-insta-check',
                on: seatOk && fsm.seats[v]!.nextTiming == TimingTell.instaAction),
            chip('⚡Insta-Call', seatOk ? () => act(() => fsm.setTiming(v, TimingTell.instaAction)) : null, 'tell-insta-call'),
            chip('⏳Tank-Bet', seatOk ? () => act(() => fsm.setTiming(v, TimingTell.longTank)) : null, 'tell-tank',
                on: seatOk && fsm.seats[v]!.nextTiming == TimingTell.longTank),
            Expanded(
              child: PopupMenuButton<AnonymousReadPreset>(
                key: const ValueKey('preset-menu'),
                enabled: v != null,
                color: AppColors.surface,
                onSelected: (p) => act(() => fsm.setPresets(v!, [p])),
                itemBuilder: (_) => [
                  for (final p in AnonymousReadPreset.values) PopupMenuItem(value: p, child: Text(ReadPresetsCatalog.label(p), style: const TextStyle(fontSize: 12))),
                ],
                child: Center(
                  child: FittedBox(
                    child: Text(
                        v == null || (fsm.manualPresets[v]?.isEmpty ?? true)
                            ? ' Preset ▾ '
                            : ' ${ReadPresetsCatalog.label(fsm.manualPresets[v]!.first).replaceFirst('PRESET_', '')} ',
                        style: const TextStyle(color: AppColors.text, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
