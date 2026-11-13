import 'package:flutter/material.dart' hide Card;

import '../core/models/cards.dart';

class AppColors {
  AppColors._();
  // Monochrome Titanium (Fase 13.0): sin verdes/azules/ámbar/violetas.
  static const bg = Color(0xFF0C0D10);
  static const surface = Color(0xFF15171C);
  static const surfaceHi = Color(0xFF1E2128);
  static const text = Color(0xFFF8FAFC);
  static const muted = Color(0xFF94A3B8);
  static const faint = Color(0xFF64748B);
  static const accent = Color(0xFFE2E8F0);
  static const turn = Color(0xFFCBD5E1);
  static const danger = Color(0xFFCBD5E1);
  static const raise = Color(0xFFE2E8F0);
  static const call = Color(0xFF94A3B8);

  static const border = Color(0xFF262932);
  static const emerald = Color(0xFFE2E8F0);
  static const cyan = Color(0xFF94A3B8);
  static const amber = Color(0xFFCBD5E1);
  static const crimson = Color(0xFFCBD5E1);
  static const violet = Color(0xFF94A3B8);

  /// Palos en 4 intensidades de plata (el glifo distingue el palo; cero color).
  static Color suit(Suit s) => switch (s) {
    Suit.spades => const Color(0xFFF8FAFC),
    Suit.hearts => const Color(0xFFCBD5E1),
    Suit.diamonds => const Color(0xFF94A3B8),
    Suit.clubs => const Color(0xFFE2E8F0),
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
  colorScheme: const ColorScheme.dark(primary: AppColors.accent, onPrimary: Color(0xFF0C0D10), surface: AppColors.surface, error: AppColors.danger),
  useMaterial3: true,
  visualDensity: VisualDensity.standard, // targets táctiles >= 44dp (Fase 16.5)
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
          : Text(
              '${c.rank.symbol}${AppColors.suitGlyph(c.suit)}',
              style: TextStyle(color: AppColors.suit(c.suit), fontWeight: FontWeight.w800, fontSize: size * .42),
            ),
    );
  }
}
