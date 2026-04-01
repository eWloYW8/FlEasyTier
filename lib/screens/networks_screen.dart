import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          instance: instance,
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
    return Center(
      child: FilledButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Create Network'),
        onPressed: () => _addConfig(context),
      ),
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

// ── Helpers ──

Future<void> _addConfig(BuildContext context) async {
  final action = await showModalBottomSheet<_NewNetworkAction>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: const Text('Import TOML'),
              onTap: () => Navigator.pop(ctx, _NewNetworkAction.importToml),
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Edit Config'),
              onTap: () => Navigator.pop(ctx, _NewNetworkAction.editConfig),
            ),
            ListTile(
              leading: const Icon(Icons.code_outlined),
              title: const Text('Edit TOML'),
              onTap: () => Navigator.pop(ctx, _NewNetworkAction.editToml),
            ),
          ],
        ),
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  final state = context.read<AppState>();
  switch (action) {
    case _NewNetworkAction.importToml:
      await _showTomlImportDialog(context, state);
    case _NewNetworkAction.editConfig:
      final config = _makeDraftConfig(state);
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: state,
          child: ConfigEditScreen(config: config, isNew: true),
        ),
      ));
    case _NewNetworkAction.editToml:
      await _showNewTomlEditor(context, state);
  }
}

NetworkConfig _makeDraftConfig(AppState state) {
  final used = state.configs.map((c) => c.rpcPort).toSet();
  var rpcPort = 15888;
  while (used.contains(rpcPort)) {
    rpcPort++;
  }
  return NetworkConfig(rpcPort: rpcPort);
}

Future<void> _showTomlImportDialog(BuildContext context, AppState state) async {
  final fallbackConfig = _makeDraftConfig(state);
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['toml'],
      dialogTitle: 'Import TOML',
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return;

    final toml = await File(path).readAsString();
    final imported = NetworkConfig.fromToml(
      toml,
      id: fallbackConfig.id,
      autoStart: false,
      serviceEnabled: false,
      rpcPort: fallbackConfig.rpcPort,
    );
    state.addConfig(imported);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Import failed: $e'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

Future<void> _showNewTomlEditor(BuildContext context, AppState state) async {
  final draft = _makeDraftConfig(state);
  final ctrl = TextEditingController(text: draft.toToml());

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Row(
          children: [
            const Text('New TOML'),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: ctrl.text));
              },
            ),
          ],
        ),
        content: SizedBox(
          width: 600,
          height: 500,
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              try {
                final parsed = NetworkConfig.fromToml(
                  ctrl.text,
                  id: draft.id,
                  autoStart: false,
                  serviceEnabled: false,
                  rpcPort: draft.rpcPort,
                );
                state.addConfig(parsed);
                Navigator.pop(ctx);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Save failed: $e'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      );
    },
  );
}

enum _NewNetworkAction {
  importToml,
  editConfig,
  editToml,
}
