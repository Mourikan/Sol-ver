import 'package:flutter/foundation.dart';

import '../core/models/decision_output.dart';
import 'hand_flow_fsm.dart';
import 'linear_hand_flow.dart';
import 'solver_controller.dart';

/// Mesa independiente: FSM + flujo lineal + controlador propio (estado, breadcrumb y perfiles HUD aislados).
class TableSlot {
  TableSlot(this.label, {LinearHandFlow? flow, SolverController? controller})
    : flow = flow ?? LinearHandFlow(),
      controller = controller ?? SolverController(executor: InlineExecutor());

  final String label;
  final LinearHandFlow flow;
  final SolverController controller;
  HandFlowFSM get fsm => flow.fsm;

  /// Resumen del tab: `{HeroCards} • {Street} • {LastRecommendation}`.
  String get summary {
    final cards = fsm.heroCards.length == 2 ? '${fsm.heroCards[0]}${fsm.heroCards[1]}' : '--';
    final street = fsm.phase == HandPhase.setup ? 'Setup' : fsm.street.name[0].toUpperCase() + fsm.street.name.substring(1);
    final d = flow.lastHero;
    final rec = d == null
        ? '—'
        : switch (d.action) {
            DecisionAction.fold => 'Fold',
            DecisionAction.check => 'Check',
            DecisionAction.call => 'Call',
            DecisionAction.betRaise => d.sizing == null ? 'Raise' : 'Raise ${d.sizing!.bb.toStringAsFixed(1)}bb',
          };
    return '$cards • $street • $rec';
  }
}

/// Arquitectura Dual-Table (Rush & Cash): 2 mesas en memoria, cambio instantáneo sin perder estado.
class DualTableSessionManager extends ChangeNotifier {
  DualTableSessionManager({LinearHandFlow? flowA, LinearHandFlow? flowB})
    : tableSlotA = TableSlot('MESA 1', flow: flowA),
      tableSlotB = TableSlot('MESA 2', flow: flowB) {
    for (final s in slots) {
      s.flow.addListener(notifyListeners);
    }
  }

  final TableSlot tableSlotA;
  final TableSlot tableSlotB;
  List<TableSlot> get slots => [tableSlotA, tableSlotB];

  int activeIndex = 0;
  TableSlot get active => slots[activeIndex];

  void switchTo(int i) {
    if (i == activeIndex || i < 0 || i > 1) return;
    activeIndex = i;
    notifyListeners();
  }

  /// [⚡ Rush Reset]: reinicia SOLO esa mesa (mano nueva, misma posición); la otra queda intacta.
  void rushReset(int i) => slots[i].flow.newHand();

  @override
  void dispose() {
    for (final s in slots) {
      s.flow.removeListener(notifyListeners);
      s.controller.dispose();
    }
    super.dispose();
  }
}
