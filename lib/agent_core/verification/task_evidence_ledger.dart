import 'dart:convert';

import '../security/secret_redactor.dart';
import 'verification_command_classifier.dart';

enum TaskEvidenceType {
  plan,
  fileMutation,
  command,
  test,
  read,
  research,
  memory,
  verification,
  permission,
  failure,
  tool,
}

class TaskEvidenceItem {
  const TaskEvidenceItem({
    required this.time,
    required this.type,
    required this.title,
    required this.detail,
    required this.successful,
  });

  final DateTime time;
  final TaskEvidenceType type;
  final String title;
  final String detail;
  final bool successful;

  factory TaskEvidenceItem.fromJson(Map<String, dynamic> json) {
    final typeName = json['type']?.toString() ?? '';
    return TaskEvidenceItem(
      time: DateTime.tryParse(json['time']?.toString() ?? '') ?? DateTime.now(),
      type: TaskEvidenceType.values.firstWhere(
        (value) => value.name == typeName,
        orElse: () => TaskEvidenceType.tool,
      ),
      title: SecretRedactor.redact(json['title']?.toString() ?? ''),
      detail: SecretRedactor.redact(json['detail']?.toString() ?? ''),
      successful: json['successful'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'type': type.name,
        'title': title,
        'detail': detail,
        'successful': successful,
      };
}

class TaskEvidenceLedger {
  final List<TaskEvidenceItem> _items = [];

  List<TaskEvidenceItem> get items => List.unmodifiable(_items);

  void reset() => _items.clear();

  void restoreFromJson(Iterable<Map<String, dynamic>> items) {
    _items
      ..clear()
      ..addAll(items.map(TaskEvidenceItem.fromJson).take(300));
  }

  List<Map<String, dynamic>> toJsonItems({int maxItems = 120}) =>
      _items.reversed
          .take(maxItems.clamp(1, 300).toInt())
          .toList(growable: false)
          .reversed
          .map((item) => item.toJson())
          .toList(growable: false);

  void add({
    required TaskEvidenceType type,
    required String title,
    required String detail,
    required bool successful,
  }) {
    _items.add(TaskEvidenceItem(
      time: DateTime.now(),
      type: type,
      title: SecretRedactor.redact(title.trim()),
      detail: _limit(SecretRedactor.redact(detail.trim()), 6000),
      successful: successful,
    ));
    if (_items.length > 300) _items.removeRange(0, _items.length - 300);
  }

  void recordTool({
    required String toolName,
    required Map<String, dynamic> args,
    required String result,
    required bool successful,
  }) {
    final type = _typeForTool(toolName, args, result);
    add(
      type: successful ? type : TaskEvidenceType.failure,
      title: toolName,
      detail: 'ARGS: ${_safeArgs(args)}\nRESULT: ${_limit(result, 5000)}',
      successful: successful,
    );
  }

  bool get hasPassingVerification =>
      latestPassingVerificationAfterLastFailure != null;

  TaskEvidenceItem? get latestPassingVerificationAfterLastFailure {
    var lastFailureIndex = -1;
    for (var index = 0; index < _items.length; index++) {
      if (!_items[index].successful) lastFailureIndex = index;
    }
    for (var index = _items.length - 1; index > lastFailureIndex; index--) {
      final item = _items[index];
      if (item.successful &&
          const {
            TaskEvidenceType.test,
            TaskEvidenceType.verification,
          }.contains(item.type)) {
        return item;
      }
    }
    return null;
  }

  String get groundedVerificationSummary {
    final item = latestPassingVerificationAfterLastFailure;
    if (item == null) return '';
    return '${item.title}: ${_resultSignal(item.detail)}';
  }

  bool get hasSuccessfulMutation => _items.any(
      (item) => item.successful && item.type == TaskEvidenceType.fileMutation);

  bool get hasSuccessfulResearch => _items
      .any((item) => item.successful && item.type == TaskEvidenceType.research);

  int get failureCount => _items.where((item) => !item.successful).length;

  List<String> failedApproaches({int maxItems = 6}) => _items
      .where((item) => !item.successful)
      .map((item) => '${item.title}: ${_resultSignal(item.detail)}')
      .toSet()
      .take(maxItems)
      .toList(growable: false);

  List<String> successfulApproaches({int maxItems = 8}) => _items
      .where((item) => item.successful)
      .map((item) => '${item.title}: ${_resultSignal(item.detail)}')
      .toSet()
      .toList(growable: false)
      .reversed
      .take(maxItems)
      .toList(growable: false)
      .reversed
      .toList(growable: false);

  double confidence({
    required bool expectsMutation,
    required bool expectsVerification,
    required bool expectsResearch,
  }) {
    var score = 0.35;
    if (!expectsMutation || hasSuccessfulMutation) score += 0.20;
    if (!expectsVerification || hasPassingVerification) score += 0.30;
    if (!expectsResearch || hasSuccessfulResearch) score += 0.15;
    score -= (failureCount * 0.025).clamp(0.0, 0.20).toDouble();
    return score.clamp(0.0, 1.0).toDouble();
  }

  String summary({int maxItems = 12}) {
    if (_items.isEmpty) return 'TASK_EVIDENCE: none';
    final successful = _items.where((item) => item.successful).length;
    final buffer = StringBuffer(
      'TASK_EVIDENCE: total=${_items.length}; successful=$successful; '
      'failed=$failureCount; passing_verification=$hasPassingVerification',
    );
    for (final item in _items.reversed.take(maxItems).toList().reversed) {
      buffer.writeln();
      buffer.write(
        '- [${item.successful ? 'OK' : 'FAIL'}] ${item.type.name}: '
        '${item.title} — ${_compactAttempt(item.detail)}',
      );
    }
    return buffer.toString();
  }

  String decisionContext({int maxItems = 20}) {
    if (_items.isEmpty) return 'ATTEMPT_MEMORY: no attempts recorded yet.';
    final recent = _items.reversed
        .take(maxItems.clamp(1, 60).toInt())
        .toList(growable: false)
        .reversed;
    final buffer = StringBuffer('ATTEMPT_MEMORY: preserve these outcomes.');
    for (final item in recent) {
      buffer
        ..writeln()
        ..write('- ${item.successful ? 'SUCCESS' : 'FAILED'} ${item.title}: '
            '${_compactAttempt(item.detail, maxChars: 700)}');
    }
    final failures = failedApproaches(maxItems: 8);
    if (failures.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('DO_NOT_REPEAT_WITHOUT_NEW_EVIDENCE:');
      for (final failure in failures) {
        buffer.writeln('- $failure');
      }
    }
    final successes = successfulApproaches(maxItems: 8);
    if (successes.isNotEmpty) {
      buffer.writeln('REUSE_CONFIRMED_RESULTS:');
      for (final success in successes) {
        buffer.writeln('- $success');
      }
    }
    return buffer.toString().trimRight();
  }

  String toJsonLine() => jsonEncode({
        'time': DateTime.now().toIso8601String(),
        'items': _items.map((item) => item.toJson()).toList(growable: false),
      });

  TaskEvidenceType _typeForTool(
    String toolName,
    Map<String, dynamic> args,
    String result,
  ) {
    if (toolName == 'set_task_plan' ||
        toolName == 'define_task_goal' ||
        toolName == 'add_task_subtask' ||
        toolName == 'update_task_subtask') {
      return TaskEvidenceType.plan;
    }
    if (const {
      'write_file',
      'create_file',
      'append_file',
      'replace_text',
      'make_dir',
      'delete_path',
      'copy_path',
      'move_path',
      'create_document_from_text',
      'edit_document_text',
      'package_project_release',
    }.contains(toolName)) {
      return TaskEvidenceType.fileMutation;
    }
    if (toolName == 'run_tests') {
      final command = args['command']?.toString().trim() ?? '';
      final passed = result.contains('EXIT_CODE: 0') ||
          result.contains('FINAL_STATUS: SUCCESS') ||
          result.contains('BUILD_ARTIFACT_OK');
      if (!passed) return TaskEvidenceType.command;
      if (command.isEmpty) return TaskEvidenceType.test;
      return VerificationCommandClassifier.isVerificationCommand(command)
          ? TaskEvidenceType.test
          : TaskEvidenceType.command;
    }
    if (toolName == 'run_command') {
      final command = args['command']?.toString() ?? '';
      final passed = result.contains('EXIT_CODE: 0') ||
          result.contains('FINAL_STATUS: SUCCESS') ||
          result.contains('BUILD_ARTIFACT_OK');
      return passed &&
              VerificationCommandClassifier.isVerificationCommand(command)
          ? TaskEvidenceType.verification
          : TaskEvidenceType.command;
    }
    if (const {
      'terminal_open',
      'terminal_write',
      'terminal_close',
    }.contains(toolName)) {
      return TaskEvidenceType.command;
    }
    if (const {'terminal_read', 'terminal_list'}.contains(toolName)) {
      return TaskEvidenceType.read;
    }
    if (const {
      'duckduckgo_search',
      'web_fetch',
      'web_deep_fetch',
      'web_research',
    }.contains(toolName)) {
      return TaskEvidenceType.research;
    }
    if (toolName.startsWith('memory_') ||
        toolName == 'knowledge_store' ||
        toolName == 'promote_golden_path') {
      return TaskEvidenceType.memory;
    }
    if (toolName.startsWith('read_') ||
        toolName.startsWith('list_') ||
        toolName.contains('search')) {
      return TaskEvidenceType.read;
    }
    return TaskEvidenceType.tool;
  }

  String _safeArgs(Map<String, dynamic> args) {
    final safe = SecretRedactor.redactObject(args);
    return _limit(SecretRedactor.redact(jsonEncode(safe)), 1800);
  }

  String _firstLine(String value) => value
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');

  String _compactAttempt(String value, {int maxChars = 420}) {
    final args =
        RegExp(r'ARGS:\s*([^\r\n]*)').firstMatch(value)?.group(1) ?? '';
    final result = _resultSignal(value);
    final combined = [
      if (args.trim().isNotEmpty) 'args=${_limit(args.trim(), 180)}',
      if (result.trim().isNotEmpty) 'result=$result',
    ].join('; ');
    return _limit(combined.isEmpty ? _firstLine(value) : combined, maxChars)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _resultSignal(String value) {
    final resultIndex = value.indexOf('RESULT:');
    final source = resultIndex >= 0
        ? value.substring(resultIndex + 'RESULT:'.length)
        : value;
    final lines = source
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) return '';
    final signalPattern = RegExp(
      r'(FINAL_STATUS|EXIT_CODE|PROCESS_EXIT_CODE|BUILD_FAILURE_ANALYSIS|'
      r'BUILD_ARTIFACT|FAILED|ERROR|DENIED|NOT_FOUND|SUCCESS|created|updated|'
      r'replaced|found|completed)',
      caseSensitive: false,
    );
    final selected = <String>[];
    for (final line in lines) {
      if (signalPattern.hasMatch(line) && !selected.contains(line)) {
        selected.add(line);
      }
      if (selected.length >= 3) break;
    }
    if (selected.isEmpty) selected.add(lines.first);
    return _limit(selected.join(' | '), 360)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _limit(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    final half = maxChars ~/ 2;
    return '${value.substring(0, half)}\n...<truncated>...\n'
        '${value.substring(value.length - half)}';
  }
}
