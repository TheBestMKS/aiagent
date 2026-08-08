import 'dart:io';

import '../../utils/path_utils.dart';

class BuildWorkingDirectoryResolution {
  const BuildWorkingDirectoryResolution({
    required this.requestedRelativeDirectory,
    required this.effectiveRelativeDirectory,
    this.reason = '',
  });

  final String requestedRelativeDirectory;
  final String effectiveRelativeDirectory;
  final String reason;

  bool get changed => requestedRelativeDirectory != effectiveRelativeDirectory;
}

class BuildWorkingDirectoryResolver {
  const BuildWorkingDirectoryResolver._();

  static BuildWorkingDirectoryResolution resolve({
    required String command,
    required String projectRoot,
    required String requestedRelativeDirectory,
  }) {
    final requested = requestedRelativeDirectory.trim();
    if (requested.isEmpty || projectRoot.trim().isEmpty) {
      return BuildWorkingDirectoryResolution(
        requestedRelativeDirectory: requested,
        effectiveRelativeDirectory: requested,
      );
    }
    final isCMake = RegExp(
      r'(^|[\s"/\\])cmake(?:\.exe)?\b',
      caseSensitive: false,
    ).hasMatch(command.trim());
    if (!isCMake) {
      return BuildWorkingDirectoryResolution(
        requestedRelativeDirectory: requested,
        effectiveRelativeDirectory: requested,
      );
    }
    final requestedDirectory = Directory(pathJoin(projectRoot, requested));
    if (requestedDirectory.existsSync()) {
      return BuildWorkingDirectoryResolution(
        requestedRelativeDirectory: requested,
        effectiveRelativeDirectory: requested,
      );
    }
    return BuildWorkingDirectoryResolution(
      requestedRelativeDirectory: requested,
      effectiveRelativeDirectory: '',
      reason: 'Запрошенная рабочая папка `$requested` ещё не существует. '
          'CMake должен сначала сконфигурировать проект из корня.',
    );
  }
}
