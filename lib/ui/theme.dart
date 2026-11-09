import 'package:flutter/material.dart' hide Card;

import '../core/models/cards.dart';

class AppColors {
  AppColors._();
  static const bg = Color(0xFF0B0D10);
  static const surface = Color(0xFF151A21);
  static const surfaceHi = Color(0xFF1F2630);
  static const text = Color(0xFFF2F5F8);
  static const muted = Color(0xFF8A96A6);
  static const accent = Color(0xFF00E5A0);
  static const turn = Color(0xFFFFD54A);
  static const danger = Color(0xFFFF5A5F);
  static const raise = Color(0xFFFF9F1C);
  static const call = Color(0xFF3FA7FF);

  static Color suit(Suit s) => switch (s) {
        Suit.spades => const Color(0xFFD9DEE5),
        Suit.hearts => const Color(0xFFFF4D4D),
        Suit.diamonds => const Color(0xFF4DA3FF),
        Suit.clubs => const Color(0xFF3DDC84),
      };

  static String suitGlyph(Suit s) => switch (s) {
        Suit.spades => '♠',
        Suit.hearts => '♥',
        Suit.diamonds => '♦',
        Suit.clubs => '♣',
      };
}

ThemeData buildTheme() => ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(primary: AppColors.accent, surface: AppColors.surface, error: AppColors.danger),
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
    );

class CardChip extends StatelessWidget {
  const CardChip(this.card, {super.key, this.size = 34});
  final Card? card;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = card;
    return Container(
      width: size,
      height: size * 1.3,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c == null ? AppColors.surfaceHi : AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c == null ? AppColors.muted.withValues(alpha: .3) : AppColors.suit(c.suit), width: 1.5),
      ),
      child: c == null
          ? const Text('?', style: TextStyle(color: AppColors.muted))
          : Text('${c.rank.symbol}${AppColors.suitGlyph(c.suit)}',
              style: TextStyle(color: AppColors.suit(c.suit), fontWeight: FontWeight.w800, fontSize: size * .42)),
    );
  }
}
