import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'models/app_log_entry.dart';
import 'providers/app_state.dart';
import 'screens/about_screen.dart';
import 'screens/app_logs_screen.dart';
import 'screens/networks_screen.dart';
import 'screens/settings_screen.dart';

class FlEasyTierApp extends StatelessWidget {
  const FlEasyTierApp({super.key});

  ThemeData _buildTheme({
    required Color seedColor,
    required Brightness brightness,
    required DynamicSchemeVariant dynamicSchemeVariant,
  }) {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
        dynamicSchemeVariant: dynamicSchemeVariant,
      ),
      useMaterial3: true,
    );

    final cs = theme.colorScheme;
    return theme.copyWith(
      cardTheme: CardThemeData(
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cs.outlineVariant),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return MaterialApp(
      title: 'FlEasyTier',
      debugShowCheckedModeBanner: false,
      themeMode: appState.themeMode,
      theme: _buildTheme(
        seedColor: appState.seedColor,
        brightness: Brightness.light,
        dynamicSchemeVariant: appState.schemeVariant,
      ),
      darkTheme: _buildTheme(
        seedColor: appState.seedColor,
        brightness: Brightness.dark,
        dynamicSchemeVariant: appState.schemeVariant,
      ),
      home: const _AppShell(),
    );
  }
}

class _AppShell extends StatelessWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        _MainShell(),
        _ErrorToastLayer(),
      ],
    );
  }
}

class _MainShell extends StatefulWidget {
  const _MainShell();

  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell>
    with WindowListener, TrayListener {
  int _index = 0;
  bool _isMaximized = false;
  bool _isAlwaysOnTop = false;
  bool _isClosing = false;
  bool _isTrayReady = false;
  String? _lastTrayMenuSignature;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    if (_isDesktop) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncWindowState();
        _initTray();
      });
    }
  }

  @override
  void dispose() {
    if (_isDesktop) {
      trayManager.removeListener(this);
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowClose() {
    if (_isClosing) return;
    _handleWindowClose();
  }

  @override
  void onWindowMaximize() {
    if (!_isMaximized) {
      setState(() => _isMaximized = true);
    }
  }

  @override
  void onWindowUnmaximize() {
    if (_isMaximized) {
      setState(() => _isMaximized = false);
    }
  }

  @override
  void onWindowRestore() {
    _syncWindowState();
  }

  Future<void> _syncWindowState() async {
    if (!_isDesktop || !mounted) return;
    final isMaximized = await windowManager.isMaximized();
    final isAlwaysOnTop = await windowManager.isAlwaysOnTop();
    if (!mounted) return;
    setState(() {
      _isMaximized = isMaximized;
      _isAlwaysOnTop = isAlwaysOnTop;
    });
  }

  Future<void> _toggleAlwaysOnTop() async {
    final next = !_isAlwaysOnTop;
    await windowManager.setAlwaysOnTop(next);
    if (!mounted) return;
    setState(() => _isAlwaysOnTop = next);
  }

  Future<void> _toggleMaximize() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Future<void> _handleWindowClose() async {
    if (_isClosing) return;
    final appState = context.read<AppState>();
    if (appState.closeToTray) {
      await _hideToTray();
    } else {
      await _quitApp();
    }
  }

  Future<void> _initTray() async {
    if (!_isDesktop || _isTrayReady) return;
    final state = context.read<AppState>();

    await trayManager.setIcon(
      Platform.isWindows ? 'assets/tray_icon.ico' : 'assets/tray_icon.png',
    );
    if (Platform.isWindows || Platform.isMacOS) {
      await trayManager.setToolTip('FlEasyTier');
    }
    await _refreshTrayMenu(state);
    _isTrayReady = true;
  }

  Future<void> _refreshTrayMenu(AppState state) async {
    if (!_isDesktop) return;
    final visible = await windowManager.isVisible();
    final signature = [
      visible ? 'visible' : 'hidden',
      state.selectedConfigId ?? '',
      for (final config in state.configs)
        '${config.id}:${state.isRunning(config.id)}:${config.serviceEnabled}',
    ].join('|');
    if (_lastTrayMenuSignature == signature) {
      return;
    }

    final runningConfigs =
        state.configs.where((config) => state.isRunning(config.id)).toList();
    final networkItems = state.configs.isEmpty
        ? [MenuItem(label: 'No Networks', disabled: true)]
        : state.configs.map((config) {
            final running = state.isRunning(config.id);
            final status = running
                ? (config.serviceEnabled ? 'Running Service' : 'Running')
                : (config.serviceEnabled ? 'Service Installed' : 'Stopped');
            return MenuItem.submenu(
              key: 'network:${config.id}',
              label: config.displayName,
              submenu: Menu(
                items: [
                  MenuItem(
                    key: 'open_network:${config.id}',
                    label: 'Open',
                  ),
                  MenuItem(
                    key: 'toggle_network:${config.id}',
                    label: running ? 'Stop' : 'Start',
                  ),
                  MenuItem(
                    label: status,
                    disabled: true,
                  ),
                ],
              ),
            );
          }).toList();

    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(
            key: visible ? 'hide_window' : 'show_window',
            label: visible ? 'Hide Window' : 'Show Window',
          ),
          MenuItem(
            key: 'open_networks',
            label: 'Networks',
          ),
          MenuItem(
            key: 'open_logs',
            label: 'Logs',
          ),
          MenuItem(
            key: 'open_settings',
            label: 'Settings',
          ),
          MenuItem(
            key: 'open_about',
            label: 'About',
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'start_all',
            label: 'Start All',
            disabled: state.configs.isEmpty,
          ),
          MenuItem(
            key: 'stop_all',
            label: 'Stop All',
            disabled: runningConfigs.isEmpty,
          ),
          MenuItem.separator(),
          MenuItem.submenu(
            key: 'manage_networks',
            label: 'Manage Networks',
            submenu: Menu(items: networkItems),
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'exit_app',
            label: 'Exit',
          ),
        ],
      ),
    );
    _lastTrayMenuSignature = signature;
  }

  Future<void> _showFromTray() async {
    final state = context.read<AppState>();
    await windowManager.setSkipTaskbar(false);
    final minimized = await windowManager.isMinimized();
    if (minimized) {
      await windowManager.restore();
    }
    await windowManager.show();
    await windowManager.focus();
    await _refreshTrayMenu(state);
  }

  Future<void> _hideToTray() async {
    final state = context.read<AppState>();
    await windowManager.setSkipTaskbar(true);
    await windowManager.hide();
    await _refreshTrayMenu(state);
  }

  Future<void> _quitApp() async {
    if (_isClosing) return;
    _isClosing = true;
    if (_isDesktop) {
      await trayManager.destroy();
      await windowManager.setSkipTaskbar(false);
    }
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_toggleWindowFromTray());
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key ?? '';
    switch (key) {
      case 'show_window':
        unawaited(_showFromTray());
        return;
      case 'hide_window':
        unawaited(_hideToTray());
        return;
      case 'open_networks':
        unawaited(_openPage(0));
        return;
      case 'open_logs':
        unawaited(_openPage(1));
        return;
      case 'open_settings':
        unawaited(_openPage(2));
        return;
      case 'open_about':
        unawaited(_openPage(3));
        return;
      case 'start_all':
        unawaited(_startAllNetworks());
        return;
      case 'stop_all':
        unawaited(_stopAllNetworks());
        return;
      case 'exit_app':
        unawaited(_quitApp());
        return;
    }

    if (key.startsWith('open_network:')) {
      final id = key.substring('open_network:'.length);
      unawaited(_openNetwork(id));
      return;
    }
    if (key.startsWith('toggle_network:')) {
      final id = key.substring('toggle_network:'.length);
      unawaited(_toggleNetwork(id));
      return;
    }
  }

  Future<void> _toggleWindowFromTray() async {
    final visible = await windowManager.isVisible();
    if (visible) {
      await windowManager.focus();
    } else {
      await _showFromTray();
    }
  }

  Future<void> _openPage(int index) async {
    if (!mounted) return;
    setState(() => _index = index);
    await _showFromTray();
  }

  Future<void> _openNetwork(String configId) async {
    final state = context.read<AppState>();
    state.selectConfig(configId);
    if (!mounted) return;
    setState(() => _index = 0);
    await _showFromTray();
  }

  Future<void> _toggleNetwork(String configId) async {
    final state = context.read<AppState>();
    await state.toggleInstance(configId);
    await _refreshTrayMenu(state);
  }

  Future<void> _startAllNetworks() async {
    final state = context.read<AppState>();
    for (final config in state.configs) {
      if (!state.isRunning(config.id)) {
        await state.startInstance(config.id);
      }
    }
    await _refreshTrayMenu(state);
  }

  Future<void> _stopAllNetworks() async {
    final state = context.read<AppState>();
    for (final config in state.configs.where((config) => state.isRunning(config.id))) {
      await state.stopInstance(config.id);
    }
    await _refreshTrayMenu(state);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final pages = const [
      NetworksScreen(),
      AppLogsScreen(),
      SettingsScreen(),
      AboutScreen(),
    ];

    final content = wide
        ? Row(
            children: [
              _buildRail(context),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(child: pages[_index]),
            ],
          )
        : Scaffold(
            body: pages[_index],
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.hub_outlined),
                  selectedIcon: Icon(Icons.hub),
                  label: 'Networks',
                ),
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: 'Logs',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Settings',
                ),
                NavigationDestination(
                  icon: Icon(Icons.info_outline),
                  selectedIcon: Icon(Icons.info),
                  label: 'About',
                ),
              ],
            ),
          );

    if (_isDesktop && _isTrayReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _refreshTrayMenu(appState);
        }
      });
    }

    if (_isDesktop) {
      return Scaffold(
        body: Column(
          children: [
            _DesktopWindowBar(
              pageTitle: switch (_index) {
                0 => 'Networks',
                1 => 'Logs',
                2 => 'Settings',
                _ => 'About',
              },
              isAlwaysOnTop: _isAlwaysOnTop,
              isMaximized: _isMaximized,
              onToggleAlwaysOnTop: _toggleAlwaysOnTop,
              onMinimize: () => windowManager.minimize(),
              onToggleMaximize: _toggleMaximize,
              onClose: _handleWindowClose,
            ),
            Expanded(child: content),
          ],
        ),
      );
    }

    return content;
  }

  Widget _buildRail(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final railLabelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w500,
        );

    return Theme(
      data: Theme.of(context).copyWith(
        navigationRailTheme: NavigationRailThemeData(
          unselectedLabelTextStyle: railLabelStyle,
          selectedLabelTextStyle:
              railLabelStyle?.copyWith(color: cs.primary),
        ),
      ),
      child: NavigationRail(
        extended: false,
        labelType: NavigationRailLabelType.all,
        minWidth: 76,
        minExtendedWidth: 76,
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationRailDestination(
            icon: Icon(Icons.hub_outlined),
            selectedIcon: Icon(Icons.hub),
            label: Text('Networks'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: Text('Logs'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: Text('Settings'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.info_outline),
            selectedIcon: Icon(Icons.info),
            label: Text('About'),
          ),
        ],
      ),
    );
  }
}

class _DesktopWindowBar extends StatelessWidget {
  const _DesktopWindowBar({
    required this.pageTitle,
    required this.isAlwaysOnTop,
    required this.isMaximized,
    required this.onToggleAlwaysOnTop,
    required this.onMinimize,
    required this.onToggleMaximize,
    required this.onClose,
  });

  final String pageTitle;
  final bool isAlwaysOnTop;
  final bool isMaximized;
  final Future<void> Function() onToggleAlwaysOnTop;
  final Future<void> Function() onMinimize;
  final Future<void> Function() onToggleMaximize;
  final Future<void> Function() onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: cs.surfaceContainerLowest,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              Expanded(
                child: DragToMoveArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.lan_rounded,
                            size: 16,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'FlEasyTier',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          width: 1,
                          height: 14,
                          color: cs.outlineVariant,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          pageTitle,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _WindowActionButton(
                tooltip: isAlwaysOnTop ? 'Unpin Window' : 'Pin Window',
                icon: isAlwaysOnTop ? Icons.push_pin : Icons.push_pin_outlined,
                active: isAlwaysOnTop,
                onPressed: onToggleAlwaysOnTop,
              ),
              _WindowActionButton(
                tooltip: 'Minimize',
                icon: Icons.remove_rounded,
                onPressed: onMinimize,
              ),
              _WindowActionButton(
                tooltip: isMaximized ? 'Restore' : 'Maximize',
                icon: isMaximized
                    ? Icons.filter_none_rounded
                    : Icons.crop_square_rounded,
                onPressed: onToggleMaximize,
              ),
              _WindowActionButton(
                tooltip: 'Close',
                icon: Icons.close_rounded,
                onPressed: onClose,
                danger: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorToastLayer extends StatefulWidget {
  const _ErrorToastLayer();

  @override
  State<_ErrorToastLayer> createState() => _ErrorToastLayerState();
}

class _ErrorToastLayerState extends State<_ErrorToastLayer> {
  static const _displayDuration = Duration(seconds: 8);
  static const _animationDuration = Duration(milliseconds: 220);
  StreamSubscription<AppLogEntry>? _subscription;
  final List<_ToastItem> _items = [];

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _subscription = state.errorLogStream.listen(_showToast);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    for (final item in _items) {
      item.timer.cancel();
    }
    super.dispose();
  }

  void _showToast(AppLogEntry entry) {
    if (!mounted) return;

    final id = '${entry.timestamp.microsecondsSinceEpoch}-${_items.length}';
    late final _ToastItem item;
    item = _ToastItem(
      id: id,
      entry: entry,
      timer: Timer(_displayDuration, () {
        _dismissToast(id);
      }),
      visible: false,
      dismissing: false,
    );

    setState(() {
      _items.insert(0, item);
      if (_items.length > 4) {
        final removed = _items.removeLast();
        removed.timer.cancel();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = _items.where((candidate) => candidate.id == id).firstOrNull;
      if (current == null || current.dismissing) return;
      setState(() {
        current.visible = true;
      });
    });
  }

  void _dismissToast(String id) {
    final item = _items.where((candidate) => candidate.id == id).firstOrNull;
    if (item == null || item.dismissing) return;

    item.timer.cancel();
    setState(() {
      item.dismissing = true;
      item.visible = false;
    });

    Future.delayed(_animationDuration, () {
      if (!mounted) return;
      setState(() {
        _items.removeWhere((candidate) => candidate.id == id);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _items
                  .map((item) => Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: AnimatedSlide(
                          duration: _animationDuration,
                          curve: Curves.easeOutCubic,
                          offset: item.visible
                              ? Offset.zero
                              : const Offset(0, 0.18),
                          child: AnimatedOpacity(
                            duration: _animationDuration,
                            curve: Curves.easeOutCubic,
                            opacity: item.visible ? 1 : 0,
                            child: _ErrorToastCard(
                              entry: item.entry,
                              onClose: () => _dismissToast(item.id),
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorToastCard extends StatelessWidget {
  const _ErrorToastCard({
    required this.entry,
    required this.onClose,
  });

  final AppLogEntry entry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final detail = entry.detail?.trim() ?? '';

    return Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(14),
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: cs.error.withValues(alpha: 0.25),
          ),
        ),
        padding: const EdgeInsets.all(12),
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
                    color: cs.error.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.error_outline_rounded,
                    size: 17,
                    color: cs.error,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${entry.category} Error',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: cs.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatTimestamp(entry.timestamp),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onErrorContainer.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onClose,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: cs.onErrorContainer.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              entry.message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onErrorContainer,
                height: 1.3,
              ),
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                detail,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onErrorContainer.withValues(alpha: 0.86),
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime time) {
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    final ss = time.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }
}

class _ToastItem {
  _ToastItem({
    required this.id,
    required this.entry,
    required this.timer,
    required this.visible,
    required this.dismissing,
  });

  final String id;
  final AppLogEntry entry;
  final Timer timer;
  bool visible;
  bool dismissing;
}

class _WindowActionButton extends StatelessWidget {
  const _WindowActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.danger = false,
  });

  final String tooltip;
  final IconData icon;
  final Future<void> Function() onPressed;
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final foregroundColor = danger
        ? cs.error
        : active
            ? cs.primary
            : cs.onSurfaceVariant;
    final backgroundColor = danger
        ? cs.errorContainer.withValues(alpha: 0.35)
        : active
            ? cs.primaryContainer.withValues(alpha: 0.7)
            : Colors.transparent;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          onPressed();
        },
        child: Container(
          width: 46,
          height: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: backgroundColor),
          child: Icon(icon, size: 18, color: foregroundColor),
        ),
      ),
    );
  }
}
