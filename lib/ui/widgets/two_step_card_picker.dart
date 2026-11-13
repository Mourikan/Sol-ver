import 'package:flutter/material.dart' hide Card;

import '../../core/models/game_state.dart';
import '../theme.dart';

/// Selector ergonómico de 2 toques: Rango (13 botones grandes) -> Palo (4 botones grandes, cartas usadas bloqueadas).
class TwoStepCardPicker extends StatefulWidget {
  const TwoStepCardPicker({super.key, required this.dead, required this.onPick, this.title = 'Elige carta'});
  final Set<int> dead;
  final ValueChanged<Card> onPick;
  final String title;

  static const ranks = [Rank.ace, Rank.king, Rank.queen, Rank.jack, Rank.ten, Rank.nine, Rank.eight, Rank.seven, Rank.six, Rank.five, Rank.four, Rank.three, Rank.two];
  static const suits = [(Suit.spades, 'Picas'), (Suit.hearts, 'Corazones'), (Suit.diamonds, 'Diamantes'), (Suit.clubs, 'Tréboles')];

  @override
  State<TwoStepCardPicker> createState() => _TwoStepCardPickerState();
}

class _TwoStepCardPickerState extends State<TwoStepCardPicker> {
  Rank? rank;

  bool _rankAvailable(Rank r) => Suit.values.any((s) => !widget.dead.contains(Card(r, s).id));

  @override
  Widget build(BuildContext context) {
    final r = rank;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(r == null ? '${widget.title}: rango' : '${widget.title}: palo de ${r.symbol}',
            key: const ValueKey('picker-title'), style: const TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
      if (r == null)
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final x in TwoStepCardPicker.ranks)
            _Big(
              x.symbol,
              key: ValueKey('rank-${x.symbol}'),
              onTap: _rankAvailable(x) ? () => setState(() => rank = x) : null,
            ),
        ])
      else
        Row(children: [
          for (final (su, name) in TwoStepCardPicker.suits)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _Big(
                  '${AppColors.suitGlyph(su)}\n$name',
                  key: ValueKey('suit-${su.symbol}'),
                  color: AppColors.suit(su),
                  height: 64,
                  onTap: widget.dead.contains(Card(r, su).id)
                      ? null
                      : () {
                          setState(() => rank = null);
                          widget.onPick(Card(r, su));
                        },
                ),
              ),
            ),
          SizedBox(width: 56, child: _Big('↩', key: const ValueKey('rank-back'), height: 64, onTap: () => setState(() => rank = null))),
        ]),
    ]);
  }
}

class _Big extends StatelessWidget {
  const _Big(this.label, {super.key, this.onTap, this.color = AppColors.text, this.height = 52});
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: height == 52 ? 52 : null,
        height: height,
        child: Material(
          color: onTap == null ? AppColors.bg : AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppColors.border)),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Center(
              child: Opacity(
                opacity: onTap == null ? .25 : 1,
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: color, fontSize: height == 52 ? 20 : 15, fontWeight: FontWeight.w800, height: 1.15)),
              ),
            ),
          ),
        ),
      );
}
