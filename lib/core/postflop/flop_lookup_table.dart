import 'dart:typed_data';

import '../evaluators/board_analyzer.dart';
import '../models/game_state.dart';
import '../preflop/range_notation.dart';
import 'hand_tier.dart';

enum FlopBucket {
  monotoneHigh,
  monotoneLow,
  pairedHigh,
  pairedLow,
  trips,
  aceHighDry,
  aceHighTwoTone,
  aceHighConnected,
  kingHighDry,
  kingHighTwoTone,
  kingHighConnected,
  broadwaySemiConnected,
  broadwayDry,
  broadwayTwoTone,
  broadwayVeryConnected,
  lowDry,
  lowTwoTone,
  lowSemiConnected,
  lowVeryConnectedRainbow,
  lowVeryConnectedTwoTone,
}

enum HuNode { srpIp, srpOop, threeBetIp, threeBetOop }

enum StrategyClass { rangeBetSmall, polarizedBetLarge, highCheckWithInitiative }

class NodeStrategy {
  const NodeStrategy(this.strategy, this.sizePct);
  final StrategyClass strategy;
  final double sizePct;
}

class BucketEntry {
  const BucketEntry(this.nodes, {this.donkSrp = false});
  final List<StrategyClass> nodes;
  final bool donkSrp;
}

class FlopStrategyResult {
  const FlopStrategyResult({
    required this.bucket,
    required this.node,
    required this.strategy,
    required this.sizePct,
    required this.betFreq,
    required this.tierShare,
    required this.donkEnabled,
    this.donkFreq = 0,
    this.donkSizePct = 0,
  });

  final FlopBucket bucket;
  final HuNode node;
  final StrategyClass strategy;
  final double sizePct;

  /// Fracción de combos del rango del PFA asignada a bet por la política del bucket (derivada, no solver).
  final double betFreq;
  double get checkFreq => 1 - betFreq;
  final Map<HandTier, double> tierShare;
  final bool donkEnabled;
  final double donkFreq;
  final double donkSizePct;
}

/// 20 arquetipos x 4 nodos HU. Lookup O(1) por (bucket, nodo); frecuencias = composición real del rango x política.
class FlopLookupTable {
  FlopLookupTable._();

  static const _s = StrategyClass.rangeBetSmall;
  static const _p = StrategyClass.polarizedBetLarge;
  static const _c = StrategyClass.highCheckWithInitiative;

  /// Columnas: [SRP_IP, SRP_OOP, 3BP_IP, 3BP_OOP].
  static const table = <FlopBucket, BucketEntry>{
    FlopBucket.monotoneHigh: BucketEntry([_s, _c, _s, _s]),
    FlopBucket.monotoneLow: BucketEntry([_s, _c, _s, _c]),
    FlopBucket.pairedHigh: BucketEntry([_s, _s, _s, _s]),
    FlopBucket.pairedLow: BucketEntry([_s, _c, _s, _s], donkSrp: true),
    FlopBucket.trips: BucketEntry([_s, _s, _s, _s]),
    FlopBucket.aceHighDry: BucketEntry([_s, _s, _s, _s]),
    FlopBucket.aceHighTwoTone: BucketEntry([_s, _s, _s, _s]),
    FlopBucket.aceHighConnected: BucketEntry([_p, _c, _p, _p]),
    FlopBucket.kingHighDry: BucketEntry([_s, _s, _s, _s]),
    FlopBucket.kingHighTwoTone: BucketEntry([_s, _s, _s, _s]),
    FlopBucket.kingHighConnected: BucketEntry([_p, _c, _p, _p]),
    FlopBucket.broadwaySemiConnected: BucketEntry([_p, _c, _p, _c]),
    FlopBucket.broadwayDry: BucketEntry([_s, _s, _s, _s]),
    FlopBucket.broadwayTwoTone: BucketEntry([_s, _c, _s, _s]),
    FlopBucket.broadwayVeryConnected: BucketEntry([_p, _c, _p, _c]),
    FlopBucket.lowDry: BucketEntry([_s, _s, _s, _s]),
    FlopBucket.lowTwoTone: BucketEntry([_s, _c, _s, _c]),
    FlopBucket.lowSemiConnected: BucketEntry([_c, _c, _p, _c], donkSrp: true),
    FlopBucket.lowVeryConnectedRainbow: BucketEntry([_c, _c, _p, _c], donkSrp: true),
    FlopBucket.lowVeryConnectedTwoTone: BucketEntry([_c, _c, _p, _c], donkSrp: true),
  };

  static const sizeOf = {
    StrategyClass.rangeBetSmall: 33.0,
    StrategyClass.polarizedBetLarge: 75.0,
    StrategyClass.highCheckWithInitiative: 66.0,
  };
  static const donkSizePct = 33.0;

  static const betTiers = {
    StrategyClass.rangeBetSmall: {
      HandTier.nutsMonster,
      HandTier.strongTopPairOverpair,
      HandTier.marginalMadeShowdown,
      HandTier.highEquityComboDraw,
      HandTier.backdoorBlockerBluff,
    },
    StrategyClass.polarizedBetLarge: {
      HandTier.nutsMonster,
      HandTier.strongTopPairOverpair,
      HandTier.highEquityComboDraw,
      HandTier.backdoorBlockerBluff,
    },
    StrategyClass.highCheckWithInitiative: {
      HandTier.nutsMonster,
      HandTier.highEquityComboDraw,
    },
  };

  static const donkTiers = {HandTier.nutsMonster, HandTier.strongTopPairOverpair, HandTier.highEquityComboDraw};

  static FlopBucket bucketOf(List<Card> flop) {
    if (flop.length != 3) throw ArgumentError('Flop requiere 3 cartas');
    final m = BoardAnalyzer.analyze(flop, pfa: Position.btn, defender: Position.bb);
    final ranks = flop.map((c) => c.rank.value).toList();
    final top = ranks.reduce((a, b) => a > b ? a : b);
    if (ranks.toSet().length == 1) return FlopBucket.trips;
    if (m.isPaired) {
      final pr = ranks.firstWhere((r) => ranks.where((x) => x == r).length == 2);
      return pr >= Rank.ten.value || top >= Rank.king.value ? FlopBucket.pairedHigh : FlopBucket.pairedLow;
    }
    if (m.suitTexture == SuitTexture.monotone) {
      return top >= Rank.queen.value ? FlopBucket.monotoneHigh : FlopBucket.monotoneLow;
    }
    final s3 = m.straightWindows;
    final twoTone = m.suitTexture == SuitTexture.twoTone;
    if (top == Rank.ace.value) {
      return s3 >= 1 ? FlopBucket.aceHighConnected : (twoTone ? FlopBucket.aceHighTwoTone : FlopBucket.aceHighDry);
    }
    if (top == Rank.king.value) {
      return s3 >= 1 ? FlopBucket.kingHighConnected : (twoTone ? FlopBucket.kingHighTwoTone : FlopBucket.kingHighDry);
    }
    if (top >= Rank.ten.value) {
      if (s3 >= 2) return FlopBucket.broadwayVeryConnected;
      if (s3 == 1) return FlopBucket.broadwaySemiConnected;
      return twoTone ? FlopBucket.broadwayTwoTone : FlopBucket.broadwayDry;
    }
    if (s3 >= 2) return twoTone ? FlopBucket.lowVeryConnectedTwoTone : FlopBucket.lowVeryConnectedRainbow;
    if (s3 == 1) return FlopBucket.lowSemiConnected;
    return twoTone ? FlopBucket.lowTwoTone : FlopBucket.lowDry;
  }

  static HuNode nodeOf(PotType potType, {required bool pfaInPosition}) {
    final threeBet = potType == PotType.threeBet || potType == PotType.fourBetPlus;
    return threeBet
        ? (pfaInPosition ? HuNode.threeBetIp : HuNode.threeBetOop)
        : (pfaInPosition ? HuNode.srpIp : HuNode.srpOop);
  }

  static NodeStrategy strategy(FlopBucket b, HuNode n) {
    final s = table[b]!.nodes[n.index];
    return NodeStrategy(s, sizeOf[s]!);
  }

  static bool donkEnabled(FlopBucket b, HuNode n) => n == HuNode.srpIp && table[b]!.donkSrp;

  /// Distribución de tiers de un rango (pesos 169) en un board, quitando combos bloqueados.
  static Map<HandTier, double> tierDistribution(Float32List range, List<Card> board) {
    final ids = [for (final c in board) c.id];
    var dead = 0;
    for (final c in ids) {
      dead |= 1 << c;
    }
    final acc = {for (final t in HandTier.values) t: 0.0};
    var total = 0.0;
    for (var i = 0; i < 169; i++) {
      final w = range[i];
      if (w <= 0) continue;
      for (final (a, b) in Matrix169.concreteCombos(i)) {
        if (dead & ((1 << a) | (1 << b)) != 0) continue;
        final t = HandTierClassifier.classify(a, b, ids).tier;
        acc[t] = acc[t]! + w;
        total += w;
      }
    }
    return {for (final e in acc.entries) e.key: total == 0 ? 0 : e.value / total};
  }

  static FlopStrategyResult evaluate(List<Card> flop, HuNode node,
      {required Float32List pfaRange, Float32List? defenderRange}) {
    final b = bucketOf(flop);
    final st = strategy(b, node);
    final dist = tierDistribution(pfaRange, flop);
    final bet = betTiers[st.strategy]!.fold<double>(0, (s, t) => s + dist[t]!);
    final donk = donkEnabled(b, node);
    var donkFreq = 0.0;
    if (donk && defenderRange != null) {
      final d = tierDistribution(defenderRange, flop);
      donkFreq = donkTiers.fold<double>(0, (s, t) => s + d[t]!);
    }
    return FlopStrategyResult(
      bucket: b,
      node: node,
      strategy: st.strategy,
      sizePct: st.sizePct,
      betFreq: bet,
      tierShare: dist,
      donkEnabled: donk,
      donkFreq: donkFreq,
      donkSizePct: donk ? donkSizePct : 0,
    );
  }
}
