import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/obsidian_theme.dart';

/// Barra Deslizadora de Alta Precisión (Fase 19.5): `min ◄───●───► techo` en pasos EXACTOS de 0.5bb.
/// Damped Contextual Range: el recorrido cubre solo `[min, clamp(bote x 2.2, min + 12, stack)]` (~4x más lenta);
/// el chip [Stack / All-In] expande el techo al stack completo. Auto-commit al soltar (`onChangeEnd`).
class BetSizeScrubberBar extends StatefulWidget {
  const BetSizeScrubberBar({
    super.key,
    required this.value,
    required this.max,
    required this.onChanged,
    this.onCommit,
    this.arrowsCommit = true,
    this.min = 1.0,
    this.potBb,
    this.rangePotBb,
  });
  final double value;
  final double min;

  /// Techo absoluto (stack del asiento).
  final double max;

  /// Bote para mostrar el % (postflop).
  final double? potBb;

  /// Bote de referencia para la ventana contextual fina (si null => potBb o 3x el valor).
  final double? rangePotBb;
  final ValueChanged<double> onChanged;

  /// Zero_Apply_Button: se dispara al SOLTAR el deslizador (y en cada flecha si [arrowsCommit]).
  final ValueChanged<double>? onCommit;
  final bool arrowsCommit;

  static const step = 0.5;
  static const height = 46.0;

  static double snap(double x) => (x / step).roundToDouble() * step;

  /// Techo de la ventana contextual: clamp(bote x 2.2, min + 12, stack).
  static double contextualMax({required double min, required double max, required double pot}) {
    final lo = min + 12.0, raw = pot * 2.2;
    final c = raw < lo ? lo : raw;
    return snap(c > max ? max : c);
  }

  @override
  State<BetSizeScrubberBar> createState() => _BetSizeScrubberBarState();
}

class _BetSizeScrubberBarState extends State<BetSizeScrubberBar> {
  bool _expanded = false;

  double get _hi {
    final w = widget;
    final abs = w.max <= w.min ? w.min + BetSizeScrubberBar.step : w.max;
    if (_expanded) return abs;
    final c = BetSizeScrubberBar.contextualMax(min: w.min, max: abs, pot: w.rangePotBb ?? w.potBb ?? w.value * 3);
    final hi = w.value > c ? BetSizeScrubberBar.snap(w.value) : c;
    return hi <= w.min ? w.min + BetSizeScrubberBar.step : (hi > abs ? abs : hi);
  }

  void _set(double x) {
    final v = BetSizeScrubberBar.snap(x).clamp(widget.min, _expanded ? widget.max : _hi).toDouble();
    if (v != widget.value) {
      HapticFeedback.selectionClick();
      widget.onChanged(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final hi = _hi;
    final v = w.value.clamp(w.min, hi).toDouble();
    final pct = w.potBb == null || w.potBb! <= 0 ? '' : ' · ${(v / w.potBb! * 100).round()}%';
    final divisions = ((hi - w.min) / BetSizeScrubberBar.step).round();
    Widget arrow(String k, String g, double d) => SizedBox(
      width: 46,
      height: BetSizeScrubberBar.height,
      child: TextButton(
        key: ValueKey(k),
        style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: Obsidian.textPrimary),
        onPressed: () {
          final nv = BetSizeScrubberBar.snap(v + d).clamp(w.min, w.max).toDouble();
          if (nv > hi) setState(() => _expanded = true);
          _set(nv);
          if (w.arrowsCommit) w.onCommit?.call(nv);
        },
        child: Text(g, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      ),
    );
    final canExpand = !_expanded && hi < w.max - 1e-9;
    return Column(
      key: const ValueKey('scrubber'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: BetSizeScrubberBar.height,
          child: Row(
            children: [
              arrow('scrub-minus', '◄', -BetSizeScrubberBar.step),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Obsidian.buttonActive,
                    inactiveTrackColor: Obsidian.borderFine,
                    thumbColor: Obsidian.buttonActive,
                    overlayColor: Obsidian.buttonActive.withValues(alpha: .12),
                    trackHeight: 3,
                    showValueIndicator: ShowValueIndicator.never,
                  ),
                  child: Slider(
                    key: const ValueKey('scrub-slider'),
                    value: v,
                    min: w.min,
                    max: hi,
                    divisions: divisions < 1 ? 1 : divisions,
                    onChanged: _set,
                    onChangeEnd: (x) => w.onCommit?.call(BetSizeScrubberBar.snap(x).clamp(w.min, hi).toDouble()),
                  ),
                ),
              ),
              arrow('scrub-plus', '►', BetSizeScrubberBar.step),
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
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                '${w.min.toStringAsFixed(1)} – ${hi.toStringAsFixed(1)} bb · paso 0.5',
                key: const ValueKey('scrub-range'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Obsidian.num(size: 11, color: Obsidian.textMuted, weight: FontWeight.w600),
              ),
            ),
            if (canExpand)
              SizedBox(
                height: 46,
                child: TextButton(
                  key: const ValueKey('scrub-expand'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 46), foregroundColor: Obsidian.textSecondary),
                  onPressed: () => setState(() => _expanded = true),
                  child: Text('${w.max.toStringAsFixed(0)}bb / All-In', maxLines: 1, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
