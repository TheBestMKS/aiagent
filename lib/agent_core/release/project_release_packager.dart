import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

import '../../utils/path_utils.dart';

class ProjectReleaseRequest {
  const ProjectReleaseRequest({
    required this.programName,
    required this.version,
    required this.platform,
    required this.architecture,
    required this.artifactPaths,
    required this.changeEnglish,
    required this.changeRussian,
    required this.readmeEnglish,
    required this.readmeRussian,
  });

  final String programName;
  final String version;
  final String platform;
  final String architecture;
  final List<String> artifactPaths;
  final String changeEnglish;
  final String changeRussian;
  final String readmeEnglish;
  final String readmeRussian;
}

class ProjectReleaseResult {
  const ProjectReleaseResult({
    required this.directory,
    required this.files,
    required this.checksums,
  });

  final Directory directory;
  final List<String> files;
  final Map<String, String> checksums;

  String toAgentText() => '''PROJECT_RELEASE_READY
DIRECTORY: ${directory.path}
FILES:
${files.map((item) => '- $item').join('\n')}
SHA256:
${checksums.entries.map((item) => '- ${item.value}  ${item.key}').join('\n')}''';
}

class ProjectReleasePackager {
  const ProjectReleasePackager();

  static const _excludedSourceSegments = <String>{
    '.git',
    '.cppagent',
    '.dart_tool',
    '.idea',
    '.vscode',
    'build',
    'release',
    'node_modules',
    '__pycache__',
    '.pytest_cache',
    '.gradle',
  };

  Future<ProjectReleaseResult> package({
    required Directory projectRoot,
    required ProjectReleaseRequest request,
  }) async {
    final root = projectRoot.absolute;
    if (!await root.exists()) {
      throw StateError('Project directory does not exist: ${root.path}');
    }
    final program = _safeName(request.programName, fallback: 'program');
    final version = _safeVersion(request.version);
    final platform = _safeName(request.platform, fallback: _hostPlatform());
    final architecture = _safeName(request.architecture, fallback: 'universal');
    _validateMetadata('CHANGE_en.md', request.changeEnglish);
    _validateMetadata('CHANGE_ru.md', request.changeRussian);
    _validateMetadata('README_en.md', request.readmeEnglish);
    _validateMetadata('README_ru.md', request.readmeRussian);

    final releaseRoot = Directory(pathJoin(root.path, 'release'));
    final target = Directory(pathJoin(releaseRoot.path, '${program}_$version'));
    final staging = Directory(pathJoin(
      root.path,
      '.cppagent',
      'release_staging',
      '${program}_${version}_${DateTime.now().microsecondsSinceEpoch}',
    ));
    await staging.create(recursive: true);

    try {
      await _writeText(staging, 'CHANGE_en.md', request.changeEnglish);
      await _writeText(staging, 'CHANGE_ru.md', request.changeRussian);
      await _writeText(staging, 'README_en.md', request.readmeEnglish);
      await _writeText(staging, 'README_ru.md', request.readmeRussian);

      final sourceName = 'source_$version.zip';
      await _zipSource(root, File(pathJoin(staging.path, sourceName)));

      final artifactBase = '${program}_${version}_${platform}_$architecture';
      var artifactIndex = 0;
      for (final rawPath in request.artifactPaths) {
        final path = rawPath.trim();
        if (path.isEmpty) continue;
        final resolved =
            isAbsolutePath(path) ? path : resolveProjectPath(root.path, path);
        final file = File(resolved);
        final directory = Directory(resolved);
        final suffix = artifactIndex == 0 ? '' : '_${artifactIndex + 1}';
        if (await file.exists()) {
          final extension = _extension(pathBasename(file.path));
          await file.copy(
            pathJoin(staging.path, '$artifactBase$suffix$extension'),
          );
          artifactIndex++;
        } else if (await directory.exists()) {
          await _zipDirectory(
            directory,
            File(pathJoin(staging.path, '$artifactBase$suffix.zip')),
          );
          artifactIndex++;
        } else {
          throw StateError('Release artifact does not exist: $path');
        }
      }

      final checksums = await _calculateChecksums(staging);
      final checksumText = checksums.entries
          .map((entry) => '${entry.value}  ${entry.key}')
          .join('\n');
      await _writeText(staging, 'SHA256SUMS.txt', '$checksumText\n');
      await _validateStaging(staging, version);

      await releaseRoot.create(recursive: true);
      if (await target.exists()) {
        final backup = Directory(pathJoin(
          root.path,
          '.cppagent',
          'release_backups',
          '${program}_${version}_${DateTime.now().microsecondsSinceEpoch}',
        ));
        await backup.parent.create(recursive: true);
        await target.rename(backup.path);
      }
      await staging.rename(target.path);

      final files = await _relativeFiles(target);
      return ProjectReleaseResult(
        directory: target,
        files: files,
        checksums: checksums,
      );
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> _zipSource(Directory root, File output) async {
    final encoder = ZipFileEncoder()..create(output.path);
    try {
      final entities = root.listSync(recursive: true, followLinks: false);
      for (final entity in entities.whereType<File>()) {
        final relative = pathRelative(root.path, entity.path)
            .replaceAll('\\', '/')
            .replaceAll(RegExp(r'^/+'), '');
        if (_isExcludedSourcePath(relative)) continue;
        await encoder.addFile(entity, relative);
      }
    } finally {
      await encoder.close();
    }
  }

  Future<void> _zipDirectory(Directory directory, File output) async {
    final encoder = ZipFileEncoder()..create(output.path);
    try {
      await encoder.addDirectory(
        directory,
        includeDirName: true,
        followLinks: false,
      );
    } finally {
      await encoder.close();
    }
  }

  bool _isExcludedSourcePath(String path) {
    final parts = path.toLowerCase().split('/');
    return parts.any(_excludedSourceSegments.contains);
  }

  Future<Map<String, String>> _calculateChecksums(Directory directory) async {
    final result = <String, String>{};
    for (final file in directory.listSync(recursive: true).whereType<File>()) {
      final relative =
          pathRelative(directory.path, file.path).replaceAll('\\', '/');
      if (relative == 'SHA256SUMS.txt') continue;
      result[relative] = (await sha256.bind(file.openRead()).first).toString();
    }
    final sorted = result.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Map.fromEntries(sorted);
  }

  Future<List<String>> _relativeFiles(Directory directory) async {
    final result = directory
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .map((file) =>
            pathRelative(directory.path, file.path).replaceAll('\\', '/'))
        .toList()
      ..sort();
    return result;
  }

  Future<void> _validateStaging(Directory directory, String version) async {
    final required = <String>{
      'SHA256SUMS.txt',
      'CHANGE_en.md',
      'CHANGE_ru.md',
      'README_en.md',
      'README_ru.md',
      'source_$version.zip',
    };
    final actual = (await _relativeFiles(directory)).toSet();
    final missing = required.difference(actual);
    if (missing.isNotEmpty) {
      throw StateError(
          'Release validation failed, missing: ${missing.join(', ')}');
    }
    final checksum = await File(pathJoin(directory.path, 'SHA256SUMS.txt'))
        .readAsString(encoding: utf8);
    for (final file in actual.where((item) => item != 'SHA256SUMS.txt')) {
      if (!checksum.contains('  $file')) {
        throw StateError('Checksum is missing for $file');
      }
    }
  }

  Future<void> _writeText(Directory directory, String name, String value) =>
      File(pathJoin(directory.path, name)).writeAsString(
        '${value.trim()}\n',
        encoding: utf8,
        flush: true,
      );

  void _validateMetadata(String name, String value) {
    final text = value.trim();
    if (text.length < 40) {
      throw ArgumentError('$name must contain a useful description');
    }
    if (RegExp(
      r'(\bTODO\b|\bTBD\b|placeholder|lorem ipsum|заглушк|будет добавлен|omitted)',
      caseSensitive: false,
    ).hasMatch(text)) {
      throw ArgumentError('$name contains placeholder text');
    }
  }

  String _safeVersion(String value) {
    final result = value.trim().replaceAll(RegExp(r'[^0-9A-Za-z._+-]+'), '_');
    if (result.isEmpty) throw ArgumentError('Version is required');
    return result;
  }

  String _safeName(String value, {required String fallback}) {
    final result = value
        .trim()
        .replaceAll(RegExp(r'[^0-9A-Za-zА-Яа-яЁё._+-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return result.isEmpty ? fallback : result;
  }

  String _extension(String name) {
    final index = name.lastIndexOf('.');
    if (index <= 0 || index == name.length - 1) return '';
    return name.substring(index);
  }

  String _hostPlatform() {
    if (Platform.isWindows) return 'win';
    if (Platform.isLinux) return 'linux';
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS) return 'macos';
    return Platform.operatingSystem;
  }
}
