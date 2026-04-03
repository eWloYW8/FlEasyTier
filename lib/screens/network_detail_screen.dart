import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/network_config.dart';
import '../models/network_instance.dart';
import '../providers/app_state.dart';
import '../services/easytier_manager.dart';
import '../utils/color_compat.dart';
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
      return Center(child: Text(context.l10n.t('detail.config_not_found')));
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
                Text(
                  config.displayName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusBadge(running: running),
                    if (running && instance?.nodeInfo != null)
                      Text(
                        instance!.nodeInfo!.virtualIpv4,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: cs.outline),
                      ),
                    if (running && instance != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 14,
                            color: cs.outline,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${instance!.peerCount}',
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(color: cs.outline),
                          ),
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
                  tooltip: context.l10n.t('detail.edit'),
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
                      Align(alignment: Alignment.centerRight, child: actions),
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
        label: Text(
          serviceEnabled
              ? context.l10n.t('detail.stop_service')
              : context.l10n.t('common.stop'),
        ),
        style: FilledButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
        ),
        onPressed: onPressed,
      );
    }
    return FilledButton.icon(
      icon: const Icon(Icons.play_arrow_rounded, size: 20),
      label: Text(
        serviceEnabled
            ? context.l10n.t('detail.start_service')
            : context.l10n.t('common.start'),
      ),
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
          PopupMenuItem(
            value: 'edit',
            child: Text(context.l10n.t('common.edit')),
          ),
        PopupMenuItem(
          value: 'toml',
          child: Text(context.l10n.t('networks.edit_toml')),
        ),
        PopupMenuItem(
          value: 'duplicate',
          child: Text(context.l10n.t('common.duplicate')),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Text(context.l10n.t('common.delete')),
        ),
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
          TabBar(
            tabs: [
              Tab(text: context.l10n.t('detail.overview')),
              Tab(text: context.l10n.t('detail.peers')),
              Tab(text: context.l10n.t('detail.routes')),
              Tab(text: context.l10n.t('detail.logs')),
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
    final l10n = context.l10n;

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
                label: l10n.t('detail.virtual_ip'),
                value: node?.virtualIpv4 ?? l10n.t('detail.connecting'),
              ),
              StatCard(
                icon: Icons.people,
                label: l10n.t('detail.peers'),
                value: '${instance.peerCount}',
              ),
              StatCard(
                icon: Icons.alt_route,
                label: l10n.t('detail.routes'),
                value: '${instance.routes.length}',
              ),
              StatCard(
                icon: Icons.timer_outlined,
                label: l10n.t('detail.uptime'),
                value: _formatDuration(context, uptime),
              ),
              StatCard(
                icon: Icons.download,
                label: l10n.t('detail.rx'),
                value: _formatBytes(instance.totalRxBytes),
              ),
              StatCard(
                icon: Icons.upload,
                label: l10n.t('detail.tx'),
                value: _formatBytes(instance.totalTxBytes),
              ),
              StatCard(
                icon: Icons.forward,
                label: l10n.t('detail.forwarded'),
                value: _formatBytes(
                  instance.metricValue('traffic_bytes_forwarded'),
                ),
              ),
              StatCard(
                icon: Icons.compress,
                label: l10n.t('detail.compressed'),
                value: _formatBytes(
                  instance.metricValue('compression_bytes_tx_after'),
                ),
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
                    Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        instance.errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
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

  Widget _nodeInfoCard(BuildContext context, NodeInfo node) {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.t('detail.node_info'),
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _infoRow(l10n.t('detail.hostname'), node.hostname),
            _infoRow(l10n.t('detail.peer_id'), '${node.peerId}'),
            if (node.virtualIpv4Cidr.isNotEmpty)
              _infoRow(l10n.t('detail.ipv4_cidr'), node.virtualIpv4Cidr),
            _infoRow(l10n.t('detail.version'), node.version),
            if (node.instId.isNotEmpty)
              _infoRow(l10n.t('detail.inst_id'), node.instId),
            if (node.udpNatType.isNotEmpty)
              _infoRow(l10n.t('detail.udp_nat'), node.udpNatType),
            if (node.tcpNatType.isNotEmpty)
              _infoRow(l10n.t('detail.tcp_nat'), node.tcpNatType),
            if (node.publicIps.isNotEmpty)
              _infoRow(l10n.t('detail.public_ip'), node.publicIps.join(', ')),
            if (node.publicIpv6.isNotEmpty)
              _infoRow(l10n.t('detail.public_ipv6'), node.publicIpv6),
            if (node.interfaceIpv4s.isNotEmpty)
              _infoRow(
                l10n.t('detail.interface_ipv4'),
                node.interfaceIpv4s.join(', '),
              ),
            if (node.interfaceIpv6s.isNotEmpty)
              _infoRow(
                l10n.t('detail.interface_ipv6'),
                node.interfaceIpv6s.join(', '),
              ),
            if (node.listeners.isNotEmpty)
              _infoRow(l10n.t('detail.listeners'), node.listeners.join('\n')),
          ],
        ),
      ),
    );
  }

  Widget _trafficMetricsCard(BuildContext context, NetworkInstance instance) {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.t('detail.traffic_metrics'),
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metricBox(
                  context,
                  l10n.t('detail.data_tx'),
                  _formatBytes(instance.metricValue('traffic_bytes_tx')),
                  Icons.upload_rounded,
                ),
                _metricBox(
                  context,
                  l10n.t('detail.data_rx'),
                  _formatBytes(instance.metricValue('traffic_bytes_rx')),
                  Icons.download_rounded,
                ),
                _metricBox(
                  context,
                  l10n.t('detail.control_tx'),
                  _formatBytes(
                    instance.metricValue('traffic_control_bytes_tx'),
                  ),
                  Icons.settings_ethernet,
                ),
                _metricBox(
                  context,
                  l10n.t('detail.control_rx'),
                  _formatBytes(
                    instance.metricValue('traffic_control_bytes_rx'),
                  ),
                  Icons.call_received_rounded,
                ),
                _metricBox(
                  context,
                  l10n.t('detail.rpc_tx'),
                  '${instance.metricValue('peer_rpc_client_tx')}',
                  Icons.sync_alt_rounded,
                ),
                _metricBox(
                  context,
                  l10n.t('detail.rpc_rx'),
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
        border: Border.all(color: withAlphaFactor(cs.outlineVariant, 0.3)),
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
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: cs.outline,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
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
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontSize: 13)),
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
  final _filterController = TextEditingController();
  String _filter = '';
  bool _autoScroll = true;
  int _prevLogCount = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final config = state.configById(widget.configId);
    final allLogs = state.manager.getLogs(widget.configId, config: config);
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    final logs = _filter.isEmpty
        ? allLogs
        : allLogs
              .where(
                (l) =>
                    stripAnsi(l).toLowerCase().contains(_filter.toLowerCase()),
              )
              .toList();

    // Only scroll when new lines actually appeared, not on every rebuild.
    if (_autoScroll && logs.length > _prevLogCount && logs.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
    _prevLogCount = logs.length;

    return Column(
      children: [
        // Toolbar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _filterController,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    hintText: l10n.t('detail.filter_logs'),
                    prefixIcon: Icon(Icons.search, size: 18, color: cs.outline),
                    suffixIcon: _filter.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.close,
                              size: 16,
                              color: cs.outline,
                            ),
                            onPressed: () {
                              _filterController.clear();
                              setState(() => _filter = '');
                            },
                          )
                        : null,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (v) => setState(() => _filter = v),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  Icons.copy_all_outlined,
                  size: 20,
                  color: cs.outline,
                ),
                tooltip: context.l10n.t('common.copy'),
                onPressed: logs.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: logs.join('\n')),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.t('detail.logs_copied')),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
              ),
              IconButton(
                icon: Icon(
                  _autoScroll
                      ? Icons.vertical_align_bottom
                      : Icons.vertical_align_top,
                  size: 20,
                ),
                tooltip: _autoScroll
                    ? l10n.t('detail.auto_scroll_on')
                    : l10n.t('detail.auto_scroll_off'),
                onPressed: () => setState(() => _autoScroll = !_autoScroll),
                color: _autoScroll ? cs.primary : cs.outline,
              ),
              Text(
                '${logs.length}',
                style: TextStyle(fontSize: 11, color: cs.outline),
              ),
            ],
          ),
        ),
        // Log content
        Expanded(
          child: logs.isEmpty
              ? const SizedBox.shrink()
              : _LogListView(
                  controller: _scrollController,
                  logs: logs,
                  errorColor: cs.error,
                  defaultColor: cs.onSurfaceVariant,
                ),
        ),
      ],
    );
  }
}

/// Extracted log list so Flutter can skip rebuilding it when only
/// toolbar state (filter text, auto-scroll) changes and the log
/// content is identical.
class _LogListView extends StatelessWidget {
  const _LogListView({
    required this.controller,
    required this.logs,
    required this.errorColor,
    required this.defaultColor,
  });

  final ScrollController controller;
  final List<String> logs;
  final Color errorColor;
  final Color defaultColor;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      itemCount: logs.length,
      itemBuilder: (_, i) => _LogLine(
        key: ValueKey(i),
        line: logs[i],
        errorColor: errorColor,
        defaultColor: defaultColor,
      ),
    );
  }
}

/// A single log line that only rebuilds when its [line] content changes.
class _LogLine extends StatelessWidget {
  const _LogLine({
    super.key,
    required this.line,
    required this.errorColor,
    required this.defaultColor,
  });

  final String line;
  final Color errorColor;
  final Color defaultColor;

  @override
  Widget build(BuildContext context) {
    final isErr = line.startsWith('[ERR]');
    final spans = parseAnsi(
      line,
      defaultColor: isErr ? errorColor : defaultColor,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 0.5),
      child: Text.rich(
        TextSpan(children: spans),
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 11.5,
          height: 1.45,
        ),
      ),
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
    final l10n = context.l10n;
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
                      context.l10n.t('detail.last_start_error'),
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
                  Text(
                    l10n.t('detail.configuration_summary'),
                    style: ts.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Divider(height: 24),
                  _row(cs, l10n.t('detail.network'), config.networkName),
                  _row(
                    cs,
                    context.l10n.t('detail.secret'),
                    config.networkSecret.isNotEmpty ? '\u2022' * 8 : '-',
                  ),
                  _row(
                    cs,
                    l10n.t('detail.ipv4'),
                    config.virtualIpv4.isNotEmpty
                        ? config.virtualIpv4
                        : (config.dhcp ? l10n.t('tile.dhcp') : '-'),
                  ),
                  if (config.virtualIpv6.isNotEmpty)
                    _row(cs, l10n.t('detail.ipv6'), config.virtualIpv6),
                  _row(
                    cs,
                    l10n.t('detail.hostname'),
                    config.hostname.isNotEmpty ? config.hostname : '-',
                  ),
                  if (config.instanceName.isNotEmpty)
                    _row(cs, l10n.t('detail.instance'), config.instanceName),
                  _row(
                    cs,
                    l10n.t('detail.peers'),
                    l10n.t('detail.configured_count', {
                      'count': '${config.peerUrls.length}',
                    }),
                  ),
                  _row(
                    cs,
                    l10n.t('detail.listeners'),
                    config.noListener
                        ? l10n.t('detail.disabled')
                        : l10n.t('detail.configured_count', {
                            'count': '${config.listeners.length}',
                          }),
                  ),
                  if (config.mappedListeners.isNotEmpty)
                    _row(
                      cs,
                      l10n.t('detail.mapped'),
                      '${config.mappedListeners.length}',
                    ),
                  _row(cs, l10n.t('detail.rpc_port'), '${config.rpcPort}'),
                  if (config.proxyCidrs.isNotEmpty)
                    _row(
                      cs,
                      l10n.t('detail.proxy_cidrs'),
                      config.proxyCidrs.join(', '),
                    ),
                  if (config.exitNodes.isNotEmpty)
                    _row(
                      cs,
                      l10n.t('detail.exit_nodes'),
                      config.exitNodes.join(', '),
                    ),
                  if (config.manualRoutes.isNotEmpty)
                    _row(
                      cs,
                      l10n.t('detail.routes'),
                      '${config.manualRoutes.length}',
                    ),
                  if (config.portForwards.isNotEmpty)
                    _row(
                      cs,
                      l10n.t('detail.port_forward'),
                      l10n.t('detail.rule_count', {
                        'count': '${config.portForwards.length}',
                      }),
                    ),
                  if (config.vpnPortal.isNotEmpty)
                    _row(cs, l10n.t('detail.wg_portal'), config.vpnPortal),
                  if (config.compression.isNotEmpty)
                    _row(cs, l10n.t('detail.compression'), config.compression),
                  if (_supportsSystemService) ...[
                    const SizedBox(height: 16),
                    _ServiceSection(config: config),
                  ],
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (config.dhcp) _chip(cs, l10n.t('tile.dhcp')),
                      if (config.enableKcpProxy) _chip(cs, 'KCP'),
                      if (config.enableQuicProxy) _chip(cs, 'QUIC'),
                      if (!config.disableIpv6) _chip(cs, l10n.t('detail.ipv6')),
                      if (config.latencyFirst)
                        _chip(cs, l10n.t('detail.latency_first')),
                      if (config.enableExitNode)
                        _chip(cs, l10n.t('detail.exit_node')),
                      if (config.acceptDns) _chip(cs, l10n.t('tile.dns')),
                      if (config.enableSocks5)
                        _chip(cs, 'SOCKS5:${config.socks5Port}'),
                      if (config.multiThread)
                        _chip(cs, l10n.t('detail.multi_thread')),
                      if (config.secureMode)
                        _chip(cs, l10n.t('edit.secure_mode')),
                      if (config.privateMode)
                        _chip(cs, l10n.t('detail.private')),
                      if (config.p2pOnly) _chip(cs, l10n.t('detail.p2p_only')),
                      if (config.noTun) _chip(cs, l10n.t('tile.no_tun')),
                      if (config.useSmoltcp) _chip(cs, 'smoltcp'),
                      if (config.proxyForwardBySystem)
                        _chip(cs, l10n.t('detail.sys_proxy')),
                      if (config.autoStart)
                        _chip(cs, l10n.t('edit.auto_start')),
                      if (config.serviceEnabled)
                        _chip(cs, l10n.t('tile.service')),
                      if (config.disableEncryption)
                        _chip(cs, l10n.t('detail.no_encryption'), warn: true),
                      if (config.disableP2p)
                        _chip(cs, l10n.t('detail.no_p2p'), warn: true),
                      if (config.noListener)
                        _chip(cs, l10n.t('detail.no_listener'), warn: true),
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
                        Text(
                          l10n.t('detail.recent_instance_logs'),
                          style: ts.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
                          final spans = parseAnsi(
                            line,
                            defaultColor: isErr
                                ? cs.error
                                : cs.onSurfaceVariant,
                          );
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
            child: Text(
              label,
              style: TextStyle(
                color: cs.outline,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _chip(ColorScheme cs, String label, {bool warn = false}) {
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      backgroundColor: warn ? cs.errorContainer : cs.secondaryContainer,
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
          ManagedServiceStatus.running => context.l10n.t(
            'detail.service_running',
          ),
          ManagedServiceStatus.stopped => context.l10n.t(
            'detail.service_installed',
          ),
          ManagedServiceStatus.notInstalled => context.l10n.t(
            'detail.service_not_installed',
          ),
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.t('detail.system_service'),
              style: ts.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.t('detail.service_manage_help'),
              style: ts.bodySmall?.copyWith(color: cs.outline),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
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
                  label: Text(
                    widget.config.serviceEnabled
                        ? context.l10n.t('detail.update_service')
                        : context.l10n.t('detail.install_service'),
                  ),
                  onPressed: () async {
                    final msg = await context.read<AppState>().installService(
                      widget.config.id,
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(msg),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    await _refresh();
                  },
                ),
                if (widget.config.serviceEnabled)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(context.l10n.t('detail.uninstall')),
                    onPressed: () async {
                      final msg = await context
                          .read<AppState>()
                          .uninstallService(widget.config.id);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(msg),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
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
                      status == ManagedServiceStatus.running
                          ? context.l10n.t('common.stop')
                          : context.l10n.t('common.start'),
                    ),
                    onPressed: () async {
                      final state = context.read<AppState>();
                      String msg;
                      if (status == ManagedServiceStatus.running) {
                        await state.stopInstance(widget.config.id);
                        msg = context.l10n.t('detail.stop_service');
                      } else {
                        msg =
                            await state.startInstance(widget.config.id) ??
                            context.l10n.t('detail.start_service');
                      }
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(msg),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
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
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider.value(
        value: state,
        child: ConfigEditScreen(config: config, isNew: false),
      ),
    ),
  );
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
            Text(context.l10n.t('detail.toml_config')),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: context.l10n.t('detail.copy_clipboard'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: ctrl.text));
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(context.l10n.t('detail.toml_copied')),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
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
              Text(
                context.l10n.t('detail.file', {'path': tomlPath}),
                style: TextStyle(fontSize: 11, color: cs.outline),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: ctrl,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
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
            child: Text(context.l10n.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () async {
              final err = await state.updateConfigToml(config.id, ctrl.text);
              if (err != null) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(err),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    context.l10n.t('detail.saved_to', {'path': tomlPath}),
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: Text(context.l10n.t('detail.save_to_file')),
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
      title: Text(context.l10n.t('detail.delete_network')),
      content: Text(
        context.l10n.t('detail.delete_network_confirm', {
          'name': config.displayName,
        }),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(context.l10n.t('common.cancel')),
        ),
        FilledButton(
          onPressed: () {
            state.removeConfig(config.id);
            Navigator.pop(ctx);
          },
          child: Text(context.l10n.t('common.delete')),
        ),
      ],
    ),
  );
}

// ── Format helpers ──

String _formatDuration(BuildContext context, Duration? d) {
  if (d == null) return '-';
  final l10n = context.l10n;
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) {
    return l10n.t('detail.duration_hm', {'hours': '$h', 'minutes': '$m'});
  }
  if (m > 0) {
    return l10n.t('detail.duration_ms', {'minutes': '$m', 'seconds': '$s'});
  }
  return l10n.t('detail.duration_s', {'seconds': '$s'});
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
