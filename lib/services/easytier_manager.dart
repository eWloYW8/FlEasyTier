import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/network_config.dart';
import '../models/network_instance.dart';
import '../rpc/easytier_api.dart';
import '../rpc/rpc_client.dart';

class EasyTierManager {
  String? coreBinaryPath;
  late String _configDir;

  final Map<String, Process> _processes = {};
  final Map<String, StreamSubscription<int>> _exitSubs = {};
  final Map<String, List<String>> _processLogs = {};
  final Map<String, EasyTierApi> _rpcClients = {};

  void Function(String configId, int exitCode)? onInstanceStopped;

  // ── Init ──

  Future<void> init() async {
    final appDir = await getApplicationSupportDirectory();
    _configDir = '${appDir.path}${Platform.pathSeparator}FlEasyTier'
        '${Platform.pathSeparator}configs';
    await Directory(_configDir).create(recursive: true);
  }

  /// Path to the TOML config file for a given config ID.
  String tomlPathFor(String configId) =>
      '$_configDir${Platform.pathSeparator}$configId.toml';

  // ── Binary detection ──

  Future<void> detectBinaries() async {
    final ext = Platform.isWindows ? '.exe' : '';
    final coreName = 'easytier-core$ext';

    final searchDirs = <String>[
      _exeDir,
      '$_exeDir/bin',
      '$_exeDir/easytier',
    ];

    if (Platform.isWindows) {
      searchDirs.addAll([
        'D:/Project/EasyTier/target/release',
        'D:/Project/EasyTier/target/debug',
        'C:/Program Files/EasyTier',
      ]);
    } else if (Platform.isLinux) {
      searchDirs.addAll([
        '/usr/local/bin',
        '/usr/bin',
        '${Platform.environment['HOME']}/easytier',
      ]);
    } else if (Platform.isMacOS) {
      searchDirs.addAll([
        '/usr/local/bin',
        '/opt/homebrew/bin',
        '${Platform.environment['HOME']}/easytier',
      ]);
    }

    for (final dir in searchDirs) {
      if (coreBinaryPath == null) {
        final p = '$dir/$coreName';
        if (await File(p).exists()) coreBinaryPath = p;
      }
      if (coreBinaryPath != null) break;
    }

    coreBinaryPath ??= await _which(coreName);
  }

  String get _exeDir {
    final exe = Platform.resolvedExecutable;
    return exe.substring(0, exe.lastIndexOf(Platform.isWindows ? '\\' : '/'));
  }

  Future<String?> _which(String name) async {
    try {
      final cmd = Platform.isWindows ? 'where' : 'which';
      final r = await Process.run(cmd, [name],
          stdoutEncoding: utf8, stderrEncoding: utf8);
      if (r.exitCode == 0) {
        return (r.stdout as String).trim().split('\n').first.trim();
      }
    } catch (_) {}
    return null;
  }

  // ── Instance lifecycle ──

  Future<String?> startInstance(NetworkConfig config) async {
    if (coreBinaryPath == null) return 'EasyTier core binary not found';
    if (_processes.containsKey(config.id)) return 'Already running';

    try {
      // Write TOML config file
      final tomlPath = tomlPathFor(config.id);
      await File(tomlPath).writeAsString(config.toToml());

      final args = ['-c', tomlPath];
      final process = await Process.start(coreBinaryPath!, args,
          mode: ProcessStartMode.normal);

      _processes[config.id] = process;
      _processLogs[config.id] = [];

      final logs = _processLogs[config.id]!;
      process.stdout.transform(utf8.decoder).listen((data) {
        for (final line in data.split('\n')) {
          if (line.trim().isNotEmpty) {
            logs.add(line.trim());
            if (logs.length > 500) logs.removeAt(0);
          }
        }
      });
      process.stderr.transform(utf8.decoder).listen((data) {
        for (final line in data.split('\n')) {
          if (line.trim().isNotEmpty) {
            logs.add('[ERR] ${line.trim()}');
            if (logs.length > 500) logs.removeAt(0);
          }
        }
      });

      _exitSubs[config.id] = process.exitCode.asStream().listen((code) {
        _processes.remove(config.id);
        _exitSubs.remove(config.id)?.cancel();
        _closeRpcClient(config.id);
        onInstanceStopped?.call(config.id, code);
      });

      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> stopInstance(String configId) async {
    final process = _processes.remove(configId);
    _exitSubs.remove(configId)?.cancel();
    _processLogs.remove(configId);
    _closeRpcClient(configId);
    if (process != null) {
      process.kill(ProcessSignal.sigterm);
      Future.delayed(const Duration(seconds: 3), () {
        try {
          process.kill(ProcessSignal.sigkill);
        } catch (_) {}
      });
    }
  }

  bool isRunning(String configId) => _processes.containsKey(configId);

  List<String> getLogs(String configId) => _processLogs[configId] ?? [];

  // ── RPC client management ──

  EasyTierApi _getOrCreateClient(int rpcPort) {
    final key = '$rpcPort';
    return _rpcClients.putIfAbsent(
        key, () => EasyTierApi(host: '127.0.0.1', port: rpcPort));
  }

  void _closeRpcClient(String configId) {
    // Close all clients — we key by port, but on stop we don't know the port.
    // This is fine since instances are 1:1 with ports and we recreate on next poll.
    // We'll just let them be GC'd; close is best-effort.
  }

  Future<void> _ensureConnected(EasyTierApi api) async {
    if (!api.connected) {
      await api.connect();
    }
  }

  // ── RPC queries (direct protocol, no CLI needed) ──

  Future<NodeInfo?> getNodeInfo(int rpcPort) async {
    final api = _getOrCreateClient(rpcPort);
    try {
      await _ensureConnected(api);
      return await api.getNodeInfo();
    } on RpcException {
      return null;
    } catch (_) {
      // Connection failed — drop client so it reconnects next time
      _rpcClients.remove('$rpcPort');
      return null;
    }
  }

  Future<List<PeerRouteInfo>> getRoutes(int rpcPort) async {
    final api = _getOrCreateClient(rpcPort);
    try {
      await _ensureConnected(api);
      return await api.listRoutes();
    } on RpcException {
      return [];
    } catch (_) {
      _rpcClients.remove('$rpcPort');
      return [];
    }
  }

  Future<List<PeerConnInfo>> getPeerConnections(int rpcPort) async {
    final api = _getOrCreateClient(rpcPort);
    try {
      await _ensureConnected(api);
      return await api.listPeers();
    } on RpcException {
      return [];
    } catch (_) {
      _rpcClients.remove('$rpcPort');
      return [];
    }
  }

  Future<void> stopAll() async {
    for (final id in _processes.keys.toList()) {
      await stopInstance(id);
    }
    for (final api in _rpcClients.values) {
      await api.close();
    }
    _rpcClients.clear();
  }
}
