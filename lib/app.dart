import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/app_state.dart';
import 'screens/app_logs_screen.dart';
import 'screens/networks_screen.dart';
import 'screens/settings_screen.dart';

class FlEasyTierApp extends StatelessWidget {
  const FlEasyTierApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return MaterialApp(
      title: 'FlEasyTier',
      debugShowCheckedModeBanner: false,
      themeMode: appState.themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: appState.seedColor,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: appState.seedColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const _MainShell(),
    );
  }
}

class _MainShell extends StatefulWidget {
  const _MainShell();

  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> with WindowListener {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowClose() {
    final appState = context.read<AppState>();
    if (appState.closeToTray && appState.hasRunningInstances) {
      // Hide to tray instead of exiting
      windowManager.hide();
    } else {
      windowManager.destroy();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final pages = const [
      NetworksScreen(),
      AppLogsScreen(),
      SettingsScreen(),
    ];

    if (wide) {
      final cs = Theme.of(context).colorScheme;
      final railLabelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w500,
          );

      return Scaffold(
        body: Row(
          children: [
            Theme(
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
                leading: Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Column(
                    children: [
                      Icon(Icons.lan_rounded, size: 30, color: cs.primary),
                      const SizedBox(height: 4),
                      Text('FlEasyTier', style: railLabelStyle),
                    ],
                  ),
                ),
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
                ],
              ),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: pages[_index]),
          ],
        ),
      );
    }

    return Scaffold(
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
        ],
      ),
    );
  }
}
