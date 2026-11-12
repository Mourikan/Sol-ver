import '../models/decision_output.dart';
import '../models/game_state.dart';
import '../postflop/geometric_2e_planner.dart';
import '../postflop/hand_tier.dart';
import '../postflop/turn_river_solver.dart';
import '../reads/gg_profiler.dart';

/// Explicador narrativo determinista (español, jerga pro): lectura del rival, por qué gana más EV y plan de la siguiente
/// calle. Solo ensambla datos ya calculados (rango percibido, EVs, regla activa); no decide nada.
class ProCoachNarrativeBuilder {
  ProCoachNarrativeBuilder._();

  static String _p(double x) => '${(x * 100).round()}%';
  static String _bb(double x) => '${x >= 0 ? '+' : ''}${x.toStringAsFixed(2)}bb';

  static (String, String, String) build(GameState s, ReadProfile rp, DecisionOutput d, VillainPerceivedRange r,
      {required double potBefore, required double toCall, required String rule, required String profile}) {
    return (_read(s, r, profile, rp.mentalState), _why(s, rp, d, r, potBefore, toCall, rule), _plan(s, d, potBefore, toCall, rule));
  }

  static String _shape(VillainPerceivedRange r) {
    if (r.totalActiveCombos == 0) return 'sin rango definido';
    if (r.isCapped) return 'CAPADO';
    if (r.nutsAndMonstersPct + r.pureAirAndBluffsPct >= 0.8 && r.mediumShowdownPct < 0.15) return 'POLARIZADO';
    return 'MIXTO';
  }

  static String _read(GameState s, VillainPerceivedRange r, String profile, VillainMentalState mentalState) {
    if (s.villainPosition == null) {
      return 'Rival aún sin definir: decisión de apertura con el rango posicional (los jugadores por detrás no han actuado).';
    }
    if (r.totalActiveCombos == 0) {
      return 'Rival [$profile] en ${s.villainPosition!.name.toUpperCase()}: rango no modelado en este nodo; la decisión se apoya en la tabla y en las pot odds.';
    }
    final buckets = '${_p(r.nutsAndMonstersPct)} Nuts, ${_p(r.mediumShowdownPct)} Pares Medios, '
        '${_p(r.drawsAndSemibluffsPct)} Draws, ${_p(r.pureAirAndBluffsPct)} Aire';
    final top = r.topRepresentativeHands.take(3).join(', ');
    final v = s.villainPosition!;
    final last = s.actions.where((a) => a.actor == v).lastOrNull;
    String why;
    if (s.street == Street.preflop) {
      why = last == null
          ? 'Rango posicional de ${v.name.toUpperCase()} antes de actuar.'
          : 'Su ${last.type.name} preflop desde ${v.name.toUpperCase()} define un rango de ${r.totalActiveCombos} combos ponderados.';
    } else if (last == null) {
      why = 'Aún no ha actuado en esta calle: rango heredado de su línea previa.';
    } else if (last.type == ActionType.check) {
      why = last.timing == TimingTell.instaAction
          ? 'Su Insta-Check descarta casi todas las trampas: los Sets/Dos Pares habrían pensado en apostar.'
          : 'Su check renuncia a la iniciativa: los Sets/Dos Pares pierden peso y el rango se apoya en manos de showdown.';
    } else if (last.type == ActionType.call) {
      why = 'Su call (sin subir) aparta la mayoría de monstruos que habrían resubido y mantiene pares y proyectos.';
    } else {
      why = last.timing == TimingTell.longTank
          ? 'Tank + apuesta grande en microlímites: polarización hacia valor pesado.'
          : 'Su apuesta concentra valor y faroles según el sizing; los pares medios suelen pasar.';
    }
    final presets = r.activePresets.isEmpty ? '' : ' Lecturas activas: ${r.activePresets.join(', ')}.';
    final mental = switch (mentalState) {
      VillainMentalState.steamingTilt => ' [🔥 EN TILT]: paga con cualquier par/draw y farolea más.',
      VillainMentalState.scaredDeepProtector => ' [🛡️ PROTEGIENDO STACK]: foldea más en botes grandes.',
      VillainMentalState.normal => '',
    };
    return 'Rival [$profile] con rango ${_shape(r)} ($buckets). $why${top.isEmpty ? '' : ' Manos más representativas: $top.'}$presets$mental';
  }

  static String _why(GameState s, ReadProfile rp, DecisionOutput d, VillainPerceivedRange r, double potBefore, double toCall, String rule) {
    final ev = d.actionEVs ?? const <String, double>{};
    final bet = ev['betRaise'];
    final pass = ev['check'] ?? ev['call'];
    final dx = d.exploitDeltaEV;
    final ex = dx != null && dx > 0 ? ' (${_bb(dx)} de Exploit sobre el ancla GTO)' : '';
    final ruleTxt = rule == 'GTO_Baseline' ? '' : ' Regla activa: $rule.';
    final blk = r.heroBlockedNutsCombos > 0
        ? ' Además nuestras cartas bloquean ${r.heroBlockedNutsCombos.toStringAsFixed(0)} combos de sus mejores manos.'
        : '';
    final txt = '${d.justificacionGto} ${d.ajusteExplotativoRead}';
    final bait = RegExp(r'ANZUELO INDUCTOR \(\+([0-9.]+)bb').firstMatch(txt);
    if (bait != null && d.action == DecisionAction.betRaise) {
      return 'Sizing anzuelo (25% Pot) con Nuts para inducir spazz-raise del perfil agresivo '
          '(+${bait.group(1)} bb extra vs apuesta grande que lo haría foldear su aire).$ruleTxt';
    }
    final cbk = RegExp(r'Min-3Bet de recreativo \(Pot Odds regaladas del ([0-9.]+)%\)').firstMatch(txt);
    if (cbk != null) {
      return 'Min-3Bet de recreativo (Pot Odds regaladas del ${cbk.group(1)}%): '
          '${d.action == DecisionAction.betRaise ? '4-bet grande de castigo con premium para cobrar de su rango medio inelástico' : 'Call obligatorio por odds directas/implícitas con todo tu rango jugable'}; '
          'precaución postflop ante posible trampa AA/KK si mete pot-bet.';
    }
    if (txt.contains('MIN-RAISE TURN/RIVER')) {
      return 'Min-raise en Turn/River de un perfil pasivo en microlímites: su rango es >82% dos pares/set/color (no re-farolea). '
          '${d.action == DecisionAction.fold ? 'El top pair solo gana a sus pocos faroles: fold disciplinado.' : 'Solo seguimos porque las odds directas pagan nuestro proyecto.'}$ruleTxt';
    }
    if (txt.contains('nano-bet')) {
      return '1bb / nano-bet = check disfrazado con dinero muerto: '
          '${d.action == DecisionAction.betRaise ? 'subimos al ~80% del bote total para cobrar valor y negar equidad (3x de 1bb no cobraría nada).' : 'pagamos porque las odds directas son mínimas frente a nuestra equidad.'}$ruleTxt';
    }
    if (txt.contains('RIESGO RIO')) {
      return 'Kicker dominado: la mayor parte de su rango de valor tras varios barriles tiene nuestro mismo par con mejor kicker o '
          'dos pares+; pagar regala el stack (Reverse Implied Odds). ${d.action == DecisionAction.fold ? 'Fold' : 'Check'} ahorra la diferencia.$ruleTxt';
    }
    switch (d.action) {
      case DecisionAction.betRaise:
        final sz = d.sizing;
        final size = sz?.bb ?? 0;
        final alpha = size <= 0 ? 0.0 : size / (potBefore + toCall + size);
        final geo = d.justificacionGto.contains('Geo-2E') ? ' (Geo-2E)' : '';
        final evTxt = bet == null ? '' : ' genera ${_bb(bet)} vs ${_bb(pass ?? 0)} de ${toCall > 0 ? 'pagar' : 'pasar'}$ex';
        final fe = r.totalActiveCombos == 0
            ? ''
            : ' Necesitamos ${_p(alpha)} de folds (Alpha) y este perfil foldea ~${_p(r.predictedFoldFreq)} en este nodo'
                '${r.predictedFoldFreq > alpha ? ': el farol ya es rentable por sí solo y el valor cobra de peores.' : '; la apuesta vive de valor/equidad, no de fold equity.'}';
        return '${toCall > 0 ? 'Subir' : 'Apostar'} ${sz == null ? '' : '${sz.potPct.round()}% Pot (${size.toStringAsFixed(1)}bb)'}$geo$evTxt.$fe$blk$ruleTxt';
      case DecisionAction.call:
        final odds = toCall / (potBefore + 2 * toCall);
        return 'Pagar ${toCall.toStringAsFixed(1)}bb exige ganar el ${_p(odds)} de las veces (pot odds). '
            '${r.totalActiveCombos == 0 ? '' : 'Su rango trae ~${_p(r.predictedBluffFreq)} de aire/faroles, '}'
            '${pass == null ? '' : 'EV(call) ${_bb(pass)} vs ${_bb(0)} de foldear$ex.'}$blk$ruleTxt';
      case DecisionAction.fold:
        final odds = toCall <= 0 ? 0.0 : toCall / (potBefore + 2 * toCall);
        return 'Foldear: necesitaríamos ganar el ${_p(odds)} y su rango solo trae ~${_p(r.predictedBluffFreq)} de faroles reales'
            '${pass == null ? '' : ' (EV del call ${_bb(pass)})'}; el fold ahorra la diferencia$ex.$ruleTxt';
      case DecisionAction.check:
        return 'Pasar${pass == null ? '' : ' (EV ${_bb(pass)})'} rinde más que apostar${bet == null ? '' : ' (EV ${_bb(bet)})'}: '
            'apostar aislaría contra manos mejores o regalaría fold equity inexistente; controlamos el bote y realizamos equidad$ex.$ruleTxt';
    }
  }

  static String _plan(GameState s, DecisionOutput d, double potBefore, double toCall, String rule) {
    final tier = s.board.length >= 3 && s.hero != null
        ? HandTierClassifier.classify(s.hero!.high.id, s.hero!.low.id, [for (final c in s.board) c.id]).tier
        : null;
    final strong = tier == HandTier.nutsMonster;
    final draw = tier == HandTier.highEquityComboDraw;
    final vsRaise = strong
        ? 'Si nos resube: con manos tan fuertes, call o all-in (no hay fold).'
        : (draw
            ? 'Si nos resube: continuar solo si las pot odds cubren la equidad del proyecto; si no, fold.'
            : 'Si nos resube: 100% Hero-Fold (T2_Shutdown: el pool sube con muy pocos faroles en este nodo).');
    switch (s.street) {
      case Street.preflop:
        return d.action == DecisionAction.fold
            ? 'Mano terminada para nosotros; esperar a la siguiente.'
            : 'En el flop: c-bet de rango en boards secos a favor de nuestro rango; en boards conectados, chequear la parte media. '
                '${d.action == DecisionAction.betRaise ? 'Si nos 4-betean: continuar solo con el top del rango (y 4-bet bluffs con blocker frente a regs).' : ''}';
      case Street.river:
        return d.action == DecisionAction.betRaise
            ? '$vsRaise Si paga: mano terminada, se muestra.'
            : (d.action == DecisionAction.fold ? 'Mano terminada.' : 'Mano a showdown; no hay más calles.');
      case Street.flop || Street.turn:
        final next = s.street == Street.flop ? 'Turn' : 'River';
        if (d.action == DecisionAction.betRaise) {
          final stack = s.effectiveStackBb ?? 100;
          final pot = potBefore + 2 * (d.sizing?.bb ?? 0);
          final geo = Geometric2EPlanner.plan(pot, stack - (d.sizing?.bb ?? 0));
          final cont = geo != null
              ? 'disparar ${geo.$1.round()}% en el $next (geométrico hacia el all-in)'
              : 'seguir apostando ~${(TurnRiverSolver.thinRiverPct * 2).round()}-75% en el $next';
          return 'Si solo paga y el $next es ladrillo, $cont; si completa proyectos, frenar con manos medias. $vsRaise';
        }
        if (d.action == DecisionAction.call) {
          return 'En el $next: check-call si cae ladrillo y seguimos por delante del rango de farol; fold frente a un segundo barril grande sin mejorar. '
              '${strong ? 'Con manos tan fuertes, valorar check-raise en el $next.' : ''}';
        }
        if (d.action == DecisionAction.check) {
          return 'Si apuesta: defender según el presupuesto MDF del nodo (manos con showdown/equidad). Si pasa: valorar probe/barril en el $next con valor y proyectos.';
        }
        return 'Mano terminada para nosotros.';
    }
  }
}
