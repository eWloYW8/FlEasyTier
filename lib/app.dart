import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'l10n/app_localizations.dart';
import 'models/app_log_entry.dart';
import 'providers/app_state.dart';
import 'screens/about_screen.dart';
import 'screens/app_logs_screen.dart';
import 'screens/networks_screen.dart';
import 'screens/settings_screen.dart';
import 'utils/color_compat.dart';

class FlEasyTierApp extends StatelessWidget {
  const FlEasyTierApp({super.key});

  List<String> _fontFallbacks() {
    if (Platform.isWindows) {
      return const [
        'Microsoft YaHei UI',
        'Microsoft YaHei',
        'SimSun',
        'Segoe UI Symbol',
      ];
    }
    if (Platform.isMacOS) {
      return const [
        'PingFang SC',
        'Hiragino Sans GB',
        'Heiti SC',
        '.AppleSystemUIFont',
      ];
    }
    if (Platform.isAndroid) {
      return const ['Noto Sans CJK SC', 'Noto Sans SC', 'sans-serif'];
    }
    if (Platform.isLinux) {
      return const [
        'Noto Sans CJK SC',
        'Noto Sans SC',
        'Source Han Sans SC',
        'WenQuanYi Zen Hei',
        'Droid Sans Fallback',
      ];
    }
    return const ['Noto Sans CJK SC', 'Noto Sans SC'];
  }

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
      fontFamilyFallback: _fontFallbacks(),
      useMaterial3: true,
    );

    final cs = theme.colorScheme;
    final cardTheme = theme.cardTheme.copyWith(
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
    );
    return theme.copyWith(
      cardTheme: cardTheme,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return MaterialApp(
      title: 'FlEasyTier',
      debugShowCheckedModeBanner: false,
      locale: appState.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
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
    return const Stack(children: [_MainShell(), _ErrorToastLayer()]);
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
        final state = context.read<AppState>();
        if (state.closeToTray) _initTray();
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
  void onWindowFocus() {
    // macOS Dock reactivation shows the window natively, bypassing
    // window_manager plugin state. Re-assert preventClose so close
    // events are intercepted, and reset _isClosing in case a previous
    // quit attempt didn't fully terminate the process.
    if (_isDesktop && _isClosing) {
      _isClosing = false;
      windowManager.setPreventClose(true);
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
    final l10n = context.l10n;

    await trayManager.setIcon(
      Platform.isWindows ? 'assets/tray_icon.ico' : 'assets/tray_icon.png',
    );
    if (Platform.isWindows || Platform.isMacOS) {
      await trayManager.setToolTip(l10n.t('app.title'));
    }
    await _refreshTrayMenu(state);
    _isTrayReady = true;
  }

  Future<void> _destroyTray() async {
    if (!_isTrayReady) return;
    await trayManager.destroy();
    _isTrayReady = false;
    _lastTrayMenuSignature = null;
  }

  Future<void> _refreshTrayMenu(AppState state) async {
    if (!_isDesktop) return;
    final l10n = context.l10n;
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

    final runningConfigs = state.configs
        .where((config) => state.isRunning(config.id))
        .toList();
    final networkItems = state.configs.isEmpty
        ? [MenuItem(label: l10n.t('tray.no_networks'), disabled: true)]
        : state.configs.map((config) {
            final running = state.isRunning(config.id);
            final status = running
                ? (config.serviceEnabled
                      ? l10n.t('tray.running_service')
                      : l10n.t('tray.running'))
                : (config.serviceEnabled
                      ? l10n.t('tray.service_installed')
                      : l10n.t('tray.stopped'));
            return MenuItem.submenu(
              key: 'network:${config.id}',
              label: config.displayName,
              submenu: Menu(
                items: [
                  MenuItem(
                    key: 'open_network:${config.id}',
                    label: l10n.t('tray.open'),
                  ),
                  MenuItem(
                    key: 'toggle_network:${config.id}',
                    label: running
                        ? l10n.t('common.stop')
                        : l10n.t('common.start'),
                  ),
                  MenuItem(label: status, disabled: true),
                ],
              ),
            );
          }).toList();

    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(
            key: visible ? 'hide_window' : 'show_window',
            label: visible
                ? l10n.t('tray.hide_window')
                : l10n.t('tray.show_window'),
          ),
          MenuItem(key: 'open_networks', label: l10n.t('nav.networks')),
          MenuItem(key: 'open_logs', label: l10n.t('nav.logs')),
          MenuItem(key: 'open_settings', label: l10n.t('nav.settings')),
          MenuItem(key: 'open_about', label: l10n.t('nav.about')),
          MenuItem.separator(),
          MenuItem(
            key: 'start_all',
            label: l10n.t('tray.start_all'),
            disabled: state.configs.isEmpty,
          ),
          MenuItem(
            key: 'stop_all',
            label: l10n.t('tray.stop_all'),
            disabled: runningConfigs.isEmpty,
          ),
          MenuItem.separator(),
          MenuItem.submenu(
            key: 'manage_networks',
            label: l10n.t('tray.manage_networks'),
            submenu: Menu(items: networkItems),
          ),
          MenuItem.separator(),
          MenuItem(key: 'exit_app', label: l10n.t('tray.exit')),
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
    final appState = context.read<AppState>();
    if (_isDesktop) {
      await trayManager.destroy();
      await windowManager.setSkipTaskbar(false);
    }
    // Shut down the privileged helper and all managed processes before
    // closing the window so the elevated daemon does not linger.
    await appState.shutdown();
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
    for (final config in state.configs.where(
      (config) => state.isRunning(config.id),
    )) {
      await state.stopInstance(config.id);
    }
    await _refreshTrayMenu(state);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final l10n = context.l10n;
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
              destinations: [
                NavigationDestination(
                  icon: Icon(Icons.hub_outlined),
                  selectedIcon: Icon(Icons.hub),
                  label: l10n.t('nav.networks'),
                ),
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: l10n.t('nav.logs'),
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: l10n.t('nav.settings'),
                ),
                NavigationDestination(
                  icon: Icon(Icons.info_outline),
                  selectedIcon: Icon(Icons.info),
                  label: l10n.t('nav.about'),
                ),
              ],
            ),
          );

    if (_isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (appState.closeToTray && !_isTrayReady) {
          _initTray();
        } else if (!appState.closeToTray && _isTrayReady) {
          _destroyTray();
        } else if (_isTrayReady) {
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
                0 => l10n.t('nav.networks'),
                1 => l10n.t('nav.logs'),
                2 => l10n.t('nav.settings'),
                _ => l10n.t('nav.about'),
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
    final l10n = context.l10n;
    final railLabelStyle = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w500);

    return Theme(
      data: Theme.of(context).copyWith(
        navigationRailTheme: NavigationRailThemeData(
          unselectedLabelTextStyle: railLabelStyle,
          selectedLabelTextStyle: railLabelStyle?.copyWith(color: cs.primary),
        ),
      ),
      child: NavigationRail(
        extended: false,
        labelType: NavigationRailLabelType.all,
        minWidth: 76,
        minExtendedWidth: 76,
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationRailDestination(
            icon: const Icon(Icons.hub_outlined),
            selectedIcon: const Icon(Icons.hub),
            label: Text(l10n.t('nav.networks')),
          ),
          NavigationRailDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            selectedIcon: const Icon(Icons.receipt_long),
            label: Text(l10n.t('nav.logs')),
          ),
          NavigationRailDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: Text(l10n.t('nav.settings')),
          ),
          NavigationRailDestination(
            icon: const Icon(Icons.info_outline),
            selectedIcon: const Icon(Icons.info),
            label: Text(l10n.t('nav.about')),
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
                          context.l10n.t('app.title'),
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
                tooltip: isAlwaysOnTop
                    ? context.l10n.t('window.unpin')
                    : context.l10n.t('window.pin'),
                icon: isAlwaysOnTop ? Icons.push_pin : Icons.push_pin_outlined,
                active: isAlwaysOnTop,
                onPressed: onToggleAlwaysOnTop,
              ),
              _WindowActionButton(
                tooltip: context.l10n.t('window.minimize'),
                icon: Icons.remove_rounded,
                onPressed: onMinimize,
              ),
              _WindowActionButton(
                tooltip: isMaximized
                    ? context.l10n.t('window.restore')
                    : context.l10n.t('window.maximize'),
                icon: isMaximized
                    ? Icons.filter_none_rounded
                    : Icons.crop_square_rounded,
                onPressed: onToggleMaximize,
              ),
              _WindowActionButton(
                tooltip: context.l10n.t('window.close'),
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
      final current = _items
          .where((candidate) => candidate.id == id)
          .firstOrNull;
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
                  .map(
                    (item) => Padding(
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
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorToastCard extends StatelessWidget {
  const _ErrorToastCard({required this.entry, required this.onClose});

  final AppLogEntry entry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final detail = entry.detail?.trim() ?? '';
    final l10n = context.l10n;

    return Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(14),
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: withAlphaFactor(cs.error, 0.25)),
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
                    color: withAlphaFactor(cs.error, 0.14),
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
                        '${entry.category} ${l10n.t('common.error')}',
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
                          color: withAlphaFactor(cs.onErrorContainer, 0.72),
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
                      color: withAlphaFactor(cs.onErrorContainer, 0.8),
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
                  color: withAlphaFactor(cs.onErrorContainer, 0.86),
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
        ? withAlphaFactor(cs.errorContainer, 0.35)
        : active
        ? withAlphaFactor(cs.primaryContainer, 0.7)
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
