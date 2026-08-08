import 'agent_run_checkpoint.dart';

enum AgentTerminationCause {
  none,
  userRequest,
  safetyGuard,
  userGuidanceRequired,
}

class AgentTerminationState {
  AgentTerminationCause _cause = AgentTerminationCause.none;
  String _reason = '';

  AgentTerminationCause get cause => _cause;
  String get reason => _reason;
  bool get shouldStop => _cause != AgentTerminationCause.none;
  bool get userRequested => _cause == AgentTerminationCause.userRequest;
  bool get safetyStopped => _cause == AgentTerminationCause.safetyGuard;
  bool get awaitingUser => _cause == AgentTerminationCause.userGuidanceRequired;

  void reset() {
    _cause = AgentTerminationCause.none;
    _reason = '';
  }

  void requestUserStop({
    String reason = 'Получена команда Stop от пользователя.',
  }) {
    _cause = AgentTerminationCause.userRequest;
    _reason = reason.trim();
  }

  void requestSafetyStop(String reason) {
    if (userRequested) return;
    _cause = AgentTerminationCause.safetyGuard;
    _reason = _normalizeSafetyReason(reason);
  }

  void requestUserGuidance(String reason) {
    if (userRequested) return;
    _cause = AgentTerminationCause.userGuidanceRequired;
    _reason = _normalizeSafetyReason(reason);
  }

  static String _normalizeSafetyReason(String reason) {
    return reason
        .trim()
        .replaceFirst(RegExp(r'^AGENT_STALLED_STOP:\s*'), '')
        .trim();
  }
}

class AgentLoopResult {
  const AgentLoopResult({
    required this.status,
    required this.outcome,
    this.reason = '',
  });

  final AgentRunStatus status;
  final String outcome;
  final String reason;

  static const completed = AgentLoopResult(
    status: AgentRunStatus.completed,
    outcome: 'Выполнено',
  );

  factory AgentLoopResult.userCancelled([String reason = '']) =>
      AgentLoopResult(
        status: AgentRunStatus.cancelled,
        outcome: 'Остановлено пользователем',
        reason: reason,
      );

  factory AgentLoopResult.safetyStopped(String reason) => AgentLoopResult(
        status: AgentRunStatus.stalled,
        outcome: 'Остановлено внутренней защитой от циклических действий',
        reason: reason,
      );

  factory AgentLoopResult.awaitingUser(String reason) => AgentLoopResult(
        status: AgentRunStatus.awaitingUser,
        outcome: 'Ожидается ответ пользователя',
        reason: reason,
      );

  factory AgentLoopResult.failed(String reason) => AgentLoopResult(
        status: AgentRunStatus.failed,
        outcome: 'Не выполнено',
        reason: reason,
      );

  factory AgentLoopResult.paused(String reason) => AgentLoopResult(
        status: AgentRunStatus.awaitingUser,
        outcome: 'Приостановлено, ожидается ответ пользователя',
        reason: reason,
      );
}

class AgentResultSummary {
  const AgentResultSummary._();

  static String build({
    required AgentLoopResult result,
    required int fileMutations,
    required int commandRuns,
    required int failedCommands,
    int? lastExitCode,
    String lastCommand = '',
    String lastCommandResult = '',
    String lastTool = '',
    String lastToolResult = '',
    String verification = '',
    String details = '',
  }) {
    final buffer = StringBuffer()
      ..writeln('**Результат выполнения задачи**')
      ..writeln()
      ..writeln('Статус: ${result.outcome}.');
    if (result.reason.trim().isNotEmpty) {
      buffer.writeln('Причина: ${result.reason.trim()}');
    }
    buffer
      ..writeln()
      ..writeln('- Изменений файлов: $fileMutations')
      ..writeln('- Команд выполнено: $commandRuns')
      ..writeln('- Команд с ошибками: $failedCommands');
    if (lastExitCode != null) {
      buffer.writeln('- Последний exit code: $lastExitCode');
    }
    if (lastCommand.trim().isNotEmpty) {
      buffer.writeln('- Последняя команда: ${_preview(lastCommand, 500)}');
    }
    if (lastCommandResult.trim().isNotEmpty) {
      buffer.writeln(
        '- Результат последней команды: ${_preview(lastCommandResult, 900)}',
      );
    } else if (lastTool.trim().isNotEmpty && lastToolResult.trim().isNotEmpty) {
      buffer.writeln(
        '- Последний инструмент: ${lastTool.trim()}; '
        '${_preview(lastToolResult, 900)}',
      );
    }
    if (verification.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Проверка: ${verification.trim()}');
    }
    if (details.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Итог:')
        ..writeln(details.trim());
    }
    return buffer.toString().trimRight();
  }

  static String _preview(String value, int maxChars) {
    final normalized = value
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join(' | ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.length <= maxChars) return normalized;
    return '${normalized.substring(0, maxChars - 3)}...';
  }
}
