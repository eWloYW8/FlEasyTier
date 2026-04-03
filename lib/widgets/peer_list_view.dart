import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/network_instance.dart';
import '../utils/color_compat.dart';

class PeerListView extends StatelessWidget {
  const PeerListView({
    super.key,
    required this.conns,
    required this.routes,
    required this.latencyFirstEnabled,
  });

  final List<PeerConnInfo> conns;
  final List<PeerRouteInfo> routes;
  final bool latencyFirstEnabled;

  @override
  Widget build(BuildContext context) {
    final summaries = _buildSummaries(latencyFirstEnabled);
    final peerNames = <int, String>{};
    for (final route in routes) {
      if (route.hostname.isNotEmpty) {
        peerNames[route.peerId] = route.hostname;
      }
    }
    if (summaries.isEmpty) return const SizedBox.shrink();

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: summaries.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        color: withAlphaFactor(
          Theme.of(context).colorScheme.outlineVariant,
          0.28,
        ),
      ),
      itemBuilder: (context, index) => _PeerRow(
        summary: summaries[index],
        latencyFirstEnabled: latencyFirstEnabled,
        peerNames: peerNames,
      ),
    );
  }

  List<_PeerSummary> _buildSummaries(bool latencyFirstEnabled) {
    final peerIds = <int>{};
    for (final conn in conns) {
      peerIds.add(conn.peerId);
    }
    for (final route in routes) {
      peerIds.add(route.peerId);
    }

    final summaries = peerIds.map((peerId) {
      final peerConns = conns.where((conn) => conn.peerId == peerId).toList()
        ..sort((a, b) {
          if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
          return a.latencyMs.compareTo(b.latencyMs);
        });
      final route = routes.where((r) => r.peerId == peerId).firstOrNull;
      return _PeerSummary(route: route, conns: peerConns, peerId: peerId);
    }).toList();

    summaries.sort((a, b) {
      final ipCompare = _compareIp(a.primarySortIp, b.primarySortIp);
      if (ipCompare != 0) return ipCompare;
      return a.peerId.compareTo(b.peerId);
    });
    return summaries;
  }

  int _compareIp(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 0;
    if (a.isEmpty) return 1;
    if (b.isEmpty) return -1;

    final av4 = _parseIpv4(a);
    final bv4 = _parseIpv4(b);
    if (av4 != null && bv4 != null) return av4.compareTo(bv4);
    if (av4 != null) return -1;
    if (bv4 != null) return 1;
    return a.compareTo(b);
  }

  int? _parseIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    final values = parts.map(int.tryParse).toList();
    if (values.any((v) => v == null || v < 0 || v > 255)) return null;
    return (values[0]! << 24) |
        (values[1]! << 16) |
        (values[2]! << 8) |
        values[3]!;
  }
}

class _PeerSummary {
  const _PeerSummary({
    required this.route,
    required this.conns,
    required this.peerId,
  });

  final PeerRouteInfo? route;
  final List<PeerConnInfo> conns;
  final int peerId;

  String get hostname =>
      route?.hostname.isNotEmpty == true ? route!.hostname : '';

  String get clientVersion => route?.version ?? '';

  String get primaryIp => route?.ipv4Addr ?? '';

  String get primarySortIp => route?.ipv4Addr.isNotEmpty == true
      ? route!.ipv4Addr
      : route?.ipv6Addr ?? '';

  int get totalRx => conns.fold(0, (sum, conn) => sum + conn.rxBytes);

  int get totalTx => conns.fold(0, (sum, conn) => sum + conn.txBytes);

  List<String> get tunnelLabels =>
      conns.map((conn) => conn.tunnelLabel).toSet().toList()..sort();

  PeerConnInfo? get primaryConn =>
      conns.where((conn) => conn.isDefault).firstOrNull ??
      conns.where((conn) => !conn.isClosed).firstOrNull ??
      conns.firstOrNull;

  double displayLatency(bool latencyFirstEnabled) {
    if (route == null) return primaryConn?.latencyMs ?? 0;
    if (route!.isDirect) return primaryConn?.latencyMs ?? route!.latencyMs;
    final selected = route!.currentLatencyMs(latencyFirstEnabled);
    if (selected > 0) {
      return selected;
    }
    return route!.latencyMs;
  }

  double get displayLossRate => primaryConn?.lossRate ?? 0;

  String nextHopLabel(bool latencyFirstEnabled, Map<int, String> peerNames) {
    if (route == null) return '-';
    final nextHop = route!.currentNextHopPeerId(latencyFirstEnabled);
    if (nextHop <= 0 || route!.currentCost(latencyFirstEnabled) <= 1) {
      return '';
    }
    final name = peerNames[nextHop];
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return '$nextHop';
  }

  String? latencyFirstLabel(
    bool latencyFirstEnabled,
    Map<int, String> peerNames,
  ) {
    if (route == null || !route!.hasLatencyFirstRoute) return null;
    if (latencyFirstEnabled) return null;
    if (route!.nextHopPeerIdLatencyFirst <= 0) return null;
    if (route!.costLatencyFirst <= 1) return 'DIRECT';
    final name = peerNames[route!.nextHopPeerIdLatencyFirst];
    if (name != null && name.isNotEmpty) return name;
    return '${route!.nextHopPeerIdLatencyFirst}';
  }
}

class _PeerRow extends StatefulWidget {
  const _PeerRow({
    required this.summary,
    required this.latencyFirstEnabled,
    required this.peerNames,
  });
  final _PeerSummary summary;
  final bool latencyFirstEnabled;
  final Map<int, String> peerNames;

  @override
  State<_PeerRow> createState() => _PeerRowState();
}

class _PeerRowState extends State<_PeerRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final accent = s.route?.isDirect == true ? Colors.green : Colors.orange;
    final currentLatency = s.displayLatency(widget.latencyFirstEnabled);
    final currentHop = s.nextHopLabel(
      widget.latencyFirstEnabled,
      widget.peerNames,
    );

    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
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
                    color: withAlphaFactor(accent, 0.14),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    s.route?.isDirect == true
                        ? Icons.hub_outlined
                        : Icons.route_outlined,
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: s.hostname.isNotEmpty
                                        ? s.hostname
                                        : l10n.t('peer.peer', {
                                            'id': '${s.peerId}',
                                          }),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                  TextSpan(
                                    text: '  ${s.peerId}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w400,
                                      color: cs.outline,
                                    ),
                                  ),
                                  if (s.clientVersion.trim().isNotEmpty)
                                    TextSpan(
                                      text: '  ${s.clientVersion.trim()}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w400,
                                        color: cs.outline,
                                      ),
                                    ),
                                ],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  _LabelPill(
                                    text: s.route?.isDirect == true
                                        ? l10n.t('peer.p2p')
                                        : l10n.t('common.relay'),
                                    color: accent.shade700,
                                    background: withAlphaFactor(accent, 0.14),
                                  ),
                                  ...s.tunnelLabels.map(
                                    (label) => _LabelPill(
                                      text: label,
                                      color: cs.outline,
                                      background: cs.surfaceContainerHighest,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          if (s.primaryIp.isNotEmpty)
                            _MetaLine(
                              icon: Icons.lan_outlined,
                              text: s.primaryIp,
                              mono: true,
                            ),
                          _MetaLine(
                            icon: Icons.schedule_outlined,
                            text: currentLatency > 0
                                ? '${currentLatency.toStringAsFixed(1)} ms'
                                : '-',
                            color: _latencyColor(currentLatency),
                          ),
                          _MetaLine(
                            icon: Icons.water_drop_outlined,
                            text:
                                '${(s.displayLossRate * 100).toStringAsFixed(1)}%',
                            color: _lossColor(s.displayLossRate),
                          ),
                          _MetaLine(
                            icon: Icons.alt_route_outlined,
                            text: currentHop.isEmpty
                                ? l10n.t('common.direct')
                                : l10n.t('peer.peer', {'id': currentHop}),
                          ),
                          if (s.route != null)
                            _MetaLine(
                              icon: Icons.route_outlined,
                              text: l10n.t('peer.cost', {
                                'value':
                                    '${s.route!.currentCost(widget.latencyFirstEnabled)}',
                              }),
                            ),
                          _MetaLine(
                            icon: Icons.download_rounded,
                            text: _fmtBytes(s.totalRx),
                            color: cs.primary,
                          ),
                          _MetaLine(
                            icon: Icons.upload_rounded,
                            text: _fmtBytes(s.totalTx),
                            color: cs.tertiary,
                          ),
                          if (s.route?.udpNatType.isNotEmpty == true)
                            _MetaLine(
                              icon: Icons.swap_vert,
                              text: s.route!.udpNatType,
                            ),
                          if (s.route?.tcpNatType.isNotEmpty == true)
                            _MetaLine(
                              icon: Icons.sync_alt,
                              text: s.route!.tcpNatType,
                            ),
                        ],
                      ),
                      if (s.route?.proxyCidrs.isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: s.route!.proxyCidrs
                              .map(
                                (cidr) => _MetaLine(
                                  icon: Icons.account_tree_outlined,
                                  text: cidr,
                                  mono: true,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: cs.outline,
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 38, right: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (s.conns.isNotEmpty) ...[
                      ...s.conns.map((conn) => _ConnRow(conn: conn)),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConnRow extends StatelessWidget {
  const _ConnRow({required this.conn});
  final PeerConnInfo conn;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: withAlphaFactor(cs.outlineVariant, 0.16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    conn.connId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.outline,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _LabelPill(
                          text: conn.tunnelLabel,
                          color: cs.primary,
                          background: cs.primaryContainer,
                        ),
                        if (conn.isDefault)
                          _LabelPill(
                            text: l10n.t('peer.default'),
                            color: cs.tertiary,
                            background: cs.tertiaryContainer,
                          ),
                        if (conn.isClosed)
                          _LabelPill(
                            text: l10n.t('peer.closed'),
                            color: cs.error,
                            background: cs.errorContainer,
                          ),
                        if (conn.secureAuthLevel.isNotEmpty)
                          _LabelPill(
                            text: conn.secureAuthLevel,
                            color: cs.secondary,
                            background: cs.secondaryContainer,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                _MetaLine(
                  icon: Icons.download_rounded,
                  text: _fmtBytes(conn.rxBytes),
                  color: cs.primary,
                ),
                _MetaLine(
                  icon: Icons.upload_rounded,
                  text: _fmtBytes(conn.txBytes),
                  color: cs.tertiary,
                ),
                _MetaLine(
                  icon: Icons.schedule_outlined,
                  text: conn.latencyMs > 0
                      ? '${conn.latencyMs.toStringAsFixed(1)} ms'
                      : '-',
                  color: _latencyColor(conn.latencyMs),
                ),
                _MetaLine(
                  icon: Icons.water_drop_outlined,
                  text: '${(conn.lossRate * 100).toStringAsFixed(1)}%',
                  color: _lossColor(conn.lossRate),
                ),
                if (conn.peerIdentityType.isNotEmpty)
                  _MetaLine(
                    icon: Icons.verified_user_outlined,
                    text: conn.peerIdentityType,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            _AddressLine(icon: Icons.call_made_outlined, value: conn.localAddr),
            const SizedBox(height: 4),
            _AddressLine(
              icon: Icons.call_received_outlined,
              value: conn.remoteAddr,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressLine extends StatelessWidget {
  const _AddressLine({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 12, color: cs.outline),
        const SizedBox(width: 6),
        Expanded(
          child: InkWell(
            onTap: value.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          context.l10n.t('common.copied', {'value': value}),
                        ),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({
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
          constraints: const BoxConstraints(maxWidth: 220),
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

class _LabelPill extends StatelessWidget {
  const _LabelPill({
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

String _fmtBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

Color _latencyColor(double ms) {
  if (ms <= 0) return Colors.grey;
  if (ms < 30) return Colors.green;
  if (ms < 80) return Colors.lightGreen;
  if (ms < 150) return Colors.orange;
  return Colors.red;
}

Color _lossColor(double loss) {
  if (loss <= 0.01) return Colors.green;
  if (loss <= 0.05) return Colors.orange;
  return Colors.red;
}
