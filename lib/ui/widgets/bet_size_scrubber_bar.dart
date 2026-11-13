import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/obsidian_theme.dart';

/// Barra Deslizadora Universal (Fase 13.0): `1.0bb ◄───●───► Stack` en pasos de 0.5bb con háptica suave por paso.
/// Geometría fija: altura constante en preflop y postflop (memoria muscular).
class BetSizeScrubberBar extends StatelessWidget {
  const BetSizeScrubberBar({super.key, required this.value, required this.max, required this.onChanged, this.min = 1.0, this.potBb});
  final double value;
  final double min;
  final double max;
  final double? potBb;
  final ValueChanged<double> onChanged;

  static const step = 0.5;
  static const height = 44.0;

  static double snap(double x) => (x / step).roundToDouble() * step;

  void _set(double x) {
    final v = snap(x).clamp(min, max).toDouble();
    if (v != value) {
      HapticFeedback.selectionClick();
      onChanged(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hi = max <= min ? min + step : max;
    final v = value.clamp(min, hi).toDouble();
    final pct = potBb == null || potBb! <= 0 ? '' : ' · ${(v / potBb! * 100).round()}%';
    Widget arrow(String k, String g, double d) => SizedBox(
      width: 40,
      height: height,
      child: TextButton(
        key: ValueKey(k),
        style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: Obsidian.textPrimary),
        onPressed: () => _set(v + d),
        child: Text(g, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      ),
    );
    return SizedBox(
      key: const ValueKey('scrubber'),
      height: height,
      child: Row(
        children: [
          Text(
            '${min.toStringAsFixed(1)}bb',
            style: Obsidian.num(size: 11, color: Obsidian.textMuted, weight: FontWeight.w600),
          ),
          arrow('scrub-minus', '◄', -step),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Obsidian.buttonActive,
                inactiveTrackColor: Obsidian.borderFine,
                thumbColor: Obsidian.buttonActive,
                overlayColor: Obsidian.buttonActive.withValues(alpha: .12),
                trackHeight: 3,
              ),
              child: Slider(key: const ValueKey('scrub-slider'), value: v, min: min, max: hi, onChanged: _set),
            ),
          ),
          arrow('scrub-plus', '►', step),
          SizedBox(
            width: 74,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text('${v.toStringAsFixed(1)}bb$pct', key: const ValueKey('scrub-value'), style: Obsidian.num(size: 13)),
            ),
          ),
        ],
      ),
    );
  }
}
