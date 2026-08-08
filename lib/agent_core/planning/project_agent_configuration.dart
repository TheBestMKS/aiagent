import 'dart:convert';
import 'dart:io';

import '../../utils/path_utils.dart';
import 'project_task_mode.dart';

class ProjectAgentConfiguration {
  const ProjectAgentConfiguration({
    this.taskMode = ProjectTaskMode.automatic,
    this.indexContents = false,
  });

  final ProjectTaskMode taskMode;
  final bool indexContents;

  ProjectAgentConfiguration copyWith({
    ProjectTaskMode? taskMode,
    bool? indexContents,
  }) =>
      ProjectAgentConfiguration(
        taskMode: taskMode ?? this.taskMode,
        indexContents: indexContents ?? this.indexContents,
      );

  Map<String, Object?> toJson() => {
        'schemaVersion': 1,
        'taskMode': taskMode.name,
        'indexContents': indexContents,
      };

  factory ProjectAgentConfiguration.fromJson(Object? value) {
    if (value is! Map) return const ProjectAgentConfiguration();
    return ProjectAgentConfiguration(
      taskMode: ProjectTaskModeX.parse(value['taskMode']),
      indexContents: value['indexContents'] == true,
    );
  }
}

class ProjectAgentConfigurationStore {
  const ProjectAgentConfigurationStore();

  File fileFor(Directory projectRoot) => File(
        pathJoin(projectRoot.path, '.cppagent', 'project_settings.json'),
      );

  Future<ProjectAgentConfiguration> load(Directory projectRoot) async {
    final file = fileFor(projectRoot);
    if (!await file.exists()) return const ProjectAgentConfiguration();
    try {
      final decoded = jsonDecode(await file.readAsString(encoding: utf8));
      return ProjectAgentConfiguration.fromJson(decoded);
    } catch (_) {
      return const ProjectAgentConfiguration();
    }
  }

  Future<void> save(
    Directory projectRoot,
    ProjectAgentConfiguration configuration,
  ) async {
    final file = fileFor(projectRoot);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(configuration.toJson()),
      encoding: utf8,
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}
