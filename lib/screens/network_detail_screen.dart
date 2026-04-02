import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/network_config.dart';
import '../models/network_instance.dart';
import '../providers/app_state.dart';
import '../services/easytier_manager.dart';
import '../widgets/ansi_text.dart';
import '../widgets/peer_list_view.dart';
import '../widgets/route_list_view.dart';
import '../widgets/stat_card.dart';
import '../widgets/status_badge.dart';
import 'config_edit_screen.dart';

class NetworkDetailScreen extends StatelessWidget {
  const NetworkDetailScreen({super.key, required this.configId});
  final String configId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final config = state.configById(configId);
    if (config == null) {
      return const Center(child: Text('Config not found'));
    }

    final running = state.isRunning(configId);
    final instance = state.instanceFor(configId);

    return Column(
      children: [
        _HeaderCard(config: config, running: running, instance: instance),
        Expanded(
          child: running && instance != null
              ? _RunningView(config: config, instance: instance)
              : _StoppedView(config: config),
        ),
      ],
    );
  }
}

// ── Header card ──

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.config,
    required this.running,
    this.instance,
  });
  final NetworkConfig config;
  final bool running;
  final NetworkInstance? instance;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final state = context.read<AppState>();

    return Card(
      margin: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final headerInfo = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(config.displayName,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusBadge(running: running),
                    if (running && instance?.nodeInfo != null)
                      Text(instance!.nodeInfo!.virtualIpv4,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.outline)),
                    if (running && instance != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.people_outline, size: 14, color: cs.outline),
                          const SizedBox(width: 2),
                          Text('${instance!.peerCount}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: cs.outline)),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          );

          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!running)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit',
                  onPressed: () => _editConfig(context, config),
                ),
              if (!running) const SizedBox(width: 4),
              _StartStopButton(
                running: running,
                serviceEnabled: config.serviceEnabled,
                onPressed: () => state.toggleInstance(config.id),
              ),
              const SizedBox(width: 4),
              _MoreMenu(config: config, running: running),
            ],
          );

          return Padding(
            padding: const EdgeInsets.all(20),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: running
                                  ? cs.primaryContainer
                                  : cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              running ? Icons.lan : Icons.lan_outlined,
                              color: running ? cs.primary : cs.outline,
                            ),
                          ),
                          const SizedBox(width: 16),
                          headerInfo,
                        ],
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: actions,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: running
                              ? cs.primaryContainer
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          running ? Icons.lan : Icons.lan_outlined,
                          color: running ? cs.primary : cs.outline,
                        ),
                      ),
                      const SizedBox(width: 16),
                      headerInfo,
                      const SizedBox(width: 8),
                      actions,
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _StartStopButton extends StatelessWidget {
  const _StartStopButton({
    required this.running,
    required this.serviceEnabled,
    required this.onPressed,
  });
  final bool running;
  final bool serviceEnabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (running) {
      return FilledButton.tonalIcon(
        icon: const Icon(Icons.stop_rounded, size: 20),
        label: Text(serviceEnabled ? 'Stop Service' : 'Stop'),
        style: FilledButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
        ),
        onPressed: onPressed,
      );
    }
    return FilledButton.icon(
      icon: const Icon(Icons.play_arrow_rounded, size: 20),
      label: Text(serviceEnabled ? 'Start Service' : 'Start'),
      onPressed: onPressed,
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.config, required this.running});
  final NetworkConfig config;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (v) {
        switch (v) {
          case 'edit':
            _editConfig(context, config);
          case 'duplicate':
            final json = config.toJson();
            json.remove('id'); // force new UUID
            json['auto_start'] = false;
            json['service_enabled'] = false;
            final duplicated = NetworkConfig.fromJson(json);
            duplicated.instanceName = config.instanceName.isNotEmpty
                ? '${config.instanceName}-copy'
                : '${config.displayName}-copy';
            state.addConfig(duplicated);
          case 'toml':
            _showTomlEditor(context, config);
          case 'delete':
            _confirmDelete(context, config);
        }
      },
      itemBuilder: (_) => [
        if (!running)
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
        const PopupMenuItem(value: 'toml', child: Text('Edit TOML')),
        const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }
}

// ── Running view with tabs ──

class _RunningView extends StatelessWidget {
  const _RunningView({required this.config, required this.instance});
  final NetworkConfig config;
  final NetworkInstance instance;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Peers'),
              Tab(text: 'Routes'),
              Tab(text: 'Logs'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _OverviewTab(config: config, instance: instance),
                PeerListView(
                  conns: instance.peerConns,
                  routes: instance.routes,
                  latencyFirstEnabled: config.latencyFirst,
                ),
                RouteListView(
                  routes: instance.routes,
                  latencyFirstEnabled: config.latencyFirst,
                ),
                _LogsTab(configId: config.id),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Overview tab ──

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.config, required this.instance});
  final NetworkConfig config;
  final NetworkInstance instance;

  @override
  Widget build(BuildContext context) {
    final node = instance.nodeInfo;
    final uptime = instance.uptime;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Stats row
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatCard(
                icon: Icons.router,
                label: 'Virtual IP',
                value: node?.virtualIpv4 ?? 'Connecting...',
              ),
              StatCard(
                icon: Icons.people,
                label: 'Peers',
                value: '${instance.peerCount}',
              ),
              StatCard(
                icon: Icons.alt_route,
                label: 'Routes',
                value: '${instance.routes.length}',
              ),
              StatCard(
                icon: Icons.timer_outlined,
                label: 'Uptime',
                value: _formatDuration(uptime),
              ),
              StatCard(
                icon: Icons.download,
                label: 'RX',
                value: _formatBytes(instance.totalRxBytes),
              ),
              StatCard(
                icon: Icons.upload,
                label: 'TX',
                value: _formatBytes(instance.totalTxBytes),
              ),
              StatCard(
                icon: Icons.forward,
                label: 'Forwarded',
                value: _formatBytes(instance.metricValue('traffic_bytes_forwarded')),
              ),
              StatCard(
                icon: Icons.compress,
                label: 'Compressed',
                value: _formatBytes(instance.metricValue('compression_bytes_tx_after')),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Node info card
          if (node != null) _nodeInfoCard(context, node),
          if (instance.metrics.isNotEmpty) ...[
            const SizedBox(height: 10),
            _trafficMetricsCard(context, instance),
          ],
          // Error
          if (instance.errorMessage != null) ...[
            const SizedBox(height: 10),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color:
                            Theme.of(context).colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(instance.errorMessage!,
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _nodeInfoCard(BuildContext context, NodeInfo node) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Node Info',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _infoRow('Hostname', node.hostname),
            _infoRow('Peer ID', '${node.peerId}'),
            if (node.virtualIpv4Cidr.isNotEmpty)
              _infoRow('IPv4 CIDR', node.virtualIpv4Cidr),
            _infoRow('Version', node.version),
            if (node.instId.isNotEmpty) _infoRow('Inst ID', node.instId),
            if (node.udpNatType.isNotEmpty)
              _infoRow('UDP NAT', node.udpNatType),
            if (node.tcpNatType.isNotEmpty)
              _infoRow('TCP NAT', node.tcpNatType),
            if (node.publicIps.isNotEmpty)
              _infoRow('Public IP', node.publicIps.join(', ')),
            if (node.publicIpv6.isNotEmpty)
              _infoRow('Public IPv6', node.publicIpv6),
            if (node.interfaceIpv4s.isNotEmpty)
              _infoRow('Interface IPv4', node.interfaceIpv4s.join(', ')),
            if (node.interfaceIpv6s.isNotEmpty)
              _infoRow('Interface IPv6', node.interfaceIpv6s.join(', ')),
            if (node.listeners.isNotEmpty)
              _infoRow('Listeners', node.listeners.join('\n')),
          ],
        ),
      ),
    );
  }

  Widget _trafficMetricsCard(BuildContext context, NetworkInstance instance) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Traffic Metrics',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metricBox(
                  context,
                  'Data TX',
                  _formatBytes(instance.metricValue('traffic_bytes_tx')),
                  Icons.upload_rounded,
                ),
                _metricBox(
                  context,
                  'Data RX',
                  _formatBytes(instance.metricValue('traffic_bytes_rx')),
                  Icons.download_rounded,
                ),
                _metricBox(
                  context,
                  'Control TX',
                  _formatBytes(instance.metricValue('traffic_control_bytes_tx')),
                  Icons.settings_ethernet,
                ),
                _metricBox(
                  context,
                  'Control RX',
                  _formatBytes(instance.metricValue('traffic_control_bytes_rx')),
                  Icons.call_received_rounded,
                ),
                _metricBox(
                  context,
                  'RPC TX',
                  '${instance.metricValue('peer_rpc_client_tx')}',
                  Icons.sync_alt_rounded,
                ),
                _metricBox(
                  context,
                  'RPC RX',
                  '${instance.metricValue('peer_rpc_client_rx')}',
                  Icons.compare_arrows_rounded,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricBox(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 132,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: cs.onSecondaryContainer),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: cs.outline,
                      fontWeight: FontWeight.w500,
                    )),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w500, fontSize: 13)),
          ),
          Expanded(
            child: SelectableText(value,
                style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _LogsTab extends StatefulWidget {
  const _LogsTab({required this.configId});
  final String configId;

  @override
  State<_LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<_LogsTab> {
  final _scrollController = ScrollController();
  String _filter = '';
  bool _autoScroll = true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final config = state.configById(widget.configId);
    final allLogs = state.manager.getLogs(widget.configId, config: config);
    final cs = Theme.of(context).colorScheme;

    final logs = _filter.isEmpty
        ? allLogs
        : allLogs
            .where((l) =>
                stripAnsi(l).toLowerCase().contains(_filter.toLowerCase()))
            .toList();

    // Auto-scroll after frame
    if (_autoScroll && logs.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController
              .jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }

    return Column(
      children: [
        // Toolbar
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            border: Border(
              bottom: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.4)),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: Row(
            children: [
              Icon(Icons.terminal, size: 14, color: cs.outline),
              const SizedBox(width: 6),
              Text('Terminal',
                  style: TextStyle(
                      fontSize: 11,
                      color: cs.outline,
                      fontFamily: 'monospace')),
              const Spacer(),
              SizedBox(
                width: 200,
                height: 28,
                child: TextField(
                  style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface,
                      fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: 'Filter...',
                    hintStyle: TextStyle(color: cs.outline, fontSize: 11),
                    prefixIcon:
                        Icon(Icons.search, size: 14, color: cs.outline),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 28, minHeight: 0),
                    filled: true,
                    fillColor: cs.surfaceContainerLowest,
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: cs.outline),
                    ),
                  ),
                  onChanged: (v) => setState(() => _filter = v),
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message:
                    _autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF',
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => setState(() => _autoScroll = !_autoScroll),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      _autoScroll
                          ? Icons.vertical_align_bottom
                          : Icons.vertical_align_top,
                      size: 16,
                      color: _autoScroll ? cs.primary : cs.outline,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text('${logs.length}',
                  style: TextStyle(
                      fontSize: 10,
                      color: cs.outline,
                      fontFamily: 'monospace')),
            ],
          ),
        ),
        // Log content
        Expanded(
          child: Container(
            color: cs.surfaceContainerLowest,
            child: logs.isEmpty
                ? const SizedBox.shrink()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    itemCount: logs.length,
                    itemBuilder: (_, i) {
                      final line = logs[i];
                      final isErr = line.startsWith('[ERR]');
                      final spans = parseAnsi(
                        line,
                        defaultColor:
                            isErr ? cs.error : cs.onSurfaceVariant,
                      );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 0.5),
                        child: SelectableText.rich(
                          TextSpan(children: spans),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            height: 1.45,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

// ── Stopped view ──

class _StoppedView extends StatelessWidget {
  const _StoppedView({required this.config});
  final NetworkConfig config;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    final instance = state.instanceFor(config.id);
    final recentLogs = state.manager.getLogs(config.id, config: config);
    final recentTail = recentLogs.length > 10
        ? recentLogs.sublist(recentLogs.length - 10)
        : recentLogs;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (instance?.errorMessage != null)
            Card(
              color: cs.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last Start Error',
                      style: ts.titleSmall?.copyWith(
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      instance!.errorMessage!,
                      style: TextStyle(color: cs.onErrorContainer),
                    ),
                  ],
                ),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Configuration',
                      style:
                          ts.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const Divider(height: 24),
                  _row(cs, 'Network', config.networkName),
                  _row(cs, 'Secret',
                      config.networkSecret.isNotEmpty ? '\u2022' * 8 : '-'),
                  _row(
                      cs,
                      'IPv4',
                      config.virtualIpv4.isNotEmpty
                          ? config.virtualIpv4
                          : (config.dhcp ? 'DHCP' : '-')),
                  if (config.virtualIpv6.isNotEmpty)
                    _row(cs, 'IPv6', config.virtualIpv6),
                  _row(cs, 'Hostname',
                      config.hostname.isNotEmpty ? config.hostname : '-'),
                  if (config.instanceName.isNotEmpty)
                    _row(cs, 'Instance', config.instanceName),
                  _row(cs, 'Peers', '${config.peerUrls.length} configured'),
                  _row(
                      cs,
                      'Listeners',
                      config.noListener
                          ? 'Disabled'
                          : '${config.listeners.length} configured'),
                  if (config.mappedListeners.isNotEmpty)
                    _row(cs, 'Mapped', '${config.mappedListeners.length}'),
                  _row(cs, 'RPC Port', '${config.rpcPort}'),
                  if (config.proxyCidrs.isNotEmpty)
                    _row(cs, 'Proxy CIDRs', config.proxyCidrs.join(', ')),
                  if (config.exitNodes.isNotEmpty)
                    _row(cs, 'Exit Nodes', config.exitNodes.join(', ')),
                  if (config.manualRoutes.isNotEmpty)
                    _row(cs, 'Routes', '${config.manualRoutes.length}'),
                  if (config.portForwards.isNotEmpty)
                    _row(cs, 'Port Fwd', '${config.portForwards.length} rules'),
                  if (config.vpnPortal.isNotEmpty)
                    _row(cs, 'WG Portal', config.vpnPortal),
                  if (config.compression.isNotEmpty)
                    _row(cs, 'Compression', config.compression),
                  if (_supportsSystemService)
                    ...[
                      const SizedBox(height: 16),
                      _ServiceSection(config: config),
                    ],
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (config.dhcp) _chip(cs, 'DHCP'),
                      if (config.enableKcpProxy) _chip(cs, 'KCP'),
                      if (config.enableQuicProxy) _chip(cs, 'QUIC'),
                      if (!config.disableIpv6) _chip(cs, 'IPv6'),
                      if (config.latencyFirst) _chip(cs, 'Latency First'),
                      if (config.enableExitNode) _chip(cs, 'Exit Node'),
                      if (config.acceptDns) _chip(cs, 'DNS'),
                      if (config.enableSocks5)
                        _chip(cs, 'SOCKS5:${config.socks5Port}'),
                      if (config.multiThread) _chip(cs, 'Multi-Thread'),
                      if (config.secureMode) _chip(cs, 'Secure Mode'),
                      if (config.privateMode) _chip(cs, 'Private'),
                      if (config.p2pOnly) _chip(cs, 'P2P Only'),
                      if (config.noTun) _chip(cs, 'No TUN'),
                      if (config.useSmoltcp) _chip(cs, 'smoltcp'),
                      if (config.proxyForwardBySystem) _chip(cs, 'Sys Proxy'),
                      if (config.autoStart) _chip(cs, 'Auto-start'),
                      if (config.serviceEnabled) _chip(cs, 'Service'),
                      if (config.disableEncryption)
                        _chip(cs, 'No Encryption', warn: true),
                      if (config.disableP2p) _chip(cs, 'No P2P', warn: true),
                      if (config.noListener)
                        _chip(cs, 'No Listener', warn: true),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (recentLogs.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.terminal, size: 14, color: cs.outline),
                        const SizedBox(width: 6),
                        Text('Recent Instance Logs',
                            style: ts.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: recentTail.map((line) {
                          final isErr = line.startsWith('[ERR]');
                          final spans = parseAnsi(line,
                              defaultColor: isErr
                                  ? cs.error
                                  : cs.onSurfaceVariant);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: SelectableText.rich(
                              TextSpan(children: spans),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11.5,
                                height: 1.45,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(ColorScheme cs, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: TextStyle(
                    color: cs.outline,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _chip(ColorScheme cs, String label, {bool warn = false}) {
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      backgroundColor:
          warn ? cs.errorContainer : cs.secondaryContainer,
      side: BorderSide.none,
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
    );
  }
}

class _ServiceSection extends StatefulWidget {
  const _ServiceSection({required this.config});
  final NetworkConfig config;

  @override
  State<_ServiceSection> createState() => _ServiceSectionState();
}

class _ServiceSectionState extends State<_ServiceSection> {
  late Future<ManagedServiceStatus> _statusFuture;

  @override
  void initState() {
    super.initState();
    _statusFuture = _loadStatus();
  }

  @override
  void didUpdateWidget(_ServiceSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.id != widget.config.id ||
        oldWidget.config.serviceEnabled != widget.config.serviceEnabled) {
      _statusFuture = _loadStatus();
    }
  }

  Future<ManagedServiceStatus> _loadStatus() {
    return context.read<AppState>().serviceStatus(widget.config.id);
  }

  Future<void> _refresh() async {
    setState(() {
      _statusFuture = _loadStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;

    return FutureBuilder<ManagedServiceStatus>(
      future: _statusFuture,
      builder: (context, snapshot) {
        final status = snapshot.data ?? ManagedServiceStatus.notInstalled;
        final statusText = switch (status) {
          ManagedServiceStatus.running => 'Running',
          ManagedServiceStatus.stopped => 'Installed',
          ManagedServiceStatus.notInstalled => 'Not installed',
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('System Service',
                style:
                    ts.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'Manage a boot-time service for this network only.',
              style: ts.bodySmall?.copyWith(color: cs.outline),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: status == ManagedServiceStatus.running
                        ? cs.primaryContainer
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 12,
                      color: status == ManagedServiceStatus.running
                          ? cs.onPrimaryContainer
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.build_circle_outlined, size: 18),
                  label: Text(widget.config.serviceEnabled
                      ? 'Update Service'
                      : 'Install Service'),
                  onPressed: () async {
                    final msg = await context
                        .read<AppState>()
                        .installService(widget.config.id);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(msg),
                      behavior: SnackBarBehavior.floating,
                    ));
                    await _refresh();
                  },
                ),
                if (widget.config.serviceEnabled)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Uninstall'),
                    onPressed: () async {
                      final msg = await context
                          .read<AppState>()
                          .uninstallService(widget.config.id);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(msg),
                        behavior: SnackBarBehavior.floating,
                      ));
                      await _refresh();
                    },
                  ),
                if (status != ManagedServiceStatus.notInstalled)
                  OutlinedButton.icon(
                    icon: Icon(
                      status == ManagedServiceStatus.running
                          ? Icons.stop_circle_outlined
                          : Icons.play_circle_outline,
                      size: 18,
                    ),
                    label: Text(
                      status == ManagedServiceStatus.running ? 'Stop' : 'Start',
                    ),
                    onPressed: () async {
                      final state = context.read<AppState>();
                      String msg;
                      if (status == ManagedServiceStatus.running) {
                        await state.stopInstance(widget.config.id);
                        msg = 'Service stopped';
                      } else {
                        msg = await state.startInstance(widget.config.id) ??
                            'Service started';
                      }
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(msg),
                        behavior: SnackBarBehavior.floating,
                      ));
                      await _refresh();
                    },
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ── Navigation helpers ──

void _editConfig(BuildContext context, NetworkConfig config) {
  final state = context.read<AppState>();
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ChangeNotifierProvider.value(
      value: state,
      child: ConfigEditScreen(config: config, isNew: false),
    ),
  ));
}

void _showTomlEditor(BuildContext context, NetworkConfig config) {
  final state = context.read<AppState>();
  final ctrl = TextEditingController(text: config.toToml());
  final tomlPath = state.manager.tomlPathFor(config.id);

  showDialog(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Row(
          children: [
            const Text('TOML Configuration'),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'Copy to clipboard',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: ctrl.text));
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                  content: Text('TOML copied'),
                  behavior: SnackBarBehavior.floating,
                ));
              },
            ),
          ],
        ),
        content: SizedBox(
          width: 600,
          height: 500,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('File: $tomlPath',
                  style: TextStyle(fontSize: 11, color: cs.outline)),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: ctrl,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                  ),
                  textAlignVertical: TextAlignVertical.top,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final err = await state.updateConfigToml(config.id, ctrl.text);
              if (err != null) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  content: Text(err),
                  behavior: SnackBarBehavior.floating,
                ));
                return;
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Saved to $tomlPath'),
                behavior: SnackBarBehavior.floating,
              ));
            },
            child: const Text('Save to file'),
          ),
        ],
      );
    },
  );
}

void _confirmDelete(BuildContext context, NetworkConfig config) {
  final state = context.read<AppState>();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete network?'),
      content:
          Text('Remove "${config.displayName}"? This cannot be undone.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            state.removeConfig(config.id);
            Navigator.pop(ctx);
          },
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}

// ── Format helpers ──

String _formatDuration(Duration? d) {
  if (d == null) return '-';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

bool get _supportsSystemService =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;
