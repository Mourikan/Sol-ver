import 'package:flutter/material.dart';

import '../../application/hand_flow_fsm.dart';
import '../../core/models/decision_output.dart';
import '../theme.dart';
import '../theme/obsidian_theme.dart';
import 'peek_169_heatmap.dart';

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
        Obsidian.panel(
          key: const ValueKey('oracle'),
          glow: c,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(_label(d), key: const ValueKey('oracle-action'), style: Obsidian.num(size: 24, color: c, weight: FontWeight.w900)),
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
                style: Obsidian.num(size: 12, weight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 3),
            EvMicroBar(raise: ev['betRaise'], passive: ev['call'] ?? ev['check'], passiveLabel: ev.containsKey('call') ? 'CALL' : 'CHECK'),
          ]),
        ),
        // ⏱️ Timebank de 12s (entrenamiento de velocidad): reinicia en cada nueva decisión de Hero.
        if (fsm.currentActor == fsm.heroPosition)
          TweenAnimationBuilder<double>(
            key: ValueKey('timebank-${fsm.actions.length}-${fsm.board.length}'),
            tween: Tween(begin: 1, end: 0),
            duration: const Duration(seconds: 12),
            builder: (context, v, _) => SizedBox(
              key: const ValueKey('timebank'),
              height: 12,
              child: Row(children: [
                Text('⏱️ ${(v * 12).ceil().toString().padLeft(2)}s ', style: Obsidian.num(size: 9, color: v < .25 ? Obsidian.crimsonFold : Obsidian.muted)),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: v,
                      minHeight: 3,
                      backgroundColor: Obsidian.bevelBottom,
                      color: v < .25 ? Obsidian.crimsonFold : Obsidian.amberCheck,
                    ),
                  ),
                ),
              ]),
            ),
          ),
        if (d.runoutForecast != null) ...[
          const SizedBox(height: 3),
          SizedBox(height: 18, child: RunoutStrip(d.runoutForecast!)),
        ],
        const SizedBox(height: 4),
        if (r != null && r.totalActiveCombos > 0) ...[
          SizedBox(
            height: 18,
            child: Row(children: [
              Expanded(child: RangeBar(r)),
              const SizedBox(width: 4),
              InkWell(
                key: const ValueKey('peek-169'),
                onTap: r.classWeights.isEmpty ? null : () => Peek169Heatmap.show(context, r.classWeights),
                onLongPress: r.classWeights.isEmpty ? null : () => Peek169Heatmap.show(context, r.classWeights),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Obsidian.violetExploit.withValues(alpha: .15), borderRadius: BorderRadius.circular(4), border: Border.all(color: Obsidian.violetExploit)),
                  child: const Text('🔍 13x13', style: TextStyle(color: Obsidian.violetExploit, fontSize: 10, fontWeight: FontWeight.w900)),
                ),
              ),
            ]),
          ),
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

/// Tira predictiva de la siguiente calle: 🟢 seguir apostando | 🟡 controlar | 🔴 frenar.
class RunoutStrip extends StatelessWidget {
  const RunoutStrip(this.f, {super.key});
  final RunoutForecast f;

  @override
  Widget build(BuildContext context) {
    Widget chip(String icon, String title, List<String> cards, Color c) => Expanded(
          child: Container(
            margin: const EdgeInsets.only(right: 3),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(4), border: Border.all(color: c.withValues(alpha: .6))),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text('$icon $title: ${cards.isEmpty ? '—' : cards.join(',')}', style: Obsidian.num(size: 10, color: c)),
            ),
          ),
        );
    return Row(key: const ValueKey('runout-strip'), children: [
      chip('🟢', 'Kill', f.barrelKillCards, Obsidian.emeraldRaise),
      chip('🟡', 'Freno', f.potControlCards, Obsidian.amberCheck),
      chip('🔴', 'Peligro', f.abortDangerCards, Obsidian.crimsonFold),
    ]);
  }
}

/// Termómetro comparativo de EV: RAISE vs CALL/CHECK vs FOLD con el margen de dominancia (+Δ EV).
class EvMicroBar extends StatelessWidget {
  const EvMicroBar({super.key, this.raise, this.passive, this.passiveLabel = 'CALL'});
  final double? raise, passive;
  final String passiveLabel;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, double, Color)>[
      if (raise != null) ('RAISE', raise!, Obsidian.emeraldRaise),
      if (passive != null) (passiveLabel, passive!, passiveLabel == 'CALL' ? Obsidian.cyanCall : Obsidian.amberCheck),
      ('FOLD', 0.0, Obsidian.crimsonFold),
    ];
    final vals = [for (final r in rows) r.$2];
    final mx = vals.reduce((a, b) => a > b ? a : b), mn = vals.reduce((a, b) => a < b ? a : b);
    final sorted = [...vals]..sort((a, b) => b.compareTo(a));
    final dom = sorted.length > 1 ? sorted[0] - sorted[1] : 0.0;
    final span = (mx - mn).abs() < 1e-9 ? 1.0 : mx - mn;
    return Column(key: const ValueKey('ev-microbar'), children: [
      for (final (l, v, col) in rows)
        SizedBox(
          height: 11,
          child: Row(children: [
            SizedBox(width: 44, child: Text(l, style: Obsidian.num(size: 9, color: v == mx ? col : Obsidian.muted, weight: FontWeight.w900))),
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                final f = ((v - mn) / span).clamp(0.04, 1.0);
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: c.maxWidth * f,
                    height: 6,
                    decoration: BoxDecoration(color: v == mx ? col : col.withValues(alpha: .35), borderRadius: BorderRadius.circular(3)),
                  ),
                );
              }),
            ),
            SizedBox(
              width: 92,
              child: Text('${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)} bb${v == mx && dom > 0 ? ' (+${dom.toStringAsFixed(2)})' : ''}',
                  textAlign: TextAlign.right, style: Obsidian.num(size: 9, color: v == mx ? col : Obsidian.muted)),
            ),
          ]),
        ),
    ]);
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
