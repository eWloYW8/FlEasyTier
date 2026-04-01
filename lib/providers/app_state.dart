import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

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

  // ── Getters ──

  List<NetworkConfig> get configs => _configs;
  Map<String, NetworkInstance> get instances => _instances;
  String? get selectedConfigId => _selectedConfigId;
  ThemeMode get themeMode => _themeMode;
  Color get seedColor => _seedColor;
  bool get closeToTray => _closeToTray;
  EasyTierManager get manager => _manager;

  String? get coreBinaryPath => _manager.coreBinaryPath;

  NetworkConfig? get selectedConfig => _selectedConfigId != null
      ? _configs.where((c) => c.id == _selectedConfigId).firstOrNull
      : null;

  NetworkInstance? instanceFor(String configId) => _instances[configId];

  bool isRunning(String configId) => _manager.isRunning(configId);

  bool get hasRunningInstances =>
      _configs.any((c) => _manager.isRunning(c.id));

  // ── Initialization ──

  Future<void> initialize() async {
    await _storage.initialize();
    _configs = await _storage.loadConfigs();

    final settings = await _storage.loadSettings();
    _manager.coreBinaryPath = settings['core_binary_path'] as String?;
    _themeMode = ThemeMode.values.elementAtOrNull(
            settings['theme_mode'] as int? ?? 0) ??
        ThemeMode.system;
    _seedColor = Color(settings['seed_color'] as int? ?? 0xFF00897B);
    _closeToTray = settings['close_to_tray'] as bool? ?? false;

    await _manager.init();
    await _manager.detectBinaries();

    _manager.onInstanceStopped = _onInstanceExit;

    if (_configs.isNotEmpty) {
      _selectedConfigId = _configs.first.id;
    }

    _pollTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _pollStatus());

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      for (final c in _configs.where((c) => c.autoStart)) {
        startInstance(c.id);
      }
    }
  }

  void _onInstanceExit(String configId, int exitCode) {
    final inst = _instances[configId];
    if (inst != null) {
      inst.running = false;
      inst.errorMessage =
          exitCode == 0 ? null : 'Process exited with code $exitCode';
    }
    notifyListeners();
  }

  // ── Config CRUD ──

  void addConfig(NetworkConfig config) {
    _configs.add(config);
    _selectedConfigId = config.id;
    _saveConfigs();
    notifyListeners();
  }

  void updateConfig(NetworkConfig config) {
    final i = _configs.indexWhere((c) => c.id == config.id);
    if (i >= 0) {
      _configs[i] = config;
      _saveConfigs();
      notifyListeners();
    }
  }

  void removeConfig(String id) {
    if (_manager.isRunning(id)) {
      _manager.stopInstance(id);
    }
    _configs.removeWhere((c) => c.id == id);
    _instances.remove(id);
    if (_selectedConfigId == id) {
      _selectedConfigId = _configs.isNotEmpty ? _configs.first.id : null;
    }
    _saveConfigs();
    notifyListeners();
  }

  void selectConfig(String id) {
    _selectedConfigId = id;
    notifyListeners();
  }

  NetworkConfig? configById(String id) =>
      _configs.where((c) => c.id == id).firstOrNull;

  // ── Config import/export ──

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
        return null;
      } else if (decoded is List) {
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            item.remove('id');
            addConfig(NetworkConfig.fromJson(item));
          }
        }
        return null;
      }
      return 'Invalid JSON format';
    } catch (e) {
      return 'JSON parse error: $e';
    }
  }

  // ── Instance lifecycle ──

  Future<String?> startInstance(String configId) async {
    final config = configById(configId);
    if (config == null) return 'Config not found';

    if (PlatformVpn.needsSystemVpn) {
      final granted = await PlatformVpn.prepareVpn();
      if (!granted) return 'VPN permission denied';

      final ip =
          config.virtualIpv4.isNotEmpty ? config.virtualIpv4 : '10.0.0.1';
      await PlatformVpn.startVpn(
        ipv4: ip.split('/').first,
        cidr: 24,
        mtu: config.mtu,
        routes: config.proxyCidrs.isNotEmpty
            ? config.proxyCidrs
            : ['0.0.0.0/0'],
      );
    }

    final err = await _manager.startInstance(config);
    if (err != null) {
      if (PlatformVpn.needsSystemVpn) await PlatformVpn.stopVpn();
      return err;
    }

    _instances[configId] = NetworkInstance(
      configId: configId,
      running: true,
      startTime: DateTime.now(),
    );
    notifyListeners();

    Future.delayed(const Duration(seconds: 2), () {
      _pollSingle(config);
    });

    return null;
  }

  Future<void> stopInstance(String configId) async {
    await _manager.stopInstance(configId);
    if (PlatformVpn.needsSystemVpn) {
      await PlatformVpn.stopVpn();
    }
    final inst = _instances[configId];
    if (inst != null) {
      inst.running = false;
      inst.errorMessage = null;
    }
    notifyListeners();
  }

  Future<void> toggleInstance(String configId) async {
    if (_manager.isRunning(configId)) {
      await stopInstance(configId);
    } else {
      await startInstance(configId);
    }
  }

  // ── System service ──

  Future<String> installService() async {
    if (_manager.coreBinaryPath == null) return 'Core binary not found';
    try {
      final result = await Process.run(
        _manager.coreBinaryPath!,
        ['service', 'install'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      return result.exitCode == 0
          ? 'Service installed'
          : 'Failed: ${result.stderr}'.trim();
    } catch (e) {
      return 'Error: $e';
    }
  }

  Future<String> uninstallService() async {
    if (_manager.coreBinaryPath == null) return 'Core binary not found';
    try {
      final result = await Process.run(
        _manager.coreBinaryPath!,
        ['service', 'uninstall'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      return result.exitCode == 0
          ? 'Service uninstalled'
          : 'Failed: ${result.stderr}'.trim();
    } catch (e) {
      return 'Error: $e';
    }
  }

  // ── Status polling ──

  Future<void> _pollStatus() async {
    bool changed = false;
    for (final config in _configs) {
      if (!_manager.isRunning(config.id)) continue;
      if (await _pollSingle(config)) changed = true;
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
      ]);

      inst.nodeInfo = results[0] as NodeInfo?;
      inst.routes = results[1] as List<PeerRouteInfo>;
      inst.peerConns = results[2] as List<PeerConnInfo>;
      inst.errorMessage = null;
      return true;
    } catch (e) {
      inst.errorMessage = e.toString();
      return true;
    }
  }

  // ── Settings ──

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _saveSettings();
    notifyListeners();
  }

  void setSeedColor(Color color) {
    _seedColor = color;
    _saveSettings();
    notifyListeners();
  }

  void setCloseToTray(bool value) {
    _closeToTray = value;
    _saveSettings();
    notifyListeners();
  }

  void setCoreBinaryPath(String? path) {
    _manager.coreBinaryPath = path;
    _saveSettings();
    notifyListeners();
  }

  Future<void> _saveConfigs() => _storage.saveConfigs(_configs);

  Future<void> _saveSettings() => _storage.saveSettings({
        'core_binary_path': _manager.coreBinaryPath,
        'theme_mode': _themeMode.index,
        'seed_color': _seedColor.toARGB32(),
        'close_to_tray': _closeToTray,
      });

  @override
  void dispose() {
    _pollTimer?.cancel();
    _manager.stopAll();
    super.dispose();
  }
}
