import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_agent/agent_core/planning/project_agent_configuration.dart';
import 'package:ii_agent/agent_core/planning/project_task_mode.dart';

void main() {
  test('project task mode and indexing survive reload', () async {
    final root = await Directory.systemTemp.createTemp('aia_project_config_');
    addTearDown(() => root.delete(recursive: true));
    const store = ProjectAgentConfigurationStore();
    const expected = ProjectAgentConfiguration(
      taskMode: ProjectTaskMode.remoteSystems,
      indexContents: true,
    );

    await store.save(root, expected);
    final restored = await store.load(root);

    expect(restored.taskMode, ProjectTaskMode.remoteSystems);
    expect(restored.indexContents, isTrue);
    expect(store.fileFor(root).path, contains('.cppagent'));
  });
}
