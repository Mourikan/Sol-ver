import 'package:flutter/material.dart';

import '../theme/obsidian_theme.dart';

/// PinnedOracleHeader (Fase 17.0): Oráculo SIEMPRE visible arriba de los controles en cuanto hay mano + posición.
/// Contexto vivo del cálculo + ACCIÓN gigante + EV + [Hice otra cosa] + cuerpo (porqué + rango) desplazable sin truncar.
class PinnedOracleHeader extends StatelessWidget {
  const PinnedOracleHeader({
    super.key,
    required this.contextLine,
    required this.action,
    required this.evLine,
    required this.status,
    required this.body,
    this.updatedBanner,
    this.onOverride,
    this.maxHeightFraction = .38,
  });

  final String contextLine;
  final String action;
  final String evLine;
  final String status;
  final String? updatedBanner;
  final VoidCallback? onOverride;
  final Widget body;
  final double maxHeightFraction;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height * maxHeightFraction;
    return Container(
      key: const ValueKey('pinned-oracle'),
      constraints: BoxConstraints(maxHeight: h),
      decoration: const BoxDecoration(
        color: Obsidian.surfacePanel,
        border: Border(bottom: BorderSide(color: Obsidian.borderFine)),
      ),
      child: SingleChildScrollView(
        key: const ValueKey('oracle-scroll'),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              contextLine,
              key: const ValueKey('oracle-context'),
              style: Obsidian.num(size: 12, color: Obsidian.textSecondary, weight: FontWeight.w700),
            ),
            if (updatedBanner != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Obsidian.buttonActive, borderRadius: BorderRadius.circular(5)),
                  child: Text(
                    updatedBanner!,
                    key: const ValueKey('oracle-updated'),
                    style: Obsidian.num(size: 11, color: Obsidian.buttonActiveText),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        action,
                        key: const ValueKey('oracle-action'),
                        style: Obsidian.num(size: 22, color: Obsidian.textPrimary, weight: FontWeight.w900),
                      ),
                      Text(
                        evLine,
                        key: const ValueKey('oracle-ev'),
                        style: Obsidian.num(size: 12, color: Obsidian.textSecondary, weight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                if (onOverride != null)
                  TextButton(
                    key: const ValueKey('override'),
                    style: TextButton.styleFrom(minimumSize: const Size(48, 46)),
                    onPressed: onOverride,
                    child: const Text('Hice otra cosa', style: TextStyle(color: Obsidian.textSecondary, fontSize: 12)),
                  ),
              ],
            ),
            Text(
              status,
              key: const ValueKey('oracle-status'),
              style: const TextStyle(color: Obsidian.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 6),
            body,
          ],
        ),
      ),
    );
  }
}
