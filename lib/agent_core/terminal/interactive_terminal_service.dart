import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_pty/flutter_pty.dart';

import '../../utils/path_utils.dart';

enum TerminalEventKind { opened, output, command, exited, closed, error }

class TerminalSessionEvent {
  const TerminalSessionEvent({
    required this.sessionId,
    required this.kind,
    required this.text,
    required this.time,
  });

  final String sessionId;
  final TerminalEventKind kind;
  final String text;
  final DateTime time;
}

class TerminalSessionSnapshot {
  const TerminalSessionSnapshot({
    required this.id,
    required this.name,
    required this.cwd,
    required this.shell,
    required this.running,
    required this.pid,
    required this.exitCode,
    required this.transcript,
    required this.lastActivity,
    this.backend = 'native',
    this.distribution = '',
  });

  final String id;
  final String name;
  final String cwd;
  final String shell;
  final bool running;
  final int? pid;
  final int? exitCode;
  final String transcript;
  final DateTime lastActivity;
  final String backend;
  final String distribution;
}

class WslDistributionInfo {
  const WslDistributionInfo({
    required this.name,
    required this.state,
    required this.version,
    required this.isDefault,
  });

  final String name;
  final String state;
  final int version;
  final bool isDefault;
}

class InteractiveTerminalService {
  final Map<String, _InteractiveTerminalSession> _sessions = {};
  final StreamController<TerminalSessionEvent> _events =
      StreamController<TerminalSessionEvent>.broadcast();
  String _projectRoot = '';
  bool _disposed = false;

  Stream<TerminalSessionEvent> get events => _events.stream;

  TerminalSessionSnapshot? snapshot(String sessionId) =>
      _sessions[_safeSessionId(sessionId)]?.snapshot;

  List<TerminalSessionSnapshot> get snapshots {
    final result = _sessions.values.map((session) => session.snapshot).toList()
      ..sort((a, b) => a.lastActivity.compareTo(b.lastActivity));
    return result;
  }

  Future<void> configureProject(String projectRoot) async {
    final normalized = Directory(projectRoot).absolute.path;
    if (_projectRoot == normalized) return;
    await closeAll();
    _projectRoot = normalized;
    await _loadPersistedTranscripts();
  }

  Future<TerminalSessionSnapshot> open({
    String sessionId = '',
    String name = '',
    String cwd = '',
    String shell = '',
    List<String> arguments = const [],
    Map<String, String>? environment,
    int rows = 30,
    int columns = 120,
    String backend = 'native',
    String wslDistribution = '',
    String wslCwd = '',
  }) async {
    _ensureAlive();
    final id = _safeSessionId(sessionId.isEmpty
        ? 'terminal-${DateTime.now().microsecondsSinceEpoch}'
        : sessionId);
    final existing = _sessions[id];
    if (existing != null && existing.running) return existing.snapshot;

    final normalizedBackend = backend.trim().toLowerCase();
    final useWsl = normalizedBackend == 'wsl';
    if (useWsl && !Platform.isWindows) {
      throw StateError('WSL backend is available only on Windows');
    }
    final effectiveCwd = _resolveCwd(cwd);
    final effectiveShell = useWsl
        ? 'wsl.exe'
        : (shell.trim().isEmpty ? defaultShell : shell.trim());
    final effectiveArguments = useWsl
        ? _wslArguments(
            distribution: wslDistribution,
            cwd: wslCwd.trim().isEmpty
                ? windowsPathToWsl(effectiveCwd)
                : wslCwd.trim(),
            shell: shell,
            extra: arguments,
          )
        : arguments;
    final session = existing ??
        _InteractiveTerminalSession(
          id: id,
          name: name.trim().isEmpty ? id : name.trim(),
          cwd: effectiveCwd,
          shell: effectiveShell,
          backend: useWsl ? 'wsl' : 'native',
          distribution: wslDistribution.trim(),
          emit: _emit,
        );
    session
      ..name = name.trim().isEmpty ? session.name : name.trim()
      ..cwd = effectiveCwd
      ..shell = effectiveShell
      ..backend = useWsl ? 'wsl' : 'native'
      ..distribution = wslDistribution.trim();
    _sessions[id] = session;
    await session.start(
      arguments: effectiveArguments,
      environment: environment,
      rows: rows,
      columns: columns,
    );
    if (Platform.isWindows && _looksLikeCmd(effectiveShell)) {
      session.writeRaw('chcp 65001>nul\r\n');
    }
    await _persistMetadata(session.snapshot);
    return session.snapshot;
  }

  Future<String> writeAndCollect(
    String sessionId,
    String input, {
    bool submit = true,
    bool sensitive = false,
    Duration quietPeriod = const Duration(milliseconds: 450),
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final session = _sessions[_safeSessionId(sessionId)];
    if (session == null) return 'TERMINAL_SESSION_NOT_FOUND: $sessionId';
    if (!session.running) {
      return 'TERMINAL_SESSION_NOT_RUNNING: $sessionId exit=${session.exitCode}';
    }
    final startOffset = session.transcript.length;
    final payload = submit ? '$input${lineEndingFor(session.shell)}' : input;
    session.writeRaw(payload);
    if (!sensitive && input.trim().isNotEmpty) {
      await _persistEvent(TerminalSessionEvent(
        sessionId: session.id,
        kind: TerminalEventKind.command,
        text: input,
        time: DateTime.now(),
      ));
    }
    await session.waitForQuiet(
      fromOffset: startOffset,
      quietPeriod: quietPeriod,
      timeout: timeout,
    );
    final output = session.transcriptFrom(startOffset, maxChars: 30000);
    return '''TERMINAL_WRITE_OK
SESSION_ID: ${session.id}
RUNNING: ${session.running}
OUTPUT_SINCE_WRITE:
${output.trim().isEmpty ? '(no output yet; use terminal_read later)' : output}''';
  }

  String read(String sessionId, {int maxChars = 30000}) {
    final session = _sessions[_safeSessionId(sessionId)];
    if (session == null) return 'TERMINAL_SESSION_NOT_FOUND: $sessionId';
    return '''TERMINAL_READ
SESSION_ID: ${session.id}
NAME: ${session.name}
CWD: ${session.cwd}
SHELL: ${session.shell}
RUNNING: ${session.running}
PID: ${session.pid ?? 'n/a'}
EXIT_CODE: ${session.exitCode ?? 'n/a'}
TRANSCRIPT:
${session.tail(maxChars.clamp(1000, 120000).toInt())}''';
  }

  String listSessions() {
    if (_sessions.isEmpty) return 'TERMINAL_SESSIONS: none';
    final buffer = StringBuffer('TERMINAL_SESSIONS: ${_sessions.length}');
    for (final snapshot in snapshots) {
      buffer.writeln();
      buffer.write(
        '- id=${snapshot.id}; name=${snapshot.name}; running=${snapshot.running}; '
        'pid=${snapshot.pid ?? 'n/a'}; cwd=${snapshot.cwd}; shell=${snapshot.shell}; '
        'backend=${snapshot.backend}${snapshot.distribution.isEmpty ? '' : '; distro=${snapshot.distribution}'}',
      );
    }
    return buffer.toString();
  }

  Future<String> close(String sessionId) async {
    final id = _safeSessionId(sessionId);
    final session = _sessions[id];
    if (session == null) return 'TERMINAL_SESSION_NOT_FOUND: $sessionId';
    await session.close();
    await _persistMetadata(session.snapshot);
    return 'TERMINAL_CLOSED: $id exit=${session.exitCode ?? 'pending'}';
  }

  Future<void> closeAll() async {
    final sessions = _sessions.values.toList(growable: false);
    for (final session in sessions) {
      await session.close();
    }
    _sessions.clear();
  }

  Future<void> recordCommandTranscript({
    required String command,
    required String cwd,
    required String output,
  }) async {
    if (_disposed) return;
    const id = 'agent-main';
    final session = _sessions.putIfAbsent(
      id,
      () => _InteractiveTerminalSession(
        id: id,
        name: 'Команды агента',
        cwd: _resolveCwd(cwd),
        shell: defaultShell,
        emit: _emit,
      ),
    );
    session.cwd = _resolveCwd(cwd);
    final rendered =
        '\r\n\x1b[36m[agent] ${session.cwd}>\x1b[0m $command\r\n$output\r\n';
    final event = session.appendExternal(rendered, emitEvent: false);
    if (!_disposed) _events.add(event);
    await _persistEvent(event);
  }

  void resize(String sessionId, int rows, int columns) {
    _sessions[_safeSessionId(sessionId)]?.resize(rows, columns);
  }

  void writeRaw(String sessionId, String data) {
    _sessions[_safeSessionId(sessionId)]?.writeRaw(data);
  }

  String get defaultShell {
    if (Platform.isWindows) return 'cmd.exe';
    if (Platform.isAndroid) return '/system/bin/sh';
    final configured = Platform.environment['SHELL'];
    if (configured != null && configured.trim().isNotEmpty) return configured;
    if (File('/bin/bash').existsSync()) return '/bin/bash';
    return '/bin/sh';
  }

  String lineEndingFor(String shell) => Platform.isWindows ? '\r\n' : '\n';

  Future<List<WslDistributionInfo>> listWslDistributions() async {
    if (!Platform.isWindows) return const [];
    final result = await Process.run(
      'wsl.exe',
      const ['--list', '--verbose'],
      runInShell: false,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        'wsl.exe',
        const ['--list', '--verbose'],
        _cleanWslOutput('${result.stderr}'),
        result.exitCode,
      );
    }
    return parseWslDistributionList('${result.stdout}');
  }

  static List<WslDistributionInfo> parseWslDistributionList(String output) {
    final rows = <WslDistributionInfo>[];
    final lines = _cleanWslOutput(output).split(RegExp(r'[\r\n]+'));
    for (final raw in lines) {
      var line = raw.trimRight();
      final trimmedLine = line.trim();
      if (trimmedLine.isEmpty ||
          trimmedLine.toLowerCase().contains('distribution') ||
          trimmedLine.toLowerCase().startsWith('name ')) {
        continue;
      }
      final isDefault = line.trimLeft().startsWith('*');
      line = line.trimLeft().replaceFirst(RegExp(r'^\*\s*'), '');
      final columns = line
          .trim()
          .split(RegExp(r'\s{2,}'))
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false);
      if (columns.isEmpty) continue;
      final parsedVersion = int.tryParse(columns.last.trim());
      if (parsedVersion == null) continue;
      final version = parsedVersion;
      final state =
          columns.length >= 3 ? columns[columns.length - 2].trim() : '';
      final name = columns.length >= 3
          ? columns.take(columns.length - 2).join(' ').trim()
          : columns.first.trim();
      if (name.isEmpty) continue;
      rows.add(WslDistributionInfo(
        name: name,
        state: state,
        version: version,
        isDefault: isDefault,
      ));
    }
    return rows;
  }

  static String windowsPathToWsl(String value) {
    final path = value.trim();
    if (path.startsWith('/')) return path.replaceAll('\\', '/');
    final match = RegExp(r'^([A-Za-z]):[\\/]*(.*)$').firstMatch(path);
    if (match == null) return path.replaceAll('\\', '/');
    final drive = match.group(1)!.toLowerCase();
    final rest = match.group(2)!.replaceAll('\\', '/');
    return rest.isEmpty ? '/mnt/$drive' : '/mnt/$drive/$rest';
  }

  List<String> _wslArguments({
    required String distribution,
    required String cwd,
    required String shell,
    required List<String> extra,
  }) {
    final result = <String>[];
    if (distribution.trim().isNotEmpty) {
      result.addAll(['--distribution', distribution.trim()]);
    }
    if (cwd.trim().isNotEmpty) result.addAll(['--cd', cwd.trim()]);
    if (shell.trim().isNotEmpty) {
      result.addAll(['--exec', shell.trim()]);
    }
    result.addAll(extra);
    return result;
  }

  static String _cleanWslOutput(String value) =>
      value.replaceAll('\u0000', '').replaceAll('\ufeff', '').trim();

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await closeAll();
    await _events.close();
  }

  void _emit(TerminalSessionEvent event) {
    if (_disposed) return;
    _events.add(event);
    if (event.kind == TerminalEventKind.output ||
        event.kind == TerminalEventKind.exited ||
        event.kind == TerminalEventKind.error) {
      unawaited(_persistEvent(event));
    }
  }

  String _resolveCwd(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value == '.') {
      return _projectRoot.isEmpty ? Directory.current.path : _projectRoot;
    }
    if (isAbsolutePath(value)) return Directory(value).absolute.path;
    final root = _projectRoot.isEmpty ? Directory.current.path : _projectRoot;
    return Directory(resolveProjectPath(root, value)).absolute.path;
  }

  String _safeSessionId(String value) {
    final safe = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return safe.isEmpty ? 'terminal' : safe;
  }

  bool _looksLikeCmd(String shell) {
    final lower = shell.toLowerCase().replaceAll('\\', '/');
    return lower.endsWith('/cmd.exe') || lower == 'cmd.exe' || lower == 'cmd';
  }

  File? get _historyFile {
    if (_projectRoot.isEmpty) return null;
    return File(
        pathJoin(_projectRoot, '.cppagent', 'terminal', 'transcript.jsonl'));
  }

  File? get _metadataFile {
    if (_projectRoot.isEmpty) return null;
    return File(
        pathJoin(_projectRoot, '.cppagent', 'terminal', 'sessions.json'));
  }

  Future<void> _persistEvent(TerminalSessionEvent event) async {
    final file = _historyFile;
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      final record = jsonEncode({
        'time': event.time.toIso8601String(),
        'session_id': event.sessionId,
        'kind': event.kind.name,
        'text': _limit(event.text, 120000),
      });
      await file.writeAsString('$record\n',
          mode: FileMode.append, encoding: utf8, flush: false);
    } catch (_) {}
  }

  Future<void> _persistMetadata(TerminalSessionSnapshot snapshot) async {
    final file = _metadataFile;
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      final data = {
        'updated_at': DateTime.now().toIso8601String(),
        'sessions': snapshots
            .map((item) => {
                  'id': item.id,
                  'name': item.name,
                  'cwd': item.cwd,
                  'shell': item.shell,
                  'backend': item.backend,
                  'distribution': item.distribution,
                  'running': item.running,
                  'exit_code': item.exitCode,
                })
            .toList(growable: false),
      };
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data),
          encoding: utf8, flush: true);
    } catch (_) {}
  }

  Future<void> _loadPersistedTranscripts() async {
    final file = _historyFile;
    if (file == null || !await file.exists()) return;
    try {
      final length = await file.length();
      final start = length > 2 * 1024 * 1024 ? length - 2 * 1024 * 1024 : 0;
      final handle = await file.open();
      await handle.setPosition(start);
      final bytes = await handle.read(length - start);
      await handle.close();
      final lines = utf8.decode(bytes, allowMalformed: true).split('\n');
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final data = jsonDecode(line) as Map<String, dynamic>;
          final id =
              _safeSessionId(data['session_id']?.toString() ?? 'history');
          final text = data['text']?.toString() ?? '';
          if (text.isEmpty) continue;
          final session = _sessions.putIfAbsent(
            id,
            () => _InteractiveTerminalSession(
              id: id,
              name: id == 'agent-main' ? 'Команды агента' : id,
              cwd: _projectRoot,
              shell: defaultShell,
              emit: _emit,
            ),
          );
          session.appendHistory(text);
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _ensureAlive() {
    if (_disposed) throw StateError('InteractiveTerminalService is disposed');
  }

  String _limit(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return value.substring(value.length - maxChars);
  }
}

class _InteractiveTerminalSession {
  _InteractiveTerminalSession({
    required this.id,
    required this.name,
    required this.cwd,
    required this.shell,
    this.backend = 'native',
    this.distribution = '',
    required this.emit,
  });

  final String id;
  String name;
  String cwd;
  String shell;
  String backend;
  String distribution;
  final void Function(TerminalSessionEvent event) emit;
  Pty? _pty;
  StreamSubscription<String>? _outputSubscription;
  String _transcript = '';
  bool running = false;
  int? exitCode;
  DateTime lastActivity = DateTime.now();

  int? get pid {
    if (!running || _pty == null) return null;
    try {
      return _pty!.pid;
    } catch (_) {
      return null;
    }
  }

  String get transcript => _transcript;

  TerminalSessionSnapshot get snapshot => TerminalSessionSnapshot(
        id: id,
        name: name,
        cwd: cwd,
        shell: shell,
        running: running,
        pid: pid,
        exitCode: exitCode,
        transcript: _transcript,
        lastActivity: lastActivity,
        backend: backend,
        distribution: distribution,
      );

  Future<void> start({
    required List<String> arguments,
    required Map<String, String>? environment,
    required int rows,
    required int columns,
  }) async {
    await close();
    exitCode = null;
    try {
      final pty = Pty.start(
        shell,
        arguments: arguments,
        workingDirectory: cwd,
        environment: environment,
        rows: rows,
        columns: columns,
      );
      _pty = pty;
      running = true;
      lastActivity = DateTime.now();
      _outputSubscription = pty.output
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(
            (text) => _append(text, TerminalEventKind.output),
            onError: (Object error) =>
                _append('\r\n[PTY ERROR] $error\r\n', TerminalEventKind.error),
          );
      unawaited(pty.exitCode.then((code) async {
        exitCode = code;
        running = false;
        lastActivity = DateTime.now();
        _append('\r\n[process exited: $code]\r\n', TerminalEventKind.exited);
        await _outputSubscription?.cancel();
        _outputSubscription = null;
      }));
      emit(TerminalSessionEvent(
        sessionId: id,
        kind: TerminalEventKind.opened,
        text: 'PTY opened: $shell ${arguments.join(' ')} ($cwd)',
        time: DateTime.now(),
      ));
    } catch (error) {
      running = false;
      _append('\r\n[PTY START FAILED] $error\r\n', TerminalEventKind.error);
      rethrow;
    }
  }

  void writeRaw(String value) {
    final pty = _pty;
    if (!running || pty == null) return;
    pty.write(Uint8List.fromList(utf8.encode(value)));
    lastActivity = DateTime.now();
  }

  void resize(int rows, int columns) {
    final pty = _pty;
    if (!running || pty == null) return;
    pty.resize(rows.clamp(2, 300).toInt(), columns.clamp(10, 500).toInt());
  }

  TerminalSessionEvent appendExternal(String value, {bool emitEvent = true}) {
    _transcript += value;
    _trimTranscript();
    lastActivity = DateTime.now();
    final event = TerminalSessionEvent(
      sessionId: id,
      kind: TerminalEventKind.output,
      text: value,
      time: lastActivity,
    );
    if (emitEvent) emit(event);
    return event;
  }

  void appendHistory(String value) {
    _transcript += value;
    _trimTranscript();
  }

  String tail(int maxChars) {
    if (_transcript.length <= maxChars) return _transcript;
    return _transcript.substring(_transcript.length - maxChars);
  }

  String transcriptFrom(int offset, {required int maxChars}) {
    final safeOffset = offset.clamp(0, _transcript.length).toInt();
    final value = _transcript.substring(safeOffset);
    if (value.length <= maxChars) return value;
    return value.substring(value.length - maxChars);
  }

  Future<void> waitForQuiet({
    required int fromOffset,
    required Duration quietPeriod,
    required Duration timeout,
  }) async {
    final started = DateTime.now();
    var lastLength = _transcript.length;
    var lastChange = DateTime.now();
    while (running && DateTime.now().difference(started) < timeout) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (_transcript.length != lastLength) {
        lastLength = _transcript.length;
        lastChange = DateTime.now();
        continue;
      }
      if (_transcript.length > fromOffset &&
          DateTime.now().difference(lastChange) >= quietPeriod) {
        break;
      }
    }
  }

  Future<void> close() async {
    final pty = _pty;
    if (pty == null) return;
    if (running) {
      try {
        pty.kill();
      } catch (_) {}
    }
    running = false;
    await _outputSubscription?.cancel();
    _outputSubscription = null;
    _pty = null;
    emit(TerminalSessionEvent(
      sessionId: id,
      kind: TerminalEventKind.closed,
      text: 'PTY closed',
      time: DateTime.now(),
    ));
  }

  void _append(String value, TerminalEventKind kind) {
    if (value.isEmpty) return;
    _transcript += value;
    _trimTranscript();
    lastActivity = DateTime.now();
    emit(TerminalSessionEvent(
      sessionId: id,
      kind: kind,
      text: value,
      time: lastActivity,
    ));
  }

  void _trimTranscript() {
    const maxChars = 2 * 1024 * 1024;
    if (_transcript.length <= maxChars) return;
    _transcript = _transcript.substring(_transcript.length - maxChars);
  }
}
