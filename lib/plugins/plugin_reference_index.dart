import 'dart:convert';
import 'dart:io';

import '../agent_core/retrieval/hybrid_retrieval.dart';
import '../utils/path_utils.dart';
import 'plugin_models.dart';

class PluginReferenceIndex {
  PluginReferenceIndex({required this.sourceDirectory});

  final Directory Function(String pluginId) sourceDirectory;
  final HybridRetrievalEngine _retrieval = const HybridRetrievalEngine();
  final Map<String, List<HybridDocument>> _cache = {};

  void invalidate(String pluginId) {
    _cache.removeWhere((key, _) => key.startsWith('$pluginId:'));
  }

  Future<String> search(
    AgentPlugin plugin,
    String query, {
    int maxResults = 8,
  }) async {
    final documents = await _documents(plugin);
    final results = _retrieval.search(query, documents, maxResults: maxResults);
    if (results.isEmpty) {
      return 'PLUGIN_DOCS_NO_RESULTS: ${plugin.name}: $query';
    }
    final buffer = StringBuffer('PLUGIN_DOCS_RESULTS: ${plugin.name}\n');
    for (final result in results) {
      final path = result.document.metadata['path']?.toString() ?? '';
      buffer.writeln(
        '\n--- ${result.document.title} [$path] '
        'score=${result.score.toStringAsFixed(2)} ---',
      );
      buffer.writeln(_excerpt(result.document.text, query));
    }
    return buffer.toString().trimRight();
  }

  Future<List<HybridDocument>> _documents(AgentPlugin plugin) async {
    final cacheKey = '${plugin.id}:${plugin.installedCommit}';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final documents = <HybridDocument>[
      HybridDocument(
        id: '${plugin.id}:summary',
        title: '${plugin.name} — встроенное описание',
        text: '${plugin.description}\n${plugin.bundledSummary}',
        metadata: const {'path': 'bundled-summary'},
      ),
    ];
    final source = sourceDirectory(plugin.id);
    if (plugin.sourceInstalled && await source.exists()) {
      var scannedFiles = 0;
      var totalChunks = 0;
      await for (final entity in source.list(recursive: true, followLinks: false)) {
        if (entity is! File || scannedFiles >= 1500 || totalChunks >= 5000) {
          continue;
        }
        final lower = entity.path.toLowerCase();
        if (!_isReferenceTextFile(lower)) continue;
        scannedFiles++;
        try {
          if (await entity.length() > 2 * 1024 * 1024) continue;
          final text = await entity.readAsString(
            encoding: const Utf8Codec(allowMalformed: true),
          );
          if (text.trim().isEmpty) continue;
          final relativePath =
              entity.path.substring(source.path.length).replaceAll('\\', '/');
          final chunks = _chunkText(text);
          for (var i = 0; i < chunks.length && totalChunks < 5000; i++) {
            documents.add(HybridDocument(
              id: '${entity.path}#$i',
              title: chunks.length == 1
                  ? pathBasename(entity.path)
                  : '${pathBasename(entity.path)} • фрагмент ${i + 1}',
              text: chunks[i],
              metadata: {'path': relativePath, 'chunk': i + 1},
            ));
            totalChunks++;
          }
        } catch (_) {
          // A single malformed or unreadable reference file is skipped.
        }
      }
    }

    final frozen = List<HybridDocument>.unmodifiable(documents);
    invalidate(plugin.id);
    _cache[cacheKey] = frozen;
    return frozen;
  }

  List<String> _chunkText(
    String value, {
    int targetChars = 7000,
    int overlapChars = 350,
  }) {
    final text = value.replaceAll('\r\n', '\n').trim();
    if (text.isEmpty) return const [];
    if (text.length <= targetChars) return [text];
    final chunks = <String>[];
    var start = 0;
    while (start < text.length && chunks.length < 100) {
      var end = (start + targetChars).clamp(0, text.length).toInt();
      if (end < text.length) {
        final searchStart =
            (end - targetChars ~/ 3).clamp(start, end).toInt();
        final headingBreak = text.lastIndexOf(RegExp(r'\n#{1,6}\s'), end);
        final paragraphBreak = text.lastIndexOf('\n\n', end);
        final lineBreak = text.lastIndexOf('\n', end);
        final preferred = [headingBreak, paragraphBreak, lineBreak]
            .where((index) => index >= searchStart)
            .fold<int>(-1, (best, index) => index > best ? index : best);
        if (preferred > start) end = preferred;
      }
      if (end <= start) {
        end = (start + targetChars).clamp(0, text.length).toInt();
      }
      final chunk = text.substring(start, end).trim();
      if (chunk.isNotEmpty) chunks.add(chunk);
      if (end >= text.length) break;
      start = (end - overlapChars).clamp(start + 1, text.length).toInt();
    }
    return chunks;
  }

  bool _isReferenceTextFile(String lowerPath) =>
      lowerPath.endsWith('.md') ||
      lowerPath.endsWith('.txt') ||
      lowerPath.endsWith('.rst') ||
      lowerPath.endsWith('.yaml') ||
      lowerPath.endsWith('.yml') ||
      lowerPath.endsWith('.json') ||
      lowerPath.endsWith('.toml');

  String _excerpt(String text, String query, {int maxChars = 1800}) {
    final clean = text.replaceAll('\u0000', '').trim();
    if (clean.length <= maxChars) return clean;
    final lower = clean.toLowerCase();
    final normalizedQuery = query.trim().toLowerCase();
    final matchIndex = normalizedQuery.isEmpty
        ? -1
        : lower.indexOf(normalizedQuery);
    final start = (matchIndex < 0
            ? 0
            : (matchIndex - maxChars ~/ 3).clamp(0, clean.length))
        .toInt();
    final end = (start + maxChars).clamp(0, clean.length).toInt();
    return '${start > 0 ? '…' : ''}'
        '${clean.substring(start, end)}'
        '${end < clean.length ? '…' : ''}';
  }
}
