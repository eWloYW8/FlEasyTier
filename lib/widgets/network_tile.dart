import 'package:flutter/material.dart';

import '../models/network_config.dart';
import 'status_badge.dart';

class NetworkTile extends StatelessWidget {
  const NetworkTile({
    super.key,
    required this.config,
    required this.running,
    this.peerCount = 0,
    this.selected = false,
    this.onTap,
  });

  final NetworkConfig config;
  final bool running;
  final int peerCount;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Status dot
                _StatusDot(running: running),
                const SizedBox(width: 12),
                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        config.displayName,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (config.networkName.isNotEmpty)
                            Flexible(
                              child: Text(
                                config.networkName,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: cs.outline),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          if (running && peerCount > 0) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.people_outline,
                                size: 12, color: cs.outline),
                            const SizedBox(width: 2),
                            Text('$peerCount',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: cs.outline)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Badge
                StatusBadge(running: running, compact: true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.running});
  final bool running;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: running ? Colors.green : Colors.grey.shade400,
        boxShadow: running
            ? [
                BoxShadow(
                  color: Colors.green.withValues(alpha: 0.4),
                  blurRadius: 6,
                  spreadRadius: 1,
                )
              ]
            : null,
      ),
    );
  }
}
