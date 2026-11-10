import 'dart:typed_data';

import '../models/decision_output.dart';
import '../models/game_state.dart';
import '../models/action_mixer.dart';
import '../reads/gg_profiler.dart';
import '../postflop/postflop_ranges.dart';
import 'hand_normalizer.dart';
import 'structure_modifier.dart';
import 'preflop_ranges_db.dart';
import 'range_notation.dart';

enum PreflopScenario { rfi, vsRfi, vs3Bet }

class PreflopContext {
  PreflopContext._(this.scenario, this.villain, this.raiseSizeBb, this.heroOpenBb, this.potBb,
      this.callBb, this.limpers, this.coldCallers);

  final PreflopScenario scenario;
  final Position? villain;
  final double raiseSizeBb;
  final double heroOpenBb;
  final double potBb;
  final double callBb;
  final int limpers;
  final int coldCallers;

  static PreflopContext from(GameState s) {
    final pre = s.actions.where((a) => a.street == Street.preflop).toList();
    final committed = <Position, double>{Position.sb: 0.5, Position.bb: 1.0};
    var current = 1.0;
    final raises = <PlayerAction>[];
    var limpers = 0, coldCallers = 0;
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
          coldCallers++;
        }
      }
    }
    final pot = committed.values.fold<double>(0, (x, y) => x + y) + s.extraDeadMoneyBb;
    final call = current - (committed[s.heroPosition] ?? 0);

    if (raises.isEmpty) {
      return PreflopContext._(PreflopScenario.rfi, s.villainPosition, 0, 0, pot, call, limpers, 0);
    }
    if (raises.length == 1 && raises[0].actor != s.heroPosition) {
      return PreflopContext._(PreflopScenario.vsRfi, raises[0].actor, raises[0].amountBb, 0, pot,
          call, limpers, coldCallers);
    }
    if (raises.length == 2 && raises[0].actor == s.heroPosition) {
      return PreflopContext._(PreflopScenario.vs3Bet, raises[1].actor, raises[1].amountBb,
          raises[0].amountBb, pot, call, 0, 0);
    }
    throw UnsupportedError('Nodo preflop no soportado (4-bet+, limp-raise o acción inconsistente)');
  }
}

class PreflopSolverEngine {
  /// Expansión del 3-bet de defensa vs Maniac (prior del usuario, Fase 9.1).
  static const maniac3BetExpansion = 0.12;

  /// Expansión del steal desde CO vs ciegas Nit (prior del usuario, Fase 9.1). BTN/SB mantienen steal 100%.
  static const nitStealExpansion = 0.15;

  static final _maniacCache = <String, Float32List>{};

  /// Rango 3-bet base (raise > 0) + mejores manos por equity vs el RFI del opener hasta +12% de 1326 combos.
  static Float32List maniacDefense3Bet(Position hero, Position opener, RakeTier tier) =>
      _maniacCache.putIfAbsent('${hero.name}|${opener.name}|${tier.name}', () {
        final raise = PreflopRangesDb.vsRfi(hero, opener, tier).weights[PreflopAction.raise];
        final out = Float32List(169);
        for (var i = 0; i < 169; i++) {
          if ((raise?[i] ?? 0) > 0) out[i] = 1;
        }
        final key = '${_tk(tier)}_RFI_${opener.name}';
        final cand = [for (var i = 0; i < 169; i++) if (out[i] == 0) i]
          ..sort((a, b) => HandProps.equity(key, b)!.compareTo(HandProps.equity(key, a)!));
        var added = 0.0;
        for (final i in cand) {
          if (added >= maniac3BetExpansion * 1326) break;
          added += Matrix169.combos(i);
          out[i] = 1;
        }
        return out;
      });

  const PreflopSolverEngine({this.rake = RakeConfig.defaults, this.seed = 0});

  final Map<RakeTier, RakeConfig> rake;
  final int seed;

  static const ipMultiplier = 1.10;
  static const oopMultiplier = 0.85;

  DecisionOutput decide(GameState s, {ReadProfile? read}) {
    final missing = s.missingForPreflop();
    if (missing.isNotEmpty) throw MissingInputs(missing);
    final ctx = PreflopContext.from(s);
    final hand = HandNormalizer.normalize(s.hero!);
    final d = switch (ctx.scenario) {
      PreflopScenario.rfi => _rfi(s, ctx, hand),
      PreflopScenario.vsRfi => _vsRfi(s, ctx, hand),
      PreflopScenario.vs3Bet => _vs3Bet(s, ctx, hand, read),
    };
    return d.copyWith(actionEVs: preflopEVs(s, ctx, hand, raiseTo: d.action == DecisionAction.betRaise ? d.sizing?.bb : null));
  }

  static double _combos(Float32List w) {
    var c = 0.0;
    for (var i = 0; i < 169; i++) {
      c += w[i] * Matrix169.combos(i);
    }
    return c;
  }

  /// EV aproximado preflop (bb, relativo a fold = 0): equity tabulada x EQR x posición, rake del bote final esperado.
  /// FE = fracción del rango rival que foldea según los propios nodos del árbol; equity vs continuación = tabla proxy.
  Map<String, double> preflopEVs(GameState s, PreflopContext ctx, CanonicalHand hand, {double? raiseTo}) {
    final i = hand.index;
    final tier = s.rakeTier;
    final rk = RakeConfig.byStake[s.stake]!;
    final villain = ctx.villain;
    final ipVsVillain = villain != null && s.heroPosition.isInPositionVs(villain);
    final eqr = hand.eqr * stackEqrMultiplier(i, s.effectiveStackBb) * (ipVsVillain ? ipMultiplier : oopMultiplier);
    switch (ctx.scenario) {
      case PreflopScenario.rfi:
        final open = raiseTo ?? (PreflopRangesDb.openSizeBb[s.heroPosition] ?? 2.5);
        var fe = 1.0;
        for (final p in Position.values) {
          if (p.index <= s.heroPosition.index || s.heroPosition == Position.bb) continue;
          final n = PreflopRangesDb.vsRfi(p, s.heroPosition, tier);
          final cont = p == Position.bb
              ? (n.percent(PreflopAction.raise) + Matrix169.percent(PostflopRangesProxy.bbDefend(s.heroPosition, tier))) / 100
              : (n.percent(PreflopAction.raise) + n.percent(PreflopAction.call)) / 100;
          fe *= 1 - cont;
        }
        final eqC = HandProps.equity('MR_RFI_utg', i)!;
        final fin = 2 * open + 1.5 - (s.heroPosition == Position.sb ? 0.5 : 0);
        final evOpen = fe * ctx.potBb + (1 - fe) * (eqC * hand.eqr * (fin - rk.rakeOn(fin)) - open);
        return {'fold': 0, 'betRaise': evOpen};
      case PreflopScenario.vsRfi:
        final eq = HandProps.equity('${_tk(tier)}_RFI_${villain!.name}', i)!;
        final call = ctx.callBb;
        final finCall = ctx.potBb + call;
        final evCall = eq * eqr * (finCall - rk.rakeOn(finCall)) - call;
        final r = raiseTo ?? ctx.raiseSizeBb * 3;
        final heroIp = s.heroPosition.isInPositionVs(villain);
        final vs3 = PreflopRangesDb.vs3Bet(villain, heroInPosition: !heroIp);
        final cont = (_combos(vs3.weights[PreflopAction.raise]!) + _combos(vs3.weights[PreflopAction.call]!)) /
            _combos(PreflopRangesDb.rfi(villain, tier).weights[PreflopAction.raise]!);
        final fe = (1 - cont).clamp(0.0, 1.0);
        final eqC = HandProps.equity('MR_RFI_utg', i)!;
        final fin3 = 2 * r + (ctx.potBb - ctx.raiseSizeBb - (s.heroPosition == Position.bb ? 1 : (s.heroPosition == Position.sb ? 0.5 : 0)));
        final ev3 = fe * ctx.potBb + (1 - fe) * (eqC * eqr * (fin3 - rk.rakeOn(fin3)) - r);
        return {'fold': 0, 'call': evCall, 'betRaise': ev3};
      case PreflopScenario.vs3Bet:
        final eq = HandProps.equity('${_tk(tier)}_3B_${villain!.name}_${s.heroPosition.name}', i) ?? HandProps.equity('MR_RFI_utg', i)!;
        final call = ctx.callBb;
        final finCall = ctx.potBb + call;
        final evCall = eq * eqr * (finCall - rk.rakeOn(finCall)) - call;
        final r = raiseTo ?? ctx.raiseSizeBb * 2.3;
        final tb = HandProps.equity('BLOCKER_REF', i)!;
        final valueShare = 34 / 1326 / (Matrix169.percent(RangeNotation.parse(PreflopRangesDb.threeBetValue[s.heroPosition] ?? 'QQ+,AKs,AKo')) / 100 + 1e-9);
        final fe = (1 - valueShare).clamp(0.0, 0.9);
        final fin4 = 2 * r + 1.5;
        final ev4 = fe * ctx.potBb + (1 - fe) * (tb * eqr * (fin4 - rk.rakeOn(fin4)) - (r - ctx.heroOpenBb));
        return {'fold': 0, 'call': evCall, 'betRaise': ev4};
    }
  }

  static String _tk(RakeTier t) => t == RakeTier.microHighRake ? 'HR' : 'MR';
  String _tierLabel(RakeTier t) => t == RakeTier.microHighRake ? 'High-Rake (NL2-NL25)' : 'Mid-Rake (NL50-NL200)';

  double potOddsRequired(double call, double pot) => call / (pot + call);

  /// Pot odds con rake sobre el bote final esperado: (call / (pot + call)) / (1 - rake_efectivo[PotType]).
  double rakedPotOdds(double call, double pot, RakeTier tier, {PotType potType = PotType.srp, Stake? stake}) =>
      call / (pot + call) / (1 - (stake != null ? RakeConfig.byStake[stake]! : rake[tier]!).effectiveRate(potType));

  double requiredEquity(double rakedOdds, double eqr, bool ip) =>
      rakedOdds / (eqr * (ip ? ipMultiplier : oopMultiplier));

  static const _toDecision = {
    PreflopAction.raise: DecisionAction.betRaise,
    PreflopAction.call: DecisionAction.call,
    PreflopAction.fold: DecisionAction.fold,
  };

  /// Selección por mezclador determinista sobre las cartas exactas de Hero.
  (PreflopAction, int, Map<DecisionAction, double>) _pick(Map<PreflopAction, double> f, GameState s) {
    final w = {for (final e in f.entries) if (e.value > 0) _toDecision[e.key]!: e.value};
    final (a, roll, norm) = DeterministicActionMixer.select([s.hero!.high, s.hero!.low], const [], s.potBb ?? 1.5, w);
    final pa = switch (a) { DecisionAction.betRaise => PreflopAction.raise, DecisionAction.call => PreflopAction.call, _ => PreflopAction.fold };
    return (pa, roll, norm);
  }

  static FreqSource _src(RangeNode? n, Map<DecisionAction, double> norm) {
    if (n?.source == RangeSource.solverImport) return FreqSource.solverImport;
    if (n?.source == RangeSource.bootstrapGTO) return FreqSource.bootstrapGTO;
    return norm.length > 1 ? FreqSource.modelCalibrated : FreqSource.pure;
  }

  /// Margen de frontera (±3%) donde la decisión call/fold se mezcla linealmente por equity.
  static const boundaryBand = 0.03;

  static double boundaryWeight(double eq, double req) => ((eq - req) / (2 * boundaryBand) + 0.5).clamp(0.0, 1.0);

  /// EQR por profundidad: >120bb premia suited/pares (nutted), <60bb premia pares y high cards.
  static double stackEqrMultiplier(int i, double? stack) {
    if (stack == null) return 1.0;
    if (stack > StructureModifier.ultraDeepBb) return StructureModifier.ultraDeepEqr(i, stack) * (Matrix169.isPair(i) || Matrix169.isSuited(i) ? 1.05 : 0.97);
    final pair = Matrix169.isPair(i), suited = Matrix169.isSuited(i);
    final high = Matrix169.highRank(i), low = Matrix169.lowRank(i);
    if (stack > 120) return pair || suited ? 1.05 : 0.97;
    if (stack < 60) {
      if (pair || low >= 8) return 1.05;
      if (suited && high < 8) return 0.95;
    }
    return 1.0;
  }

  static final _bbCache = <String, Float32List>{};
  static const _monoExempt = {'A5s', 'A4s', 'A3s', 'A2s', 'A5o', 'A4o', 'A3o', 'A2o'};

  /// Pesos de continuación BB (frontera mezclada) con corrección isotónica: la mano dominante nunca continúa menos
  /// que la dominada (corrige ruido Monte Carlo de la tabla de equity).
  Float32List _bbContinue(Position opener, RakeTier tier, PreflopContext ctx, double? stack, double raked) {
    final key = '${opener.name}|${tier.name}|${ctx.callBb}|${ctx.potBb}|${stack?.round()}|${raked.toStringAsFixed(6)}|$seed';
    return _bbCache.putIfAbsent(key, () {
      if (_bbCache.length > 128) _bbCache.clear();
      final w = Float32List(169);
      for (var i = 0; i < 169; i++) {
        final eq = HandProps.equity('${_tk(tier)}_RFI_${opener.name}', i)!;
        final req = requiredEquity(raked, HandProps.eqr[i] * stackEqrMultiplier(i, stack), false);
        w[i] = boundaryWeight(eq, req);
      }
      for (var r = 12; r > 0; r--) {
        final lo = Matrix169.index(r, r, suited: false), hi = Matrix169.index(r - 1, r - 1, suited: false);
        if (w[hi] < w[lo]) w[hi] = w[lo];
      }
      for (final suited in [true, false]) {
        for (var h = 0; h < 12; h++) {
          for (var k = 12; k > h + 1; k--) {
            final low = Matrix169.index(h, k, suited: suited), up = Matrix169.index(h, k - 1, suited: suited);
            if (_monoExempt.contains(Matrix169.label(low))) continue;
            if (w[up] < w[low]) w[up] = w[low];
          }
        }
      }
      return w;
    });
  }

  /// 3-bet que compromete >= 25% del stack efectivo => shove (stacks cortos 20-40bb).
  static const commitThreshold = 0.25;

  /// Set-mining viable: implícitas >= 12x el call.
  static bool setMiningOk(double call, double? stack) => stack != null && stack >= 12 * call;

  String _freqLabel(Map<PreflopAction, double> f) {
    final parts = [
      for (final a in [PreflopAction.raise, PreflopAction.call, PreflopAction.fold])
        if ((f[a] ?? 0) > 0) '${((f[a] ?? 0) * 100).round()}% ${a.name}',
    ];
    return parts.join(' / ');
  }

  DecisionOutput _rfi(GameState s, PreflopContext ctx, CanonicalHand hand) {
    final hero = s.heroPosition;
    final tier = s.rakeTier;
    final station = s.villainProfile == VillainProfile.callingStation;
    final ip = hero != Position.sb && hero != Position.bb;

    if (hero == Position.bb && ctx.limpers == 0) {
      return DecisionOutput(
          action: DecisionAction.check,
          justificacionGto: 'BB sin open: walk/check.',
          ajusteExplotativoRead: 'N/A');
    }

    Float32List range;
    String rangeLabel;
    if (ctx.limpers > 0) {
      if (station) {
        range = RangeNotation.parse(PreflopRangesDb.stationValue3Bet);
        rangeLabel = 'iso lineal de valor vs recreativo';
      } else {
        final tighter = hero == Position.utg || hero == Position.bb
            ? Position.utg
            : Position.values[hero.index - 1];
        range = PreflopRangesDb.rfi(tighter == Position.bb ? Position.utg : tighter, tier)
            .weights[PreflopAction.raise]!;
        rangeLabel = 'iso = RFI de ${tighter.name.toUpperCase()} (rango 1 posición más tight)';
      }
    } else {
      final exp = StructureModifier.rfiExpansion(s, hero);
      range = exp > 0 ? StructureModifier.expandedRfi(hero, tier, exp) : PreflopRangesDb.rfi(hero, tier).weights[PreflopAction.raise]!;
      rangeLabel = 'RFI ${hero.name.toUpperCase()} ${PreflopRangesDb.rfi(hero, tier).percent(PreflopAction.raise).toStringAsFixed(1)}%';
    }

    final stealVsNit = s.villainProfile == VillainProfile.nit &&
        ctx.limpers == 0 &&
        (hero == Position.btn || hero == Position.sb);
    final coStealVsNit = s.villainProfile == VillainProfile.nit && ctx.limpers == 0 && hero == Position.co;
    var w = range[hand.index].toDouble();
    if (stealVsNit) w = 1.0;
    if (coStealVsNit) {
      final exp = StructureModifier.expandedRfi(hero, tier, nitStealExpansion + StructureModifier.rfiExpansion(s, hero));
      w = exp[hand.index].toDouble();
    }

    final base = ctx.limpers > 0
        ? (ip ? 3.5 : 4.5) + ctx.limpers
        : StructureModifier.openSize(s, PreflopRangesDb.openSizeBb[hero]!);
    final f = {PreflopAction.raise: w, PreflopAction.fold: 1 - w};
    final (a, roll, norm) = _pick(f, s);
    final raise = a == PreflopAction.raise;
    final checkOption = hero == Position.bb && !raise;

    return DecisionOutput(
      action: raise ? DecisionAction.betRaise : (checkOption ? DecisionAction.check : DecisionAction.fold),
      sizing: raise ? Sizing(bb: base, potPct: base / ctx.potBb * 100) : null,
      freqGto: norm,
      freqSource: _src(ctx.limpers == 0 ? PreflopRangesDb.rfi(hero, tier) : null, norm),
      roll: norm.length > 1 ? roll : null,
      metrics: [
        KeyMetric(MetricType.eqr, hand.eqr),
        KeyMetric(MetricType.equity, hand.rawEquityVsTopRange, 'vs top range'),
      ],
      justificacionGto: '${hand.label} | ${hero.name.toUpperCase()} | ${_tierLabel(tier)} | $rangeLabel | '
          'EQR ${hand.eqr.toStringAsFixed(2)} (${hand.isSuited ? 'suited' : hand.isPair ? 'par' : 'offsuit'}) | '
          'freq tabla: ${_freqLabel(f)}${hero == Position.sb ? ' | SB: raise-or-fold, 0% complete' : ''}',
      ajusteExplotativoRead: stealVsNit
          ? 'Ciegas Nit: fold-to-steal excesivo => steal 100% cualquier dos cartas.'
          : coStealVsNit
          ? 'Ciegas Nit: Steal_RFI +${(nitStealExpansion * 100).round()}% desde CO (lineal por equity).'
          : ctx.limpers > 0
              ? 'Iso ${base}bb (${ctx.limpers} limper(s) +1bb c/u)${station ? '; station: sin bluffs, sizing agrandado' : ''}.'
              : 'Sin desviación: perfil ${s.villainProfile.name}.',
    );
  }

  DecisionOutput _vsRfi(GameState s, PreflopContext ctx, CanonicalHand hand) {
    final hero = s.heroPosition, opener = ctx.villain!, tier = s.rakeTier;
    final node = PreflopRangesDb.vsRfi(hero, opener, tier);
    final structure = PreflopRangesDb.structure(hero, opener);
    final ip = hero.isInPositionVs(opener);
    final i = hand.index;
    final profile = s.villainProfile;
    final std = PreflopRangesDb.openSizeBb[opener]!;
    final offSize = (ctx.raiseSizeBb - std).abs() > 0.25;

    var f3 = node.freq(PreflopAction.raise, i);
    var fc = node.freq(PreflopAction.call, i);
    final notes = <String>[];

    final odds = potOddsRequired(ctx.callBb, ctx.potBb);
    final raked = rakedPotOdds(ctx.callBb, ctx.potBb, tier, stake: s.stake);
    final req = requiredEquity(raked, hand.eqr * stackEqrMultiplier(i, s.effectiveStackBb), ip);
    final eq = HandProps.equity('${_tk(tier)}_RFI_${opener.name}', i)!;
    final passes = eq >= req;

    if (profile == VillainProfile.callingStation) {
      final value = RangeNotation.union([PreflopRangesDb.stationValue3Bet, _valueOf(opener)]);
      final isBluff = f3 > 0 && value[i] == 0;
      if (isBluff) {
        f3 = 0;
        notes.add('Station: elimina 3-bet bluff (no foldea, sin fold equity).');
      }
      if (value[i] > 0 && f3 < 1) {
        f3 = 1;
        fc = 0;
        notes.add('Station: 3-bet lineal de valor extendido (domina su rango de call).');
      }
    }

    if (hero == Position.bb && PreflopRangesDb.isPolarBluff3Bet(i) && f3 >= 1 && profile != VillainProfile.callingStation) {
      final r = (0.5 + (req - eq) / (2 * 0.06)).clamp(0.25, 1.0);
      f3 = r;
      fc = (1 - r) * boundaryWeight(eq, req);
      notes.add('BB: 3-bet bluff polar mezclado con call según margen de equity (raise ${(r * 100).round()}%).');
    } else if (hero == Position.bb && f3 < 1) {
      fc = (1 - f3) * _bbContinue(opener, tier, ctx, s.effectiveStackBb, raked)[i];
      notes.add('BB: call derivado de pot odds (eq ${_p(eq)} vs req ${_p(req)}${fc > 0 && fc < 1 - f3 ? ', frontera mezclada' : ''}).');
    } else if (fc > 0 && offSize && !passes) {
      fc = 0;
      notes.add('Open ${ctx.raiseSizeBb}bb (no estándar): flat no supera umbral (eq ${_p(eq)} < ${_p(req)}).');
    }

    // TAG_AGRO_MANIAC (ATS >= 55%): 3-bet de defensa en ciegas expandido +12% de combos, lineal por equity vs su RFI.
    final maniacSteal = profile == VillainProfile.maniac &&
        (hero == Position.bb || hero == Position.sb) &&
        (opener == Position.co || opener == Position.btn || opener == Position.sb);
    if (maniacSteal && f3 < 1 && maniacDefense3Bet(hero, opener, tier)[i] > 0) {
      f3 = 1;
      fc = 0;
      notes.add('Maniac ATS>=55%: 3-bet Def +${(maniac3BetExpansion * 100).round()}% lineal (${Matrix169.percent(maniacDefense3Bet(hero, opener, tier)).toStringAsFixed(1)}%).');
    }

    final f = {PreflopAction.raise: f3, PreflopAction.call: fc, PreflopAction.fold: 1 - f3 - fc};
    final (a, roll, norm) = _pick(f, s);

    final micro = tier == RakeTier.microHighRake;
    final station = profile == VillainProfile.callingStation;
    final mult = station
        ? (ip ? 4.0 : 5.0)
        : ip
            ? (micro ? 3.2 : 3.0)
            : (hero == Position.bb ? (micro ? 4.5 : 3.75) : (micro ? 4.0 : 3.75));
    var size = ctx.raiseSizeBb * mult + ctx.raiseSizeBb * ctx.coldCallers;
    final allIn = s.effectiveStackBb != null && size >= s.effectiveStackBb! * commitThreshold;
    if (allIn) size = s.effectiveStackBb!;

    final noFlat = !PreflopRangesDb.flatsAllowed(hero, opener, tier);
    final setMine = noFlat && a == PreflopAction.fold && hand.isPair && Matrix169.highRank(i) <= 7
        ? ' | ${_setMiningNote(ctx, s.effectiveStackBb, s.stake)}'
        : '';
    return DecisionOutput(
      action: switch (a) {
        PreflopAction.raise => DecisionAction.betRaise,
        PreflopAction.call => DecisionAction.call,
        PreflopAction.fold => DecisionAction.fold,
      },
      sizing: switch (a) {
        PreflopAction.raise => Sizing(bb: size, potPct: size / ctx.potBb * 100),
        PreflopAction.call => Sizing(bb: ctx.callBb, potPct: ctx.callBb / ctx.potBb * 100),
        PreflopAction.fold => null,
      },
      freqGto: norm,
      freqSource: _src(node, norm),
      roll: norm.length > 1 ? roll : null,
      metrics: [
        KeyMetric(MetricType.potOdds, odds),
        KeyMetric(MetricType.requiredEquity, req, 'pot odds con rake / (EQR x ${ip ? 'IP 1.10' : 'OOP 0.85'})'),
        KeyMetric(MetricType.equity, eq, 'vs RFI ${opener.name.toUpperCase()}'),
        KeyMetric(MetricType.eqr, hand.eqr),
        KeyMetric(MetricType.blocker, hand.blockerWeight, 'vs QQ+/AK'),
      ],
      justificacionGto: '${hand.label} ${hero.name.toUpperCase()} vs open ${opener.name.toUpperCase()} | ${_tierLabel(tier)} | '
          '3-bet ${structure == ThreeBetStructure.polar ? 'POLAR (value + bluffs suited con blocker/jugabilidad)' : 'LINEAL (rango condensado, OOP)'} | '
          'EQR ${hand.eqr.toStringAsFixed(2)} ${hand.isSuited ? 'suited' : hand.isPair ? 'par' : 'offsuit'} | '
          'blocker ${_p(hand.blockerWeight)} | ${noFlat ? '3-bet o fold (0% cold call por rake)' : 'flats habilitados'}$setMine | '
          'freq tabla: ${_freqLabel(f)}',
      ajusteExplotativoRead: [
        if (a == PreflopAction.raise)
          '3-bet ${mult}x${ctx.coldCallers > 0 ? ' +${ctx.coldCallers}x open por caller (squeeze)' : ''} = ${size.toStringAsFixed(1)}bb${allIn ? ' (all-in)' : ''}${micro && !station ? ' (sizing agrandado high-rake)' : ''}',
        ...notes,
        if (notes.isEmpty) 'Sin desviación: perfil ${profile.name}.',
      ].join(' '),
    );
  }

  DecisionOutput _vs3Bet(GameState s, PreflopContext ctx, CanonicalHand hand, ReadProfile? read) {
    if (s.effectiveStackBb == null) throw const MissingInputs(['effectiveStackBb']);
    final hero = s.heroPosition, villain = ctx.villain!, tier = s.rakeTier;
    final ip = hero.isInPositionVs(villain);
    final node = PreflopRangesDb.vs3Bet(hero, heroInPosition: ip);
    final i = hand.index;
    final profile = s.villainProfile;
    final notes = <String>[];

    var f4 = node.freq(PreflopAction.raise, i);
    var fc = node.freq(PreflopAction.call, i);
    final eqKey = '${_tk(tier)}_3B_${villain.name}_${hero.name}';
    final eq = HandProps.equity(eqKey, i) ?? HandProps.equity('MR_RFI_utg', i)!;

    final odds = potOddsRequired(ctx.callBb, ctx.potBb);
    final raked = rakedPotOdds(ctx.callBb, ctx.potBb, tier, potType: PotType.threeBet, stake: s.stake);
    final req = requiredEquity(raked, hand.eqr * stackEqrMultiplier(i, s.effectiveStackBb), ip);

    final micro = tier == RakeTier.microHighRake;
    final villainIp = villain.isInPositionVs(hero);
    final std3b = ctx.heroOpenBb * (villainIp ? (micro ? 3.2 : 3.0) : (micro ? 4.25 : 3.75));
    final ratio = ctx.raiseSizeBb / std3b;

    final noBluff = profile == VillainProfile.nit ||
        profile == VillainProfile.callingStation ||
        profile == VillainProfile.trapperPremium ||
        (read != null && !read.allows4BetBluff);
    if (noBluff && f4 > 0 && PreflopRangesDb.isBluff4Bet(i) && f4 < 1.01 &&
        RangeNotation.parse(PreflopRangesDb.vsNitAgroExtra4BetValue)[i] == 0) {
      f4 = 0;
      final mining = Matrix169.highRank(i) == 12 && Matrix169.isSuited(i) && setMiningOk(ctx.callBb, s.effectiveStackBb);
      fc = mining ? 1 : 0;
      notes.add('4-bet bluff anulado vs ${read?.archetype.name ?? profile.name} (no foldea al 4-bet)'
          '${mining ? '; degradado a call (nut-flush mining, call <= 10% stack)' : '; fold'}.');
    }
    if (profile == VillainProfile.nit) {
      if ((f4 > 0 || fc > 0) && _bottomOfDefense(node, eqKey, i, 0.30)) {
        f4 = 0;
        fc = 0;
        notes.add('Nit: mano en el bottom 30% del rango de defensa por equity => fold.');
      }
    } else if (profile == VillainProfile.regAgro || profile == VillainProfile.maniac) {
      if (RangeNotation.parse(PreflopRangesDb.vsNitAgroExtra4BetValue)[i] > 0) {
        f4 = 1;
        fc = 0;
        notes.add('${profile.name}: 3-bet ancho => TT+/AQs+/AKo stack-off por valor.');
      } else if (RangeNotation.parse(PreflopRangesDb.agroExtra4BetBluffs)[i] > 0 && f4 < 1) {
        f4 = 1;
        fc = 0;
        notes.add('${profile.name}: +4-bet bluff con blocker Ax/Kx suited.');
      }
    }

    if (ratio <= 0.8 && f4 == 0 && fc == 0 && eq >= req) {
      fc = 1;
      notes.add('3-bet pequeño (${ctx.raiseSizeBb}bb, ${(ratio * 100).round()}% del estándar): umbral recalculado, call (eq ${_p(eq)} >= ${_p(req)}).');
    } else if (ratio >= 1.2 && fc > 0 && eq < req) {
      fc = 0;
      notes.add('3-bet grande (${(ratio * 100).round()}% del estándar): call no supera umbral (eq ${_p(eq)} < ${_p(req)}).');
    }

    final f = {PreflopAction.raise: f4, PreflopAction.call: fc, PreflopAction.fold: 1 - f4 - fc};
    final (a, roll, norm) = _pick(f, s);

    var size = ctx.raiseSizeBb * (ip ? 2.2 : 2.5);
    final potAfter = 2 * size + (ctx.potBb - ctx.raiseSizeBb - ctx.heroOpenBb);
    final jam = (s.effectiveStackBb! - size) / potAfter < 1;
    if (jam) size = s.effectiveStackBb!;

    final offsuitOop = !ip && !hand.isSuited && !hand.isPair;
    return DecisionOutput(
      action: switch (a) {
        PreflopAction.raise => DecisionAction.betRaise,
        PreflopAction.call => DecisionAction.call,
        PreflopAction.fold => DecisionAction.fold,
      },
      sizing: switch (a) {
        PreflopAction.raise => Sizing(bb: size, potPct: size / ctx.potBb * 100),
        PreflopAction.call => Sizing(bb: ctx.callBb, potPct: ctx.callBb / ctx.potBb * 100),
        PreflopAction.fold => null,
      },
      freqGto: norm,
      freqSource: _src(node, norm),
      roll: norm.length > 1 ? roll : null,
      metrics: [
        KeyMetric(MetricType.potOdds, odds),
        KeyMetric(MetricType.requiredEquity, req, 'pot odds con rake / (EQR x ${ip ? 'IP 1.10' : 'OOP 0.85'})'),
        KeyMetric(MetricType.equity, eq, 'vs 3-bet ${villain.name.toUpperCase()}'),
        KeyMetric(MetricType.eqr, hand.eqr),
        KeyMetric(MetricType.blocker, hand.blockerWeight, 'vs QQ+/AK'),
        KeyMetric(MetricType.spr, (s.effectiveStackBb! - ctx.raiseSizeBb) / (ctx.potBb + ctx.callBb), 'SPR si call'),
      ],
      justificacionGto: '${hand.label} ${hero.name.toUpperCase()} vs 3-bet ${villain.name.toUpperCase()} ${ip ? 'IP' : 'OOP'} | '
          '${_tierLabel(tier)} | EQR ${hand.eqr.toStringAsFixed(2)} | blocker ${_p(hand.blockerWeight)} | '
          '${offsuitOop ? 'OOP: offsuit realiza mal equity => fold/4-bet, no call' : ip ? 'IP: defensa más ancha, incluye offsuit fuertes' : 'OOP: defensa con suited y pares'} | '
          'freq tabla: ${_freqLabel(f)}',
      ajusteExplotativoRead: [
        if (a == PreflopAction.raise)
          '4-bet ${jam ? 'all-in (SPR post-4bet < 1)' : '${ip ? '2.2' : '2.5'}x = ${size.toStringAsFixed(1)}bb'}.',
        ...notes,
        if (notes.isEmpty) 'Sin desviación: perfil ${profile.name}.',
      ].join(' '),
    );
  }

  String _valueOf(Position opener) =>
      PreflopRangesDb.threeBetValue[opener] ?? '';

  bool _bottomOfDefense(RangeNode node, String eqKey, int i, double frac) {
    final hands = <int>[
      for (var k = 0; k < 169; k++)
        if (node.freq(PreflopAction.call, k) > 0 ||
            (node.freq(PreflopAction.raise, k) > 0 && !PreflopRangesDb.isBluff4Bet(k)))
          k,
    ];
    double e(int k) => HandProps.equity(eqKey, k) ?? HandProps.equity('MR_RFI_utg', k)!;
    hands.sort((a, b) => e(a).compareTo(e(b)));
    final total = hands.fold<int>(0, (s, k) => s + Matrix169.combos(k));
    var acc = 0;
    for (final k in hands) {
      if (k == i) return acc < total * frac;
      acc += Matrix169.combos(k);
    }
    return false;
  }

  String _p(double x) => '${(x * 100).toStringAsFixed(1)}%';

  /// P(set o mejor en el flop) = 1 - C(48,3)/C(50,3).
  static const setOnFlop = 1 - 17296 / 19600;

  String _setMiningNote(PreflopContext ctx, double? stack, Stake s0Stake) {
    final call = ctx.callBb;
    final pot = ctx.potBb + call;
    final implied = call / setOnFlop - pot;
    final rate = RakeConfig.byStake[s0Stake]!.effectiveRate(PotType.srp);
    final stackTxt = stack == null
        ? 'stack desconocido'
        : 'stack ${stack.toStringAsFixed(0)}bb (${setMiningOk(call, stack) ? 'implícitas >= 12x OK' : 'implícitas < 12x: insuficiente'})';
    return 'Set-Mining: P(set)=${_p(setOnFlop)} exige ganar >= ${implied.toStringAsFixed(1)}bb implícitos + rake ${_p(rate)} del bote final; '
        'con $stackTxt el cold call es bloqueado por la regla 3-Bet o Fold High-Rake (riesgo de squeeze de ciegas y reverse implied) '
        'y el 3-bet lineal empieza en el par mínimo del rango de valor => fold';
  }
}


/// Acceso a la defensa BB derivada (evita duplicar la lógica de rangos).
class PostflopRangesProxy {
  PostflopRangesProxy._();
  static Float32List bbDefend(Position opener, RakeTier tier) => PostflopRanges.defendVsOpen(Position.bb, opener, tier);
}
