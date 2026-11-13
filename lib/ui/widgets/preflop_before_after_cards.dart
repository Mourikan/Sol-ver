import 'package:flutter/material.dart' hide Card;

import '../../application/hand_flow_fsm.dart';
import '../../application/linear_hand_flow.dart';
import '../../core/models/game_state.dart';
import '../theme/obsidian_theme.dart';

/// Preflop ultra-rápido (Fase 13.0): TARJETA 1 "¿Qué ocurrió antes de ti?" + TARJETA 2 "¿Qué pasó después de tu acción?".
/// Los montos no estándar salen de la barra deslizadora universal ([scrub]).
class PreflopBeforeAfterCards extends StatefulWidget {
  const PreflopBeforeAfterCards({super.key, required this.flow, required this.scrub, required this.onScrub, required this.act});
  final LinearHandFlow flow;
  final double scrub;
  final ValueChanged<double> onScrub;
  final void Function(VoidCallback f) act;

  static bool heroActedPreflop(HandFlowFSM fsm) => fsm.actions.any((a) => a.street == Street.preflop && a.actor == fsm.heroPosition);

  @override
  State<PreflopBeforeAfterCards> createState() => _PreflopBeforeAfterCardsState();
}

class _PreflopBeforeAfterCardsState extends State<PreflopBeforeAfterCards> {
  LinearHandFlow get flow => widget.flow;
  HandFlowFSM get fsm => flow.fsm;
  Position? opener;
  final mw = <Position>{};
  final paid = <Position>{};

  static int _idx(Position p) => HandFlowFSM.preflopOrder.indexOf(p);

  Widget _chip(String label, String key, bool selected, VoidCallback? f, {double h = 40, bool expand = false}) {
    final b = SizedBox(
      height: h,
      child: FilledButton(
        key: ValueKey(key),
        style: FilledButton.styleFrom(
          backgroundColor: selected ? Obsidian.buttonActive : Obsidian.buttonDefault,
          foregroundColor: selected ? Obsidian.buttonActiveText : Obsidian.buttonDefaultText,
          disabledBackgroundColor: Obsidian.surfacePanel,
          disabledForegroundColor: Obsidian.textMuted,
          minimumSize: const Size(44, 40),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
            side: const BorderSide(color: Obsidian.borderFine),
          ),
        ),
        onPressed: f,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      ),
    );
    return expand ? Expanded(child: b) : b;
  }

  Widget _card(String title, List<Widget> rows, String key) => Container(
    key: ValueKey(key),
    margin: const EdgeInsets.only(top: 6),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Obsidian.surfacePanel,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Obsidian.borderFine),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(color: Obsidian.textSecondary, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .3),
        ),
        ...rows,
      ],
    ),
  );

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Text(
      t,
      style: const TextStyle(color: Obsidian.textMuted, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );

  double _raiseTo(Position p, double to) {
    final s = fsm.seats[p]!;
    final x = to < fsm.minRaiseTo ? fsm.minRaiseTo : to;
    return x > s.committed + s.stack ? s.committed + s.stack : x;
  }

  void _seatRaise(Position p, double to) {
    final x = _raiseTo(p, to);
    final s = fsm.seats[p]!;
    flow.seatAct(p, x >= s.committed + s.stack - 1e-9 ? ActionType.allIn : ActionType.raise, amount: x);
  }

  /// Ejecuta el escenario previo y deja que el solver actúe por Hero (Auto-Commit).
  void _before(String kind) {
    final o = opener!;
    final callers = mw.toList()..sort((a, b) => _idx(a).compareTo(_idx(b)));
    final open = LinearHandFlow.openSize(o);
    switch (kind) {
      case 'open':
        _seatRaise(o, widget.scrub);
        for (final c in callers) {
          flow.seatAct(c, ActionType.call);
        }
      case 'limp':
        flow.seatAct(o, ActionType.call);
        for (final c in callers) {
          flow.seatAct(c, ActionType.call);
        }
      case 'allin':
        flow.seatAct(o, ActionType.allIn);
        for (final c in callers) {
          flow.seatAct(c, ActionType.call);
        }
      case '3bet':
        _seatRaise(o, open);
        final tb = callers.first;
        _seatRaise(tb, widget.scrub >= open * 2 ? widget.scrub : open * 3);
        for (final c in callers.skip(1)) {
          flow.seatAct(c, ActionType.call);
        }
    }
    if (!PreflopBeforeAfterCards.heroActedPreflop(fsm) && fsm.currentActorSeat != null && !flow.manualMode) flow.heroGo();
    opener = null;
    mw.clear();
  }

  Widget _before1() {
    final prev = flow.openersBeforeHero;
    if (opener != null && !prev.contains(opener)) opener = null;
    final mids = opener == null ? const <Position>[] : flow.coldCallerCandidates(opener!);
    mw.removeWhere((x) => !mids.contains(x));
    final ready = opener != null;
    return _card('¿QUÉ OCURRIÓ ANTES DE TI?', [
      const SizedBox(height: 6),
      Row(children: [_chip('Nadie entró (Limpia a mí)', 'nobody-in', true, () => widget.act(flow.heroGo), h: 48, expand: true)]),
      _label('¿Quién abrió / entró?'),
      Wrap(
        spacing: 5,
        runSpacing: 5,
        children: [
          for (final p in prev)
            _chip(
              p.name.toUpperCase(),
              'who-${p.name}',
              opener == p,
              () => setState(() {
                opener = opener == p ? null : p;
                if (opener != null) widget.onScrub(LinearHandFlow.openSize(p));
              }),
            ),
        ],
      ),
      _label('¿Qué acción hizo?'),
      Row(
        children: [
          _chip('Open', 'act-open', false, ready ? () => widget.act(() => _before('open')) : null, expand: true),
          const SizedBox(width: 4),
          _chip('Limp', 'act-limp', false, ready ? () => widget.act(() => _before('limp')) : null, expand: true),
          const SizedBox(width: 4),
          _chip('3-Bet (otro)', 'act-3bet', false, ready && mw.isNotEmpty ? () => widget.act(() => _before('3bet')) : null, expand: true),
          const SizedBox(width: 4),
          _chip('All-In', 'act-allin', false, ready ? () => widget.act(() => _before('allin')) : null, expand: true),
        ],
      ),
      if (mids.isNotEmpty) ...[
        _label('¿Alguien más pagó en medio? (Multiway) · en 3-Bet: el 1° marcado resube'),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            for (final p in mids)
              _chip('+${p.name.toUpperCase()}', 'mw-${p.name}', mw.contains(p), () => setState(() => mw.contains(p) ? mw.remove(p) : mw.add(p))),
          ],
        ),
      ],
    ], 'card-before');
  }

  Widget _after2() {
    final pending = flow.pendingOwing;
    paid.removeWhere((x) => !pending.contains(x));
    final already = flow.liveVillains.where((v) => !pending.contains(v)).length;
    final n = already + paid.length + 1;
    final reTo = widget.scrub >= fsm.minRaiseTo ? widget.scrub : fsm.currentBet * 3;
    final h = fsm.actions.lastWhere((a) => a.street == Street.preflop && a.actor == fsm.heroPosition);
    final hv = switch (h.type) {
      ActionType.fold => 'Fold',
      ActionType.check => 'Check',
      ActionType.call => 'Call ${h.amountBb.toStringAsFixed(1)}bb',
      _ => '${h.type == ActionType.allIn ? 'All-In' : 'Raise'} ${h.amountBb.toStringAsFixed(1)}bb',
    };
    return _card('¿QUÉ PASÓ DESPUÉS DE TU ACCIÓN?', [
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '★ HERO (${fsm.heroPosition.name.toUpperCase()}): $hv${flow.manualMode ? '' : ' (Auto-Aplicado)'}',
          key: const ValueKey('hero-applied'),
          style: Obsidian.num(size: 13, color: Obsidian.textPrimary),
        ),
      ),
      const SizedBox(height: 6),
      Row(children: [_chip('Todos Foldearon (Fin de Mano)', 'all-fold', false, () => widget.act(flow.resolveStreet), h: 48, expand: true)]),
      _label('¿Quiénes te pagaron para ir al Flop?'),
      Wrap(
        spacing: 5,
        runSpacing: 5,
        children: [
          for (final p in pending)
            _chip('Pagó ${p.name.toUpperCase()}', 'paid-${p.name}', paid.contains(p), () => setState(() => paid.contains(p) ? paid.remove(p) : paid.add(p))),
          _chip(
            'Ir a Flop ➔ ${n <= 2 ? '(HU)' : '($n-Way)'}',
            'go-flop',
            true,
            paid.isEmpty && already == 0
                ? null
                : () => widget.act(() {
                    final cs = Set.of(paid);
                    paid.clear();
                    flow.goToFlop(cs);
                  }),
          ),
        ],
      ),
      _label('¿Alguien te resubió? (monto = barra: ${reTo.toStringAsFixed(1)}bb)'),
      Wrap(
        spacing: 5,
        runSpacing: 5,
        children: [
          for (final p in pending)
            if (fsm.canRaise(p))
              _chip(
                'Me resubió: ${p.name.toUpperCase()}',
                're-raise-${p.name}',
                false,
                () => widget.act(() {
                  paid.clear();
                  _seatRaise(p, reTo);
                }),
              ),
        ],
      ),
    ], 'card-after');
  }

  @override
  Widget build(BuildContext context) {
    if (fsm.phase != HandPhase.preflop || fsm.awaitingCards) return const SizedBox.shrink();
    final acted = PreflopBeforeAfterCards.heroActedPreflop(fsm);
    final cur = fsm.currentActorSeat;
    if (!acted && cur != fsm.heroPosition && flow.openersBeforeHero.isNotEmpty) return _before1();
    if (acted && cur != null && cur != fsm.heroPosition) return _after2();
    return const SizedBox.shrink();
  }
}
