import 'package:flutter_test/flutter_test.dart';
import 'package:ii_agent/agent_core/planning/project_task_mode.dart';
import 'package:ii_agent/agent_core/prompts/agent_prompt_templates.dart';

void main() {
  test('editable prompt override is serialized and rendered for a task mode',
      () {
    final library = AgentPromptLibrary()
      ..update('mode.documents', 'Проверь документ: {{expected_result}}');
    final restored = AgentPromptLibrary.fromJson(library.toJson());
    final rendered = restored.render(
      mode: ProjectTaskMode.documents,
      taskType: 'documents',
      expectedResult: 'таблица присутствует',
    );

    expect(rendered, contains('Проверь документ: таблица присутствует'));
    expect(rendered, contains('[stage.verify]'));
    expect(rendered, isNot(contains('[stage.release]')));
  });
}
