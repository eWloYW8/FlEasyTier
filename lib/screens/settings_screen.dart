import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Binary paths ──
          if (state.canEditCoreBinaryPath)
            _SettingsCard(
              icon: Icons.folder_outlined,
              title: 'Binary Paths',
              children: [
                _PathField(
                  label: 'easytier-core',
                  value: state.coreBinaryPath,
                  detected: state.coreBinaryPath != null,
                  onChanged: (v) => state.setCoreBinaryPath(v),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Auto-detect'),
                  onPressed: () async {
                    await state.manager.detectBinaries();
                    state.setCoreBinaryPath(state.manager.coreBinaryPath);
                  },
                ),
              ],
            ),

          // ── Appearance ──
          _SettingsCard(
            icon: Icons.palette_outlined,
            title: 'Appearance',
            children: [
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 380) {
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ThemeModeChip(
                          icon: Icons.brightness_auto,
                          label: 'System',
                          selected: state.themeMode == ThemeMode.system,
                          onTap: () => state.setThemeMode(ThemeMode.system),
                        ),
                        _ThemeModeChip(
                          icon: Icons.light_mode,
                          label: 'Light',
                          selected: state.themeMode == ThemeMode.light,
                          onTap: () => state.setThemeMode(ThemeMode.light),
                        ),
                        _ThemeModeChip(
                          icon: Icons.dark_mode,
                          label: 'Dark',
                          selected: state.themeMode == ThemeMode.dark,
                          onTap: () => state.setThemeMode(ThemeMode.dark),
                        ),
                      ],
                    );
                  }

                  return SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto),
                          label: Text('System')),
                      ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode),
                          label: Text('Light')),
                      ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode),
                          label: Text('Dark')),
                    ],
                    selected: {state.themeMode},
                    onSelectionChanged: (s) => state.setThemeMode(s.first),
                  );
                },
              ),
              const SizedBox(height: 20),
              _ColorPicker(
                selected: state.seedColor,
                onChanged: (c) => state.setSeedColor(c),
              ),
              const SizedBox(height: 20),
              _SchemeVariantPicker(
                selected: state.schemeVariant,
                onChanged: state.setSchemeVariant,
              ),
            ],
          ),

          // ── Behavior ──
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
            _SettingsCard(
              icon: Icons.tune,
              title: 'Behavior',
              children: [
                SwitchListTile(
                  title: const Text('Close to tray'),
                  value: state.closeToTray,
                  onChanged: (v) => state.setCloseToTray(v),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),

          _SettingsCard(
            icon: Icons.receipt_long_outlined,
            title: 'Logs',
            children: [
              _IntField(
                label: 'Auto-clear oversized logs (MB)',
                value: state.logAutoClearSizeMb,
                onChanged: state.setLogAutoClearSizeMb,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Clear local logs'),
                onPressed: () async {
                  final cleared = await state.clearLocalLogs();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Cleared $cleared log file(s)'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ],
          ),

          // ── Import / Export ──
          _SettingsCard(
            icon: Icons.import_export,
            title: 'Import / Export',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.file_upload_outlined, size: 18),
                    label: const Text('Export all'),
                    onPressed: () {
                      final json = state.exportAllConfigsJson();
                      Clipboard.setData(ClipboardData(text: json));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('All configs copied to clipboard'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.file_download_outlined, size: 18),
                    label: const Text('Import from clipboard'),
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text == null || data!.text!.isEmpty) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Clipboard is empty'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }
                      final err = state.importConfigJson(data.text!);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(err ?? 'Config(s) imported'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Reusable settings card
// ═══════════════════════════════════════════════════════════════════════════

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.children,
  });
  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(title,
                      style:
                          ts.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Color picker
// ═══════════════════════════════════════════════════════════════════════════

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.selected, required this.onChanged});
  final Color selected;
  final ValueChanged<Color> onChanged;

  static const _presets = [
    (Color(0xFF00897B), 'Teal'),
    (Color(0xFF1976D2), 'Blue'),
    (Color(0xFF7B1FA2), 'Purple'),
    (Color(0xFFC62828), 'Red'),
    (Color(0xFFEF6C00), 'Orange'),
    (Color(0xFF2E7D32), 'Green'),
    (Color(0xFF00838F), 'Cyan'),
    (Color(0xFF4527A0), 'Indigo'),
    (Color(0xFF5D4037), 'Brown'),
    (Color(0xFF455A64), 'Blue Grey'),
    (Color(0xFFAD1457), 'Pink'),
    (Color(0xFF283593), 'Deep Blue'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _presets.map((entry) {
        final (color, name) = entry;
        final isSelected = selected.toARGB32() == color.toARGB32();
        return Tooltip(
          message: name,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onChanged(color),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: isSelected
                    ? Border.all(
                        color: Theme.of(context).colorScheme.onSurface,
                        width: 3)
                    : null,
                boxShadow: [
                  if (isSelected)
                    BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 8,
                        spreadRadius: 1),
                ],
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : null,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SchemeVariantPicker extends StatelessWidget {
  const _SchemeVariantPicker({
    required this.selected,
    required this.onChanged,
  });

  final DynamicSchemeVariant selected;
  final ValueChanged<DynamicSchemeVariant> onChanged;

  static const _variants = [
    DynamicSchemeVariant.tonalSpot,
    DynamicSchemeVariant.content,
    DynamicSchemeVariant.neutral,
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _variants.map((variant) {
        return ChoiceChip(
          label: Text(AppState.schemeVariantLabel(variant)),
          selected: selected == variant,
          onSelected: (_) => onChanged(variant),
          visualDensity: VisualDensity.compact,
        );
      }).toList(),
    );
  }
}

class _ThemeModeChip extends StatelessWidget {
  const _ThemeModeChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Path field
// ═══════════════════════════════════════════════════════════════════════════

class _PathField extends StatefulWidget {
  const _PathField({
    required this.label,
    required this.value,
    required this.detected,
    required this.onChanged,
  });
  final String label;
  final String? value;
  final bool detected;
  final ValueChanged<String?> onChanged;

  @override
  State<_PathField> createState() => _PathFieldState();
}

class _PathFieldState extends State<_PathField> {
  late TextEditingController _ctrl;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value ?? '');
    _focusNode = FocusNode()
      ..addListener(() {
        if (!_focusNode.hasFocus) {
          _commit();
        }
      });
  }

  @override
  void didUpdateWidget(_PathField old) {
    super.didUpdateWidget(old);
    final nextValue = widget.value ?? '';
    if (_focusNode.hasFocus) return;
    if (nextValue != _ctrl.text) {
      _ctrl.value = _ctrl.value.copyWith(
        text: nextValue,
        selection: TextSelection.collapsed(offset: nextValue.length),
        composing: TextRange.empty,
      );
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            focusNode: _focusNode,
            decoration: InputDecoration(
              labelText: widget.label,
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: widget.detected
                  ? Tooltip(
                      message: 'Detected',
                      child: Icon(Icons.check_circle, color: cs.primary, size: 20))
                  : Tooltip(
                      message: 'Not found',
                      child: Icon(Icons.warning_amber, color: cs.error, size: 20)),
            ),
            onSubmitted: (_) => _commit(),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _pickFile,
          icon: const Icon(Icons.folder_open_outlined, size: 18),
          label: const Text('Browse'),
        ),
      ],
    );
  }

  void _commit() {
    final value = _ctrl.text.trim();
    widget.onChanged(value.isEmpty ? null : value);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: widget.label,
      allowMultiple: false,
      withData: false,
      type: Platform.isWindows ? FileType.custom : FileType.any,
      allowedExtensions: Platform.isWindows ? const ['exe'] : null,
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return;
    _ctrl.value = _ctrl.value.copyWith(
      text: path,
      selection: TextSelection.collapsed(offset: path.length),
      composing: TextRange.empty,
    );
    _commit();
  }
}

class _IntField extends StatefulWidget {
  const _IntField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_IntField> createState() => _IntFieldState();
}

class _IntFieldState extends State<_IntField> {
  late TextEditingController _ctrl;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toString());
    _focusNode = FocusNode()
      ..addListener(() {
        if (!_focusNode.hasFocus) {
          _commit();
        }
      });
  }

  @override
  void didUpdateWidget(_IntField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextValue = widget.value.toString();
    if (_focusNode.hasFocus) return;
    if (_ctrl.text != nextValue) {
      _ctrl.value = _ctrl.value.copyWith(
        text: nextValue,
        selection: TextSelection.collapsed(offset: nextValue.length),
        composing: TextRange.empty,
      );
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      focusNode: _focusNode,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onSubmitted: (_) => _commit(),
    );
  }

  void _commit() {
    final parsed = int.tryParse(_ctrl.text.trim()) ?? widget.value;
    final normalized = parsed < 0 ? 0 : parsed;
    final nextText = normalized.toString();
    if (_ctrl.text != nextText) {
      _ctrl.value = _ctrl.value.copyWith(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
        composing: TextRange.empty,
      );
    }
    widget.onChanged(normalized);
  }
}
