import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_agent/agent_core/planning/project_task_mode.dart';
import 'package:ii_agent/agent_core/planning/task_execution_state.dart';
import 'package:ii_agent/agent_core/planning/task_intent_analyzer.dart';

void main() {
  test('canonical recursive task state is persisted and restored verbatim',
      () async {
    final root = await Directory.systemTemp.createTemp('aia_task_state_');
    addTearDown(() => root.delete(recursive: true));
    const analyzer = TaskIntentAnalyzer();
    const planner = TaskGoalPlanner();
    final intent = analyzer.analyze(
      'Создай приложение, проверь его и собери релиз',
      projectMode: ProjectTaskMode.software,
    );
    var state = planner.create(
      taskId: 'run_42',
      projectPath: root.path,
      projectMode: ProjectTaskMode.software,
      intent: intent,
      prompt: 'Создай приложение, проверь его и собери релиз',
    );
    final now = DateTime.now();
    state = state.defineGoal(
      expectedResult: 'Рабочее приложение и проверенный release/app_1.0.0',
      subtasks: [
        TaskNode(
          id: 'implementation',
          title: 'Реализовать приложение',
          expectedResult: 'Исходники созданы',
          kind: TaskNodeKind.execution,
          status: TaskNodeStatus.pending,
          result: '',
          evidence: const [],
          artifacts: const [],
          attempts: 0,
          nextAction: '',
          children: const [],
          updatedAt: now,
        ),
      ],
    );
    state = state.addSubtask(
      parentId: 'implementation',
      node: TaskNode(
        id: 'compile',
        title: 'Собрать приложение',
        expectedResult: 'Компилятор вернул exit code 0',
        kind: TaskNodeKind.verification,
        status: TaskNodeStatus.pending,
        result: '',
        evidence: const [],
        artifacts: const [],
        attempts: 0,
        nextAction: '',
        children: const [],
        updatedAt: now,
      ),
    );
    state = state.rememberFact(TaskContextFact(
      kind: 'compiler',
      key: 'flutter',
      value: r'N:\Compilers\flutter\bin\flutter.bat',
      source: 'list_local_tools',
      verified: true,
      updatedAt: now,
    ));
    final store = TaskExecutionStateStore(projectRoot: root);
    await store.begin(state);
    final handoffBefore = await store.readInvariant(state);

    final restored = await store.load('run_42');
    expect(restored, isNotNull);
    expect(
        restored!.findNode('compile')?.expectedResult, contains('exit code 0'));
    expect(restored.contextFacts.single.key, 'flutter');
    expect(await store.readInvariant(restored), handoffBefore);
    expect(handoffBefore, contains('[CANONICAL_TASK_STATE]'));
    expect(handoffBefore, contains('ORIGINAL_USER_TASK'));
    expect(handoffBefore, contains('N:\\Compilers'));
  });
}
