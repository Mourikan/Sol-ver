enum DecisionAction { fold, check, call, betRaise }

class Sizing {
  const Sizing({required this.bb, required this.potPct});
  final double bb;
  final double potPct;

  Map<String, Object> toJson() => {'bb': bb, 'pot_pct': potPct};
}

enum MetricType { spr, potOdds, requiredEquity, equity, eqr, blocker, mdf, alpha, bluffShare, valueShare, rangeActionFreq, rangeAdvantage, nutAdvantage }

class KeyMetric {
  const KeyMetric(this.type, this.value, [this.label]);
  final MetricType type;
  final double value;
  final String? label;

  Map<String, Object?> toJson() =>
      {'type': type.name, 'value': value, if (label != null) 'label': label};
}

class DecisionOutput {
  const DecisionOutput({
    required this.action,
    this.sizing,
    this.freqGto,
    this.metrics = const [],
    required this.justificacionGto,
    required this.ajusteExplotativoRead,
  });

  final DecisionAction action;
  final Sizing? sizing;

  /// Solo poblado desde datos importados de solver; null = sin frecuencia verificable.
  final double? freqGto;
  final List<KeyMetric> metrics;
  final String justificacionGto;
  final String ajusteExplotativoRead;

  Map<String, Object?> toJson() => {
        'accion': action.name,
        'sizing_bb_o_pct': sizing?.toJson(),
        'freq_gto': freqGto,
        'metricas': [for (final m in metrics) m.toJson()],
        'justificacion_gto': justificacionGto,
        'ajuste_explotativo_read': ajusteExplotativoRead,
      };
}

class MissingInputs implements Exception {
  const MissingInputs(this.fields);
  final List<String> fields;
  @override
  String toString() => 'Faltan variables: ${fields.join(', ')}';
}
