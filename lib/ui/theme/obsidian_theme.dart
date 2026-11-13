import 'package:flutter/material.dart';

/// Matte Ergonomic Slate (Fase 11.0): tonos mate sin neón + tipografía financiera (cifras tabulares).
class Obsidian {
  Obsidian._();

  static const bgCanvas = Color(0xFF111315);
  static const surfaceCard = Color(0xFF1A1D21);
  static const bevelTop = Color(0xFF2B3036);
  static const bevelBottom = Color(0xFF2B3036);
  static const emeraldRaise = Color(0xFF16A34A);
  static const cyanCall = Color(0xFF2563EB);
  static const amberCheck = Color(0xFFD97706);
  static const crimsonFold = Color(0xFFDC2626);
  static const violetExploit = Color(0xFF7C6FB0);
  static const text = Color(0xFFF1F5F9);
  static const muted = Color(0xFF94A3B8);

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
        child: Container(decoration: inner(radius: radius - 1), padding: padding, child: child),
      );
}
