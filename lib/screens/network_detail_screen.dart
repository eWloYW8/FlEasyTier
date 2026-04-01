import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/network_config.dart';
import '../models/network_instance.dart';
import '../providers/app_state.dart';
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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            // Icon
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
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(config.displayName,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      StatusBadge(running: running),
                      if (running && instance?.nodeInfo != null) ...[
                        const SizedBox(width: 8),
                        Text(instance!.nodeInfo!.virtualIpv4,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: cs.outline)),
                      ],
                      if (running && instance != null) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.people_outline,
                            size: 14, color: cs.outline),
                        const SizedBox(width: 2),
                        Text('${instance!.peerCount}',
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
            // Actions
            if (!running)
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit',
                onPressed: () => _editConfig(context, config),
              ),
            const SizedBox(width: 4),
            _StartStopButton(
              running: running,
              onPressed: () => state.toggleInstance(config.id),
            ),
            const SizedBox(width: 4),
            _MoreMenu(config: config, running: running),
          ],
        ),
      ),
    );
  }
}

class _StartStopButton extends StatelessWidget {
  const _StartStopButton({required this.running, required this.onPressed});
  final bool running;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (running) {
      return FilledButton.tonalIcon(
        icon: const Icon(Icons.stop_rounded, size: 20),
        label: const Text('Stop'),
        style: FilledButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
        ),
        onPressed: onPressed,
      );
    }
    return FilledButton.icon(
      icon: const Icon(Icons.play_arrow_rounded, size: 20),
      label: const Text('Start'),
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
            final json = config.copyWith(
              configName: '${config.displayName} (copy)',
            ).toJson();
            json.remove('id'); // force new UUID
            state.addConfig(NetworkConfig.fromJson(json));
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
                ),
                RouteListView(routes: instance.routes),
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
            spacing: 12,
            runSpacing: 12,
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
            ],
          ),
          const SizedBox(height: 20),
          // Node info card
          if (node != null) _nodeInfoCard(context, node),
          // Error
          if (instance.errorMessage != null) ...[
            const SizedBox(height: 12),
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
            _infoRow('Version', node.version),
            if (node.udpNatType.isNotEmpty)
              _infoRow('UDP NAT', node.udpNatType),
            if (node.tcpNatType.isNotEmpty)
              _infoRow('TCP NAT', node.tcpNatType),
            if (node.publicIps.isNotEmpty)
              _infoRow('Public IP', node.publicIps.join(', ')),
            if (node.listeners.isNotEmpty)
              _infoRow('Listeners', node.listeners.join('\n')),
          ],
        ),
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
    final allLogs = state.manager.getLogs(widget.configId);
    final cs = Theme.of(context).colorScheme;

    final logs = _filter.isEmpty
        ? allLogs
        : allLogs
            .where(
                (l) => l.toLowerCase().contains(_filter.toLowerCase()))
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
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Filter logs...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                  ),
                  style: const TextStyle(fontSize: 12),
                  onChanged: (v) => setState(() => _filter = v),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  _autoScroll
                      ? Icons.vertical_align_bottom
                      : Icons.vertical_align_top,
                  size: 20,
                ),
                tooltip:
                    _autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF',
                onPressed: () =>
                    setState(() => _autoScroll = !_autoScroll),
                color: _autoScroll ? cs.primary : cs.outline,
              ),
              Text('${logs.length}',
                  style: TextStyle(fontSize: 11, color: cs.outline)),
            ],
          ),
        ),
        // Log content
        Expanded(
          child: logs.isEmpty
              ? Center(
                  child: Text('No logs',
                      style: TextStyle(color: cs.outline)))
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: logs.length,
                  itemBuilder: (_, i) {
                    final line = logs[i];
                    final isErr = line.startsWith('[ERR]');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 1),
                      child: SelectableText(
                        line,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: isErr ? cs.error : cs.onSurface,
                          height: 1.4,
                        ),
                      ),
                    );
                  },
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
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
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
              const SizedBox(height: 4),
              // Feature chips
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
                  if (config.enableMagicDns) _chip(cs, 'Magic DNS'),
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
                  if (config.disableEncryption)
                    _chip(cs, 'No Encryption', warn: true),
                  if (config.disableP2p) _chip(cs, 'No P2P', warn: true),
                  if (config.noListener) _chip(cs, 'No Listener', warn: true),
                ],
              ),
            ],
          ),
        ),
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
              // Save TOML to file directly
              await File(tomlPath).writeAsString(ctrl.text);
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
