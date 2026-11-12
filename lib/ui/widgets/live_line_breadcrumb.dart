import 'package:flutter/material.dart';

import '../../application/hand_flow_fsm.dart';
import '../theme/obsidian_theme.dart';

/// Cinta viva de la mano actual (26px). Tocar un chip = Instant Rewind al estado exacto ANTES de ese paso.
/// Solo vive en memoria durante la mano en curso; Nueva Mano la vacía (sin historial persistente).
class LiveLineBreadcrumb extends StatelessWidget {
  const LiveLineBreadcrumb({super.key, required this.fsm, required this.act});
  final HandFlowFSM fsm;
  final void Function(VoidCallback) act;

  @override
  Widget build(BuildContext context) {
    final labels = fsm.stepLabels;
    final chips = <Widget>[];
    for (var i = 0; i < labels.length; i++) {
      if (labels[i].isEmpty) continue;
      final card = labels[i].startsWith('[');
      if (chips.isNotEmpty) chips.add(const Padding(padding: EdgeInsets.symmetric(horizontal: 2), child: Text('➔', style: TextStyle(color: Obsidian.muted, fontSize: 10))));
      final idx = i;
      chips.add(InkWell(
        key: ValueKey('crumb-$idx'),
        onTap: () => act(() => fsm.rewindTo(idx)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: card ? Obsidian.amberCheck.withValues(alpha: .12) : Obsidian.surfaceCard,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: Obsidian.bevelTop),
          ),
          child: Text(labels[i], style: Obsidian.num(size: 10, color: card ? Obsidian.amberCheck : Obsidian.text)),
        ),
      ));
    }
    return SizedBox(
      height: 26,
      child: chips.isEmpty
          ? const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(left: 8), child: Text('Línea de la mano: —', style: TextStyle(color: Obsidian.muted, fontSize: 10))))
          : ListView(
              key: const ValueKey('breadcrumb'),
              scrollDirection: Axis.horizontal,
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              children: [Row(children: chips)],
            ),
    );
  }
}
