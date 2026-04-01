import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'models/app_log_entry.dart';
import 'providers/app_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    const options = WindowOptions(
      size: Size(1100, 720),
      minimumSize: Size(480, 520),
      center: true,
      title: 'FlEasyTier',
      titleBarStyle: TitleBarStyle.hidden,
    );
    windowManager.waitUntilReadyToShow(options, () async {
      if (Platform.isMacOS) {
        await windowManager.setTitleBarStyle(
          TitleBarStyle.hidden,
          windowButtonVisibility: false,
        );
      }
      await windowManager.show();
      await windowManager.focus();
    });
  }

  final appState = AppState();
  await appState.initialize();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    appState.addLog(
      AppLogLevel.error,
      'Unhandled Flutter framework exception',
      category: 'Crash',
      detail: details.exceptionAsString(),
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    appState.addLog(
      AppLogLevel.error,
      'Unhandled platform exception',
      category: 'Crash',
      detail: '$error\n$stack',
    );
    return true;
  };

  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: const FlEasyTierApp(),
    ),
  );
}
