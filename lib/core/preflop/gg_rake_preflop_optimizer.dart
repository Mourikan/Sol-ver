import '../models/game_state.dart';
import 'preflop_ranges_db.dart';
import 'range_notation.dart';

/// No-Flop-No-Drop (GGPoker): si el bote se gana preflop no hay rake. El EV del 3-bet de `preflopEVs` YA modela esa
/// rama sin rake (fe x pot) y el rake del bote final cuando pagan, así que el bono no se vuelve a sumar (doble conteo):
/// se expone `noFlopRakeSavedBB` como métrica y, en manos frontera, la aguja se inclina por argmax(EV) que ya lo incluye.
class GgRakePreflopOptimizer {
  GgRakePreflopOptimizer._();

  static final border = RangeNotation.parse('A2s-A5s,KTs,QTs,AJo,KQo,77-99');

  static bool isBorder(int i) => border[i] > 0;

  /// Rake que el pool pagaría en el flop de la línea de call y que el 3-bet ahorra cuando el rival foldea: fe x rake(bote del call).
  static double noFlopRakeSavedBB(GameState s, double fe, double potIfCalledBb) => fe * RakeConfig.byStake[s.stake]!.rakeOn(potIfCalledBb);
}
