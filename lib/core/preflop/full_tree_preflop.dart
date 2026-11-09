import 'dart:typed_data';

import '../models/decision_output.dart';
import '../models/game_state.dart';
import '../reads/gg_profiler.dart';
import 'hand_normalizer.dart';
import 'preflop_ranges_db.dart';
import 'preflop_solver_engine.dart';
import 'range_notation.dart';

enum TreeScenario { rfi, isoVsLimpers, threeBetHu, squeeze, standard4Bet, cold4Bet }

class TreeSpot {
  const TreeSpot(this.scenario, {this.opener, this.threeBettor, this.openBb = 0, this.threeBetBb = 0, this.limpers = 0, this.callers = 0, this.potBb = 1.5});
  final TreeScenario scenario;
  final Position? opener;
  final Position? threeBettor;
  final double openBb;
  final double threeBetBb;
  final int limpers;
  final int callers;
  final double potBb;
}

/// Árbol preflop 6-max completo (1-6 jugadores activos) que converge a HU.
class FullTreePreflop {
  const FullTreePreflop({this.engine = const PreflopSolverEngine()});

  final PreflopSolverEngine engine;

  static const isoIp = 3.5, isoOop = 4.5;
  static const squeezeIp = 3.5, squeezeOop = 4.5;
  static const cold4BetIp = 2.2, cold4BetOop = 2.5;

  static const squeezeExtra = 'TT+,AQs+,AKo,A5s,A4s,KQs';
  static const cold4Bet = 'QQ+,AKs,AKo';

  /// "Baja frecuencia" según especificación del usuario: parámetro explícito, no frecuencia de solver.
  static const cold4BetBluff = 'A5s';
  static const cold4BetBluffWeight = 0.25;

  static TreeSpot classify(GameState s) {
    final pre = s.actions.where((a) => a.street == Street.preflop).toList();
    final committed = <Position, double>{Position.sb: 0.5, Position.bb: 1.0};
    var current = 1.0;
    final raises = <PlayerAction>[];
    var limpers = 0, callersAfterOpen = 0;
    for (final a in pre) {
      if (a.isAggressive) {
        committed[a.actor] = a.amountBb;
        current = a.amountBb;
        raises.add(a);
      } else if (a.type == ActionType.call) {
        committed[a.actor] = current;
        if (raises.isEmpty) {
          limpers++;
        } else if (raises.length == 1) {
          callersAfterOpen++;
        }
      }
    }
    final pot = committed.values.fold<double>(0, (x, y) => x + y);
    final hero = s.heroPosition;
    if (raises.isEmpty) {
      return TreeSpot(limpers > 0 ? TreeScenario.isoVsLimpers : TreeScenario.rfi, limpers: limpers, potBb: pot);
    }
    if (raises.length == 1 && raises[0].actor != hero) {
      final callers = limpers + callersAfterOpen;
      return TreeSpot(callers > 0 ? TreeScenario.squeeze : TreeScenario.threeBetHu,
          opener: raises[0].actor, openBb: raises[0].amountBb, callers: callers, potBb: pot);
    }
    if (raises.length == 2) {
      return TreeSpot(raises[0].actor == hero ? TreeScenario.standard4Bet : TreeScenario.cold4Bet,
          opener: raises[0].actor, threeBettor: raises[1].actor, openBb: raises[0].amountBb, threeBetBb: raises[1].amountBb, potBb: pot);
    }
    throw UnsupportedError('Nodo preflop no soportado (5-bet+ / limp-raise)');
  }

  static bool isLimpReraise(GameState s) {
    final pre = s.actions.where((a) => a.street == Street.preflop).toList();
    final firstRaise = pre.indexWhere((a) => a.isAggressive);
    if (firstRaise < 0 || pre[firstRaise].actor != s.heroPosition) return false;
    final limpers = {for (final a in pre.take(firstRaise)) if (a.type == ActionType.call) a.actor};
    return pre.skip(firstRaise + 1).any((a) => a.isAggressive && limpers.contains(a.actor));
  }

  DecisionOutput decide(GameState s, {ReadProfile? read}) {
    if (s.hero == null) throw const MissingInputs(['hero']);
    final spot = classify(s);
    final hand = HandNormalizer.normalize(s.hero!);
    if (spot.scenario == TreeScenario.standard4Bet &&
        (isLimpReraise(s) || read?.archetype == GgArchetype.trapperLimpReraiser)) {
      if (s.effectiveStackBb == null) throw const MissingInputs(['effectiveStackBb']);
      final (r, why) = TrapperDecoder.respond(hand.label,
          raiseToBb: spot.threeBetBb, heroRaiseBb: spot.openBb, effStackBb: s.effectiveStackBb!);
      final call = spot.threeBetBb - spot.openBb;
      return DecisionOutput(
        action: switch (r) {
          TrapperResponse.fourBetJam => DecisionAction.betRaise,
          TrapperResponse.call || TrapperResponse.setMineCall => DecisionAction.call,
          TrapperResponse.fold => DecisionAction.fold,
        },
        sizing: switch (r) {
          TrapperResponse.fourBetJam => Sizing(bb: s.effectiveStackBb!, potPct: s.effectiveStackBb! / spot.potBb * 100),
          TrapperResponse.call || TrapperResponse.setMineCall => Sizing(bb: call, potPct: call / spot.potBb * 100),
          TrapperResponse.fold => null,
        },
        justificacionGto: 'Limp-reraise: poda del 95% del rango; ${hand.label} vs AA/KK/AKs.',
        ajusteExplotativoRead: why,
      );
    }
    return switch (spot.scenario) {
      TreeScenario.isoVsLimpers => _iso(s, spot, hand),
      TreeScenario.squeeze => _squeeze(s, spot, hand),
      TreeScenario.cold4Bet => _cold4Bet(s, spot, hand),
      _ => engine.decide(s),
    };
  }

  static bool _lowNoEqr(int i) {
    if (Matrix169.isPair(i)) return false;
    final h = Matrix169.highRank(i), l = Matrix169.lowRank(i);
    final suitedConnector = Matrix169.isSuited(i) && h - l == 1;
    return h < 8 && !suitedConnector;
  }

  static Float32List isoRange(Position hero, RakeTier tier, {required bool station}) {
    if (station) return RangeNotation.parse(PreflopRangesDb.stationValue3Bet);
    final tighter = switch (hero) {
      Position.utg || Position.mp => Position.utg,
      Position.sb || Position.bb => Position.co,
      _ => Position.values[hero.index - 1],
    };
    final base = Float32List.fromList(PreflopRangesDb.rfi(tighter, tier).weights[PreflopAction.raise]!);
    for (var i = 0; i < 169; i++) {
      if (_lowNoEqr(i)) base[i] = 0;
    }
    return base;
  }

  static double isoSize(Position hero, int limpers) =>
      (hero == Position.sb || hero == Position.bb ? isoOop : isoIp) + limpers;

  static double squeezeSize(double open, int callers, {required bool ip}) =>
      open * (ip ? squeezeIp : squeezeOop) + open * callers;

  DecisionOutput _iso(GameState s, TreeSpot spot, CanonicalHand hand) {
    final hero = s.heroPosition;
    final station = s.villainProfile == VillainProfile.callingStation;
    final r = isoRange(hero, s.rakeTier, station: station);
    final size = isoSize(hero, spot.limpers);
    final raise = r[hand.index] > 0;
    final ip = hero != Position.sb && hero != Position.bb;
    return DecisionOutput(
      action: raise ? DecisionAction.betRaise : (hero == Position.bb ? DecisionAction.check : DecisionAction.fold),
      sizing: raise ? Sizing(bb: size, potPct: size / spot.potBb * 100) : null,
      metrics: [KeyMetric(MetricType.eqr, hand.eqr)],
      justificacionGto: '${hand.label} iso vs ${spot.limpers} limper(s) | ${ip ? 'IP' : 'OOP'} | rango lineal depurado '
          '(${Matrix169.percent(r).toStringAsFixed(1)}%, sin bluffs bajos sin EQR) | sizing ${ip ? isoIp : isoOop}bb + ${spot.limpers}bb',
      ajusteExplotativoRead: station ? 'Station limper: iso solo por valor lineal.' : 'Limpers = rango capado; iso para jugar HU con iniciativa.',
    );
  }

  DecisionOutput _squeeze(GameState s, TreeSpot spot, CanonicalHand hand) {
    final hero = s.heroPosition, opener = spot.opener!;
    final ip = hero.isInPositionVs(opener) && hero != Position.sb && hero != Position.bb;
    final value = RangeNotation.union([PreflopRangesDb.threeBetValue[opener] ?? '', squeezeExtra]);
    final raise = value[hand.index] > 0 && !_lowNoEqr(hand.index);
    var size = squeezeSize(spot.openBb, spot.callers, ip: ip);
    final allIn = s.effectiveStackBb != null && size >= s.effectiveStackBb!;
    if (allIn) size = s.effectiveStackBb!;
    return DecisionOutput(
      action: raise ? DecisionAction.betRaise : DecisionAction.fold,
      sizing: raise ? Sizing(bb: size, potPct: size / spot.potBb * 100) : null,
      metrics: [KeyMetric(MetricType.eqr, hand.eqr), KeyMetric(MetricType.blocker, hand.blockerWeight)],
      justificacionGto: '${hand.label} squeeze vs open ${opener.name.toUpperCase()} + ${spot.callers} caller(s) | '
          'rango condensado valor + blockers Ax/Kx suited (${Matrix169.percent(value).toStringAsFixed(1)}%) | '
          'especulativas bajas fuera (pierden EQR multiway) | 0% cold call',
      ajusteExplotativoRead: 'Sizing ${ip ? squeezeIp : squeezeOop}x open + ${spot.callers}x open por caller = ${size.toStringAsFixed(2)}bb${allIn ? ' (all-in)' : ''}.',
    );
  }

  DecisionOutput _cold4Bet(GameState s, TreeSpot spot, CanonicalHand hand) {
    if (s.effectiveStackBb == null) throw const MissingInputs(['effectiveStackBb']);
    final hero = s.heroPosition, tb = spot.threeBettor!;
    final ip = hero.isInPositionVs(tb);
    final value = RangeNotation.parse(cold4Bet)[hand.index] > 0;
    final bluff = RangeNotation.parse(cold4BetBluff)[hand.index] > 0 &&
        s.villainProfile != VillainProfile.nit &&
        s.villainProfile != VillainProfile.callingStation;
    final f = value ? 1.0 : (bluff ? cold4BetBluffWeight : 0.0);
    final raise = f >= 1 || (f > 0 && _u(hand.index) < f);
    var size = spot.threeBetBb * (ip ? cold4BetIp : cold4BetOop);
    final potAfter = spot.potBb - spot.threeBetBb + 2 * size;
    final jam = (s.effectiveStackBb! - size) / potAfter < 1;
    if (jam) size = s.effectiveStackBb!;
    return DecisionOutput(
      action: raise ? DecisionAction.betRaise : DecisionAction.fold,
      sizing: raise ? Sizing(bb: size, potPct: size / spot.potBb * 100) : null,
      metrics: [KeyMetric(MetricType.blocker, hand.blockerWeight, 'vs QQ+/AK')],
      justificacionGto: '${hand.label} cold 4-bet vs open ${spot.opener!.name.toUpperCase()} + 3-bet ${tb.name.toUpperCase()} | '
          'rango ultra-estrecho QQ+/AK (dos rangos fuertes delante) + A5s blocker-bluff baja frecuencia | 0% cold call',
      ajusteExplotativoRead: '${raise ? (jam ? 'All-in (SPR post-4bet < 1).' : '${ip ? cold4BetIp : cold4BetOop}x = ${size.toStringAsFixed(1)}bb.') : 'Fold.'}'
          '${s.villainProfile == VillainProfile.nit ? ' Nit: sin bluff.' : ''}',
    );
  }

  double _u(int i) => ((engine.seed ^ (i * 2654435761)) & 0xFFFFFFFF) / 0x100000000;
}
