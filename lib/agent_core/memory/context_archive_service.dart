import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../utils/path_utils.dart';
import '../retrieval/hybrid_retrieval.dart';
import '../security/secret_redactor.dart';

typedef ContextDocumentTextExtractor = Future<String> Function(
  String path,
  int maxChars,
);
typedef ContextProjectPathsProvider = Iterable<String> Function();

enum ContextArchiveCorpus { projectContext, globalMemory, literature }

enum ContextArchiveScope {
  currentProject,
  otherProjects,
  allProjects,
  globalMemory,
  literature,
  all,
}

extension ContextArchiveScopeParsing on ContextArchiveScope {
  String get wireName => switch (this) {
        ContextArchiveScope.currentProject => 'current_project',
        ContextArchiveScope.otherProjects => 'other_projects',
        ContextArchiveScope.allProjects => 'all_projects',
        ContextArchiveScope.globalMemory => 'global_memory',
        ContextArchiveScope.literature => 'literature',
        ContextArchiveScope.all => 'all',
      };

  static ContextArchiveScope parse(String value) =>
      switch (value.trim().toLowerCase()) {
        'current' || 'current_project' => ContextArchiveScope.currentProject,
        'other' || 'other_projects' => ContextArchiveScope.otherProjects,
        'projects' || 'all_projects' => ContextArchiveScope.allProjects,
        'memory' || 'global_memory' => ContextArchiveScope.globalMemory,
        'documents' || 'literature' => ContextArchiveScope.literature,
        _ => ContextArchiveScope.all,
      };
}

class ContextArchiveChunk {
  const ContextArchiveChunk({
    required this.id,
    required this.sourceId,
    required this.sourcePath,
    required this.sourceSignature,
    required this.corpus,
    required this.projectPath,
    required this.projectName,
    required this.title,
    required this.chunkIndex,
    required this.text,
    required this.updatedAt,
  });

  final String id;
  final String sourceId;
  final String sourcePath;
  final String sourceSignature;
  final ContextArchiveCorpus corpus;
  final String projectPath;
  final String projectName;
  final String title;
  final int chunkIndex;
  final String text;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'sourceId': sourceId,
        'sourcePath': sourcePath,
        'sourceSignature': sourceSignature,
        'corpus': corpus.name,
        'projectPath': projectPath,
        'projectName': projectName,
        'title': title,
        'chunkIndex': chunkIndex,
        'text': text,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ContextArchiveChunk.fromJson(Map<String, dynamic> json) {
    final corpusName = json['corpus']?.toString() ?? '';
    return ContextArchiveChunk(
      id: json['id']?.toString() ?? '',
      sourceId: json['sourceId']?.toString() ?? '',
      sourcePath: json['sourcePath']?.toString() ?? '',
      sourceSignature: json['sourceSignature']?.toString() ?? '',
      corpus: ContextArchiveCorpus.values.firstWhere(
        (value) => value.name == corpusName,
        orElse: () => ContextArchiveCorpus.projectContext,
      ),
      projectPath: json['projectPath']?.toString() ?? '',
      projectName: json['projectName']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      chunkIndex: int.tryParse(json['chunkIndex']?.toString() ?? '') ?? 0,
      text: json['text']?.toString() ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class ContextArchiveSearchHit {
  const ContextArchiveSearchHit({required this.chunk, required this.score});

  final ContextArchiveChunk chunk;
  final double score;
}

class ContextArchiveIndexReport {
  const ContextArchiveIndexReport({
    required this.sources,
    required this.chunks,
    required this.reusedSources,
    required this.updatedSources,
    required this.skippedSources,
    required this.completedAt,
  });

  final int sources;
  final int chunks;
  final int reusedSources;
  final int updatedSources;
  final int skippedSources;
  final DateTime completedAt;

  String get summary =>
      'sources=$sources; chunks=$chunks; reused=$reusedSources; '
      'updated=$updatedSources; skipped=$skippedSources; '
      'completed=${completedAt.toIso8601String()}';
}

class ContextArchiveService {
  ContextArchiveService({
    required this.configRoot,
    required this.projectsRoot,
    required this.documentsRoot,
    required this.textExtractor,
    this.projectPathsProvider,
  });

  final Directory configRoot;
  Directory projectsRoot;
  final Directory documentsRoot;
  final ContextDocumentTextExtractor textExtractor;
  final ContextProjectPathsProvider? projectPathsProvider;
  final HybridRetrievalEngine _retrieval = const HybridRetrievalEngine();

  List<ContextArchiveChunk> _chunks = const [];
  Future<ContextArchiveIndexReport>? _activeRebuild;
  ContextArchiveIndexReport? lastReport;

  Directory get indexRoot =>
      Directory(pathJoin(configRoot.path, 'memory', 'context_archive'));
  File get indexFile => File(pathJoin(indexRoot.path, 'chunks.jsonl'));

  Future<void> initialize() async {
    await documentsRoot.create(recursive: true);
    await indexRoot.create(recursive: true);
    final readme = File(pathJoin(documentsRoot.path, 'README_RU.txt'));
    if (!await readme.exists()) {
      await readme.writeAsString(
        'Эта папка является общей библиотекой AI Agent.\n'
        'Положите сюда документацию, книги, стандарты, примеры кода и другие '
        'материалы, которые агент должен использовать при выполнении задач.\n\n'
        'Поддерживаются текстовые файлы, исходный код, JSON/YAML/XML/HTML, '
        'RTF, DOCX, XLSX, PPTX, VSDX, ODT/ODS/ODP/ODC и PDF '
        '(для PDF рекомендуется pdftotext или OCR в tools).\n'
        'Индекс обновляется перед поиском и вручную из настроек программы.\n',
        encoding: utf8,
      );
    }
    _chunks = await _readIndex();
  }

  void updateProjectsRoot(Directory value) {
    projectsRoot = value;
  }

  Future<ContextArchiveIndexReport> rebuild({
    String currentProjectPath = '',
    bool force = false,
  }) {
    final running = _activeRebuild;
    if (running != null) return running;
    final future = _rebuildInternal(
      currentProjectPath: currentProjectPath,
      force: force,
    );
    _activeRebuild = future;
    return future.whenComplete(() => _activeRebuild = null);
  }

  Future<List<ContextArchiveSearchHit>> search(
    String query, {
    ContextArchiveScope scope = ContextArchiveScope.all,
    String currentProjectPath = '',
    int maxResults = 8,
    bool includeOtherProjects = true,
    bool refresh = true,
  }) async {
    if (query.trim().isEmpty) return const [];
    if (refresh || _chunks.isEmpty) {
      await rebuild(currentProjectPath: currentProjectPath);
    }
    final current = normalizePathForCompare(currentProjectPath);
    final candidates = _chunks.where((chunk) {
      final chunkProject = normalizePathForCompare(chunk.projectPath);
      final isCurrent = current.isNotEmpty && chunkProject == current;
      final isOtherProject =
          chunk.corpus == ContextArchiveCorpus.projectContext &&
              chunkProject.isNotEmpty &&
              !isCurrent;
      if (!includeOtherProjects && isOtherProject) return false;
      return switch (scope) {
        ContextArchiveScope.currentProject =>
          chunk.corpus == ContextArchiveCorpus.projectContext && isCurrent,
        ContextArchiveScope.otherProjects => isOtherProject,
        ContextArchiveScope.allProjects =>
          chunk.corpus == ContextArchiveCorpus.projectContext,
        ContextArchiveScope.globalMemory =>
          chunk.corpus == ContextArchiveCorpus.globalMemory,
        ContextArchiveScope.literature =>
          chunk.corpus == ContextArchiveCorpus.literature,
        ContextArchiveScope.all => true,
      };
    }).toList(growable: false);
    final documents = candidates
        .map((chunk) => HybridDocument(
              id: chunk.id,
              title: '${chunk.title} ${chunk.projectName}',
              text: '${chunk.text}\n${chunk.sourcePath}\n${chunk.corpus.name}',
              metadata: {'chunk': chunk},
            ))
        .toList(growable: false);
    final raw = _retrieval.search(
      query,
      documents,
      maxResults: (maxResults * 8).clamp(16, 200).toInt(),
    );
    final now = DateTime.now();
    final ranked = raw.where((result) => result.score >= 0.2).map((result) {
      final chunk = result.document.metadata['chunk'] as ContextArchiveChunk;
      final chunkProject = normalizePathForCompare(chunk.projectPath);
      final currentBonus =
          current.isNotEmpty && chunkProject == current ? 1.0 : 0.0;
      final literatureBonus =
          chunk.corpus == ContextArchiveCorpus.literature ? 0.25 : 0.0;
      final ageDays = now.difference(chunk.updatedAt).inHours.abs() / 24.0;
      final recency = 0.25 / (1.0 + ageDays / 90.0);
      return ContextArchiveSearchHit(
        chunk: chunk,
        score: result.score + currentBonus + literatureBonus + recency,
      );
    }).toList(growable: false)
      ..sort((left, right) => right.score.compareTo(left.score));
    final result = <ContextArchiveSearchHit>[];
    final perSource = <String, int>{};
    for (final hit in ranked) {
      final count = perSource[hit.chunk.sourceId] ?? 0;
      if (count >= 2) continue;
      perSource[hit.chunk.sourceId] = count + 1;
      result.add(hit);
      if (result.length >= maxResults.clamp(1, 50)) break;
    }
    return result;
  }

  Future<String> formatSearchResults(
    String query, {
    ContextArchiveScope scope = ContextArchiveScope.all,
    String currentProjectPath = '',
    int maxResults = 8,
    bool includeOtherProjects = true,
    int maxCharsPerResult = 2600,
  }) async {
    final hits = await search(
      query,
      scope: scope,
      currentProjectPath: currentProjectPath,
      maxResults: maxResults,
      includeOtherProjects: includeOtherProjects,
    );
    if (hits.isEmpty) {
      return 'CONTEXT_SEARCH_NO_RESULTS: query=$query; scope=${scope.wireName}';
    }
    final buffer = StringBuffer(
        'CONTEXT_SEARCH_RESULTS: query="$query"; scope=${scope.wireName}; hits=${hits.length}\n');
    for (final hit in hits) {
      final chunk = hit.chunk;
      buffer
        ..writeln('\n--- ${chunk.title} ---')
        ..writeln('SOURCE_ID: ${chunk.sourceId}')
        ..writeln('SOURCE: ${chunk.sourcePath}')
        ..writeln('CORPUS: ${chunk.corpus.name}')
        ..writeln(
            'PROJECT: ${chunk.projectName.isEmpty ? '(global)' : chunk.projectName} ${chunk.projectPath}')
        ..writeln(
            'CHUNK: ${chunk.chunkIndex}; SCORE: ${hit.score.toStringAsFixed(3)}')
        ..writeln(truncateMiddle(chunk.text.trim(), maxCharsPerResult));
    }
    return buffer.toString().trimRight();
  }

  Future<String> readSource(
    String sourceId, {
    int offset = 0,
    int maxChars = 24000,
  }) async {
    if (_chunks.isEmpty) await rebuild();
    final found = _chunks.where((chunk) => chunk.sourceId == sourceId).toList()
      ..sort((left, right) => left.chunkIndex.compareTo(right.chunkIndex));
    if (found.isEmpty) return 'CONTEXT_SOURCE_NOT_FOUND: $sourceId';
    final combined = _combineChunks(found);
    final safeOffset = offset.clamp(0, combined.length).toInt();
    final end = (safeOffset + maxChars.clamp(1000, 100000))
        .clamp(safeOffset, combined.length)
        .toInt();
    return 'CONTEXT_SOURCE: ${found.first.sourcePath}\n'
        'SOURCE_ID: $sourceId\n'
        'OFFSET: $safeOffset; END: $end; TOTAL_CHARS: ${combined.length}\n'
        '${combined.substring(safeOffset, end)}';
  }

  Future<String> listLiterature({int maxItems = 200}) async {
    await rebuild();
    final bySource = <String, ContextArchiveChunk>{};
    for (final chunk in _chunks
        .where((item) => item.corpus == ContextArchiveCorpus.literature)) {
      bySource.putIfAbsent(chunk.sourceId, () => chunk);
    }
    final sources = bySource.values.toList()
      ..sort((left, right) => left.sourcePath.compareTo(right.sourcePath));
    final buffer = StringBuffer('LITERATURE_LIBRARY: ${documentsRoot.path}\n')
      ..writeln('FILES: ${sources.length}');
    for (final source in sources.take(maxItems.clamp(1, 2000))) {
      final chunks =
          _chunks.where((item) => item.sourceId == source.sourceId).length;
      buffer.writeln(
          '- ${source.title}; source_id=${source.sourceId}; chunks=$chunks; '
          'path=${source.sourcePath}');
    }
    return buffer.toString().trimRight();
  }

  Future<ContextArchiveIndexReport> _rebuildInternal({
    required String currentProjectPath,
    required bool force,
  }) async {
    await initializeDirectoriesOnly();
    final previous = _chunks.isEmpty ? await _readIndex() : _chunks;
    final previousBySource = <String, List<ContextArchiveChunk>>{};
    for (final chunk in previous) {
      previousBySource.putIfAbsent(chunk.sourcePath, () => []).add(chunk);
    }
    final sources = await _discoverSources(currentProjectPath);
    final next = <ContextArchiveChunk>[];
    var reused = 0;
    var updated = 0;
    var skipped = 0;
    for (final source in sources) {
      final cached = previousBySource[source.path] ?? const [];
      if (!force &&
          cached.isNotEmpty &&
          cached.every((chunk) => chunk.sourceSignature == source.signature)) {
        next.addAll(cached);
        reused++;
        continue;
      }
      try {
        final text = await _extractSourceText(source);
        if (text.trim().isEmpty) {
          skipped++;
          continue;
        }
        next.addAll(_createChunks(source, SecretRedactor.redact(text)));
        updated++;
      } catch (_) {
        skipped++;
      }
    }
    next.sort((left, right) {
      final source = left.sourcePath.compareTo(right.sourcePath);
      return source != 0 ? source : left.chunkIndex.compareTo(right.chunkIndex);
    });
    await _writeIndex(next);
    _chunks = List<ContextArchiveChunk>.unmodifiable(next);
    final report = ContextArchiveIndexReport(
      sources: sources.length,
      chunks: next.length,
      reusedSources: reused,
      updatedSources: updated,
      skippedSources: skipped,
      completedAt: DateTime.now(),
    );
    lastReport = report;
    return report;
  }

  Future<void> initializeDirectoriesOnly() async {
    await documentsRoot.create(recursive: true);
    await indexRoot.create(recursive: true);
  }

  Future<List<_ContextSource>> _discoverSources(
      String currentProjectPath) async {
    final result = <_ContextSource>[];
    final seen = <String>{};
    final projects = <Directory>[];
    final current = Directory(currentProjectPath);
    if (currentProjectPath.trim().isNotEmpty && await current.exists()) {
      projects.add(current);
    }
    if (await projectsRoot.exists()) {
      await for (final entity in projectsRoot.list(followLinks: false)) {
        if (entity is Directory) projects.add(entity);
      }
    }
    for (final path in projectPathsProvider?.call() ?? const <String>[]) {
      if (path.trim().isNotEmpty) projects.add(Directory(path.trim()));
    }
    for (final project in projects) {
      final normalized = normalizePathForCompare(project.absolute.path);
      if (!seen.add('project:$normalized')) continue;
      final agentRoot = Directory(pathJoin(project.path, '.cppagent'));
      if (!await agentRoot.exists()) continue;
      await for (final entity
          in agentRoot.list(recursive: true, followLinks: false)) {
        if (entity is! File || !_isProjectContextFile(agentRoot, entity))
          continue;
        final source = await _sourceForFile(
          entity,
          corpus: ContextArchiveCorpus.projectContext,
          projectPath: project.absolute.path,
          projectName: pathBasename(project.path),
          title:
              '${pathBasename(project.path)}: ${pathRelative(agentRoot.path, entity.path)}',
        );
        if (source != null &&
            seen.add('file:${normalizePathForCompare(source.path)}')) {
          result.add(source);
        }
      }
    }
    for (final file in <File>[
      File(pathJoin(configRoot.path, 'memory', 'records.jsonl')),
      File(pathJoin(configRoot.path, 'knowledge_base.jsonl')),
      File(pathJoin(configRoot.path, 'solution_memory.jsonl')),
    ]) {
      final source = await _sourceForFile(
        file,
        corpus: ContextArchiveCorpus.globalMemory,
        projectPath: '',
        projectName: '',
        title: 'Общая память: ${pathBasename(file.path)}',
      );
      if (source != null &&
          seen.add('file:${normalizePathForCompare(source.path)}')) {
        result.add(source);
      }
    }
    if (await documentsRoot.exists()) {
      await for (final entity
          in documentsRoot.list(recursive: true, followLinks: false)) {
        if (entity is! File || !_isLiteratureFile(entity.path)) continue;
        final source = await _sourceForFile(
          entity,
          corpus: ContextArchiveCorpus.literature,
          projectPath: '',
          projectName: '',
          title: pathRelative(documentsRoot.path, entity.path),
        );
        if (source != null &&
            seen.add('file:${normalizePathForCompare(source.path)}')) {
          result.add(source);
        }
      }
    }
    return result;
  }

  Future<_ContextSource?> _sourceForFile(
    File file, {
    required ContextArchiveCorpus corpus,
    required String projectPath,
    required String projectName,
    required String title,
  }) async {
    try {
      if (!await file.exists()) return null;
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) return null;
      final absolute = file.absolute.path;
      return _ContextSource(
        path: absolute,
        sourceId: sha256
            .convert(utf8.encode(normalizePathForCompare(absolute)))
            .toString()
            .substring(0, 20),
        signature:
            '${stat.size}:${stat.modified.toUtc().microsecondsSinceEpoch}',
        corpus: corpus,
        projectPath: projectPath,
        projectName: projectName,
        title: title,
        updatedAt: stat.modified,
      );
    } catch (_) {
      return null;
    }
  }

  bool _isProjectContextFile(Directory agentRoot, File file) {
    final relative = pathRelative(agentRoot.path, file.path)
        .replaceAll('\\', '/')
        .toLowerCase();
    if (!(relative.startsWith('sessions/') ||
        relative.startsWith('tasks/') ||
        relative.startsWith('runs/') ||
        relative.startsWith('terminal/'))) {
      return false;
    }
    return const ['.jsonl', '.json', '.md', '.txt']
        .any(file.path.toLowerCase().endsWith);
  }

  bool _isLiteratureFile(String path) {
    final lower = path.toLowerCase();
    return _literatureExtensions.any(lower.endsWith);
  }

  Future<String> _extractSourceText(_ContextSource source) async {
    final lower = source.path.toLowerCase();
    if (lower.endsWith('.jsonl')) return _readJsonLines(File(source.path));
    if (lower.endsWith('.json')) {
      final raw = await File(source.path)
          .readAsString(encoding: const Utf8Codec(allowMalformed: true));
      try {
        return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
      } catch (_) {
        return raw;
      }
    }
    if (_structuredDocumentExtensions.any(lower.endsWith) ||
        lower.endsWith('.pdf') ||
        lower.endsWith('.doc') ||
        lower.endsWith('.xls') ||
        lower.endsWith('.ppt')) {
      return textExtractor(source.path, 8 * 1024 * 1024);
    }
    return File(source.path)
        .readAsString(encoding: const Utf8Codec(allowMalformed: true));
  }

  Future<String> _readJsonLines(File file) async {
    final buffer = StringBuffer();
    var lineNumber = 0;
    await for (final line in file
        .openRead()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())) {
      lineNumber++;
      if (line.trim().isEmpty) continue;
      buffer.write('LINE $lineNumber: ');
      try {
        final decoded = jsonDecode(line);
        buffer.writeln(jsonEncode(decoded));
      } catch (_) {
        buffer.writeln(line);
      }
    }
    return buffer.toString();
  }

  List<ContextArchiveChunk> _createChunks(_ContextSource source, String text) {
    const chunkSize = 6000;
    const overlap = 600;
    final normalized = text.replaceAll('\u0000', '').trim();
    if (normalized.isEmpty) return const [];
    final result = <ContextArchiveChunk>[];
    var start = 0;
    var index = 0;
    while (start < normalized.length) {
      var end = (start + chunkSize).clamp(start, normalized.length).toInt();
      if (end < normalized.length) {
        final newline = normalized.lastIndexOf('\n', end);
        if (newline > start + chunkSize ~/ 2) end = newline + 1;
      }
      final chunkText = normalized.substring(start, end).trim();
      if (chunkText.isNotEmpty) {
        result.add(ContextArchiveChunk(
          id: '${source.sourceId}:$index',
          sourceId: source.sourceId,
          sourcePath: source.path,
          sourceSignature: source.signature,
          corpus: source.corpus,
          projectPath: source.projectPath,
          projectName: source.projectName,
          title: source.title,
          chunkIndex: index,
          text: chunkText,
          updatedAt: source.updatedAt,
        ));
        index++;
      }
      if (end >= normalized.length) break;
      start = (end - overlap).clamp(start + 1, end).toInt();
    }
    return result;
  }

  String _combineChunks(List<ContextArchiveChunk> chunks) {
    if (chunks.isEmpty) return '';
    const overlap = 600;
    final buffer = StringBuffer(chunks.first.text);
    for (final chunk in chunks.skip(1)) {
      final previous = buffer.toString();
      final maxOverlap = overlap.clamp(0, chunk.text.length).toInt();
      var matched = 0;
      for (var size = maxOverlap; size >= 40; size--) {
        if (previous.endsWith(chunk.text.substring(0, size))) {
          matched = size;
          break;
        }
      }
      if (matched == 0) buffer.writeln();
      buffer.write(chunk.text.substring(matched));
    }
    return buffer.toString();
  }

  Future<List<ContextArchiveChunk>> _readIndex() async {
    if (!await indexFile.exists()) return const [];
    final result = <ContextArchiveChunk>[];
    await for (final line in indexFile
        .openRead()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) {
          final chunk = ContextArchiveChunk.fromJson(
              decoded.map((key, value) => MapEntry(key.toString(), value)));
          if (chunk.id.isNotEmpty && chunk.sourcePath.isNotEmpty)
            result.add(chunk);
        }
      } catch (_) {}
    }
    return result;
  }

  Future<void> _writeIndex(List<ContextArchiveChunk> chunks) async {
    await indexRoot.create(recursive: true);
    final temporary = File('${indexFile.path}.tmp');
    final sink = temporary.openWrite(encoding: utf8);
    for (final chunk in chunks) {
      sink.writeln(jsonEncode(chunk.toJson()));
    }
    await sink.flush();
    await sink.close();
    if (await indexFile.exists()) await indexFile.delete();
    await temporary.rename(indexFile.path);
  }

  static const _structuredDocumentExtensions = <String>[
    '.rtf',
    '.docx',
    '.xlsx',
    '.pptx',
    '.vsdx',
    '.odt',
    '.ods',
    '.odp',
    '.odc',
  ];

  static const _literatureExtensions = <String>[
    '.txt',
    '.md',
    '.rst',
    '.adoc',
    '.json',
    '.jsonl',
    '.yaml',
    '.yml',
    '.toml',
    '.ini',
    '.cfg',
    '.csv',
    '.tsv',
    '.html',
    '.htm',
    '.xml',
    '.pdf',
    '.rtf',
    '.doc',
    '.docx',
    '.xls',
    '.xlsx',
    '.ppt',
    '.pptx',
    '.vsdx',
    '.odt',
    '.ods',
    '.odp',
    '.odc',
    '.dart',
    '.py',
    '.js',
    '.ts',
    '.jsx',
    '.tsx',
    '.c',
    '.cc',
    '.cpp',
    '.cxx',
    '.h',
    '.hpp',
    '.rs',
    '.go',
    '.java',
    '.kt',
    '.kts',
    '.cs',
    '.swift',
    '.rb',
    '.php',
    '.sql',
    '.sh',
    '.ps1',
    '.bat',
    '.cmd',
  ];
}

class _ContextSource {
  const _ContextSource({
    required this.path,
    required this.sourceId,
    required this.signature,
    required this.corpus,
    required this.projectPath,
    required this.projectName,
    required this.title,
    required this.updatedAt,
  });

  final String path;
  final String sourceId;
  final String signature;
  final ContextArchiveCorpus corpus;
  final String projectPath;
  final String projectName;
  final String title;
  final DateTime updatedAt;
}
