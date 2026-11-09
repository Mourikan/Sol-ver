import 'dart:typed_data';

import '../models/decision_output.dart';
import '../models/game_state.dart';
import '../reads/gg_profiler.dart';
import 'hand_normalizer.dart';
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
    final pot = committed.values.fold<double>(0, (x, y) => x + y);
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
    return switch (ctx.scenario) {
      PreflopScenario.rfi => _rfi(s, ctx, hand),
      PreflopScenario.vsRfi => _vsRfi(s, ctx, hand),
      PreflopScenario.vs3Bet => _vs3Bet(s, ctx, hand, read),
    };
  }

  String _tk(RakeTier t) => t == RakeTier.microHighRake ? 'HR' : 'MR';
  String _tierLabel(RakeTier t) => t == RakeTier.microHighRake ? 'High-Rake (NL2-NL25)' : 'Mid-Rake (NL50-NL200)';

  double potOddsRequired(double call, double pot) => call / (pot + call);

  /// Pot odds con rake sobre el bote final esperado: (call / (pot + call)) / (1 - rake_efectivo[PotType]).
  double rakedPotOdds(double call, double pot, RakeTier tier, {PotType potType = PotType.srp}) =>
      call / (pot + call) / (1 - rake[tier]!.effectiveRate(potType));

  double requiredEquity(double rakedOdds, double eqr, bool ip) =>
      rakedOdds / (eqr * (ip ? ipMultiplier : oopMultiplier));

  double _u(int index, String node) {
    var h = seed ^ 0x811C9DC5;
    for (final c in '$node#$index'.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
    }
    return h / 0x100000000;
  }

  PreflopAction _pick(Map<PreflopAction, double> f, int idx, String node) {
    final u = _u(idx, node);
    var acc = 0.0;
    for (final a in [PreflopAction.raise, PreflopAction.call]) {
      acc += f[a] ?? 0;
      if (u < acc) return a;
    }
    return PreflopAction.fold;
  }

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
      range = PreflopRangesDb.rfi(hero, tier).weights[PreflopAction.raise]!;
      rangeLabel = 'RFI ${hero.name.toUpperCase()} ${PreflopRangesDb.rfi(hero, tier).percent(PreflopAction.raise).toStringAsFixed(1)}%';
    }

    final stealVsNit = s.villainProfile == VillainProfile.nit &&
        ctx.limpers == 0 &&
        (hero == Position.btn || hero == Position.sb);
    var w = range[hand.index].toDouble();
    if (stealVsNit) w = 1.0;

    final base = ctx.limpers > 0
        ? (ip ? 3.5 : 4.5) + ctx.limpers
        : PreflopRangesDb.openSizeBb[hero]!;
    final f = {PreflopAction.raise: w, PreflopAction.fold: 1 - w};
    final a = _pick(f, hand.index, 'RFI_${hero.name}');
    final raise = a == PreflopAction.raise;
    final checkOption = hero == Position.bb && !raise;

    return DecisionOutput(
      action: raise ? DecisionAction.betRaise : (checkOption ? DecisionAction.check : DecisionAction.fold),
      sizing: raise ? Sizing(bb: base, potPct: base / ctx.potBb * 100) : null,
      freqGto: null,
      metrics: [
        KeyMetric(MetricType.eqr, hand.eqr),
        KeyMetric(MetricType.equity, hand.rawEquityVsTopRange, 'vs top range'),
      ],
      justificacionGto: '${hand.label} | ${hero.name.toUpperCase()} | ${_tierLabel(tier)} | $rangeLabel | '
          'EQR ${hand.eqr.toStringAsFixed(2)} (${hand.isSuited ? 'suited' : hand.isPair ? 'par' : 'offsuit'}) | '
          'freq tabla: ${_freqLabel(f)}${hero == Position.sb ? ' | SB: raise-or-fold, 0% complete' : ''}',
      ajusteExplotativoRead: stealVsNit
          ? 'Ciegas Nit: fold-to-steal excesivo => steal 100% cualquier dos cartas.'
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
    final raked = rakedPotOdds(ctx.callBb, ctx.potBb, tier);
    final req = requiredEquity(raked, hand.eqr, ip);
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

    if (hero == Position.bb && f3 < 1) {
      fc = passes ? 1 - f3 : 0;
      notes.add('BB: call derivado de pot odds (eq ${_p(eq)} vs req ${_p(req)}).');
    } else if (fc > 0 && offSize && !passes) {
      fc = 0;
      notes.add('Open ${ctx.raiseSizeBb}bb (no estándar): flat no supera umbral (eq ${_p(eq)} < ${_p(req)}).');
    }

    final f = {PreflopAction.raise: f3, PreflopAction.call: fc, PreflopAction.fold: 1 - f3 - fc};
    final a = _pick(f, i, node.id);

    final micro = tier == RakeTier.microHighRake;
    final station = profile == VillainProfile.callingStation;
    final mult = station
        ? (ip ? 4.0 : 5.0)
        : ip
            ? (micro ? 3.2 : 3.0)
            : (hero == Position.bb ? (micro ? 4.5 : 3.75) : (micro ? 4.0 : 3.75));
    var size = ctx.raiseSizeBb * mult + ctx.raiseSizeBb * ctx.coldCallers;
    final allIn = s.effectiveStackBb != null && size >= s.effectiveStackBb!;
    if (allIn) size = s.effectiveStackBb!;

    final noFlat = !PreflopRangesDb.flatsAllowed(hero, opener, tier);
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
      freqGto: node.source == RangeSource.solverImport ? f[a] : null,
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
          'blocker ${_p(hand.blockerWeight)} | ${noFlat ? '3-bet o fold (0% cold call por rake)' : 'flats habilitados'} | '
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
    final raked = rakedPotOdds(ctx.callBb, ctx.potBb, tier, potType: PotType.threeBet);
    final req = requiredEquity(raked, hand.eqr, ip);

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
      final mining = Matrix169.highRank(i) == 12 && Matrix169.isSuited(i) && ctx.callBb <= 0.10 * s.effectiveStackBb!;
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
    final a = _pick(f, i, node.id);

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
      freqGto: node.source == RangeSource.solverImport ? f[a] : null,
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
}
