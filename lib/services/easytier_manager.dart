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
      final lines = logFile.readAsLinesSync();
      if (lines.length <= 500) return lines;
      return lines.sublist(lines.length - 500);
    } catch (_) {
      return const [];
    }
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
          );
        case ServiceBackend.openrc:
          return _runServiceCommand(
            'rc-service',
            [serviceNameFor(config), 'start'],
            success: 'Service started',
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
          );
        case ServiceBackend.openrc:
          return _runServiceCommand(
            'rc-service',
            [serviceNameFor(config), 'stop'],
            success: 'Service stopped',
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
        config.autoStart ? 'auto' : 'demand',
        'DisplayName=',
        'FlEasyTier ${config.displayName}',
        'depend=',
        'rpcss/dnscache',
      ]);
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
        config.autoStart ? 'auto' : 'demand',
        'DisplayName=',
        'FlEasyTier ${config.displayName}',
        'depend=',
        'rpcss/dnscache',
      ]);
      if (update.exitCode != 0) {
        return _errorMessage(update, fallback: 'failed to update service');
      }
    }

    final description = await _run('sc.exe', [
      'description',
      serviceName,
      'FlEasyTier managed EasyTier network ${config.displayName}',
    ]);
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
    ]);
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

    final delete = await _run('sc.exe', ['delete', serviceName]);
    if (delete.exitCode != 0) {
      return _errorMessage(delete, fallback: 'failed to uninstall service');
    }

    await _run('reg.exe', [
      'delete',
      r'HKLM\SOFTWARE\EasyTier\Service\WorkDir',
      '/v',
      serviceName,
      '/f',
    ]);
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

    final result = await _run('sc.exe', ['start', serviceName]);
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

    final result = await _run('sc.exe', ['stop', serviceName]);
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

    if (status == ManagedServiceStatus.running) {
      final stop = await _run('systemctl', ['stop', '$serviceName.service']);
      if (stop.exitCode != 0) {
        return _errorMessage(stop, fallback: 'failed to stop running service');
      }
    }

    await file.writeAsString(_makeSystemdUnit(config));

    final reload = await _run('systemctl', ['daemon-reload']);
    if (reload.exitCode != 0) {
      return _errorMessage(reload, fallback: 'failed to reload systemd');
    }

    final enable = await _run('systemctl', [
      config.autoStart ? 'enable' : 'disable',
      '$serviceName.service',
    ]);
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

    await _run('systemctl', ['disable', '--now', unit]);
    if (await file.exists()) {
      await file.delete();
    }

    final reload = await _run('systemctl', ['daemon-reload']);
    if (reload.exitCode != 0) {
      return _errorMessage(reload, fallback: 'failed to reload systemd');
    }
    await _run('systemctl', ['reset-failed', unit]);
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

    if (status == ManagedServiceStatus.running) {
      final stop = await _run('rc-service', [serviceName, 'stop']);
      if (stop.exitCode != 0) {
        return _errorMessage(stop, fallback: 'failed to stop running service');
      }
    }

    await file.writeAsString(_makeOpenRcScript(config));
    await _run('chmod', ['755', file.path]);

    final autoResult = await _run('rc-update', [
      config.autoStart ? 'add' : 'del',
      serviceName,
      'default',
    ]);
    if (autoResult.exitCode != 0 && config.autoStart) {
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

    await _run('rc-service', [serviceName, 'stop']);
    await _run('rc-update', ['del', serviceName, 'default']);
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

    if (status == ManagedServiceStatus.running) {
      await _run('launchctl', ['bootout', 'system/${_launchdLabel(config)}']);
    }

    await plist.writeAsString(_makeLaunchdPlist(config));
    await _run('chmod', ['644', plistPath]);
    await _run('chown', ['root:wheel', plistPath]);

    if (config.autoStart) {
      final bootstrap =
          await _run('launchctl', ['bootstrap', 'system', plistPath]);
      if (bootstrap.exitCode != 0) {
        return _errorMessage(bootstrap, fallback: 'failed to bootstrap launchd service');
      }
    }

    return status == ManagedServiceStatus.notInstalled
        ? 'Service installed'
        : 'Service updated';
  }

  Future<String> _uninstallLaunchdService(NetworkConfig config) async {
    final plistPath = _launchdPlistPath(config);
    final plist = File(plistPath);
    final status = await _getLaunchdServiceStatus(config);
    if (status != ManagedServiceStatus.notInstalled) {
      await _run('launchctl', ['bootout', 'system/${_launchdLabel(config)}']);
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
      final kick = await _run('launchctl', ['kickstart', '-k', 'system/$label']);
      if (kick.exitCode != 0) {
        return _errorMessage(kick, fallback: 'failed to restart service');
      }
      return 'Service started';
    }

    final bootstrap = await _run('launchctl', ['bootstrap', 'system', plistPath]);
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
        await _run('launchctl', ['bootout', 'system/${_launchdLabel(config)}']);
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
      config.autoStart ? '  <true/>' : '  <false/>',
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
  }) async {
    final result = await _run(command, args);
    if (result.exitCode == 0) return success;
    return _errorMessage(result, fallback: 'command failed');
  }

  Future<ProcessResult> _run(String command, List<String> args) {
    return Process.run(
      command,
      args,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
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
