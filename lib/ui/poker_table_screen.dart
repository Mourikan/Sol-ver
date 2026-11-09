import 'package:flutter/material.dart' hide Card;

import '../application/hand_flow_fsm.dart';
import '../core/models/game_state.dart';
import 'theme.dart';
import 'widgets/action_pad.dart';
import 'widgets/card_picker_grid.dart';
import 'widgets/solver_verdict_card.dart';

/// Pantalla única: header, mesa 6-max, board, veredicto del solver y teclado/acciones contextuales.
class PokerTableScreen extends StatefulWidget {
  const PokerTableScreen({super.key, this.fsm});
  final HandFlowFSM? fsm;

  @override
  State<PokerTableScreen> createState() => _PokerTableScreenState();
}

class _PokerTableScreenState extends State<PokerTableScreen> {
  late final HandFlowFSM fsm = widget.fsm ?? HandFlowFSM();

  void _error(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), duration: const Duration(milliseconds: 1500), backgroundColor: AppColors.danger));

  void _guard(VoidCallback f) {
    try {
      f();
    } on IllegalAction catch (e) {
      _error(e.message);
    }
  }

  String get _cardPrompt => switch (fsm.phase) {
        HandPhase.setup => 'Cartas de Hero (${2 - fsm.heroCards.length})',
        HandPhase.flopCards => 'Flop (${fsm.cardsNeeded})',
        HandPhase.turnCards => 'Turn',
        HandPhase.riverCards => 'River',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: fsm,
          builder: (context, _) {
            final heroTurn = fsm.currentActor == fsm.heroPosition && fsm.currentActor != null;
            return Column(
              children: [
                _Header(fsm: fsm, onReset: fsm.reset, onStake: (s) => _guard(() => fsm.configure(stake: s))),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _Table(fsm: fsm, onHero: (p) => _guard(() => fsm.configure(hero: p))),
                        _BoardRow(fsm: fsm),
                        if (heroTurn) SolverVerdictCard(fsm: fsm, onExecute: () => _guard(fsm.executeRecommendation)),
                        if (fsm.phase == HandPhase.handOver)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('Mano terminada · toca Nueva Mano', style: TextStyle(color: AppColors.muted)),
                          ),
                      ],
                    ),
                  ),
                ),
                if (fsm.awaitingCards)
                  CardPickerGrid(dead: fsm.deadCardIds, prompt: _cardPrompt, onPick: (c) => _guard(() => fsm.addCard(c)))
                else if (fsm.currentActor != null)
                  ActionPad(fsm: fsm, onError: _error),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.fsm, required this.onReset, required this.onStake});
  final HandFlowFSM fsm;
  final VoidCallback onReset;
  final ValueChanged<Stake> onStake;

  @override
  Widget build(BuildContext context) {
    final setup = fsm.phase == HandPhase.setup;
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final s in Stake.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ChoiceChip(
                      key: ValueKey('stake-${s.name}'),
                      label: Text(s.name.toUpperCase()),
                      selected: fsm.stake == s,
                      onSelected: setup ? (_) => onStake(s) : null,
                      selectedColor: AppColors.accent.withValues(alpha: .25),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(width: 6),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Pot ${fsm.phase == HandPhase.setup ? '—' : fsm.pot.toStringAsFixed(1)}bb',
                style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w800)),
            Text('SPR ${fsm.spr?.toStringAsFixed(1) ?? '—'}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
          IconButton(key: const ValueKey('reset'), onPressed: onReset, icon: const Icon(Icons.refresh, color: AppColors.accent), tooltip: 'Nueva mano'),
        ],
      ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.fsm, required this.onHero});
  final HandFlowFSM fsm;
  final ValueChanged<Position> onHero;

  @override
  Widget build(BuildContext context) {
    final seats = HandFlowFSM.preflopOrder;
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(children: [
        for (final row in [seats.sublist(0, 3), seats.sublist(3)])
          Row(children: [for (final p in row) Expanded(child: _Seat(fsm: fsm, p: p, onHero: onHero))]),
      ]),
    );
  }
}

class _Seat extends StatelessWidget {
  const _Seat({required this.fsm, required this.p, required this.onHero});
  final HandFlowFSM fsm;
  final Position p;
  final ValueChanged<Position> onHero;

  static const profiles = [
    (VillainProfile.gtoBase, 'Reg'),
    (VillainProfile.callingStation, 'Fish/CS'),
    (VillainProfile.nit, 'Nit'),
    (VillainProfile.regAbc, 'Scared'),
    (VillainProfile.maniac, 'Maniac'),
    (VillainProfile.trapperPremium, 'Trapper'),
  ];
  static const timings = [(TimingTell.none, 'Normal'), (TimingTell.instaAction, 'Insta'), (TimingTell.longTank, 'Tank')];

  @override
  Widget build(BuildContext context) {
    final seat = fsm.seats[p];
    final hero = p == fsm.heroPosition;
    final turn = fsm.currentActor == p;
    final alive = seat?.alive ?? true;
    final profile = seat?.profile ?? VillainProfile.gtoBase;
    final pi = profiles.indexWhere((x) => x.$1 == profile);
    final ti = timings.indexWhere((x) => x.$1 == (seat?.nextTiming ?? TimingTell.none));
    return GestureDetector(
      key: ValueKey('seat-${p.name}'),
      onTap: fsm.phase == HandPhase.setup ? () => onHero(p) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.all(3),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: hero ? AppColors.accent.withValues(alpha: .12) : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: turn ? AppColors.turn : (hero ? AppColors.accent : AppColors.surfaceHi), width: turn ? 3 : 1.5),
          boxShadow: turn ? [BoxShadow(color: AppColors.turn.withValues(alpha: .45), blurRadius: 10)] : null,
        ),
        child: Opacity(
          opacity: alive ? 1 : .35,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${p.name.toUpperCase()}${hero ? ' ★' : ''}',
                style: TextStyle(color: hero ? AppColors.accent : AppColors.text, fontWeight: FontWeight.w800)),
            Text(seat == null ? '' : (alive ? '${seat.committed.toStringAsFixed(1)}bb' : 'FOLD'),
                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            if (!hero && seat != null && alive) ...[
              const SizedBox(height: 2),
              _Tag(profiles[pi < 0 ? 0 : pi].$2, AppColors.call,
                  () => fsm.setProfile(p, profiles[(pi + 1) % profiles.length].$1), key: ValueKey('profile-${p.name}')),
              const SizedBox(height: 2),
              _Tag(timings[ti < 0 ? 0 : ti].$2, AppColors.muted, () => fsm.setTiming(p, timings[(ti + 1) % timings.length].$1)),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color, this.onTap, {super.key});
  final String text;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(border: Border.all(color: color.withValues(alpha: .6)), borderRadius: BorderRadius.circular(6)),
          child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      );
}

class _BoardRow extends StatelessWidget {
  const _BoardRow({required this.fsm});
  final HandFlowFSM fsm;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: [
          const Text('HERO ', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          for (var i = 0; i < 2; i++) CardChip(i < fsm.heroCards.length ? fsm.heroCards[i] : null),
          const Spacer(),
          for (var i = 0; i < 5; i++) CardChip(i < fsm.board.length ? fsm.board[i] : null, size: 30),
        ]),
      );
}
