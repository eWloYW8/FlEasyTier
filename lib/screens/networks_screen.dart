import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/network_config.dart';
import '../providers/app_state.dart';
import '../widgets/network_tile.dart';
import 'config_edit_screen.dart';
import 'network_detail_screen.dart';

class NetworksScreen extends StatelessWidget {
  const NetworksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    if (wide) return const _DesktopLayout();
    return const _MobileLayout();
  }
}

// ── Desktop: master-detail ──

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        // Master
        SizedBox(
          width: 300,
          child: Column(
            children: [
              _ListHeader(cs: cs),
              Expanded(child: _ConfigList(selected: state.selectedConfigId)),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // Detail
        Expanded(
          child: state.selectedConfig != null
              ? NetworkDetailScreen(configId: state.selectedConfig!.id)
              : const _EmptyDetail(),
        ),
      ],
    );
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.cs});
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
      child: Row(
        children: [
          Text('Networks',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const Spacer(),
          IconButton.filledTonal(
            icon: const Icon(Icons.add, size: 20),
            tooltip: 'New network',
            onPressed: () => _addConfig(context),
          ),
        ],
      ),
    );
  }
}

// ── Mobile: list with navigation ──

class _MobileLayout extends StatelessWidget {
  const _MobileLayout();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Networks')),
      body: const _ConfigList(navigateOnTap: true),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addConfig(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ── Shared pieces ──

class _ConfigList extends StatelessWidget {
  const _ConfigList({this.selected, this.navigateOnTap = false});
  final String? selected;
  final bool navigateOnTap;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.configs.isEmpty) return const _EmptyList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: state.configs.length,
      itemBuilder: (ctx, i) {
        final cfg = state.configs[i];
        final running = state.isRunning(cfg.id);
        final instance = state.instanceFor(cfg.id);
        return NetworkTile(
          config: cfg,
          running: running,
          peerCount: instance?.peerCount ?? 0,
          selected: cfg.id == selected,
          onTap: () {
            state.selectConfig(cfg.id);
            if (navigateOnTap) {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ChangeNotifierProvider.value(
                  value: state,
                  child: Scaffold(
                    appBar: AppBar(title: Text(cfg.displayName)),
                    body: NetworkDetailScreen(configId: cfg.id),
                  ),
                ),
              ));
            }
          },
        );
      },
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hub_outlined, size: 64, color: cs.outlineVariant),
          const SizedBox(height: 16),
          Text('No networks yet',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: cs.outline)),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Create network'),
            onPressed: () => _addConfig(context),
          ),
        ],
      ),
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.arrow_back, size: 48, color: cs.outlineVariant),
          const SizedBox(height: 12),
          Text('Select a network',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: cs.outline)),
        ],
      ),
    );
  }
}

// ── Helpers ──

void _addConfig(BuildContext context) {
  final state = context.read<AppState>();
  final rpcPort = 15888 + state.configs.length;
  final config = NetworkConfig(rpcPort: rpcPort);
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ChangeNotifierProvider.value(
      value: state,
      child: ConfigEditScreen(config: config, isNew: true),
    ),
  ));
}
