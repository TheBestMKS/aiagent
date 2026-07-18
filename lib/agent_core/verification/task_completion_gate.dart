import 'task_evidence_ledger.dart';

enum TaskCompletionState {
  ready,
  needsEvidence,
  failed,
}

extension TaskCompletionStateX on TaskCompletionState {
  String get label => switch (this) {
        TaskCompletionState.ready => 'готово к завершению',
        TaskCompletionState.needsEvidence => 'нужны доказательства',
        TaskCompletionState.failed => 'есть ошибка проверки',
      };
}

class TaskCompletionAssessment {
  const TaskCompletionAssessment({
    required this.state,
    required this.confidence,
    required this.missingEvidence,
  });

  final TaskCompletionState state;
  final double confidence;
  final List<String> missingEvidence;

  bool get ready => state == TaskCompletionState.ready;

  String get summary {
    final percent = (confidence * 100).round();
    if (missingEvidence.isEmpty) {
      return 'COMPLETION_GATE: ${state.name}; confidence=$percent%; missing=none';
    }
    return 'COMPLETION_GATE: ${state.name}; confidence=$percent%; missing='
        '${missingEvidence.join(' | ')}';
  }

  String get userMessage {
    if (ready) return 'Результат подтверждён необходимыми доказательствами.';
    return 'Для завершения задачи не хватает: ${missingEvidence.join('; ')}.';
  }
}

class TaskCompletionGate {
  const TaskCompletionGate._();

  static TaskCompletionAssessment assess({
    required TaskEvidenceLedger evidence,
    required bool expectsMutation,
    required bool expectsVerification,
    required bool expectsResearch,
    required int? lastCommandExitCode,
    required int circuitBreakerBlocks,
  }) {
    final missing = <String>[];
    if (expectsMutation && !evidence.hasSuccessfulMutation) {
      missing.add('подтверждённого изменения файлов');
    }
    if (expectsVerification && !evidence.hasPassingVerification) {
      missing.add('успешной сборки, теста или анализа');
    }
    if (expectsResearch && !evidence.hasSuccessfulResearch) {
      missing.add('успешного исследования источников');
    }
    if (lastCommandExitCode != null && lastCommandExitCode != 0) {
      missing.add('исправления последней команды с exit code $lastCommandExitCode');
    }
    if (circuitBreakerBlocks > 0 &&
        expectsVerification &&
        !evidence.hasPassingVerification) {
      missing.add('новой стратегии после блокировки циклического действия');
    }

    final confidence = evidence.confidence(
      expectsMutation: expectsMutation,
      expectsVerification: expectsVerification,
      expectsResearch: expectsResearch,
    );
    final state = missing.isEmpty
        ? TaskCompletionState.ready
        : (lastCommandExitCode != null && lastCommandExitCode != 0
            ? TaskCompletionState.failed
            : TaskCompletionState.needsEvidence);
    return TaskCompletionAssessment(
      state: state,
      confidence: confidence,
      missingEvidence: List.unmodifiable(missing),
    );
  }
}
