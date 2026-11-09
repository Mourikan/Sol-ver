// Genera lib/core/preflop/data/hand_equity.g.dart: equity (permil) de cada mano 169 vs cada rango de referencia.
// Monte Carlo con semilla fija => salida reproducible. Uso: dart run tool/gen_hand_equity.dart [muestras]
import 'dart:io';
import 'dart:typed_data';

import 'package:sol_ver/core/evaluators/hand_evaluator.dart';
import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/preflop/preflop_ranges_db.dart';
import 'package:sol_ver/core/preflop/range_notation.dart';

int _s = 0x9E3779B9;
int _rnd(int n) {
  _s ^= (_s << 13) & 0xFFFFFFFF;
  _s ^= _s >> 17;
  _s ^= (_s << 5) & 0xFFFFFFFF;
  return (_s & 0x7FFFFFFF) % n;
}

void main(List<String> args) {
  final samples = args.isEmpty ? 6000 : int.parse(args.first);
  final refs = <String, Float32List>{};
  for (final t in RakeTier.values) {
    final tk = t == RakeTier.microHighRake ? 'HR' : 'MR';
    for (final p in [Position.utg, Position.mp, Position.co, Position.btn, Position.sb]) {
      refs['${tk}_RFI_${p.name}'] = PreflopRangesDb.rfi(p, t).weights[PreflopAction.raise]!;
    }
    for (final h in Position.values) {
      for (final o in Position.values) {
        if (h.index <= o.index || o == Position.bb) continue;
        refs['${tk}_3B_${h.name}_${o.name}'] = PreflopRangesDb.vsRfi(h, o, t).weights[PreflopAction.raise]!;
      }
    }
  }
  refs['BLOCKER_REF'] = RangeNotation.parse(PreflopRangesDb.blockerReference);

  final heroCombos = [for (var i = 0; i < 169; i++) Matrix169.concreteCombos(i)];
  final cards = Int32List(9);
  final out = StringBuffer()
    ..writeln('// GENERADO por tool/gen_hand_equity.dart ($samples muestras/mano, semilla fija). No editar.')
    ..writeln('const int handEquitySamples = $samples;')
    ..writeln('const Map<String, List<int>> handEquityPermil = {');

  final sw = Stopwatch()..start();
  for (final e in refs.entries) {
    final vc = <(int, int)>[];
    final vw = <double>[];
    for (var i = 0; i < 169; i++) {
      if (e.value[i] <= 0) continue;
      for (final c in Matrix169.concreteCombos(i)) {
        vc.add(c);
        vw.add(e.value[i].toDouble());
      }
    }
    final cum = Float64List(vw.length);
    var acc = 0.0;
    for (var k = 0; k < vw.length; k++) {
      cum[k] = acc += vw[k];
    }
    final row = <int>[];
    for (var i = 0; i < 169; i++) {
      final hc = heroCombos[i];
      var score = 0.0, n = 0;
      for (var s = 0; s < samples; s++) {
        final h = hc[s % hc.length];
        final dead0 = (1 << h.$1) | (1 << h.$2);
        int v1 = -1, v2 = -1;
        for (var tries = 0; tries < 64; tries++) {
          final x = _rnd(1 << 30) / (1 << 30) * acc;
          var lo = 0, hi = cum.length - 1;
          while (lo < hi) {
            final m = (lo + hi) >> 1;
            if (cum[m] < x) {
              lo = m + 1;
            } else {
              hi = m;
            }
          }
          final c = vc[lo];
          if (dead0 & ((1 << c.$1) | (1 << c.$2)) == 0) {
            v1 = c.$1;
            v2 = c.$2;
            break;
          }
        }
        if (v1 < 0) continue;
        var dead = dead0 | (1 << v1) | (1 << v2);
        for (var b = 0; b < 5; b++) {
          int c;
          do {
            c = _rnd(52);
          } while (dead & (1 << c) != 0);
          dead |= 1 << c;
          cards[2 + b] = c;
        }
        cards[0] = h.$1;
        cards[1] = h.$2;
        final hs = HandEvaluator.evaluate(cards, 7);
        cards[0] = v1;
        cards[1] = v2;
        final vs = HandEvaluator.evaluate(cards, 7);
        score += hs > vs ? 1 : (hs == vs ? 0.5 : 0);
        n++;
      }
      row.add(n == 0 ? 0 : (score / n * 1000).round());
    }
    out.writeln("  '${e.key}': [${row.join(',')}],");
    stderr.writeln('${e.key} ${sw.elapsed.inSeconds}s');
  }
  out.writeln('};');
  File('lib/core/preflop/data/hand_equity.g.dart').writeAsStringSync(out.toString());
}
