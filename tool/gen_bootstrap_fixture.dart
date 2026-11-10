// Genera test/fixtures/texassolver_btn_rfi.json: extracción SIMULADA estilo TexasSolver (baja resolución) del RFI de BTN.
// No es output real de TexasSolver: se deriva del rango semilla con mezclas en la frontera y combos omitidos a propósito.
import 'dart:convert';
import 'dart:io';

import 'package:sol_ver/core/models/game_state.dart';
import 'package:sol_ver/core/preflop/hand_normalizer.dart';
import 'package:sol_ver/core/preflop/preflop_ranges_db.dart';
import 'package:sol_ver/core/preflop/range_notation.dart';

void main() {
  final w = PreflopRangesDb.rfi(Position.btn, RakeTier.midRake).weights[PreflopAction.raise]!;
  double eq(int i) => HandProps.equity('MR_RFI_utg', i)!;
  final order = List<int>.generate(169, (i) => i)..sort((a, b) => eq(b).compareTo(eq(a)));
  final inRange = order.where((i) => w[i] > 0).length;
  final combos = <Map<String, Object>>[];
  for (var r = 0; r < order.length; r++) {
    final i = order[r];
    final edge = (r - inRange).abs() <= 10;
    if (edge && r.isOdd) continue; // omitidos: límite de resolución / RAM
    if (r > 160 && r.isEven) continue; // omitidos: cola de manos basura
    final raise = edge ? (r < inRange ? 70 : 30) : (w[i] > 0 ? 100 : 0);
    combos.add({'combo': Matrix169.label(i), 'rfi': raise, 'fold': 100 - raise});
  }
  final out = {'source': 'TexasSolver (simulado)', 'node': 'BTN_RFI_100bb', 'combos': combos};
  File('test/fixtures/texassolver_btn_rfi.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
  stdout.writeln('combos ${combos.length}/169');
}
