import 'package:flutter/material.dart';

import '../agent_core/runs/agent_run_checkpoint.dart';
import '../controllers/agent_controller.dart';

class TaskRunHistoryDialog extends StatefulWidget {
  const TaskRunHistoryDialog({
    super.key,
    required this.controller,
  });

  final AgentController controller;

  @override
  State<TaskRunHistoryDialog> createState() => _TaskRunHistoryDialogState();
}

class _TaskRunHistoryDialogState extends State<TaskRunHistoryDialog> {
  late Future<List<AgentRunCheckpoint>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.recentTaskRuns(maxItems: 50);
  }

  void _reload() {
    setState(() {
      _future = widget.controller.recentTaskRuns(maxItems: 50);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final dialogWidth = (screen.width - 48).clamp(320.0, 780.0).toDouble();
    final dialogHeight = (screen.height - 180).clamp(320.0, 620.0).toDouble();
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('История запусков агента')),
          IconButton(
            tooltip: 'Очистить историю',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Очистить историю запусков?'),
                      content: const Text(
                        'Завершённые, отменённые и ошибочные записи этого '
                        'проекта будут удалены. Активная задача не затрагивается.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Отмена'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Очистить'),
                        ),
                      ],
                    ),
                  ) ??
                  false;
              if (!confirmed || !mounted) return;
              await widget.controller.clearTaskRunHistory();
              if (mounted) _reload();
            },
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          IconButton(
            tooltip: 'Обновить',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: FutureBuilder<List<AgentRunCheckpoint>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return SelectableText('Ошибка чтения истории: ${snapshot.error}');
            }
            final runs = snapshot.data ?? const <AgentRunCheckpoint>[];
            if (runs.isEmpty) {
              return const Center(
                child: Text('История запусков пока пуста.'),
              );
            }
            return ListView.separated(
              itemCount: runs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final run = runs[index];
                return ExpansionTile(
                  leading: Icon(_iconFor(run.status)),
                  title: Text(
                    run.prompt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${run.status.label} · ${_formatTime(run.updatedAt)} · '
                    'итерация ${run.iteration}/${run.maxIterations}',
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        'Run ID: ${run.runId}\n'
                        'Действий: ${run.toolActions}\n'
                        'Изменений файлов: ${run.fileMutations}\n'
                        'Команд: ${run.commandRuns}\n'
                        'Ошибок команд: ${run.failedCommands}\n'
                        'Сетевых действий: ${run.internetActions}\n'
                        'Последний exit code: ${run.lastCommandExitCode ?? '—'}\n'
                        'Последний инструмент: '
                        '${run.lastTool.isEmpty ? '—' : run.lastTool}',
                      ),
                    ),
                    if (run.lastCommand.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Последняя команда',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(run.lastCommand),
                      ),
                    ],
                    if (run.plan.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'План',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(run.plan),
                      ),
                    ],
                    if (run.evidenceSummary.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Доказательства выполнения',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(run.evidenceSummary),
                      ),
                    ],
                    if (run.lastError.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText('Ошибка: ${run.lastError}'),
                      ),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }

  IconData _iconFor(AgentRunStatus status) => switch (status) {
        AgentRunStatus.completed => Icons.check_circle_outline,
        AgentRunStatus.cancelled => Icons.stop_circle_outlined,
        AgentRunStatus.stalled => Icons.repeat_on_outlined,
        AgentRunStatus.failed => Icons.error_outline,
        AgentRunStatus.interrupted => Icons.restore,
        _ => Icons.pending_outlined,
      };

  String _formatTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.day)}.${two(value.month)}.${value.year} '
        '${two(value.hour)}:${two(value.minute)}';
  }
}
