import 'dart:async';
import 'dart:convert';
import 'dart:io';

class PrivilegedSession {
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
  }

  Future<ProcessResult> runShell(
    String script, {
    String? workingDirectory,
  }) async {
    final error = await ensureStarted();
    if (error != null) {
      return ProcessResult(0, 1, '', error);
    }
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
    final response = await _send({
      'op': 'start_tracked_process',
      'key': key,
      'command': command,
      'args': args,
      'cwd': workingDirectory,
    });
    return PrivilegedTrackedStartResult(pid: response['pid'] as int? ?? 0);
  }

  Future<ProcessResult> stopTrackedProcess(String key) async {
    final error = await ensureStarted();
    if (error != null) {
      return ProcessResult(0, 1, '', error);
    }
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

    final tempDir = await Directory.systemTemp.createTemp('fleasytier-helper-');
    final sessionFile =
        File('${tempDir.path}${Platform.pathSeparator}session.json');
    final token = DateTime.now().microsecondsSinceEpoch.toRadixString(16);

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
              [
                '--privileged-helper',
                '--session-file=${sessionFile.path}',
                '--session-token=$token',
              ],
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
          _shellEscape('--privileged-helper'),
          _shellEscape('--session-file=${sessionFile.path}'),
          _shellEscape('--session-token=$token'),
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
        final command = [
          _shellEscape(Platform.resolvedExecutable),
          _shellEscape('--privileged-helper'),
          _shellEscape('--session-file=${sessionFile.path}'),
          _shellEscape('--session-token=$token'),
          '>/dev/null',
          '2>&1',
          '&',
        ].join(' ');
        final result = await _runProcessDecoded(
          'osascript',
          [
            '-e',
            'do shell script "${_appleScriptEscape(command)}" with administrator privileges',
          ],
        );
        if (result.exitCode != 0) {
          return _mergeOutput(result).ifEmpty(
            'Failed to launch elevated helper',
          );
        }
      } else {
        return 'Unsupported platform for privilege escalation';
      }

      for (int i = 0; i < 100; i++) {
        if (await sessionFile.exists()) {
          final decoded =
              jsonDecode(await sessionFile.readAsString()) as Map<String, dynamic>;
          _port = decoded['port'] as int?;
          _token = decoded['token'] as String?;
          if (await _ping()) {
            return null;
          }
        }
        await Future.delayed(const Duration(milliseconds: 150));
      }
      return 'Timed out waiting for elevated helper';
    } catch (e) {
      return 'Failed to launch elevated helper: $e';
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
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
      final raw = await _readSocketLine(socket);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      if (decoded['ok'] == true) {
        return decoded;
      }
      throw StateError(decoded['error']?.toString() ?? 'Privileged helper failed');
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
    if (sessionFile == null || token == null) {
      stderr.writeln('Missing helper bootstrap arguments');
      return 2;
    }

    final tracked = <String, Process>{};
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);

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
            return {'ok': false, 'error': 'Shell scripts are unsupported on Windows'};
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
          try {
            process.kill(ProcessSignal.sigterm);
            await process.exitCode.timeout(const Duration(seconds: 3));
          } on TimeoutException {
            process.kill(ProcessSignal.sigkill);
            await process.exitCode.timeout(const Duration(seconds: 3));
          } catch (_) {}
          return {'ok': true, 'exitCode': 0, 'stdout': '', 'stderr': ''};
        case 'is_tracked_process_running':
          final key = request['key'] as String? ?? '';
          return {
            'ok': true,
            'running': tracked.containsKey(key),
          };
        case 'shutdown':
          for (final process in tracked.values.toList()) {
            try {
              process.kill(ProcessSignal.sigterm);
            } catch (_) {}
          }
          unawaited(server.close());
          return {'ok': true};
        default:
          return {'ok': false, 'error': 'Unsupported operation: $op'};
      }
    }

    await File(sessionFile).writeAsString(
      jsonEncode({
        'port': server.port,
        'token': token,
      }),
    );

    await for (final socket in server) {
      unawaited(() async {
        try {
          final raw = await _readSocketLine(socket);
          final request =
              raw.trim().isEmpty ? <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
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

    return 0;
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
    completer.complete(utf8.decode(buffer.sublist(0, end), allowMalformed: true));
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
  return "Start-Process '$quotedExe' -Verb RunAs -WindowStyle Hidden -ArgumentList @($quotedArgs)";
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
