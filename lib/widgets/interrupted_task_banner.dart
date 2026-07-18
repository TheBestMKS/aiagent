import 'package:flutter/material.dart';

import '../controllers/agent_controller.dart';

class InterruptedTaskBanner extends StatelessWidget {
  const InterruptedTaskBanner({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final AgentController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final checkpoint = controller.interruptedRunCheckpoint;
    if (checkpoint == null) return const SizedBox.shrink();
    final theme = Theme.of(context);

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Найдена незавершённая задача',
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          checkpoint.prompt,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          'Запуск ${checkpoint.runId} · '
          'итерация ${checkpoint.iteration}/${checkpoint.maxIterations} · '
          'действий ${checkpoint.toolActions} · '
          'изменений ${checkpoint.fileMutations} · '
          'команд ${checkpoint.commandRuns}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );

    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        OutlinedButton(
          onPressed: controller.busy
              ? null
              : () async {
                  await controller.dismissInterruptedTask();
                  onChanged();
                },
          child: const Text('Не продолжать'),
        ),
        FilledButton.icon(
          onPressed: controller.busy
              ? null
              : () async {
                  final future = controller.resumeInterruptedTask();
                  onChanged();
                  await future;
                  onChanged();
                },
          icon: const Icon(Icons.play_arrow),
          label: const Text('Продолжить'),
        ),
      ],
    );

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 620) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.restore),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: details),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.restore),
                ),
                const SizedBox(width: 10),
                Expanded(child: details),
                const SizedBox(width: 10),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }
}
