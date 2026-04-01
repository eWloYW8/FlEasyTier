import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/app_log_entry.dart';
import '../providers/app_state.dart';

class AppLogsScreen extends StatefulWidget {
  const AppLogsScreen({super.key});

  @override
  State<AppLogsScreen> createState() => _AppLogsScreenState();
}

class _AppLogsScreenState extends State<AppLogsScreen> {
  String _query = '';
  AppLogLevel? _level;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    final logs = state.appLogs.where(_matches).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Application Logs')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(
                  top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
                  bottom:
                      BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(Icons.article_outlined,
                            size: 16, color: cs.primary),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Runtime Logs',
                        style: ts.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        '${logs.length} visible',
                        style: ts.bodySmall?.copyWith(color: cs.outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search message, category, or detail',
                      prefixIcon: Icon(Icons.search, size: 18),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) => setState(() => _query = value.trim()),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _LevelChip(
                              label: 'All',
                              selected: _level == null,
                              onTap: () => setState(() => _level = null),
                            ),
                            _LevelChip(
                              label: 'Info',
                              selected: _level == AppLogLevel.info,
                              onTap: () =>
                                  setState(() => _level = AppLogLevel.info),
                            ),
                            _LevelChip(
                              label: 'Warnings',
                              selected: _level == AppLogLevel.warning,
                              onTap: () =>
                                  setState(() => _level = AppLogLevel.warning),
                            ),
                            _LevelChip(
                              label: 'Errors',
                              selected: _level == AppLogLevel.error,
                              onTap: () =>
                                  setState(() => _level = AppLogLevel.error),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Copy all',
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: state.exportAppLogsText()),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Application logs copied'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_all_outlined, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Clear',
                        onPressed:
                            state.appLogs.isEmpty ? null : () => state.clearAppLogs(),
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: logs.isEmpty
                ? const SizedBox.shrink()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: logs.length,
                    separatorBuilder: (context, index) =>
                        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
                    itemBuilder: (context, index) =>
                        _LogRow(entry: logs[index]),
                  ),
          ),
        ],
      ),
    );
  }

  bool _matches(AppLogEntry entry) {
    if (_level != null && entry.level != _level) return false;
    if (_query.isEmpty) return true;
    final haystack = [
      entry.category,
      entry.message,
      entry.detail ?? '',
    ].join('\n').toLowerCase();
    return haystack.contains(_query.toLowerCase());
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final AppLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final badgeBg = switch (entry.level) {
      AppLogLevel.info => cs.primaryContainer,
      AppLogLevel.warning => const Color(0xFFFFE3B1),
      AppLogLevel.error => cs.errorContainer,
    };
    final badgeFg = switch (entry.level) {
      AppLogLevel.info => cs.onPrimaryContainer,
      AppLogLevel.warning => const Color(0xFF6E4A00),
      AppLogLevel.error => cs.onErrorContainer,
    };

    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 30,
                  child: Center(
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Icon(
                        switch (entry.level) {
                          AppLogLevel.info => Icons.info_outline,
                          AppLogLevel.warning => Icons.warning_amber_rounded,
                          AppLogLevel.error => Icons.error_outline,
                        },
                        size: 14,
                        color: badgeFg,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: badgeBg,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              entry.levelLabel,
                              style: TextStyle(
                                color: badgeFg,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.label_outline, size: 12, color: cs.outline),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              entry.category,
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.outline,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatTimestamp(entry.timestamp),
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.outline,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        entry.message,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                      if (entry.detail != null && entry.detail!.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SelectableText(
                            entry.detail!,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                              color: cs.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTimestamp(DateTime timestamp) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(timestamp.hour)}:${two(timestamp.minute)}:${two(timestamp.second)}';
}
