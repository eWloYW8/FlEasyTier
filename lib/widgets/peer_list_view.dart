import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/network_instance.dart';

/// Groups peers by ID, shows expandable cards with connection detail sheets.
class PeerListView extends StatelessWidget {
  const PeerListView({
    super.key,
    required this.conns,
    required this.routes,
  });

  final List<PeerConnInfo> conns;
  final List<PeerRouteInfo> routes;

  @override
  Widget build(BuildContext context) {
    if (conns.isEmpty && routes.isEmpty) return _empty(context);

    final peerIds = <int>{};
    for (final c in conns) {
      peerIds.add(c.peerId);
    }
    for (final r in routes) {
      peerIds.add(r.peerId);
    }
    final sortedIds = peerIds.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: sortedIds.length,
      itemBuilder: (_, i) {
        final pid = sortedIds[i];
        return _PeerCard(
          peerId: pid,
          route: routes.where((r) => r.peerId == pid).firstOrNull,
          conns: conns.where((c) => c.peerId == pid).toList(),
        );
      },
    );
  }

  Widget _empty(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline, size: 56, color: cs.outlineVariant),
          const SizedBox(height: 16),
          Text('No peers connected',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: cs.outline)),
          const SizedBox(height: 4),
          Text('Waiting for network activity...',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.outlineVariant)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Peer Card
// ═══════════════════════════════════════════════════════════════════════════

class _PeerCard extends StatefulWidget {
  const _PeerCard({
    required this.peerId,
    this.route,
    required this.conns,
  });
  final int peerId;
  final PeerRouteInfo? route;
  final List<PeerConnInfo> conns;

  @override
  State<_PeerCard> createState() => _PeerCardState();
}

class _PeerCardState extends State<_PeerCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = widget.route;
    final hostname = r?.hostname ?? '';
    final ip = r?.ipv4Addr ?? '';
    final hasDetail = r != null || widget.conns.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // ── Header ──
          InkWell(
            onTap: hasDetail ? () => setState(() => _expanded = !_expanded) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  _PeerAvatar(
                    label: hostname.isNotEmpty ? hostname[0].toUpperCase() : '#',
                    active: widget.conns.isNotEmpty,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hostname.isNotEmpty ? hostname : 'Peer ${widget.peerId}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        _SubtitleRow(ip: ip, route: r, connCount: widget.conns.length),
                      ],
                    ),
                  ),
                  if (r != null) _RouteTypeBadge(isDirect: r.isDirect),
                  if (hasDetail) ...[
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.expand_more, color: cs.outline, size: 22),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Expanded detail ──
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState:
                _expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: _ExpandedBody(
                route: widget.route, conns: widget.conns, peerId: widget.peerId),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Peer avatar
// ═══════════════════════════════════════════════════════════════════════════

class _PeerAvatar extends StatelessWidget {
  const _PeerAvatar({required this.label, required this.active});
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: cs.primaryContainer,
          child: Text(label,
              style: TextStyle(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              )),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? Colors.green : Colors.grey.shade400,
              border: Border.all(
                  color: Theme.of(context).cardColor, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Subtitle row under hostname
// ═══════════════════════════════════════════════════════════════════════════

class _SubtitleRow extends StatelessWidget {
  const _SubtitleRow({required this.ip, this.route, required this.connCount});
  final String ip;
  final PeerRouteInfo? route;
  final int connCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(fontSize: 12, color: cs.outline);
    final parts = <Widget>[];

    if (ip.isNotEmpty) {
      parts.add(Text(ip, style: style.copyWith(fontFamily: 'monospace')));
    }
    if (route != null && route!.latencyMs > 0) {
      parts.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 11, color: _latencyColor(route!.latencyMs)),
          const SizedBox(width: 2),
          Text('${route!.latencyMs.toStringAsFixed(1)}ms',
              style: style.copyWith(color: _latencyColor(route!.latencyMs))),
        ],
      ));
    }
    if (connCount > 0) {
      parts.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cable, size: 11, color: cs.outline),
          const SizedBox(width: 2),
          Text('$connCount conn${connCount > 1 ? 's' : ''}', style: style),
        ],
      ));
    }
    if (route?.version.isNotEmpty == true) {
      parts.add(Text('v${route!.version}', style: style));
    }

    return Wrap(
      spacing: 12,
      runSpacing: 2,
      children: parts,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Route type badge (P2P / Relay)
// ═══════════════════════════════════════════════════════════════════════════

class _RouteTypeBadge extends StatelessWidget {
  const _RouteTypeBadge({required this.isDirect});
  final bool isDirect;

  @override
  Widget build(BuildContext context) {
    final color = isDirect ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDirect ? Icons.swap_horiz : Icons.mediation,
            size: 14,
            color: color.shade700,
          ),
          const SizedBox(width: 4),
          Text(isDirect ? 'P2P' : 'Relay',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color.shade700,
              )),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Expanded body (route info + connection list)
// ═══════════════════════════════════════════════════════════════════════════

class _ExpandedBody extends StatelessWidget {
  const _ExpandedBody({this.route, required this.conns, required this.peerId});
  final PeerRouteInfo? route;
  final List<PeerConnInfo> conns;
  final int peerId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),

        // ── Route info grid ──
        if (route != null) _routeInfoGrid(context, route!),

        // ── Connections list ──
        if (conns.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text('CONNECTIONS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: cs.outline,
                  letterSpacing: 1,
                )),
          ),
          ...conns.map((c) => _ConnTile(conn: c, peerId: peerId)),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _routeInfoGrid(BuildContext context, PeerRouteInfo r) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top stats row
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _MiniStat(
                icon: Icons.tag,
                label: 'Peer ID',
                value: '${r.peerId}',
                color: cs.primary,
              ),
              _MiniStat(
                icon: Icons.alt_route,
                label: 'Cost',
                value: '${r.cost}',
                color: cs.tertiary,
              ),
              _MiniStat(
                icon: Icons.schedule,
                label: 'Latency',
                value: r.latencyMs > 0
                    ? '${r.latencyMs.toStringAsFixed(1)} ms'
                    : '-',
                color: _latencyColor(r.latencyMs),
              ),
              _MiniStat(
                icon: Icons.mediation,
                label: 'Next Hop',
                value: r.isDirect ? 'Direct' : 'Peer ${r.nextHopPeerId}',
                color: r.isDirect ? Colors.green : Colors.orange,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // NAT info
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              if (r.udpNatType.isNotEmpty)
                _InfoPill(icon: Icons.swap_vert, label: 'UDP NAT', value: r.udpNatType),
              if (r.tcpNatType.isNotEmpty)
                _InfoPill(icon: Icons.sync_alt, label: 'TCP NAT', value: r.tcpNatType),
              if (r.ipv6Addr.isNotEmpty)
                _InfoPill(icon: Icons.language, label: 'IPv6', value: r.ipv6Addr),
            ],
          ),
          // Proxy CIDRs
          if (r.proxyCidrs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                Icon(Icons.lan_outlined, size: 13, color: cs.outline),
                const SizedBox(width: 2),
                ...r.proxyCidrs.map((cidr) => Chip(
                      label: Text(cidr,
                          style: const TextStyle(
                              fontSize: 11, fontFamily: 'monospace')),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      side: BorderSide.none,
                      padding: EdgeInsets.zero,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                    )),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Mini stat chip (icon + label + value inside a tinted container)
// ═══════════════════════════════════════════════════════════════════════════

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 9,
                      color: cs.outline,
                      fontWeight: FontWeight.w500)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Info pill (compact label:value inline)
// ═══════════════════════════════════════════════════════════════════════════

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: cs.outline),
        const SizedBox(width: 4),
        Text('$label ', style: TextStyle(fontSize: 11, color: cs.outline)),
        Text(value,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Connection tile (tappable → opens detail bottom sheet)
// ═══════════════════════════════════════════════════════════════════════════

class _ConnTile extends StatelessWidget {
  const _ConnTile({required this.conn, required this.peerId});
  final PeerConnInfo conn;
  final int peerId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tunnelColor = _tunnelColor(conn.tunnelLabel);

    return InkWell(
      onTap: () => _showConnDetail(context, conn, peerId),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            // Protocol badge
            Container(
              width: 44,
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: tunnelColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(conn.tunnelLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: tunnelColor,
                    letterSpacing: 0.5,
                  )),
            ),
            const SizedBox(width: 10),
            // Address
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conn.remoteAddr.isNotEmpty ? conn.remoteAddr : '-',
                    style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: cs.onSurface),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      if (conn.isClient)
                        _tinyLabel(cs, 'Client')
                      else
                        _tinyLabel(cs, 'Server'),
                      if (conn.isClosed) ...[
                        const SizedBox(width: 4),
                        _tinyLabel(cs, 'Closed', warn: true),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Traffic indicators
            _TrafficIndicator(
              rxBytes: conn.rxBytes,
              txBytes: conn.txBytes,
              latencyMs: conn.latencyMs,
              lossRate: conn.lossRate,
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: cs.outlineVariant),
          ],
        ),
      ),
    );
  }

  Widget _tinyLabel(ColorScheme cs, String text, {bool warn = false}) {
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: warn
            ? cs.errorContainer.withValues(alpha: 0.6)
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: warn ? cs.error : cs.outline,
          )),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Traffic indicator (compact RX/TX/latency/loss)
// ═══════════════════════════════════════════════════════════════════════════

class _TrafficIndicator extends StatelessWidget {
  const _TrafficIndicator({
    required this.rxBytes,
    required this.txBytes,
    required this.latencyMs,
    required this.lossRate,
  });
  final int rxBytes;
  final int txBytes;
  final double latencyMs;
  final double lossRate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final small = TextStyle(fontSize: 10, color: cs.outline, fontFamily: 'monospace');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_downward, size: 9, color: Colors.blue.shade300),
            Text(_fmtBytes(rxBytes), style: small),
            const SizedBox(width: 4),
            Icon(Icons.arrow_upward, size: 9, color: Colors.orange.shade300),
            Text(_fmtBytes(txBytes), style: small),
          ],
        ),
        if (latencyMs > 0 || lossRate > 0)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (latencyMs > 0)
                Text('${latencyMs.toStringAsFixed(0)}ms',
                    style: small.copyWith(
                        color: _latencyColor(latencyMs), fontSize: 9)),
              if (latencyMs > 0 && lossRate > 0) const SizedBox(width: 4),
              if (lossRate > 0)
                Text('${(lossRate * 100).toStringAsFixed(1)}%',
                    style: small.copyWith(
                        color: lossRate > 0.05 ? Colors.red : cs.outline,
                        fontSize: 9)),
            ],
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Connection detail bottom sheet
// ═══════════════════════════════════════════════════════════════════════════

void _showConnDetail(BuildContext context, PeerConnInfo c, int peerId) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => _ConnDetailSheet(
        conn: c,
        peerId: peerId,
        scrollController: scroll,
      ),
    ),
  );
}

class _ConnDetailSheet extends StatelessWidget {
  const _ConnDetailSheet({
    required this.conn,
    required this.peerId,
    required this.scrollController,
  });
  final PeerConnInfo conn;
  final int peerId;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    final tunnelColor = _tunnelColor(conn.tunnelLabel);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      children: [
        // ── Header ──
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: tunnelColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(conn.tunnelLabel,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: tunnelColor,
                  )),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Connection Detail',
                  style:
                      ts.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (conn.isClosed)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('CLOSED',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: cs.error)),
              ),
          ],
        ),
        const SizedBox(height: 24),

        // ── Tunnel section ──
        _DetailSection(title: 'Tunnel', icon: Icons.cable, children: [
          _DetailRow(label: 'Protocol', value: conn.tunnelType.isNotEmpty ? conn.tunnelType : 'tcp'),
          _DetailRow(label: 'Connection ID', value: conn.connId, mono: true, copyable: true),
          _DetailRow(label: 'Local Address', value: conn.localAddr, mono: true, copyable: true),
          _DetailRow(label: 'Remote Address', value: conn.remoteAddr, mono: true, copyable: true),
          _DetailRow(label: 'Role', value: conn.isClient ? 'Client (outgoing)' : 'Server (incoming)'),
          _DetailRow(label: 'Peer ID', value: '$peerId'),
          if (conn.networkName.isNotEmpty)
            _DetailRow(label: 'Network', value: conn.networkName),
        ]),
        const SizedBox(height: 16),

        // ── Traffic section ──
        _DetailSection(title: 'Traffic', icon: Icons.bar_chart, children: [
          _TrafficBar(rxBytes: conn.rxBytes, txBytes: conn.txBytes),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TrafficCard(
                  icon: Icons.arrow_downward,
                  color: Colors.blue,
                  label: 'Received',
                  bytes: conn.rxBytes,
                  packets: conn.rxPackets,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TrafficCard(
                  icon: Icons.arrow_upward,
                  color: Colors.orange,
                  label: 'Sent',
                  bytes: conn.txBytes,
                  packets: conn.txPackets,
                ),
              ),
            ],
          ),
        ]),
        const SizedBox(height: 16),

        // ── Quality section ──
        _DetailSection(title: 'Quality', icon: Icons.speed, children: [
          _QualityGauge(
            latencyMs: conn.latencyMs,
            lossRate: conn.lossRate,
          ),
        ]),
        const SizedBox(height: 16),

        // ── Features section ──
        if (conn.features.isNotEmpty) ...[
          _DetailSection(
              title: 'Features',
              icon: Icons.extension_outlined,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: conn.features.map((f) {
                    return Chip(
                      label: Text(f, style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      side: BorderSide.none,
                      padding: EdgeInsets.zero,
                      labelPadding:
                          const EdgeInsets.symmetric(horizontal: 8),
                    );
                  }).toList(),
                ),
              ]),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Detail section wrapper
// ═══════════════════════════════════════════════════════════════════════════

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Text(title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                      letterSpacing: 0.5,
                    )),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Detail row (label: value)
// ═══════════════════════════════════════════════════════════════════════════

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.mono = false,
    this.copyable = false,
  });
  final String label;
  final String value;
  final bool mono;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final displayValue = value.isNotEmpty ? value : '-';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.outline,
                  fontWeight: FontWeight.w500,
                )),
          ),
          Expanded(
            child: SelectableText(displayValue,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  fontFamily: mono ? 'monospace' : null,
                )),
          ),
          if (copyable && value.isNotEmpty)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Copied: $value'),
                    duration: const Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.copy, size: 14, color: cs.outlineVariant),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Traffic bar (visual ratio of RX vs TX)
// ═══════════════════════════════════════════════════════════════════════════

class _TrafficBar extends StatelessWidget {
  const _TrafficBar({required this.rxBytes, required this.txBytes});
  final int rxBytes;
  final int txBytes;

  @override
  Widget build(BuildContext context) {
    final total = rxBytes + txBytes;
    if (total == 0) {
      return const SizedBox(
        height: 8,
        child: ClipRRect(
          borderRadius: BorderRadius.all(Radius.circular(4)),
          child: LinearProgressIndicator(value: 0),
        ),
      );
    }
    final rxFraction = rxBytes / total;

    return Column(
      children: [
        SizedBox(
          height: 8,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                Expanded(
                  flex: (rxFraction * 100).round().clamp(1, 99),
                  child: Container(color: Colors.blue.shade400),
                ),
                Expanded(
                  flex: ((1 - rxFraction) * 100).round().clamp(1, 99),
                  child: Container(color: Colors.orange.shade400),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('RX ${(rxFraction * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                    fontSize: 10, color: Colors.blue.shade400)),
            Text('Total ${_fmtBytes(total)}',
                style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.outline)),
            Text('TX ${((1 - rxFraction) * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                    fontSize: 10, color: Colors.orange.shade400)),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Traffic card (bytes + packets for one direction)
// ═══════════════════════════════════════════════════════════════════════════

class _TrafficCard extends StatelessWidget {
  const _TrafficCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.bytes,
    required this.packets,
  });
  final IconData icon;
  final Color color;
  final String label;
  final int bytes;
  final int packets;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: cs.outline,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          Text(_fmtBytes(bytes),
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800)),
          Text('$packets packets',
              style: TextStyle(fontSize: 11, color: cs.outline)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Quality gauge (latency + loss)
// ═══════════════════════════════════════════════════════════════════════════

class _QualityGauge extends StatelessWidget {
  const _QualityGauge({required this.latencyMs, required this.lossRate});
  final double latencyMs;
  final double lossRate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final latColor = _latencyColor(latencyMs);
    final lossColor =
        lossRate > 0.1 ? Colors.red : (lossRate > 0.02 ? Colors.orange : Colors.green);

    String qualityLabel;
    Color qualityColor;
    if (latencyMs <= 0) {
      qualityLabel = 'No data';
      qualityColor = cs.outline;
    } else if (latencyMs < 30 && lossRate < 0.01) {
      qualityLabel = 'Excellent';
      qualityColor = Colors.green;
    } else if (latencyMs < 80 && lossRate < 0.03) {
      qualityLabel = 'Good';
      qualityColor = Colors.green.shade300;
    } else if (latencyMs < 150 && lossRate < 0.1) {
      qualityLabel = 'Fair';
      qualityColor = Colors.orange;
    } else {
      qualityLabel = 'Poor';
      qualityColor = Colors.red;
    }

    return Column(
      children: [
        // Overall quality
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: qualityColor,
              ),
            ),
            const SizedBox(width: 8),
            Text(qualityLabel,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: qualityColor)),
          ],
        ),
        const SizedBox(height: 16),
        // Detail bars
        Row(
          children: [
            Expanded(
              child: _QualityMetric(
                label: 'Latency',
                value: latencyMs > 0
                    ? '${latencyMs.toStringAsFixed(1)} ms'
                    : '-',
                fraction: latencyMs > 0
                    ? (latencyMs / 300).clamp(0.0, 1.0)
                    : 0,
                color: latColor,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _QualityMetric(
                label: 'Packet Loss',
                value: lossRate > 0
                    ? '${(lossRate * 100).toStringAsFixed(2)}%'
                    : '0%',
                fraction: (lossRate * 5).clamp(0.0, 1.0),
                color: lossColor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QualityMetric extends StatelessWidget {
  const _QualityMetric({
    required this.label,
    required this.value,
    required this.fraction,
    required this.color,
  });
  final String label;
  final String value;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style:
                    TextStyle(fontSize: 11, color: cs.outline)),
            Text(value,
                style:
                    TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: fraction,
            backgroundColor: cs.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 6,
          ),
        ),
      ],
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

Color _tunnelColor(String label) {
  switch (label) {
    case 'UDP':
      return Colors.blue;
    case 'TCP':
      return Colors.teal;
    case 'QUIC':
      return Colors.purple;
    case 'WS':
      return Colors.indigo;
    case 'WSS':
      return Colors.deepPurple;
    case 'Ring':
      return Colors.brown;
    default:
      return Colors.blueGrey;
  }
}

String _fmtBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1024 * 1024 * 1024) {
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}
