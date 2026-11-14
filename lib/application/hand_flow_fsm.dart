import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/models/decision_output.dart';
import '../core/models/game_state.dart';
import '../core/reads/engine_mode.dart';
import '../core/reads/gg_smarthud_analyzer.dart';
import '../core/reads/villain_archetypes.dart';
import '../core/reads/gg_profiler.dart';
import '../core/reads/range_funnel.dart';
import '../core/evaluators/decision_justifier.dart';
import '../core/reads/read_presets_catalog.dart';
import '../core/reads/villain_range_inspector.dart';
import 'solver_controller.dart';

/// Ventanas del StreetByStreetWizard (Fase 15.0), derivadas 100% del estado de la mano.
enum ScreenPhase { setupHero, preflopAction, pickFlop, pickTurn, pickRiver, postflopStreetAction, handFinished }

/// Cómo terminó la mano.
enum HandEndReason { foldWin, showdown, heroFolded }

enum HandPhase { setup, preflop, flopCards, flop, turnCards, turn, riverCards, river, handOver }

class SeatState {
  SeatState(this.position, this.stack);
  final Position position;
  double stack;
  double committed = 0;
  bool alive = true;
  bool allIn = false;
  VillainProfile profile = VillainProfile.gtoBase;

  /// true si el usuario etiquetó al villano; si no, se usa el perfil por defecto del modo (FULL_EXPLOIT).
  bool labeled = false;
  TimingTell nextTiming = TimingTell.none;

  /// Último diagnóstico SmartHUD (stats GGPoker + etiqueta) del asiento.
  SmartHudDeviation? hud;

  SeatState clone() => SeatState(position, stack)
    ..committed = committed
    ..alive = alive
    ..allIn = allIn
    ..profile = profile
    ..labeled = labeled
    ..nextTiming = nextTiming
    ..hud = hud;
}

class _Snap {
  const _Snap({
    required this.heroCards,
    required this.board,
    required this.actions,
    required this.seats,
    required this.phase,
    required this.currentActor,
    required this.needsToAct,
    required this.currentBet,
    required this.lastRaise,
    required this.potStart,
    required this.noReraise,
    required this.reopens,
  });
  final List<Card> heroCards, board;
  final List<PlayerAction> actions;
  final Map<Position, SeatState> seats;
  final HandPhase phase;
  final Position? currentActor;
  final Set<Position> needsToAct;
  final double currentBet, lastRaise, potStart;
  final Set<Position> noReraise;
  final bool reopens;
}

class IllegalAction implements Exception {
  const IllegalAction(this.message);
  final String message;
  @override
  String toString() => 'IllegalAction: $message';
}

/// FSM de mano NLHE 6-max: orden de turnos, reapertura por raises, fast-forward preflop, Street_Gate y disparo del solver.
class HandFlowFSM extends ChangeNotifier {
  HandFlowFSM({this.startingStackBb = 100});

  final double startingStackBb;

  static const preflopOrder = [Position.utg, Position.mp, Position.co, Position.btn, Position.sb, Position.bb];
  static const postflopOrder = [Position.sb, Position.bb, Position.utg, Position.mp, Position.co, Position.btn];

  Stake stake = Stake.nl25;
  Position heroPosition = Position.bb;
  final List<Card> heroCards = [];
  final List<Card> board = [];
  final List<PlayerAction> actions = [];
  final Map<Position, SeatState> seats = {};
  HandPhase phase = HandPhase.setup;
  Position? currentActor;
  final Set<Position> _needsToAct = {};
  double _currentBet = 0;
  double _lastRaiseSize = 1;
  double _potStartStreet = 0;
  DecisionOutput? activeRecommendation;
  String? recommendationError;
  int solverMicros = 0;

  int _version = 0;
  int _projVersion = -1;
  DecisionOutput? _projCache;

  @override
  void notifyListeners() {
    _version++;
    super.notifyListeners();
  }

  /// Always_On_Reactive_Oracle (R2/R3/R4): decisión de Hero en el nodo actual SIN tocar [Mi turno].
  /// Si Hero aún no habla, proyecta como Fold (o Check si no deben nada) a los asientos pendientes antes de Hero,
  /// evalúa al solver y restaura el estado exacto (sin notificar). Cacheada por versión de estado.
  DecisionOutput? get projectedHeroDecision {
    if (_projVersion == _version) return _projCache;
    _projVersion = _version;
    _projCache = _project();
    return _projCache;
  }

  DecisionOutput? _project() {
    final hs = seats[heroPosition];
    if (heroCards.length < 2 || hs == null || !hs.alive || awaitingCards || phase == HandPhase.setup || phase == HandPhase.handOver) return null;
    if (currentActor == heroPosition) return activeRecommendation;
    if (currentActor == null || !_needsToAct.contains(heroPosition)) return null;
    final rec = activeRecommendation, err = recommendationError, micros = solverMicros;
    _push();
    DecisionOutput? d;
    try {
      for (final q in _ffPath(heroPosition)) {
        if (!_needsToAct.contains(q)) continue;
        final owes = _currentBet - seats[q]!.committed > 0;
        _apply(q, owes ? ActionType.fold : ActionType.check, 0);
      }
      if (alive.length >= 2) {
        currentActor = heroPosition;
        _refreshRecommendation();
        d = activeRecommendation;
      }
    } on Object {
      d = null;
    } finally {
      _restore(_undo.removeLast());
      activeRecommendation = rec;
      recommendationError = err;
      solverMicros = micros;
    }
    return d;
  }

  /// Dinero muerto: ante por jugador y straddle de UTG (2bb).
  double anteBb = 0;
  bool hasStraddle = false;

  /// Persistente entre manos (mesa continua): stacks, SmartHUD y etiquetas por asiento.
  final Map<Position, double> _stacks = {};
  final Map<Position, SmartHudDeviation> _huds = {};

  /// Villano seleccionado en la UI (timing / presets) y presets manuales de la mano actual.
  Position? selectedVillain;
  final Map<Position, List<AnonymousReadPreset>> manualPresets = {};

  /// Inversión de cada asiento en la calle actual y apuesta más alta a igualar (Action_Closure_Invariant).
  Map<Position, double> get streetInvestedBB => {for (final s in seats.values) s.position: s.committed};
  double get currentHighBetBB => _currentBet;
  double get totalPotBB => pot;

  /// La calle se cierra solo si todos los vivos no all-in actuaron y han igualado la apuesta más alta.
  bool get isBettingRoundClosed => phase == HandPhase.flopCards || phase == HandPhase.turnCards || phase == HandPhase.riverCards || phase == HandPhase.handOver;

  // ---- Undo (pila de snapshots en memoria de la mano actual; no es historial persistente) ----
  final List<_Snap> _undo = [];
  final List<String> _labels = [];
  bool get canUndo => _undo.isNotEmpty;

  int _trimmed = 0;

  /// Contador monótono de pasos vivos (para rollback exacto de la auto-aplicación especulativa de Hero).
  int get stepSeq => _trimmed + _undo.length;

  /// Etiqueta legible de cada paso de la mano actual (alineada con la pila de snapshots; '' = paso oculto).
  List<String> get stepLabels => List.unmodifiable(_labels);

  /// Instant Rewind: vuelve al estado exacto ANTES del paso [i] (el paso i y posteriores se descartan).
  void rewindTo(int i) {
    if (i < 0 || i >= _undo.length) throw IllegalAction('Paso $i fuera de rango');
    while (_undo.length > i + 1) {
      _undo.removeLast();
      _labels.removeLast();
    }
    undo();
  }

  static String _abbr(PlayerAction a) => switch (a.type) {
    ActionType.fold => '${a.actor.name.toUpperCase()} F',
    ActionType.check => '${a.actor.name.toUpperCase()} X',
    ActionType.call => '${a.actor.name.toUpperCase()} C ${a.amountBb.toStringAsFixed(1)}',
    ActionType.allIn => '${a.actor.name.toUpperCase()} AI ${a.amountBb.toStringAsFixed(1)}',
    _ => '${a.actor.name.toUpperCase()} ${a.isAggressive ? 'R' : ''} ${a.amountBb.toStringAsFixed(1)}bb',
  };

  /// Ejecuta [f] con snapshot previo; si lanza, el snapshot se descarta (la pila nunca guarda pasos fantasma).
  void _step(void Function() f, String Function() label) {
    _push();
    try {
      f();
    } on Object {
      _restore(_undo.removeLast());
      rethrow;
    }
    _labels.add(label());
    if (_labels.length > _undo.length) _labels.removeAt(0);
  }

  void _push() {
    _undo.add(
      _Snap(
        heroCards: List.of(heroCards),
        board: List.of(board),
        actions: List.of(actions),
        seats: {for (final e in seats.entries) e.key: e.value.clone()},
        phase: phase,
        currentActor: currentActor,
        needsToAct: Set.of(_needsToAct),
        currentBet: _currentBet,
        lastRaise: _lastRaiseSize,
        potStart: _potStartStreet,
        noReraise: Set.of(_noReraise),
        reopens: reopensBettingForPriorActors,
      ),
    );
    if (_undo.length > 64) {
      _undo.removeAt(0);
      _trimmed++;
    }
  }

  /// Deshace el último paso (acción o carta) de la mano en curso.
  void undo() {
    if (_undo.isEmpty) throw const IllegalAction('Nada que deshacer');
    final s = _undo.removeLast();
    if (_labels.length > _undo.length) _labels.removeLast();
    _restore(s);
    _refreshRecommendation();
    notifyListeners();
  }

  void _restore(_Snap s) {
    heroCards
      ..clear()
      ..addAll(s.heroCards);
    board
      ..clear()
      ..addAll(s.board);
    actions
      ..clear()
      ..addAll(s.actions);
    seats
      ..clear()
      ..addAll(s.seats);
    phase = s.phase;
    currentActor = s.currentActor;
    _needsToAct
      ..clear()
      ..addAll(s.needsToAct);
    _currentBet = s.currentBet;
    _lastRaiseSize = s.lastRaise;
    _potStartStreet = s.potStart;
    _noReraise
      ..clear()
      ..addAll(s.noReraise);
    reopensBettingForPriorActors = s.reopens;
  }

  /// Bote total, stack efectivo restante (Hero vs villano principal) y SPR en vivo.
  double get currentPotBB => pot;
  double get effectiveStackBB {
    final v = _mainVillain();
    final h = seats[heroPosition];
    if (h == null) return startingStackBb;
    if (v == null) return h.stack;
    return math.min(h.stack, seats[v]!.stack);
  }

  double? get currentSPR => pot <= 0 ? null : effectiveStackBB / pot;

  double stackOf(Position p) => seats[p]?.stack ?? (_stacks[p] ?? startingStackBb);

  void setStack(Position p, double bb) {
    _stacks[p] = bb;
    notifyListeners();
  }

  /// Última acción del asiento en la calle actual.
  PlayerAction? lastActionOf(Position p) => actions.where((a) => a.actor == p && a.street == street).lastOrNull;

  SmartHudDeviation? hudOf(Position p) => seats[p]?.hud ?? _huds[p];

  /// Estado mental por asiento (persistente entre manos hasta que el usuario lo cambie; no es historial).
  final Map<Position, VillainMentalState> _mental = {};
  VillainMentalState mentalOf(Position p) => _mental[p] ?? VillainMentalState.normal;

  void setMental(Position p, VillainMentalState m) {
    if (m == VillainMentalState.normal) {
      _mental.remove(p);
    } else {
      _mental[p] = m;
    }
    _refreshRecommendation();
    notifyListeners();
  }

  /// Lectura efectiva del villano: perfil + stats SmartHUD (PFR/VPIP/3B) + estado mental.
  ReadProfile readOf(Position p) {
    final base = ReadProfile.fromVillainProfile(effectiveProfile(p));
    final hud = hudOf(p);
    return ReadProfile(base.archetype, base.reasons, pfr: hud?.stats.pfr, vpip: hud?.stats.vpip, threeBet: hud?.stats.threeBet, mentalState: mentalOf(p));
  }

  void setPresets(Position p, List<AnonymousReadPreset> presets) {
    manualPresets[p] = presets;
    _refreshRecommendation();
    notifyListeners();
  }

  void setDeadMoney({double? ante, bool? straddle}) {
    if (phase != HandPhase.setup) throw const IllegalAction('Ante/straddle solo en setup');
    if (ante != null) anteBb = ante;
    if (straddle != null) hasStraddle = straddle;
    notifyListeners();
  }

  /// Nueva mano: limpia cartas, bote y acciones; conserva SmartHUD/etiquetas/stacks. Con [rotateButton] el botón avanza
  /// un puesto y cada jugador (y su lectura) se mueve a su nueva posición.
  void nextHand({bool rotateButton = false}) {
    for (final e in seats.entries) {
      if (e.value.hud != null) _huds[e.key] = e.value.hud!;
    }
    if (rotateButton) {
      Position mv(Position p) => preflopOrder[(preflopOrder.indexOf(p) + preflopOrder.length - 1) % preflopOrder.length];
      final prof = {for (final e in _profiles.entries) mv(e.key): e.value};
      final mental = {for (final e in _mental.entries) mv(e.key): e.value};
      _mental
        ..clear()
        ..addAll(mental);
      final huds = {for (final e in _huds.entries) mv(e.key): e.value};
      final stacks = {for (final e in _stacks.entries) mv(e.key): e.value};
      _profiles
        ..clear()
        ..addAll(prof);
      _huds
        ..clear()
        ..addAll(huds);
      _stacks
        ..clear()
        ..addAll(stacks);
      heroPosition = mv(heroPosition);
    }
    manualPresets.clear();
    selectedVillain = null;
    reset();
  }

  Street get street => switch (phase) {
    HandPhase.flop || HandPhase.turnCards => Street.flop,
    HandPhase.turn || HandPhase.riverCards => Street.turn,
    HandPhase.river || HandPhase.handOver when board.length == 5 => Street.river,
    _ => Street.preflop,
  };

  double get pot => _potStartStreet + seats.values.fold<double>(0, (s, x) => s + x.committed);
  double get currentBet => _currentBet;
  List<Position> get alive => [
    for (final p in preflopOrder)
      if (seats[p]?.alive ?? false) p,
  ];

  Set<int> get deadCardIds => {
    for (final c in [...heroCards, ...board]) c.id,
  };

  bool get awaitingCards => phase == HandPhase.setup || phase == HandPhase.flopCards || phase == HandPhase.turnCards || phase == HandPhase.riverCards;

  int get cardsNeeded => switch (phase) {
    HandPhase.setup => 2 - heroCards.length,
    HandPhase.flopCards => 3 - (board.length),
    HandPhase.turnCards => 4 - board.length,
    HandPhase.riverCards => 5 - board.length,
    _ => 0,
  };

  bool get isStreetActionClosed => phase != HandPhase.setup && _needsToAct.isEmpty;

  double? get spr {
    final v = _mainVillain();
    if (v == null || pot <= 0) return null;
    return _effectiveBehind(v) / pot;
  }

  void configure({Stake? stake, Position? hero}) {
    final untouchedPreflop = phase == HandPhase.preflop && actions.isEmpty;
    if (phase != HandPhase.setup && !untouchedPreflop) throw const IllegalAction('Stake/posición solo en setup');
    if (stake != null) this.stake = stake;
    if (hero != null) heroPosition = hero;
    // Orden natural (1° mano -> 2° posición): re-sienta la mesa si la mano aún no tiene acciones.
    if (untouchedPreflop) _startPreflop();
    notifyListeners();
  }

  void reset() {
    _undo.clear();
    _trimmed = 0;
    _labels.clear();
    heroCards.clear();
    board.clear();
    actions.clear();
    seats.clear();
    _needsToAct.clear();
    _potStartStreet = 0;
    _currentBet = 0;
    _lastRaiseSize = 1;
    phase = HandPhase.setup;
    currentActor = null;
    activeRecommendation = null;
    recommendationError = null;
    notifyListeners();
  }

  EngineMode engineMode = ProfileDefaults.defaultMode;

  VillainProfile effectiveProfile(Position p) {
    final seat = seats[p];
    if (seat != null && seat.labeled) return seat.profile;
    return ProfileDefaults.defaultFor(stake, mode: engineMode);
  }

  void setProfile(Position p, VillainProfile profile) {
    seats[p]?.profile = profile;
    seats[p]?.labeled = true;
    _profiles[p] = profile;
    _refreshRecommendation();
    notifyListeners();
  }

  final Map<Position, VillainProfile> _profiles = {};

  /// SmartHUD: analiza stats (+ etiqueta manual opcional) y activa el perfil del motor de la etiqueta resultante.
  SmartHudDeviation? setHud(Position p, SmartHudStats stats, {VillainTag? manualTag}) {
    final seat = seats[p];
    final dev = GgSmartHudAnalyzer.analyze(stats, manualTag: manualTag);
    if (seat == null) {
      // Setup (mano no iniciada): se guarda para los asientos de la próxima mano.
      _huds[p] = dev;
      if (dev.tag == VillainTag.poolDefault) {
        _profiles.remove(p);
      } else {
        _profiles[p] = dev.vector.profileFor(stake);
      }
      notifyListeners();
      return dev;
    }
    seat.hud = dev;
    _huds[p] = dev;
    if (dev.tag == VillainTag.poolDefault) {
      seat.labeled = false;
      _profiles.remove(p);
      _refreshRecommendation();
      notifyListeners();
    } else {
      setProfile(p, dev.vector.profileFor(stake));
    }
    return dev;
  }

  void setTiming(Position p, TimingTell t) {
    seats[p]?.nextTiming = t;
    notifyListeners();
  }

  /// Teclado de cartas: Hero (2) en setup, luego 3/1/1 al abrirse el Street_Gate.
  void addCard(Card c) {
    if (!awaitingCards) throw const IllegalAction('Street_Gate cerrado: la acción de la calle no ha terminado');
    if (deadCardIds.contains(c.id)) throw IllegalAction('Carta muerta: $c');
    final hero = phase == HandPhase.setup;
    _step(() {
      if (hero) {
        heroCards.add(c);
        if (heroCards.length == 2) _startPreflop();
      } else {
        board.add(c);
        if (cardsNeeded == 0) _startStreet();
      }
    }, () => hero ? '' : '[$c]');
    notifyListeners();
  }

  void _startPreflop() {
    seats
      ..clear()
      ..addAll({
        for (final p in preflopOrder)
          p: SeatState(p, (_stacks[p] ?? startingStackBb) - anteBb)
            ..profile = _profiles[p] ?? VillainProfile.gtoBase
            ..labeled = _profiles.containsKey(p)
            ..hud = _huds[p],
      });
    seats[Position.sb]!
      ..committed = 0.5
      ..stack -= 0.5;
    seats[Position.bb]!
      ..committed = 1.0
      ..stack -= 1.0;
    _potStartStreet = anteBb * preflopOrder.length;
    _currentBet = 1.0;
    _lastRaiseSize = 1.0;
    if (hasStraddle) {
      seats[Position.utg]!
        ..committed = 2.0
        ..stack -= 2.0;
      _currentBet = 2.0;
    }
    phase = HandPhase.preflop;
    _needsToAct
      ..clear()
      ..addAll(preflopOrder);
    _noReraise.clear();
    reopensBettingForPriorActors = true;
    currentActor = hasStraddle ? Position.mp : Position.utg;
    _refreshRecommendation();
  }

  void _startStreet() {
    _noReraise.clear();
    reopensBettingForPriorActors = true;
    _potStartStreet = pot;
    for (final s in seats.values) {
      s.committed = 0;
    }
    _currentBet = 0;
    _lastRaiseSize = 1.0;
    phase = switch (board.length) {
      3 => HandPhase.flop,
      4 => HandPhase.turn,
      _ => HandPhase.river,
    };
    _needsToAct
      ..clear()
      ..addAll([
        for (final p in postflopOrder)
          if (seats[p]!.alive && !seats[p]!.allIn) p,
      ]);
    if (_needsToAct.length < 2) _needsToAct.clear();
    currentActor = _nextFrom(null);
    if (currentActor == null) _closeStreet();
    _refreshRecommendation();
  }

  List<Position> get _order => phase == HandPhase.preflop ? preflopOrder : postflopOrder;

  Position? _nextFrom(Position? after) {
    final o = _order;
    final start = after == null ? 0 : o.indexOf(after) + 1;
    for (var k = 0; k < o.length; k++) {
      final p = o[(start + k) % o.length];
      if (_needsToAct.contains(p)) return p;
    }
    return null;
  }

  /// Jugadores que ya actuaron antes de un all-in incompleto: solo fold/call.
  final Set<Position> _noReraise = {};
  bool reopensBettingForPriorActors = true;
  bool canRaise(Position p) => !_noReraise.contains(p);

  /// Ventana activa: Hero foldeado => mano terminada para el usuario aunque sigan villanos.
  ScreenPhase get screenPhase {
    if (phase == HandPhase.setup) return ScreenPhase.setupHero;
    if (phase == HandPhase.handOver || (seats[heroPosition] != null && !seats[heroPosition]!.alive)) return ScreenPhase.handFinished;
    return switch (phase) {
      HandPhase.preflop => ScreenPhase.preflopAction,
      HandPhase.flopCards => ScreenPhase.pickFlop,
      HandPhase.turnCards => ScreenPhase.pickTurn,
      HandPhase.riverCards => ScreenPhase.pickRiver,
      _ => ScreenPhase.postflopStreetAction,
    };
  }

  /// Motivo del cierre (solo con [screenPhase] == handFinished).
  HandEndReason? get endReason {
    if (screenPhase != ScreenPhase.handFinished) return null;
    if (seats[heroPosition] != null && !seats[heroPosition]!.alive) return HandEndReason.heroFolded;
    return alive.length <= 1 ? HandEndReason.foldWin : HandEndReason.showdown;
  }

  /// Law_1_Deterministic_Auto_Cursor: asiento al que apunta el cursor autónomo (cola circular `pendingToAct`).
  Position? get currentActorSeat => currentActor;

  /// Asientos vivos de la calle en orden de acción (los foldeados se borran de la lista).
  List<Position> get activeSeats => [
    for (final p in _order)
      if (seats[p]?.alive ?? false) p,
  ];

  /// Asientos que aún deben actuar en la ronda (Betting_Round_Closure_Gate).
  Set<Position> get pendingToAct => Set.unmodifiable(_needsToAct);

  /// true => tocar la fila de [p] es legal ahora (turno actual o salto implícito sin saltar a Hero).
  bool canTap(Position p) {
    final cur = currentActor;
    if (cur == null || awaitingCards || phase == HandPhase.setup || phase == HandPhase.handOver) return false;
    if (p == cur) return true;
    return _needsToAct.contains(p) && !_skipsHero(p);
  }

  /// Acciones legales para el jugador en turno.
  Set<ActionType> legalActions() {
    final p = currentActor;
    if (p == null) return {};
    final s = seats[p]!;
    final toCall = _currentBet - s.committed;
    final raiseOk = canRaise(p);
    return {
      if (toCall > 0) ActionType.fold,
      if (toCall <= 0) ActionType.check,
      if (toCall > 0) ActionType.call,
      if (s.stack > toCall && raiseOk) _currentBet == 0 ? ActionType.bet : ActionType.raise,
      if (raiseOk || s.stack <= toCall) ActionType.allIn,
    };
  }

  double get minRaiseTo => _currentBet + math.max(_lastRaiseSize, 1);

  /// Aplica una acción. [amountBb] = total "to" de la calle para bet/raise.
  void act(Position p, ActionType type, {double amountBb = 0}) {
    if (phase == HandPhase.setup || awaitingCards || phase == HandPhase.handOver) throw const IllegalAction('No hay acción pendiente');
    final before = actions.length;
    _step(() => _act(p, type, amountBb), () => actions.sublist(before).map(_abbr).join(' · '));
    notifyListeners();
  }

  void _act(Position p, ActionType type, double amountBb) {
    if (!canRaise(p) &&
        (type == ActionType.bet || type == ActionType.raise || (type == ActionType.allIn && seats[p]!.stack > _currentBet - seats[p]!.committed))) {
      throw IllegalAction('${p.name.toUpperCase()}: el all-in incompleto no reabre la subida (solo fold/call)');
    }
    if (p != currentActor) {
      // Implicit_Fast_Forward: los asientos omitidos entre el turno actual y el actor foldean (o pasan si no deben nada).
      final fastForward = _needsToAct.contains(p) && !_skipsHero(p);
      if (!fastForward) throw IllegalAction('Turno de ${currentActor?.name}, no de ${p.name}');
      for (final q in _ffPath(p)) {
        if (!_needsToAct.contains(q)) continue;
        final owes = _currentBet - seats[q]!.committed > 0;
        _apply(q, owes ? ActionType.fold : ActionType.check, 0);
      }
    }
    _apply(p, type, amountBb);
    _advance(p);
  }

  /// Asientos desde el actor actual (incluido) hasta [target] (excluido) en orden circular de la calle:
  /// tras una re-subida la ronda se reabre y el turno da la vuelta a la mesa.
  List<Position> _ffPath(Position target) {
    final o = _order;
    final ci = o.indexOf(currentActor!);
    final out = <Position>[];
    for (var k = 0; k < o.length; k++) {
      final q = o[(ci + k) % o.length];
      if (q == target) return out;
      out.add(q);
    }
    return out;
  }

  bool _skipsHero(Position target) => _needsToAct.contains(heroPosition) && _ffPath(target).contains(heroPosition);

  void _apply(Position p, ActionType type, double amount) {
    final s = seats[p]!;
    final toCall = _currentBet - s.committed;
    final st = street;
    final timing = s.nextTiming;
    s.nextTiming = TimingTell.none;
    switch (type) {
      case ActionType.fold:
        s.alive = false;
        actions.add(PlayerAction(st, p, ActionType.fold, 0, timing));
      case ActionType.check:
        if (toCall > 0) throw IllegalAction('${p.name} no puede check: debe ${toCall.toStringAsFixed(2)}bb');
        actions.add(PlayerAction(st, p, ActionType.check, 0, timing));
      case ActionType.call:
        if (toCall <= 0) throw IllegalAction('Nada que igualar');
        final pay = math.min(toCall, s.stack);
        s.stack -= pay;
        s.committed += pay;
        if (s.stack <= 0) s.allIn = true;
        actions.add(PlayerAction(st, p, ActionType.call, s.committed, timing));
      case ActionType.bet || ActionType.raise || ActionType.allIn:
        final target = type == ActionType.allIn ? s.committed + s.stack : amount;
        if (type != ActionType.allIn && target < minRaiseTo - 1e-9 && target < s.committed + s.stack) {
          throw IllegalAction('Raise mínimo a ${minRaiseTo.toStringAsFixed(2)}bb');
        }
        final pay = math.min(target - s.committed, s.stack);
        s.stack -= pay;
        s.committed += pay;
        if (s.stack <= 1e-9) s.allIn = true;
        if (s.committed > _currentBet) {
          final increment = s.committed - _currentBet;
          final full = increment >= _lastRaiseSize - 1e-9;
          final pending = Set.of(_needsToAct);
          _currentBet = s.committed;
          final others = [
            for (final q in _order)
              if (q != p && seats[q]!.alive && !seats[q]!.allIn) q,
          ];
          if (full) {
            _lastRaiseSize = math.max(_lastRaiseSize, increment);
            _noReraise.clear();
            reopensBettingForPriorActors = true;
          } else {
            // Incomplete_ShortStack_AllIn_Rule (GGPoker): un all-in que no completa la subida mínima NO reabre la apuesta
            // para quien ya actuó en la ronda: solo puede foldear o pagar la diferencia.
            reopensBettingForPriorActors = false;
            _noReraise.addAll([
              for (final q in others)
                if (!pending.contains(q)) q,
            ]);
          }
          _needsToAct
            ..clear()
            ..addAll(others);
        }
        final priorAgg = actions.any((a) => a.street == st && a.isAggressive);
        final t = type == ActionType.allIn ? ActionType.allIn : (st == Street.preflop || priorAgg ? ActionType.raise : ActionType.bet);
        actions.add(PlayerAction(st, p, t, s.committed, timing));
    }
    _needsToAct.remove(p);
  }

  void _advance(Position p) {
    if (alive.length < 2) {
      _needsToAct.clear();
      phase = HandPhase.handOver;
      currentActor = null;
      activeRecommendation = null;
      return;
    }
    final next = _nextFrom(p);
    if (next == null) {
      _closeStreet();
    } else {
      currentActor = next;
    }
    _refreshRecommendation();
  }

  void _closeStreet() {
    currentActor = null;
    phase = switch (phase) {
      HandPhase.preflop => HandPhase.flopCards,
      HandPhase.flop => HandPhase.turnCards,
      HandPhase.turn => HandPhase.riverCards,
      _ => HandPhase.handOver,
    };
  }

  Position? _mainVillain() {
    final others = alive.where((p) => p != heroPosition).toList();
    if (others.isEmpty) return null;
    final agg = actions.reversed.where((a) => a.isAggressive && a.actor != heroPosition && others.contains(a.actor));
    if (agg.isNotEmpty) return agg.first.actor;
    return others.first;
  }

  double _effectiveBehind(Position v) {
    final h = seats[heroPosition]!, x = seats[v]!;
    return math.min(h.stack + h.committed, x.stack + x.committed);
  }

  /// GameState exacto acumulado hasta este instante (el que ve el solver).
  GameState buildGameState() {
    final v = _mainVillain();
    final postflop = board.length >= 3;
    final streetStart = <Position, double>{};
    for (final s in seats.values) {
      streetStart[s.position] = s.stack + s.committed;
    }
    final eff = v == null ? startingStackBb : math.min(streetStart[heroPosition]!, streetStart[v]!);
    return GameState(
      stake: stake,
      heroPosition: heroPosition,
      villainPosition: v,
      effectiveStackBb: postflop ? eff : startingStackBb,
      potBb: postflop ? _potStartStreet : pot,
      hero: HoleCards(heroCards[0], heroCards[1]),
      board: board.length >= 3 ? List.of(board) : const [],
      actions: List.of(actions),
      villainProfile: v == null ? ProfileDefaults.defaultFor(stake, mode: engineMode) : effectiveProfile(v),
      activePlayers: alive.length,
      activeVillains: alive.length >= 3
          ? [
              for (final p in alive)
                if (p != heroPosition) VillainSeatState(p, profile: effectiveProfile(p)),
            ]
          : const [],
      anteBb: anteBb,
      hasStraddle: hasStraddle,
      seatStacksBb: {for (final s in seats.values) s.position: s.stack + s.committed},
    );
  }

  VillainRangeState? get villainFunnelState {
    if (board.length < 3 || _mainVillain() == null) return null;
    try {
      return RangeFunnel.track(buildGameState()).state;
    } catch (_) {
      return null;
    }
  }

  void _refreshRecommendation() {
    activeRecommendation = null;
    recommendationError = null;
    if (currentActor != heroPosition || heroCards.length < 2) return;
    final sw = Stopwatch()..start();
    try {
      final s = buildGameState();
      final v = s.villainPosition;
      final read = v == null ? null : readOf(v);
      var d = solve(s, read);
      final manual = v == null ? const <AnonymousReadPreset>[] : (manualPresets[v] ?? const <AnonymousReadPreset>[]);
      if (manual.isNotEmpty && s.board.length >= 3 && read != null) {
        final toCall = _currentBet - seats[heroPosition]!.committed;
        final potBefore = pot - toCall;
        final r = VillainRangeInspector.inspect(s, read, potBefore: potBefore, toCall: toCall, manualPresets: manual);
        d = d.copyWith(
          perceivedVillainRange: r,
          justification: DecisionJustifier.build(s, read, d, r, potBefore: potBefore, toCall: toCall),
        );
      }
      activeRecommendation = d;
    } catch (e) {
      recommendationError = e.toString();
    }
    solverMicros = sw.elapsedMicroseconds;
  }

  /// Ejecuta la recomendación del solver para Hero y avanza la FSM.
  void executeRecommendation() {
    final d = activeRecommendation;
    if (d == null || currentActor != heroPosition) throw const IllegalAction('Sin recomendación activa');
    final toCall = _currentBet - seats[heroPosition]!.committed;
    switch (d.action) {
      case DecisionAction.fold:
        act(heroPosition, toCall > 0 ? ActionType.fold : ActionType.check);
      case DecisionAction.check:
        act(heroPosition, toCall > 0 ? ActionType.fold : ActionType.check);
      case DecisionAction.call:
        act(heroPosition, toCall > 0 ? ActionType.call : ActionType.check);
      case DecisionAction.betRaise:
        final bb = d.sizing?.bb ?? minRaiseTo;
        final target = street == Street.preflop ? bb : seats[heroPosition]!.committed + (toCall > 0 ? bb - seats[heroPosition]!.committed : bb);
        final s = seats[heroPosition]!;
        final capped = math.min(math.max(target, minRaiseTo), s.committed + s.stack);
        act(heroPosition, capped >= s.committed + s.stack ? ActionType.allIn : (_currentBet == 0 ? ActionType.bet : ActionType.raise), amountBb: capped);
    }
  }
}
