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
    final waitingSetup = fsm.phase == HandPhase.preflop && fsm.actions.isEmpty && !_heroGo;
    _heroGo = false;
    if (!manualMode && !waitingSetup && atHeroTurn && fsm.activeRecommendation != null) {
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
  bool _heroGo = false;

  /// [Limpia] / [⭐ TU TURNO]: todos los anteriores foldean y el solver actúa por Hero.
  void scenarioClean() {
    _heroGo = true;
    _step(() => _resolve());
  }

  void heroGo() => scenarioClean();

  /// Positional_Sequential_Ledger: el asiento [p] actúa (los omitidos antes que él foldean / pasan).
  void seatAct(Position p, ActionType type, {double amount = 0}) {
    _heroGo = true;
    _step(() => fsm.act(p, type, amountBb: amount));
  }

  /// [✓ Resolver]: los asientos no tocados foldean (o pasan) hasta cerrar la ronda o volver a Hero.
  void resolveStreet() => _step(() => _resolve());

  /// [↶ Deshacer Último Toque]: si el último paso fue el auto-commit de Hero, deshace también el toque que lo provocó.
  void undoLast() {
    if (!fsm.canUndo) return;
    final heroWasLast = fsm.actions.isNotEmpty && fsm.actions.last.actor == hero && !manualMode;
    fsm.undo();
    if (heroWasLast && fsm.canUndo && fsm.actions.isNotEmpty) fsm.undo();
    manualMode = atHeroTurn;
    notifyListeners();
  }

  /// [Open de X] + cold callers (multi-select) => squeeze multiway (dinero muerto por caller).
  void scenarioOpen(Position opener, {Position? caller, List<Position> callers = const []}) => _step(() {
    _resolveCallers({...callers, ?caller}, opener: opener);
  });

  /// Todos los [callers] pagan (cada uno en su turno); el resto foldea/pasa hasta Hero.
  void _resolveCallers(Set<Position> callers, {Position? opener}) {
    var guard = 0;
    while (fsm.currentActor != null && fsm.currentActor != hero && guard++ < 12) {
      final p = fsm.currentActor!;
      if (p == opener) {
        fsm.act(p, ActionType.raise, amountBb: openSize(p));
        continue;
      }
      final owes = fsm.currentBet - fsm.seats[p]!.committed > 0;
      fsm.act(p, callers.contains(p) ? (owes ? ActionType.call : ActionType.check) : (owes ? ActionType.fold : ActionType.check));
    }
  }

  /// Asientos entre el opener y Hero (candidatos a cold call).
  List<Position> coldCallerCandidates(Position opener) {
    final o = openersBeforeHero;
    final i = o.indexOf(opener);
    return i < 0 ? const [] : o.sublist(i + 1);
  }

  /// Villanos vivos (no Hero) en orden posicional postflop (OOP -> IP).
  List<Position> get liveVillains => [
    for (final p in HandFlowFSM.postflopOrder)
      if (p != hero && (fsm.seats[p]?.alive ?? false)) p,
  ];

  /// Villanos que aún deben dinero en la ronda actual (respuesta a la acción de Hero).
  List<Position> get pendingOwing => [
    for (final p in HandFlowFSM.preflopOrder)
      if (p != hero && (fsm.seats[p]?.alive ?? false) && !(fsm.seats[p]?.allIn ?? true) && fsm.currentBet - fsm.seats[p]!.committed > 0) p,
  ];

  /// Preflop tras la acción de Hero: [callers] pagan, el resto foldea => flop N-way.
  void goToFlop(Set<Position> callers) => _step(() => _resolveCallers(callers));

  /// [3-Bet de X] sobre la acción de Hero: el turno vuelve a Hero con el bote exacto.
  void threeBetBy(Position p) {
    final s = fsm.seats[p]!;
    final mult = p == Position.sb || p == Position.bb ? 4.0 : 3.0;
    final to = fsm.currentBet * mult;
    final cap = s.committed + s.stack;
    villain(p, ActionType.raise, amount: to > cap ? cap : to);
  }

  /// Acción de UN solo villano (el actor actual), sin tocar al resto: necesario en botes multiway.
  void villainAct(ActionType type, {double amount = 0}) => _step(() {
    final p = fsm.currentActor;
    if (p == null || p == hero) return;
    fsm.act(p, type, amountBb: amount);
  });

  /// [X Foldeó]: elimina al villano (solo en su turno) y re-evalúa el agregador multiway.
  void villainFolded(Position p) {
    if (fsm.currentActor == p) villainAct(ActionType.fold);
  }

  /// [1+ Limpers]: [limpers] pagan 1bb; el resto foldea.
  void scenarioLimpers(List<Position> limpers) => _step(() => _resolveCallers(limpers.toSet()));

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
