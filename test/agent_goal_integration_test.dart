import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_agent/agent_core/planning/project_agent_configuration.dart';
import 'package:ii_agent/agent_core/planning/project_task_mode.dart';
import 'package:ii_agent/agent_core/planning/task_execution_state.dart';
import 'package:ii_agent/controllers/agent_controller.dart';
import 'package:ii_agent/core/models.dart';

void main() {
  test(
      'model context contains project mode and canonical goal after compaction',
      () async {
    final root = await Directory.systemTemp.createTemp('aia_goal_context_');
    addTearDown(() => root.delete(recursive: true));
    final controller = AgentController()
      ..currentProject = ProjectInfo(name: 'Demo', path: root.path)
      ..currentProjectConfiguration = const ProjectAgentConfiguration(
        taskMode: ProjectTaskMode.software,
      )
      ..activeTaskText = 'Создай и проверь Demo';
    controller.activeTaskIntent =
        controller.analyzeTaskIntent(controller.activeTaskText);
    controller.activeTaskGoal = const TaskGoalPlanner().create(
      taskId: 'run_context',
      projectPath: root.path,
      projectMode: ProjectTaskMode.software,
      intent: controller.activeTaskIntent!,
      prompt: controller.activeTaskText,
    );
    controller.activeTaskInvariant =
        controller.activeTaskGoal!.toInvariantMarkdown();

    final messages = controller.buildMessagesForModel();
    final system = messages.first['content']!;

    expect(system, contains('"primary_domain": "software"'));
    expect(system, contains('[CANONICAL_TASK_STATE]'));
    expect(system, contains('task_id=run_context'));
    expect(system, contains('record_task_context'));
    expect(system, contains('inspect_project_build'));
    expect(system, contains('context_search'));
    expect(system, contains('[GUIDED_EXECUTION_STEP]'));
    expect(system.length, lessThan(18000),
        reason: 'strict guidance must leave context room for tool results');
  });

  test('goal release and WSL tools have unique OpenAI definitions', () {
    final controller = AgentController();
    final definitions = controller.buildOpenAiToolDefinitions();
    final names = definitions
        .map((item) => item['function'])
        .whereType<Map>()
        .map((item) => item['name']?.toString() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);

    expect(names.toSet().length, names.length);
    expect(
        names,
        containsAll(<String>[
          'define_task_goal',
          'add_task_subtask',
          'update_task_subtask',
          'record_task_context',
          'get_task_goal',
          'package_project_release',
          'wsl_list',
          'inspect_project_build',
          'context_search',
          'context_read',
          'context_reindex',
          'literature_list',
          'literature_search',
        ]));
  });

  test('strict software routing starts with inspection tools', () async {
    final root = await Directory.systemTemp.createTemp('aia_routed_tools_');
    addTearDown(() => root.delete(recursive: true));
    final controller = AgentController()
      ..currentProject = ProjectInfo(name: 'Demo', path: root.path)
      ..activeTaskText = 'Создай и собери программу';
    controller.activeTaskIntent =
        controller.analyzeTaskIntent(controller.activeTaskText);

    final names = controller
        .buildRoutedOpenAiToolDefinitions()
        .map((item) => item['function'])
        .whereType<Map>()
        .map((item) => item['name']?.toString() ?? '')
        .toSet();

    expect(names, contains('inspect_project_build'));
    expect(names, contains('project_map'));
    expect(names, isNot(contains('write_file')));
    expect(names.length, lessThanOrEqualTo(10));
  });

  test('output budget reserves context for native tool schemas', () {
    final controller = AgentController()
      ..maxContextTokens = 8192
      ..maxOutputTokens = 4096;
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': List.filled(8000, 'x').join()},
    ];

    final withoutSchemas = controller.calculateMaxOutputTokens(messages);
    final withSchemas = controller.calculateMaxOutputTokens(
      messages,
      extraPromptTokens: 1800,
    );

    expect(withSchemas, lessThan(withoutSchemas));
    expect(withSchemas, greaterThanOrEqualTo(512));
  });
}
