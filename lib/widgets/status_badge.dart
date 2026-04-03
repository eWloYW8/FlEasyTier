import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/color_compat.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.running, this.compact = false});

  final bool running;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: running
              ? withAlphaFactor(Colors.green, 0.12)
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          running ? l10n.t('status.on') : l10n.t('status.off'),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: running ? Colors.green.shade700 : cs.outline,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: running
            ? withAlphaFactor(Colors.green, 0.12)
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: running ? Colors.green : cs.outline,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            running ? l10n.t('status.running') : l10n.t('status.stopped'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: running ? Colors.green.shade700 : cs.outline,
            ),
          ),
        ],
      ),
    );
  }
}
