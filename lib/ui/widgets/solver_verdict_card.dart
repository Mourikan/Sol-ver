import 'package:flutter/material.dart';

import '../../application/hand_flow_fsm.dart';
import '../../core/models/decision_output.dart';
import '../theme.dart';

/// Panel HUD de decisión óptima de Hero.
class SolverVerdictCard extends StatelessWidget {
  const SolverVerdictCard({super.key, required this.fsm, required this.onExecute});
  final HandFlowFSM fsm;
  final VoidCallback onExecute;

  static String label(DecisionOutput d) {
    final a = switch (d.action) {
      DecisionAction.fold => 'FOLD',
      DecisionAction.check => 'CHECK',
      DecisionAction.call => 'CALL',
      DecisionAction.betRaise => 'BET / RAISE',
    };
    final s = d.sizing;
    return s == null ? a : '$a ${s.bb.toStringAsFixed(2)}bb (${s.potPct.toStringAsFixed(0)}% pot)';
  }

  String _metric(DecisionOutput d, MetricType t) {
    final m = d.metrics.where((x) => x.type == t).firstOrNull;
    return m == null ? '—' : '${(m.value * 100).toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    final d = fsm.activeRecommendation;
    final err = fsm.recommendationError;
    if (d == null && err == null) return const SizedBox.shrink();
    final color = d == null
        ? AppColors.danger
        : switch (d.action) {
            DecisionAction.fold => AppColors.danger,
            DecisionAction.check => AppColors.muted,
            DecisionAction.call => AppColors.call,
            DecisionAction.betRaise => AppColors.raise,
          };
    return Container(
      key: const ValueKey('verdict'),
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: 2),
      ),
      child: d == null
          ? Text('Faltan datos: $err', style: const TextStyle(color: AppColors.danger))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(label(d), style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w900)),
                ),
                Text('Freq: ${d.frequencies.entries.map((e) => '${e.key.name} ${(e.value * 100).round()}%').join(' / ')} (${d.freqSource.name})  ·  ${fsm.solverMicros}µs',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(spacing: 10, runSpacing: 2, children: [
                  _kv('MDF', _metric(d, MetricType.mdf)),
                  _kv('Pot odds', _metric(d, MetricType.potOdds)),
                  _kv('SPR', fsm.spr == null ? '—' : fsm.spr!.toStringAsFixed(1)),
                  _kv('Funnel', fsm.villainFunnelState?.name ?? '—'),
                ]),
                const SizedBox(height: 6),
                Text('GTO: ${d.justificacionGto}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.text, fontSize: 12)),
                Text('READ: ${d.ajusteExplotativoRead}', maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: d.ajusteExplotativoRead.contains('SANITY') ? AppColors.turn : AppColors.accent, fontSize: 12)),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    key: const ValueKey('execute'),
                    style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: AppColors.bg),
                    onPressed: onExecute,
                    child: const Text('Ejecutar Acción Óptima', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _kv(String k, String v) => Text.rich(TextSpan(children: [
        TextSpan(text: '$k ', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        TextSpan(text: v, style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w700)),
      ]));
}
