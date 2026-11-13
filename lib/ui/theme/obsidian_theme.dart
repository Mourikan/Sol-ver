import 'package:flutter/material.dart';

/// Monochrome Titanium (Fase 13.0): cero colores saturados; jerarquía por luminancia + cifras tabulares.
class Obsidian {
  Obsidian._();

  static const bgPrimary = Color(0xFF0C0D10);
  static const surfacePanel = Color(0xFF15171C);
  static const borderFine = Color(0xFF262932);
  static const buttonDefault = Color(0xFF1E2128);
  static const buttonDefaultText = Color(0xFFF3F4F6);
  static const buttonActive = Color(0xFFE2E8F0);
  static const buttonActiveText = Color(0xFF0C0D10);
  static const textPrimary = Color(0xFFF8FAFC);
  static const textSecondary = Color(0xFF94A3B8);
  static const textMuted = Color(0xFF64748B);

  /// Escala plata de 4 intensidades (rango percibido).
  static const rangeScale = [Color(0xFFF8FAFC), Color(0xFFCBD5E1), Color(0xFF64748B), Color(0xFF334155)];

  // Alias heredados (todos monocromos).
  static const bgCanvas = bgPrimary;
  static const surfaceCard = surfacePanel;
  static const bevelTop = borderFine;
  static const bevelBottom = borderFine;
  static const emeraldRaise = buttonActive;
  static const cyanCall = buttonDefault;
  static const amberCheck = buttonDefault;
  static const crimsonFold = buttonDefault;
  static const violetExploit = textSecondary;
  static const text = textPrimary;
  static const muted = textSecondary;

  /// Texto legible sobre [bg]: inversión limpia (oscuro sobre titanio, claro sobre grafito).
  static Color onColor(Color bg) => bg.computeLuminance() > .4 ? buttonActiveText : buttonDefaultText;

  /// true si el color es acromático / casi gris (saturación HSL baja).
  static bool isMonochrome(Color c) => HSLColor.fromColor(c).saturation < .4 || HSLColor.fromColor(c).lightness > .9;

  static const tabular = [FontFeature.tabularFigures()];

  /// Estilo numérico: los contadores (bb, %, EV, SPR, Pot) no desplazan el layout al cambiar.
  static TextStyle num({double size = 12, Color color = text, FontWeight weight = FontWeight.w800}) =>
      TextStyle(fontSize: size, color: color, fontWeight: weight, fontFeatures: tabular);

  /// Panel con bisel de 1px (gradiente lineal #2A3446 -> #141A24) sin blur.
  static BoxDecoration card({double radius = 10, Color? glow}) => BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [bevelTop, bevelBottom]),
    boxShadow: glow == null ? null : [BoxShadow(color: glow.withValues(alpha: .35), blurRadius: 8)],
  );

  /// Contenido interior del panel (1px dentro del bisel).
  static BoxDecoration inner({double radius = 9}) => BoxDecoration(color: surfaceCard, borderRadius: BorderRadius.circular(radius));

  /// Panel biselado listo para usar.
  static Widget panel({required Widget child, double radius = 10, EdgeInsets padding = const EdgeInsets.all(6), Color? glow, Key? key}) => Container(
    key: key,
    decoration: card(radius: radius, glow: glow),
    padding: const EdgeInsets.all(1),
    child: Container(
      decoration: inner(radius: radius - 1),
      padding: padding,
      child: child,
    ),
  );
}
