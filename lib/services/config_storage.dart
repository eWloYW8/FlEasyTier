import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/network_config.dart';

class ConfigStorage {
  late String _dataDir;

  Future<void> initialize() async {
    final appDir = await getApplicationSupportDirectory();
    _dataDir = '${appDir.path}${Platform.pathSeparator}FlEasyTier';
    await Directory(_dataDir).create(recursive: true);
  }

  String get _configFile =>
      '$_dataDir${Platform.pathSeparator}configs.json';

  String get _settingsFile =>
      '$_dataDir${Platform.pathSeparator}settings.json';

  Future<List<NetworkConfig>> loadConfigs() async {
    final file = File(_configFile);
    if (!await file.exists()) return [];
    try {
      final content = await file.readAsString();
      final list = jsonDecode(content) as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map(NetworkConfig.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveConfigs(List<NetworkConfig> configs) async {
    final json = configs.map((c) => c.toJson()).toList();
    await File(_configFile)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(json));
  }

  Future<Map<String, dynamic>> loadSettings() async {
    final file = File(_settingsFile);
    if (!await file.exists()) return {};
    try {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveSettings(Map<String, dynamic> settings) async {
    await File(_settingsFile)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(settings));
  }
}
