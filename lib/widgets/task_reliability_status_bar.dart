import 'package:flutter/material.dart';

import '../agent_core/runs/agent_run_checkpoint.dart';
import '../agent_core/verification/task_completion_gate.dart';
import '../controllers/agent_controller.dart';

class TaskReliabilityStatusBar extends StatelessWidget {
  const TaskReliabilityStatusBar({
    super.key,
    required this.controller,
  });

  final AgentController controller;

  @override
  Widget build(BuildContext context) {
    final checkpoint = controller.activeRunCheckpoint;
    if (checkpoint == null) return const SizedBox.shrink();
    final maxIterations = checkpoint.maxIterations <= 0
        ? 1
        : checkpoint.maxIterations;
    final progress =
        (checkpoint.iteration / maxIterations).clamp(0.0, 1.0).toDouble();
    final completion = controller.currentTaskCompletionAssessment();
    final buildFailure = controller.lastBuildFailureAnalysis;
    final buildState = buildFailure == null
        ? ''
        : ' · сборка: ${buildFailure.kind.name}'
            '${controller.buildRetryRequired ? ' (нужен повтор)' : ''}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: LinearProgressIndicator(value: progress),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${checkpoint.status.label}: '
              '${checkpoint.iteration}/${checkpoint.maxIterations} · '
              'доказательств ${controller.taskEvidenceLedger.items.length} · '
              'блокировок ${controller.toolExecutionGuard.blockedCalls} · '
              '${completion.state.label} ${(completion.confidence * 100).round()}%'
              '$buildState',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}
