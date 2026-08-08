import 'dart:io';

class CMakeCommandResolution {
  const CMakeCommandResolution({
    required this.originalCommand,
    required this.effectiveCommand,
    this.reason = '',
  });

  final String originalCommand;
  final String effectiveCommand;
  final String reason;

  bool get changed => originalCommand.trim() != effectiveCommand.trim();
}

class CMakeCommandResolver {
  const CMakeCommandResolver._();

  static final RegExp _buildPattern = RegExp(
    r'''((?:^|[&|;]\s*)(?:"[^"]*cmake(?:\.exe)?"|[^\s&|;]*cmake(?:\.exe)?))\s+--build\s+("[^"]+"|[^\s&|;]+)''',
    caseSensitive: false,
  );

  static bool isCMakeBuildCommand(String command) =>
      _buildPattern.hasMatch(command.trim());

  static bool isCMakeConfigureOnlyCommand(String command) {
    final normalized = command.toLowerCase();
    if (!RegExp(r'(^|[\s"/\\])cmake(?:\.exe)?\b').hasMatch(normalized)) {
      return false;
    }
    if (normalized.contains('--build')) return false;
    return RegExp(r'(^|\s)-(?:s|b)(?:\s|$)', caseSensitive: false)
            .hasMatch(normalized) ||
        normalized.contains('cmakelists.txt');
  }

  static String deriveBuildCommandFromConfigure(String command) {
    final executable = _cmakeExecutable(command) ?? 'cmake';
    final buildDir = _optionValue(command, '-B') ?? 'build';
    return '$executable --build ${_quoteIfNeeded(buildDir)} --config Release';
  }

  static CMakeCommandResolution resolve({
    required String command,
    required String workingDirectory,
  }) {
    final original = command.trim();
    if (original.isEmpty || !isCMakeBuildCommand(original)) {
      return CMakeCommandResolution(
        originalCommand: command,
        effectiveCommand: command,
      );
    }

    final match = _buildPattern.firstMatch(original);
    if (match == null) {
      return CMakeCommandResolution(
        originalCommand: command,
        effectiveCommand: command,
      );
    }

    final rawBuildDir = _unquote(match.group(2) ?? '.');
    final requestedDir = rawBuildDir.isEmpty ? '.' : rawBuildDir;
    final requestedCache = File(
      _join(workingDirectory, requestedDir, 'CMakeCache.txt'),
    );
    if (requestedCache.existsSync()) {
      return CMakeCommandResolution(
        originalCommand: command,
        effectiveCommand: command,
      );
    }

    final candidate = _findExistingBuildDirectory(workingDirectory);
    if (candidate != null) {
      final effective = _replaceBuildDirectory(
        original,
        match,
        _quoteIfNeeded(candidate),
      );
      return CMakeCommandResolution(
        originalCommand: command,
        effectiveCommand: effective,
        reason:
            'В указанной папке `$requestedDir` нет CMakeCache.txt; найден существующий каталог сборки `$candidate`.',
      );
    }

    final cmakeLists = File(_join(workingDirectory, 'CMakeLists.txt'));
    if (cmakeLists.existsSync()) {
      final executable = _cmakeExecutable(original) ?? 'cmake';
      const generatedDir = 'build';
      final normalizedBuild = _replaceBuildDirectory(
        original,
        match,
        generatedDir,
      );
      final effective = '$executable -S . -B $generatedDir && $normalizedBuild';
      return CMakeCommandResolution(
        originalCommand: command,
        effectiveCommand: effective,
        reason:
            'Каталог сборки ещё не сконфигурирован; перед сборкой автоматически добавлена генерация `cmake -S . -B build`.',
      );
    }

    return CMakeCommandResolution(
      originalCommand: command,
      effectiveCommand: command,
    );
  }

  static String _replaceBuildDirectory(
    String command,
    RegExpMatch match,
    String replacement,
  ) {
    final matchedText = match.group(0) ?? '';
    final capturedDirectory = match.group(2) ?? '';
    if (matchedText.isEmpty || capturedDirectory.isEmpty) return command;

    final relativeStart = matchedText.lastIndexOf(capturedDirectory);
    if (relativeStart < 0) return command;

    final absoluteStart = match.start + relativeStart;
    final absoluteEnd = absoluteStart + capturedDirectory.length;
    return command.replaceRange(absoluteStart, absoluteEnd, replacement);
  }

  static String? _findExistingBuildDirectory(String workingDirectory) {
    const preferred = <String>[
      'build',
      'build-release',
      'cmake-build-release',
      'out/build',
    ];
    for (final relative in preferred) {
      if (File(_join(workingDirectory, relative, 'CMakeCache.txt'))
          .existsSync()) {
        return relative;
      }
    }
    try {
      for (final entity in Directory(workingDirectory)
          .listSync(recursive: false, followLinks: false)) {
        if (entity is! Directory) continue;
        final cache = File(_join(entity.path, 'CMakeCache.txt'));
        if (cache.existsSync()) {
          return entity.path
              .substring(workingDirectory.length)
              .replaceAll('\\', '/')
              .replaceFirst(RegExp(r'^/+'), '');
        }
      }
    } catch (_) {
      // Best effort only.
    }
    return null;
  }

  static String? _cmakeExecutable(String command) {
    final quoted = RegExp(r'''"([^"]*cmake(?:\.exe)?)"''', caseSensitive: false)
        .firstMatch(command)
        ?.group(1);
    if (quoted != null) return '"$quoted"';
    return RegExp(r'''(?:^|[&|;]\s*)([^\s&|;]*cmake(?:\.exe)?)\b''',
            caseSensitive: false)
        .firstMatch(command)
        ?.group(1);
  }

  static String? _optionValue(String command, String option) {
    final escaped = RegExp.escape(option);
    final match = RegExp(
      '$escaped\\s+("[^"]+"|[^\\s&|;]+)',
      caseSensitive: false,
    ).firstMatch(command);
    return match == null ? null : _unquote(match.group(1) ?? '');
  }

  static String _unquote(String value) {
    final trimmed = value.trim();
    if (trimmed.length >= 2 &&
        trimmed.startsWith('"') &&
        trimmed.endsWith('"')) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return trimmed;
  }

  static String _quoteIfNeeded(String value) =>
      RegExp(r'\s').hasMatch(value) ? '"$value"' : value;

  static String _join(String first, [String second = '', String third = '']) {
    final separator = Platform.pathSeparator;
    final parts = <String>[first, second, third]
        .where((part) => part.trim().isNotEmpty)
        .map((part) =>
            part.replaceAll('/', separator).replaceAll('\\', separator))
        .toList(growable: false);
    return parts.join(separator);
  }
}
