import 'dart:async';
import 'dart:isolate';

import '../core/models/decision_output.dart';
import '../core/models/game_state.dart';
import '../core/postflop/postflop_heuristic_engine.dart';
import '../core/preflop/full_tree_preflop.dart';
import '../core/reads/gg_profiler.dart';
import 'state_validator.dart';

enum ControllerStatus { idle, computing, ready, invalid, error }

class ControllerState {
  const ControllerState(this.status, {this.decision, this.issues = const [], this.error, this.requestId = 0, this.elapsedMicros = 0});
  final ControllerStatus status;
  final DecisionOutput? decision;
  final List<ValidationIssue> issues;
  final Object? error;
  final int requestId;
  final int elapsedMicros;
}

/// Punto único de entrada a los motores (puro, sin UI).
DecisionOutput solve(GameState s, ReadProfile? read) =>
    s.street == Street.preflop ? const FullTreePreflop().decide(s, read: read) : const PostflopHeuristicEngine().decide(s, read: read);

abstract class DecisionExecutor {
  Future<DecisionOutput> run(GameState s, ReadProfile? read);
  Future<void> dispose() async {}
}

/// Ejecución en el mismo hilo (tests / herramientas).
class InlineExecutor implements DecisionExecutor {
  const InlineExecutor();
  @override
  Future<DecisionOutput> run(GameState s, ReadProfile? read) async => solve(s, read);
  @override
  Future<void> dispose() async {}
}

/// Isolate persistente: los cálculos nunca bloquean el hilo de UI y las cachés del motor sobreviven entre manos.
class IsolateExecutor implements DecisionExecutor {
  SendPort? _send;
  Isolate? _isolate;
  Completer<void>? _ready;
  int _seq = 0;
  final _pending = <int, Completer<DecisionOutput>>{};
  ReceivePort? _rx;

  Future<void> _start() async {
    if (_ready != null) return _ready!.future;
    _ready = Completer<void>();
    _rx = ReceivePort();
    _isolate = await Isolate.spawn(_worker, _rx!.sendPort);
    _rx!.listen((msg) {
      if (msg is SendPort) {
        _send = msg;
        _ready!.complete();
      } else if (msg is (int, DecisionOutput?, String?)) {
        final c = _pending.remove(msg.$1);
        if (c == null) return;
        if (msg.$2 != null) {
          c.complete(msg.$2);
        } else {
          c.completeError(StateError(msg.$3 ?? 'error'));
        }
      }
    });
    return _ready!.future;
  }

  static void _worker(SendPort out) {
    final rx = ReceivePort();
    out.send(rx.sendPort);
    rx.listen((msg) {
      final (id, s, read) = msg as (int, GameState, ReadProfile?);
      try {
        out.send((id, solve(s, read), null));
      } catch (e) {
        out.send((id, null, e.toString()));
      }
    });
  }

  @override
  Future<DecisionOutput> run(GameState s, ReadProfile? read) async {
    await _start();
    final id = ++_seq;
    final c = Completer<DecisionOutput>();
    _pending[id] = c;
    _send!.send((id, s, read));
    return c.future;
  }

  @override
  Future<void> dispose() async {
    _isolate?.kill(priority: Isolate.immediate);
    _rx?.close();
    for (final c in _pending.values) {
      c.completeError(StateError('executor disposed'));
    }
    _pending.clear();
  }
}

/// Controlador reactivo: `GameState` -> `Stream<ControllerState>`. Descarta resultados obsoletos (solo emite el último request).
class SolverController {
  SolverController({DecisionExecutor? executor}) : _executor = executor ?? IsolateExecutor();

  final DecisionExecutor _executor;
  final _out = StreamController<ControllerState>.broadcast();
  ControllerState _state = const ControllerState(ControllerStatus.idle);
  int _latest = 0;

  Stream<ControllerState> get states => _out.stream;
  ControllerState get state => _state;

  void _emit(ControllerState s) {
    _state = s;
    if (!_out.isClosed) _out.add(s);
  }

  Future<ControllerState> submit(GameState s, {ReadProfile? read}) async {
    final id = ++_latest;
    final issues = StateValidator.validate(s);
    if (issues.isNotEmpty) {
      final st = ControllerState(ControllerStatus.invalid, issues: issues, requestId: id);
      _emit(st);
      return st;
    }
    _emit(ControllerState(ControllerStatus.computing, requestId: id));
    final sw = Stopwatch()..start();
    try {
      final d = await _executor.run(s, read);
      final st = ControllerState(ControllerStatus.ready, decision: d, requestId: id, elapsedMicros: sw.elapsedMicroseconds);
      if (id == _latest) _emit(st);
      return st;
    } catch (e) {
      final st = ControllerState(ControllerStatus.error, error: e, requestId: id);
      if (id == _latest) _emit(st);
      return st;
    }
  }

  Future<void> dispose() async {
    await _executor.dispose();
    await _out.close();
  }
}
