import 'dart:io';

enum BuildFailureKind {
  none,
  sourceCompile,
  linker,
  buildConfiguration,
  toolUsage,
  dependency,
  environment,
  artifact,
  unknown,
}

class BuildFailureAnalysis {
  const BuildFailureAnalysis({
    required this.kind,
    required this.summary,
    this.implicatedFiles = const <String>[],
    this.implicatedLines = const <String, int>{},
    this.suggestedDiagnosticCommand,
    this.suggestedRecoveryCommand,
    this.missingDependency = '',
    this.locatedDependencyPath = '',
    this.recommendedAction = '',
  });

  final BuildFailureKind kind;
  final String summary;
  final List<String> implicatedFiles;
  final Map<String, int> implicatedLines;
  final String? suggestedDiagnosticCommand;
  final String? suggestedRecoveryCommand;
  final String missingDependency;
  final String locatedDependencyPath;
  final String recommendedAction;

  bool get isFailure => kind != BuildFailureKind.none;

  bool get sourceMutationAllowed =>
      kind == BuildFailureKind.sourceCompile && implicatedFiles.isNotEmpty;

  bool get configurationMutationAllowed => const {
        BuildFailureKind.buildConfiguration,
        BuildFailureKind.linker,
        BuildFailureKind.dependency,
      }.contains(kind);

  bool get diagnosticRequiredBeforeMutation => const {
        BuildFailureKind.toolUsage,
        BuildFailureKind.environment,
        BuildFailureKind.unknown,
      }.contains(kind);

  String toPromptBlock() {
    final buffer = StringBuffer()
      ..writeln('[BUILD_FAILURE_ANALYSIS]')
      ..writeln('kind=${kind.name}')
      ..writeln('summary=$summary');
    if (missingDependency.isNotEmpty) {
      buffer.writeln('missing_dependency=$missingDependency');
    }
    if (locatedDependencyPath.isNotEmpty) {
      buffer.writeln('located_dependency=$locatedDependencyPath');
    }
    if (implicatedFiles.isNotEmpty) {
      buffer.writeln('implicated_files=${implicatedFiles.join(', ')}');
    }
    if (implicatedLines.isNotEmpty) {
      buffer.writeln(
        'implicated_locations=${implicatedLines.entries.map((entry) => '${entry.key}:${entry.value}').join(', ')}',
      );
      final first = implicatedLines.entries.first;
      final start = first.value > 20 ? first.value - 20 : 1;
      final end = first.value + 20;
      buffer.writeln(
        'suggested_read=read_file path=${first.key} line_start=$start line_end=$end',
      );
    }
    if (suggestedDiagnosticCommand != null) {
      buffer.writeln('suggested_diagnostic=$suggestedDiagnosticCommand');
    }
    if (suggestedRecoveryCommand != null) {
      buffer.writeln('suggested_recovery=$suggestedRecoveryCommand');
    }
    if (recommendedAction.trim().isNotEmpty) {
      buffer.writeln('next_action=$recommendedAction');
    }
    buffer.writeln('[/BUILD_FAILURE_ANALYSIS]');
    return buffer.toString().trimRight();
  }
}

class BuildFailureAnalyzer {
  const BuildFailureAnalyzer();

  static final RegExp _gccSourceError = RegExp(
    r'''(?:^|\n)((?:[A-Za-z]:[\\/])?[^\r\n:]+\.(?:c|cc|cpp|cxx|h|hh|hpp|hxx)):(\d+)(?::\d+)?:\s*(?:fatal\s+)?error:''',
    caseSensitive: false,
  );

  static final RegExp _msvcSourceError = RegExp(
    r'''(?:^|\n)((?:[A-Za-z]:[\\/])?[^\r\n()]+\.(?:c|cc|cpp|cxx|h|hh|hpp|hxx))\((\d+)(?:,\d+)?\)\s*:\s*(?:fatal\s+)?error\s+[A-Z]+\d+:''',
    caseSensitive: false,
  );

  static final RegExp _gccMissingHeader = RegExp(
    r'''fatal\s+error:\s*([^\r\n:]+):\s*no such file or directory''',
    caseSensitive: false,
  );

  static final RegExp _msvcMissingHeader = RegExp(
    r'''fatal\s+error\s+C1083:\s*Cannot open include file:\s*['"]([^'"]+)['"]''',
    caseSensitive: false,
  );

  BuildFailureAnalysis analyze({
    required String command,
    required String output,
    String projectRoot = '',
  }) {
    final lower = output.toLowerCase();
    if (_looksSuccessful(lower)) {
      return const BuildFailureAnalysis(
        kind: BuildFailureKind.none,
        summary: 'Команда сборки завершилась успешно.',
      );
    }

    final diagnostic = _suggestedDiagnostic(command, lower);
    final sourceLocations = _sourceLocations(output, projectRoot);
    final sourceFiles = sourceLocations.keys.toList(growable: false);

    if (_containsAny(lower, const <String>[
      'not a cmake build directory',
      'missing cmakecache.txt',
      'could not load cache',
      'cmakecache.txt was not found',
    ])) {
      return BuildFailureAnalysis(
        kind: BuildFailureKind.buildConfiguration,
        summary:
            'Команда `cmake --build` запущена не в каталоге, который был сконфигурирован CMake.',
        suggestedDiagnosticCommand: diagnostic,
        suggestedRecoveryCommand:
            'cmake -S . -B build && cmake --build build --config Release',
        recommendedAction:
            'Не меняй исходники. Сначала создай или найди каталог с CMakeCache.txt командой `cmake -S . -B build`, затем собирай именно `cmake --build build --config Release`.',
      );
    }

    final missingHeader = _missingHeader(output);
    if (missingHeader != null) {
      final located = _findProjectDependency(projectRoot, missingHeader);
      if (located != null) {
        return BuildFailureAnalysis(
          kind: BuildFailureKind.buildConfiguration,
          summary:
              'Заголовок `$missingHeader` существует в проекте (`$located`), но каталог с ним не передан компилятору.',
          implicatedFiles: const <String>['CMakeLists.txt'],
          missingDependency: missingHeader,
          locatedDependencyPath: located,
          suggestedDiagnosticCommand: diagnostic,
          suggestedRecoveryCommand:
              'cmake -S . -B build && cmake --build build --config Release',
          recommendedAction:
              'Прочитай CMakeLists.txt и добавь каталог `${_parentPath(located)}` через target_include_directories для реальной цели. Не меняй строку #include в .cpp, потому что заголовок уже найден в проекте. После правки заново выполни конфигурацию и сборку.',
        );
      }
      return BuildFailureAnalysis(
        kind: BuildFailureKind.dependency,
        summary:
            'Компилятор не нашёл заголовок `$missingHeader`, и такого файла нет внутри текущего проекта.',
        implicatedFiles: sourceFiles,
        implicatedLines: sourceLocations,
        missingDependency: missingHeader,
        suggestedDiagnosticCommand: diagnostic,
        recommendedAction:
            'Проверь наличие зависимости или SDK, затем include paths. Не переписывай прикладной исходник, пока отсутствующий заголовок не найден или не установлен.',
      );
    }

    if (_containsAny(lower, const <String>[
      'could not find a package configuration file',
      'could not find package',
      'could not find opencv',
      'package configuration file provided by',
      'cannot find -l',
      'library not found for',
      'module not found',
      'dependency not found',
    ])) {
      return BuildFailureAnalysis(
        kind: BuildFailureKind.dependency,
        summary:
            'Сборка остановилась из-за отсутствующей зависимости или библиотеки.',
        implicatedFiles: sourceFiles,
        implicatedLines: sourceLocations,
        suggestedDiagnosticCommand: diagnostic,
        recommendedAction:
            'Проверь зависимости, include/library paths и доступные инструменты. Не переписывай прикладной исходный код, пока не подтверждено, что ошибка находится в нём.',
      );
    }

    if (_containsAny(lower, const <String>[
          'does not appear to contain cmakelists.txt',
          'could not find cmakelists.txt',
          'cannot find source file',
          'no sources given to target',
          'source directory does not exist',
          'the source directory',
          'cmake_minimum_required command is not present',
          'build directory not found',
          'is not a directory',
        ]) &&
        (lower.contains('cmake') || lower.contains('cmakelists'))) {
      return BuildFailureAnalysis(
        kind: BuildFailureKind.buildConfiguration,
        summary:
            'Ошибка относится к структуре или конфигурации сборки CMake, а не к телу исходного файла.',
        suggestedDiagnosticCommand: diagnostic,
        suggestedRecoveryCommand:
            'cmake -S . -B build && cmake --build build --config Release',
        recommendedAction:
            'Проверь рабочую папку, наличие и содержимое CMakeLists.txt, пути -S/-B и реальные исходники. Разрешено исправлять конфигурацию сборки, но не main.cpp без сообщения компилятора с файлом и строкой.',
      );
    }

    if (_containsAny(lower, const <String>[
      'unknown argument',
      'unknown option',
      'unrecognized option',
      'unrecognised option',
      'invalid option',
      'invalid value for',
      'usage:',
      'specify --help for usage',
      'try --help',
      'use --help',
    ])) {
      return BuildFailureAnalysis(
        kind: BuildFailureKind.toolUsage,
        summary: 'Команда или параметры инструмента заданы неверно.',
        suggestedDiagnosticCommand: diagnostic,
        recommendedAction:
            'Сначала выполни безопасную справочную команду --help/--version, исправь параметры и повтори ту же сборку. Исходники менять нельзя.',
      );
    }

    if (_containsAny(lower, const <String>[
      'undefined reference to',
      'unresolved external symbol',
      'multiple definition of',
      'ld returned 1 exit status',
      'linker command failed',
      'lnk2001',
      'lnk2019',
      'lnk1120',
    ])) {
      return BuildFailureAnalysis(
        kind: BuildFailureKind.linker,
        summary:
            'Компиляция дошла до этапа линковки, но символы или библиотеки не были разрешены.',
        implicatedFiles: sourceFiles,
        implicatedLines: sourceLocations,
        suggestedDiagnosticCommand: diagnostic,
        recommendedAction:
            'Сначала проверь список объектных файлов, target_link_libraries и сигнатуры символов. Не переписывай main.cpp без доказательства, что объявление или определение находится именно там.',
      );
    }

    if (sourceFiles.isNotEmpty) {
      return BuildFailureAnalysis(
        kind: BuildFailureKind.sourceCompile,
        summary: 'Компилятор указал конкретный исходный файл и строку.',
        implicatedFiles: sourceFiles,
        implicatedLines: sourceLocations,
        suggestedDiagnosticCommand: diagnostic,
        recommendedAction:
            'Прочитай только указанный участок файла, внеси минимальную правку и обязательно повтори ту же команду сборки.',
      );
    }

    if (_containsAny(lower, const <String>[
      'no space left on device',
      'not enough space on the disk',
      'insufficient disk space',
      'disk full',
      'errno = 112',
      'недостаточно места на диске',
      'there is not enough space on the disk',
    ])) {
      return const BuildFailureAnalysis(
        kind: BuildFailureKind.environment,
        summary:
            'Сборка остановилась из-за нехватки свободного места на диске, а не из-за ошибки исходного кода.',
        recommendedAction:
            'Не изменяй исходники. Проверь свободное место на диске проекта, сохрани уже созданные артефакты, удали только генерируемые build/.dart_tool/flutter_build/Gradle-кеши и повтори ту же команду сборки. Пользовательские файлы и dist автоматически не удаляй.',
      );
    }

    if (_containsAny(lower, const <String>[
      'is not recognized as an internal or external command',
      'command not found',
      'compiler not found',
      'no c++ compiler could be found',
      'could not create named generator',
      'ninja was not found',
      'permission denied',
      'access is denied',
      'failed to start process',
      'the system cannot find the file specified',
    ])) {
      return BuildFailureAnalysis(
        kind: BuildFailureKind.environment,
        summary:
            'Ошибка вызвана окружением, отсутствующим инструментом, генератором или правами доступа.',
        suggestedDiagnosticCommand: diagnostic,
        recommendedAction:
            'Проверь list_local_tools, PATH, генератор и права. Попробуй альтернативный локальный инструмент или корректную команду. Исходники не менять.',
      );
    }

    if (lower.contains('build_artifact_missing') ||
        lower.contains('expected build artifact') ||
        lower.contains('executable was not found')) {
      return BuildFailureAnalysis(
        kind: BuildFailureKind.artifact,
        summary:
            'Команда не создала ожидаемый артефакт либо оболочка проверяет неверный путь.',
        suggestedDiagnosticCommand: diagnostic,
        recommendedAction:
            'Проверь фактически выполненную команду, PROCESS_EXIT_CODE, stdout/stderr и реальный путь результата. Не редактируй исходники без сообщения компилятора.',
      );
    }

    return BuildFailureAnalysis(
      kind: BuildFailureKind.unknown,
      summary: 'Причина ошибки сборки пока не классифицирована.',
      suggestedDiagnosticCommand: diagnostic,
      recommendedAction:
          'Не меняй код вслепую. Выполни справочную/диагностическую команду, проверь структуру проекта и повтори сборку с более подробным выводом.',
    );
  }

  bool _looksSuccessful(String lower) {
    if (lower.contains('build_artifact_missing')) return false;
    return RegExp(r'(^|\n)exit_code:\s*0(?:\r?\n|$)').hasMatch(lower) ||
        lower.contains('final_status: success') ||
        lower.contains('build_artifact_ok');
  }

  Map<String, int> _sourceLocations(String output, String projectRoot) {
    final result = <String, int>{};
    void addMatches(RegExp pattern) {
      for (final match in pattern.allMatches(output)) {
        final file = _normalizeDiagnosticPath(
          (match.group(1) ?? '').trim(),
          projectRoot,
        );
        final line = int.tryParse(match.group(2) ?? '') ?? 0;
        if (file.isNotEmpty && line > 0) {
          result.putIfAbsent(file, () => line);
        }
      }
    }

    addMatches(_gccSourceError);
    addMatches(_msvcSourceError);
    return result;
  }

  String _normalizeDiagnosticPath(String raw, String projectRoot) {
    var file = raw.replaceAll('\\', '/').replaceFirst(RegExp(r'^\./'), '');
    final root =
        projectRoot.trim().replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
    if (root.isNotEmpty) {
      final lowerFile = file.toLowerCase();
      final lowerRoot = root.toLowerCase();
      if (lowerFile == lowerRoot) return '.';
      if (lowerFile.startsWith('$lowerRoot/')) {
        file = file.substring(root.length + 1);
      }
    }
    return file.replaceFirst(RegExp(r'^/+'), '');
  }

  String? _missingHeader(String output) {
    final gcc = _gccMissingHeader.firstMatch(output)?.group(1)?.trim();
    if (gcc != null && gcc.isNotEmpty) return gcc;
    final msvc = _msvcMissingHeader.firstMatch(output)?.group(1)?.trim();
    return msvc == null || msvc.isEmpty ? null : msvc;
  }

  String? _findProjectDependency(String projectRoot, String requested) {
    if (projectRoot.trim().isEmpty) return null;
    final root = Directory(projectRoot);
    if (!root.existsSync()) return null;
    final normalized = requested.replaceAll('\\', '/').toLowerCase();
    final basename = normalized.split('/').last;
    var inspected = 0;
    try {
      for (final entity in root.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        inspected++;
        if (inspected > 10000) break;
        final relative = entity.path
            .substring(root.path.length)
            .replaceAll('\\', '/')
            .replaceFirst(RegExp(r'^/+'), '');
        final lower = relative.toLowerCase();
        if (lower.startsWith('build/') ||
            lower.contains('/build/') ||
            lower.startsWith('.cppagent/')) {
          continue;
        }
        if (lower == normalized ||
            lower.endsWith('/$normalized') ||
            lower.split('/').last == basename) {
          return relative;
        }
      }
    } catch (_) {
      // Best effort only.
    }
    return null;
  }

  String? _suggestedDiagnostic(String command, String lowerOutput) {
    final explicit = RegExp(
      r'''(?:run|try|use|specify)\s+[`"']?([a-zA-Z0-9_+.-]+\s+--help)[`"']?''',
      caseSensitive: false,
    ).firstMatch(lowerOutput)?.group(1);
    if (explicit != null && _isSafeHelpCommand(explicit)) return explicit;

    final asksForHelp = lowerOutput.contains('specify --help for usage') ||
        lowerOutput.contains('try --help') ||
        lowerOutput.contains('use --help') ||
        lowerOutput.contains('usage:') ||
        lowerOutput.contains('unknown option') ||
        lowerOutput.contains('unrecognized option') ||
        lowerOutput.contains('unknown argument');
    if (!asksForHelp) return null;

    final executable = _firstExecutable(command);
    if (executable == null) return null;
    final candidate = '$executable --help';
    return _isSafeHelpCommand(candidate) ? candidate : null;
  }

  String? _firstExecutable(String command) {
    var value = command.trim();
    while (value.startsWith('(')) value = value.substring(1).trimLeft();
    final quoted = RegExp(r'''^"([^"]+)"''').firstMatch(value);
    var raw = quoted?.group(1);
    raw ??= RegExp(r'''^([^\s&|;]+)''').firstMatch(value)?.group(1);
    if (raw == null || raw.isEmpty) return null;
    final normalized = raw.replaceAll('\\', '/');
    final basename = normalized.split('/').last.toLowerCase();
    return basename.endsWith('.exe')
        ? basename.substring(0, basename.length - 4)
        : basename;
  }

  bool _isSafeHelpCommand(String command) {
    final normalized = command.trim().toLowerCase();
    final match = RegExp(r'^([a-z0-9_+.-]+)\s+--help$').firstMatch(normalized);
    if (match == null) return false;
    return const <String>{
      'cmake',
      'ninja',
      'g++',
      'gcc',
      'clang++',
      'clang',
      'cl',
      'msbuild',
      'flutter',
      'dart',
      'gradle',
      'gradlew',
      'cargo',
      'npm',
      'node',
      'python',
      'python3',
    }.contains(match.group(1));
  }

  static String _parentPath(String value) {
    final normalized = value.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index <= 0 ? '.' : normalized.substring(0, index);
  }

  bool _containsAny(String value, List<String> needles) =>
      needles.any(value.contains);
}
