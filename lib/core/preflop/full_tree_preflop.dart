import 'dart:typed_data';

import '../discipline/ev_sanity_guard.dart';
import '../models/action_mixer.dart';
import '../models/decision_output.dart';
import '../models/game_state.dart';
import '../reads/gg_profiler.dart';
import 'hand_normalizer.dart';
import 'preflop_ranges_db.dart';
import 'preflop_solver_engine.dart';
import 'range_notation.dart';
import 'structure_modifier.dart';

enum TreeScenario { rfi, isoVsLimpers, threeBetHu, squeeze, standard4Bet, cold4Bet, facing4Bet, facing5Bet }

class TreeSpot {
  const TreeSpot(this.scenario, {this.opener, this.threeBettor, this.openBb = 0, this.threeBetBb = 0, this.limpers = 0, this.callers = 0, this.potBb = 1.5, this.callBb = 0, this.lastRaiseBb = 0});
  final double callBb;
  final double lastRaiseBb;
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

  /// Overcall multiway (L4): pares, Ax suited, broadways suited y suited connectors 54s+.
  static const multiwayWhitelist = '22-TT,A2s-AJs,KTs+,QTs+,JTs,T9s,98s,87s,76s,65s,54s';

  /// Penalización de realización multiway para manos fuera de la whitelist (parámetro de modelo).
  static const multiwayOffsuitEqr = 0.80;

  /// Iso vs Rec_Passive_Fish: Iso_Raise_Linear top ~32% en CO/BTN/ciegas (prior del usuario, Fase 9.1).
  static const fishIsoRange = '22+,A2s+,K5s+,Q8s+,J8s+,T8s+,97s+,87s,76s,65s,A7o+,A5o,K9o+,Q9o+,J9o+';

  static const callOff = 'QQ+,AKs,AKo';
  static const callOffVsNit = 'KK+,AKs';
  static const fiveBetJam = 'QQ+,AKs,AKo';
  static const call4BetIp = 'TT-JJ,AQs';
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
    final pot = committed.values.fold<double>(0, (x, y) => x + y) + s.extraDeadMoneyBb;
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
    final heroIn = committed[hero] ?? 0;
    if (raises.length == 3 && raises[1].actor == hero) {
      return TreeSpot(TreeScenario.facing4Bet, opener: raises[0].actor, threeBettor: hero, potBb: pot,
          callBb: current - heroIn, lastRaiseBb: current);
    }
    if (raises.length == 4 && raises[2].actor == hero) {
      return TreeSpot(TreeScenario.facing5Bet, opener: raises[0].actor, threeBettor: raises[1].actor, potBb: pot,
          callBb: current - heroIn, lastRaiseBb: current);
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
    final vp = read?.engineProfile ?? s.villainProfile;
    final d = switch (spot.scenario) {
      TreeScenario.isoVsLimpers => _iso(s, spot, hand, vp),
      TreeScenario.squeeze => _squeeze(s, spot, hand),
      TreeScenario.cold4Bet => _cold4Bet(s, spot, hand),
      TreeScenario.facing4Bet || TreeScenario.facing5Bet => _facingBig(s, spot, hand, vp),
      _ => engine.decide(read == null ? s : s.copyWith(villainProfile: vp), read: read),
    };
    final call = switch (spot.scenario) {
      TreeScenario.facing4Bet || TreeScenario.facing5Bet => spot.callBb,
      _ => d.sizing?.bb ?? 0,
    };
    return EvSanityGuard.preflop(s, d, hand.label, callBb: call, potBb: spot.potBb);
  }

  /// Hero enfrenta 4-bet (tras su 3-bet) o 5-bet (tras su 4-bet). Blocker-bluffs: 100% fold salvo pot odds <= 28%.
  DecisionOutput _facingBig(GameState s, TreeSpot spot, CanonicalHand hand, VillainProfile vp) {
    if (s.effectiveStackBb == null) throw const MissingInputs(['effectiveStackBb']);
    final i = hand.index;
    final stack = s.effectiveStackBb!;
    final allIn = spot.lastRaiseBb >= stack * 0.9 || spot.scenario == TreeScenario.facing5Bet;
    final tight = vp == VillainProfile.nit || vp == VillainProfile.trapperPremium;
    final odds = spot.callBb / (spot.potBb + spot.callBb);
    final callOffR = RangeNotation.parse(StructureModifier.stackOffRange(stack, vp, tight ? callOffVsNit : callOff));
    final ip = s.heroPosition.isInPositionVs(spot.opener!);
    final label = spot.scenario == TreeScenario.facing5Bet ? '5-bet' : '4-bet';
    DecisionOutput out(DecisionAction a, String why, {Sizing? sz}) => DecisionOutput(
          action: a,
          sizing: sz,
          metrics: [KeyMetric(MetricType.potOdds, odds), KeyMetric(MetricType.blocker, hand.blockerWeight)],
          justificacionGto: '${hand.label} vs $label ${allIn ? 'all-in' : '${spot.lastRaiseBb}bb'} | pot odds ${(odds * 100).round()}%',
          ajusteExplotativoRead: why,
        );
    if (allIn) {
      if (callOffR[i] > 0) return out(DecisionAction.call, 'Call-off: ${tight ? 'KK+/AKs vs nit' : 'QQ+/AK'}.', sz: Sizing(bb: spot.callBb, potPct: spot.callBb / spot.potBb * 100));
      if (odds <= EvSanityGuard.allInDirectOddsMax) {
        return out(DecisionAction.call, 'Stacks cortos: pot odds directas ${(odds * 100).round()}% <= 28%.', sz: Sizing(bb: spot.callBb, potPct: spot.callBb / spot.potBb * 100));
      }
      return out(DecisionAction.fold, PreflopRangesDb.isBluff4Bet(i) ? '${hand.label} es farol/blocker: 100% fold vs $label all-in.' : 'Fuera del rango de call-off.');
    }
    if (RangeNotation.parse(StructureModifier.stackOffRange(stack, vp, tight ? callOffVsNit : fiveBetJam))[i] > 0) {
      return out(DecisionAction.betRaise, '5-bet jam por valor.', sz: Sizing(bb: stack, potPct: stack / spot.potBb * 100));
    }
    if (ip && !tight && RangeNotation.parse(call4BetIp)[i] > 0) {
      return out(DecisionAction.call, 'Call IP vs 4-bet no all-in.', sz: Sizing(bb: spot.callBb, potPct: spot.callBb / spot.potBb * 100));
    }
    return out(DecisionAction.fold, PreflopRangesDb.isBluff4Bet(i) ? '${hand.label}: blocker-bluff, fold vs 4-bet grande.' : 'Fold vs 4-bet.');
  }

  static bool _lowNoEqr(int i) {
    if (Matrix169.isPair(i)) return false;
    final h = Matrix169.highRank(i), l = Matrix169.lowRank(i);
    final suitedConnector = Matrix169.isSuited(i) && h - l == 1;
    return h < 8 && !suitedConnector;
  }

  static Float32List isoRange(Position hero, RakeTier tier, {required bool station}) {
    if (station) {
      if (hero == Position.utg || hero == Position.mp) {
        return RangeNotation.union([PreflopRangesDb.stationValue3Bet, PreflopRangesDb.rfiNotation(Position.utg, tier)]);
      }
      return RangeNotation.parse(fishIsoRange);
    }
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

  DecisionOutput _iso(GameState s, TreeSpot spot, CanonicalHand hand, VillainProfile vp) {
    final hero = s.heroPosition;
    final station = vp == VillainProfile.callingStation;
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
      ajusteExplotativoRead: station
          ? 'Fish limper: iso lineal ancho (rango del limper capado e inelástico) con sizing punitivo.'
          : 'Limpers = rango capado; iso para jugar HU con iniciativa.',
    );
  }

  DecisionOutput _squeeze(GameState s, TreeSpot spot, CanonicalHand hand) {
    final hero = s.heroPosition, opener = spot.opener!;
    final ip = hero.isInPositionVs(opener) && hero != Position.sb && hero != Position.bb;
    final value = RangeNotation.union([PreflopRangesDb.threeBetValue[opener] ?? '', squeezeExtra]);
    final raise = value[hand.index] > 0 && !_lowNoEqr(hand.index);
    if (!raise && (hero == Position.bb || hero == Position.btn)) {
      final oc = overcall(s, spot, hand);
      if (oc != null) return oc;
    }
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

  /// L4: overcall multiway en BB/BTN. eq_MW = eq_HU(vs opener) x 2/N x EQR_MW >= pot odds con rake final esperado.
  DecisionOutput? overcall(GameState s, TreeSpot spot, CanonicalHand hand) {
    final hero = s.heroPosition, opener = spot.opener!;
    final tk = s.rakeTier == RakeTier.microHighRake ? 'HR' : 'MR';
    final eqHu = HandProps.equity('${tk}_RFI_${opener.name}', hand.index);
    if (eqHu == null) return null;
    final white = RangeNotation.parse(multiwayWhitelist)[hand.index] > 0;
    if (hero == Position.btn && !white) return null;
    final n = spot.callers + 2;
    final committed = hero == Position.bb ? 1.0 : 0.0;
    final call = spot.openBb - committed;
    final req = engine.rakedPotOdds(call, spot.potBb, s.rakeTier, stake: s.stake);
    final eqr = white ? hand.eqr : hand.eqr * multiwayOffsuitEqr;
    final eqMw = eqHu * 2 / n * eqr;
    if (eqMw < req) return null;
    return DecisionOutput(
      action: DecisionAction.call,
      sizing: Sizing(bb: call, potPct: call / spot.potBb * 100),
      metrics: [
        KeyMetric(MetricType.equity, eqMw, 'eq multiway estimada (eq_HU x 2/N x EQR_MW)'),
        KeyMetric(MetricType.requiredEquity, req, 'pot odds con rake final esperado'),
      ],
      justificacionGto: '${hand.label} overcall multiway ${hero.name.toUpperCase()} vs open ${opener.name.toUpperCase()} + ${spot.callers} caller(s) | '
          '${white ? 'whitelist multiway (pares/suited)' : 'offsuit con EQR_MW x$multiwayOffsuitEqr'} | eq ${(eqMw * 100).toStringAsFixed(1)}% >= ${(req * 100).toStringAsFixed(1)}%',
      ajusteExplotativoRead: hero == Position.bb ? 'BB cierra la acción con odds directas.' : 'BTN IP: overcall con manos de alta realización multiway.',
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
    final (pick, roll, norm) = DeterministicActionMixer.select([s.hero!.high, s.hero!.low], const [], spot.potBb,
        {DecisionAction.betRaise: f, DecisionAction.fold: 1 - f});
    final raise = pick == DecisionAction.betRaise;
    var size = spot.threeBetBb * (ip ? cold4BetIp : cold4BetOop);
    final potAfter = spot.potBb - spot.threeBetBb + 2 * size;
    final jam = (s.effectiveStackBb! - size) / potAfter < 1;
    if (jam) size = s.effectiveStackBb!;
    return DecisionOutput(
      action: raise ? DecisionAction.betRaise : DecisionAction.fold,
      sizing: raise ? Sizing(bb: size, potPct: size / spot.potBb * 100) : null,
      freqGto: norm,
      freqSource: norm.length > 1 ? FreqSource.modelCalibrated : FreqSource.pure,
      roll: norm.length > 1 ? roll : null,
      metrics: [KeyMetric(MetricType.blocker, hand.blockerWeight, 'vs QQ+/AK')],
      justificacionGto: '${hand.label} cold 4-bet vs open ${spot.opener!.name.toUpperCase()} + 3-bet ${tb.name.toUpperCase()} | '
          'rango ultra-estrecho QQ+/AK (dos rangos fuertes delante) + A5s blocker-bluff baja frecuencia | 0% cold call',
      ajusteExplotativoRead: '${raise ? (jam ? 'All-in (SPR post-4bet < 1).' : '${ip ? cold4BetIp : cold4BetOop}x = ${size.toStringAsFixed(1)}bb.') : 'Fold.'}'
          '${s.villainProfile == VillainProfile.nit ? ' Nit: sin bluff.' : ''}',
    );
  }

}
