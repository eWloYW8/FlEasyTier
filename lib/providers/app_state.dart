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
  static const supportedSchemeVariants = <DynamicSchemeVariant>[
    DynamicSchemeVariant.tonalSpot,
    DynamicSchemeVariant.content,
    DynamicSchemeVariant.neutral,
  ];

  final ConfigStorage _storage = ConfigStorage();
  final EasyTierManager _manager = EasyTierManager();
  Timer? _pollTimer;

  List<NetworkConfig> _configs = [];
  final Map<String, NetworkInstance> _instances = {};
  String? _selectedConfigId;
  ThemeMode _themeMode = ThemeMode.system;
  Color _seedColor = const Color(0xFF00897B);
  DynamicSchemeVariant _schemeVariant = DynamicSchemeVariant.tonalSpot;
  bool _closeToTray = false;
  int _logAutoClearSizeMb = 10;
  final List<AppLogEntry> _appLogs = [];
  final StreamController<AppLogEntry> _errorLogController =
      StreamController<AppLogEntry>.broadcast();

  List<NetworkConfig> get configs => _configs;
  Map<String, NetworkInstance> get instances => _instances;
  String? get selectedConfigId => _selectedConfigId;
  ThemeMode get themeMode => _themeMode;
  Color get seedColor => _seedColor;
  DynamicSchemeVariant get schemeVariant => _schemeVariant;
  bool get closeToTray => _closeToTray;
  int get logAutoClearSizeMb => _logAutoClearSizeMb;
  List<AppLogEntry> get appLogs => List.unmodifiable(_appLogs);
  Stream<AppLogEntry> get errorLogStream => _errorLogController.stream;
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
    final savedSchemeVariant = DynamicSchemeVariant.values
        .elementAtOrNull(settings['scheme_variant'] as int? ?? 2);
    _schemeVariant = _normalizeSchemeVariant(savedSchemeVariant);
    _closeToTray = settings['close_to_tray'] as bool? ?? false;
    _logAutoClearSizeMb =
        (settings['log_auto_clear_size_mb'] as int? ?? 10).clamp(0, 10240);

    await _manager.init();
    _manager.onLog = addLog;
    final clearedLogs = await _manager.clearOversizedLocalLogs(
      _configs,
      maxBytes: _logAutoClearSizeMb * 1024 * 1024,
    );
    if (clearedLogs.clearedFiles > 0) {
      addLog(
        AppLogLevel.info,
        'Auto-cleared ${clearedLogs.clearedFiles} oversized log file(s)',
        category: 'Logs',
        detail:
            '${clearedLogs.clearedBytes ~/ (1024 * 1024)} MB reclaimed',
      );
    }
    await _manager.detectBinaries();
    _manager.onInstanceStopped = _onInstanceExit;

    var normalizedConfigs = false;
    for (int i = 0; i < _configs.length; i++) {
      var normalized = _normalizeConfigForPlatform(_configs[i]);
      normalized = _deduplicateRpcPort(normalized);
      if (!identical(normalized, _configs[i])) {
        _configs[i] = normalized;
        normalizedConfigs = true;
      }
    }
    if (normalizedConfigs) {
      unawaited(_saveConfigs());
    }

    if (savedSchemeVariant != _schemeVariant) {
      unawaited(_saveSettings());
    }

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
    config = _normalizeConfigForPlatform(config);
    config = _deduplicateRpcPort(config);
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
    config = _normalizeConfigForPlatform(config);
    config = _deduplicateRpcPort(config);
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
    if (isRunning(id)) {
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
        autoStart: current.autoStart,
        serviceEnabled: current.serviceEnabled,
        rpcPort: current.rpcPort,
        rpcPortalWhitelist: current.rpcPortalWhitelist,
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
    final currentConfig = configById(configId);
    if (currentConfig == null) return 'Config not found';
    final config = await _ensureRuntimeRpcPort(currentConfig, operation: 'start');
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
      final syncMsg = await _manager.installService(config);
      if (!_isSuccessMessage(syncMsg)) {
        final inst = _instances.putIfAbsent(
          configId,
          () => NetworkInstance(configId: configId),
        );
        inst.running = false;
        inst.managedByService = true;
        inst.errorMessage = syncMsg;
        notifyListeners();
        return syncMsg;
      }
      final msg = await _manager.startService(config);
      if (!_isSuccessMessage(msg)) {
        final inst = _instances.putIfAbsent(
          configId,
          () => NetworkInstance(configId: configId),
        );
        inst.running = false;
        inst.managedByService = true;
        inst.errorMessage = msg;
        notifyListeners();
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

      if (Platform.isAndroid) {
        for (final other in _configs.where(
          (item) => item.id != configId && (_instances[item.id]?.running ?? false),
        )) {
          addLog(
            AppLogLevel.info,
            'Android VPN only supports one active network, stopping ${other.displayName}',
            category: 'VPN',
          );
          await stopInstance(other.id);
        }
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
      notifyListeners();
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
    final activeConfig = configById(configId);
    final inst = _instances[configId];
    if (activeConfig != null) {
      addLog(
        AppLogLevel.info,
        'Stop requested for ${activeConfig.displayName}',
        category: 'Instance',
      );
    }

    if (activeConfig != null &&
        _supportsSystemService &&
        inst?.managedByService == true) {
      final msg = await _manager.stopService(activeConfig);
      if (!_isSuccessMessage(msg)) {
        inst?.errorMessage = msg;
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
    if (activeConfig != null) {
      addLog(
        AppLogLevel.info,
        'Stopped ${activeConfig.displayName}',
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
    if (!_supportsSystemService) {
      return 'System services are only supported on Windows, macOS, and Linux';
    }
    var config = configById(configId);
    if (config == null) return 'Config not found';
    config = await _ensureRuntimeRpcPort(config, operation: 'install service');
    final msg = await _manager.installService(config);
    if (_isSuccessMessage(msg)) {
      updateConfig(config.copyWith(serviceEnabled: true));
      addLog(
        AppLogLevel.info,
        'Installed service for ${config.displayName}',
        category: 'Service',
      );
    }
    return msg;
  }

  Future<String> uninstallService(String configId) async {
    if (!_supportsSystemService) {
      return 'System services are only supported on Windows, macOS, and Linux';
    }
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
    }
    return msg;
  }

  Future<ManagedServiceStatus> serviceStatus(String configId) async {
    if (!_supportsSystemService) return ManagedServiceStatus.notInstalled;
    final config = configById(configId);
    if (config == null) return ManagedServiceStatus.notInstalled;
    return _manager.getServiceStatus(config);
  }

  Future<void> _pollStatus() async {
    bool changed = false;

    for (final config in _configs) {
      if (await _manager.isLocalRunning(config.id)) {
        if (await _pollSingle(config)) changed = true;
        continue;
      }

      final localInst = _instances[config.id];
      if (localInst?.managedByService != true && localInst?.running == true) {
        localInst!.running = false;
        localInst.errorMessage = null;
        changed = true;
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

  void setSchemeVariant(DynamicSchemeVariant variant) {
    _schemeVariant = _normalizeSchemeVariant(variant);
    addLog(
      AppLogLevel.info,
      'Color scheme changed to ${schemeVariantLabel(_schemeVariant)}',
      category: 'UI',
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

  void setLogAutoClearSizeMb(int value) {
    final normalized = value.clamp(0, 10240);
    _logAutoClearSizeMb = normalized;
    addLog(
      AppLogLevel.info,
      normalized == 0
          ? 'Disabled automatic oversized log cleanup'
          : 'Set oversized log cleanup threshold to ${normalized}MB',
      category: 'Logs',
    );
    unawaited(_saveSettings());
    notifyListeners();
  }

  Future<int> clearLocalLogs() async {
    final result = await _manager.clearAllLocalLogs(_configs);
    addLog(
      AppLogLevel.info,
      'Cleared ${result.clearedFiles} local log file(s)',
      category: 'Logs',
      detail: '${result.clearedBytes ~/ 1024} KB removed',
    );
    notifyListeners();
    return result.clearedFiles;
  }

  void addLog(
    AppLogLevel level,
    String message, {
    String category = 'App',
    String? detail,
  }) {
    final entry = AppLogEntry(
      timestamp: DateTime.now(),
      level: level,
      category: category,
      message: message,
      detail: detail,
    );
    _appLogs.insert(0, entry);
    if (_appLogs.length > 1200) {
      _appLogs.removeRange(1200, _appLogs.length);
    }
    if (level == AppLogLevel.error) {
      _errorLogController.add(entry);
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
        'scheme_variant': _schemeVariant.index,
        'close_to_tray': _closeToTray,
        'log_auto_clear_size_mb': _logAutoClearSizeMb,
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

  static DynamicSchemeVariant _normalizeSchemeVariant(
    DynamicSchemeVariant? variant,
  ) {
    if (supportedSchemeVariants.contains(variant)) {
      return variant!;
    }
    return DynamicSchemeVariant.tonalSpot;
  }

  static String schemeVariantLabel(DynamicSchemeVariant variant) {
    switch (_normalizeSchemeVariant(variant)) {
      case DynamicSchemeVariant.tonalSpot:
        return 'Balanced';
      case DynamicSchemeVariant.content:
        return 'Richer';
      case DynamicSchemeVariant.neutral:
        return 'Muted';
      default:
        return 'Balanced';
    }
  }

  bool get _supportsSystemService =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  bool _isSuccessMessage(String msg) {
    final lower = msg.toLowerCase();
    return !lower.startsWith('failed') && !lower.startsWith('error');
  }

  NetworkConfig _normalizeConfigForPlatform(NetworkConfig config) {
    if (_supportsSystemService) return config;
    if (!config.serviceEnabled) return config;
    return config.copyWith(serviceEnabled: false);
  }

  NetworkConfig _deduplicateRpcPort(NetworkConfig config) {
    var desired = config.rpcPort;
    if (desired <= 0) desired = 15888;
    final usedPorts = _configs
        .where((item) => item.id != config.id)
        .map((item) => item.rpcPort)
        .where((port) => port > 0)
        .toSet();
    var next = desired;
    while (usedPorts.contains(next)) {
      next++;
    }
    if (next == config.rpcPort) return config;
    addLog(
      AppLogLevel.info,
      'Adjusted RPC port for ${config.displayName}',
      category: 'RPC',
      detail: '${config.rpcPort} -> $next',
    );
    return config.copyWith(rpcPort: next);
  }

  Future<NetworkConfig> _ensureRuntimeRpcPort(
    NetworkConfig config, {
    required String operation,
  }) async {
    var updated = _deduplicateRpcPort(config);
    if (updated.rpcPort <= 0) {
      updated = updated.copyWith(rpcPort: 15888);
    }

    if (await _canBindRpcPort(updated.rpcPort)) {
      if (updated.rpcPort != config.rpcPort) {
        updateConfig(updated);
      }
      return updated;
    }

    final next = await _findAvailableRpcPort(
      preferred: updated.rpcPort + 1,
      excludeConfigId: updated.id,
    );
    final reassigned = updated.copyWith(rpcPort: next);
    addLog(
      AppLogLevel.warning,
      'RPC port ${updated.rpcPort} is unavailable for ${updated.displayName}',
      category: 'RPC',
      detail: 'Reassigned to $next before $operation',
    );
    updateConfig(reassigned);
    return reassigned;
  }

  Future<int> _findAvailableRpcPort({
    required int preferred,
    required String excludeConfigId,
  }) async {
    var port = preferred <= 0 ? 15888 : preferred;
    final usedPorts = _configs
        .where((item) => item.id != excludeConfigId)
        .map((item) => item.rpcPort)
        .where((value) => value > 0)
        .toSet();
    while (usedPorts.contains(port) || !await _canBindRpcPort(port)) {
      port++;
      if (port > 65535) {
        port = 15888;
      }
    }
    return port;
  }

  Future<bool> _canBindRpcPort(int port) async {
    if (port <= 0 || port > 65535) return false;
    ServerSocket? socket;
    try {
      socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: false,
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      await socket?.close();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _errorLogController.close();
    _manager.stopAll();
    super.dispose();
  }
}
