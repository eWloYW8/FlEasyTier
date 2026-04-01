import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/network_instance.dart';

class RouteListView extends StatelessWidget {
  const RouteListView({super.key, required this.routes});

  final List<PeerRouteInfo> routes;

  @override
  Widget build(BuildContext context) {
    if (routes.isEmpty) return _empty(context);

    // Sort: direct first, then by cost
    final sorted = List.of(routes)
      ..sort((a, b) {
        if (a.isDirect != b.isDirect) return a.isDirect ? -1 : 1;
        return a.cost.compareTo(b.cost);
      });

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: sorted.length,
      itemBuilder: (_, i) => _RouteCard(route: sorted[i]),
    );
  }

  Widget _empty(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.alt_route, size: 56, color: cs.outlineVariant),
          const SizedBox(height: 16),
          Text('No routes',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: cs.outline)),
          const SizedBox(height: 4),
          Text('Routes will appear when peers connect',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.outlineVariant)),
        ],
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.route});
  final PeerRouteInfo route;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final directColor = route.isDirect ? Colors.green : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: hostname + IP + route type ──
            Row(
              children: [
                // Route indicator
                Container(
                  width: 4,
                  height: 36,
                  decoration: BoxDecoration(
                    color: directColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            route.hostname.isNotEmpty
                                ? route.hostname
                                : 'Peer ${route.peerId}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          if (route.version.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text('v${route.version}',
                                style: TextStyle(
                                    fontSize: 10, color: cs.outline)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (route.ipv4Addr.isNotEmpty) ...[
                            InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () {
                                Clipboard.setData(
                                    ClipboardData(text: route.ipv4Addr));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content:
                                        Text('Copied: ${route.ipv4Addr}'),
                                    duration: const Duration(seconds: 1),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(route.ipv4Addr,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                        color: cs.primary,
                                      )),
                                  const SizedBox(width: 2),
                                  Icon(Icons.copy,
                                      size: 10, color: cs.outlineVariant),
                                ],
                              ),
                            ),
                          ],
                          if (route.ipv6Addr.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(route.ipv6Addr,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    color: cs.outline,
                                  ),
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Route type
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: directColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        route.isDirect ? Icons.swap_horiz : Icons.mediation,
                        size: 13,
                        color: directColor.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        route.isDirect ? 'Direct' : 'Relay',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: directColor.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Stats row ──
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _StatChip(
                  icon: Icons.tag,
                  value: '${route.peerId}',
                  label: 'Peer ID',
                ),
                _StatChip(
                  icon: Icons.alt_route,
                  value: '${route.cost}',
                  label: 'Cost',
                ),
                _StatChip(
                  icon: Icons.schedule,
                  value: route.latencyMs > 0
                      ? '${route.latencyMs.toStringAsFixed(1)}ms'
                      : '-',
                  label: 'Latency',
                  valueColor: _latencyColor(route.latencyMs),
                ),
                if (!route.isDirect)
                  _StatChip(
                    icon: Icons.mediation,
                    value: '${route.nextHopPeerId}',
                    label: 'Next Hop',
                  ),
              ],
            ),

            // ── NAT info ──
            if (route.udpNatType.isNotEmpty || route.tcpNatType.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (route.udpNatType.isNotEmpty) ...[
                    Icon(Icons.swap_vert, size: 12, color: cs.outline),
                    const SizedBox(width: 4),
                    Text('UDP ',
                        style: TextStyle(fontSize: 10, color: cs.outline)),
                    Text(route.udpNatType,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _natColor(route.udpNatType))),
                  ],
                  if (route.udpNatType.isNotEmpty &&
                      route.tcpNatType.isNotEmpty)
                    const SizedBox(width: 16),
                  if (route.tcpNatType.isNotEmpty) ...[
                    Icon(Icons.sync_alt, size: 12, color: cs.outline),
                    const SizedBox(width: 4),
                    Text('TCP ',
                        style: TextStyle(fontSize: 10, color: cs.outline)),
                    Text(route.tcpNatType,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _natColor(route.tcpNatType))),
                  ],
                ],
              ),
            ],

            // ── Proxy CIDRs ──
            if (route.proxyCidrs.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  Icon(Icons.lan_outlined, size: 12, color: cs.outline),
                  ...route.proxyCidrs.map((cidr) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(cidr,
                            style: const TextStyle(
                                fontSize: 10, fontFamily: 'monospace')),
                      )),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Stat chip
// ═══════════════════════════════════════════════════════════════════════════

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.value,
    required this.label,
    this.valueColor,
  });
  final IconData icon;
  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: cs.outline),
          const SizedBox(width: 4),
          Text('$label ',
              style: TextStyle(fontSize: 10, color: cs.outline)),
          Text(value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: valueColor,
              )),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════

Color _latencyColor(double ms) {
  if (ms <= 0) return Colors.grey;
  if (ms < 30) return Colors.green;
  if (ms < 80) return Colors.green.shade300;
  if (ms < 150) return Colors.orange;
  return Colors.red;
}

Color _natColor(String natType) {
  final lower = natType.toLowerCase();
  if (lower.contains('open') || lower.contains('full cone')) {
    return Colors.green;
  }
  if (lower.contains('restricted') || lower.contains('no pat')) {
    return Colors.orange;
  }
  if (lower.contains('symmetric') || lower.contains('sym')) {
    return Colors.red.shade400;
  }
  return Colors.grey;
}
