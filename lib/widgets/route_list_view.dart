import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/network_instance.dart';

class RouteListView extends StatelessWidget {
  const RouteListView({
    super.key,
    required this.routes,
    required this.latencyFirstEnabled,
  });

  final List<PeerRouteInfo> routes;
  final bool latencyFirstEnabled;

  @override
  Widget build(BuildContext context) {
    if (routes.isEmpty) return const SizedBox.shrink();

    final sorted = List.of(routes)
      ..sort((a, b) {
        if (a.isDirect != b.isDirect) return a.isDirect ? -1 : 1;
        final latA = a.pathLatencyLatencyFirstMs > 0
            ? a.pathLatencyLatencyFirstMs
            : a.latencyMs;
        final latB = b.pathLatencyLatencyFirstMs > 0
            ? b.pathLatencyLatencyFirstMs
            : b.latencyMs;
        return latA.compareTo(latB);
      });
    final peerNames = <int, String>{};
    for (final route in sorted) {
      if (route.hostname.isNotEmpty) {
        peerNames[route.peerId] = route.hostname;
      }
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: sorted.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.28),
      ),
      itemBuilder: (context, index) => _RouteRow(
        route: sorted[index],
        peerNames: peerNames,
        latencyFirstEnabled: latencyFirstEnabled,
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.route,
    required this.peerNames,
    required this.latencyFirstEnabled,
  });
  final PeerRouteInfo route;
  final Map<int, String> peerNames;
  final bool latencyFirstEnabled;

  @override
  Widget build(BuildContext context) {
    final accent = route.isDirect ? Colors.green : Colors.orange;
    final currentLatency = route.currentLatencyMs(latencyFirstEnabled);
    final currentCost = route.currentCost(latencyFirstEnabled);
    final currentHop = route.currentNextHopPeerId(latencyFirstEnabled);
    final latencyFirstHop = route.nextHopPeerIdLatencyFirst;
    final showAlternate =
        route.hasLatencyFirstRoute &&
        (!latencyFirstEnabled &&
            (latencyFirstHop != route.nextHopPeerId ||
                route.costLatencyFirst != route.cost));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  route.isDirect ? Icons.route_outlined : Icons.compare_arrows,
                  size: 15,
                  color: accent.shade700,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            route.hostname.isNotEmpty
                                ? route.hostname
                                : 'Peer ${route.peerId}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _RoutePill(
                          text: route.isDirect ? 'Direct' : 'Relay',
                          color: accent.shade700,
                          background: accent.withValues(alpha: 0.14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        if (route.ipv4Cidr.isNotEmpty)
                          _RouteMeta(
                            icon: Icons.lan_outlined,
                            text: route.ipv4Cidr,
                            mono: true,
                          ),
                        if (route.ipv6Addr.isNotEmpty)
                          _RouteMeta(
                            icon: Icons.language,
                            text: route.ipv6Addr,
                            mono: true,
                          ),
                        _RouteMeta(
                          icon: Icons.schedule_outlined,
                          text: currentLatency > 0
                              ? '${currentLatency.toStringAsFixed(1)} ms'
                              : '-',
                          color: _latencyColor(currentLatency),
                        ),
                        _RouteMeta(
                          icon: Icons.route_outlined,
                          text: 'cost $currentCost',
                        ),
                        if (currentHop > 0 && currentCost > 1)
                          _RouteMeta(
                            icon: Icons.alt_route_outlined,
                            text: _currentHopLabel(currentHop),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              _RouteMeta(
                icon: latencyFirstEnabled
                    ? Icons.check_circle_outline
                    : Icons.radio_button_checked,
                text: latencyFirstEnabled ? 'Current: latency-first' : 'Current: default',
                color: latencyFirstEnabled ? Colors.teal : Colors.blueGrey,
              ),
              if (showAlternate)
                _RouteMeta(
                  icon: Icons.speed_outlined,
                  text: _latencyFirstLabel(),
                ),
              if (showAlternate && route.pathLatencyLatencyFirstMs > 0)
                _RouteMeta(
                  icon: Icons.timelapse_outlined,
                  text:
                      'LF ${route.pathLatencyLatencyFirstMs.toStringAsFixed(1)} ms',
                  color: _latencyColor(route.pathLatencyLatencyFirstMs),
                ),
              if (route.instId.isNotEmpty)
                _RouteMeta(
                  icon: Icons.fingerprint_outlined,
                  text: route.instId,
                  mono: true,
                ),
              if (route.udpNatType.isNotEmpty)
                _RouteMeta(
                  icon: Icons.swap_vert,
                  text: route.udpNatType,
                ),
              if (route.tcpNatType.isNotEmpty)
                _RouteMeta(
                  icon: Icons.sync_alt,
                  text: route.tcpNatType,
                ),
              ...route.proxyCidrs.map(
                (cidr) => _CopyableMeta(
                  icon: Icons.account_tree_outlined,
                  text: cidr,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _currentHopLabel(int peerId) => _nextHopLabel(peerId, route.currentCost(latencyFirstEnabled));

  String _nextHopLabel(int peerId, int cost) {
    if (peerId <= 0 || cost <= 1) return 'Direct';
    final name = peerNames[peerId];
    if (name == null || name.isEmpty) {
      return 'hop $peerId';
    }
    return 'hop $peerId $name';
  }

  String _latencyFirstLabel() {
    if (route.costLatencyFirst <= 1) return 'LF Direct';
    final name = peerNames[route.nextHopPeerIdLatencyFirst];
    if (name == null || name.isEmpty) return 'LF Peer';
    return 'LF $name';
  }
}

class _RouteMeta extends StatelessWidget {
  const _RouteMeta({
    required this.icon,
    required this.text,
    this.color,
    this.mono = false,
  });

  final IconData icon;
  final String text;
  final Color? color;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = color ?? cs.outline;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: fg),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  text,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: fg,
                    fontWeight: FontWeight.w400,
                    fontFamily: mono ? 'monospace' : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CopyableMeta extends StatelessWidget {
  const _CopyableMeta({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copied: $text'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: _RouteMeta(
        icon: icon,
        text: text,
        mono: true,
      ),
    );
  }
}

class _RoutePill extends StatelessWidget {
  const _RoutePill({
    required this.text,
    required this.color,
    required this.background,
  });

  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          color: color,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

Color _latencyColor(double ms) {
  if (ms <= 0) return Colors.grey;
  if (ms < 30) return Colors.green;
  if (ms < 80) return Colors.lightGreen;
  if (ms < 150) return Colors.orange;
  return Colors.red;
}
