import 'package:flutter/services.dart';

import '../../core/models/decision_output.dart';

/// Háptica táctica + bloqueo de suspensión de pantalla (canal nativo; no-op si la plataforma no lo implementa).
class TacticalFeedback {
  TacticalFeedback._();

  static const _screen = MethodChannel('sol_ver/screen');
  static String? _lastKey;

  /// Disparo único por recomendación nueva de Hero.
  static Future<void> onDecision(DecisionOutput? d) async {
    if (d == null) {
      _lastKey = null;
      return;
    }
    final key = '${d.action}|${d.sizing?.bb}|${d.justification?.activeCloserRule}|${d.metrics.length}';
    if (key == _lastKey) return;
    _lastKey = key;
    final shutdown = d.justification?.activeCloserRule == 'T2';
    if (d.action == DecisionAction.fold || shutdown) {
      await HapticFeedback.vibrate();
    } else if (d.action == DecisionAction.betRaise) {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 70));
      await HapticFeedback.heavyImpact();
    } else {
      await HapticFeedback.selectionClick();
    }
  }

  static Future<void> tap() => HapticFeedback.lightImpact();

  static Future<void> keepScreenOn(bool on) async {
    try {
      await _screen.invokeMethod<void>('keepOn', on);
    } on MissingPluginException {
      // Plataformas sin el canal (tests, desktop): sin efecto.
    } on PlatformException {
      // Sin efecto.
    }
  }
}
