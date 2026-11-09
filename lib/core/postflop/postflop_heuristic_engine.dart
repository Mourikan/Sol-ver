import '../evaluators/board_analyzer.dart';
import '../evaluators/hand_evaluator.dart';
import '../models/decision_output.dart';
import '../models/game_state.dart';
import 'exploit_modifier.dart';
import 'defense_budget.dart';
import 'flop_lookup_table.dart';
import 'geometry.dart';
import 'hand_tier.dart';
import '../discipline/blocker_bluff_converter.dart';
import '../discipline/board_history.dart';
import '../discipline/ev_sanity_guard.dart';
import '../discipline/bluff_catch_auditor.dart';
import '../discipline/timing_tells_matrix.dart';
import '../reads/gg_profiler.dart';
import 'postflop_ranges.dart';
import 'turn_river_solver.dart';

class PostflopHeuristicEngine {
  const PostflopHeuristicEngine();

  DecisionOutput decide(GameState input, {ReadProfile? read}) {
    final missing = input.missingForPostflop();
    if (missing.isNotEmpty) throw MissingInputs(missing);
    final rp = read ?? ReadProfile.fromVillainProfile(input.villainProfile);
    final s = read == null ? input : input.copyWith(villainProfile: read.engineProfile);
    final hero = s.heroPosition, villain = s.villainPosition!;
    final limped = s.potType == PotType.limped;
    final pfa = s.preflopAggressor ?? villain;
    if (!limped && pfa != hero && pfa != villain) throw UnsupportedError('PFA fuera del bote HU');

    final defender = pfa == hero ? villain : hero;
    final pfaIp = pfa.isInPositionVs(defender);
    final node = FlopLookupTable.nodeOf(s.potType, pfaInPosition: pfaIp);
    final heroIp = hero.isInPositionVs(villain);
    final boardIds = [for (final c in s.board) c.id];
    final h = HandTierClassifier.classify(s.hero!.high.id, s.hero!.low.id, boardIds);

    final street = s.actions.where((a) => a.street == s.street).toList();
    double heroIn = 0, villainIn = 0;
    for (final a in street) {
      if (a.type == ActionType.call) {
        if (a.actor == hero) {
          heroIn = villainIn;
        } else {
          villainIn = heroIn;
        }
      } else if (a.isAggressive) {
        if (a.actor == hero) {
          heroIn = a.amountBb;
        } else {
          villainIn = a.amountBb;
        }
      }
    }
    final pot = s.potBb! + heroIn + villainIn;
    final stack = s.effectiveStackBb! - heroIn;
    final toCall = villainIn - heroIn;
    final spr = PotGeometry.spr(s.effectiveStackBb!, s.potBb!);

    final metrics = <KeyMetric>[KeyMetric(MetricType.spr, spr)];
    final b = BoardAnalyzer.analyze(s.board.sublist(0, 3), pfa: pfa, defender: defender, potType: s.potType);
    metrics
      ..add(KeyMetric(MetricType.rangeAdvantage, b.rangeAdvantage.index.toDouble(), b.rangeAdvantage.name))
      ..add(KeyMetric(MetricType.nutAdvantage, b.nutAdvantage.index.toDouble(), b.nutAdvantage.name));

    final hadInitiative = _initiative(s) == hero;
    final potBeforeBet = pot - villainIn + heroIn;
    final d = _route(s, rp, h, node, pfa, defender, pot, stack, heroIp, metrics, street, heroIn, villainIn, toCall, hadInitiative, limped);
    return EvSanityGuard.postflop(s, rp, d, h, toCall: toCall, potBeforeBet: potBeforeBet);
  }

  DecisionOutput _route(GameState s, ReadProfile rp, HandTierResult h, HuNode node, Position pfa, Position defender,
      double pot, double stack, bool heroIp, List<KeyMetric> metrics, List<PlayerAction> street, double heroIn,
      double villainIn, double toCall, bool hadInitiative, bool limped) {
    final villain = s.villainPosition!;
    if (toCall > 0) {
      final firstAgg = street.where((a) => a.isAggressive).firstOrNull;
      final donk = firstAgg != null && firstAgg.actor == villain && hadInitiative;
      final potBefore = pot - villainIn + heroIn;
      if (donk) {
        final tell = DonkTellDecoder.classify(
            donkBb: toCall, potBb: potBefore, read: rp, stake: s.stake, donkRaise: heroIn > 0);
        final adj = _donkAdjust(tell, h, potBefore, toCall, stack, metrics);
        if (adj != null) return adj;
      }
      if (s.villainProfile == VillainProfile.trapperPremium &&
          h.tier != HandTier.nutsMonster && h.tier != HandTier.highEquityComboDraw) {
        return DecisionOutput(
            action: DecisionAction.fold,
            metrics: metrics,
            justificacionGto: '${h.tier.name} no supera AA/KK/AKs del trapper.',
            ajusteExplotativoRead: 'Trapper premium: check/fold todo lo que no gane a AA/KK.');
      }
      return s.street == Street.river
          ? _riverFacing(s, rp, h, potBefore, toCall, stack, metrics)
          : _budgetFacing(s, rp, h, potBefore, toCall, stack, heroIp, metrics);
    }

    if (s.street == Street.flop) {
      return limped
          ? _limpedFlop(s, h, pot, stack, heroIp, metrics, street.any((a) => a.actor == villain && a.type == ActionType.check))
          : _flop(s, h, node, pfa, defender, pot, stack, heroIp, metrics);
    }
    final villainChecked = street.any((a) => a.actor == villain && a.type == ActionType.check);

    final (instaCall, riverBrick) = TimingTellsMatrix.instaCallTurnIntoRiver(s);
    if (instaCall) {
      final t = TimingTellsMatrix.of(
          s.actions.lastWhere((a) => a.street == Street.turn && a.actor == villain && a.type == ActionType.call), s.stake);
      if (riverBrick) {
        if (!villainChecked && !heroIp) {
          return _check(metrics, 'River brick tras insta-call en turn: rango cargado de draws rotos.',
              '${t.note} OOP: check para inducir faroles de proyectos fallidos.');
        }
        final fishGate = rp.archetype == GgArchetype.recPassiveFish || s.villainProfile == VillainProfile.callingStation;
        if (fishGate && h.tier != HandTier.nutsMonster && h.tier != HandTier.strongTopPairOverpair) {
          return _check(metrics, 'River brick tras insta-call: gate de perfil aplicado antes del timing.',
              'Fish/Station: multiplicador de farol River = 0.0 (ignora el insta-call).');
        }
        if (h.tier != HandTier.marginalMadeShowdown) {
          return _bet(85, pot, stack, metrics, 'River brick tras insta-call en turn: alta densidad de draws fallidos => River Barrel Grande 75-100%.',
              '${t.note} IP: presión máxima (insta-fold de proyectos rotos).');
        }
        return _check(metrics, 'River brick: showdown marginal => check behind.', t.note);
      }
      if (h.tier != HandTier.nutsMonster) {
        return _check(metrics, 'River completa proyectos tras insta-call: bluffs 0%, thin value reducido.', t.note);
      }
    }

    final conv = BlockerBluffConverter.evaluate(s, rp, heroCanBet: villainChecked || heroIp);
    if (conv.converts) {
      if (conv.mode == ConversionMode.polarizedOverbetBluff) {
        return _bet(conv.sizePct, pot, stack, metrics,
            'Turn_SDV_Into_Bluff (LLinusLLove): ${conv.reasons.join(' | ')} => Polarized_Overbet_Bluff ${conv.sizePct.round()}%',
            'Gate activo vs ${rp.archetype.name}: fold forzado de Qx/2P capados | ${conv.reasons.firstWhere((r) => r.startsWith('Key blocker'))}.');
      }
      return _check(metrics, 'Turn_SDV_Into_Bluff: ${conv.reasons.join(' | ')}', 'Plan: River_Check_Raise_Bluff ${conv.sizePct.round()}%.');
    }

    const solver = TurnRiverSolver();
    final plan = solver.plan(s, rp, heroHadInitiative: hadInitiative, pot: pot, stack: stack);
    return solver.toDecision(plan, pot, stack, metrics, rp);
  }

  DecisionOutput? _donkAdjust(DonkTell tell, HandTierResult h, double pot, double bet, double stack, List<KeyMetric> m) {
    switch (tell) {
      case DonkTell.blockingBetWeakOrDraw:
        const raiseTiers = {HandTier.nutsMonster, HandTier.strongTopPairOverpair, HandTier.highEquityComboDraw};
        if (!raiseTiers.contains(h.tier)) return null;
        final after = pot + 2 * bet;
        var to = bet + after / 3;
        if (to >= stack * 0.9) to = stack;
        return DecisionOutput(
          action: DecisionAction.betRaise,
          sizing: Sizing(bb: to, potPct: to / (pot + bet) * 100),
          metrics: m,
          justificacionGto: 'Min-donk (${(bet / pot * 100).round()}% bote) de recreativo = Blocking_Bet_Weak_Or_Draw | ${h.tier.name} | '
              'raise = apuesta + 1/3 del bote tras call (${to.toStringAsFixed(2)}bb)',
          ajusteExplotativoRead: h.tier == HandTier.highEquityComboDraw
              ? 'Raise semi-bluff: alta equidad + su rango débil no aguanta presión.'
              : 'Raise por valor/protección: su rango (TP débil, 2do par, draws) paga e iguala.',
        );
      case DonkTell.nuttedUnbalancedValue:
        final overpairNoRedraw = h.tier == HandTier.strongTopPairOverpair && !h.flushDraw && !h.oesd;
        if (!overpairNoRedraw) return null;
        return DecisionOutput(
          action: DecisionAction.fold,
          metrics: m,
          justificacionGto: 'Pot-donk / donk-raise en NL2-NL50 = Nutted_Unbalanced_Value (prior ${(ReadProfile.nuttedDonkPrior * 100).round()}% 2P+/sets).',
          ajusteExplotativoRead: 'Over-fold de overpair/top pair sin redraws: rango del rival no contiene bluffs suficientes.',
        );
      case DonkTell.standard:
        return null;
    }
  }

  Position? _initiative(GameState s) {
    if (s.street == Street.flop) return s.preflopAggressor;
    final prev = Street.values[s.street.index - 1];
    final agg = s.actions.where((a) => a.street == prev && a.isAggressive);
    return agg.isEmpty ? null : agg.last.actor;
  }

  DecisionOutput _bet(double pct, double pot, double stack, List<KeyMetric> m, String gto, String read, {bool allIn = false}) {
    var bb = allIn ? stack : pot * pct / 100;
    if (bb >= stack * 0.9) bb = stack;
    return DecisionOutput(
      action: DecisionAction.betRaise,
      sizing: Sizing(bb: bb, potPct: bb / pot * 100),
      metrics: [...m, KeyMetric(MetricType.alpha, PotGeometry.alpha(pot, bb), 'fold eq. requerida')],
      justificacionGto: gto,
      ajusteExplotativoRead: read,
    );
  }

  DecisionOutput _check(List<KeyMetric> m, String gto, String read) =>
      DecisionOutput(action: DecisionAction.check, metrics: m, justificacionGto: gto, ajusteExplotativoRead: read);

  DecisionOutput _flop(GameState s, HandTierResult h, HuNode node, Position pfa, Position defender, double pot,
      double stack, bool heroIp, List<KeyMetric> m) {
    final flop = s.board.sublist(0, 3);
    final ranges = PostflopRanges.forPot(pfa, defender, s.potType, s.rakeTier);
    final r = FlopLookupTable.evaluate(flop, node, pfaRange: ranges.$1, defenderRange: ranges.$2);
    final tag = '${r.bucket.name} | nodo ${node.name} | ${h.tier.name}';
    final heroIsPfa = s.heroPosition == pfa;

    if (heroIsPfa) {
      final (tiers, size, note) =
          ExploitModifier.adjustBetting(FlopLookupTable.betTiers[r.strategy]!, r.sizePct, s.villainProfile, players: s.activePlayers);
      m.add(KeyMetric(MetricType.rangeActionFreq, r.betFreq, 'bet del rango PFA (política ${r.strategy.name})'));
      final gto = '$tag | ${r.strategy.name} ${r.sizePct.round()}% | bet rango ${(r.betFreq * 100).round()}% / check ${(r.checkFreq * 100).round()}%';
      return tiers.contains(h.tier)
          ? _bet(size, pot, stack, m, gto, note ?? 'Sin desviación: ${s.villainProfile.name}.')
          : _check(m, gto, note ?? 'Sin desviación: ${s.villainProfile.name}.');
    }

    if (!heroIp) {
      final donk = r.donkEnabled && FlopLookupTable.donkTiers.contains(h.tier) && s.villainProfile != VillainProfile.maniac;
      m.add(KeyMetric(MetricType.rangeActionFreq, r.donkFreq, 'donk del rango defensor'));
      final gto = '$tag | defensor OOP | ${r.donkEnabled ? 'donk habilitado (NA defensor: más 2P/sets/escaleras) ${(r.donkFreq * 100).round()}% @${r.donkSizePct.round()}%' : 'donk 0%: board favorece al PFA => check 100%'}';
      final plan = r.donkEnabled && (h.tier == HandTier.nutsMonster || h.tier == HandTier.highEquityComboDraw)
          ? ' Plan: check-raise si no donkeamos.'
          : '';
      return donk
          ? _bet(r.donkSizePct, pot, stack, m, gto, 'Lead ${r.donkSizePct.round()}% con valor/protección.')
          : _check(m, gto, s.villainProfile == VillainProfile.maniac
              ? 'Maniac: check para inducir; X/R con monsters.'
              : 'Check al PFA.$plan');
    }

    const probe = {HandTier.nutsMonster, HandTier.strongTopPairOverpair, HandTier.highEquityComboDraw};
    final gto = '$tag | defensor IP tras check del PFA: stab 50% con value/draws (rango del PFA capado al checkear).';
    return probe.contains(h.tier) ? _bet(50, pot, stack, m, gto, 'Stab IP.') : _check(m, gto, 'Check behind.');
  }

  DecisionOutput _limpedFlop(GameState s, HandTierResult h, double pot, double stack, bool heroIp, List<KeyMetric> m, bool villainChecked) {
    final multi = s.activePlayers >= 3;
    final tiers = multi
        ? {HandTier.nutsMonster, HandTier.strongTopPairOverpair}
        : {HandTier.nutsMonster, HandTier.strongTopPairOverpair, HandTier.highEquityComboDraw,
            if (heroIp && villainChecked) HandTier.backdoorBlockerBluff};
    final gto = 'Limped_Pot (${s.activePlayers} jugadores) | ${h.tier.name} | sin iniciativa: stab 50% con valor${multi ? ' TPGK+ (multiway)' : '/draws'}';
    return tiers.contains(h.tier) ? _bet(50, pot, stack, m, gto, 'Limped pot.') : _check(m, gto, 'Check.');
  }

  DecisionOutput _raiseTo(double potBeforeBet, double toCall, double stack, int streetsLeft, List<KeyMetric> m, String gto, String read) {
    final after = potBeforeBet + 2 * toCall;
    final f = PotGeometry.geometricFraction(after, stack - toCall, streetsLeft);
    var to = toCall + f * after;
    if (stack - to < after + 2 * f * after) to = stack;
    return DecisionOutput(
        action: DecisionAction.betRaise,
        sizing: Sizing(bb: to, potPct: to / (potBeforeBet + toCall) * 100),
        metrics: m,
        justificacionGto: '$gto | raise geométrico ${streetsLeft}c (f=${(f * 100).round()}%)',
        ajusteExplotativoRead: read);
  }

  /// FLOP/TURN: DefenseBudget (top MDF x factor del rango que llega al nodo).
  DecisionOutput _budgetFacing(GameState s, ReadProfile rp, HandTierResult h, double potBeforeBet, double toCall,
      double stack, bool heroIp, List<KeyMetric> m) {
    final res = DefenseBudget.evaluate(s, rp, potBeforeBet: potBeforeBet, call: toCall);
    final odds = PotGeometry.potOdds(toCall, potBeforeBet + toCall);
    final betFrac = toCall / potBeforeBet;
    final streetsLeft = 3 - (s.street.index - 1);
    m
      ..add(KeyMetric(MetricType.mdf, res.mdf))
      ..add(KeyMetric(MetricType.potOdds, odds))
      ..add(KeyMetric(MetricType.rangeActionFreq, res.target, 'presupuesto de defensa (MDF x ${DefenseBudget.factor(rp, s.stake)})'));
    m.add(KeyMetric(MetricType.equity, _drawEquity(s, h), 'equity de mejorar a monster (outs exactos)'));
    final tag = '${s.street.name} | ${h.tier.name} | bet ${(betFrac * 100).round()}% | MDF ${(res.mdf * 100).round()}% | '
        'DefenseBudget top ${(res.target * 100).round()}% (mano en percentil ${(res.percentile * 100).round()}%)';
    final read = 'Perfil ${rp.archetype.name}: factor ${DefenseBudget.factor(rp, s.stake)}.';
    if (!res.continues) {
      return DecisionOutput(action: DecisionAction.fold, metrics: m, justificacionGto: '$tag | fuera del presupuesto', ajusteExplotativoRead: read);
    }
    if (h.tier == HandTier.nutsMonster) return _raiseTo(potBeforeBet, toCall, stack, streetsLeft, m, '$tag | Monster: raise por valor', read);
    if (!heroIp && s.street == Street.flop && h.flushDraw && h.oesd) {
      return _raiseTo(potBeforeBet, toCall, stack, streetsLeft, m, '$tag | combo draw OOP: check-raise semi-bluff', read);
    }
    final float = h.tier == HandTier.backdoorBlockerBluff || h.tier == HandTier.airGiveUp;
    return DecisionOutput(
        action: DecisionAction.call,
        sizing: Sizing(bb: toCall, potPct: betFrac * 100),
        metrics: m,
        justificacionGto: '$tag | ${float ? 'float (overcards/backdoors) para completar MDF' : 'dentro del presupuesto'}',
        ajusteExplotativoRead: read);
  }

  /// RIVER: Bluff_Combo_Audit por combos reales + Nut-Raise Gate (L12).
  DecisionOutput _riverFacing(GameState s, ReadProfile rp, HandTierResult h, double potBeforeBet, double toCall,
      double stack, List<KeyMetric> m) {
    final odds = PotGeometry.potOdds(toCall, potBeforeBet + toCall);
    m
      ..add(KeyMetric(MetricType.mdf, PotGeometry.mdf(potBeforeBet, toCall)))
      ..add(KeyMetric(MetricType.potOdds, odds));
    final betFrac = toCall / potBeforeBet;
    final tag = 'river | ${h.tier.name} | bet ${(betFrac * 100).round()}% | pot odds ${(odds * 100).round()}%';
    const catchers = {HandTier.nutsMonster, HandTier.strongTopPairOverpair, HandTier.marginalMadeShowdown};
    if (!catchers.contains(h.tier)) {
      return DecisionOutput(action: DecisionAction.fold, metrics: m, justificacionGto: '$tag | sin showdown', ajusteExplotativoRead: 'Draw fallido / aire.');
    }
    final cat = HandEvaluator.category(HandEvaluator.evaluate([s.hero!.high.id, s.hero!.low.id, for (final c in s.board) c.id]));
    final danger = EvSanityGuard.board4Flush(s.board) || EvSanityGuard.board4Straight(s.board);
    final hist = BoardHistory(s.board);
    final raiseDanger = danger || hist.flushCompleted || BoardAnalyzer.analyze(s.board.sublist(0, 3), pfa: s.villainPosition!, defender: s.heroPosition).straightWindows > 0 && cat < HandEvaluator.straight;
    final nuts = h.tier == HandTier.nutsMonster && cat >= HandEvaluator.straight && (!danger || cat >= HandEvaluator.flush && h.flushSuitBlocker || cat >= HandEvaluator.fullHouse);
    final a = BluffCatchAuditor.audit(s, rp, pot: potBeforeBet, call: toCall, heroHasNuts: nuts);
    final metrics = [...m, KeyMetric(MetricType.bluffShare, a.availableBluffs, 'faroles efectivos por combos (${a.categories.join(', ')})')];
    final txt = 'Bluff_Combo_Audit: ${a.reasons.join(' | ')}';

    if (h.tier == HandTier.nutsMonster) {
      final pct = DefenseBudget.percentile(s, rp);
      if (pct <= 0.15 && (!raiseDanger || nuts)) {
        return _raiseTo(potBeforeBet, toCall, stack, 1, metrics, '$tag | Nut-Raise Gate OK (top ${(pct * 100).round()}% del rango)', 'Raise por valor.');
      }
    }
    final agroSafe = rp.archetype == GgArchetype.agroSpewy &&
        (cat >= HandEvaluator.twoPair || h.tier == HandTier.strongTopPairOverpair);
    final budget = DefenseBudget.evaluate(s, rp, potBeforeBet: potBeforeBet, call: toCall);
    metrics.add(KeyMetric(MetricType.rangeActionFreq, budget.target, 'presupuesto de defensa River (MDF x factor)'));
    if ((a.allowsCall && budget.continues) || agroSafe || nuts) {
      return DecisionOutput(
          action: DecisionAction.call,
          sizing: Sizing(bb: toCall, potPct: betFrac * 100),
          metrics: metrics,
          justificacionGto: '$tag | $txt${h.tier == HandTier.nutsMonster ? ' | Nut-Raise Gate: degradado a call' : ''}',
          ajusteExplotativoRead: a.verdict == AuditVerdict.heroCallApproved ? 'HERO CALL quirúrgico aprobado.' : 'Call dentro de umbral.');
    }
    return DecisionOutput(
        action: DecisionAction.fold,
        metrics: metrics,
        justificacionGto: '$tag | $txt',
        ajusteExplotativoRead: a.verdict == AuditVerdict.heroFoldDisciplined
            ? '100% FOLD DISCIPLINADO: colapso de faroles; la fuerza absoluta de la mano no justifica el call.'
            : 'Fold: bluff-catcher -EV en este nodo/combos.');
  }

  /// Probabilidad exacta (por enumeración de cartas restantes) de mejorar a nutsMonster.
  double _drawEquity(GameState s, HandTierResult h) {
    final ids = [for (final c in s.board) c.id];
    final dead = s.deadMask;
    var outs = 0, unseen = 0;
    for (var c = 0; c < 52; c++) {
      if (dead & (1 << c) != 0) continue;
      unseen++;
      final t = HandTierClassifier.classify(s.hero!.high.id, s.hero!.low.id, [...ids, c]).tier;
      if (t == HandTier.nutsMonster) outs++;
    }
    if (s.street == Street.flop) {
      return 1 - ((unseen - outs) * (unseen - outs - 1)) / (unseen * (unseen - 1));
    }
    return outs / unseen;
  }
}
