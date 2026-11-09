import 'package:flutter/material.dart' hide Card;

import '../../core/models/cards.dart';
import '../theme.dart';

/// Matriz 4 palos x 13 rangos con dead cards deshabilitadas.
class CardPickerGrid extends StatelessWidget {
  const CardPickerGrid({super.key, required this.dead, required this.onPick, required this.prompt});
  final Set<int> dead;
  final ValueChanged<Card> onPick;
  final String prompt;

  static const _suits = [Suit.spades, Suit.hearts, Suit.diamonds, Suit.clubs];

  @override
  Widget build(BuildContext context) {
    final ranks = Rank.values.reversed.toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
      color: AppColors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(prompt, style: const TextStyle(color: AppColors.turn, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          for (final s in _suits)
            Row(
              children: [
                for (final r in ranks)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(1.5),
                      child: _CardKey(card: Card(r, s), enabled: !dead.contains(Card(r, s).id), onPick: onPick),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CardKey extends StatelessWidget {
  const _CardKey({required this.card, required this.enabled, required this.onPick});
  final Card card;
  final bool enabled;
  final ValueChanged<Card> onPick;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.suit(card.suit);
    return Material(
      color: enabled ? AppColors.surfaceHi : AppColors.bg,
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        key: ValueKey('card-$card'),
        borderRadius: BorderRadius.circular(5),
        onTap: enabled ? () => onPick(card) : null,
        child: SizedBox(
          height: 40,
          child: Center(
            child: FittedBox(
              child: Text('${card.rank.symbol}${AppColors.suitGlyph(card.suit)}',
                  style: TextStyle(color: enabled ? color : color.withValues(alpha: .18), fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ),
        ),
      ),
    );
  }
}
