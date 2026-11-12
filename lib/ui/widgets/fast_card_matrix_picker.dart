import 'package:flutter/material.dart' hide Card;

import '../../core/models/game_state.dart';
import '../theme.dart';

/// Teclado matricial 4x13 (4 colores GGPoker). DeadCard_Guard: cartas de Hero/Board bloqueadas (opacity 0.2, sin tap).
class FastCardMatrixPicker extends StatelessWidget {
  const FastCardMatrixPicker({super.key, required this.dead, required this.onPick, this.enabled = true});

  final Set<int> dead;
  final ValueChanged<Card> onPick;
  final bool enabled;

  static const ranks = [Rank.ace, Rank.king, Rank.queen, Rank.jack, Rank.ten, Rank.nine, Rank.eight, Rank.seven, Rank.six, Rank.five, Rank.four, Rank.three, Rank.two];
  static const suits = [Suit.spades, Suit.hearts, Suit.diamonds, Suit.clubs];

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final s in suits)
            Expanded(
              child: Row(children: [
                for (final r in ranks) Expanded(child: _Key(Card(r, s), dead: dead.contains(Card(r, s).id), enabled: enabled, onPick: onPick)),
              ]),
            ),
        ],
      );
}

class _Key extends StatelessWidget {
  const _Key(this.card, {required this.dead, required this.enabled, required this.onPick});
  final Card card;
  final bool dead, enabled;
  final ValueChanged<Card> onPick;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.suit(card.suit);
    return Opacity(
      opacity: dead ? 0.2 : 1,
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: Material(
          color: c.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(5),
          child: InkWell(
            key: ValueKey('fcm-$card'),
            borderRadius: BorderRadius.circular(5),
            onTap: dead || !enabled ? null : () => onPick(card),
            child: Center(
              child: FittedBox(
                child: Text('${card.rank.symbol}${AppColors.suitGlyph(card.suit)}',
                    style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
