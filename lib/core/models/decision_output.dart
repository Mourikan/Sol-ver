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

/// Origen de la distribución de frecuencias.
enum FreqSource { pure, modelCalibrated, solverImport, bootstrapGTO }

class DecisionOutput {
  const DecisionOutput({
    required this.action,
    this.sizing,
    this.freqGto,
    this.freqSource = FreqSource.pure,
    this.roll,
    this.actionEVs,
    this.heuristicAction,
    this.exploitDeltaEV,
    this.metrics = const [],
    required this.justificacionGto,
    required this.ajusteExplotativoRead,
  });

  final DecisionAction action;
  final Sizing? sizing;

  /// Distribución {acción: frecuencia}; null = estrategia pura sobre [action].
  final Map<DecisionAction, double>? freqGto;
  final FreqSource freqSource;

  /// Roll determinista 0..99 usado por el mezclador (null si la acción es pura).
  final int? roll;

  /// EV aproximado (bb) por acción legal: {fold, check|call, betRaise}.
  final Map<String, double>? actionEVs;

  /// Acción de la heurística antes de la puerta de EV (null si no hubo corrección).
  final DecisionAction? heuristicAction;

  /// EV_Exploit - EV_GTO (bb) de la línea elegida frente a la línea base Reg_GTO, ambas bajo el perfil asumido.
  /// null en modo Reg_GTO (sin desviación posible).
  final double? exploitDeltaEV;
  final List<KeyMetric> metrics;
  final String justificacionGto;
  final String ajusteExplotativoRead;

  /// Nunca null: estrategia pura => {action: 1.0}.
  Map<DecisionAction, double> get frequencies => freqGto ?? {action: 1.0};

  DecisionAction get majorityAction => frequencies.entries.reduce((a, b) => b.value > a.value ? b : a).key;

  DecisionOutput copyWith({DecisionAction? action, Sizing? sizing, String? ajusteExplotativoRead, List<KeyMetric>? metrics,
          Map<DecisionAction, double>? freqGto, FreqSource? freqSource, Map<String, double>? actionEVs, DecisionAction? heuristicAction,
          bool clearSizing = false, double? exploitDeltaEV}) =>
      DecisionOutput(
        action: action ?? this.action,
        sizing: clearSizing ? null : (sizing ?? this.sizing),
        freqGto: freqGto ?? this.freqGto,
        freqSource: freqSource ?? this.freqSource,
        roll: roll,
        actionEVs: actionEVs ?? this.actionEVs,
        heuristicAction: heuristicAction ?? this.heuristicAction,
        exploitDeltaEV: exploitDeltaEV ?? this.exploitDeltaEV,
        metrics: metrics ?? this.metrics,
        justificacionGto: justificacionGto,
        ajusteExplotativoRead: ajusteExplotativoRead ?? this.ajusteExplotativoRead,
      );

  Map<String, Object?> toJson() => {
        'accion': action.name,
        'sizing_bb_o_pct': sizing?.toJson(),
        'freq_gto': {for (final e in frequencies.entries) e.key.name: double.parse((e.value * 100).toStringAsFixed(1))},
        'accion_mayoritaria': majorityAction.name,
        'freq_source': freqSource.name,
        if (actionEVs != null) 'action_evs_bb': actionEVs,
        if (exploitDeltaEV != null) 'exploit_delta_ev_bb': exploitDeltaEV,
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
