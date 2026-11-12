import '../discipline/ev_sanity_guard.dart';
import '../models/decision_output.dart';
import '../models/game_state.dart';
import '../reads/gg_profiler.dart';
import 'pro_coach_narrative_builder.dart';

/// Ensambla en O(1) (sin Monte Carlo) la lectura dominante, la prueba de EV en 1 línea y la regla activa.
class DecisionJustifier {
  DecisionJustifier._();

  static String _p(double x) => '${(x * 100).toStringAsFixed(0)}%';
  static String _bb(double x) => '${x >= 0 ? '+' : ''}${x.toStringAsFixed(1)}bb';

  static String profileLabel(ReadProfile rp, VillainProfile vp) => switch (rp.archetype) {
        GgArchetype.recPassiveFish => 'Fish_Station',
        GgArchetype.trapperLimpReraiser => 'Trapper',
        GgArchetype.scaredMoneyReg => vp == VillainProfile.nit ? 'Nit' : 'Scared_Reg',
        GgArchetype.agroSpewy => 'Agro_Maniac',
        GgArchetype.unknownReg => 'Reg_GTO',
        GgArchetype.poolDefault => 'Pool_Default',
      };

  static String activeRule(DecisionOutput d) {
    final txt = '${d.justificacionGto} ${d.ajusteExplotativoRead}';
    if (txt.contains(EvSanityGuard.tag)) return 'EV_Sanity_Guard';
    if (txt.contains('[EV_ANCHOR]')) return 'Nash_Anchor';
    final m = RegExp(r'Terminal_Closer (T\d)').firstMatch(txt);
    if (m != null) return m.group(1)!;
    final u = RegExp(r'Unmapped_Spot (\w+)').firstMatch(txt);
    if (u != null) return u.group(1)!;
    if (txt.contains(EvSanityGuard.tag)) return 'EV_Sanity_Guard';
    if (txt.contains('[EV_ANCHOR]')) return 'Nash_Anchor';
    if (txt.contains('[EV_GATE]')) return 'EV_Gate';
    if (txt.contains('Turn_SDV_Into_Bluff') || txt.contains('Overbet_Bluff')) return 'LLinus_Overbet';
    if (txt.contains('Auto_Profit_Stab')) return 'Insta_Check_Stab';
    if (txt.contains('FOLD DISCIPLINADO')) return 'Disciplined_Overfold';
    if ((d.exploitDeltaEV ?? 0) > 0) return 'Exploit_Layer';
    return 'GTO_Baseline';
  }

  static DecisionJustification build(GameState s, ReadProfile rp, DecisionOutput d, VillainPerceivedRange r,
      {required double potBefore, required double toCall}) {
    final timed = s.actions.where((a) => a.actor == s.villainPosition && a.timing != TimingTell.none).lastOrNull;
    final tell = timed == null
        ? ''
        : ' + ${timed.timing == TimingTell.instaAction ? '⚡Insta' : '⏳Tank'}-${timed.type.name} ${timed.street.name}';
    final fish = rp.archetype == GgArchetype.recPassiveFish;
    final rangeTag = r.totalActiveCombos == 0
        ? 'Sin rango (RFI)'
        : r.isCapped
            ? 'Rango Capado (${_p(r.nutsAndMonstersPct)} Nuts)'
            : fish
                ? 'Inelástico (${_p(r.predictedFoldFreq)} Fold)'
                : 'Nuts ${_p(r.nutsAndMonstersPct)} / Aire ${_p(r.pureAirAndBluffsPct)}';
    final pre = r.activePresets.isEmpty ? '' : ' | ${r.activePresets.join(' + ')}';
    final mental = switch (rp.mentalState) {
      VillainMentalState.steamingTilt => ' 🔥TILT',
      VillainMentalState.scaredDeepProtector => ' 🛡️PROTECTOR',
      VillainMentalState.normal => '',
    };
    final rio = '${d.justificacionGto} ${d.ajusteExplotativoRead}'.contains('RIESGO RIO') ? ' [⚠️ RIESGO RIO: KICKER DOMINADO]' : '';
    final badge = '[READ: ${profileLabel(rp, s.villainProfile)}$mental$tell$pre -> $rangeTag]$rio';

    final rule = activeRule(d);
    final range = r.totalActiveCombos == 0
        ? 'Rango rival: n/a'
        : 'Rango rival: ${_p(r.nutsAndMonstersPct)} Nuts / ${_p(r.mediumShowdownPct)} Pares Medios / '
            '${_p(r.drawsAndSemibluffsPct)} Draws / ${_p(r.pureAirAndBluffsPct)} Aire';
    final blk = r.heroBlockedNutsCombos > 0 ? ' | Blockers Hero: -${r.heroBlockedNutsCombos.toStringAsFixed(1)} combos Nuts' : '';
    final ev = d.actionEVs;
    final pass = ev == null ? 0.0 : (ev['check'] ?? ev['call'] ?? 0.0);
    final bet = ev == null ? 0.0 : (ev['betRaise'] ?? ev['raise'] ?? 0.0);
    final delta = d.exploitDeltaEV;
    final ex = delta != null && delta > 0 ? ' (${_bb(delta)} Exploit)' : '';
    String math;
    if (d.action == DecisionAction.betRaise) {
      final size = d.sizing?.bb ?? 0;
      final alpha = size <= 0 ? 0.0 : size / (potBefore + toCall + size);
      final evs = ev == null ? '' : ' | EV(Bet): ${_bb(bet)} vs EV(${toCall > 0 ? 'Call' : 'Check'}): ${_bb(pass)}$ex';
      math = 'FE Real (${_p(r.predictedFoldFreq)}) ${r.predictedFoldFreq > alpha ? '>' : '<='} Alpha (${_p(alpha)}) | $range$blk$evs';
    } else if (toCall > 0) {
      final odds = toCall / (potBefore + 2 * toCall);
      final evs = ev == null ? '' : ' | EV(Call): ${_bb(pass)} vs EV(Fold): ${_bb(0)}';
      final save = d.action == DecisionAction.fold && rule == 'T2' ? ' | MDF apagado por T2_Shutdown -> Ahorro: ${_bb(delta ?? 0)}' : ex;
      final polar = s.street == Street.river && potBefore > 0 && toCall / potBefore >= 0.75 ? 'Polar_Node | ' : '';
      math = '${polar}Bluff Rival Real (${_p(r.predictedBluffFreq)}) ${r.predictedBluffFreq < odds ? '<' : '>='} Pot Odds (${_p(odds)}) | '
          '$range$blk$evs$save';
    } else {
      final evs = ev == null ? '' : ' | EV(Check): ${_bb(pass)} vs EV(Bet): ${_bb(bet)}$ex';
      math = '${d.action.name} | $range$blk$evs';
    }
    final geo = RegExp(r'Geo-2E Sizing \(\d+% Pot\) -> Prepara River All-In exacto de \d+% Pot \(\+EV Max\)')
        .firstMatch('${d.justificacionGto} ${d.ajusteExplotativoRead}');
    if (geo != null) math = '${geo.group(0)} | $math';
    if (r.topRepresentativeHands.isNotEmpty) math = '$math | Top: ${r.topRepresentativeHands.take(3).join(', ')}';
    final n = ProCoachNarrativeBuilder.build(s, rp, d, r, potBefore: potBefore, toCall: toCall, rule: rule, profile: profileLabel(rp, s.villainProfile));
    return DecisionJustification(
        activeReadBadge: badge,
        mathRationale: math,
        activeCloserRule: rule,
        villainReadExplanation: n.$1,
        evWhyExplanation: n.$2,
        nextStreetPlan: n.$3);
  }
}
