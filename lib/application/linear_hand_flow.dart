import 'package:flutter/foundation.dart';

import '../core/models/decision_output.dart';
import '../core/models/game_state.dart';
import '../core/preflop/preflop_ranges_db.dart';
import 'hand_flow_fsm.dart';

/// Flujo lineal de mínimos toques sobre [HandFlowFSM]: escenarios preflop de 1 toque (fold implícito de los asientos
/// omitidos), AUTO-COMMIT de la acción del solver en el turno de Hero y respuestas del villano en 1 toque.
/// No guarda historial: todo vive en la mano actual.
class LinearHandFlow extends ChangeNotifier {
  LinearHandFlow([HandFlowFSM? fsm]) : fsm = fsm ?? HandFlowFSM() {
    this.fsm.addListener(notifyListeners);
  }

  final HandFlowFSM fsm;

  /// Última decisión del solver para Hero (ya ejecutada automáticamente salvo en modo manual).
  DecisionOutput? lastHero;
  Street? lastHeroStreet;

  /// true => Hero eligió jugar distinto: la FSM espera la acción manual de Hero.
  bool manualMode = false;

  Position get hero => fsm.heroPosition;
  bool get atHeroTurn => fsm.currentActor == hero;
  /// Paso 2 disponible: preflop sin ninguna acción registrada todavía.
  bool get preflopUntouched => fsm.phase == HandPhase.preflop && fsm.actions.isEmpty;

  /// Asientos que actúan antes que Hero en preflop (candidatos a abrir).
  List<Position> get openersBeforeHero {
    final o = HandFlowFSM.preflopOrder;
    return o.sublist(0, o.indexOf(hero));
  }

  /// Asientos que actúan después de Hero en preflop (candidatos a 3-betear el open de Hero).
  List<Position> get seatsAfterHero {
    final o = HandFlowFSM.preflopOrder;
    return o.sublist(o.indexOf(hero) + 1);
  }

  static double openSize(Position p) => PreflopRangesDb.openSizeBb[p] ?? 2.5;

  void _step(void Function() f) {
    f();
    _afterChange();
  }

  /// AUTO-COMMIT: en cuanto el solver emite la recomendación del turno de Hero, se asume ejecutada.
  void _afterChange() {
    if (!manualMode && atHeroTurn && fsm.activeRecommendation != null) {
      lastHero = fsm.activeRecommendation;
      lastHeroStreet = fsm.street;
      fsm.executeRecommendation();
    }
    notifyListeners();
  }

  /// Resuelve la ronda hasta el turno de Hero: [target] hace [type] (con [amount]); el resto de villanos foldea.
  void _resolve({Position? target, ActionType? type, double amount = 0}) {
    var targetDone = target == null;
    var guard = 0;
    while (fsm.currentActor != null && fsm.currentActor != hero && guard++ < 12) {
      final p = fsm.currentActor!;
      if (!targetDone && p == target) {
        fsm.act(p, type!, amountBb: amount);
        targetDone = true;
      } else {
        final owes = fsm.currentBet - fsm.seats[p]!.committed > 0;
        fsm.act(p, owes ? ActionType.fold : ActionType.check);
      }
    }
  }

  // ---------------- Paso 1 ----------------
  void setPosition(Position p) => fsm.configure(hero: p);
  void setStake(Stake s) => fsm.configure(stake: s);
  void pickCard(Card c) => _step(() => fsm.addCard(c));

  // ---------------- Paso 2: escenario preflop (1 toque) ----------------
  /// [Limpia]: todos los anteriores foldean.
  void scenarioClean() => _step(() => _resolve());

  /// [Open de X] (+ opcionalmente un caller => squeeze spot).
  void scenarioOpen(Position opener, {Position? caller}) => _step(() {
        _resolve(target: opener, type: ActionType.raise, amount: openSize(opener));
        if (caller != null && fsm.currentActor != hero) _resolve(target: caller, type: ActionType.call);
      });

  /// [1+ Limpers]: [limpers] pagan 1bb; el resto foldea.
  void scenarioLimpers(List<Position> limpers) => _step(() {
        for (final l in limpers) {
          if (fsm.currentActor == hero) break;
          _resolve(target: l, type: ActionType.call);
        }
        _resolve();
      });

  /// [Enfrento 3-Bet]: Hero abre (tamaño estándar) y [threeBettor] 3-betea (3x IP / 4x desde las ciegas).
  void scenarioFacing3Bet(Position threeBettor) => _step(() {
        _resolve();
        if (fsm.currentActor != hero) return;
        final open = openSize(hero);
        fsm.act(hero, ActionType.raise, amountBb: open);
        final mult = threeBettor == Position.sb || threeBettor == Position.bb ? 4.0 : 3.0;
        _resolve(target: threeBettor, type: ActionType.raise, amount: open * mult);
      });

  // ---------------- Respuestas del villano en 1 toque ----------------
  /// Todos los villanos pendientes foldean (o pasan si no deben nada).
  void allFold() => _step(() => _resolve());

  /// El villano [p] hace [type] (los demás pendientes foldean/pasan).
  void villain(Position p, ActionType type, {double amount = 0}) => _step(() => _resolve(target: p, type: type, amount: amount));

  // ---------------- Override manual ----------------
  /// [Cambiar mi acción]: deshace el auto-commit y deja a Hero en su turno para elegir a mano.
  void overrideHero() {
    if (lastHero == null || !fsm.canUndo) return;
    fsm.undo();
    manualMode = true;
    notifyListeners();
  }

  void heroManual(ActionType type, {double amount = 0}) {
    manualMode = false;
    _step(() => fsm.act(hero, type, amountBb: amount));
  }

  void newHand({bool rotate = false}) {
    lastHero = null;
    lastHeroStreet = null;
    manualMode = false;
    fsm.nextHand(rotateButton: rotate);
    notifyListeners();
  }

  @override
  void dispose() {
    fsm.removeListener(notifyListeners);
    super.dispose();
  }
}
