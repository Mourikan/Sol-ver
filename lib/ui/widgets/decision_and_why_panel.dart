import 'package:flutter/material.dart';

import '../../application/hand_flow_fsm.dart';
import '../../core/models/decision_output.dart';
import '../theme.dart';

Color actionColor(DecisionAction a) => switch (a) {
      DecisionAction.betRaise => AppColors.emerald,
      DecisionAction.call => AppColors.cyan,
      DecisionAction.check => AppColors.amber,
      DecisionAction.fold => AppColors.crimson,
    };

/// Oráculo: acción + EVs comparados + rango percibido del villano + tarjeta "Por qué" (ProCoachNarrativeBuilder).
class DecisionAndWhyPanel extends StatelessWidget {
  const DecisionAndWhyPanel({super.key, required this.fsm, this.error});
  final HandFlowFSM fsm;
  final String? error;

  String _label(DecisionOutput d) {
    final sz = d.sizing;
    final a = switch (d.action) {
      DecisionAction.betRaise => fsm.currentBet > (fsm.seats[fsm.heroPosition]?.committed ?? 0) ? 'RAISE' : 'BET',
      DecisionAction.call => 'CALL',
      DecisionAction.check => 'CHECK',
      DecisionAction.fold => 'FOLD',
    };
    return sz == null ? a : '$a ${sz.potPct.round()}% (${sz.bb.toStringAsFixed(1)} bb)';
  }

  @override
  Widget build(BuildContext context) {
    final d = fsm.activeRecommendation;
    if (d == null) {
      final msg = error ??
          fsm.recommendationError ??
          (fsm.phase == HandPhase.handOver ? 'Mano terminada — Nueva Mano ↺' : 'Esperando la acción de ${fsm.currentActor?.name.toUpperCase() ?? '—'}');
      return Center(child: Text(msg, key: const ValueKey('oracle-idle'), style: const TextStyle(color: AppColors.muted), textAlign: TextAlign.center));
    }
    final c = actionColor(d.action);
    final ev = d.actionEVs ?? const <String, double>{};
    final key = switch (d.action) { DecisionAction.betRaise => 'betRaise', DecisionAction.call => 'call', DecisionAction.check => 'check', DecisionAction.fold => 'fold' };
    String f(double? x) => x == null ? '—' : '${x >= 0 ? '+' : ''}${x.toStringAsFixed(2)}';
    final j = d.justification;
    final r = d.perceivedVillainRange;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          key: const ValueKey('oracle'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: c.withValues(alpha: .14), borderRadius: BorderRadius.circular(10), border: Border.all(color: c, width: 1.5)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(_label(d), key: const ValueKey('oracle-action'), style: TextStyle(color: c, fontSize: 24, fontWeight: FontWeight.w900)),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'EV ${f(ev[key])} bb'
                '${d.exploitDeltaEV == null ? '' : '  ·  Δ Exploit ${f(d.exploitDeltaEV)} bb'}'
                '  ·  ${[if (ev['betRaise'] != null) 'R ${f(ev['betRaise'])}', if (ev['call'] != null) 'C ${f(ev['call'])}', if (ev['check'] != null) 'X ${f(ev['check'])}', 'F ${f(ev['fold'] ?? 0)}'].join(' | ')}'
                '  ·  ${j?.activeCloserRule ?? 'GTO_Baseline'}',
                key: const ValueKey('oracle-evs'),
                style: const TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 4),
        if (r != null && r.totalActiveCombos > 0) ...[
          SizedBox(height: 18, child: RangeBar(r)),
          const SizedBox(height: 3),
          SizedBox(
            height: 20,
            child: Row(key: const ValueKey('range-top'), children: [
              for (final h in r.topRepresentativeHands.take(5))
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(5)),
                    child: Text(h, style: const TextStyle(color: AppColors.text, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 3),
        ],
        if (j != null)
          Expanded(
            child: Container(
              key: const ValueKey('why-card'),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(8)),
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(j.activeReadBadge, key: const ValueKey('read-badge'), style: const TextStyle(color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.w800)),
                  _Why('1. Lectura de Rango', j.villainReadExplanation, const ValueKey('why-1')),
                  _Why('2. Matemática EV', j.evWhyExplanation, const ValueKey('why-2')),
                  _Why('3. Plan Siguiente Calle', j.nextStreetPlan, const ValueKey('why-3')),
                  Text(j.mathRationale, key: const ValueKey('math-rationale'), style: const TextStyle(color: AppColors.muted, fontSize: 10)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

class _Why extends StatelessWidget {
  const _Why(this.title, this.body, Key key) : super(key: key);
  final String title, body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: RichText(
          text: TextSpan(children: [
            TextSpan(text: '$title  ', style: const TextStyle(color: AppColors.amber, fontSize: 11, fontWeight: FontWeight.w900)),
            TextSpan(text: body, style: const TextStyle(color: AppColors.text, fontSize: 11, height: 1.25)),
          ]),
        ),
      );
}

class RangeBar extends StatelessWidget {
  const RangeBar(this.r, {super.key});
  final VillainPerceivedRange r;

  @override
  Widget build(BuildContext context) {
    final segs = [
      (r.nutsAndMonstersPct, AppColors.crimson, 'Nuts'),
      (r.mediumShowdownPct, const Color(0xFF3B82F6), 'Pares'),
      (r.drawsAndSemibluffsPct, AppColors.amber, 'Draws'),
      (r.pureAirAndBluffsPct, const Color(0xFF6B7280), 'Bluffs'),
    ];
    final polar = r.nutsAndMonstersPct + r.pureAirAndBluffsPct >= 0.8 && r.mediumShowdownPct < 0.15;
    return Row(key: const ValueKey('range-bar'), children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Row(children: [
            for (final (p, col, l) in segs)
              if (p > 0.005)
                Expanded(
                  flex: (p * 1000).round().clamp(1, 1000),
                  child: Container(
                    color: col,
                    alignment: Alignment.center,
                    child: FittedBox(child: Text(' $l ${(p * 100).round()}% ', style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900))),
                  ),
                ),
          ]),
        ),
      ),
      if (r.isCapped || polar)
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(r.isCapped ? '[CAPADO]' : '[POLARIZADO]', key: const ValueKey('range-badge'),
              style: TextStyle(color: r.isCapped ? AppColors.amber : AppColors.crimson, fontSize: 10, fontWeight: FontWeight.w900)),
        ),
    ]);
  }
}
