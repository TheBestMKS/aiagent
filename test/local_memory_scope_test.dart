import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_agent/agent_core/memory/local_memory_service.dart';

void main() {
  test('typed memory can search current and other projects independently',
      () async {
    final root = await Directory.systemTemp.createTemp('aia_memory_scope_');
    addTearDown(() => root.delete(recursive: true));
    final service = LocalMemoryService(configRoot: root);
    await service.initialize();
    await service.remember(
      type: AgentMemoryType.procedure,
      title: 'Global compiler cache',
      content: 'compiler cache shared procedure',
    );
    await service.remember(
      type: AgentMemoryType.learning,
      title: 'Alpha compiler cache',
      content: 'compiler cache alpha procedure',
      scope: 'project',
      projectPath: 'N:/Projects/Alpha',
    );
    await service.remember(
      type: AgentMemoryType.learning,
      title: 'Beta compiler cache',
      content: 'compiler cache beta procedure',
      scope: 'project',
      projectPath: 'N:/Projects/Beta',
    );

    final current = await service.search(
      'compiler cache',
      projectPath: 'N:/Projects/Alpha',
      scope: AgentMemorySearchScope.currentProject,
    );
    final other = await service.search(
      'compiler cache',
      projectPath: 'N:/Projects/Alpha',
      scope: AgentMemorySearchScope.otherProjects,
    );
    final currentAndGlobal = await service.search(
      'compiler cache',
      projectPath: 'N:/Projects/Alpha',
    );

    expect(current.map((item) => item.title), ['Alpha compiler cache']);
    expect(other.map((item) => item.title), ['Beta compiler cache']);
    expect(currentAndGlobal.map((item) => item.title),
        containsAll(['Alpha compiler cache', 'Global compiler cache']));
    expect(currentAndGlobal.map((item) => item.title),
        isNot(contains('Beta compiler cache')));
  });
}
