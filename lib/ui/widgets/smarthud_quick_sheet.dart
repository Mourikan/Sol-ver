import 'package:flutter/material.dart';

import '../../application/hand_flow_fsm.dart';
import '../../core/models/game_state.dart';
import '../../core/reads/gg_smarthud_analyzer.dart';
import '../../core/reads/villain_archetypes.dart';
import '../theme.dart';

/// Panel HUD por asiento: 1-tap etiqueta, steppers GGPoker (-5/+5) con diagnóstico en vivo y timing de la calle actual.
class SmartHudQuickSheet extends StatefulWidget {
  const SmartHudQuickSheet({super.key, required this.fsm, required this.seat});
  final HandFlowFSM fsm;
  final Position seat;

  static Future<void> show(BuildContext context, HandFlowFSM fsm, Position seat) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppColors.surface,
        isScrollControlled: true,
        builder: (_) => SmartHudQuickSheet(fsm: fsm, seat: seat),
      );

  static const tagColors = {
    VillainTag.fishStation: AppColors.call,
    VillainTag.nitPassive: AppColors.muted,
    VillainTag.scaredReg: AppColors.turn,
    VillainTag.agroManiac: AppColors.danger,
    VillainTag.trapper: AppColors.raise,
    VillainTag.poolDefault: AppColors.accent,
  };

  static const timings = [
    (TimingTell.none, 'Normal'),
    (TimingTell.instaAction, '⚡ Insta-Check'),
    (TimingTell.instaAction, '⚡ Insta-Call'),
    (TimingTell.longTank, '⏳ Tank-Bet'),
  ];

  @override
  State<SmartHudQuickSheet> createState() => _SmartHudQuickSheetState();
}

class _SmartHudQuickSheetState extends State<SmartHudQuickSheet> {
  late SmartHudStats stats;
  VillainTag? manual;
  late SmartHudDeviation dev;
  int timingIdx = 0;

  @override
  void initState() {
    super.initState();
    final prev = widget.fsm.seats[widget.seat]?.hud;
    stats = prev?.stats ?? SmartHudStats.preset(VillainTag.poolDefault);
    manual = prev != null && !prev.autoInferred ? prev.tag : null;
    dev = GgSmartHudAnalyzer.analyze(stats, manualTag: manual);
  }

  void _apply() {
    dev = widget.fsm.setHud(widget.seat, stats, manualTag: manual) ?? GgSmartHudAnalyzer.analyze(stats, manualTag: manual);
    setState(() {});
  }

  void _tag(VillainTag t) {
    manual = t;
    stats = SmartHudStats.preset(t);
    _apply();
  }

  void _step(String k, double d) {
    double c(double x) => (x + d).clamp(0, 100).toDouble();
    stats = switch (k) {
      'VPIP' => stats.copyWith(vpip: c(stats.vpip)),
      'PFR' => stats.copyWith(pfr: c(stats.pfr)),
      '3Bet' => stats.copyWith(threeBet: c(stats.threeBet)),
      _ => stats.copyWith(ats: c(stats.ats)),
    };
    manual = null; // los stats mandan al moverlos (re-inferencia en vivo)
    _apply();
  }

  @override
  Widget build(BuildContext context) {
    final values = {'VPIP': stats.vpip, 'PFR': stats.pfr, '3Bet': stats.threeBet, 'ATS': stats.ats};
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('SmartHUD ${widget.seat.name.toUpperCase()}',
              style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in VillainTag.values)
              _Chip(VillainArchetypes.of(t).label, SmartHudQuickSheet.tagColors[t]!, dev.tag == t, () => _tag(t),
                  key: ValueKey('hud-tag-${t.name}')),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            for (final e in values.entries)
              Expanded(child: _Stepper(e.key, e.value, (d) => _step(e.key, d), key: ValueKey('hud-step-${e.key}'))),
          ]),
          const SizedBox(height: 8),
          Container(
            key: const ValueKey('hud-badge'),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: SmartHudQuickSheet.tagColors[dev.tag]!.withValues(alpha: .12), borderRadius: BorderRadius.circular(8)),
            child: Text(dev.badge, style: TextStyle(color: SmartHudQuickSheet.tagColors[dev.tag], fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 10),
          Row(children: [
            for (var i = 0; i < SmartHudQuickSheet.timings.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _Chip(SmartHudQuickSheet.timings[i].$2, AppColors.turn, timingIdx == i, () {
                    widget.fsm.setTiming(widget.seat, SmartHudQuickSheet.timings[i].$1);
                    setState(() => timingIdx = i);
                  }, key: ValueKey('hud-timing-$i')),
                ),
              ),
          ]),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, this.color, this.selected, this.onTap, {super.key});
  final String text;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: .22) : Colors.transparent,
            border: Border.all(color: color.withValues(alpha: selected ? 1 : .5)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
        ),
      );
}

class _Stepper extends StatelessWidget {
  const _Stepper(this.label, this.value, this.onStep, {super.key});
  final String label;
  final double value;
  final ValueChanged<double> onStep;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
        Text(value.toStringAsFixed(value % 1 == 0 ? 0 : 1),
            style: const TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800)),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _btn('-5', () => onStep(-5)),
          const SizedBox(width: 4),
          _btn('+5', () => onStep(5)),
        ]),
      ]);

  Widget _btn(String t, VoidCallback f) => InkWell(
        onTap: f,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(color: AppColors.surfaceHi, borderRadius: BorderRadius.circular(6)),
          child: Text(t, style: const TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      );
}
