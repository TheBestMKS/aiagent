import 'dart:convert';

enum AgentRunStatus {
  running,
  waitingForModel,
  executingTool,
  verifying,
  completed,
  cancelled,
  failed,
  interrupted,
}

extension AgentRunStatusX on AgentRunStatus {
  bool get isTerminal => switch (this) {
        AgentRunStatus.completed ||
        AgentRunStatus.cancelled ||
        AgentRunStatus.failed =>
          true,
        _ => false,
      };

  String get label => switch (this) {
        AgentRunStatus.running => 'Выполнение',
        AgentRunStatus.waitingForModel => 'Ожидание модели',
        AgentRunStatus.executingTool => 'Выполнение инструмента',
        AgentRunStatus.verifying => 'Проверка результата',
        AgentRunStatus.completed => 'Завершено',
        AgentRunStatus.cancelled => 'Остановлено',
        AgentRunStatus.failed => 'Ошибка',
        AgentRunStatus.interrupted => 'Прервано',
      };
}

class AgentRunCheckpoint {
  const AgentRunCheckpoint({
    required this.runId,
    required this.projectPath,
    required this.prompt,
    required this.status,
    required this.iteration,
    required this.maxIterations,
    required this.startedAt,
    required this.updatedAt,
    required this.plan,
    required this.toolActions,
    required this.fileMutations,
    required this.commandRuns,
    required this.failedCommands,
    required this.internetActions,
    required this.progressRevision,
    required this.lastTool,
    required this.lastToolResultPreview,
    required this.lastCommand,
    required this.lastCommandResultPreview,
    required this.lastCommandExitCode,
    required this.lastError,
    required this.evidenceSummary,
    required this.evidenceItems,
    required this.toolGuardState,
    required this.messageCount,
    this.buildFailureKind = '',
    this.buildFailureSummary = '',
    this.buildFailureRecommendedAction = '',
    this.buildFailureImplicatedFiles = const <String>[],
    this.buildFailureImplicatedLines = const <String, int>{},
    this.buildSuggestedDiagnostic = '',
    this.buildSuggestedRecovery = '',
    this.buildMissingDependency = '',
    this.buildLocatedDependencyPath = '',
    this.buildRetryRequired = false,
    this.requiredBuildRetryCommand = '',
    this.requiredBuildRetryWorkingDirectory = '',
    this.buildMutationAwaitingRetry = false,
    this.buildFailureRevision = 0,
    this.buildDiagnosticsRun = const <String>[],
    this.fileReadAtBuildFailureRevision = const <String, int>{},
    this.fileReadRangesAtBuildFailureRevision = const <String, String>{},
  });

  final String runId;
  final String projectPath;
  final String prompt;
  final AgentRunStatus status;
  final int iteration;
  final int maxIterations;
  final DateTime startedAt;
  final DateTime updatedAt;
  final String plan;
  final int toolActions;
  final int fileMutations;
  final int commandRuns;
  final int failedCommands;
  final int internetActions;
  final int progressRevision;
  final String lastTool;
  final String lastToolResultPreview;
  final String lastCommand;
  final String lastCommandResultPreview;
  final int? lastCommandExitCode;
  final String lastError;
  final String evidenceSummary;
  final List<Map<String, dynamic>> evidenceItems;
  final Map<String, dynamic> toolGuardState;
  final int messageCount;
  final String buildFailureKind;
  final String buildFailureSummary;
  final String buildFailureRecommendedAction;
  final List<String> buildFailureImplicatedFiles;
  final Map<String, int> buildFailureImplicatedLines;
  final String buildSuggestedDiagnostic;
  final String buildSuggestedRecovery;
  final String buildMissingDependency;
  final String buildLocatedDependencyPath;
  final bool buildRetryRequired;
  final String requiredBuildRetryCommand;
  final String requiredBuildRetryWorkingDirectory;
  final bool buildMutationAwaitingRetry;
  final int buildFailureRevision;
  final List<String> buildDiagnosticsRun;
  final Map<String, int> fileReadAtBuildFailureRevision;
  final Map<String, String> fileReadRangesAtBuildFailureRevision;

  bool get canResume => !status.isTerminal && prompt.trim().isNotEmpty;

  AgentRunCheckpoint copyWith({
    AgentRunStatus? status,
    int? iteration,
    int? maxIterations,
    DateTime? updatedAt,
    String? plan,
    int? toolActions,
    int? fileMutations,
    int? commandRuns,
    int? failedCommands,
    int? internetActions,
    int? progressRevision,
    String? lastTool,
    String? lastToolResultPreview,
    String? lastCommand,
    String? lastCommandResultPreview,
    int? lastCommandExitCode,
    String? lastError,
    String? evidenceSummary,
    List<Map<String, dynamic>>? evidenceItems,
    Map<String, dynamic>? toolGuardState,
    int? messageCount,
    String? buildFailureKind,
    String? buildFailureSummary,
    String? buildFailureRecommendedAction,
    List<String>? buildFailureImplicatedFiles,
    Map<String, int>? buildFailureImplicatedLines,
    String? buildSuggestedDiagnostic,
    String? buildSuggestedRecovery,
    String? buildMissingDependency,
    String? buildLocatedDependencyPath,
    bool? buildRetryRequired,
    String? requiredBuildRetryCommand,
    String? requiredBuildRetryWorkingDirectory,
    bool? buildMutationAwaitingRetry,
    int? buildFailureRevision,
    List<String>? buildDiagnosticsRun,
    Map<String, int>? fileReadAtBuildFailureRevision,
    Map<String, String>? fileReadRangesAtBuildFailureRevision,
  }) {
    return AgentRunCheckpoint(
      runId: runId,
      projectPath: projectPath,
      prompt: prompt,
      status: status ?? this.status,
      iteration: iteration ?? this.iteration,
      maxIterations: maxIterations ?? this.maxIterations,
      startedAt: startedAt,
      updatedAt: updatedAt ?? DateTime.now(),
      plan: plan ?? this.plan,
      toolActions: toolActions ?? this.toolActions,
      fileMutations: fileMutations ?? this.fileMutations,
      commandRuns: commandRuns ?? this.commandRuns,
      failedCommands: failedCommands ?? this.failedCommands,
      internetActions: internetActions ?? this.internetActions,
      progressRevision: progressRevision ?? this.progressRevision,
      lastTool: lastTool ?? this.lastTool,
      lastToolResultPreview:
          lastToolResultPreview ?? this.lastToolResultPreview,
      lastCommand: lastCommand ?? this.lastCommand,
      lastCommandResultPreview:
          lastCommandResultPreview ?? this.lastCommandResultPreview,
      lastCommandExitCode: lastCommandExitCode ?? this.lastCommandExitCode,
      lastError: lastError ?? this.lastError,
      evidenceSummary: evidenceSummary ?? this.evidenceSummary,
      evidenceItems: evidenceItems ?? this.evidenceItems,
      toolGuardState: toolGuardState ?? this.toolGuardState,
      messageCount: messageCount ?? this.messageCount,
      buildFailureKind: buildFailureKind ?? this.buildFailureKind,
      buildFailureSummary: buildFailureSummary ?? this.buildFailureSummary,
      buildFailureRecommendedAction: buildFailureRecommendedAction ??
          this.buildFailureRecommendedAction,
      buildFailureImplicatedFiles: buildFailureImplicatedFiles ??
          this.buildFailureImplicatedFiles,
      buildFailureImplicatedLines: buildFailureImplicatedLines ??
          this.buildFailureImplicatedLines,
      buildSuggestedDiagnostic:
          buildSuggestedDiagnostic ?? this.buildSuggestedDiagnostic,
      buildSuggestedRecovery:
          buildSuggestedRecovery ?? this.buildSuggestedRecovery,
      buildMissingDependency:
          buildMissingDependency ?? this.buildMissingDependency,
      buildLocatedDependencyPath:
          buildLocatedDependencyPath ?? this.buildLocatedDependencyPath,
      buildRetryRequired: buildRetryRequired ?? this.buildRetryRequired,
      requiredBuildRetryCommand:
          requiredBuildRetryCommand ?? this.requiredBuildRetryCommand,
      requiredBuildRetryWorkingDirectory: requiredBuildRetryWorkingDirectory ??
          this.requiredBuildRetryWorkingDirectory,
      buildMutationAwaitingRetry:
          buildMutationAwaitingRetry ?? this.buildMutationAwaitingRetry,
      buildFailureRevision:
          buildFailureRevision ?? this.buildFailureRevision,
      buildDiagnosticsRun: buildDiagnosticsRun ?? this.buildDiagnosticsRun,
      fileReadAtBuildFailureRevision: fileReadAtBuildFailureRevision ??
          this.fileReadAtBuildFailureRevision,
      fileReadRangesAtBuildFailureRevision:
          fileReadRangesAtBuildFailureRevision ??
              this.fileReadRangesAtBuildFailureRevision,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': 4,
        'runId': runId,
        'projectPath': projectPath,
        'prompt': prompt,
        'status': status.name,
        'iteration': iteration,
        'maxIterations': maxIterations,
        'startedAt': startedAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'plan': plan,
        'toolActions': toolActions,
        'fileMutations': fileMutations,
        'commandRuns': commandRuns,
        'failedCommands': failedCommands,
        'internetActions': internetActions,
        'progressRevision': progressRevision,
        'lastTool': lastTool,
        'lastToolResultPreview': lastToolResultPreview,
        'lastCommand': lastCommand,
        'lastCommandResultPreview': lastCommandResultPreview,
        'lastCommandExitCode': lastCommandExitCode,
        'lastError': lastError,
        'evidenceSummary': evidenceSummary,
        'evidenceItems': evidenceItems,
        'toolGuardState': toolGuardState,
        'messageCount': messageCount,
        'buildFailureKind': buildFailureKind,
        'buildFailureSummary': buildFailureSummary,
        'buildFailureRecommendedAction': buildFailureRecommendedAction,
        'buildFailureImplicatedFiles': buildFailureImplicatedFiles,
        'buildFailureImplicatedLines': buildFailureImplicatedLines,
        'buildSuggestedDiagnostic': buildSuggestedDiagnostic,
        'buildSuggestedRecovery': buildSuggestedRecovery,
        'buildMissingDependency': buildMissingDependency,
        'buildLocatedDependencyPath': buildLocatedDependencyPath,
        'buildRetryRequired': buildRetryRequired,
        'requiredBuildRetryCommand': requiredBuildRetryCommand,
        'requiredBuildRetryWorkingDirectory':
            requiredBuildRetryWorkingDirectory,
        'buildMutationAwaitingRetry': buildMutationAwaitingRetry,
        'buildFailureRevision': buildFailureRevision,
        'buildDiagnosticsRun': buildDiagnosticsRun,
        'fileReadAtBuildFailureRevision': fileReadAtBuildFailureRevision,
        'fileReadRangesAtBuildFailureRevision':
            fileReadRangesAtBuildFailureRevision,
      };

  factory AgentRunCheckpoint.fromJson(Map<String, dynamic> json) {
    final statusName = json['status']?.toString() ?? '';
    final rawEvidence = json['evidenceItems'];
    final evidenceItems = <Map<String, dynamic>>[];
    if (rawEvidence is List) {
      for (final item in rawEvidence.whereType<Map>().take(300)) {
        evidenceItems.add(
          item.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    }
    final rawGuard = json['toolGuardState'];
    final toolGuardState = rawGuard is Map
        ? rawGuard.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    final implicatedFiles = _asStringList(json['buildFailureImplicatedFiles']);
    final implicatedLines = _asStringIntMap(json['buildFailureImplicatedLines']);
    final diagnostics = _asStringList(json['buildDiagnosticsRun']);
    final rawReadRevisions = json['fileReadAtBuildFailureRevision'];
    final readRevisions = <String, int>{};
    if (rawReadRevisions is Map) {
      for (final entry in rawReadRevisions.entries.take(500)) {
        final key = entry.key.toString();
        if (key.isEmpty) continue;
        readRevisions[key] = _asInt(entry.value);
      }
    }
    final readRanges = _asStringStringMap(
      json['fileReadRangesAtBuildFailureRevision'],
    );
    return AgentRunCheckpoint(
      runId: json['runId']?.toString() ?? '',
      projectPath: json['projectPath']?.toString() ?? '',
      prompt: json['prompt']?.toString() ?? '',
      status: AgentRunStatus.values.firstWhere(
        (value) => value.name == statusName,
        orElse: () => AgentRunStatus.interrupted,
      ),
      iteration: _asInt(json['iteration']),
      maxIterations: _asInt(json['maxIterations'], fallback: 120),
      startedAt: DateTime.tryParse(json['startedAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
      plan: json['plan']?.toString() ?? '',
      toolActions: _asInt(json['toolActions']),
      fileMutations: _asInt(json['fileMutations']),
      commandRuns: _asInt(json['commandRuns']),
      failedCommands: _asInt(json['failedCommands']),
      internetActions: _asInt(json['internetActions']),
      progressRevision: _asInt(json['progressRevision']),
      lastTool: json['lastTool']?.toString() ?? '',
      lastToolResultPreview: json['lastToolResultPreview']?.toString() ?? '',
      lastCommand: json['lastCommand']?.toString() ?? '',
      lastCommandResultPreview:
          json['lastCommandResultPreview']?.toString() ?? '',
      lastCommandExitCode: _asNullableInt(json['lastCommandExitCode']),
      lastError: json['lastError']?.toString() ?? '',
      evidenceSummary: json['evidenceSummary']?.toString() ?? '',
      evidenceItems: evidenceItems,
      toolGuardState: toolGuardState,
      messageCount: _asInt(json['messageCount']),
      buildFailureKind: json['buildFailureKind']?.toString() ?? '',
      buildFailureSummary: json['buildFailureSummary']?.toString() ?? '',
      buildFailureRecommendedAction:
          json['buildFailureRecommendedAction']?.toString() ?? '',
      buildFailureImplicatedFiles: implicatedFiles,
      buildFailureImplicatedLines: implicatedLines,
      buildSuggestedDiagnostic:
          json['buildSuggestedDiagnostic']?.toString() ?? '',
      buildSuggestedRecovery:
          json['buildSuggestedRecovery']?.toString() ?? '',
      buildMissingDependency:
          json['buildMissingDependency']?.toString() ?? '',
      buildLocatedDependencyPath:
          json['buildLocatedDependencyPath']?.toString() ?? '',
      buildRetryRequired: _asBool(json['buildRetryRequired']),
      requiredBuildRetryCommand:
          json['requiredBuildRetryCommand']?.toString() ?? '',
      requiredBuildRetryWorkingDirectory:
          json['requiredBuildRetryWorkingDirectory']?.toString() ?? '',
      buildMutationAwaitingRetry:
          _asBool(json['buildMutationAwaitingRetry']),
      buildFailureRevision: _asInt(json['buildFailureRevision']),
      buildDiagnosticsRun: diagnostics,
      fileReadAtBuildFailureRevision: readRevisions,
      fileReadRangesAtBuildFailureRevision: readRanges,
    );
  }

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  static List<String> _asStringList(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .take(500)
        .toList(growable: false);
  }

  static Map<String, String> _asStringStringMap(Object? value) {
    if (value is! Map) return const <String, String>{};
    final result = <String, String>{};
    for (final entry in value.entries.take(500)) {
      final key = entry.key.toString();
      if (key.trim().isEmpty) continue;
      result[key] = entry.value.toString();
    }
    return result;
  }

  static Map<String, int> _asStringIntMap(Object? value) {
    if (value is! Map) return const <String, int>{};
    final result = <String, int>{};
    for (final entry in value.entries.take(500)) {
      final key = entry.key.toString();
      if (key.trim().isEmpty) continue;
      result[key] = _asInt(entry.value);
    }
    return result;
  }

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  static int _asInt(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static int? _asNullableInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}
