import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_agent/agent_core/memory/context_archive_service.dart';

void main() {
  test('searches current, other project, and literature corpora separately',
      () async {
    final root = await Directory.systemTemp.createTemp('aia_context_archive_');
    addTearDown(() => root.delete(recursive: true));
    final config = Directory('${root.path}${Platform.pathSeparator}config');
    final projects = Directory('${root.path}${Platform.pathSeparator}Projects');
    final documents =
        Directory('${root.path}${Platform.pathSeparator}documents');
    final projectA =
        Directory('${projects.path}${Platform.pathSeparator}Alpha');
    final projectB = Directory('${projects.path}${Platform.pathSeparator}Beta');
    final sessionA = File(
        '${projectA.path}${Platform.pathSeparator}.cppagent${Platform.pathSeparator}sessions${Platform.pathSeparator}session.jsonl');
    final sessionB = File(
        '${projectB.path}${Platform.pathSeparator}.cppagent${Platform.pathSeparator}runs${Platform.pathSeparator}run.json');
    await sessionA.parent.create(recursive: true);
    await sessionB.parent.create(recursive: true);
    await documents.create(recursive: true);
    await sessionA.writeAsString(
        '{"content":"ALPHA_ONLY verified flutter build windows"}\n');
    await sessionB.writeAsString(
        '{"result":"BETA_ONLY fixed linker with target_link_libraries"}');
    await File('${documents.path}${Platform.pathSeparator}compiler_notes.md')
        .writeAsString('LITERATURE_ONLY use incremental compilation cache');

    final service = ContextArchiveService(
      configRoot: config,
      projectsRoot: projects,
      documentsRoot: documents,
      textExtractor: (path, maxChars) async => File(path).readAsString(),
      projectPathsProvider: () => [projectA.path, projectB.path],
    );
    await service.initialize();
    final first = await service.rebuild(currentProjectPath: projectA.path);

    expect(first.updatedSources, greaterThanOrEqualTo(3));
    final current = await service.search(
      'ALPHA_ONLY',
      scope: ContextArchiveScope.currentProject,
      currentProjectPath: projectA.path,
      refresh: false,
    );
    final other = await service.search(
      'BETA_ONLY',
      scope: ContextArchiveScope.otherProjects,
      currentProjectPath: projectA.path,
      refresh: false,
    );
    final literature = await service.search(
      'LITERATURE_ONLY',
      scope: ContextArchiveScope.literature,
      currentProjectPath: projectA.path,
      refresh: false,
    );

    expect(current.single.chunk.projectName, 'Alpha');
    expect(other.single.chunk.projectName, 'Beta');
    final literatureHit = literature.firstWhere(
      (hit) => hit.chunk.sourcePath.endsWith('compiler_notes.md'),
    );
    expect(
      literature.where((hit) => hit.chunk.sourcePath.endsWith('README_RU.txt')),
      isEmpty,
    );
    expect(literatureHit.chunk.corpus, ContextArchiveCorpus.literature);
    final full = await service.readSource(literatureHit.chunk.sourceId);
    expect(full, contains('LITERATURE_ONLY'));

    final second = await service.rebuild(currentProjectPath: projectA.path);
    expect(second.reusedSources, greaterThanOrEqualTo(3));
  });
}
