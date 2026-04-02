import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

import 'app.dart';
import 'models/app_log_entry.dart';
import 'providers/app_state.dart';
import 'services/privileged_session.dart';

void main(List<String> args) async {
  if (args.contains('--privileged-helper')) {
    final exitCode = await PrivilegedSession.runHelper(args);
    exit(exitCode);
  }

  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await WindowsSingleInstance.ensureSingleInstance(
      args,
      'FlEasyTier-{4a8d7e2b-single}',
      onSecondWindow: (args) async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

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
