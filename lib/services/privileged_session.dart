import 'dart:async';
import 'dart:convert';
import 'dart:io';

class PrivilegedSession {
  static const Duration _requestTimeout = Duration(seconds: 45);

  int? _port;
  String? _token;
  Future<String?>? _startup;

  bool get isReady => _port != null && _token != null;

  Future<String?> ensureStarted() {
    final existing = _startup;
    if (existing != null) return existing;
    final future = _ensureStartedImpl();
    _startup = future;
    future.whenComplete(() {
      if (_startup == future) {
        _startup = null;
      }
    });
    return future;
  }

  Future<ProcessResult> runProcess(
    String command,
    List<String> args, {
    String? workingDirectory,
  }) async {
    final error = await ensureStarted();
    if (error != null) {
      return ProcessResult(0, 1, '', error);
    }
    try {
      final response = await _send({
        'op': 'run_process',
        'command': command,
        'args': args,
        'cwd': workingDirectory,
      });
      return ProcessResult(
        0,
        response['exitCode'] as int? ?? 1,
        response['stdout'] ?? '',
        response['stderr'] ?? '',
      );
    } catch (e) {
      return ProcessResult(
        0,
        1,
        '',
        'Privileged helper request failed: $e',
      );
    }
  }

  Future<ProcessResult> runShell(
    String script, {
    String? workingDirectory,
  }) async {
    final error = await ensureStarted();
    if (error != null) {
      return ProcessResult(0, 1, '', error);
    }
    try {
      final response = await _send({
        'op': 'run_shell',
        'script': script,
        'cwd': workingDirectory,
      });
      return ProcessResult(
        0,
        response['exitCode'] as int? ?? 1,
        response['stdout'] ?? '',
        response['stderr'] ?? '',
      );
    } catch (e) {
      return ProcessResult(
        0,
        1,
        '',
        'Privileged helper request failed: $e',
      );
    }
  }

  Future<PrivilegedTrackedStartResult> startTrackedProcess({
    required String key,
    required String command,
    required List<String> args,
    String? workingDirectory,
  }) async {
    final error = await ensureStarted();
    if (error != null) {
      return PrivilegedTrackedStartResult(error: error);
    }
    try {
      final response = await _send({
        'op': 'start_tracked_process',
        'key': key,
        'command': command,
        'args': args,
        'cwd': workingDirectory,
      });
      return PrivilegedTrackedStartResult(pid: response['pid'] as int? ?? 0);
    } catch (e) {
      return PrivilegedTrackedStartResult(
        error: 'Privileged helper request failed: $e',
      );
    }
  }

  Future<ProcessResult> stopTrackedProcess(String key) async {
    final error = await ensureStarted();
    if (error != null) {
      return ProcessResult(0, 1, '', error);
    }
    try {
      final response = await _send({
        'op': 'stop_tracked_process',
        'key': key,
      });
      return ProcessResult(
        0,
        response['exitCode'] as int? ?? 0,
        response['stdout'] ?? '',
        response['stderr'] ?? '',
      );
    } catch (e) {
      return ProcessResult(
        0,
        1,
        '',
        'Privileged helper request failed: $e',
      );
    }
  }

  Future<bool> isTrackedProcessRunning(String key) async {
    if (!isReady) return false;
    try {
      final response = await _send({
        'op': 'is_tracked_process_running',
        'key': key,
      });
      return response['running'] == true;
    } catch (_) {
      _clear();
      return false;
    }
  }

  Future<void> close() async {
    if (!isReady) return;
    try {
      await _send({'op': 'shutdown'});
    } catch (_) {}
    _clear();
  }

  Future<String?> _ensureStartedImpl() async {
    if (await _ping()) return null;

    final tempDir = await _createHelperTempDir();
    final sessionFile =
        File('${tempDir.path}${Platform.pathSeparator}session.json');
    final pidFile = File('${tempDir.path}${Platform.pathSeparator}helper.pid');
    final logFile =
        File('${tempDir.path}${Platform.pathSeparator}helper-launch.log');
    final launcherFile =
        File('${tempDir.path}${Platform.pathSeparator}start-helper.sh');
    final token = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final helperArgs = [
      '--privileged-helper',
      '--session-file=${sessionFile.path}',
      '--session-token=$token',
      '--parent-pid=$pid',
    ];

    try {
      if (Platform.isWindows) {
        final result = await _runProcessDecoded(
          'powershell',
          [
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-Command',
            _windowsLaunchCommand(
              Platform.resolvedExecutable,
              helperArgs,
            ),
          ],
        );
        if (result.exitCode != 0) {
          return _mergeOutput(result).ifEmpty(
            'Failed to launch elevated helper',
          );
        }
      } else if (Platform.isLinux) {
        final command = [
          'nohup',
          _shellEscape(Platform.resolvedExecutable),
          ...helperArgs.map(_shellEscape),
          '>/dev/null',
          '2>&1',
          '&',
        ].join(' ');
        final result = await _runProcessDecoded(
          'pkexec',
          [
            '/bin/bash',
            '-lc',
            command,
          ],
        );
        if (result.exitCode != 0) {
          return _mergeOutput(result).ifEmpty(
            'Failed to launch elevated helper',
          );
        }
      } else if (Platform.isMacOS) {
        await _writeMacOSHelperLauncher(
          launcherFile: launcherFile,
          logFile: logFile,
          pidFile: pidFile,
          executable: Platform.resolvedExecutable,
          args: helperArgs,
        );
        final result = await _launchMacOSHelper(launcherFile);
        if (result.exitCode != 0) {
          final output = _mergeOutput(result);
          final launchLog = await _readTextIfExists(logFile);
          return [
            output.ifEmpty('Failed to launch elevated helper'),
            if (launchLog.trim().isNotEmpty)
              'Helper launch log:\n${launchLog.trim()}',
          ].join('\n');
        }
      } else {
        return 'Unsupported platform for privilege escalation';
      }

      Object? lastReadError;
      int? helperPid;
      for (int i = 0; i < 160; i++) {
        helperPid ??= await _readPidIfExists(pidFile);
        if (await sessionFile.exists()) {
          try {
            final raw = (await sessionFile.readAsString()).trim();
            if (raw.isNotEmpty) {
              final decoded = jsonDecode(raw) as Map<String, dynamic>;
              _port = decoded['port'] as int?;
              _token = decoded['token'] as String?;
              if (_token == token && await _ping()) {
                try {
                  await tempDir.delete(recursive: true);
                } catch (_) {}
                return null;
              }
            }
          } catch (e) {
            lastReadError = e;
          }
        }
        if (helperPid != null &&
            !await _isProcessAlive(helperPid, allowPermissionDenied: true)) {
          return _helperStartupFailure(
            'Elevated helper exited before it became ready',
            logFile: logFile,
            pidFile: pidFile,
            lastReadError: lastReadError,
          );
        }
        await Future.delayed(const Duration(milliseconds: 150));
      }
      return _helperStartupFailure(
        'Timed out waiting for elevated helper',
        logFile: logFile,
        pidFile: pidFile,
        lastReadError: lastReadError,
      );
    } catch (e) {
      return 'Failed to launch elevated helper: $e';
    }
  }

  Future<Directory> _createHelperTempDir() async {
    final base = Platform.isMacOS
        ? Directory('/tmp')
        : Directory.systemTemp;
    final dir = await base.createTemp('fleasytier-helper-');
    try {
      await Process.run('chmod', ['700', dir.path]);
    } catch (_) {}
    return dir;
  }

  Future<void> _writeMacOSHelperLauncher({
    required File launcherFile,
    required File logFile,
    required File pidFile,
    required String executable,
    required List<String> args,
  }) async {
    final invocation = [
      _shellEscape(executable),
      ...args.map(_shellEscape),
    ].join(' ');
    final script = [
      '#!/bin/sh',
      'LOG=${_shellEscape(logFile.path)}',
      'PIDFILE=${_shellEscape(pidFile.path)}',
      'EXE=${_shellEscape(executable)}',
      'umask 022',
      '{',
      '  echo "[\$(date -u +%Y-%m-%dT%H:%M:%SZ)] launcher uid=\$(id -u) euid=\$(id -u)"',
      '  echo "executable=\$EXE"',
      '  /bin/ls -l "\$EXE"',
      '  if [ ! -x "\$EXE" ]; then',
      '    echo "executable is not runnable"',
      '    exit 126',
      '  fi',
      '  trap "" HUP',
      '  $invocation </dev/null >> "\$LOG" 2>&1 &',
      '  helper_pid=\$!',
      '  echo "\$helper_pid" > "\$PIDFILE"',
      '  chmod 644 "\$PIDFILE" "\$LOG" 2>/dev/null || true',
      '  echo "started helper pid=\$helper_pid"',
      '  sleep 0.2',
      '  if kill -0 "\$helper_pid" 2>/dev/null; then',
      '    echo "helper pid \$helper_pid is alive after launch"',
      '  else',
      '    echo "helper pid \$helper_pid exited immediately"',
      '  fi',
      '} >> "\$LOG" 2>&1',
      'exit 0',
      '',
    ].join('\n');
    await launcherFile.writeAsString(script, flush: true);
    try {
      await Process.run('chmod', ['700', launcherFile.path]);
    } catch (_) {}
  }

  Future<ProcessResult> _launchMacOSHelper(File launcherFile) {
    final command = '/bin/sh ${_shellEscape(launcherFile.path)}';
    return _runProcessDecoded(
      'osascript',
      [
        '-e',
        'do shell script "${_appleScriptEscape(command)}" with administrator privileges',
      ],
    );
  }

  Future<String> _helperStartupFailure(
    String message, {
    required File logFile,
    required File pidFile,
    Object? lastReadError,
  }) async {
    final pid = await _readTextIfExists(pidFile);
    final launchLog = await _readTextIfExists(logFile);
    return [
      if (lastReadError != null) '$message: $lastReadError' else message,
      if (pid.trim().isNotEmpty) 'Helper pid: ${pid.trim()}',
      'Helper work dir: ${logFile.parent.path}',
      if (launchLog.trim().isNotEmpty)
        'Helper launch log:\n${launchLog.trim()}',
    ].join('\n');
  }

  Future<bool> _ping() async {
    if (!isReady) return false;
    try {
      final response = await _send({'op': 'ping'});
      return response['ok'] == true;
    } catch (_) {
      _clear();
      return false;
    }
  }

  Future<Map<String, dynamic>> _send(Map<String, dynamic> request) async {
    final port = _port;
    final token = _token;
    if (port == null || token == null) {
      throw StateError('Privileged session is not ready');
    }

    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: const Duration(seconds: 5),
    );
    try {
      final payload = jsonEncode({
        ...request,
        'token': token,
      });
      socket.writeln(payload);
      await socket.flush();
      final raw = await _readSocketLine(socket).timeout(_requestTimeout);
      if (raw.trim().isEmpty) {
        throw StateError('Privileged helper closed without a response');
      }
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      if (decoded['ok'] == true) {
        return decoded;
      }
      throw StateError(
        decoded['error']?.toString() ?? 'Privileged helper failed',
      );
    } finally {
      await socket.close();
    }
  }

  void _clear() {
    _port = null;
    _token = null;
  }

  static Future<int> runHelper(List<String> args) async {
    final sessionFile = _argValue(args, '--session-file=');
    final token = _argValue(args, '--session-token=');
    final parentPid = int.tryParse(_argValue(args, '--parent-pid=') ?? '');
    if (sessionFile == null || token == null) {
      stderr.writeln('Missing helper bootstrap arguments');
      return 2;
    }
    stderr.writeln(
      'Privileged helper bootstrap pid=$pid sessionFile=$sessionFile',
    );

    final tracked = <String, Process>{};
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    stderr.writeln(
      'Privileged helper listening on 127.0.0.1:${server.port}',
    );
    var shuttingDown = false;

    Future<void> stopTrackedProcesses() async {
      for (final process in tracked.values.toList()) {
        await _terminateProcess(process);
      }
      tracked.clear();
    }

    Future<void> shutdownHelper() async {
      if (shuttingDown) return;
      shuttingDown = true;
      await stopTrackedProcesses();
      await server.close();
    }

    Timer? parentMonitor;
    var checkingParent = false;
    if (parentPid != null && parentPid > 0) {
      parentMonitor = Timer.periodic(const Duration(seconds: 2), (_) async {
        if (checkingParent || shuttingDown) return;
        checkingParent = true;
        try {
          if (!await _isProcessAlive(parentPid)) {
            parentMonitor?.cancel();
            await shutdownHelper();
          }
        } finally {
          checkingParent = false;
        }
      });
    }

    Future<Map<String, dynamic>> handle(Map<String, dynamic> request) async {
      if (request['token'] != token) {
        return {'ok': false, 'error': 'Unauthorized'};
      }

      final op = request['op'] as String? ?? '';
      switch (op) {
        case 'ping':
          return {'ok': true};
        case 'run_process':
          final result = await _runProcessDecoded(
            request['command'] as String,
            (request['args'] as List? ?? const [])
                .map((item) => '$item')
                .toList(),
            workingDirectory: request['cwd'] as String?,
          );
          return {
            'ok': true,
            'exitCode': result.exitCode,
            'stdout': result.stdout.toString(),
            'stderr': result.stderr.toString(),
          };
        case 'run_shell':
          if (Platform.isWindows) {
            return {
              'ok': false,
              'error': 'Shell scripts are unsupported on Windows',
            };
          }
          final result = await _runProcessDecoded(
            '/bin/bash',
            ['-lc', request['script'] as String? ?? ''],
            workingDirectory: request['cwd'] as String?,
          );
          return {
            'ok': true,
            'exitCode': result.exitCode,
            'stdout': result.stdout.toString(),
            'stderr': result.stderr.toString(),
          };
        case 'start_tracked_process':
          final key = request['key'] as String? ?? '';
          if (key.isEmpty) {
            return {'ok': false, 'error': 'Missing process key'};
          }
          final existing = tracked[key];
          if (existing != null) {
            return {'ok': false, 'error': 'Process already running'};
          }
          final process = await Process.start(
            request['command'] as String,
            (request['args'] as List? ?? const [])
                .map((item) => '$item')
                .toList(),
            workingDirectory: request['cwd'] as String?,
            mode: ProcessStartMode.normal,
          );
          process.stdout.listen((_) {});
          process.stderr.listen((_) {});
          tracked[key] = process;
          unawaited(process.exitCode.then((_) {
            tracked.remove(key);
          }));
          return {
            'ok': true,
            'pid': process.pid,
          };
        case 'stop_tracked_process':
          final key = request['key'] as String? ?? '';
          final process = tracked.remove(key);
          if (process == null) {
            return {'ok': true, 'exitCode': 0, 'stdout': '', 'stderr': ''};
          }
          await _terminateProcess(process);
          return {'ok': true, 'exitCode': 0, 'stdout': '', 'stderr': ''};
        case 'is_tracked_process_running':
          final key = request['key'] as String? ?? '';
          return {
            'ok': true,
            'running': tracked.containsKey(key),
          };
        case 'shutdown':
          unawaited(shutdownHelper());
          return {'ok': true};
        default:
          return {'ok': false, 'error': 'Unsupported operation: $op'};
      }
    }

    await _writeJsonFileAtomically(
      File(sessionFile),
      {
        'port': server.port,
        'token': token,
      },
    );

    try {
      await for (final socket in server) {
        unawaited(() async {
          try {
            final raw = await _readSocketLine(socket);
            final request = raw.trim().isEmpty
                ? <String, dynamic>{}
                : jsonDecode(raw) as Map<String, dynamic>;
            final response = await handle(request);
            socket.writeln(jsonEncode(response));
            await socket.flush();
          } catch (e) {
            socket.writeln(jsonEncode({'ok': false, 'error': e.toString()}));
            await socket.flush();
          } finally {
            await socket.close();
          }
        }());
      }
    } finally {
      parentMonitor?.cancel();
      await stopTrackedProcesses();
    }

    return 0;
  }
}

Future<void> _writeJsonFileAtomically(
  File target,
  Map<String, dynamic> payload,
) async {
  final temp = File('${target.path}.tmp');
  await temp.writeAsString(jsonEncode(payload), flush: true);
  if (await target.exists()) {
    await target.delete();
  }
  await temp.rename(target.path);
}

Future<int?> _readPidIfExists(File file) async {
  final raw = await _readTextIfExists(file);
  if (raw.trim().isEmpty) return null;
  return int.tryParse(raw.trim());
}

Future<String> _readTextIfExists(File file) async {
  try {
    if (!await file.exists()) return '';
    return await file.readAsString();
  } catch (_) {
    return '';
  }
}

Future<void> _terminateProcess(Process process) async {
  try {
    process.kill(ProcessSignal.sigterm);
    await process.exitCode.timeout(const Duration(seconds: 3));
    return;
  } on TimeoutException {
    try {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode.timeout(const Duration(seconds: 3));
    } catch (_) {}
  } catch (_) {}
}

Future<bool> _isProcessAlive(
  int targetPid, {
  bool allowPermissionDenied = false,
}) async {
  if (targetPid <= 0) return false;
  if (targetPid == pid) return true;

  try {
    if (Platform.isWindows) {
      final result = await _runProcessDecoded('tasklist', [
        '/FI',
        'PID eq $targetPid',
        '/FO',
        'CSV',
        '/NH',
      ]);
      final output = result.stdout.toString();
      return result.exitCode == 0 &&
          output.contains('"$targetPid"') &&
          !output.toLowerCase().contains('no tasks are running');
    }

    final result = await _runProcessDecoded('/bin/kill', ['-0', '$targetPid']);
    if (result.exitCode == 0) return true;
    if (!allowPermissionDenied) return false;
    final output = _mergeOutput(result).toLowerCase();
    return output.contains('operation not permitted') ||
        output.contains('not permitted');
  } catch (_) {
    return false;
  }
}

Future<String> _readSocketLine(Socket socket) async {
  final completer = Completer<String>();
  final buffer = <int>[];
  StreamSubscription<List<int>>? sub;

  void completeWithBuffer() {
    if (completer.isCompleted) return;
    var end = buffer.length;
    if (end > 0 && buffer[end - 1] == 0x0A) {
      end -= 1;
    }
    if (end > 0 && buffer[end - 1] == 0x0D) {
      end -= 1;
    }
    completer.complete(
      utf8.decode(buffer.sublist(0, end), allowMalformed: true),
    );
    unawaited(sub?.cancel());
  }

  sub = socket.listen(
    (chunk) {
      if (completer.isCompleted) return;
      final newlineIndex = chunk.indexOf(0x0A);
      if (newlineIndex >= 0) {
        buffer.addAll(chunk.take(newlineIndex + 1));
        completeWithBuffer();
        return;
      }
      buffer.addAll(chunk);
    },
    onError: (Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    },
    onDone: completeWithBuffer,
    cancelOnError: true,
  );

  return completer.future;
}

Encoding get _platformProcessEncoding =>
    Platform.isWindows ? systemEncoding : utf8;

Future<ProcessResult> _runProcessDecoded(
  String command,
  List<String> args, {
  String? workingDirectory,
}) async {
  final result = await Process.run(
    command,
    args,
    workingDirectory: workingDirectory,
    stdoutEncoding: null,
    stderrEncoding: null,
  );
  return ProcessResult(
    result.pid,
    result.exitCode,
    _decodeProcessOutput(result.stdout),
    _decodeProcessOutput(result.stderr),
  );
}

String _decodeProcessOutput(Object? output) {
  if (output == null) return '';
  if (output is String) return output;
  if (output is List<int>) {
    if (output.isEmpty) return '';
    try {
      return _platformProcessEncoding.decode(output);
    } catch (_) {
      try {
        return utf8.decode(output);
      } catch (_) {
        return utf8.decode(output, allowMalformed: true);
      }
    }
  }
  return output.toString();
}

class PrivilegedTrackedStartResult {
  PrivilegedTrackedStartResult({
    this.pid = 0,
    this.error,
  });

  final int pid;
  final String? error;

  bool get isSuccess => error == null;
}

String? _argValue(List<String> args, String prefix) {
  for (final arg in args) {
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }
  return null;
}

String _mergeOutput(ProcessResult result) {
  final stdout = result.stdout.toString().trim();
  final stderr = result.stderr.toString().trim();
  return [stdout, stderr].where((part) => part.isNotEmpty).join('\n');
}

String _windowsLaunchCommand(String executable, List<String> args) {
  final quotedExe = executable.replaceAll("'", "''");
  final quotedArgs = args
      .map((arg) => "'${arg.replaceAll("'", "''")}'")
      .join(', ');
  return "Start-Process '$quotedExe' -Verb RunAs -WindowStyle Hidden "
      '-ArgumentList @($quotedArgs)';
}

String _shellEscape(String value) {
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

String _appleScriptEscape(String value) {
  return value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
