import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';

import '../utils/path_utils.dart';
import 'plugin_models.dart';

class PluginGithubUpdater {
  PluginGithubUpdater({
    required this.pluginsRoot,
    required this.onStatus,
  });

  final Directory pluginsRoot;
  final void Function(PluginOperationStatus status) onStatus;

  Directory get stagingRoot => Directory(pathJoin(pluginsRoot.path, '.staging'));
  Directory get backupRoot => Directory(pathJoin(pluginsRoot.path, '.backup'));

  Directory pluginDirectory(String pluginId) =>
      Directory(pathJoin(pluginsRoot.path, pluginId));

  Directory pluginSourceDirectory(String pluginId) =>
      Directory(pathJoin(pluginDirectory(pluginId).path, 'source'));

  Future<void> initialize() async {
    await stagingRoot.create(recursive: true);
    await backupRoot.create(recursive: true);
  }

  Future<String> fetchLatestCommit(AgentPlugin plugin) async {
    final uri = Uri.https(
      'api.github.com',
      '/repos/${plugin.repository}/commits/${plugin.defaultBranch}',
    );
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'AIAgent-PluginManager/1.0',
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      final response = await request.close().timeout(const Duration(seconds: 45));
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        throw HttpException(
          'GitHub HTTP ${response.statusCode}: ${_excerpt(body)}',
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['sha'] == null) {
        throw const FormatException('GitHub response has no commit SHA');
      }
      final sha = decoded['sha'].toString();
      if (!RegExp(r'^[0-9a-f]{40}$', caseSensitive: false).hasMatch(sha)) {
        throw const FormatException('GitHub response contains an invalid commit SHA');
      }
      return sha;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> installCommit(AgentPlugin plugin, String commit) async {
    if (!RegExp(r'^[0-9a-f]{40}$', caseSensitive: false).hasMatch(commit)) {
      throw ArgumentError.value(commit, 'commit', 'Expected a full Git commit SHA');
    }
    await initialize();
    final operationId = '${plugin.id}_${DateTime.now().microsecondsSinceEpoch}';
    final zipFile = File(pathJoin(stagingRoot.path, '$operationId.zip'));
    final extractDir = Directory(pathJoin(stagingRoot.path, operationId));
    try {
      await _downloadArchive(plugin, commit, zipFile);
      await extractDir.create(recursive: true);
      onStatus(PluginOperationStatus(
        active: true,
        message: 'Проверка и распаковка ${plugin.name}',
        pluginId: plugin.id,
      ));
      await _extractZip(zipFile, extractDir);
      final extractedRoot = _singleExtractedRoot(extractDir);
      await _validateExtractedSource(plugin, extractedRoot);
      await _activateSource(plugin, extractedRoot, commit);
    } finally {
      if (await zipFile.exists()) await zipFile.delete();
      if (await extractDir.exists()) await extractDir.delete(recursive: true);
    }
  }

  Future<void> _downloadArchive(
    AgentPlugin plugin,
    String commit,
    File destination,
  ) async {
    final uri = Uri.https(
      'codeload.github.com',
      '/${plugin.repository}/zip/$commit',
    );
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'AIAgent-PluginManager/1.0',
      );
      final response = await request.close().timeout(const Duration(minutes: 2));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await utf8.decoder.bind(response).join();
        throw HttpException(
          'GitHub archive HTTP ${response.statusCode}: ${_excerpt(body)}',
        );
      }

      const maxArchiveBytes = 512 * 1024 * 1024;
      final total = response.contentLength;
      if (total > maxArchiveBytes) {
        throw StateError('GitHub archive is too large: ${_formatBytes(total)}');
      }
      await destination.parent.create(recursive: true);
      final sink = destination.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.timeout(const Duration(minutes: 20))) {
          received += chunk.length;
          if (received > maxArchiveBytes) {
            throw StateError('GitHub archive exceeded the 512 MB safety limit');
          }
          sink.add(chunk);
          onStatus(PluginOperationStatus(
            active: true,
            message: 'Загрузка ${plugin.name}: ${_formatBytes(received)}',
            progress: total > 0 ? received / total : null,
            pluginId: plugin.id,
          ));
        }
      } finally {
        await sink.close();
      }
      if (received < 100) {
        throw StateError('Downloaded GitHub archive is empty');
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _extractZip(File archiveFile, Directory destination) async {
    final archivePath = archiveFile.path;
    final destinationPath = destination.path;
    await Isolate.run(
      () => _extractPluginZipWorker(archivePath, destinationPath),
    );
  }

  Directory _singleExtractedRoot(Directory extraction) {
    final children = extraction.listSync(followLinks: false);
    final directories = children.whereType<Directory>().toList();
    if (directories.length == 1) return directories.single;
    return extraction;
  }

  Future<void> _validateExtractedSource(
    AgentPlugin plugin,
    Directory extractedRoot,
  ) async {
    if (!await extractedRoot.exists()) {
      throw StateError('Extracted source is missing');
    }
    final entries = extractedRoot.listSync(followLinks: false);
    if (entries.isEmpty) throw StateError('Extracted source is empty');
    final hasReadme = entries.whereType<File>().any(
          (file) => pathBasename(file.path).toLowerCase().startsWith('readme'),
        );
    if (!hasReadme) {
      throw StateError('${plugin.name}: README was not found in downloaded source');
    }
  }

  Future<void> _activateSource(
    AgentPlugin plugin,
    Directory extractedRoot,
    String commit,
  ) async {
    final pluginDir = pluginDirectory(plugin.id);
    await pluginDir.create(recursive: true);
    final target = pluginSourceDirectory(plugin.id);
    final backup = Directory(
      pathJoin(
        backupRoot.path,
        '${plugin.id}_${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
    final manifest = File(pathJoin(pluginDir.path, 'plugin.json'));
    final manifestTemp = File('${manifest.path}.tmp');
    final previousManifest =
        await manifest.exists() ? await manifest.readAsBytes() : null;
    if (await target.exists()) await target.rename(backup.path);
    try {
      await extractedRoot.rename(target.path);
      await manifestTemp.writeAsString(
        prettyPluginJson({
          'schemaVersion': 1,
          'id': plugin.id,
          'name': plugin.name,
          'repository': plugin.repository,
          'commit': commit,
          'toolName': plugin.toolName,
          'kind': plugin.kind.name,
          'permissions': plugin.permissions
              .map((permission) => permission.name)
              .toList(growable: false),
          'sensitive': plugin.sensitive,
          'installedAt': DateTime.now().toIso8601String(),
        }),
        encoding: utf8,
        flush: true,
      );
      if (await manifest.exists()) await manifest.delete();
      await manifestTemp.rename(manifest.path);
      if (await backup.exists()) await backup.delete(recursive: true);
    } catch (_) {
      if (await manifestTemp.exists()) await manifestTemp.delete();
      if (await target.exists()) await target.delete(recursive: true);
      if (await backup.exists()) await backup.rename(target.path);
      if (previousManifest == null) {
        if (await manifest.exists()) await manifest.delete();
      } else {
        await manifest.writeAsBytes(previousManifest, flush: true);
      }
      rethrow;
    }
  }

  String _excerpt(String value, {int maxChars = 1800}) {
    final clean = value.replaceAll('\u0000', '').trim();
    if (clean.length <= maxChars) return clean;
    return '${clean.substring(0, maxChars)}…';
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }
}

Future<void> _extractPluginZipWorker(
  String archivePath,
  String destinationPath,
) async {
  final archiveFile = File(archivePath);
  final destination = Directory(destinationPath);
  final archive = ZipDecoder().decodeBytes(
    await archiveFile.readAsBytes(),
    verify: true,
  );
  if (archive.files.length > 100000) {
    throw StateError('Plugin archive contains too many entries');
  }

  var extractedBytes = 0;
  const maxExtractedBytes = 2 * 1024 * 1024 * 1024;
  final root = destination.absolute.path.replaceAll('\\', '/');
  for (final entry in archive.files) {
    extractedBytes += entry.size;
    if (extractedBytes > maxExtractedBytes) {
      throw StateError('Plugin archive exceeds the 2 GB extraction safety limit');
    }
    final normalized = entry.name.replaceAll('\\', '/');
    final parts = normalized
        .split('/')
        .where((part) => part.isNotEmpty && part != '.')
        .toList(growable: false);
    if (parts.isEmpty) continue;
    if (normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
        parts.contains('..')) {
      throw StateError('Unsafe path in plugin archive: ${entry.name}');
    }

    final targetPath = parts.fold<String>(
      destination.path,
      (current, part) => pathJoin(current, part),
    );
    final absoluteTarget = File(targetPath).absolute.path.replaceAll('\\', '/');
    if (!(absoluteTarget == root || absoluteTarget.startsWith('$root/'))) {
      throw StateError(
        'Archive entry escapes plugin staging directory: ${entry.name}',
      );
    }
    if (entry.isFile) {
      final file = File(targetPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(List<int>.from(entry.content), flush: true);
    } else {
      await Directory(targetPath).create(recursive: true);
    }
  }
}
