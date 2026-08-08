enum ProjectTaskMode {
  automatic,
  software,
  documents,
  fileSystem,
  remoteSystems,
  pentesting,
}

extension ProjectTaskModeX on ProjectTaskMode {
  String get label => switch (this) {
        ProjectTaskMode.automatic => 'Автоматически',
        ProjectTaskMode.software =>
          'Программирование, кодинг, скрипты (сценарии)',
        ProjectTaskMode.documents => 'Работа с документами',
        ProjectTaskMode.fileSystem => 'Работа с файловой системой',
        ProjectTaskMode.remoteSystems =>
          'Работа с удаленными компьютерами, серверами и сетью',
        ProjectTaskMode.pentesting => 'Пентестинг',
      };

  String get promptKey => switch (this) {
        ProjectTaskMode.automatic => 'mode.automatic',
        ProjectTaskMode.software => 'mode.software',
        ProjectTaskMode.documents => 'mode.documents',
        ProjectTaskMode.fileSystem => 'mode.filesystem',
        ProjectTaskMode.remoteSystems => 'mode.remote',
        ProjectTaskMode.pentesting => 'mode.pentesting',
      };

  bool get isExplicit => this != ProjectTaskMode.automatic;

  static ProjectTaskMode parse(Object? value) {
    final name = value?.toString() ?? '';
    return ProjectTaskMode.values.firstWhere(
      (item) => item.name == name,
      orElse: () => ProjectTaskMode.automatic,
    );
  }
}
