import 'dart:convert';
import 'dart:io';

import '../../utils/path_utils.dart';
import '../security/secret_redactor.dart';
import 'project_task_mode.dart';
import 'task_intent_analyzer.dart';

enum TaskGoalStatus {
  active,
  awaitingUser,
  blocked,
  completed,
  failed,
  cancelled,
}

enum TaskNodeStatus {
  pending,
  inProgress,
  blocked,
  completed,
  failed,
  skipped,
}

enum TaskNodeKind { discovery, execution, verification, delivery, custom }

class TaskContextFact {
  const TaskContextFact({
    required this.kind,
    required this.key,
    required this.value,
    required this.source,
    required this.verified,
    required this.updatedAt,
  });

  final String kind;
  final String key;
  final String value;
  final String source;
  final bool verified;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'key': key,
        'value': value,
        'source': source,
        'verified': verified,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory TaskContextFact.fromJson(Map<String, dynamic> json) =>
      TaskContextFact(
        kind: json['kind']?.toString() ?? 'context',
        key: json['key']?.toString() ?? '',
        value: json['value']?.toString() ?? '',
        source: json['source']?.toString() ?? '',
        verified: json['verified'] == true,
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class TaskNode {
  const TaskNode({
    required this.id,
    required this.title,
    required this.expectedResult,
    required this.kind,
    required this.status,
    required this.result,
    required this.evidence,
    required this.artifacts,
    required this.attempts,
    required this.nextAction,
    required this.children,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String expectedResult;
  final TaskNodeKind kind;
  final TaskNodeStatus status;
  final String result;
  final List<String> evidence;
  final List<String> artifacts;
  final int attempts;
  final String nextAction;
  final List<TaskNode> children;
  final DateTime updatedAt;

  bool get isDone =>
      status == TaskNodeStatus.completed || status == TaskNodeStatus.skipped;

  double get completion {
    if (children.isNotEmpty) {
      return children.fold<double>(0, (sum, child) => sum + child.completion) /
          children.length;
    }
    return switch (status) {
      TaskNodeStatus.completed || TaskNodeStatus.skipped => 1,
      TaskNodeStatus.inProgress => 0.35,
      TaskNodeStatus.blocked || TaskNodeStatus.failed => 0.15,
      TaskNodeStatus.pending => 0,
    };
  }

  TaskNode copyWith({
    String? title,
    String? expectedResult,
    TaskNodeKind? kind,
    TaskNodeStatus? status,
    String? result,
    List<String>? evidence,
    List<String>? artifacts,
    int? attempts,
    String? nextAction,
    List<TaskNode>? children,
    DateTime? updatedAt,
  }) =>
      TaskNode(
        id: id,
        title: title ?? this.title,
        expectedResult: expectedResult ?? this.expectedResult,
        kind: kind ?? this.kind,
        status: status ?? this.status,
        result: result ?? this.result,
        evidence: evidence ?? this.evidence,
        artifacts: artifacts ?? this.artifacts,
        attempts: attempts ?? this.attempts,
        nextAction: nextAction ?? this.nextAction,
        children: children ?? this.children,
        updatedAt: updatedAt ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'expectedResult': expectedResult,
        'kind': kind.name,
        'status': status.name,
        'completionPercent': (completion * 100).round(),
        'result': result,
        'evidence': evidence,
        'artifacts': artifacts,
        'attempts': attempts,
        'nextAction': nextAction,
        'children': children.map((item) => item.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory TaskNode.fromJson(Map<String, dynamic> json) => TaskNode(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        expectedResult: json['expectedResult']?.toString() ?? '',
        kind: TaskNodeKind.values.firstWhere(
          (item) => item.name == json['kind']?.toString(),
          orElse: () => TaskNodeKind.custom,
        ),
        status: TaskNodeStatus.values.firstWhere(
          (item) => item.name == json['status']?.toString(),
          orElse: () => TaskNodeStatus.pending,
        ),
        result: json['result']?.toString() ?? '',
        evidence: _strings(json['evidence']),
        artifacts: _strings(json['artifacts']),
        attempts: _integer(json['attempts']),
        nextAction: json['nextAction']?.toString() ?? '',
        children: (json['children'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((item) => TaskNode.fromJson(
                item.map((key, value) => MapEntry(key.toString(), value))))
            .toList(growable: false),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class TaskExecutionState {
  const TaskExecutionState({
    required this.taskId,
    required this.projectPath,
    required this.projectMode,
    required this.detectedDomain,
    required this.originalPrompt,
    required this.expectedResult,
    required this.goalDefined,
    required this.expectsMutation,
    required this.status,
    required this.subtasks,
    required this.contextFacts,
    required this.finalResult,
    required this.resultArtifacts,
    required this.blocker,
    required this.questionForUser,
    required this.createdAt,
    required this.updatedAt,
  });

  final String taskId;
  final String projectPath;
  final ProjectTaskMode projectMode;
  final String detectedDomain;
  final String originalPrompt;
  final String expectedResult;
  final bool goalDefined;
  final bool expectsMutation;
  final TaskGoalStatus status;
  final List<TaskNode> subtasks;
  final List<TaskContextFact> contextFacts;
  final String finalResult;
  final List<String> resultArtifacts;
  final String blocker;
  final String questionForUser;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get completionPercent {
    if (status == TaskGoalStatus.completed) return 100;
    if (subtasks.isEmpty) return 0;
    final value = subtasks.fold<double>(
          0,
          (sum, item) => sum + item.completion,
        ) /
        subtasks.length;
    return (value * 100).round().clamp(0, 99).toInt();
  }

  int get nodeCount {
    int count(Iterable<TaskNode> nodes) => nodes.fold<int>(
          0,
          (total, node) => total + 1 + count(node.children),
        );
    return count(subtasks);
  }

  TaskNode? findNode(String id) {
    TaskNode? visit(Iterable<TaskNode> nodes) {
      for (final node in nodes) {
        if (node.id == id) return node;
        final child = visit(node.children);
        if (child != null) return child;
      }
      return null;
    }

    return visit(subtasks);
  }

  TaskExecutionState copyWith({
    String? expectedResult,
    bool? goalDefined,
    TaskGoalStatus? status,
    List<TaskNode>? subtasks,
    List<TaskContextFact>? contextFacts,
    String? finalResult,
    List<String>? resultArtifacts,
    String? blocker,
    String? questionForUser,
    DateTime? updatedAt,
  }) =>
      TaskExecutionState(
        taskId: taskId,
        projectPath: projectPath,
        projectMode: projectMode,
        detectedDomain: detectedDomain,
        originalPrompt: originalPrompt,
        expectedResult: expectedResult ?? this.expectedResult,
        goalDefined: goalDefined ?? this.goalDefined,
        expectsMutation: expectsMutation,
        status: status ?? this.status,
        subtasks: subtasks ?? this.subtasks,
        contextFacts: contextFacts ?? this.contextFacts,
        finalResult: finalResult ?? this.finalResult,
        resultArtifacts: resultArtifacts ?? this.resultArtifacts,
        blocker: blocker ?? this.blocker,
        questionForUser: questionForUser ?? this.questionForUser,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );

  TaskExecutionState defineGoal({
    required String expectedResult,
    required List<TaskNode> subtasks,
  }) {
    final normalized = _activateFirstPending(subtasks);
    return copyWith(
      expectedResult: SecretRedactor.redact(expectedResult.trim()),
      goalDefined: true,
      status: TaskGoalStatus.active,
      subtasks: normalized,
      blocker: '',
      questionForUser: '',
    );
  }

  TaskExecutionState addSubtask({
    required String parentId,
    required TaskNode node,
  }) {
    if (parentId.trim().isEmpty || parentId == 'root') {
      return copyWith(subtasks: _activateFirstPending([...subtasks, node]));
    }
    var found = false;
    TaskNode visit(TaskNode current) {
      if (current.id == parentId) {
        found = true;
        return current.copyWith(children: [...current.children, node]);
      }
      return current.copyWith(children: current.children.map(visit).toList());
    }

    final updated = subtasks.map(visit).toList(growable: false);
    return found ? copyWith(subtasks: _activateFirstPending(updated)) : this;
  }

  TaskExecutionState updateSubtask({
    required String nodeId,
    required TaskNodeStatus nodeStatus,
    String result = '',
    List<String> evidence = const [],
    List<String> artifacts = const [],
    String nextAction = '',
  }) {
    var found = false;
    TaskNode visit(TaskNode current) {
      if (current.id == nodeId) {
        found = true;
        return current.copyWith(
          status: nodeStatus,
          result: result.trim().isEmpty
              ? current.result
              : SecretRedactor.redact(_limit(result.trim(), 5000)),
          evidence: _mergeStrings(current.evidence, evidence),
          artifacts: _mergeStrings(current.artifacts, artifacts),
          attempts: nodeStatus == TaskNodeStatus.failed ||
                  nodeStatus == TaskNodeStatus.blocked
              ? current.attempts + 1
              : current.attempts,
          nextAction: SecretRedactor.redact(nextAction.trim()),
          children: current.children,
        );
      }
      return current.copyWith(children: current.children.map(visit).toList());
    }

    final updated = subtasks.map(visit).toList(growable: false);
    if (!found) return this;
    return copyWith(subtasks: _activateFirstPending(updated));
  }

  TaskExecutionState rememberFact(TaskContextFact fact) {
    final safe = TaskContextFact(
      kind: fact.kind.trim(),
      key: SecretRedactor.redact(fact.key.trim()),
      value: SecretRedactor.redact(_limit(fact.value.trim(), 3500)),
      source: SecretRedactor.redact(fact.source.trim()),
      verified: fact.verified,
      updatedAt: fact.updatedAt,
    );
    final retained = contextFacts
        .where((item) => !(item.kind == safe.kind && item.key == safe.key))
        .toList();
    retained.add(safe);
    return copyWith(
      contextFacts: retained.length <= 80
          ? retained
          : retained.sublist(retained.length - 80),
    );
  }

  TaskExecutionState observeTool({
    required String toolName,
    required Map<String, dynamic> args,
    required String result,
    required bool successful,
    required int fileMutations,
    required int? lastExitCode,
  }) {
    var state = this;
    final now = DateTime.now();
    final readTools = <String>{
      'project_map',
      'list_files',
      'list_local_tools',
      'read_file',
      'read_document_structure',
      'filesystem_search',
      'list_device_directory',
      'read_device_text_file',
      'read_device_folder_texts',
      'search_device_index',
      'search_device_documents',
      'duckduckgo_search',
      'web_fetch',
      'web_deep_fetch',
      'web_research',
      'terminal_read',
      'wsl_list',
    };
    final executionTools = <String>{
      'write_file',
      'create_file',
      'append_file',
      'replace_text',
      'make_dir',
      'copy_path',
      'move_path',
      'edit_document_text',
      'create_document_from_text',
      'run_command',
      'terminal_open',
      'terminal_write',
      'package_project_release',
    };
    final verificationTools = <String>{
      'run_tests',
      'inspect_zip',
      'read_document_structure',
      'read_docx_text',
      'read_xlsx_text',
      'terminal_read',
    };

    if (successful && readTools.contains(toolName)) {
      state = state._completeKind(
        TaskNodeKind.discovery,
        'Контекст изучен инструментом $toolName.',
        _limit(result, 1600),
      );
      final contextKey = (args['path'] ??
              args['root'] ??
              args['url'] ??
              args['query'] ??
              args['purpose'] ??
              toolName)
          .toString()
          .trim();
      state = state.rememberFact(TaskContextFact(
        kind: 'tool_result',
        key: '$toolName:${contextKey.isEmpty ? toolName : contextKey}',
        value: _limit(result, 3500),
        source: toolName,
        verified: true,
        updatedAt: now,
      ));
    }
    if (successful &&
        (executionTools.contains(toolName) || fileMutations > 0)) {
      state = state._completeKind(
        TaskNodeKind.execution,
        'Основное действие подтверждено инструментом $toolName.',
        _limit(result, 1600),
      );
    }
    if (successful &&
        verificationTools.contains(toolName) &&
        (lastExitCode == null || lastExitCode == 0)) {
      state = state._completeKind(
        TaskNodeKind.verification,
        'Проверка выполнена инструментом $toolName.',
        _limit(result, 1800),
      );
    }

    if (toolName == 'run_command' || toolName == 'run_tests') {
      final command = args['command']?.toString().trim() ?? '';
      if (command.isNotEmpty) {
        state = state.rememberFact(TaskContextFact(
          kind: lastExitCode == 0 ? 'successful_command' : 'failed_command',
          key: command,
          value:
              'cwd=${args['cwd'] ?? '.'}; exit=${lastExitCode ?? 'unknown'}; '
              '${_limit(result, 2600)}',
          source: toolName,
          verified: successful && lastExitCode == 0,
          updatedAt: now,
        ));
      }
    }
    if (successful &&
        const {'read_file', 'read_document_structure'}.contains(toolName)) {
      final path = args['path']?.toString().trim() ?? '';
      if (path.isNotEmpty) {
        state = state.rememberFact(TaskContextFact(
          kind: 'relevant_file',
          key: path,
          value: _limit(result, 3500),
          source: toolName,
          verified: true,
          updatedAt: now,
        ));
      }
    }
    if (successful && toolName == 'terminal_open') {
      state = state.rememberFact(TaskContextFact(
        kind: 'terminal_session',
        key: args['session_id']?.toString() ?? 'terminal',
        value: _limit(result, 2200),
        source: toolName,
        verified: true,
        updatedAt: now,
      ));
    }
    return state;
  }

  TaskExecutionState _completeKind(
      TaskNodeKind kind, String result, String evidence) {
    final candidate = _findFirstByKind(subtasks, kind);
    if (candidate == null || candidate.isDone) return this;
    return updateSubtask(
      nodeId: candidate.id,
      nodeStatus: TaskNodeStatus.completed,
      result: result,
      evidence: evidence.trim().isEmpty ? const [] : [evidence],
    );
  }

  TaskExecutionState awaitUser({
    required String blocker,
    required String question,
  }) =>
      copyWith(
        status: TaskGoalStatus.awaitingUser,
        blocker: SecretRedactor.redact(blocker.trim()),
        questionForUser: SecretRedactor.redact(question.trim()),
      );

  TaskExecutionState finish({
    required TaskGoalStatus finalStatus,
    required String result,
    List<String> artifacts = const [],
  }) {
    var nodes = subtasks;
    if (finalStatus == TaskGoalStatus.completed) {
      nodes = nodes.map((node) {
        if (node.kind != TaskNodeKind.delivery || node.isDone) return node;
        return node.copyWith(
          status: TaskNodeStatus.completed,
          result: 'Итог и результирующие файлы переданы пользователю.',
          artifacts: _mergeStrings(node.artifacts, artifacts),
        );
      }).toList(growable: false);
    }
    return copyWith(
      status: finalStatus,
      subtasks: nodes,
      finalResult: SecretRedactor.redact(result.trim()),
      resultArtifacts: _mergeStrings(resultArtifacts, artifacts),
      blocker: finalStatus == TaskGoalStatus.completed ? '' : blocker,
      questionForUser:
          finalStatus == TaskGoalStatus.completed ? '' : questionForUser,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': 1,
        'taskId': taskId,
        'projectPath': projectPath,
        'projectMode': projectMode.name,
        'detectedDomain': detectedDomain,
        'originalPrompt': originalPrompt,
        'expectedResult': expectedResult,
        'goalDefined': goalDefined,
        'expectsMutation': expectsMutation,
        'status': status.name,
        'completionPercent': completionPercent,
        'subtasks': subtasks.map((item) => item.toJson()).toList(),
        'contextFacts': contextFacts.map((item) => item.toJson()).toList(),
        'finalResult': finalResult,
        'resultArtifacts': resultArtifacts,
        'blocker': blocker,
        'questionForUser': questionForUser,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory TaskExecutionState.fromJson(Map<String, dynamic> json) =>
      TaskExecutionState(
        taskId: json['taskId']?.toString() ?? '',
        projectPath: json['projectPath']?.toString() ?? '',
        projectMode: ProjectTaskModeX.parse(json['projectMode']),
        detectedDomain: json['detectedDomain']?.toString() ?? 'general',
        originalPrompt: json['originalPrompt']?.toString() ?? '',
        expectedResult: json['expectedResult']?.toString() ?? '',
        goalDefined: json['goalDefined'] == true,
        expectsMutation: json['expectsMutation'] == true,
        status: TaskGoalStatus.values.firstWhere(
          (item) => item.name == json['status']?.toString(),
          orElse: () => TaskGoalStatus.active,
        ),
        subtasks: (json['subtasks'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((item) => TaskNode.fromJson(
                item.map((key, value) => MapEntry(key.toString(), value))))
            .toList(growable: false),
        contextFacts: (json['contextFacts'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((item) => TaskContextFact.fromJson(
                item.map((key, value) => MapEntry(key.toString(), value))))
            .toList(growable: false),
        finalResult: json['finalResult']?.toString() ?? '',
        resultArtifacts: _strings(json['resultArtifacts']),
        blocker: json['blocker']?.toString() ?? '',
        questionForUser: json['questionForUser']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
            DateTime.now(),
      );

  String toInvariantMarkdown() {
    final buffer = StringBuffer()
      ..writeln('[CANONICAL_TASK_STATE]')
      ..writeln('task_id=$taskId')
      ..writeln('project_mode=${projectMode.name}')
      ..writeln('detected_domain=$detectedDomain')
      ..writeln('status=${status.name}')
      ..writeln('completion_percent=$completionPercent')
      ..writeln('goal_defined=$goalDefined')
      ..writeln()
      ..writeln('ORIGINAL_USER_TASK:')
      ..writeln(originalPrompt.trim())
      ..writeln()
      ..writeln('EXPECTED_FINAL_RESULT:')
      ..writeln(expectedResult.trim())
      ..writeln()
      ..writeln('SUBTASKS:');
    void writeNodes(Iterable<TaskNode> nodes, int depth) {
      for (final node in nodes) {
        final indent = '  ' * depth;
        buffer
          ..writeln('$indent- [${node.status.name}] ${node.id}: ${node.title}')
          ..writeln('$indent  expected: ${node.expectedResult}');
        if (node.result.isNotEmpty) {
          buffer.writeln('$indent  result: ${node.result}');
        }
        if (node.evidence.isNotEmpty) {
          buffer.writeln('$indent  evidence: ${node.evidence.join(' | ')}');
        }
        if (node.artifacts.isNotEmpty) {
          buffer.writeln('$indent  artifacts: ${node.artifacts.join(' | ')}');
        }
        if (node.nextAction.isNotEmpty) {
          buffer.writeln('$indent  next: ${node.nextAction}');
        }
        writeNodes(node.children, depth + 1);
      }
    }

    writeNodes(subtasks, 0);
    buffer
      ..writeln()
      ..writeln('IMPORTANT_CONTEXT:');
    if (contextFacts.isEmpty) {
      buffer.writeln('- none');
    } else {
      for (final fact in contextFacts) {
        buffer.writeln(
          '- [${fact.verified ? 'verified' : 'unverified'}] '
          '${fact.kind}/${fact.key}: ${fact.value}',
        );
      }
    }
    if (blocker.isNotEmpty) buffer.writeln('\nBLOCKER: $blocker');
    if (questionForUser.isNotEmpty) {
      buffer.writeln('QUESTION_FOR_USER: $questionForUser');
    }
    if (resultArtifacts.isNotEmpty) {
      buffer.writeln('\nRESULT_ARTIFACTS: ${resultArtifacts.join(' | ')}');
    }
    if (finalResult.isNotEmpty) buffer.writeln('\nFINAL_RESULT: $finalResult');
    buffer.writeln('[/CANONICAL_TASK_STATE]');
    return buffer.toString().trimRight();
  }
}

class TaskGoalPlanner {
  const TaskGoalPlanner();

  TaskExecutionState create({
    required String taskId,
    required String projectPath,
    required ProjectTaskMode projectMode,
    required TaskIntentProfile intent,
    required String prompt,
    List<TaskContextFact> initialContext = const [],
  }) {
    final now = DateTime.now();
    final criteria = intent.completionCriteria.join(' ');
    final expected = _expectedResult(projectMode, intent, prompt, criteria);
    final nodes = <TaskNode>[
      _node(
        'scope',
        'Проверить исходные данные и рабочее окружение',
        _discoveryResult(projectMode, intent),
        TaskNodeKind.discovery,
        TaskNodeStatus.inProgress,
        now,
      ),
      _node(
        'execute',
        'Выполнить целевое действие',
        _executionResult(projectMode, prompt),
        TaskNodeKind.execution,
        TaskNodeStatus.pending,
        now,
      ),
      _node(
        'verify',
        'Проверить результат по требованиям пользователя',
        criteria,
        TaskNodeKind.verification,
        TaskNodeStatus.pending,
        now,
      ),
      _node(
        'deliver',
        'Собрать и передать итог',
        'Перечислены фактические результаты, проверки и пути всех '
            'результирующих файлов.',
        TaskNodeKind.delivery,
        TaskNodeStatus.pending,
        now,
      ),
    ];
    return TaskExecutionState(
      taskId: taskId,
      projectPath: projectPath,
      projectMode: projectMode,
      detectedDomain: intent.primaryDomain.name,
      originalPrompt: SecretRedactor.redact(prompt.trim()),
      expectedResult: expected,
      goalDefined: false,
      expectsMutation: intent.expectsMutation,
      status: TaskGoalStatus.active,
      subtasks: nodes,
      contextFacts: initialContext,
      finalResult: '',
      resultArtifacts: const [],
      blocker: '',
      questionForUser: '',
      createdAt: now,
      updatedAt: now,
    );
  }

  TaskNode _node(String id, String title, String expectedResult,
          TaskNodeKind kind, TaskNodeStatus status, DateTime now) =>
      TaskNode(
        id: id,
        title: title,
        expectedResult: expectedResult,
        kind: kind,
        status: status,
        result: '',
        evidence: const [],
        artifacts: const [],
        attempts: 0,
        nextAction: '',
        children: const [],
        updatedAt: now,
      );

  String _expectedResult(ProjectTaskMode mode, TaskIntentProfile intent,
      String prompt, String criteria) {
    final prefix = switch (mode) {
      ProjectTaskMode.software =>
        'Рабочая реализация с корректной структурой проекта, успешной '
            'сборкой/тестами и готовыми релизными файлами.',
      ProjectTaskMode.documents =>
        'Созданный или измененный документ с проверенными содержанием, '
            'структурой и расположением элементов.',
      ProjectTaskMode.fileSystem =>
        'Точные найденные или измененные файлы в заданной области с '
            'проверенными путями и результатами операций.',
      ProjectTaskMode.remoteSystems =>
        'Подтвержденное состояние удаленной системы и сохраненная '
            'интерактивная сессия, если она нужна пользователю.',
      ProjectTaskMode.pentesting =>
        'Проверенный результат в явно разрешенной области тестирования с '
            'доказательствами и без выхода за заданный scope.',
      ProjectTaskMode.automatic =>
        'Полностью выполненный исходный запрос с наблюдаемыми доказательствами.',
    };
    return '$prefix Исходная цель: ${prompt.trim()} Критерии: $criteria';
  }

  String _discoveryResult(ProjectTaskMode mode, TaskIntentProfile intent) {
    if (mode == ProjectTaskMode.automatic) {
      return 'Подтверждены тип задачи (${intent.primaryDomain.name}), '
          'входные данные, доступные инструменты и предполагаемый результат.';
    }
    return 'Подтверждены входные данные, ограничения, доступные инструменты '
        'и текущее состояние для режима «${mode.label}».';
  }

  String _executionResult(ProjectTaskMode mode, String prompt) =>
      'Выполнены все изменяющие, поисковые или управляющие действия, '
      'необходимые для запроса «${_limit(prompt.trim(), 1200)}», с учетом '
      'режима «${mode.label}».';
}

class TaskExecutionStateStore {
  TaskExecutionStateStore({required this.projectRoot});

  final Directory projectRoot;

  Directory get tasksRoot =>
      Directory(pathJoin(projectRoot.path, '.cppagent', 'tasks'));

  Directory taskDirectory(String taskId) =>
      Directory(pathJoin(tasksRoot.path, _safeId(taskId)));

  File stateFile(String taskId) =>
      File(pathJoin(taskDirectory(taskId).path, 'state.json'));

  File handoffFile(String taskId) =>
      File(pathJoin(taskDirectory(taskId).path, 'handoff.md'));

  File get activePointer => File(pathJoin(tasksRoot.path, 'active.json'));

  Future<void> initialize() => tasksRoot.create(recursive: true);

  Future<TaskExecutionState> begin(TaskExecutionState state) async {
    await initialize();
    await save(state);
    await _writeAtomic(
      activePointer,
      const JsonEncoder.withIndent('  ').convert({
        'taskId': state.taskId,
        'updatedAt': state.updatedAt.toIso8601String(),
      }),
    );
    return state;
  }

  Future<TaskExecutionState?> load(String taskId) async {
    final file = stateFile(taskId);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString(encoding: utf8));
      if (decoded is! Map) return null;
      final state = TaskExecutionState.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
      final expectedProject = Directory(projectRoot.path).absolute.path;
      final actualProject = Directory(state.projectPath).absolute.path;
      if (expectedProject.toLowerCase() != actualProject.toLowerCase()) {
        return null;
      }
      return state;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(TaskExecutionState state) async {
    final dir = taskDirectory(state.taskId);
    await dir.create(recursive: true);
    await _writeAtomic(
      stateFile(state.taskId),
      const JsonEncoder.withIndent('  ').convert(state.toJson()),
    );
    await _writeAtomic(handoffFile(state.taskId), state.toInvariantMarkdown());
  }

  Future<String> readInvariant(TaskExecutionState state) async {
    final file = handoffFile(state.taskId);
    if (await file.exists()) {
      return file.readAsString(encoding: utf8);
    }
    return state.toInvariantMarkdown();
  }

  Future<void> clearActivePointer(String taskId) async {
    if (!await activePointer.exists()) return;
    try {
      final decoded = jsonDecode(await activePointer.readAsString());
      if (decoded is Map && decoded['taskId']?.toString() != taskId) return;
    } catch (_) {}
    await activePointer.delete();
  }

  Future<void> _writeAtomic(File target, String value) async {
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(value, encoding: utf8, flush: true);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }

  String _safeId(String value) {
    final result = value
        .replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return result.isEmpty ? 'task' : result;
  }
}

TaskNode? _findFirstByKind(Iterable<TaskNode> nodes, TaskNodeKind kind) {
  for (final node in nodes) {
    if (node.kind == kind) return node;
    final child = _findFirstByKind(node.children, kind);
    if (child != null) return child;
  }
  return null;
}

List<TaskNode> _activateFirstPending(List<TaskNode> nodes) {
  var hasActive = false;
  bool scan(Iterable<TaskNode> current) {
    for (final node in current) {
      if (node.status == TaskNodeStatus.inProgress) return true;
      if (scan(node.children)) return true;
    }
    return false;
  }

  hasActive = scan(nodes);
  if (hasActive) return nodes;
  var activated = false;
  TaskNode visit(TaskNode node) {
    if (!activated && node.status == TaskNodeStatus.pending) {
      activated = true;
      return node.copyWith(status: TaskNodeStatus.inProgress);
    }
    return node.copyWith(children: node.children.map(visit).toList());
  }

  return nodes.map(visit).toList(growable: false);
}

List<String> _strings(Object? value) {
  if (value is! List) return const [];
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .take(500)
      .toList(growable: false);
}

List<String> _mergeStrings(Iterable<String> current, Iterable<String> added) {
  final result = <String>[];
  final seen = <String>{};
  for (final value in [...current, ...added]) {
    final safe = SecretRedactor.redact(_limit(value.trim(), 2500));
    if (safe.isEmpty || !seen.add(safe)) continue;
    result.add(safe);
  }
  return result.take(80).toList(growable: false);
}

int _integer(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _limit(String value, int maxChars) {
  if (value.length <= maxChars) return value;
  return '${value.substring(0, maxChars - 3)}...';
}
