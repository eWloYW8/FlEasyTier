import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/network_config.dart';

class ConfigStorage {
  late String _dataDir;
  late String _configsDir;

  Future<void> initialize() async {
    final appDir = await getApplicationSupportDirectory();
    _dataDir = '${appDir.path}${Platform.pathSeparator}FlEasyTier';
    _configsDir = '$_dataDir${Platform.pathSeparator}configs';
    await Directory(_configsDir).create(recursive: true);
  }

  String get configDir => _configsDir;

  String configTomlPath(String configId) =>
      '$_configsDir${Platform.pathSeparator}$configId.toml';

  String configMetaPath(String configId) =>
      '$_configsDir${Platform.pathSeparator}$configId.meta.json';

  String get _settingsFile =>
      '$_dataDir${Platform.pathSeparator}settings.json';

  Future<List<NetworkConfig>> loadConfigs() async {
    final dir = Directory(_configsDir);
    if (!await dir.exists()) return [];

    final files = await dir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.toml'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));

    final configs = <NetworkConfig>[];
    for (final file in files) {
      try {
        final configId = _configIdFromPath(file.path);
        final meta = await _loadMeta(configId);
        final toml = await file.readAsString();
        configs.add(NetworkConfig.fromToml(
          toml,
          id: meta['id'] as String? ?? configId,
          autoStart: meta['auto_start'] as bool? ?? false,
          serviceEnabled: meta['service_enabled'] as bool? ?? false,
          rpcPort: meta['rpc_port'] as int? ?? 15888,
          rpcPortalWhitelist:
              (meta['rpc_portal_whitelist'] as List?)?.map((e) => '$e').toList(),
        ));
      } catch (_) {
        // Skip malformed files so one bad config does not block the app.
      }
    }

    return configs;
  }

  Future<void> saveConfigs(List<NetworkConfig> configs) async {
    await Directory(_configsDir).create(recursive: true);

    final expectedIds = configs.map((config) => config.id).toSet();
    final existingFiles = await Directory(_configsDir).list().toList();
    for (final entity in existingFiles) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name.endsWith('.toml') || name.endsWith('.meta.json')) {
        final id = _configIdFromPath(entity.path);
        if (!expectedIds.contains(id)) {
          await entity.delete();
        }
      }
    }

    for (final config in configs) {
      await File(configTomlPath(config.id)).writeAsString(config.toToml());
      await File(configMetaPath(config.id))
          .writeAsString(const JsonEncoder.withIndent('  ').convert({
        'id': config.id,
        'auto_start': config.autoStart,
        'service_enabled': config.serviceEnabled,
        'rpc_port': config.rpcPort,
        'rpc_portal_whitelist': config.rpcPortalWhitelist,
      }));
    }
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

  Future<Map<String, dynamic>> _loadMeta(String configId) async {
    final file = File(configMetaPath(configId));
    if (!await file.exists()) return {};
    try {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  String _configIdFromPath(String path) {
    final fileName = path.split(Platform.pathSeparator).last;
    if (fileName.endsWith('.meta.json')) {
      return fileName.substring(0, fileName.length - '.meta.json'.length);
    }
    if (fileName.endsWith('.toml')) {
      return fileName.substring(0, fileName.length - '.toml'.length);
    }
    return fileName;
  }
}
