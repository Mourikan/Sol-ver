import '../evaluators/board_analyzer.dart';
import '../evaluators/action_ev_calculator.dart';
import '../evaluators/hand_evaluator.dart';
import '../models/decision_output.dart';
import '../models/game_state.dart';
import 'exploit_modifier.dart';
import 'defense_budget.dart';
import 'flop_lookup_table.dart';
import 'four_bet_pot_solver.dart';
import 'geometry.dart';
import 'hand_tier.dart';
import '../discipline/blocker_bluff_converter.dart';
import '../models/action_mixer.dart';
import '../discipline/board_history.dart';
import '../discipline/ev_sanity_guard.dart';
import '../discipline/bluff_catch_auditor.dart';
import '../discipline/timing_tells_matrix.dart';
import '../reads/gg_profiler.dart';
import '../reads/multiway_threat_aggregator.dart';
import 'postflop_ranges.dart';
import 'range_equity.dart';
import 'terminal_exploit_closers.dart';
import '../reads/unmapped_spots_resolver.dart';
import '../evaluators/decision_justifier.dart';
import '../reads/villain_range_inspector.dart';
import 'turn_river_solver.dart';

class PostflopHeuristicEngine {
  const PostflopHeuristicEngine();

  DecisionOutput decide(GameState input, {ReadProfile? read}) {
    final d = _decideCore(input, read: read);
    final rp = read ?? ReadProfile.fromVillainProfile(input.villainProfile);
    final s = read == null ? input : input.copyWith(villainProfile: read.engineProfile);
    return annotate(s, rp, d);
  }

  /// Inspector de rango percibido + justificador determinista (sin Monte Carlo).
  DecisionOutput annotate(GameState s, ReadProfile rp, DecisionOutput d) {
    final (potBefore, toCall) = _potAndCall(s);
    final f = d.action == DecisionAction.betRaise && d.sizing != null && potBefore > 0
        ? (toCall > 0 ? (d.sizing!.bb - toCall) / (potBefore + 2 * toCall) : d.sizing!.bb / potBefore)
        : 0.66;
    final r = VillainRangeInspector.inspect(s, rp, betFraction: f, potBefore: potBefore, toCall: toCall);
    // Con terminación activa, los EV mostrados usan el mismo contexto de línea que certificó exploitDeltaEV.
    final closer = s.activeVillains.length >= 2 || rp.archetype == GgArchetype.unknownReg
        ? null
        : TerminalExploitClosers.context(s, rp, potBefore: potBefore, toCall: toCall);
    if (closer != null && d.actionEVs != null) {
      final size = d.action == DecisionAction.betRaise && d.sizing != null ? d.sizing!.bb : (toCall > 0 ? toCall * 3 : potBefore * 0.5);
      d = d.copyWith(
          actionEVs: ActionEvCalculator.postflop(s, rp,
                  potBefore: potBefore,
                  toCall: toCall,
                  betSizeBb: size,
                  exactSize: true,
                  foldEquityOverride: closer.foldEquityOverride,
                  villainBluffShare: closer.villainBluffShare)
              .toMap());
    }
    return d.copyWith(
        perceivedVillainRange: r, justification: DecisionJustifier.build(s, rp, d, r, potBefore: potBefore, toCall: toCall));
  }

  DecisionOutput _decideCore(GameState input, {ReadProfile? read}) {
    if (input.activeVillains.length >= 2) return _multiway(input, read);
    final missing = input.missingForPostflop();
    if (missing.isNotEmpty) throw MissingInputs(missing);
    final rp = read ?? ReadProfile.fromVillainProfile(input.villainProfile);
    final s = read == null ? input : input.copyWith(villainProfile: read.engineProfile);
    final d = _decideHu(s, rp);
    if (rp.archetype == GgArchetype.unknownReg) return d;
    // CAPA 1 — Ancla Nash: decisión vs Reg_GTO en segundo plano; ambas líneas evaluadas bajo el perfil asumido.
    final base = _decideHu(s.copyWith(villainProfile: VillainProfile.gtoBase), _anchor);
    final (potBefore, toCall) = _potAndCall(s);
    // Terminaciones T1-T6: el mismo contexto de línea (prior del perfil) evalúa la línea explotativa y el ancla.
    final closer = TerminalExploitClosers.context(s, rp, potBefore: potBefore, toCall: toCall);
    final spotShare = closer != null
        ? null
        : UnmappedSpotsResolver.plan(s, rp, HandTierClassifier.classify(s.hero!.high.id, s.hero!.low.id, [for (final c in s.board) c.id]),
                potBefore: potBefore, toCall: toCall)
            ?.bluffShare;
    final delta = evOfDecision(s, rp, d, potBefore: potBefore, toCall: toCall, closer: closer, bluffShare: spotShare) -
        evOfDecision(s, rp, base, potBefore: potBefore, toCall: toCall, closer: closer, bluffShare: spotShare);
    // Regla explotativa con Δ < 0 en apuesta propia => no se aplica (vuelve al ancla Nash). Los calls quedan bajo MDF.
    // Check explotativo (sin apuesta enfrente) con Δ < 0 frente a la apuesta del ancla => tampoco se aplica, salvo candados
    // del EV_Sanity_Guard y del Profile_Gate (Fish/Station inelástico y Trapper: farol 0% por candado de perfil).
    final lock = d.justificacionGto.contains(EvSanityGuard.tag) ||
        d.ajusteExplotativoRead.contains(EvSanityGuard.tag) ||
        rp.archetype == GgArchetype.recPassiveFish ||
        rp.archetype == GgArchetype.trapperLimpReraiser;
    final passiveLoses = toCall == 0 && d.action == DecisionAction.check && base.action == DecisionAction.betRaise && !lock;
    if (delta < 0 && (d.action == DecisionAction.betRaise || passiveLoses)) {
      return base.copyWith(
          exploitDeltaEV: 0,
          ajusteExplotativoRead: '[EV_ANCHOR] desviación ${d.action.name} vs ${rp.archetype.name} con Δ EV '
              '${delta.toStringAsFixed(2)}bb <= 0: no aplicada (línea Reg_GTO). ${d.ajusteExplotativoRead}');
    }
    return d.copyWith(exploitDeltaEV: delta);
  }

  static const _anchor = ReadProfile(GgArchetype.unknownReg, ['ancla Nash (Reg_GTO)']);

  (double, double) _potAndCall(GameState s) {
    double heroIn = 0, villainIn = 0;
    for (final a in s.actions.where((a) => a.street == s.street)) {
      final mine = a.actor == s.heroPosition;
      if (a.type == ActionType.call) {
        if (mine) {
          heroIn = villainIn;
        } else {
          villainIn = heroIn;
        }
      } else if (a.isAggressive) {
        if (mine) {
          heroIn = a.amountBb;
        } else {
          villainIn = a.amountBb;
        }
      }
    }
    return (s.potBb! + 2 * heroIn, villainIn - heroIn);
  }

  /// EV (bb) de la acción de una decisión con `ActionEvCalculator` bajo el read dado (mismo modelo para exploit y GTO).
  static double evOfDecision(GameState s, ReadProfile rp, DecisionOutput d,
      {required double potBefore, required double toCall, CloserContext? closer, double? bluffShare}) {
    final size = d.action == DecisionAction.betRaise && d.sizing != null ? d.sizing!.bb : (toCall > 0 ? toCall * 3 : potBefore * 0.5);
    final ev = ActionEvCalculator.postflop(s, rp,
        potBefore: potBefore,
        toCall: toCall,
        betSizeBb: size,
        exactSize: true,
        foldEquityOverride: closer?.foldEquityOverride,
        villainBluffShare: closer?.villainBluffShare ?? bluffShare);
    return switch (d.action) {
      DecisionAction.fold => toCall > 0 ? ev.fold : ev.checkCall,
      DecisionAction.check || DecisionAction.call => ev.checkCall,
      DecisionAction.betRaise => ev.betRaise,
    };
  }

  DecisionOutput _decideHu(GameState s, ReadProfile rp) {
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
    final guarded = EvSanityGuard.postflop(s, rp, d, h, toCall: toCall, potBeforeBet: potBeforeBet);
    final inv = _invariants(s, rp, guarded, h, pot: pot, stack: stack, toCall: toCall, potBeforeBet: potBeforeBet);
    return evGate(s, rp, inv, pot: pot, stack: stack, toCall: toCall, potBeforeBet: potBeforeBet);
  }

  /// Multiway con villanos modelados por separado: decide contra la amenaza principal y consolida
  /// Bluff_Gate_Multiway (min factor x 0.5^(N-1)) y Value_Threshold_Multiway (equity > 50% vs la amenaza más fuerte).
  DecisionOutput _multiway(GameState input, ReadProfile? read) {
    final a = MultiwayThreatAggregator.assess(input);
    final main = a.mainThreat;
    final s = input.copyWith(
      villainPosition: main.position,
      villainProfile: main.profile,
      activePlayers: a.villains.length + 1,
      activeVillains: const [],
    );
    final d = decide(s, read: read ?? ReadProfile.fromVillainProfile(main.profile));
    if (d.action != DecisionAction.betRaise) return d;
    final h = HandTierClassifier.classify(s.hero!.high.id, s.hero!.low.id, [for (final c in s.board) c.id]);
    const bluffTiers = {HandTier.airGiveUp, HandTier.backdoorBlockerBluff, HandTier.highEquityComboDraw};
    final tag = 'Multiway ${a.villains.length} villanos [${a.notes.join('; ')}] | amenaza principal ${main.position.name}';
    if (bluffTiers.contains(h.tier)) {
      final keep = !a.bluffBlocked &&
          DeterministicActionMixer.roll([s.hero!.high, s.hero!.low], s.board, s.potBb ?? 1) < a.bluffFactor * 100;
      if (!keep) {
        return d.copyWith(
          action: DecisionAction.check,
          clearSizing: true,
          freqGto: {DecisionAction.betRaise: a.bluffFactor, DecisionAction.check: 1 - a.bluffFactor},
          freqSource: FreqSource.modelCalibrated,
          ajusteExplotativoRead: '$tag | Bluff_Gate_Multiway: factor ${a.bluffFactor.toStringAsFixed(2)}${a.bluffBlocked ? ' (Fish/Station activo => 0%)' : ''}. ${d.ajusteExplotativoRead}',
        );
      }
    } else if (h.tier != HandTier.nutsMonster) {
      final eq = RangeEquity.vsVillainLine(s);
      if (eq < 0.5) {
        return d.copyWith(
          action: DecisionAction.check,
          clearSizing: true,
          ajusteExplotativoRead: '$tag | Value_Threshold_Multiway: equity ${(eq * 100).toStringAsFixed(1)}% < 50% vs amenaza principal. ${d.ajusteExplotativoRead}',
        );
      }
    }
    return d.copyWith(ajusteExplotativoRead: '$tag. ${d.ajusteExplotativoRead}');
  }

  /// Marcadores de intervenciones documentadas que la puerta de EV respeta (reglas explotativas / cordura).
  static const protectedMarkers = [
    EvSanityGuard.tag,
    'Turn_SDV_Into_Bluff',
    'FOLD DISCIPLINADO',
    'Terminal_Closer',
    'Unmapped_Spot',
    'Nutted_Unbalanced_Value',
    'Trapper',
    'trap',
    'Maniac',
    'inducir',
    'Fish/Station',
    'Station',
    'Exploit_Bluff_Factor 0.0',
    // Faroles del selector balanceado (cupo = alpha x factor): individualmente -EV en el modelo de 1 calle por diseño.
    'Farol seleccionado',
    'Rank_Shift',
  ];

  /// Banda de indiferencia: diferencias de EV menores se tratan como mezcla de equilibrio (no se corrigen).
  static const maniacTrapShare = 0.40;

  /// Timing (Fase 9.1, priors del usuario): Auto_Profit_Stab 66-80% (punto medio) y Overbet_Bluff River 125%.
  static const instaStabPct = 73.0, instaOverbetPct = 125.0;

  static double evTolerance(double pot) => pot * 0.05 < 0.25 ? 0.25 : pot * 0.05;

  /// Puerta de EV: si la acción heurística pierde más que la banda frente al argmax(EV), se corrige y se documenta.
  DecisionOutput evGate(GameState s, ReadProfile rp, DecisionOutput d,
      {required double pot, required double stack, required double toCall, required double potBeforeBet}) {
    final candidate = d.action == DecisionAction.betRaise && d.sizing != null
        ? d.sizing!.bb
        : (toCall > 0 ? (toCall * 3 < stack ? toCall * 3 : stack) : (pot * 0.5 < stack ? pot * 0.5 : stack));
    final ev = ActionEvCalculator.postflop(s, rp, potBefore: potBeforeBet, toCall: toCall, betSizeBb: candidate);
    final evs = ev.toMap();
    double evOf(DecisionAction a) => switch (a) {
          DecisionAction.fold => toCall > 0 ? ev.fold : ev.checkCall,
          DecisionAction.check || DecisionAction.call => ev.checkCall,
          DecisionAction.betRaise => ev.betRaise,
        };
    final chosen = evOf(d.action);
    final text = '${d.justificacionGto} ${d.ajusteExplotativoRead}';
    final protected = protectedMarkers.any(text.contains);
    final withEv = d.copyWith(actionEVs: evs);
    // Solo des-escala: la acción agresiva/inversora (bet, raise, call) que pierde frente a la pasiva (check/fold)
    // más que la banda se corrige. Nunca escala (el modelo de 1 calle no ve protección de rango ni calles futuras).
    final passive = toCall > 0 ? (DecisionAction.call, ev.checkCall) : (DecisionAction.check, ev.checkCall);
    // Los calls quedan bajo la restricción MDF (DefenseBudget/auditor por combos): el modelo de 1 calle infravalora faroles.
    final invests = d.action == DecisionAction.betRaise;
    if (!invests || protected || passive.$1 == d.action || passive.$2 - chosen <= evTolerance(potBeforeBet + toCall)) return withEv;
    final best = passive.$2;
    final target = passive.$1;
    final sizing = switch (target) {
      DecisionAction.betRaise => Sizing(bb: candidate, potPct: candidate / (potBeforeBet + toCall) * 100),
      DecisionAction.call => Sizing(bb: toCall, potPct: toCall / potBeforeBet * 100),
      _ => null,
    };
    return withEv.copyWith(
      action: target,
      sizing: sizing,
      clearSizing: sizing == null,
      heuristicAction: d.action,
      freqGto: {target: 1.0},
      freqSource: FreqSource.pure,
      ajusteExplotativoRead: '[EV_GATE] ${d.action.name} -> ${target.name}: EV ${chosen.toStringAsFixed(2)}bb vs argmax '
          '${best.toStringAsFixed(2)}bb (banda ${evTolerance(potBeforeBet + toCall).toStringAsFixed(2)}bb). ${d.ajusteExplotativoRead}',
    );
  }

  /// Invariantes inquebrantables (monotonía de EV).
  DecisionOutput _invariants(GameState s, ReadProfile rp, DecisionOutput d, HandTierResult h,
      {required double pot, required double stack, required double toCall, required double potBeforeBet}) {
    const tag = EvSanityGuard.tag;
    DecisionOutput fix(DecisionAction a, String why, Sizing? sz) => DecisionOutput(
        action: a,
        sizing: sz,
        metrics: d.metrics,
        justificacionGto: d.justificacionGto,
        ajusteExplotativoRead: '$tag $why | original: ${d.action.name}. ${d.ajusteExplotativoRead}');
    if (toCall > 0 && d.action == DecisionAction.fold && s.street != Street.river) {
      final odds = PotGeometry.potOdds(toCall, potBeforeBet + toCall);
      final nutted = d.justificacionGto.contains('Nutted_Unbalanced_Value');
      final eq = RangeEquity.realized(s, valuePrior: nutted ? ReadProfile.nuttedDonkPrior : null);
      if (eq >= odds) {
        return fix(DecisionAction.call, 'Equity real (realizada) ${(eq * 100).toStringAsFixed(1)}% >= pot odds ${(odds * 100).toStringAsFixed(1)}%: prohibido foldear.',
            Sizing(bb: toCall, potPct: toCall / potBeforeBet * 100));
      }
    }
    if (s.street == Street.river && toCall == 0 && d.action == DecisionAction.check && RangeEquity.isAbsoluteNuts(s)) {
      final bb = stack < pot * 0.75 ? stack : pot * 0.75;
      return fix(DecisionAction.betRaise, 'Nuts absolutas en River: prohibido check behind.', Sizing(bb: bb, potPct: bb / pot * 100));
    }
    if (s.street == Street.river && toCall > 0 && d.action == DecisionAction.betRaise) {
      final ok = RangeEquity.isAbsoluteNuts(s) || (h.tier == HandTier.nutsMonster && DefenseBudget.percentile(s, rp) <= 0.15);
      if (!ok) {
        return fix(DecisionAction.call, 'Raise River por debajo del umbral de valor (top 15%) sin blocker-bluff validado: degradado a call.',
            Sizing(bb: toCall, potPct: toCall / potBeforeBet * 100));
      }
    }
    return d;
  }

  DecisionOutput _route(GameState s, ReadProfile rp, HandTierResult h, HuNode node, Position pfa, Position defender,
      double pot, double stack, bool heroIp, List<KeyMetric> metrics, List<PlayerAction> street, double heroIn,
      double villainIn, double toCall, bool hadInitiative, bool limped) {
    final villain = s.villainPosition!;
    if (s.potType == PotType.fourBetPlus) {
      return FourBetPotSolver.decide(s, h,
          pot: pot, stack: stack, toCall: toCall, potBeforeBet: pot - villainIn + heroIn, heroIsPfa: s.preflopAggressor == s.heroPosition);
    }
    if (s.street != Street.flop) {
      final potBefore = pot - villainIn + heroIn;
      final cp = TerminalExploitClosers.plan(s, rp, h,
          potBefore: potBefore, toCall: toCall, roll: DeterministicActionMixer.roll([s.hero!.high, s.hero!.low], s.board, pot));
      if (cp != null) return _closer(cp, pot, stack, toCall, potBefore, metrics);
    }
    final sp = UnmappedSpotsResolver.plan(s, rp, h, potBefore: pot - villainIn + heroIn, toCall: toCall);
    if (sp != null) return _spot(sp, pot, stack, toCall, pot - villainIn + heroIn, metrics);
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

    // Insta_Check (Profile_Gate primero): rango Capped_Weak. Fish => solo thin value; Trapper/Reg_GTO => sin desviación.
    final instaCheck = villainChecked &&
        street.any((a) => a.actor == villain && a.type == ActionType.check && a.timing == TimingTell.instaAction);
    final timingGate = rp.archetype != GgArchetype.recPassiveFish &&
        rp.archetype != GgArchetype.trapperLimpReraiser &&
        rp.archetype != GgArchetype.unknownReg;
    const noSdv = {HandTier.airGiveUp, HandTier.backdoorBlockerBluff};
    if (instaCheck && timingGate && noSdv.contains(h.tier)) {
      if (s.street == Street.turn) {
        return _bet(instaStabPct, pot, stack, metrics, 'Insta-check Turn: rango Capped_Weak (sin sets/nut-draws que protegerían).',
            'Auto_Profit_Stab ${instaStabPct.round()}% vs ${rp.archetype.name} (Profile_Gate OK; FE del rango capado > alpha).');
      }
      final (blocksCall, _, blk) = TurnRiverSolver.keyBlockers(s, h);
      if (s.street == Street.river && blocksCall) {
        return _bet(instaOverbetPct, pot, stack, metrics, 'Insta-check River: rango Capped_Weak => Overbet_Bluff polar ${instaOverbetPct.round()}%.',
            'Overbet_Bluff con blocker ($blk) vs ${rp.archetype.name}; Profile_Gate OK.');
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

  DecisionOutput _closer(CloserPlan cp, double pot, double stack, double toCall, double potBefore, List<KeyMetric> m) {
    final read = '${cp.marker} (Stake_Gate + perfil; certificado por exploitDeltaEV).';
    switch (cp.action) {
      case DecisionAction.fold:
        return DecisionOutput(
            action: DecisionAction.fold,
            metrics: m,
            freqGto: const {DecisionAction.fold: 1.0},
            freqSource: FreqSource.pure,
            justificacionGto: cp.why,
            ajusteExplotativoRead: '100% FOLD DISCIPLINADO: $read');
      case DecisionAction.check || DecisionAction.call:
        return _check(m, cp.why, read);
      case DecisionAction.betRaise:
        if (toCall > 0) {
          var to = toCall * TerminalExploitClosers.t1RaiseMult;
          if (to >= stack * 0.9) to = stack;
          return DecisionOutput(
            action: DecisionAction.betRaise,
            sizing: Sizing(bb: to, potPct: to / potBefore * 100),
            metrics: m,
            justificacionGto: cp.why,
            ajusteExplotativoRead: read,
          );
        }
        return _bet(cp.sizePct!, pot, stack, m, cp.why, read);
    }
  }

  DecisionOutput _spot(SpotPlan sp, double pot, double stack, double toCall, double potBefore, List<KeyMetric> m) {
    final read = 'Unmapped_Spot ${sp.name} (Equilibrium_Deviation_Read; certificado por exploitDeltaEV).';
    switch (sp.action) {
      case DecisionAction.fold:
        return DecisionOutput(
            action: DecisionAction.fold,
            metrics: m,
            freqGto: const {DecisionAction.fold: 1.0},
            freqSource: FreqSource.pure,
            justificacionGto: sp.why,
            ajusteExplotativoRead: 'FOLD DISCIPLINADO: $read');
      case DecisionAction.call:
        return DecisionOutput(
            action: DecisionAction.call,
            sizing: Sizing(bb: toCall, potPct: toCall / potBefore * 100),
            metrics: m,
            freqGto: const {DecisionAction.call: 1.0},
            freqSource: FreqSource.pure,
            justificacionGto: sp.why,
            ajusteExplotativoRead: read);
      case DecisionAction.check:
        return _check(m, sp.why, read);
      case DecisionAction.betRaise:
        if (toCall > 0) {
          var to = toCall * (sp.raiseMult ?? 3.0);
          if (to >= stack * 0.9) to = stack;
          return DecisionOutput(
              action: DecisionAction.betRaise,
              sizing: Sizing(bb: to, potPct: to / potBefore * 100),
              metrics: m,
              justificacionGto: sp.why,
              ajusteExplotativoRead: read);
        }
        return _bet(sp.sizePct!, pot, stack, m, sp.why, read);
    }
  }

  DecisionOutput _check(List<KeyMetric> m, String gto, String read) =>
      DecisionOutput(action: DecisionAction.check, metrics: m, justificacionGto: gto, ajusteExplotativoRead: read);

  DecisionOutput _flop(GameState s, HandTierResult h, HuNode node, Position pfa, Position defender, double pot,
      double stack, bool heroIp, List<KeyMetric> m) {
    final flop = s.board.sublist(0, 3);
    final ranges = PostflopRanges.forPot(pfa, defender, s.potType, s.rakeTier);
    final r = FlopLookupTable.evaluate(flop, node, pfaRange: ranges.$1, defenderRange: ranges.$2, pfa: pfa, defender: defender);
    final tag = '${r.bucket.name} | nodo ${node.name} | ${h.tier.name}';
    final heroIsPfa = s.heroPosition == pfa;

    if (heroIsPfa) {
      var row = FlopLookupTable.row(r.strategy, h.tier, trap: r.trapActive);
      final baseSet = {for (final t in HandTier.values) if (FlopLookupTable.betProbability(r.strategy, t) > 0) t};
      final (tiers, size, note) = ExploitModifier.adjustBetting(baseSet, r.sizePct, s.villainProfile,
          players: s.activePlayers, dryBoard: r.strategy == StrategyClass.rangeBetSmall);
      if (!tiers.contains(h.tier)) {
        row = (1.0, 0.0, 0.0);
      } else if (row.$2 + row.$3 == 0 || note != null) {
        row = size >= 60 ? (0.0, 0.0, 1.0) : (0.0, 1.0, 0.0);
      }
      // TAG_AGRO_MANIAC: Trap_Check_Nuts 40% (prior del usuario): el maniac farolea en el nodo de check.
      final maniacTrap = s.villainProfile == VillainProfile.maniac && h.tier == HandTier.nutsMonster;
      if (maniacTrap) {
        final keep = 1 - maniacTrapShare, bet = row.$2 + row.$3;
        row = bet == 0 ? (1.0, 0.0, 0.0) : (1 - keep * bet, row.$2 * keep, row.$3 * keep);
      }
      m.add(KeyMetric(MetricType.rangeActionFreq, r.betFreq, 'bet del rango PFA (matriz ${r.strategy.name})'));
      final roll = DeterministicActionMixer.roll([s.hero!.high, s.hero!.low], flop, pot);
      final big = roll < row.$3 * 100, small = !big && roll < (row.$3 + row.$2) * 100;
      final freqs = {DecisionAction.check: row.$1, DecisionAction.betRaise: row.$2 + row.$3};
      final gto = '$tag | ${r.strategy.name} | fila tier [X ${(row.$1 * 100).round()} / B33 ${(row.$2 * 100).round()} / B75 ${(row.$3 * 100).round()}]'
          '${r.trapActive && h.tier == HandTier.nutsMonster ? ' (trap ${(FlopLookupTable.trapShare * 100).round()}%)' : ''} | '
          'bet rango ${(r.betFreq * 100).round()}% / check ${(r.checkFreq * 100).round()}% (monsters en check ${(r.monsterShareOfCheck * 100).toStringAsFixed(1)}%)';
      final read = '${note ?? 'Sin desviación: ${s.villainProfile.name}.'}'
          '${maniacTrap ? ' Trap_Check_Nuts ${(maniacTrapShare * 100).round()}% vs Maniac.' : ''}';
      final src = freqs.values.any((v) => v > 0 && v < 1) ? FreqSource.modelCalibrated : FreqSource.pure;
      final d = big || small
          ? _bet(big ? (note != null ? size : 75) : (note != null ? size : FlopLookupTable.sizeOf[StrategyClass.rangeBetSmall]!), pot, stack, m, gto, read)
          : _check(m, gto, read);
      return d.copyWith(freqGto: freqs, freqSource: src);
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
    final xr = !heroIp && s.street == Street.flop && betFrac <= 0.5 ? checkRaiseShare(s, h) : (h.tier == HandTier.nutsMonster ? 1.0 : 0.0);
    if (xr > 0) {
      final roll = DeterministicActionMixer.roll([s.hero!.high, s.hero!.low], s.board, potBeforeBet + toCall);
      final freqs = {DecisionAction.betRaise: xr, DecisionAction.call: 1 - xr};
      if (roll < xr * 100) {
        return _raiseTo(potBeforeBet, toCall, stack, streetsLeft, m, '$tag | ${!heroIp && s.street == Street.flop ? 'check-raise frecuencial ${(xr * 100).round()}%' : 'Monster: raise por valor'}', read)
            .copyWith(freqGto: freqs, freqSource: xr < 1 ? FreqSource.modelCalibrated : FreqSource.pure);
      }
      return DecisionOutput(
          action: DecisionAction.call,
          sizing: Sizing(bb: toCall, potPct: betFrac * 100),
          freqGto: freqs,
          freqSource: FreqSource.modelCalibrated,
          metrics: m,
          justificacionGto: '$tag | call (rama no-raise de la mezcla X/R ${(xr * 100).round()}%)',
          ajusteExplotativoRead: read);
    }
    final float = h.tier == HandTier.backdoorBlockerBluff || h.tier == HandTier.airGiveUp;
    return DecisionOutput(
        action: DecisionAction.call,
        sizing: Sizing(bb: toCall, potPct: betFrac * 100),
        metrics: m,
        justificacionGto: '$tag | ${float ? 'float (overcards/backdoors) para completar MDF' : 'dentro del presupuesto'}',
        ajusteExplotativoRead: read);
  }

  static double checkRaiseShare(GameState s, HandTierResult h) => DefenseBudget.checkRaiseShare(
      h, BoardAnalyzer.analyze(s.board.sublist(0, 3), pfa: s.villainPosition!, defender: s.heroPosition));

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
