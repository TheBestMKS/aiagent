import 'dart:convert';
import 'dart:io';

import '../../utils/path_utils.dart';

enum ProjectEcosystem {
  flutter,
  dart,
  node,
  python,
  cmake,
  rust,
  go,
  dotnet,
  maven,
  gradle,
  meson,
  make,
  zig,
  swift,
  ruby,
  php,
  cpp,
  c,
  java,
  unknown,
}

extension ProjectEcosystemLabel on ProjectEcosystem {
  String get label => switch (this) {
        ProjectEcosystem.flutter => 'Flutter',
        ProjectEcosystem.dart => 'Dart',
        ProjectEcosystem.node => 'Node.js',
        ProjectEcosystem.python => 'Python',
        ProjectEcosystem.cmake => 'CMake',
        ProjectEcosystem.rust => 'Rust/Cargo',
        ProjectEcosystem.go => 'Go',
        ProjectEcosystem.dotnet => '.NET',
        ProjectEcosystem.maven => 'Java/Maven',
        ProjectEcosystem.gradle => 'Gradle',
        ProjectEcosystem.meson => 'Meson',
        ProjectEcosystem.make => 'Make',
        ProjectEcosystem.zig => 'Zig',
        ProjectEcosystem.swift => 'Swift Package Manager',
        ProjectEcosystem.ruby => 'Ruby',
        ProjectEcosystem.php => 'PHP/Composer',
        ProjectEcosystem.cpp => 'C++',
        ProjectEcosystem.c => 'C',
        ProjectEcosystem.java => 'Java',
        ProjectEcosystem.unknown => 'Не определена',
      };
}

class ProjectBuildRecipe {
  const ProjectBuildRecipe({
    required this.ecosystem,
    required this.projectRoot,
    required this.signals,
    required this.sourceFiles,
    required this.verificationCommands,
    required this.buildCommands,
    required this.runCommands,
    required this.requiredExecutables,
    required this.missingExecutables,
  });

  final ProjectEcosystem ecosystem;
  final String projectRoot;
  final List<String> signals;
  final List<String> sourceFiles;
  final List<String> verificationCommands;
  final List<String> buildCommands;
  final List<String> runCommands;
  final List<String> requiredExecutables;
  final List<String> missingExecutables;

  bool get detected => ecosystem != ProjectEcosystem.unknown;

  String get preferredVerificationCommand =>
      verificationCommands.isEmpty ? '' : verificationCommands.first;

  String toPromptBlock() {
    final buffer = StringBuffer()
      ..writeln('[PROJECT_BUILD_RECIPE]')
      ..writeln('ecosystem=${ecosystem.name}')
      ..writeln('label=${ecosystem.label}')
      ..writeln('root=$projectRoot')
      ..writeln('signals=${signals.isEmpty ? '(none)' : signals.join(', ')}')
      ..writeln(
          'sources=${sourceFiles.isEmpty ? '(none)' : sourceFiles.take(20).join(', ')}')
      ..writeln('verification_commands:');
    if (verificationCommands.isEmpty) {
      buffer.writeln('- (not detected)');
    } else {
      for (final command in verificationCommands) {
        buffer.writeln('- $command');
      }
    }
    buffer.writeln('build_commands:');
    if (buildCommands.isEmpty) {
      buffer.writeln('- (not detected)');
    } else {
      for (final command in buildCommands) {
        buffer.writeln('- $command');
      }
    }
    if (runCommands.isNotEmpty) {
      buffer.writeln('run_commands:');
      for (final command in runCommands) {
        buffer.writeln('- $command');
      }
    }
    buffer.writeln(
        'required_executables=${requiredExecutables.isEmpty ? '(none)' : requiredExecutables.join(', ')}');
    buffer.writeln(
        'missing_executables=${missingExecutables.isEmpty ? '(none)' : missingExecutables.join(', ')}');
    buffer.writeln('[/PROJECT_BUILD_RECIPE]');
    return buffer.toString().trimRight();
  }
}

class ProjectBuildRecipeDetector {
  const ProjectBuildRecipeDetector();

  ProjectBuildRecipe detect(
    Directory root, {
    Map<String, String> executables = const <String, String>{},
    bool Function(String executable)? isExecutableAvailable,
    bool? windows,
  }) {
    final isWindows = windows ?? Platform.isWindows;
    final files = _projectFiles(root);
    final names = <String, String>{
      for (final file in files)
        pathBasename(file.path).toLowerCase():
            pathRelative(root.path, file.path).replaceAll('\\', '/'),
    };
    final sourceFiles = files
        .where((file) => _sourceExtensions
            .any((extension) => file.path.toLowerCase().endsWith(extension)))
        .map((file) => pathRelative(root.path, file.path).replaceAll('\\', '/'))
        .take(200)
        .toList(growable: false);
    final signals = <String>[];
    final verification = <String>[];
    final builds = <String>[];
    final runs = <String>[];
    final required = <String>[];
    var ecosystem = ProjectEcosystem.unknown;

    String exe(String name) => executables[name] ?? name;
    bool has(String name) => isExecutableAvailable?.call(exe(name)) ?? true;
    bool hasName(String name) => names.containsKey(name.toLowerCase());
    String signal(String name) => names[name.toLowerCase()] ?? name;
    bool hasDirectory(String name) =>
        Directory(pathJoin(root.path, name)).existsSync();

    if (hasName('pubspec.yaml')) {
      final pubspec = File(pathJoin(root.path, signal('pubspec.yaml')));
      var flutter = false;
      try {
        flutter = pubspec.readAsStringSync().contains('sdk: flutter');
      } catch (_) {}
      signals.add(signal('pubspec.yaml'));
      if (flutter) {
        ecosystem = ProjectEcosystem.flutter;
        required.add('flutter');
        verification.add('${exe('flutter')} analyze');
        if (hasDirectory('test')) verification.add('${exe('flutter')} test');
        if (isWindows && hasDirectory('windows')) {
          builds.add('${exe('flutter')} build windows --release');
        }
        if (hasDirectory('android')) {
          builds.add('${exe('flutter')} build apk --release');
        }
        if (hasDirectory('web')) {
          builds.add('${exe('flutter')} build web --release');
        }
      } else {
        ecosystem = ProjectEcosystem.dart;
        required.add('dart');
        verification.add('${exe('dart')} analyze');
        if (hasDirectory('test')) verification.add('${exe('dart')} test');
        if (File(pathJoin(root.path, 'bin', 'main.dart')).existsSync()) {
          builds.add('${exe('dart')} compile exe bin/main.dart');
          runs.add('${exe('dart')} run bin/main.dart');
        }
      }
    } else if (hasName('package.json')) {
      ecosystem = ProjectEcosystem.node;
      signals.add(signal('package.json'));
      required.add('npm');
      final scripts =
          _packageScripts(File(pathJoin(root.path, signal('package.json'))));
      if (scripts.contains('lint')) verification.add('${exe('npm')} run lint');
      if (scripts.contains('test')) verification.add('${exe('npm')} test');
      if (scripts.contains('build')) builds.add('${exe('npm')} run build');
      if (scripts.contains('start')) runs.add('${exe('npm')} start');
      if (verification.isEmpty && builds.isEmpty) {
        final javaScript = sourceFiles.where((path) =>
            path.endsWith('.js') ||
            path.endsWith('.mjs') ||
            path.endsWith('.cjs'));
        if (javaScript.isNotEmpty) {
          required.add('node');
          verification.add('${exe('node')} --check "${javaScript.first}"');
        } else if (hasName('tsconfig.json')) {
          verification.add('${exe('npm')} exec --offline tsc -- --noEmit');
        } else {
          verification.add('${exe('npm')} --version');
        }
      }
    } else if (hasName('cargo.toml')) {
      ecosystem = ProjectEcosystem.rust;
      signals.add(signal('cargo.toml'));
      required.add('cargo');
      verification.add('${exe('cargo')} test');
      builds.add('${exe('cargo')} build --release');
      runs.add('${exe('cargo')} run');
    } else if (hasName('go.mod')) {
      ecosystem = ProjectEcosystem.go;
      signals.add(signal('go.mod'));
      required.add('go');
      verification.add('${exe('go')} test ./...');
      builds.add('${exe('go')} build ./...');
      runs.add('${exe('go')} run .');
    } else if (names.keys
        .any((name) => name.endsWith('.sln') || name.endsWith('.csproj'))) {
      ecosystem = ProjectEcosystem.dotnet;
      signals.addAll(names.entries
          .where((entry) =>
              entry.key.endsWith('.sln') || entry.key.endsWith('.csproj'))
          .map((entry) => entry.value)
          .take(10));
      required.add('dotnet');
      verification.add('${exe('dotnet')} test');
      builds.add('${exe('dotnet')} build -c Release');
      runs.add('${exe('dotnet')} run');
    } else if (hasName('pom.xml')) {
      ecosystem = ProjectEcosystem.maven;
      signals.add(signal('pom.xml'));
      required.add('mvn');
      verification.add('${exe('mvn')} test');
      builds.add('${exe('mvn')} package -DskipTests');
    } else if (hasName(isWindows ? 'gradlew.bat' : 'gradlew') ||
        hasName('build.gradle') ||
        hasName('build.gradle.kts')) {
      ecosystem = ProjectEcosystem.gradle;
      final wrapper = hasName(isWindows ? 'gradlew.bat' : 'gradlew')
          ? (isWindows ? '.\\gradlew.bat' : './gradlew')
          : exe('gradle');
      signals.addAll(const [
        'gradlew',
        'gradlew.bat',
        'build.gradle',
        'build.gradle.kts'
      ].where(hasName).map(signal));
      if (!hasName(isWindows ? 'gradlew.bat' : 'gradlew')) {
        required.add('gradle');
      }
      verification.add('$wrapper test');
      builds.add('$wrapper build');
    } else if (hasName('cmakelists.txt')) {
      ecosystem = ProjectEcosystem.cmake;
      signals.add(signal('cmakelists.txt'));
      required.add('cmake');
      verification.add(
          '${exe('cmake')} -S . -B build && ${exe('cmake')} --build build');
      builds.add(
          '${exe('cmake')} -S . -B build -DCMAKE_BUILD_TYPE=Release && ${exe('cmake')} --build build --config Release');
    } else if (hasName('meson.build')) {
      ecosystem = ProjectEcosystem.meson;
      signals.add(signal('meson.build'));
      required.add('meson');
      required.add('ninja');
      verification
          .add('${exe('meson')} setup build && ${exe('meson')} test -C build');
      builds.add('${exe('meson')} compile -C build');
    } else if (hasName('makefile') || hasName('gnumakefile')) {
      ecosystem = ProjectEcosystem.make;
      signals.add(
          hasName('makefile') ? signal('makefile') : signal('gnumakefile'));
      required.add('make');
      verification.add(exe('make'));
      builds.add(exe('make'));
    } else if (hasName('pyproject.toml') ||
        hasName('requirements.txt') ||
        sourceFiles.any((path) => path.endsWith('.py'))) {
      ecosystem = ProjectEcosystem.python;
      signals.addAll(const ['pyproject.toml', 'requirements.txt', 'setup.py']
          .where(hasName)
          .map(signal));
      required.add('python');
      verification.add('${exe('python')} -m compileall .');
      if (hasDirectory('test') || hasDirectory('tests')) {
        verification.add('${exe('python')} -m pytest');
      }
      final main = sourceFiles
          .where((path) => path.endsWith('/main.py') || path == 'main.py');
      if (main.isNotEmpty) runs.add('${exe('python')} "${main.first}"');
    } else if (hasName('build.zig')) {
      ecosystem = ProjectEcosystem.zig;
      signals.add(signal('build.zig'));
      required.add('zig');
      verification.add('${exe('zig')} build test');
      builds.add('${exe('zig')} build -Doptimize=ReleaseSafe');
      runs.add('${exe('zig')} build run');
    } else if (hasName('package.swift')) {
      ecosystem = ProjectEcosystem.swift;
      signals.add(signal('package.swift'));
      required.add('swift');
      verification.add('${exe('swift')} test');
      builds.add('${exe('swift')} build -c release');
      runs.add('${exe('swift')} run');
    } else if (hasName('gemfile')) {
      ecosystem = ProjectEcosystem.ruby;
      signals.add(signal('gemfile'));
      required.add('bundle');
      verification.add('${exe('bundle')} exec rake test');
      builds.add('${exe('bundle')} exec rake build');
    } else if (hasName('composer.json')) {
      ecosystem = ProjectEcosystem.php;
      signals.add(signal('composer.json'));
      required.add('composer');
      verification.add('${exe('composer')} test');
      builds.add('${exe('composer')} install --no-dev --optimize-autoloader');
    } else if (sourceFiles.any((path) =>
        path.endsWith('.cpp') ||
        path.endsWith('.cc') ||
        path.endsWith('.cxx'))) {
      ecosystem = ProjectEcosystem.cpp;
      required.add('g++');
      final createBuild =
          isWindows ? 'if not exist build mkdir build' : 'mkdir -p build';
      final source = sourceFiles.firstWhere(
          (path) => pathBasename(path).toLowerCase() == 'main.cpp',
          orElse: () => sourceFiles.first);
      verification.add(
          '$createBuild && ${exe('g++')} "$source" -std=c++17 -O0 -g -o build/app');
      builds.add(
          '$createBuild && ${exe('g++')} "$source" -std=c++17 -O2 -o build/app');
    } else if (sourceFiles.any((path) => path.endsWith('.c'))) {
      ecosystem = ProjectEcosystem.c;
      required.add('gcc');
      final createBuild =
          isWindows ? 'if not exist build mkdir build' : 'mkdir -p build';
      final source = sourceFiles.firstWhere(
          (path) => pathBasename(path).toLowerCase() == 'main.c',
          orElse: () => sourceFiles.first);
      verification.add(
          '$createBuild && ${exe('gcc')} "$source" -std=c11 -O0 -g -o build/app');
      builds.add(
          '$createBuild && ${exe('gcc')} "$source" -std=c11 -O2 -o build/app');
    } else if (sourceFiles.any((path) => path.endsWith('.java'))) {
      ecosystem = ProjectEcosystem.java;
      required.add('javac');
      final javaFiles =
          sourceFiles.where((path) => path.endsWith('.java')).take(100);
      builds.add(
          '${exe('javac')} ${javaFiles.map((path) => '"$path"').join(' ')}');
      verification.add(builds.first);
    }

    final missing = required.where((name) => !has(name)).toSet().toList();
    return ProjectBuildRecipe(
      ecosystem: ecosystem,
      projectRoot: root.absolute.path,
      signals: signals.toSet().toList(growable: false),
      sourceFiles: sourceFiles,
      verificationCommands: verification.toSet().toList(growable: false),
      buildCommands: builds.toSet().toList(growable: false),
      runCommands: runs.toSet().toList(growable: false),
      requiredExecutables: required.toSet().toList(growable: false),
      missingExecutables: missing,
    );
  }

  Set<String> _packageScripts(File packageFile) {
    try {
      final decoded = jsonDecode(packageFile.readAsStringSync());
      if (decoded is! Map || decoded['scripts'] is! Map) return const {};
      return (decoded['scripts'] as Map)
          .keys
          .map((key) => key.toString())
          .toSet();
    } catch (_) {
      return const {};
    }
  }

  List<File> _projectFiles(Directory root) {
    if (!root.existsSync()) return const [];
    final result = <File>[];
    try {
      for (final entity in root.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final relative =
            pathRelative(root.path, entity.path).replaceAll('\\', '/');
        final segments = relative.toLowerCase().split('/');
        if (segments.any(_ignoredDirectoryNames.contains)) continue;
        result.add(entity);
        if (result.length >= 5000) break;
      }
    } catch (_) {}
    return result;
  }

  static const _ignoredDirectoryNames = <String>{
    '.git',
    '.cppagent',
    '.dart_tool',
    '.gradle',
    'build',
    'dist',
    'release',
    'node_modules',
    'target',
    '.idea',
    '.vscode',
  };

  static const _sourceExtensions = <String>[
    '.dart',
    '.js',
    '.mjs',
    '.cjs',
    '.ts',
    '.jsx',
    '.tsx',
    '.py',
    '.cpp',
    '.cc',
    '.cxx',
    '.c',
    '.h',
    '.hpp',
    '.rs',
    '.go',
    '.cs',
    '.java',
    '.kt',
    '.kts',
    '.swift',
    '.rb',
    '.php',
    '.zig',
  ];
}
