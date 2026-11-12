import 'package:flutter/material.dart' hide Card;

import '../../application/hand_flow_fsm.dart';
import '../../core/models/decision_output.dart';
import '../../core/models/game_state.dart';
import '../../core/reads/read_presets_catalog.dart';
import '../../core/reads/villain_archetypes.dart';
import '../theme.dart';
import '../widgets/fast_card_matrix_picker.dart';
import '../widgets/smarthud_quick_sheet.dart';

/// Cockpit de una sola pantalla (sin scroll): Mesa 26% | Cartas+Tells 22% | Oráculo+Rango 32% | Teclado de acción 20%.
class SolverCockpitScreen extends StatefulWidget {
  const SolverCockpitScreen({super.key, this.fsm});
  final HandFlowFSM? fsm;

  @override
  State<SolverCockpitScreen> createState() => _SolverCockpitScreenState();
}

class _SolverCockpitScreenState extends State<SolverCockpitScreen> {
  late final HandFlowFSM fsm = widget.fsm ?? HandFlowFSM();
  String? error;

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

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SafeArea(
      child: ListenableBuilder(
        listenable: fsm,
        builder: (context, _) => Column(
          children: [
            Expanded(
              flex: 26,
              child: _TableBlock(fsm: fsm, act: _do),
            ),
            Expanded(
              flex: 22,
              child: _CardsBlock(fsm: fsm, act: _do),
            ),
            Expanded(
              flex: 32,
              child: fsm.awaitingCards ? _PickerBlock(fsm: fsm, act: _do) : _OracleBlock(fsm: fsm, error: error),
            ),
            Expanded(
              flex: 20,
              child: _ActionBlock(fsm: fsm, act: _do),
            ),
          ],
        ),
      ),
    ),
  );
}

typedef _Act = void Function(VoidCallback f);

const _emerald = Color(0xFF00C896), _cyan = Color(0xFF00BCD4), _amber = Color(0xFFFFB300), _crimson = Color(0xFFDC143C);

Color actionColor(DecisionAction a) => switch (a) {
  DecisionAction.betRaise => _emerald,
  DecisionAction.call => _cyan,
  DecisionAction.check => _amber,
  DecisionAction.fold => _crimson,
};

String _tagLabel(HandFlowFSM fsm, Position p) {
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

class _TableBlock extends StatelessWidget {
  const _TableBlock({required this.fsm, required this.act});
  final HandFlowFSM fsm;
  final _Act act;

  @override
  Widget build(BuildContext context) {
    final setup = fsm.phase == HandPhase.setup;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
      child: Column(
        children: [
          SizedBox(
            height: 30,
            child: Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButton<Stake>(
                          key: const ValueKey('stake'),
                          value: fsm.stake,
                          isDense: true,
                          underline: const SizedBox.shrink(),
                          style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 13),
                          dropdownColor: AppColors.surface,
                          items: [for (final s in Stake.values) DropdownMenuItem(value: s, child: Text(s.name.toUpperCase()))],
                          onChanged: setup ? (s) => act(() => fsm.configure(stake: s)) : null,
                        ),
                        const SizedBox(width: 6),
                        _Toggle('Ante', fsm.anteBb > 0, setup ? () => act(() => fsm.setDeadMoney(ante: fsm.anteBb > 0 ? 0 : 0.12)) : null),
                        _Toggle('Straddle', fsm.hasStraddle, setup ? () => act(() => fsm.setDeadMoney(straddle: !fsm.hasStraddle)) : null),
                      ],
                    ),
                  ),
                ),
                TextButton(
                  key: const ValueKey('new-hand'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => act(() => fsm.nextHand()),
                  onLongPress: () => act(() => fsm.nextHand(rotateButton: true)),
                  child: const Text(
                    'Nueva Mano ↺',
                    style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.6,
              padding: EdgeInsets.zero,
              children: [for (final p in HandFlowFSM.preflopOrder) _Seat(fsm: fsm, p: p, act: act)],
            ),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle(this.label, this.on, this.onTap);
  final String label;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: on ? AppColors.accent : AppColors.surfaceHi),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(color: on ? AppColors.accent : AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),
    ),
  );
}

class _Seat extends StatelessWidget {
  const _Seat({required this.fsm, required this.p, required this.act});
  final HandFlowFSM fsm;
  final Position p;
  final _Act act;

  @override
  Widget build(BuildContext context) {
    final hero = p == fsm.heroPosition;
    final turn = fsm.currentActor == p;
    final seat = fsm.seats[p];
    final alive = seat?.alive ?? true;
    final selected = fsm.selectedVillain == p;
    final last = fsm.lastActionOf(p);
    final lastTxt = last == null ? '' : '${last.type.name}${last.amountBb > 0 ? ' ${last.amountBb.toStringAsFixed(1)}' : ''}';
    return GestureDetector(
      key: ValueKey('cockpit-seat-${p.name}'),
      onTap: () => act(() {
        if (fsm.phase == HandPhase.setup) {
          fsm.configure(hero: p);
        } else if (!hero) {
          fsm.selectedVillain = p;
        }
      }),
      onLongPress: hero ? null : () => SmartHudQuickSheet.show(context, fsm, p),
      child: Opacity(
        opacity: alive ? 1 : .35,
        child: Container(
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: hero ? AppColors.accent.withValues(alpha: .12) : AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: turn ? AppColors.turn : (selected ? AppColors.call : (hero ? AppColors.accent : AppColors.surfaceHi)),
              width: turn ? 2.5 : 1.2,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${p.name.toUpperCase()}${hero ? '★' : ''} ',
                      style: TextStyle(color: hero ? AppColors.accent : AppColors.text, fontWeight: FontWeight.w800),
                    ),
                    Text('${fsm.stackOf(p).toStringAsFixed(1)}bb', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!hero)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(color: AppColors.call.withValues(alpha: .2), borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          _tagLabel(fsm, p),
                          style: const TextStyle(color: AppColors.call, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    Text(' $lastTxt', style: const TextStyle(color: AppColors.turn, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardsBlock extends StatelessWidget {
  const _CardsBlock({required this.fsm, required this.act});
  final HandFlowFSM fsm;
  final _Act act;

  @override
  Widget build(BuildContext context) {
    final spr = fsm.currentSPR;
    final v = fsm.selectedVillain;
    final slots = [...fsm.heroCards, ...List<Card?>.filled(2 - fsm.heroCards.length, null)];
    final boardSlots = [...fsm.board, ...List<Card?>.filled(5 - fsm.board.length, null)];
    final nextSlot = fsm.phase == HandPhase.setup ? fsm.heroCards.length : (fsm.awaitingCards ? 2 + fsm.board.length : -1);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                for (var i = 0; i < 2; i++)
                  Expanded(
                    child: _Slot(slots[i], focus: nextSlot == i, key: ValueKey('slot-hero-$i')),
                  ),
                const SizedBox(width: 8),
                for (var i = 0; i < 5; i++)
                  Expanded(
                    child: _Slot(boardSlots[i], focus: nextSlot == 2 + i, key: ValueKey('slot-board-$i')),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: FittedBox(
              child: Text(
                'Pot: ${fsm.currentPotBB.toStringAsFixed(1)} bb | SPR: ${spr == null ? '—' : spr.toStringAsFixed(1)}',
                key: const ValueKey('pot-spr'),
                style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 20),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                for (final (t, label) in [
                  (TimingTell.instaAction, '⚡Insta-Check'),
                  (TimingTell.instaAction, '⚡Insta-Call'),
                  (TimingTell.longTank, '⏳Tank-Bet'),
                ])
                  Expanded(
                    child: _Chip(
                      label,
                      v != null && fsm.seats[v]?.nextTiming == t,
                      v == null || fsm.seats[v] == null ? null : () => act(() => fsm.setTiming(v, t)),
                      key: ValueKey('tell-$label'),
                    ),
                  ),
                Expanded(
                  child: PopupMenuButton<AnonymousReadPreset>(
                    key: const ValueKey('preset-menu'),
                    enabled: v != null,
                    color: AppColors.surface,
                    onSelected: (p) => act(() => fsm.setPresets(v!, [p])),
                    itemBuilder: (_) => [
                      for (final p in AnonymousReadPreset.values)
                        PopupMenuItem(
                          value: p,
                          child: Text(ReadPresetsCatalog.label(p), style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                    child: _Chip(
                      v == null || (fsm.manualPresets[v]?.isEmpty ?? true)
                          ? 'Preset'
                          : ReadPresetsCatalog.label(fsm.manualPresets[v]!.first).replaceFirst('PRESET_', ''),
                      false,
                      null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot(this.card, {required this.focus, super.key});
  final Card? card;
  final bool focus;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: focus ? AppColors.turn : AppColors.surfaceHi, width: focus ? 2 : 1),
    ),
    child: Center(
      child: FittedBox(
        child: Text(
          card == null ? '·' : '${card!.rank.symbol}${AppColors.suitGlyph(card!.suit)}',
          style: TextStyle(color: card == null ? AppColors.muted : AppColors.suit(card!.suit), fontWeight: FontWeight.w900, fontSize: 18),
        ),
      ),
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.on, this.onTap, {super.key});
  final String label;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(2),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppColors.turn.withValues(alpha: .2) : AppColors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.surfaceHi),
        ),
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              label,
              style: TextStyle(color: onTap == null ? AppColors.muted : AppColors.text, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    ),
  );
}

class _PickerBlock extends StatelessWidget {
  const _PickerBlock({required this.fsm, required this.act});
  final HandFlowFSM fsm;
  final _Act act;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    child: FastCardMatrixPicker(dead: fsm.deadCardIds, onPick: (c) => act(() => fsm.addCard(c))),
  );
}

class _OracleBlock extends StatelessWidget {
  const _OracleBlock({required this.fsm, this.error});
  final HandFlowFSM fsm;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final d = fsm.activeRecommendation;
    if (d == null) {
      final msg =
          error ??
          fsm.recommendationError ??
          (fsm.phase == HandPhase.handOver ? 'Mano terminada — Nueva Mano ↺' : 'Turno de ${fsm.currentActor?.name.toUpperCase() ?? '—'}');
      return Center(
        child: Text(
          msg,
          key: const ValueKey('oracle-idle'),
          style: const TextStyle(color: AppColors.muted, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      );
    }
    final c = actionColor(d.action);
    final sz = d.sizing;
    final evs = d.actionEVs;
    final evKey = switch (d.action) {
      DecisionAction.betRaise => 'betRaise',
      DecisionAction.call => 'call',
      DecisionAction.check => 'check',
      DecisionAction.fold => 'fold',
    };
    final ev = evs?[evKey];
    final j = d.justification;
    final rule = j == null ? 'GTO_Anchor' : (j.mathRationale.startsWith('Geo-2E') ? 'Geo-2E' : j.activeCloserRule);
    final r = d.perceivedVillainRange;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Column(
        children: [
          Expanded(
            flex: 5,
            child: Container(
              key: const ValueKey('oracle'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: c.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c, width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${d.action == DecisionAction.betRaise ? 'BET/RAISE' : d.action.name.toUpperCase()}'
                        '${sz == null ? '' : ' ${sz.bb.toStringAsFixed(1)}bb (${sz.potPct.round()}%)'}',
                        key: const ValueKey('oracle-action'),
                        style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 28),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'EV: ${ev == null ? '—' : '${ev >= 0 ? '+' : ''}${ev.toStringAsFixed(2)} bb'}'
                        '${d.exploitDeltaEV == null ? '' : '  |  Exploit ΔEV: ${d.exploitDeltaEV! >= 0 ? '+' : ''}${d.exploitDeltaEV!.toStringAsFixed(2)} bb'}'
                        '  |  $rule  |  ${(fsm.solverMicros / 1000).toStringAsFixed(2)} ms',
                        style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 3),
          if (r != null) Expanded(flex: 2, child: _RangeBar(r)),
          if (r != null && r.topRepresentativeHands.isNotEmpty)
            Expanded(
              flex: 1,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'Top: ${r.topRepresentativeHands.join('  ')}',
                  key: const ValueKey('range-top'),
                  style: const TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          if (j != null)
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      j.activeReadBadge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      key: const ValueKey('read-badge'),
                      style: const TextStyle(color: AppColors.call, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      j.mathRationale,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      key: const ValueKey('math-rationale'),
                      style: const TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RangeBar extends StatelessWidget {
  const _RangeBar(this.r);
  final VillainPerceivedRange r;

  @override
  Widget build(BuildContext context) {
    final segs = [
      (r.nutsAndMonstersPct, const Color(0xFFE53935), 'Nuts'),
      (r.mediumShowdownPct, const Color(0xFF1E88E5), 'SD'),
      (r.drawsAndSemibluffsPct, const Color(0xFFFDD835), 'Draw'),
      (r.pureAirAndBluffsPct, const Color(0xFF757575), 'Aire'),
    ];
    final polar = r.nutsAndMonstersPct + r.pureAirAndBluffsPct >= 0.8 && r.mediumShowdownPct < 0.15;
    return Row(
      key: const ValueKey('range-bar'),
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                for (final (pct, col, lbl) in segs)
                  if (pct > 0.005)
                    Expanded(
                      flex: (pct * 1000).round().clamp(1, 1000),
                      child: Container(
                        color: col,
                        alignment: Alignment.center,
                        child: FittedBox(
                          child: Text(
                            '$lbl ${(pct * 100).round()}%',
                            style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
        if (r.isCapped || polar)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              r.isCapped ? '[CAPADO]' : '[POLARIZADO]',
              key: const ValueKey('range-badge'),
              style: TextStyle(color: r.isCapped ? AppColors.turn : AppColors.danger, fontSize: 11, fontWeight: FontWeight.w900),
            ),
          ),
      ],
    );
  }
}

class _ActionBlock extends StatelessWidget {
  const _ActionBlock({required this.fsm, required this.act});
  final HandFlowFSM fsm;
  final _Act act;

  List<(String, double)> _sizes() {
    final p = fsm.currentActor;
    if (p == null) return const [];
    final s = fsm.seats[p]!;
    final allIn = s.committed + s.stack;
    double clampTo(double x) => x < fsm.minRaiseTo ? fsm.minRaiseTo : (x > allIn ? allIn : x);
    if (fsm.street == Street.preflop) {
      final b = fsm.currentBet;
      return [
        ('Min', fsm.minRaiseTo),
        ('2.5x', clampTo(b * 2.5)),
        ('3x', clampTo(b * 3)),
        ('3.5x', clampTo(b * 3.5)),
        ('4x', clampTo(b * 4)),
      ];
    }
    final toCall = fsm.currentBet - s.committed;
    double sz(double f) => fsm.currentBet == 0 ? clampTo(fsm.pot * f) : clampTo(fsm.currentBet + f * (fsm.pot + toCall));
    return [('25%', sz(.25)), ('33%', sz(.33)), ('50%', sz(.5)), ('75%', sz(.75)), ('Pot', sz(1))];
  }

  @override
  Widget build(BuildContext context) {
    final p = fsm.currentActor;
    if (p == null || fsm.awaitingCards) {
      return Center(
        child: Text(
          fsm.awaitingCards ? 'Introduce ${fsm.cardsNeeded} carta(s)' : '—',
          key: const ValueKey('action-idle'),
          style: const TextStyle(color: AppColors.muted),
        ),
      );
    }
    final legal = fsm.legalActions();
    final s = fsm.seats[p]!;
    final toCall = fsm.currentBet - s.committed;
    final heroTurn = p == fsm.heroPosition;
    final manual = <Widget>[
      _Btn('Fold', _crimson, legal.contains(ActionType.fold) ? () => act(() => fsm.act(p, ActionType.fold)) : null, k: 'act-fold'),
      _Btn(
        toCall > 0 ? 'Call ${toCall.toStringAsFixed(1)}' : 'Check',
        _cyan,
        () => act(() => fsm.act(p, toCall > 0 ? ActionType.call : ActionType.check)),
        k: 'act-checkcall',
      ),
      for (final (l, to) in _sizes())
        _Btn(
          l,
          _emerald,
          legal.contains(ActionType.bet) || legal.contains(ActionType.raise)
              ? () => act(() => fsm.act(p, fsm.currentBet == 0 ? ActionType.bet : ActionType.raise, amountBb: to))
              : null,
          k: 'act-$l',
        ),
      _Btn('All-In', _amber, () => act(() => fsm.act(p, ActionType.allIn)), k: 'act-allin'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: Column(
        children: [
          if (heroTurn)
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('execute-optimal'),
                    style: FilledButton.styleFrom(
                      backgroundColor: fsm.activeRecommendation == null
                          ? AppColors.surfaceHi
                          : actionColor(fsm.activeRecommendation!.action),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: fsm.activeRecommendation == null ? null : () => act(fsm.executeRecommendation),
                    child: const FittedBox(
                      child: Text(
                        '⚡ EJECUTAR ACCIÓN ÓPTIMA DEL SOLVER',
                        style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            flex: 4,
            child: Row(children: [for (final w in manual.take(4)) Expanded(child: w)]),
          ),
          Expanded(
            flex: 4,
            child: Row(children: [for (final w in manual.skip(4)) Expanded(child: w)]),
          ),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn(this.label, this.color, this.onTap, {required this.k});
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final String k;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(2),
    child: Material(
      color: onTap == null ? AppColors.surface : color.withValues(alpha: .22),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: ValueKey(k),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Center(
          child: FittedBox(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                style: TextStyle(color: onTap == null ? AppColors.muted : color, fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
