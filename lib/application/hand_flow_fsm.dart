import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/models/decision_output.dart';
import '../core/models/game_state.dart';
import '../core/reads/engine_mode.dart';
import '../core/reads/gg_profiler.dart';
import '../core/reads/range_funnel.dart';
import 'solver_controller.dart';

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

  Street get street => switch (phase) {
        HandPhase.flop || HandPhase.turnCards => Street.flop,
        HandPhase.turn || HandPhase.riverCards => Street.turn,
        HandPhase.river || HandPhase.handOver when board.length == 5 => Street.river,
        _ => Street.preflop,
      };

  double get pot => _potStartStreet + seats.values.fold<double>(0, (s, x) => s + x.committed);
  double get currentBet => _currentBet;
  List<Position> get alive => [for (final p in preflopOrder) if (seats[p]?.alive ?? false) p];

  Set<int> get deadCardIds => {for (final c in [...heroCards, ...board]) c.id};

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
    if (phase != HandPhase.setup) throw const IllegalAction('Stake/posición solo en setup');
    if (stake != null) this.stake = stake;
    if (hero != null) heroPosition = hero;
    notifyListeners();
  }

  void reset() {
    heroCards.clear();
    board.clear();
    actions.clear();
    seats.clear();
    _needsToAct.clear();
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

  void setTiming(Position p, TimingTell t) {
    seats[p]?.nextTiming = t;
    notifyListeners();
  }

  /// Teclado de cartas: Hero (2) en setup, luego 3/1/1 al abrirse el Street_Gate.
  void addCard(Card c) {
    if (!awaitingCards) throw const IllegalAction('Street_Gate cerrado: la acción de la calle no ha terminado');
    if (deadCardIds.contains(c.id)) throw IllegalAction('Carta muerta: $c');
    if (phase == HandPhase.setup) {
      heroCards.add(c);
      if (heroCards.length == 2) _startPreflop();
    } else {
      board.add(c);
      if (cardsNeeded == 0) _startStreet();
    }
    notifyListeners();
  }

  void _startPreflop() {
    seats
      ..clear()
      ..addAll({
        for (final p in preflopOrder)
          p: SeatState(p, startingStackBb)
            ..profile = _profiles[p] ?? VillainProfile.gtoBase
            ..labeled = _profiles.containsKey(p),
      });
    seats[Position.sb]!
      ..committed = 0.5
      ..stack -= 0.5;
    seats[Position.bb]!
      ..committed = 1.0
      ..stack -= 1.0;
    _potStartStreet = 0;
    _currentBet = 1.0;
    _lastRaiseSize = 1.0;
    phase = HandPhase.preflop;
    _needsToAct
      ..clear()
      ..addAll(preflopOrder);
    currentActor = Position.utg;
    _refreshRecommendation();
  }

  void _startStreet() {
    _potStartStreet = pot;
    for (final s in seats.values) {
      s.committed = 0;
    }
    _currentBet = 0;
    _lastRaiseSize = 1.0;
    phase = switch (board.length) { 3 => HandPhase.flop, 4 => HandPhase.turn, _ => HandPhase.river };
    _needsToAct
      ..clear()
      ..addAll([for (final p in postflopOrder) if (seats[p]!.alive && !seats[p]!.allIn) p]);
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

  /// Acciones legales para el jugador en turno.
  Set<ActionType> legalActions() {
    final p = currentActor;
    if (p == null) return {};
    final s = seats[p]!;
    final toCall = _currentBet - s.committed;
    return {
      if (toCall > 0) ActionType.fold,
      if (toCall <= 0) ActionType.check,
      if (toCall > 0) ActionType.call,
      if (s.stack > toCall) _currentBet == 0 ? ActionType.bet : ActionType.raise,
      ActionType.allIn,
    };
  }

  double get minRaiseTo => _currentBet + math.max(_lastRaiseSize, 1);

  /// Aplica una acción. [amountBb] = total "to" de la calle para bet/raise.
  void act(Position p, ActionType type, {double amountBb = 0}) {
    if (phase == HandPhase.setup || awaitingCards || phase == HandPhase.handOver) throw const IllegalAction('No hay acción pendiente');
    final aggressive = type == ActionType.bet || type == ActionType.raise || type == ActionType.allIn;
    if (p != currentActor) {
      final o = _order;
      final fastForward = phase == HandPhase.preflop && aggressive && _needsToAct.contains(p) &&
          o.indexOf(p) > o.indexOf(currentActor!) && !_skipsHero(p);
      if (!fastForward) throw IllegalAction('Turno de ${currentActor?.name}, no de ${p.name}');
      for (final q in o.sublist(o.indexOf(currentActor!), o.indexOf(p))) {
        if (_needsToAct.contains(q)) _apply(q, ActionType.fold, 0);
      }
    }
    _apply(p, type, amountBb);
    _advance(p);
    notifyListeners();
  }

  bool _skipsHero(Position target) {
    final o = _order;
    final i = o.indexOf(currentActor!), j = o.indexOf(target), h = o.indexOf(heroPosition);
    return h >= i && h < j && _needsToAct.contains(heroPosition);
  }

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
          _lastRaiseSize = math.max(_lastRaiseSize, s.committed - _currentBet);
          _currentBet = s.committed;
          _needsToAct
            ..clear()
            ..addAll([for (final q in _order) if (q != p && seats[q]!.alive && !seats[q]!.allIn) q]);
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
      final read = v == null ? null : ReadProfile.fromVillainProfile(effectiveProfile(v));
      activeRecommendation = solve(s, read);
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
