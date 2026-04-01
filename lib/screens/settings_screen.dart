import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/platform_vpn.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Binary paths ──
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
              const SizedBox(height: 8),
              Text(
                'Status queries use direct RPC — easytier-cli not needed.',
                style: ts.bodySmall?.copyWith(color: cs.outline),
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
              Text('Theme', style: ts.bodySmall?.copyWith(color: cs.outline)),
              const SizedBox(height: 8),
              SegmentedButton<ThemeMode>(
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
              ),
              const SizedBox(height: 20),
              Text('Accent Color',
                  style: ts.bodySmall?.copyWith(color: cs.outline)),
              const SizedBox(height: 8),
              _ColorPicker(
                selected: state.seedColor,
                onChanged: (c) => state.setSeedColor(c),
              ),
            ],
          ),

          // ── Behavior ──
          _SettingsCard(
            icon: Icons.tune,
            title: 'Behavior',
            children: [
              if (Platform.isWindows ||
                  Platform.isLinux ||
                  Platform.isMacOS) ...[
                SwitchListTile(
                  title: const Text('Close to tray'),
                  subtitle: const Text(
                      'Hide window instead of quitting when instances are running'),
                  value: state.closeToTray,
                  onChanged: (v) => state.setCloseToTray(v),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ],
          ),

          // ── Import / Export ──
          _SettingsCard(
            icon: Icons.import_export,
            title: 'Import / Export',
            children: [
              Row(
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

          // ── System Service ──
          if (Platform.isWindows || Platform.isLinux)
            _SettingsCard(
              icon: Icons.miscellaneous_services,
              title: 'System Service',
              children: [
                Text(
                  'Register easytier-core as a system service so it starts at boot.',
                  style: ts.bodySmall?.copyWith(color: cs.outline),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: const Text('Install'),
                      onPressed: () async {
                        final msg = await state.installService();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(msg),
                          behavior: SnackBarBehavior.floating,
                        ));
                      },
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      label: const Text('Uninstall'),
                      onPressed: () async {
                        final msg = await state.uninstallService();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(msg),
                          behavior: SnackBarBehavior.floating,
                        ));
                      },
                    ),
                  ],
                ),
              ],
            ),

          // ── Platform ──
          _SettingsCard(
            icon: Icons.devices_outlined,
            title: 'Platform',
            children: [
              Text(PlatformVpn.platformRequirements,
                  style:
                      ts.bodySmall?.copyWith(fontFamily: 'monospace', height: 1.5)),
              const SizedBox(height: 12),
              const _WintunCheck(),
            ],
          ),

          // ── About ──
          _SettingsCard(
            icon: Icons.info_outline,
            title: 'About',
            children: [
              _aboutRow('App', 'FlEasyTier v1.0.0'),
              _aboutRow('Framework', 'Flutter'),
              _aboutRow('Backend', 'EasyTier Core (direct RPC)'),
              const SizedBox(height: 8),
              Text(
                'A Flutter GUI for EasyTier mesh VPN.\n'
                'Supports Windows, Linux, macOS, and Android.',
                style: ts.bodySmall?.copyWith(color: cs.outline),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _aboutRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          Text(value, style: const TextStyle(fontSize: 13)),
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

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value ?? '');
  }

  @override
  void didUpdateWidget(_PathField old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value) {
      _ctrl.text = widget.value ?? '';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: _ctrl,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: widget.detected
            ? Tooltip(
                message: 'Detected',
                child:
                    Icon(Icons.check_circle, color: cs.primary, size: 20))
            : Tooltip(
                message: 'Not found',
                child:
                    Icon(Icons.warning_amber, color: cs.error, size: 20)),
      ),
      onChanged: (v) =>
          widget.onChanged(v.trim().isEmpty ? null : v.trim()),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Wintun check
// ═══════════════════════════════════════════════════════════════════════════

class _WintunCheck extends StatefulWidget {
  const _WintunCheck();

  @override
  State<_WintunCheck> createState() => _WintunCheckState();
}

class _WintunCheckState extends State<_WintunCheck> {
  bool? _found;

  @override
  void initState() {
    super.initState();
    PlatformVpn.checkWintun().then((v) {
      if (mounted) setState(() => _found = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_found == null || _found == true) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, size: 18, color: cs.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'wintun.dll not found next to the executable.\n'
              'Download it from wintun.net and place it alongside fleasytier.exe.',
              style: TextStyle(fontSize: 12, color: cs.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
