import 'package:flutter/material.dart' hide Card;

import '../../core/models/game_state.dart';
import '../theme.dart';

/// Selector ergonómico de 2 toques: Rango (13 botones grandes) -> Palo (4 botones grandes, cartas usadas bloqueadas).
class TwoStepCardPicker extends StatefulWidget {
  const TwoStepCardPicker({super.key, required this.dead, required this.onPick, this.title = 'Elige carta'});
  final Set<int> dead;
  final ValueChanged<Card> onPick;
  final String title;

  static const ranks = [
    Rank.ace,
    Rank.king,
    Rank.queen,
    Rank.jack,
    Rank.ten,
    Rank.nine,
    Rank.eight,
    Rank.seven,
    Rank.six,
    Rank.five,
    Rank.four,
    Rank.three,
    Rank.two,
  ];

  /// Selector puro: solo el símbolo gráfico del palo (cero texto).
  static const suits = [Suit.spades, Suit.hearts, Suit.diamonds, Suit.clubs];

  @override
  State<TwoStepCardPicker> createState() => _TwoStepCardPickerState();
}

class _TwoStepCardPickerState extends State<TwoStepCardPicker> {
  Rank? rank;

  bool _rankAvailable(Rank r) => Suit.values.any((s) => !widget.dead.contains(Card(r, s).id));

  @override
  Widget build(BuildContext context) {
    final r = rank;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            r == null ? '${widget.title}: rango' : '${widget.title}: palo de ${r.symbol}',
            key: const ValueKey('picker-title'),
            style: const TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        if (r == null)
          // Cuadrícula fija 7 + 6 (anchos flexibles): cabe en cualquier móvil sin overflow, misma altura que los palos.
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final row in [TwoStepCardPicker.ranks.sublist(0, 7), TwoStepCardPicker.ranks.sublist(7)])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      for (final x in row)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: _Big(
                              x.symbol,
                              key: ValueKey('rank-${x.symbol}'),
                              height: 52,
                              fontSize: 20,
                              onTap: _rankAvailable(x) ? () => setState(() => rank = x) : null,
                            ),
                          ),
                        ),
                      if (row.length == 6) const Expanded(child: SizedBox()),
                    ],
                  ),
                ),
            ],
          )
        else
          Row(
            children: [
              for (final su in TwoStepCardPicker.suits)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _Big(
                      AppColors.suitGlyph(su),
                      key: ValueKey('suit-${su.symbol}'),
                      color: AppColors.suit(su),
                      height: 110,
                      fontSize: 40,
                      onTap: widget.dead.contains(Card(r, su).id)
                          ? null
                          : () {
                              setState(() => rank = null);
                              widget.onPick(Card(r, su));
                            },
                    ),
                  ),
                ),
              SizedBox(
                width: 52,
                child: _Big('↩', key: const ValueKey('rank-back'), height: 110, fontSize: 20, onTap: () => setState(() => rank = null)),
              ),
            ],
          ),
      ],
    );
  }
}

class _Big extends StatelessWidget {
  const _Big(this.label, {super.key, this.onTap, this.color = AppColors.text, this.height = 52, this.fontSize = 20});
  final String label;
  final double fontSize;
  final VoidCallback? onTap;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Material(
      color: onTap == null ? AppColors.bg : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Center(
          child: Opacity(
            opacity: onTap == null ? .25 : 1,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.w800, height: 1.15),
            ),
          ),
        ),
      ),
    ),
  );
}
