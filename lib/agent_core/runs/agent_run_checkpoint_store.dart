import 'dart:convert';
import 'dart:io';

import '../../utils/path_utils.dart';
import '../security/secret_redactor.dart';
import 'agent_run_checkpoint.dart';

class AgentRunCheckpointStore {
  AgentRunCheckpointStore({required this.projectRoot});

  static const int maxCheckpointBytes = 4 * 1024 * 1024;

  final Directory projectRoot;
  Future<void> _writeQueue = Future<void>.value();

  Directory get runsRoot =>
      Directory(pathJoin(projectRoot.path, '.cppagent', 'runs'));
  Directory get historyRoot => Directory(pathJoin(runsRoot.path, 'history'));
  Directory get corruptRoot => Directory(pathJoin(runsRoot.path, 'corrupt'));
  File get activeFile => File(pathJoin(runsRoot.path, 'active.json'));

  Future<void> initialize() async {
    await historyRoot.create(recursive: true);
    await corruptRoot.create(recursive: true);
  }

  Future<AgentRunCheckpoint> begin({
    required String prompt,
    required int maxIterations,
  }) async {
    await initialize();
    final now = DateTime.now();
    final checkpoint = AgentRunCheckpoint(
      runId: 'run_${now.microsecondsSinceEpoch}',
      projectPath: projectRoot.absolute.path,
      prompt: SecretRedactor.redact(prompt.trim()),
      status: AgentRunStatus.running,
      iteration: 0,
      maxIterations: maxIterations,
      startedAt: now,
      updatedAt: now,
      plan: '',
      toolActions: 0,
      fileMutations: 0,
      commandRuns: 0,
      failedCommands: 0,
      internetActions: 0,
      progressRevision: 0,
      lastTool: '',
      lastToolResultPreview: '',
      lastCommand: '',
      lastCommandResultPreview: '',
      lastCommandExitCode: null,
      lastError: '',
      evidenceSummary: '',
      evidenceItems: const <Map<String, dynamic>>[],
      toolGuardState: const <String, dynamic>{},
      messageCount: 0,
    );
    await save(checkpoint);
    return checkpoint;
  }

  Future<void> save(AgentRunCheckpoint checkpoint) async {
    await initialize();
    await _enqueueWrite(
      () => _atomicWrite(activeFile, _checkpointJson(checkpoint)),
    );
  }

  Future<AgentRunCheckpoint?> loadInterrupted() async {
    await initialize();
    if (!await activeFile.exists()) return null;
    try {
      if (await activeFile.length() > maxCheckpointBytes) {
        await _quarantine(activeFile, reason: 'oversized');
        return null;
      }
      final decoded = jsonDecode(await activeFile.readAsString(encoding: utf8));
      if (decoded is! Map) {
        await _quarantine(activeFile, reason: 'not_map');
        return null;
      }
      final checkpoint = AgentRunCheckpoint.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (!_belongsToProject(checkpoint) || checkpoint.runId.trim().isEmpty) {
        await _quarantine(activeFile, reason: 'invalid_identity');
        return null;
      }
      if (!checkpoint.canResume) {
        await archiveAndClear(checkpoint);
        return null;
      }
      final interrupted = checkpoint.copyWith(
        status: AgentRunStatus.interrupted,
        updatedAt: DateTime.now(),
      );
      await save(interrupted);
      return interrupted;
    } catch (_) {
      await _quarantine(activeFile, reason: 'decode_error');
      return null;
    }
  }

  Future<void> archiveAndClear(AgentRunCheckpoint checkpoint) async {
    await initialize();
    await _enqueueWrite(() async {
      final safeStamp = checkpoint.updatedAt
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final historyFile = File(
        pathJoin(historyRoot.path, '${safeStamp}_${checkpoint.runId}.json'),
      );
      await _atomicWrite(historyFile, _checkpointJson(checkpoint));
      await _clearActiveNow();
      await _pruneHistoryNow(maxFiles: 80);
    });
  }

  Future<List<AgentRunCheckpoint>> loadRecent({int maxItems = 30}) async {
    await initialize();
    final files = historyRoot
        .listSync(followLinks: false)
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.json'))
        .toList()
      ..sort((left, right) => right.statSync().modified.compareTo(
            left.statSync().modified,
          ));
    final runs = <AgentRunCheckpoint>[];
    for (final file in files.take(maxItems.clamp(1, 200).toInt())) {
      try {
        if (await file.length() > maxCheckpointBytes) continue;
        final decoded = jsonDecode(await file.readAsString(encoding: utf8));
        if (decoded is! Map) continue;
        final checkpoint = AgentRunCheckpoint.fromJson(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
        if (_belongsToProject(checkpoint)) runs.add(checkpoint);
      } catch (_) {}
    }
    runs.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return runs;
  }

  Future<AgentRunCheckpoint?> loadLatestResumableHistory({
    Duration maxAge = const Duration(hours: 48),
  }) async {
    final recent = await loadRecent(maxItems: 40);
    final cutoff = DateTime.now().subtract(maxAge);
    for (final checkpoint in recent) {
      final resumableStatus = checkpoint.status == AgentRunStatus.cancelled ||
          checkpoint.status == AgentRunStatus.failed ||
          checkpoint.status == AgentRunStatus.interrupted;
      final hasProgress = checkpoint.toolActions > 0 ||
          checkpoint.fileMutations > 0 ||
          checkpoint.commandRuns > 0 ||
          checkpoint.plan.trim().isNotEmpty;
      if (resumableStatus &&
          hasProgress &&
          checkpoint.prompt.trim().isNotEmpty &&
          checkpoint.updatedAt.isAfter(cutoff)) {
        return checkpoint;
      }
    }
    return null;
  }

  Future<void> clearActive() async {
    await _enqueueWrite(_clearActiveNow);
  }

  Future<void> pruneHistory({int maxFiles = 80}) async {
    await _enqueueWrite(
      () => _pruneHistoryNow(maxFiles: maxFiles.clamp(1, 500).toInt()),
    );
  }

  Future<void> clearHistory() async {
    await initialize();
    await _enqueueWrite(() async {
      if (await historyRoot.exists()) {
        await historyRoot.delete(recursive: true);
      }
      await historyRoot.create(recursive: true);
    });
  }

  bool _belongsToProject(AgentRunCheckpoint checkpoint) {
    String normalize(String value) =>
        Directory(value).absolute.path.replaceAll('\\', '/').toLowerCase();
    return normalize(checkpoint.projectPath) == normalize(projectRoot.path);
  }

  Future<void> _clearActiveNow() async {
    if (await activeFile.exists()) await activeFile.delete();
  }

  Future<void> _pruneHistoryNow({required int maxFiles}) async {
    if (!await historyRoot.exists()) return;
    final files = historyRoot
        .listSync(followLinks: false)
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.json'))
        .toList()
      ..sort((left, right) => right.statSync().modified.compareTo(
            left.statSync().modified,
          ));
    for (final file in files.skip(maxFiles)) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  Future<void> _quarantine(File source, {required String reason}) async {
    if (!await source.exists()) return;
    await corruptRoot.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final target = File(pathJoin(corruptRoot.path, '${stamp}_$reason.json'));
    try {
      await source.rename(target.path);
    } catch (_) {
      try {
        await source.copy(target.path);
        await source.delete();
      } catch (_) {}
    }
  }

  Future<void> _enqueueWrite(Future<void> Function() action) {
    final operation = _writeQueue.then((_) => action());
    _writeQueue = operation.then<void>(
      (_) {},
      onError: (_) {},
    );
    return operation;
  }

  String _checkpointJson(AgentRunCheckpoint checkpoint) {
    final safe = SecretRedactor.redactObject(checkpoint.toJson());
    return const JsonEncoder.withIndent('  ').convert(safe);
  }

  Future<void> _atomicWrite(File target, String content) async {
    await target.parent.create(recursive: true);
    final temp = File('${target.path}.tmp');
    final backup = File('${target.path}.bak');
    await temp.writeAsString(content, encoding: utf8, flush: true);
    if (await backup.exists()) await backup.delete();
    if (await target.exists()) await target.rename(backup.path);
    try {
      await temp.rename(target.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await target.exists()) await target.delete();
      if (await backup.exists()) await backup.rename(target.path);
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }
}
