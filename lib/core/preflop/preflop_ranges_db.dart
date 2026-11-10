import 'dart:typed_data';

import '../models/game_state.dart';
import 'range_notation.dart';

enum PreflopAction { fold, call, raise }

/// calibratedHeuristicBase: matriz interna (charts semilla + calibración por auditoría, NO solver); modelCalibrated: mezclas de frontera derivadas por modelo (NO solver); solverImport: exports reales.
enum RangeSource { calibratedHeuristicBase, modelCalibrated, solverImport, bootstrapGTO }

enum ThreeBetStructure { polar, linear }

class RakeConfig {
  const RakeConfig(this.percent, this.capBb);
  final double percent;
  final double capBb;

  double rakeOn(double potBb) {
    final r = potBb * percent;
    return r < capBb ? r : capBb;
  }

  /// Bote final esperado por tipo de bote (bb): base del rake efectivo.
  static const expectedFinalPot = {
    PotType.limped: 8.0,
    PotType.srp: 22.0,
    PotType.threeBet: 55.0,
    PotType.fourBetPlus: 100.0,
  };

  /// Expected_Final_Pot_Rake / E_Final_Pot.
  /// Distribución de tamaños de bote final (bb, probabilidad) por tipo de bote: pequeño / medio / grande / stack-off.
  static const potDistribution = <PotType, List<(double, double)>>{
    PotType.limped: [(4, 0.55), (10, 0.30), (25, 0.10), (80, 0.05)],
    PotType.srp: [(10, 0.40), (25, 0.30), (60, 0.20), (200, 0.10)],
    PotType.threeBet: [(25, 0.30), (55, 0.35), (120, 0.20), (200, 0.15)],
    PotType.fourBetPlus: [(50, 0.25), (100, 0.30), (200, 0.45)],
  };

  /// Rake efectivo ponderado por tamaño de bote: Σ p·min(%·pot, cap) / Σ p·pot (los caps muerden en botes medianos/grandes).
  double effectiveRate(PotType t) {
    var num = 0.0, den = 0.0;
    for (final (pot, p) in potDistribution[t]!) {
      num += p * rakeOn(pot);
      den += p * pot;
    }
    return num / den;
  }

  /// Plantilla estilo GGPoker (5% con caps en bb decrecientes; anclas del usuario NL10 ~8bb, NL25 ~4bb).
  /// NO verificada contra la tabla oficial de la sala ni modela PVI: editable.
  static const byStake = {
    Stake.nl2: RakeConfig(0.05, 20.0),
    Stake.nl5: RakeConfig(0.05, 9.0),
    Stake.nl10: RakeConfig(0.05, 8.0),
    Stake.nl25: RakeConfig(0.05, 4.0),
    Stake.nl50: RakeConfig(0.05, 3.0),
    Stake.nl100: RakeConfig(0.05, 2.5),
    Stake.nl200: RakeConfig(0.05, 1.5),
  };

  /// Valores por defecto editables: verificar contra la estructura real de la sala.
  static const defaults = {
    RakeTier.microHighRake: RakeConfig(0.05, 4.0),
    RakeTier.midRake: RakeConfig(0.04, 1.0),
  };
}

/// Nodo compilado: pesos 0..1 por mano (índice 169) y acción. Lookup O(1).
class RangeNode {
  RangeNode(this.id, Map<PreflopAction, String> notation, {RangeSource? source})
      : weights = _compile(notation),
        source = source ?? (_hasMix(notation) ? RangeSource.modelCalibrated : RangeSource.calibratedHeuristicBase);

  /// Nodo construido desde pesos ya resueltos (p.ej. bootstrap de solver open-source).
  RangeNode.fromWeights(this.id, Map<PreflopAction, Float32List> w, {required this.source}) : weights = Map.unmodifiable(w);

  static bool _hasMix(Map<PreflopAction, String> n) => n.values.any((v) => v.contains(':'));

  final String id;
  final RangeSource source;
  final Map<PreflopAction, Float32List> weights;

  double freq(PreflopAction a, int i) => weights[a]?[i] ?? (a == PreflopAction.fold ? _fold(i) : 0);

  double _fold(int i) {
    var s = 0.0;
    for (final w in weights.values) {
      s += w[i];
    }
    return 1 - s;
  }

  double percent(PreflopAction a) => weights[a] == null ? 0 : Matrix169.percent(weights[a]!);

  /// Prioridad por orden de declaración: raise > call. La suma por mano nunca excede 1.
  static Map<PreflopAction, Float32List> _compile(Map<PreflopAction, String> n) {
    final used = Float32List(169);
    final out = <PreflopAction, Float32List>{};
    for (final e in n.entries) {
      final w = RangeNotation.parse(e.value);
      for (var i = 0; i < 169; i++) {
        final free = 1 - used[i];
        if (w[i] > free) w[i] = free;
        used[i] += w[i];
      }
      out[e.key] = w;
    }
    return Map.unmodifiable(out);
  }
}

/// Rangos semilla 100bb 6-max (aproximación de charts públicos; reemplazables por import de solver).
class PreflopRangesDb {
  PreflopRangesDb._();

  static const openSizeBb = {
    Position.utg: 2.5,
    Position.mp: 2.5,
    Position.co: 2.5,
    Position.btn: 2.5,
    Position.sb: 3.0,
  };

  static const _rfiMicro = {
    Position.utg: '22+,A2s+,KTs+,QTs+,JTs,T9s,98s,AJo+,KQo',
    Position.mp: '22+,A2s+,K9s+,Q9s+,J9s+,T9s,98s,87s,ATo+,KJo+',
    Position.co: '22+,A2s+,K5s+,Q8s+,J8s+,T8s+,97s+,86s+,76s,65s,54s,A9o+,KTo+,QTo+,JTo',
    Position.btn: '22+,A2s+,K2s+,Q4s+,J6s+,T6s+,96s+,85s+,74s+,64s+,53s+,43s,A2o+,K8o+,Q9o+,J9o+,T9o,98o',
    Position.sb: '22+,A2s+,K2s+,Q5s+,J7s+,T7s+,97s+,86s+,75s+,64s+,54s,A2o+,K9o+,Q9o+,J9o+,T9o',
  };

  static const _rfiMidExtra = {
    Position.utg: '',
    Position.mp: '',
    Position.co: 'K2s+,Q6s+,J7s+,T7s+,96s+,75s+,A8o+,K9o+',
    Position.btn: 'Q2s+,J4s+,T5s+,95s+,84s+,73s+,K7o+,Q8o+',
    Position.sb: 'Q2s+,J5s+,T6s+,96s+,85s+,K7o+',
  };

  static const threeBetValue = _tbValue;
  static const _tbValue = {
    Position.utg: 'QQ+,AKs,AKo',
    Position.mp: 'JJ+,AQs+,AKo',
    Position.co: 'TT+,AJs+,KQs,AQo+',
    Position.btn: '99+,ATs+,KJs+,AJo+,KQo',
    Position.sb: '88+,A9s+,KTs+,QJs,ATo+,KJo+',
  };

  static const _tbPolarBluffs = {
    Position.utg: 'A5s,A4s',
    Position.mp: 'A5s-A3s',
    Position.co: 'A5s-A2s,K9s,76s',
    Position.btn: 'A5s-A2s,K9s,Q9s,J9s,T8s,76s,65s',
    Position.sb: 'A5s-A2s,K9s,K8s,Q9s,J9s,T8s,97s,86s,76s,65s',
  };

  static const _tbLinearExt = {
    Position.utg: 'JJ,AQs,KQs',
    Position.mp: 'TT,AJs,KQs,AQo',
    Position.co: '99,ATs,KJs,QJs,JTs,AJo,KQo,A5s',
    Position.btn: '77-88,A8s-A9s,KTs,QTs+,JTs,T9s,ATo,KJo,QJo,A5s-A4s',
    Position.sb: '77,A8s,K9s,QTs,JTs,T9s,A9o,KTo,QJo,A5s-A4s',
  };

  static const _flatMidIp = {
    Position.utg: '55-JJ,AJs-AQs,KJs+,QJs,JTs,T9s,98s',
    Position.mp: '55-TT,ATs-AJs,KJs+,QJs,JTs,T9s,98s,87s,AQo',
    Position.co: '22-99,A9s-ATs,KTs+,QTs+,JTs,T9s,98s,87s,76s,AJo,KQo',
  };

  /// Mezclas de frontera explícitas (raise weight; el resto va al call si el nodo permite flat, si no a fold).
  /// Valores del usuario: BTN vs CO A5s 75/25/0; CO vs MP 88 35/65/0 (mid) y 35/0/65 (micro); 99 micro 50% por monotonía.
  static const mixOverrides = {
    // BTN vs CO: farol/total calibrado a ~35.5% (α del 3-bet IP) añadiendo suited con jugabilidad/blockers.
    (Position.btn, Position.co): ('A5s:0.75,Q9s,J9s,T8s,65s', 'A5s:0.75,Q9s,J9s,T8s,65s', 'A5s'),
    (Position.co, Position.mp): ('88:0.35', '88:0.35,99:0.5', ''),
  };

  static const _flatMicroBtn = '66-JJ,AQs,KQs';

  static const _vs3bet = {
    (Position.utg, false): ('KK+,AKs,A5s,A4s', '77-QQ,AKo,AQs,AJs,KQs,QJs,JTs'),
    (Position.mp, false): ('KK+,AKs,A5s,A4s', '77-QQ,AKo,AQs,AJs,ATs,KQs,KJs,QJs,JTs,T9s'),
    (Position.co, false): ('QQ+,AKs,AKo,A5s-A3s', '66-JJ,AQs,AJs,ATs,KQs,KJs,QJs,JTs,T9s,98s'),
    (Position.utg, true): ('KK+,AKs,A5s,A4s', '77-QQ,AKo,AQs,AJs,KQs,QJs,JTs,AQo'),
    (Position.mp, true): ('KK+,AKs,A5s,A4s', '77-QQ,AKo,AQs,AJs,ATs,KQs,KJs,QJs,JTs,AQo'),
    (Position.co, true): ('QQ+,AKs,AKo,A5s-A3s', '66-JJ,ATs-AQs,KJs+,QJs,JTs,T9s,AQo,KQo'),
    (Position.btn, true): ('QQ+,AKs,AKo,A5s-A3s', '55-JJ,A9s-AQs,KTs+,QTs+,JTs,T9s,98s,87s,76s,AJo,AQo,KQo'),
    (Position.sb, false): ('QQ+,AKs,AKo,A5s-A3s', '66-JJ,ATs-AQs,KTs+,QJs,JTs,T9s'),
  };

  /// Referencia de 4-bet/5-bet para blocker_weight.
  static const blockerReference = 'QQ+,AKs,AKo';

  static const vsNitAgroExtra4BetValue = 'TT+,AQs+,AKo';
  static const agroExtra4BetBluffs = 'A3s-A2s,K9s,KTs';
  static const stationValue3Bet = '88+,AJo+,KQo,KJs+';

  static final Map<String, RangeNode> _cache = {};

  static String _tierKey(RakeTier t) => t == RakeTier.microHighRake ? 'HR' : 'MR';

  static final Map<String, RangeNode> _overrides = {};

  /// Registra un nodo importado (bootstrap/solver) que sustituye al nodo semilla del mismo id.
  static void registerOverride(RangeNode node) => _overrides[node.id] = node;
  static void clearOverrides() => _overrides.clear();
  static String rfiId(Position p, RakeTier tier) => '${_tierKey(tier)}_RFI_${p.name}';

  static RangeNode rfi(Position p, RakeTier tier) {
    if (p == Position.bb) throw ArgumentError('BB no tiene RFI');
    final o = _overrides[rfiId(p, tier)];
    if (o != null) return o;
    return _cache.putIfAbsent('${_tierKey(tier)}_RFI_${p.name}', () {
      final r = tier == RakeTier.microHighRake ? _rfiMicro[p]! : '${_rfiMicro[p]},${_rfiMidExtra[p]}';
      return RangeNode('${_tierKey(tier)}_RFI_${p.name}', {PreflopAction.raise: r});
    });
  }

  static String rfiNotation(Position p, RakeTier tier) =>
      tier == RakeTier.microHighRake ? _rfiMicro[p]! : '${_rfiMicro[p]},${_rfiMidExtra[p]}';

  static ThreeBetStructure structure(Position hero, Position opener) {
    if (hero == Position.sb) return ThreeBetStructure.linear;
    if (hero == Position.bb) {
      return (opener == Position.utg || opener == Position.mp)
          ? ThreeBetStructure.linear
          : ThreeBetStructure.polar;
    }
    return ThreeBetStructure.polar;
  }

  static bool flatsAllowed(Position hero, Position opener, RakeTier tier) {
    if (hero == Position.bb) return true;
    if (tier == RakeTier.microHighRake) return hero == Position.btn;
    return (hero == Position.btn || hero == Position.co) && _flatMidIp.containsKey(opener);
  }

  /// Nodo vs RFI. BB: el rango de call se deriva por pot odds en el motor; aquí solo 3-bet.
  static RangeNode vsRfi(Position hero, Position opener, RakeTier tier) {
    if (hero.index <= opener.index) throw ArgumentError('$hero no puede enfrentar open de $opener');
    final id = '${_tierKey(tier)}_VS_${hero.name}_${opener.name}';
    return _cache.putIfAbsent(id, () {
      final s = structure(hero, opener);
      final micro = tier == RakeTier.microHighRake;
      final threeBet = <String>[_tbValue[opener]!];
      String call = '';
      if (s == ThreeBetStructure.linear) {
        threeBet.add(_tbLinearExt[opener]!);
      } else {
        threeBet.add(_tbPolarBluffs[opener]!);
        if (hero != Position.bb && !flatsAllowed(hero, opener, tier)) {
          threeBet.add(_tbLinearExt[opener]!);
        }
      }
      if (hero != Position.bb && flatsAllowed(hero, opener, tier)) {
        call = micro ? _flatMicroBtn : _flatMidIp[opener]!;
      }
      final mix = mixOverrides[(hero, opener)];
      if (mix != null) {
        threeBet.add(micro ? mix.$2 : mix.$1);
        if (!micro && mix.$3.isNotEmpty && call.isNotEmpty) call = '$call,${mix.$3}';
      }
      return RangeNode(id, {
        PreflopAction.raise: threeBet.join(','),
        if (call.isNotEmpty) PreflopAction.call: call,
      });
    });
  }

  static String threeBetNotation(Position hero, Position opener, RakeTier tier) {
    final n = vsRfi(hero, opener, tier).weights[PreflopAction.raise]!;
    return [for (var i = 0; i < 169; i++) if (n[i] > 0) Matrix169.label(i)].join(',');
  }

  static RangeNode vs3Bet(Position hero, {required bool heroInPosition}) {
    final key = (hero, heroInPosition);
    final d = _vs3bet[key] ??
        _vs3bet[(hero, !heroInPosition)] ??
        (throw ArgumentError('Sin nodo vs 3-bet para $hero'));
    final id = 'VS3B_${hero.name}_${heroInPosition ? 'IP' : 'OOP'}';
    return _cache.putIfAbsent(
        id, () => RangeNode(id, {PreflopAction.raise: d.$1, PreflopAction.call: d.$2}));
  }

  static const _polarBluffSet = {'A5s', 'A4s', 'A3s', 'A2s', 'K9s', 'K8s', 'Q9s', 'J9s', 'T8s', '97s', '86s', '76s', '65s'};
  static bool isPolarBluff3Bet(int i) => _polarBluffSet.contains(Matrix169.label(i));

  static bool isBluff4Bet(int i) => const {'A5s', 'A4s', 'A3s', 'A2s', 'K9s', 'KTs'}.contains(Matrix169.label(i));
}
