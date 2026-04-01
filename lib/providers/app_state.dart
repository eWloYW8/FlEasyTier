import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/app_log_entry.dart';
import '../models/network_config.dart';
import '../models/network_instance.dart';
import '../services/config_storage.dart';
import '../services/easytier_manager.dart';
import '../services/platform_vpn.dart';

class AppState extends ChangeNotifier {
  final ConfigStorage _storage = ConfigStorage();
  final EasyTierManager _manager = EasyTierManager();
  Timer? _pollTimer;

  List<NetworkConfig> _configs = [];
  final Map<String, NetworkInstance> _instances = {};
  String? _selectedConfigId;
  ThemeMode _themeMode = ThemeMode.system;
  Color _seedColor = const Color(0xFF00897B);
  bool _closeToTray = false;
  final List<AppLogEntry> _appLogs = [];

  List<NetworkConfig> get configs => _configs;
  Map<String, NetworkInstance> get instances => _instances;
  String? get selectedConfigId => _selectedConfigId;
  ThemeMode get themeMode => _themeMode;
  Color get seedColor => _seedColor;
  bool get closeToTray => _closeToTray;
  List<AppLogEntry> get appLogs => List.unmodifiable(_appLogs);
  EasyTierManager get manager => _manager;
  bool get canEditCoreBinaryPath =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  String? get coreBinaryPath => _manager.coreBinaryPath;

  NetworkConfig? get selectedConfig => _selectedConfigId != null
      ? _configs.where((c) => c.id == _selectedConfigId).firstOrNull
      : null;

  NetworkInstance? instanceFor(String configId) => _instances[configId];

  bool isRunning(String configId) => _instances[configId]?.running ?? false;

  bool get hasRunningInstances =>
      _configs.any((config) => _instances[config.id]?.running ?? false);

  Future<void> initialize() async {
    addLog(
      AppLogLevel.info,
      'Initializing FlEasyTier application',
      category: 'App',
    );
    await _storage.initialize();
    _configs = await _storage.loadConfigs();
    addLog(
      AppLogLevel.info,
      'Loaded ${_configs.length} network configuration(s)',
      category: 'Storage',
    );

    final settings = await _storage.loadSettings();
    _manager.coreBinaryPath = canEditCoreBinaryPath
        ? _normalizeBinaryPath(settings['core_binary_path'] as String?)
        : null;
    _themeMode = ThemeMode.values.elementAtOrNull(
            settings['theme_mode'] as int? ?? 0) ??
        ThemeMode.system;
    _seedColor = Color(settings['seed_color'] as int? ?? 0xFF00897B);
    _closeToTray = settings['close_to_tray'] as bool? ?? false;

    await _manager.init();
    _manager.onLog = addLog;
    await _manager.detectBinaries();
    _manager.onInstanceStopped = _onInstanceExit;

    if (_configs.isNotEmpty) {
      _selectedConfigId = _configs.first.id;
    }

    _pollTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _pollStatus());
    await _pollStatus();

    if (_supportsSystemService) {
      for (final config in _configs.where(
          (config) => config.autoStart && !config.serviceEnabled)) {
        addLog(
          AppLogLevel.info,
          'Auto-start queued for ${config.displayName}',
          category: 'Startup',
        );
        unawaited(startInstance(config.id));
      }
    }
  }

  void _onInstanceExit(String configId, int exitCode, String? detail) {
    final inst = _instances[configId];
    final config = configById(configId);
    if (inst != null) {
      inst.running = false;
      inst.errorMessage = exitCode == 0
          ? null
          : (detail?.trim().isNotEmpty == true
              ? detail!.trim()
              : 'Process exited with code $exitCode');
    }
    addLog(
      exitCode == 0 ? AppLogLevel.info : AppLogLevel.warning,
      '${config?.displayName ?? configId} exited with code $exitCode',
      category: 'Instance',
      detail: detail,
    );
    notifyListeners();
  }

  void addConfig(NetworkConfig config) {
    _configs.add(config);
    _selectedConfigId = config.id;
    addLog(
      AppLogLevel.info,
      'Added network ${config.displayName}',
      category: 'Config',
    );
    unawaited(_saveConfigs());
    notifyListeners();
  }

  void updateConfig(NetworkConfig config) {
    final index = _configs.indexWhere((c) => c.id == config.id);
    if (index < 0) return;
    _configs[index] = config;
    addLog(
      AppLogLevel.info,
      'Updated network ${config.displayName}',
      category: 'Config',
    );
    unawaited(_saveConfigs());
    notifyListeners();
  }

  void removeConfig(String id) {
    final removed = configById(id);
    if (_manager.isRunning(id)) {
      unawaited(_manager.stopInstance(id));
    }
    _configs.removeWhere((c) => c.id == id);
    _instances.remove(id);
    if (_selectedConfigId == id) {
      _selectedConfigId = _configs.isNotEmpty ? _configs.first.id : null;
    }
    addLog(
      AppLogLevel.warning,
      'Removed network ${removed?.displayName ?? id}',
      category: 'Config',
    );
    unawaited(_saveConfigs());
    notifyListeners();
  }

  void selectConfig(String id) {
    _selectedConfigId = id;
    notifyListeners();
  }

  NetworkConfig? configById(String id) =>
      _configs.where((c) => c.id == id).firstOrNull;

  String exportConfigJson(String configId) {
    final config = configById(configId);
    if (config == null) return '';
    return const JsonEncoder.withIndent('  ').convert(config.toJson());
  }

  String exportAllConfigsJson() {
    return const JsonEncoder.withIndent('  ')
        .convert(_configs.map((c) => c.toJson()).toList());
  }

  String? importConfigJson(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) {
        decoded.remove('id');
        addConfig(NetworkConfig.fromJson(decoded));
        addLog(
          AppLogLevel.info,
          'Imported one network configuration from JSON',
          category: 'Import',
        );
        return null;
      }
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            item.remove('id');
            addConfig(NetworkConfig.fromJson(item));
          }
        }
        addLog(
          AppLogLevel.info,
          'Imported ${decoded.length} configuration item(s) from JSON',
          category: 'Import',
        );
        return null;
      }
      return 'Invalid JSON format';
    } catch (e) {
      addLog(
        AppLogLevel.error,
        'JSON import failed',
        category: 'Import',
        detail: e.toString(),
      );
      return 'JSON parse error: $e';
    }
  }

  Future<String?> updateConfigToml(String configId, String toml) async {
    final current = configById(configId);
    if (current == null) return 'Config not found';

    try {
      final parsed = NetworkConfig.fromToml(
        toml,
        id: current.id,
        configName: current.configName,
        autoStart: current.autoStart,
        serviceEnabled: current.serviceEnabled,
      );
      updateConfig(parsed);
      addLog(
        AppLogLevel.info,
        'Saved TOML for ${current.displayName}',
        category: 'TOML',
      );
      return null;
    } catch (e) {
      addLog(
        AppLogLevel.error,
        'TOML parse failed for ${current.displayName}',
        category: 'TOML',
        detail: e.toString(),
      );
      return 'TOML parse error: $e';
    }
  }

  Future<String?> startInstance(String configId) async {
    final config = configById(configId);
    if (config == null) return 'Config not found';
    addLog(
      AppLogLevel.info,
      'Start requested for ${config.displayName}',
      category: 'Instance',
    );

    final validationError = await _manager.validateLocalStart(config);
    if (validationError != null) {
      final inst = _instances.putIfAbsent(
        configId,
        () => NetworkInstance(configId: configId),
      );
      inst.running = false;
      inst.managedByService = false;
      inst.errorMessage = validationError;
      addLog(
        AppLogLevel.error,
        'Preflight checks failed for ${config.displayName}',
        category: 'Instance',
        detail: validationError,
      );
      notifyListeners();
      return validationError;
    }

    if (_supportsSystemService && config.serviceEnabled) {
      final msg = await _manager.startService(config);
      if (!_isSuccessMessage(msg)) {
        addLog(
          AppLogLevel.error,
          'Service start failed for ${config.displayName}',
          category: 'Service',
          detail: msg,
        );
        return msg;
      }

      final inst = _instances.putIfAbsent(
        configId,
        () => NetworkInstance(configId: configId),
      );
      inst.running = true;
      inst.managedByService = true;
      inst.startTime ??= DateTime.now();
      inst.errorMessage = null;
      addLog(
        AppLogLevel.info,
        'Service started for ${config.displayName}',
        category: 'Service',
      );
      notifyListeners();

      Future.delayed(const Duration(seconds: 2), () {
        _pollSingle(config);
      });
      return null;
    }

    if (PlatformVpn.needsSystemVpn) {
      final granted = await PlatformVpn.prepareVpn();
      if (!granted) {
        addLog(
          AppLogLevel.warning,
          'VPN permission denied for ${config.displayName}',
          category: 'VPN',
        );
        return 'VPN permission denied';
      }

      final ip =
          config.virtualIpv4.isNotEmpty ? config.virtualIpv4 : '10.0.0.1';
      await PlatformVpn.startVpn(
        ipv4: ip.split('/').first,
        cidr: 24,
        mtu: config.mtu,
        routes:
            config.proxyCidrs.isNotEmpty ? config.proxyCidrs : ['0.0.0.0/0'],
      );
    }

    final err = await _manager.startInstance(config);
    if (err != null) {
      final inst = _instances.putIfAbsent(
        configId,
        () => NetworkInstance(configId: configId),
      );
      inst.running = false;
      inst.managedByService = false;
      inst.errorMessage = err;
      if (PlatformVpn.needsSystemVpn) await PlatformVpn.stopVpn();
      addLog(
        AppLogLevel.error,
        'Failed to start ${config.displayName}',
        category: 'Instance',
        detail: err,
      );
      return err;
    }

    _instances[configId] = NetworkInstance(
      configId: configId,
      running: true,
      managedByService: false,
      startTime: DateTime.now(),
    );
    addLog(
      AppLogLevel.info,
      'Instance started for ${config.displayName}',
      category: 'Instance',
    );
    notifyListeners();

    Future.delayed(const Duration(seconds: 2), () {
      _pollSingle(config);
    });

    return null;
  }

  Future<void> stopInstance(String configId) async {
    final config = configById(configId);
    final inst = _instances[configId];
    if (config != null) {
      addLog(
        AppLogLevel.info,
        'Stop requested for ${config.displayName}',
        category: 'Instance',
      );
    }

    if (config != null &&
        _supportsSystemService &&
        inst?.managedByService == true) {
      final msg = await _manager.stopService(config);
      if (!_isSuccessMessage(msg)) {
        inst?.errorMessage = msg;
        addLog(
          AppLogLevel.error,
          'Service stop failed for ${config.displayName}',
          category: 'Service',
          detail: msg,
        );
        notifyListeners();
        return;
      }
    } else {
      await _manager.stopInstance(configId);
    }

    if (PlatformVpn.needsSystemVpn) {
      await PlatformVpn.stopVpn();
    }
    if (inst != null) {
      inst.running = false;
      inst.errorMessage = null;
    }
    if (config != null) {
      addLog(
        AppLogLevel.info,
        'Stopped ${config.displayName}',
        category: inst?.managedByService == true ? 'Service' : 'Instance',
      );
    }
    notifyListeners();
  }

  Future<void> toggleInstance(String configId) async {
    if (isRunning(configId)) {
      await stopInstance(configId);
    } else {
      await startInstance(configId);
    }
  }

  Future<String> installService(String configId) async {
    final config = configById(configId);
    if (config == null) return 'Config not found';
    final msg = await _manager.installService(config);
    if (_isSuccessMessage(msg)) {
      updateConfig(config.copyWith(serviceEnabled: true));
      addLog(
        AppLogLevel.info,
        'Installed service for ${config.displayName}',
        category: 'Service',
      );
    } else {
      addLog(
        AppLogLevel.error,
        'Service install failed for ${config.displayName}',
        category: 'Service',
        detail: msg,
      );
    }
    return msg;
  }

  Future<String> uninstallService(String configId) async {
    final config = configById(configId);
    if (config == null) return 'Config not found';
    final msg = await _manager.uninstallService(config);
    if (_isSuccessMessage(msg)) {
      final inst = _instances[configId];
      if (inst?.managedByService == true) {
        inst!.running = false;
        inst.errorMessage = null;
      }
      updateConfig(config.copyWith(serviceEnabled: false));
      addLog(
        AppLogLevel.info,
        'Uninstalled service for ${config.displayName}',
        category: 'Service',
      );
    } else {
      addLog(
        AppLogLevel.error,
        'Service uninstall failed for ${config.displayName}',
        category: 'Service',
        detail: msg,
      );
    }
    return msg;
  }

  Future<ManagedServiceStatus> serviceStatus(String configId) async {
    final config = configById(configId);
    if (config == null) return ManagedServiceStatus.notInstalled;
    return _manager.getServiceStatus(config);
  }

  Future<void> _pollStatus() async {
    bool changed = false;

    for (final config in _configs) {
      if (_manager.isRunning(config.id)) {
        if (await _pollSingle(config)) changed = true;
        continue;
      }

      if (_supportsSystemService && config.serviceEnabled) {
        final status = await _manager.getServiceStatus(config);
        final inst = _instances[config.id];

        if (status == ManagedServiceStatus.running) {
          final current = inst ??
              (_instances[config.id] = NetworkInstance(configId: config.id));
          current.running = true;
          current.managedByService = true;
          current.startTime ??= DateTime.now();
          if (await _pollSingle(config)) changed = true;
        } else if (inst?.managedByService == true && inst!.running) {
          inst.running = false;
          inst.errorMessage = null;
          changed = true;
        }
      }
    }

    if (changed) notifyListeners();
  }

  Future<bool> _pollSingle(NetworkConfig config) async {
    final inst = _instances[config.id];
    if (inst == null || !inst.running) return false;

    try {
      final results = await Future.wait([
        _manager.getNodeInfo(config.rpcPort),
        _manager.getRoutes(config.rpcPort),
        _manager.getPeerConnections(config.rpcPort),
        _manager.getStats(config.rpcPort),
      ]);

      inst.nodeInfo = results[0] as NodeInfo?;
      inst.routes = results[1] as List<PeerRouteInfo>;
      inst.peerConns = results[2] as List<PeerConnInfo>;
      inst.metrics = results[3] as List<MetricSnapshot>;
      inst.errorMessage = null;
      return true;
    } catch (e) {
      final nextError = e.toString();
      if (inst.errorMessage != nextError) {
        addLog(
          AppLogLevel.warning,
          'Polling failed for ${config.displayName}',
          category: 'RPC',
          detail: nextError,
        );
      }
      inst.errorMessage = nextError;
      return true;
    }
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    addLog(
      AppLogLevel.info,
      'Theme mode changed to ${mode.name}',
      category: 'UI',
    );
    unawaited(_saveSettings());
    notifyListeners();
  }

  void setSeedColor(Color color) {
    _seedColor = color;
    addLog(
      AppLogLevel.info,
      'Accent color changed',
      category: 'UI',
      detail: color.toARGB32().toRadixString(16),
    );
    unawaited(_saveSettings());
    notifyListeners();
  }

  void setCloseToTray(bool value) {
    _closeToTray = value;
    addLog(
      AppLogLevel.info,
      value ? 'Enabled close-to-tray' : 'Disabled close-to-tray',
      category: 'UI',
    );
    unawaited(_saveSettings());
    notifyListeners();
  }

  void setCoreBinaryPath(String? path) {
    if (!canEditCoreBinaryPath) return;
    final normalized = _normalizeBinaryPath(path);
    _manager.coreBinaryPath = normalized;
    addLog(
      AppLogLevel.info,
      'Updated easytier-core binary path',
      category: 'Binary',
      detail: normalized,
    );
    unawaited(_saveSettings());
    notifyListeners();
  }

  void addLog(
    AppLogLevel level,
    String message, {
    String category = 'App',
    String? detail,
  }) {
    _appLogs.insert(
      0,
      AppLogEntry(
        timestamp: DateTime.now(),
        level: level,
        category: category,
        message: message,
        detail: detail,
      ),
    );
    if (_appLogs.length > 1200) {
      _appLogs.removeRange(1200, _appLogs.length);
    }
    notifyListeners();
  }

  void clearAppLogs() {
    _appLogs.clear();
    addLog(
      AppLogLevel.info,
      'Cleared application logs',
      category: 'Logs',
    );
  }

  String exportAppLogsText() {
    return _appLogs.reversed.map((entry) => entry.toPlainText()).join('\n\n');
  }

  Future<void> _saveConfigs() => _storage.saveConfigs(_configs);

  Future<void> _saveSettings() => _storage.saveSettings({
        'core_binary_path': _manager.coreBinaryPath,
        'theme_mode': _themeMode.index,
        'seed_color': _seedColor.toARGB32(),
        'close_to_tray': _closeToTray,
      });

  String? _normalizeBinaryPath(String? path) {
    var value = path?.trim() ?? '';
    if (value.isEmpty) return null;

    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1).trim();
    }

    return value.isEmpty ? null : value;
  }

  bool get _supportsSystemService =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  bool _isSuccessMessage(String msg) {
    final lower = msg.toLowerCase();
    return !lower.startsWith('failed') && !lower.startsWith('error');
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _manager.stopAll();
    super.dispose();
  }
}
