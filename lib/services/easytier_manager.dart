import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/app_log_entry.dart';
import '../models/network_config.dart';
import '../models/network_instance.dart';
import '../rpc/easytier_api.dart';
import '../rpc/rpc_client.dart';

typedef AppLogWriter = void Function(
  AppLogLevel level,
  String message, {
  String category,
  String? detail,
});

class EasyTierManager {
  String? coreBinaryPath;
  late String _configDir;

  final Map<String, Process> _processes = {};
  final Map<String, StreamSubscription<int>> _exitSubs = {};
  final Map<String, List<String>> _processLogs = {};
  final Map<String, EasyTierApi> _rpcClients = {};

  void Function(String configId, int exitCode, String? detail)? onInstanceStopped;
  AppLogWriter? onLog;

  Future<void> init() async {
    final appDir = await getApplicationSupportDirectory();
    _configDir = '${appDir.path}${Platform.pathSeparator}FlEasyTier'
        '${Platform.pathSeparator}configs';
    await Directory(_configDir).create(recursive: true);
  }

  String tomlPathFor(String configId) =>
      '$_configDir${Platform.pathSeparator}$configId.toml';

  String metaPathFor(String configId) =>
      '$_configDir${Platform.pathSeparator}$configId.meta.json';

  Future<void> detectBinaries() async {
    if (coreBinaryPath != null && !await File(coreBinaryPath!).exists()) {
      coreBinaryPath = null;
    }

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
      coreBinaryPath ??= await _detectBinaryInDir(dir, coreName);
      if (coreBinaryPath != null) break;
    }

    coreBinaryPath ??= await _which(coreName);
    onLog?.call(
      AppLogLevel.info,
      coreBinaryPath != null
          ? 'Detected easytier-core binary'
          : 'Unable to auto-detect easytier-core binary',
      category: 'Binary',
      detail: coreBinaryPath,
    );
  }

  String get _exeDir {
    final exe = Platform.resolvedExecutable;
    return exe.substring(0, exe.lastIndexOf(Platform.isWindows ? '\\' : '/'));
  }

  Future<String?> _which(String name) async {
    try {
      final cmd = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(
        cmd,
        [name],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode == 0) {
        return (result.stdout as String).trim().split('\n').first.trim();
      }
    } catch (_) {}
    return null;
  }

  Future<String?> startInstance(NetworkConfig config) async {
    if (coreBinaryPath == null) return 'EasyTier core binary not found';
    if (_processes.containsKey(config.id)) return 'Already running';

    try {
      onLog?.call(
        AppLogLevel.info,
        'Starting network instance ${config.displayName}',
        category: 'Instance',
        detail: config.toCliArgs().join(' '),
      );
      final process = await Process.start(
        coreBinaryPath!,
        config.toCliArgs(),
        mode: ProcessStartMode.normal,
      );

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
        final detail = _buildExitDetail(config.id, code);
        onLog?.call(
          code == 0 ? AppLogLevel.info : AppLogLevel.warning,
          'Instance ${config.displayName} exited with code $code',
          category: 'Instance',
          detail: detail,
        );
        onInstanceStopped?.call(config.id, code, detail);
      });

      return null;
    } catch (e) {
      onLog?.call(
        AppLogLevel.error,
        'Failed to start instance ${config.displayName}',
        category: 'Instance',
        detail: e.toString(),
      );
      return e.toString();
    }
  }

  Future<void> stopInstance(String configId) async {
    onLog?.call(
      AppLogLevel.info,
      'Stopping local instance $configId',
      category: 'Instance',
    );
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

  List<String> getLogs(String configId, {NetworkConfig? config}) {
    final processLogs = _processLogs[configId];
    if (processLogs != null && processLogs.isNotEmpty) {
      return processLogs;
    }

    final logFile = _serviceLogFileFor(configId, config: config);
    if (!logFile.existsSync()) return const [];

    try {
      return _readLogTail(logFile);
    } catch (_) {
      return const [];
    }
  }

  Future<LogCleanupResult> clearAllLocalLogs(List<NetworkConfig> configs) {
    return _cleanupLocalLogs(
      configs,
      shouldClear: (_) => true,
    );
  }

  Future<LogCleanupResult> clearOversizedLocalLogs(
    List<NetworkConfig> configs, {
    required int maxBytes,
  }) {
    if (maxBytes <= 0) {
      return Future.value(const LogCleanupResult());
    }
    return _cleanupLocalLogs(
      configs,
      shouldClear: (file) => file.lengthSync() > maxBytes,
    );
  }

  Future<String?> validateLocalStart(NetworkConfig config) async {
    if (coreBinaryPath == null) {
      return 'EasyTier core binary not found';
    }
    if (!await File(coreBinaryPath!).exists()) {
      return 'easytier-core binary does not exist: $coreBinaryPath';
    }

    if (Platform.isWindows &&
        !config.noTun &&
        !config.useSmoltcp &&
        !config.serviceEnabled) {
      final hasWintun = await _hasWintun();
      if (!hasWintun) {
        return 'wintun.dll was not found next to easytier-core.exe';
      }

      final elevated = await _isWindowsElevated();
      if (!elevated) {
        return 'Windows TUN mode requires Administrator privileges. Run FlEasyTier as Administrator, or enable No TUN / Use smoltcp.';
      }
    }

    if (Platform.isLinux && !config.noTun && !config.useSmoltcp) {
      final isRoot = Platform.environment['USER'] == 'root';
      if (!isRoot) {
        onLog?.call(
          AppLogLevel.warning,
          'Linux TUN mode may require root or CAP_NET_ADMIN',
          category: 'Instance',
        );
      }
    }

    return null;
  }

  String serviceNameFor(NetworkConfig config) => 'fleasytier-${config.id}';

  Future<ManagedServiceStatus> getServiceStatus(NetworkConfig config) async {
    try {
      final backend = await _detectServiceBackend();
      switch (backend) {
        case ServiceBackend.windows:
          return _getWindowsServiceStatus(serviceNameFor(config));
        case ServiceBackend.systemd:
          return _getSystemdServiceStatus(serviceNameFor(config));
        case ServiceBackend.openrc:
          return _getOpenRcServiceStatus(serviceNameFor(config));
        case ServiceBackend.launchd:
          return _getLaunchdServiceStatus(config);
        case ServiceBackend.unsupported:
          return ManagedServiceStatus.notInstalled;
      }
    } catch (_) {
        return ManagedServiceStatus.notInstalled;
    }
  }

  Future<String> installService(NetworkConfig config) async {
    if (coreBinaryPath == null) return 'EasyTier core binary not found';
    await _ensureServiceLogDir(config);
    onLog?.call(
      AppLogLevel.info,
      'Installing system service for ${config.displayName}',
      category: 'Service',
    );
    try {
      final backend = await _detectServiceBackend();
      switch (backend) {
        case ServiceBackend.windows:
          return _installWindowsService(config);
        case ServiceBackend.systemd:
          return _installSystemdService(config);
        case ServiceBackend.openrc:
          return _installOpenRcService(config);
        case ServiceBackend.launchd:
          return _installLaunchdService(config);
        case ServiceBackend.unsupported:
          return 'Unsupported service manager on this platform';
      }
    } catch (e) {
      onLog?.call(
        AppLogLevel.error,
        'Failed to install service for ${config.displayName}',
        category: 'Service',
        detail: e.toString(),
      );
      return 'Error: $e';
    }
  }

  Future<String> uninstallService(NetworkConfig config) async {
    onLog?.call(
      AppLogLevel.info,
      'Uninstalling system service for ${config.displayName}',
      category: 'Service',
    );
    try {
      final backend = await _detectServiceBackend();
      switch (backend) {
        case ServiceBackend.windows:
          return _uninstallWindowsService(config);
        case ServiceBackend.systemd:
          return _uninstallSystemdService(config);
        case ServiceBackend.openrc:
          return _uninstallOpenRcService(config);
        case ServiceBackend.launchd:
          return _uninstallLaunchdService(config);
        case ServiceBackend.unsupported:
          return 'Unsupported service manager on this platform';
      }
    } catch (e) {
      onLog?.call(
        AppLogLevel.error,
        'Failed to uninstall service for ${config.displayName}',
        category: 'Service',
        detail: e.toString(),
      );
      return 'Error: $e';
    }
  }

  Future<String> startService(NetworkConfig config) async {
    await _ensureServiceLogDir(config);
    onLog?.call(
      AppLogLevel.info,
      'Starting system service for ${config.displayName}',
      category: 'Service',
    );
    try {
      final backend = await _detectServiceBackend();
      switch (backend) {
        case ServiceBackend.windows:
          return _startWindowsService(config);
        case ServiceBackend.systemd:
          return _runServiceCommand(
            'systemctl',
            ['start', '${serviceNameFor(config)}.service'],
            success: 'Service started',
            allowPrivilegeRetry: true,
          );
        case ServiceBackend.openrc:
          return _runServiceCommand(
            'rc-service',
            [serviceNameFor(config), 'start'],
            success: 'Service started',
            allowPrivilegeRetry: true,
          );
        case ServiceBackend.launchd:
          return _startLaunchdService(config);
        case ServiceBackend.unsupported:
          return 'Unsupported service manager on this platform';
      }
    } catch (e) {
      onLog?.call(
        AppLogLevel.error,
        'Failed to start service for ${config.displayName}',
        category: 'Service',
        detail: e.toString(),
      );
      return 'Error: $e';
    }
  }

  Future<String> stopService(NetworkConfig config) async {
    onLog?.call(
      AppLogLevel.info,
      'Stopping system service for ${config.displayName}',
      category: 'Service',
    );
    try {
      final backend = await _detectServiceBackend();
      switch (backend) {
        case ServiceBackend.windows:
          return _stopWindowsService(config);
        case ServiceBackend.systemd:
          return _runServiceCommand(
            'systemctl',
            ['stop', '${serviceNameFor(config)}.service'],
            success: 'Service stopped',
            allowPrivilegeRetry: true,
          );
        case ServiceBackend.openrc:
          return _runServiceCommand(
            'rc-service',
            [serviceNameFor(config), 'stop'],
            success: 'Service stopped',
            allowPrivilegeRetry: true,
          );
        case ServiceBackend.launchd:
          return _stopLaunchdService(config);
        case ServiceBackend.unsupported:
          return 'Unsupported service manager on this platform';
      }
    } catch (e) {
      onLog?.call(
        AppLogLevel.error,
        'Failed to stop service for ${config.displayName}',
        category: 'Service',
        detail: e.toString(),
      );
      return 'Error: $e';
    }
  }

  EasyTierApi _getOrCreateClient(int rpcPort) {
    final key = '$rpcPort';
    return _rpcClients.putIfAbsent(
      key,
      () => EasyTierApi(host: '127.0.0.1', port: rpcPort),
    );
  }

  void _closeRpcClient(String configId) {
    // Best-effort cleanup. RPC clients are keyed by port and recreated on demand.
  }

  Future<void> _ensureConnected(EasyTierApi api) async {
    if (!api.connected) {
      await api.connect();
    }
  }

  Future<NodeInfo?> getNodeInfo(int rpcPort) async {
    final api = _getOrCreateClient(rpcPort);
    try {
      await _ensureConnected(api);
      return await api.getNodeInfo();
    } on RpcException {
      return null;
    } catch (_) {
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

  Future<List<MetricSnapshot>> getStats(int rpcPort) async {
    final api = _getOrCreateClient(rpcPort);
    try {
      await _ensureConnected(api);
      return await api.getStats();
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

  Future<ServiceBackend> _detectServiceBackend() async {
    if (Platform.isWindows) return ServiceBackend.windows;
    if (Platform.isMacOS) return ServiceBackend.launchd;
    if (!Platform.isLinux) return ServiceBackend.unsupported;

    if (await _commandExists('systemctl')) return ServiceBackend.systemd;
    if (await _commandExists('rc-service') && await _commandExists('rc-update')) {
      return ServiceBackend.openrc;
    }
    return ServiceBackend.unsupported;
  }

  Future<bool> _commandExists(String command) async {
    try {
      final result = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        [command],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _hasUnixRootPrivileges() async {
    if (Platform.isWindows) return true;
    try {
      final result = await Process.run(
        'id',
        ['-u'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      return result.exitCode == 0 && result.stdout.toString().trim() == '0';
    } catch (_) {
      return false;
    }
  }

  Future<String?> _detectBinaryInDir(String dir, String fileName) async {
    final path = '$dir/$fileName';
    if (await File(path).exists()) return path;
    return null;
  }

  Future<bool> _hasWintun() async {
    if (!Platform.isWindows || coreBinaryPath == null) return true;
    final normalized = coreBinaryPath!.replaceAll('/', '\\');
    final idx = normalized.lastIndexOf('\\');
    if (idx < 0) return false;
    final dir = normalized.substring(0, idx);
    return File('$dir\\wintun.dll').exists();
  }

  Future<bool> _isWindowsElevated() async {
    if (!Platform.isWindows) return true;
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          '(New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)',
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      return result.exitCode == 0 &&
          result.stdout.toString().trim().toLowerCase() == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<ManagedServiceStatus> _getWindowsServiceStatus(String serviceName) async {
    final result = await _run('sc.exe', ['query', serviceName]);
    if (result.exitCode != 0) {
      final output = _mergedOutput(result).toLowerCase();
      if (output.contains('1060') || output.contains('does not exist')) {
        return ManagedServiceStatus.notInstalled;
      }
      return ManagedServiceStatus.notInstalled;
    }

    final output = _mergedOutput(result).toUpperCase();
    if (output.contains('STATE') && output.contains('RUNNING')) {
      return ManagedServiceStatus.running;
    }
    return ManagedServiceStatus.stopped;
  }

  Future<String> _installWindowsService(NetworkConfig config) async {
    final serviceName = serviceNameFor(config);
    final status = await _getWindowsServiceStatus(serviceName);
    final binPath = _windowsBinPath(config);

    if (status == ManagedServiceStatus.running) {
      final stopMsg = await _stopWindowsService(config);
      if (!_isSuccessMessage(stopMsg)) return stopMsg;
    }

    if (status == ManagedServiceStatus.notInstalled) {
      final create = await _run('sc.exe', [
        'create',
        serviceName,
        'binPath=',
        binPath,
        'start=',
        'auto',
        'DisplayName=',
        'FlEasyTier ${config.displayName}',
        'depend=',
        'rpcss/dnscache',
      ], allowPrivilegeRetry: true);
      if (create.exitCode != 0) {
        return _errorMessage(create, fallback: 'failed to create service');
      }
    } else {
      final update = await _run('sc.exe', [
        'config',
        serviceName,
        'binPath=',
        binPath,
        'start=',
        'auto',
        'DisplayName=',
        'FlEasyTier ${config.displayName}',
        'depend=',
        'rpcss/dnscache',
      ], allowPrivilegeRetry: true);
      if (update.exitCode != 0) {
        return _errorMessage(update, fallback: 'failed to update service');
      }
    }

    final description = await _run('sc.exe', [
      'description',
      serviceName,
      'FlEasyTier managed EasyTier network ${config.displayName}',
    ], allowPrivilegeRetry: true);
    if (description.exitCode != 0) {
      return _errorMessage(description, fallback: 'failed to set description');
    }

    final reg = await _run('reg.exe', [
      'add',
      r'HKLM\SOFTWARE\EasyTier\Service\WorkDir',
      '/v',
      serviceName,
      '/t',
      'REG_SZ',
      '/d',
      _configDir,
      '/f',
    ], allowPrivilegeRetry: true);
    if (reg.exitCode != 0) {
      return _errorMessage(reg, fallback: 'failed to set service work dir');
    }

    return status == ManagedServiceStatus.notInstalled
        ? 'Service installed'
        : 'Service updated';
  }

  Future<String> _uninstallWindowsService(NetworkConfig config) async {
    final serviceName = serviceNameFor(config);
    final status = await _getWindowsServiceStatus(serviceName);
    if (status == ManagedServiceStatus.notInstalled) {
      return 'Service is not installed';
    }

    if (status == ManagedServiceStatus.running) {
      final stopMsg = await _stopWindowsService(config);
      if (!_isSuccessMessage(stopMsg)) return stopMsg;
    }

    final delete = await _run(
      'sc.exe',
      ['delete', serviceName],
      allowPrivilegeRetry: true,
    );
    if (delete.exitCode != 0) {
      return _errorMessage(delete, fallback: 'failed to uninstall service');
    }

    await _run('reg.exe', [
      'delete',
      r'HKLM\SOFTWARE\EasyTier\Service\WorkDir',
      '/v',
      serviceName,
      '/f',
    ], allowPrivilegeRetry: true);
    return 'Service uninstalled';
  }

  Future<String> _startWindowsService(NetworkConfig config) async {
    final serviceName = serviceNameFor(config);
    final status = await _getWindowsServiceStatus(serviceName);
    if (status == ManagedServiceStatus.notInstalled) {
      return 'Service is not installed';
    }
    if (status == ManagedServiceStatus.running) {
      return 'Service is already running';
    }

    final result = await _run(
      'sc.exe',
      ['start', serviceName],
      allowPrivilegeRetry: true,
    );
    if (result.exitCode != 0) {
      return _errorMessage(result, fallback: 'failed to start service');
    }
    return 'Service started';
  }

  Future<String> _stopWindowsService(NetworkConfig config) async {
    final serviceName = serviceNameFor(config);
    final status = await _getWindowsServiceStatus(serviceName);
    if (status == ManagedServiceStatus.notInstalled) {
      return 'Service is not installed';
    }
    if (status == ManagedServiceStatus.stopped) {
      return 'Service is already stopped';
    }

    final result = await _run(
      'sc.exe',
      ['stop', serviceName],
      allowPrivilegeRetry: true,
    );
    if (result.exitCode != 0) {
      return _errorMessage(result, fallback: 'failed to stop service');
    }

    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      final next = await _getWindowsServiceStatus(serviceName);
      if (next != ManagedServiceStatus.running) {
        return 'Service stopped';
      }
    }
    return 'Service stop requested';
  }

  String _windowsBinPath(NetworkConfig config) {
    final allArgs = [coreBinaryPath!, ..._serviceCliArgs(config)];
    return allArgs.map(_quoteWindowsArg).join(' ');
  }

  String _quoteWindowsArg(String value) {
    if (value.isEmpty) return '""';
    if (!value.contains(' ') && !value.contains('"')) return value;
    return '"${value.replaceAll('"', r'\"')}"';
  }

  Future<ManagedServiceStatus> _getSystemdServiceStatus(String serviceName) async {
    final unit = '$serviceName.service';
    final load = await _run('systemctl', ['show', unit, '--property=LoadState', '--value']);
    final loadValue = _firstMeaningfulLine(load);
    if (load.exitCode != 0 || loadValue == 'not-found') {
      return ManagedServiceStatus.notInstalled;
    }

    final active =
        await _run('systemctl', ['show', unit, '--property=ActiveState', '--value']);
    final activeValue = _firstMeaningfulLine(active);
    if (activeValue == 'active' || activeValue == 'activating') {
      return ManagedServiceStatus.running;
    }
    return ManagedServiceStatus.stopped;
  }

  Future<String> _installSystemdService(NetworkConfig config) async {
    final serviceName = serviceNameFor(config);
    final file = File(_systemdUnitPath(serviceName));
    final status = await _getSystemdServiceStatus(serviceName);

    if (!await _hasUnixRootPrivileges()) {
      final result = await _runElevatedShellScript([
        "systemctl stop '$serviceName.service' >/dev/null 2>&1 || true",
        "cat > '${_systemdUnitPath(serviceName)}' <<'EOF'",
        _makeSystemdUnit(config),
        'EOF',
        'systemctl daemon-reload',
        "systemctl enable '$serviceName.service'",
      ].join('\n'));
      if (result.exitCode != 0) {
        return _errorMessage(result, fallback: 'failed to install systemd service');
      }
      return status == ManagedServiceStatus.notInstalled
          ? 'Service installed'
          : 'Service updated';
    }

    if (status == ManagedServiceStatus.running) {
      final stop = await _run(
        'systemctl',
        ['stop', '$serviceName.service'],
        allowPrivilegeRetry: true,
      );
      if (stop.exitCode != 0) {
        return _errorMessage(stop, fallback: 'failed to stop running service');
      }
    }

    await file.writeAsString(_makeSystemdUnit(config));

    final reload = await _run(
      'systemctl',
      ['daemon-reload'],
      allowPrivilegeRetry: true,
    );
    if (reload.exitCode != 0) {
      return _errorMessage(reload, fallback: 'failed to reload systemd');
    }

    final enable = await _run('systemctl', [
      'enable',
      '$serviceName.service',
    ], allowPrivilegeRetry: true);
    if (enable.exitCode != 0) {
      return _errorMessage(enable, fallback: 'failed to update autostart');
    }

    return status == ManagedServiceStatus.notInstalled
        ? 'Service installed'
        : 'Service updated';
  }

  Future<String> _uninstallSystemdService(NetworkConfig config) async {
    final serviceName = serviceNameFor(config);
    final unit = '$serviceName.service';
    final file = File(_systemdUnitPath(serviceName));
    final status = await _getSystemdServiceStatus(serviceName);
    if (status == ManagedServiceStatus.notInstalled && !await file.exists()) {
      return 'Service is not installed';
    }

    if (!await _hasUnixRootPrivileges()) {
      final result = await _runElevatedShellScript([
        "systemctl disable --now '$unit' >/dev/null 2>&1 || true",
        "rm -f '${_systemdUnitPath(serviceName)}'",
        'systemctl daemon-reload',
        "systemctl reset-failed '$unit' >/dev/null 2>&1 || true",
      ].join('\n'));
      if (result.exitCode != 0) {
        return _errorMessage(result, fallback: 'failed to uninstall systemd service');
      }
      return 'Service uninstalled';
    }

    await _run(
      'systemctl',
      ['disable', '--now', unit],
      allowPrivilegeRetry: true,
    );
    if (await file.exists()) {
      await file.delete();
    }

    final reload = await _run(
      'systemctl',
      ['daemon-reload'],
      allowPrivilegeRetry: true,
    );
    if (reload.exitCode != 0) {
      return _errorMessage(reload, fallback: 'failed to reload systemd');
    }
    await _run(
      'systemctl',
      ['reset-failed', unit],
      allowPrivilegeRetry: true,
    );
    return 'Service uninstalled';
  }

  String _systemdUnitPath(String serviceName) =>
      '/etc/systemd/system/$serviceName.service';

  String _makeSystemdUnit(NetworkConfig config) {
    final args = _serviceCliArgs(config).map(_systemdEscape).join(' ');
    final targetApp = _systemdEscape(coreBinaryPath!);
    final workDir = _systemdEscape(_configDir);
    final description = 'FlEasyTier managed EasyTier network ${config.displayName}';

    return [
      '[Unit]',
      'After=network.target syslog.target',
      'Description=${_systemdEscape(description)}',
      'StartLimitIntervalSec=0',
      '',
      '[Service]',
      'Type=simple',
      'WorkingDirectory=$workDir',
      'ExecStart=$targetApp $args',
      'Restart=always',
      'RestartSec=1',
      'LimitNOFILE=infinity',
      '',
      '[Install]',
      'WantedBy=multi-user.target',
      '',
    ].join('\n');
  }

  String _systemdEscape(String input) {
    if (input.isEmpty) return '""';
    final escaped = input
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n');
    if (!escaped.contains(' ') && !escaped.contains('"')) {
      return escaped;
    }
    return '"$escaped"';
  }

  Future<ManagedServiceStatus> _getOpenRcServiceStatus(String serviceName) async {
    final file = File('/etc/init.d/$serviceName');
    if (!await file.exists()) return ManagedServiceStatus.notInstalled;

    final result = await _run('rc-service', [serviceName, 'status']);
    if (result.exitCode == 0) return ManagedServiceStatus.running;
    return ManagedServiceStatus.stopped;
  }

  Future<String> _installOpenRcService(NetworkConfig config) async {
    final serviceName = serviceNameFor(config);
    final file = File('/etc/init.d/$serviceName');
    final status = await _getOpenRcServiceStatus(serviceName);

    if (!await _hasUnixRootPrivileges()) {
      final result = await _runElevatedShellScript([
        "rc-service '$serviceName' stop >/dev/null 2>&1 || true",
        "cat > '/etc/init.d/$serviceName' <<'EOF'",
        _makeOpenRcScript(config),
        'EOF',
        "chmod 755 '/etc/init.d/$serviceName'",
        "rc-update add '$serviceName' default",
      ].join('\n'));
      if (result.exitCode != 0) {
        return _errorMessage(result, fallback: 'failed to install OpenRC service');
      }
      return status == ManagedServiceStatus.notInstalled
          ? 'Service installed'
          : 'Service updated';
    }

    if (status == ManagedServiceStatus.running) {
      final stop = await _run(
        'rc-service',
        [serviceName, 'stop'],
        allowPrivilegeRetry: true,
      );
      if (stop.exitCode != 0) {
        return _errorMessage(stop, fallback: 'failed to stop running service');
      }
    }

    await file.writeAsString(_makeOpenRcScript(config));
    await _run('chmod', ['755', file.path], allowPrivilegeRetry: true);

    final autoResult = await _run('rc-update', [
      'add',
      serviceName,
      'default',
    ], allowPrivilegeRetry: true);
    if (autoResult.exitCode != 0) {
      return _errorMessage(autoResult, fallback: 'failed to update autostart');
    }

    return status == ManagedServiceStatus.notInstalled
        ? 'Service installed'
        : 'Service updated';
  }

  Future<String> _uninstallOpenRcService(NetworkConfig config) async {
    final serviceName = serviceNameFor(config);
    final file = File('/etc/init.d/$serviceName');
    final status = await _getOpenRcServiceStatus(serviceName);
    if (status == ManagedServiceStatus.notInstalled && !await file.exists()) {
      return 'Service is not installed';
    }

    if (!await _hasUnixRootPrivileges()) {
      final result = await _runElevatedShellScript([
        "rc-service '$serviceName' stop >/dev/null 2>&1 || true",
        "rc-update del '$serviceName' default >/dev/null 2>&1 || true",
        "rm -f '/etc/init.d/$serviceName'",
      ].join('\n'));
      if (result.exitCode != 0) {
        return _errorMessage(result, fallback: 'failed to uninstall OpenRC service');
      }
      return 'Service uninstalled';
    }

    await _run(
      'rc-service',
      [serviceName, 'stop'],
      allowPrivilegeRetry: true,
    );
    await _run(
      'rc-update',
      ['del', serviceName, 'default'],
      allowPrivilegeRetry: true,
    );
    if (await file.exists()) {
      await file.delete();
    }
    return 'Service uninstalled';
  }

  String _makeOpenRcScript(NetworkConfig config) {
    final args = _serviceCliArgs(config).map(_shellEscape).join(' ');
    final targetApp = _shellEscape(coreBinaryPath!);
    final workDir = _shellEscape(_configDir);
    final description = _shellEscape(
      'FlEasyTier managed EasyTier network ${config.displayName}',
    );

    return [
      '#!/sbin/openrc-run',
      '',
      'description=$description',
      'command=$targetApp',
      'command_args="$args"',
      'pidfile="/run/\${RC_SVCNAME}.pid"',
      'command_background="yes"',
      'directory=$workDir',
      '',
      'depend() {',
      '    need net',
      '    use logger',
      '}',
      '',
    ].join('\n');
  }

  Future<ManagedServiceStatus> _getLaunchdServiceStatus(NetworkConfig config) async {
    final plist = File(_launchdPlistPath(config));
    if (!await plist.exists()) return ManagedServiceStatus.notInstalled;

    final label = _launchdLabel(config);
    final result = await _run('launchctl', ['print', 'system/$label']);
    if (result.exitCode != 0) {
      return ManagedServiceStatus.stopped;
    }

    final output = _mergedOutput(result).toLowerCase();
    if (output.contains('state = running')) {
      return ManagedServiceStatus.running;
    }
    return ManagedServiceStatus.stopped;
  }

  Future<String> _installLaunchdService(NetworkConfig config) async {
    final plistPath = _launchdPlistPath(config);
    final plist = File(plistPath);
    final status = await _getLaunchdServiceStatus(config);

    if (!await _hasUnixRootPrivileges()) {
      final result = await _runElevatedShellScript([
        "launchctl bootout 'system/${_launchdLabel(config)}' >/dev/null 2>&1 || true",
        "cat > '$plistPath' <<'EOF'",
        _makeLaunchdPlist(config),
        'EOF',
        "chmod 644 '$plistPath'",
        "chown root:wheel '$plistPath'",
        "launchctl bootstrap system '$plistPath'",
      ].join('\n'));
      if (result.exitCode != 0) {
        return _errorMessage(result, fallback: 'failed to install launchd service');
      }
      return status == ManagedServiceStatus.notInstalled
          ? 'Service installed'
          : 'Service updated';
    }

    if (status == ManagedServiceStatus.running) {
      await _run(
        'launchctl',
        ['bootout', 'system/${_launchdLabel(config)}'],
        allowPrivilegeRetry: true,
      );
    }

    await plist.writeAsString(_makeLaunchdPlist(config));
    await _run('chmod', ['644', plistPath], allowPrivilegeRetry: true);
    await _run('chown', ['root:wheel', plistPath], allowPrivilegeRetry: true);

    final bootstrap =
        await _run(
          'launchctl',
          ['bootstrap', 'system', plistPath],
          allowPrivilegeRetry: true,
        );
    if (bootstrap.exitCode != 0) {
      return _errorMessage(bootstrap, fallback: 'failed to bootstrap launchd service');
    }

    return status == ManagedServiceStatus.notInstalled
        ? 'Service installed'
        : 'Service updated';
  }

  Future<String> _uninstallLaunchdService(NetworkConfig config) async {
    final plistPath = _launchdPlistPath(config);
    final plist = File(plistPath);
    final status = await _getLaunchdServiceStatus(config);

    if (!await _hasUnixRootPrivileges()) {
      final result = await _runElevatedShellScript([
        "launchctl bootout 'system/${_launchdLabel(config)}' >/dev/null 2>&1 || true",
        "rm -f '$plistPath'",
      ].join('\n'));
      if (result.exitCode != 0) {
        return _errorMessage(result, fallback: 'failed to uninstall launchd service');
      }
      return 'Service uninstalled';
    }

    if (status != ManagedServiceStatus.notInstalled) {
      await _run(
        'launchctl',
        ['bootout', 'system/${_launchdLabel(config)}'],
        allowPrivilegeRetry: true,
      );
    } else if (!await plist.exists()) {
      return 'Service is not installed';
    }

    if (await plist.exists()) {
      await plist.delete();
    }
    return 'Service uninstalled';
  }

  Future<String> _startLaunchdService(NetworkConfig config) async {
    final plistPath = _launchdPlistPath(config);
    final plist = File(plistPath);
    if (!await plist.exists()) return 'Service is not installed';

    final label = _launchdLabel(config);
    final status = await _getLaunchdServiceStatus(config);
    if (status == ManagedServiceStatus.running) {
      final kick = await _run(
        'launchctl',
        ['kickstart', '-k', 'system/$label'],
        allowPrivilegeRetry: true,
      );
      if (kick.exitCode != 0) {
        return _errorMessage(kick, fallback: 'failed to restart service');
      }
      return 'Service started';
    }

    final bootstrap = await _run(
      'launchctl',
      ['bootstrap', 'system', plistPath],
      allowPrivilegeRetry: true,
    );
    if (bootstrap.exitCode != 0) {
      return _errorMessage(bootstrap, fallback: 'failed to start service');
    }
    return 'Service started';
  }

  Future<String> _stopLaunchdService(NetworkConfig config) async {
    final status = await _getLaunchdServiceStatus(config);
    if (status == ManagedServiceStatus.notInstalled) {
      return 'Service is not installed';
    }
    if (status == ManagedServiceStatus.stopped) {
      return 'Service is already stopped';
    }

    final result =
        await _run(
          'launchctl',
          ['bootout', 'system/${_launchdLabel(config)}'],
          allowPrivilegeRetry: true,
        );
    if (result.exitCode != 0) {
      return _errorMessage(result, fallback: 'failed to stop service');
    }
    return 'Service stopped';
  }

  String _launchdLabel(NetworkConfig config) =>
      'com.fleasytier.${serviceNameFor(config)}';

  String _launchdPlistPath(NetworkConfig config) =>
      '/Library/LaunchDaemons/${_launchdLabel(config)}.plist';

  String _makeLaunchdPlist(NetworkConfig config) {
    final args = [coreBinaryPath!, ..._serviceCliArgs(config)]
        .map((arg) => '    <string>${_xmlEscape(arg)}</string>')
        .join('\n');

    return [
      '<?xml version="1.0" encoding="UTF-8"?>',
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
          '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
      '<plist version="1.0">',
      '<dict>',
      '  <key>Label</key>',
      '  <string>${_xmlEscape(_launchdLabel(config))}</string>',
      '  <key>ProgramArguments</key>',
      '  <array>',
      args,
      '  </array>',
      '  <key>WorkingDirectory</key>',
      '  <string>${_xmlEscape(_configDir)}</string>',
      '  <key>KeepAlive</key>',
      '  <dict>',
      '    <key>Crashed</key>',
      '    <true/>',
      '    <key>SuccessfulExit</key>',
      '    <false/>',
      '  </dict>',
      '  <key>RunAtLoad</key>',
      '  <true/>',
      '</dict>',
      '</plist>',
      '',
    ].join('\n');
  }

  String _xmlEscape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  String _shellEscape(String value) {
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  Future<String> _runServiceCommand(
    String command,
    List<String> args, {
    required String success,
    bool allowPrivilegeRetry = false,
  }) async {
    final result = await _run(
      command,
      args,
      allowPrivilegeRetry: allowPrivilegeRetry,
    );
    if (result.exitCode == 0) return success;
    return _errorMessage(result, fallback: 'command failed');
  }

  Future<ProcessResult> _run(
    String command,
    List<String> args, {
    bool allowPrivilegeRetry = false,
  }) async {
    final result = await Process.run(
      command,
      args,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (allowPrivilegeRetry &&
        Platform.isWindows &&
        !await _isWindowsElevated() &&
        _looksLikeWindowsPermissionError(result)) {
      return _runWindowsElevated(command, args);
    }
    if (allowPrivilegeRetry &&
        !Platform.isWindows &&
        !await _hasUnixRootPrivileges() &&
        _looksLikeUnixPermissionError(result)) {
      return _runElevatedShellScript(_shellCommand(command, args));
    }
    return result;
  }

  String _mergedOutput(ProcessResult result) {
    final stdout = result.stdout.toString().trim();
    final stderr = result.stderr.toString().trim();
    return [stdout, stderr].where((part) => part.isNotEmpty).join('\n');
  }

  String _firstMeaningfulLine(ProcessResult result) {
    return _mergedOutput(result)
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  }

  String _errorMessage(ProcessResult result, {required String fallback}) {
    final output = _mergedOutput(result);
    final message = output.isNotEmpty ? 'Failed: $output' : 'Failed: $fallback';
    onLog?.call(
      AppLogLevel.error,
      fallback,
      category: 'Service',
      detail: output.isNotEmpty ? output : null,
    );
    return message;
  }

  bool _looksLikeWindowsPermissionError(ProcessResult result) {
    final output = _mergedOutput(result).toLowerCase();
    return output.contains('access is denied') ||
        output.contains('permission denied') ||
        output.contains('openservice failed 5') ||
        output.contains('error 5') ||
        output.contains('requires administrator privileges');
  }

  bool _looksLikeUnixPermissionError(ProcessResult result) {
    final output = _mergedOutput(result).toLowerCase();
    return output.contains('permission denied') ||
        output.contains('operation not permitted') ||
        output.contains('not permitted') ||
        output.contains('authentication is required') ||
        output.contains('must be root') ||
        output.contains('must be superuser');
  }

  String _shellCommand(String command, List<String> args) {
    final escapedArgs = args.map(_shellEscape).join(' ');
    return escapedArgs.isEmpty
        ? _shellEscape(command)
        : '${_shellEscape(command)} $escapedArgs';
  }

  Future<ProcessResult> _runElevatedShellScript(String scriptBody) async {
    if (Platform.isWindows) {
      return ProcessResult(
        0,
        1,
        '',
        'Elevated shell scripts are not supported on Windows by this helper',
      );
    }

    final tempDir = await Directory.systemTemp.createTemp('fleasytier-elev-');
    final scriptFile = File('${tempDir.path}${Platform.pathSeparator}run.sh');
    final stdoutFile =
        File('${tempDir.path}${Platform.pathSeparator}stdout.txt');
    final stderrFile =
        File('${tempDir.path}${Platform.pathSeparator}stderr.txt');
    final exitFile = File('${tempDir.path}${Platform.pathSeparator}exit.txt');

    await scriptFile.writeAsString([
      '#!/bin/bash',
      'set +e',
      '{',
      scriptBody,
      "} >'${stdoutFile.path}' 2>'${stderrFile.path}'",
      'code=\$?',
      "printf '%s' \"\$code\" >'${exitFile.path}'",
      'exit "\$code"',
      '',
    ].join('\n'));

    try {
      await Process.run('chmod', ['700', scriptFile.path]);
    } catch (_) {}

    ProcessResult launcher;
    if (Platform.isLinux) {
      final hasPkexec = await _commandExists('pkexec');
      if (!hasPkexec) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
        return ProcessResult(
          0,
          1,
          '',
          'pkexec is not available on this system',
        );
      }
      launcher = await Process.run(
        'pkexec',
        ['/bin/bash', scriptFile.path],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
    } else if (Platform.isMacOS) {
      final command = '/bin/bash ${_shellEscape(scriptFile.path)}';
      launcher = await Process.run(
        'osascript',
        [
          '-e',
          'do shell script "${_appleScriptEscape(command)}" with administrator privileges',
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
    } else {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
      return ProcessResult(0, 1, '', 'Unsupported platform for elevation');
    }

    final stdout =
        await stdoutFile.exists() ? await stdoutFile.readAsString() : '';
    final stderr =
        await stderrFile.exists() ? await stderrFile.readAsString() : '';
    final exitCode = await exitFile.exists()
        ? int.tryParse((await exitFile.readAsString()).trim()) ?? launcher.exitCode
        : launcher.exitCode;

    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}

    if (launcher.exitCode != 0 && exitCode == launcher.exitCode && stderr.isEmpty) {
      return ProcessResult(
        0,
        launcher.exitCode,
        stdout,
        _mergedOutput(launcher),
      );
    }

    return ProcessResult(0, exitCode, stdout, stderr);
  }

  Future<ProcessResult> _runWindowsElevated(
    String command,
    List<String> args,
  ) async {
    final baseDir = await Directory.systemTemp.createTemp('fleasytier-elev-');
    final stdoutFile = File('${baseDir.path}\\stdout.txt');
    final stderrFile = File('${baseDir.path}\\stderr.txt');
    final exitFile = File('${baseDir.path}\\exit.txt');
    final scriptFile = File('${baseDir.path}\\run.ps1');

    final psCommand = _psSingleQuote(command);
    final psArgs = args.map(_psSingleQuote).map((arg) => "'$arg'").join(', ');
    final psStdout = _psSingleQuote(stdoutFile.path);
    final psStderr = _psSingleQuote(stderrFile.path);
    final psExit = _psSingleQuote(exitFile.path);

    await scriptFile.writeAsString([
      "\$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new(\$false)",
      "\$ErrorActionPreference = 'Continue'",
      "\$stdoutPath = '$psStdout'",
      "\$stderrPath = '$psStderr'",
      "\$exitPath = '$psExit'",
      "\$command = '$psCommand'",
      "\$args = @($psArgs)",
      "\$stdout = New-Object System.Collections.Generic.List[string]",
      "\$stderr = New-Object System.Collections.Generic.List[string]",
      "\$code = 0",
      "try {",
      "  & \$command @args 2>&1 | ForEach-Object {",
      "    if (\$_ -is [System.Management.Automation.ErrorRecord]) {",
      "      [void]\$stderr.Add(\$_.ToString())",
      "    } else {",
      "      [void]\$stdout.Add(\$_.ToString())",
      "    }",
      "  }",
      "  if (\$LASTEXITCODE -ne \$null) { \$code = [int]\$LASTEXITCODE }",
      "} catch {",
      "  [void]\$stderr.Add(\$_.Exception.Message)",
      "  \$code = 1",
      "}",
      "[System.IO.File]::WriteAllText(\$stdoutPath, (\$stdout -join [Environment]::NewLine), [System.Text.UTF8Encoding]::new(\$false))",
      "[System.IO.File]::WriteAllText(\$stderrPath, (\$stderr -join [Environment]::NewLine), [System.Text.UTF8Encoding]::new(\$false))",
      "[System.IO.File]::WriteAllText(\$exitPath, \$code.ToString(), [System.Text.UTF8Encoding]::new(\$false))",
    ].join('\r\n'));

    final launcher = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        "Start-Process powershell -Verb RunAs -Wait -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','${scriptFile.path.replaceAll("'", "''")}')",
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    if (launcher.exitCode != 0) {
      final stderr = _mergedOutput(launcher);
      return ProcessResult(
        0,
        launcher.exitCode,
        '',
        stderr.isNotEmpty ? stderr : 'Elevation request was cancelled or failed',
      );
    }

    final stdout = await stdoutFile.exists() ? await stdoutFile.readAsString() : '';
    final stderr = await stderrFile.exists() ? await stderrFile.readAsString() : '';
    final exitCode = await exitFile.exists()
        ? int.tryParse((await exitFile.readAsString()).trim()) ?? 1
        : 1;

    try {
      await baseDir.delete(recursive: true);
    } catch (_) {}

    return ProcessResult(0, exitCode, stdout, stderr);
  }

  String _psSingleQuote(String value) => value.replaceAll("'", "''");

  String _appleScriptEscape(String value) {
    return value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  }

  bool _isSuccessMessage(String msg) {
    final lower = msg.toLowerCase();
    return !lower.startsWith('failed');
  }

  List<String> _serviceCliArgs(NetworkConfig config) {
    final args = List<String>.from(config.toCliArgs());
    final hasFileLogLevel = args.contains('--file-log-level');
    final hasFileLogDir = args.contains('--file-log-dir');

    if (!hasFileLogLevel) {
      args.addAll([
        '--file-log-level',
        config.fileLogLevel.isNotEmpty ? config.fileLogLevel : 'info',
      ]);
    }
    if (!hasFileLogDir) {
      args.addAll([
        '--file-log-dir',
        _effectiveServiceLogDir(config),
      ]);
    }

    return args;
  }

  String _effectiveServiceLogDir(NetworkConfig config) {
    if (config.fileLogDir.isNotEmpty) return config.fileLogDir;
    return '$_configDir${Platform.pathSeparator}logs${Platform.pathSeparator}${config.id}';
  }

  File _serviceLogFileFor(String configId, {NetworkConfig? config}) {
    final dir = config != null
        ? _effectiveServiceLogDir(config)
        : '$_configDir${Platform.pathSeparator}logs${Platform.pathSeparator}$configId';
    return File('$dir${Platform.pathSeparator}easytier.log');
  }

  Future<void> _ensureServiceLogDir(NetworkConfig config) async {
    await Directory(_effectiveServiceLogDir(config)).create(recursive: true);
  }

  Future<LogCleanupResult> _cleanupLocalLogs(
    List<NetworkConfig> configs, {
    required bool Function(File file) shouldClear,
  }) async {
    final seenDirs = <String>{};
    final targets = <Directory>[];

    void addDir(String path) {
      if (path.trim().isEmpty) return;
      final normalized = Directory(path).absolute.path;
      if (seenDirs.add(normalized)) {
        targets.add(Directory(normalized));
      }
    }

    addDir('$_configDir${Platform.pathSeparator}logs');
    for (final config in configs) {
      addDir(_effectiveServiceLogDir(config));
    }

    var clearedFiles = 0;
    var clearedBytes = 0;

    for (final dir in targets) {
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        try {
          if (!shouldClear(entity)) continue;
          final length = await entity.length();
          await entity.writeAsBytes(const [], mode: FileMode.write);
          clearedFiles += 1;
          clearedBytes += length;
        } catch (_) {
          // Ignore files currently locked by the OS or service manager.
        }
      }
    }

    return LogCleanupResult(
      clearedFiles: clearedFiles,
      clearedBytes: clearedBytes,
    );
  }

  List<String> _readLogTail(
    File logFile, {
    int maxLines = 500,
    int maxBytes = 256 * 1024,
  }) {
    final raf = logFile.openSync(mode: FileMode.read);
    try {
      final length = raf.lengthSync();
      if (length <= 0) return const [];

      final readBytes = length < maxBytes ? length : maxBytes;
      raf.setPositionSync(length - readBytes);
      final bytes = raf.readSync(readBytes);
      final start = _safeUtf8TailStart(bytes, truncated: length > readBytes);
      final text = utf8.decode(bytes.sublist(start), allowMalformed: false);
      final lines = const LineSplitter().convert(text);

      if (lines.isEmpty) return const [];

      if (lines.length <= maxLines) return lines;
      return lines.sublist(lines.length - maxLines);
    } finally {
      raf.closeSync();
    }
  }

  int _safeUtf8TailStart(List<int> bytes, {required bool truncated}) {
    if (bytes.isEmpty) return 0;

    if (truncated) {
      for (var i = 0; i < bytes.length; i++) {
        if (bytes[i] == 0x0A) {
          final next = i + 1;
          return next < bytes.length ? next : bytes.length;
        }
      }
    }

    var start = 0;
    while (start < bytes.length && (bytes[start] & 0xC0) == 0x80) {
      start += 1;
    }
    return start;
  }

  String? _buildExitDetail(String configId, int exitCode) {
    if (exitCode == 0) return null;

    final lines = _processLogs[configId] ?? const <String>[];
    if (lines.isEmpty) return 'Process exited with code $exitCode';

    final cleaned = lines
        .map(_cleanLogLine)
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final merged = cleaned.join('\n').toLowerCase();

    if (Platform.isWindows &&
        (merged.contains('failed to create adapter') ||
            merged.contains('wintun') ||
            merged.contains('拒绝访问'))) {
      return 'Failed to create the Wintun adapter. Run FlEasyTier as Administrator, or enable No TUN / Use smoltcp.';
    }

    final candidates = cleaned
        .where((line) =>
            line.contains('Failed to') ||
            line.contains('error:') ||
            line.contains('ERROR') ||
            line.contains('拒绝访问') ||
            line.contains('stopped with error'))
        .toList();
    final source = candidates.isNotEmpty ? candidates : cleaned;
    final start = source.length > 4 ? source.length - 4 : 0;
    final tail = source.sublist(start).join('\n').trim();

    return tail.isNotEmpty ? tail : 'Process exited with code $exitCode';
  }

  String _cleanLogLine(String line) {
    final withoutAnsi =
        line.replaceAll(RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]'), '').trim();
    if (withoutAnsi.startsWith('[ERR] ')) {
      return withoutAnsi.substring(6).trim();
    }
    return withoutAnsi;
  }
}

class LogCleanupResult {
  const LogCleanupResult({
    this.clearedFiles = 0,
    this.clearedBytes = 0,
  });

  final int clearedFiles;
  final int clearedBytes;
}

enum ManagedServiceStatus {
  notInstalled,
  stopped,
  running,
}

enum ServiceBackend {
  windows,
  systemd,
  openrc,
  launchd,
  unsupported,
}
