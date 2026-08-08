import 'dart:convert';
import 'dart:io';

import '../../utils/path_utils.dart';
import '../retrieval/hybrid_retrieval.dart';
import '../security/secret_redactor.dart';

enum AgentMemoryType {
  instruction,
  fact,
  decision,
  goal,
  commitment,
  preference,
  relationship,
  context,
  event,
  learning,
  observation,
  artifact,
  procedure,
}

enum AgentMemorySearchScope {
  currentAndGlobal,
  currentProject,
  otherProjects,
  allProjects,
  globalOnly,
}

extension AgentMemorySearchScopeParsing on AgentMemorySearchScope {
  static AgentMemorySearchScope parse(String value) =>
      switch (value.trim().toLowerCase()) {
        'current' || 'current_project' => AgentMemorySearchScope.currentProject,
        'other' || 'other_projects' => AgentMemorySearchScope.otherProjects,
        'all' || 'all_projects' => AgentMemorySearchScope.allProjects,
        'global' || 'global_only' => AgentMemorySearchScope.globalOnly,
        _ => AgentMemorySearchScope.currentAndGlobal,
      };
}

class AgentMemoryRecord {
  const AgentMemoryRecord({
    required this.id,
    required this.key,
    required this.type,
    required this.title,
    required this.content,
    required this.scope,
    required this.projectPath,
    required this.source,
    required this.provenance,
    required this.confidence,
    required this.verified,
    required this.verification,
    required this.failedApproaches,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
    required this.supersedesId,
    required this.conflictGroup,
    required this.deleted,
  });

  final String id;
  final String key;
  final AgentMemoryType type;
  final String title;
  final String content;
  final String scope;
  final String projectPath;
  final String source;
  final String provenance;
  final double confidence;
  final bool verified;
  final String verification;
  final List<String> failedApproaches;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String supersedesId;
  final String conflictGroup;
  final bool deleted;

  Map<String, dynamic> toJson() => {
        'id': id,
        'key': key,
        'type': type.name,
        'title': title,
        'content': content,
        'scope': scope,
        'projectPath': projectPath,
        'source': source,
        'provenance': provenance,
        'confidence': confidence,
        'verified': verified,
        'verification': verification,
        'failedApproaches': failedApproaches,
        'tags': tags,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'supersedesId': supersedesId,
        'conflictGroup': conflictGroup,
        'deleted': deleted,
      };

  factory AgentMemoryRecord.fromJson(Map<String, dynamic> json) {
    final typeName = json['type']?.toString() ?? AgentMemoryType.context.name;
    return AgentMemoryRecord(
      id: json['id']?.toString() ?? '',
      key: json['key']?.toString() ?? '',
      type: AgentMemoryType.values.firstWhere(
        (value) => value.name == typeName,
        orElse: () => AgentMemoryType.context,
      ),
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      scope: json['scope']?.toString() ?? 'global',
      projectPath: json['projectPath']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      provenance: json['provenance']?.toString() ?? 'agent',
      confidence: (json['confidence'] is num
              ? (json['confidence'] as num).toDouble()
              : double.tryParse(json['confidence']?.toString() ?? '') ?? 0.5)
          .clamp(0.0, 1.0)
          .toDouble(),
      verified: json['verified'] == true,
      verification: json['verification']?.toString() ?? '',
      failedApproaches: (json['failedApproaches'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false),
      tags: (json['tags'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
      supersedesId: json['supersedesId']?.toString() ?? '',
      conflictGroup: json['conflictGroup']?.toString() ?? '',
      deleted: json['deleted'] == true,
    );
  }
}

class LocalMemoryService {
  LocalMemoryService({required this.configRoot});

  final Directory configRoot;
  final HybridRetrievalEngine _retrieval = const HybridRetrievalEngine();
  Future<void> _pendingMutation = Future<void>.value();

  Directory get memoryRoot => Directory(pathJoin(configRoot.path, 'memory'));
  File get ledgerFile => File(pathJoin(memoryRoot.path, 'records.jsonl'));
  File get migrationMarker =>
      File(pathJoin(memoryRoot.path, '.legacy_migrated'));

  Future<void> initialize() async {
    await memoryRoot.create(recursive: true);
    if (!await ledgerFile.exists())
      await ledgerFile.writeAsString('', encoding: utf8);
  }

  Future<AgentMemoryRecord> remember({
    required AgentMemoryType type,
    required String title,
    required String content,
    String key = '',
    String scope = 'global',
    String projectPath = '',
    String source = '',
    String provenance = 'agent',
    double confidence = 0.65,
    bool verified = false,
    String verification = '',
    List<String> failedApproaches = const [],
    List<String> tags = const [],
  }) {
    final operation = _pendingMutation.then(
      (_) => _rememberInternal(
        type: type,
        title: title,
        content: content,
        key: key,
        scope: scope,
        projectPath: projectPath,
        source: source,
        provenance: provenance,
        confidence: confidence,
        verified: verified,
        verification: verification,
        failedApproaches: failedApproaches,
        tags: tags,
      ),
    );
    _pendingMutation = operation.then<void>((_) {}).catchError((Object _) {});
    return operation;
  }

  Future<AgentMemoryRecord> _rememberInternal({
    required AgentMemoryType type,
    required String title,
    required String content,
    String key = '',
    String scope = 'global',
    String projectPath = '',
    String source = '',
    String provenance = 'agent',
    double confidence = 0.65,
    bool verified = false,
    String verification = '',
    List<String> failedApproaches = const [],
    List<String> tags = const [],
  }) async {
    await initialize();
    final now = DateTime.now();
    final normalizedKey = _normalizeKey(key.isEmpty ? title : key);
    final active = await readActiveRecords();
    AgentMemoryRecord? previous;
    for (final item in active.reversed) {
      if (item.key == normalizedKey &&
          item.scope == scope &&
          item.projectPath == projectPath) {
        previous = item;
        break;
      }
    }
    final differs = previous != null &&
        _normalizeText(previous.content) != _normalizeText(content);
    final conflictGroup = differs
        ? (previous.conflictGroup.isNotEmpty
            ? previous.conflictGroup
            : 'conflict_${now.microsecondsSinceEpoch}')
        : (previous?.conflictGroup ?? '');
    final record = AgentMemoryRecord(
      id: 'mem_${now.microsecondsSinceEpoch}',
      key: normalizedKey,
      type: type,
      title: SecretRedactor.redact(title.trim()),
      content: SecretRedactor.redact(content.trim()),
      scope: scope.trim().isEmpty ? 'global' : scope.trim(),
      projectPath: projectPath.trim(),
      source: SecretRedactor.redact(source.trim()),
      provenance: provenance.trim().isEmpty ? 'agent' : provenance.trim(),
      confidence: confidence.clamp(0.0, 1.0).toDouble(),
      verified: verified,
      verification: SecretRedactor.redact(verification.trim()),
      failedApproaches: failedApproaches
          .map((item) => SecretRedactor.redact(item.trim()))
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(growable: false),
      tags: tags
          .map((item) => item.trim().toLowerCase())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(growable: false),
      createdAt: previous?.createdAt ?? now,
      updatedAt: now,
      supersedesId: previous?.id ?? '',
      conflictGroup: conflictGroup,
      deleted: false,
    );
    await _append(record);
    return record;
  }

  Future<AgentMemoryRecord> promoteGoldenPath({
    required String problem,
    required String solution,
    required String verification,
    required List<String> failedApproaches,
    String projectPath = '',
    List<String> tags = const [],
  }) async {
    if (verification.trim().isEmpty) {
      throw StateError('A passing verification is required before promotion');
    }
    final failures = failedApproaches
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (failures.isEmpty) {
      throw StateError(
          'At least one ruled-out approach is required before promotion');
    }
    return remember(
      type: AgentMemoryType.procedure,
      key: 'golden_path:${_normalizeKey(problem)}',
      title: problem,
      content: solution,
      scope: projectPath.isEmpty ? 'global' : 'project',
      projectPath: projectPath,
      provenance: 'verified-agent-run',
      confidence: 0.95,
      verified: true,
      verification: verification,
      failedApproaches: failures,
      tags: {'golden-path', 'procedure', ...tags}.toList(),
    );
  }

  Future<List<AgentMemoryRecord>> readActiveRecords() async {
    await initialize();
    final latestById = <String, AgentMemoryRecord>{};
    for (final line in await ledgerFile.readAsLines(encoding: utf8)) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map) continue;
        final record = AgentMemoryRecord.fromJson(
            decoded.map((key, value) => MapEntry(key.toString(), value)));
        if (record.id.isNotEmpty) latestById[record.id] = record;
      } catch (_) {}
    }
    final superseded = latestById.values
        .map((record) => record.supersedesId)
        .where((id) => id.isNotEmpty)
        .toSet();
    final active = latestById.values
        .where((record) => !record.deleted && !superseded.contains(record.id))
        .toList();
    active.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return active;
  }

  Future<List<AgentMemoryRecord>> search(
    String query, {
    int maxResults = 8,
    String projectPath = '',
    Set<AgentMemoryType>? types,
    AgentMemorySearchScope scope = AgentMemorySearchScope.currentAndGlobal,
  }) async {
    final records = (await readActiveRecords()).where((record) {
      if (types != null && !types.contains(record.type)) return false;
      final sameProject = projectPath.isNotEmpty &&
          normalizePathForCompare(record.projectPath) ==
              normalizePathForCompare(projectPath);
      final hasProject = record.projectPath.trim().isNotEmpty;
      return switch (scope) {
        AgentMemorySearchScope.currentAndGlobal =>
          projectPath.isEmpty || !hasProject || sameProject,
        AgentMemorySearchScope.currentProject => sameProject,
        AgentMemorySearchScope.otherProjects => hasProject && !sameProject,
        AgentMemorySearchScope.allProjects => true,
        AgentMemorySearchScope.globalOnly => !hasProject,
      };
    }).toList(growable: false);
    final documents = records
        .map((record) => HybridDocument(
              id: record.id,
              title: record.title,
              text:
                  '${record.content}\n${record.type.name}\n${record.tags.join(' ')}\n${record.source}\n${record.verification}\n${record.failedApproaches.join(' ')}',
              metadata: {'record': record},
            ))
        .toList(growable: false);
    final semanticResults = _retrieval.search(
      query,
      documents,
      maxResults: (maxResults * 4).clamp(8, 100).toInt(),
    );
    final now = DateTime.now();
    final ranked = semanticResults.map((result) {
      final record = result.document.metadata['record'] as AgentMemoryRecord;
      final ageDays = now.difference(record.updatedAt).inHours / 24.0;
      final recency = 1.0 / (1.0 + ageDays.clamp(0.0, 3650.0) / 45.0);
      final verificationBonus = record.verified ? 0.9 : 0.0;
      final confidenceBonus = record.confidence * 0.7;
      final projectBonus =
          projectPath.isNotEmpty && record.projectPath == projectPath
              ? 0.45
              : 0.0;
      final temporalWeight = switch (record.type) {
        AgentMemoryType.preference ||
        AgentMemoryType.goal ||
        AgentMemoryType.commitment ||
        AgentMemoryType.event =>
          0.8,
        _ => 0.35,
      };
      return MapEntry(
        result.score +
            verificationBonus +
            confidenceBonus +
            projectBonus +
            recency * temporalWeight,
        record,
      );
    }).toList(growable: false)
      ..sort((left, right) => right.key.compareTo(left.key));
    return ranked
        .take(maxResults.clamp(1, 100).toInt())
        .map((entry) => entry.value)
        .toList(growable: false);
  }

  Future<List<List<AgentMemoryRecord>>> conflicts() async {
    final groups = <String, List<AgentMemoryRecord>>{};
    for (final record in await _readAllRecords()) {
      if (record.deleted) continue;
      final groupKey = '${record.scope}|${record.projectPath}|${record.key}';
      groups.putIfAbsent(groupKey, () => []).add(record);
    }
    final conflicts = <List<AgentMemoryRecord>>[];
    for (final group in groups.values) {
      final distinct = group
          .map((record) => _normalizeText(record.content))
          .where((value) => value.isNotEmpty)
          .toSet();
      if (group.length > 1 && distinct.length > 1) {
        group.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
        conflicts.add(group);
      }
    }
    return conflicts;
  }

  Future<String> formatSearchResults(
    String query, {
    int maxResults = 8,
    String projectPath = '',
    AgentMemorySearchScope scope = AgentMemorySearchScope.currentAndGlobal,
  }) async {
    final results = await search(query,
        maxResults: maxResults, projectPath: projectPath, scope: scope);
    if (results.isEmpty) return 'MEMORY_NO_RESULTS: $query';
    final buffer =
        StringBuffer('MEMORY_RESULTS for "$query"; scope=${scope.name}\n');
    for (final record in results) {
      buffer.writeln(
          '\n--- ${record.type.name.toUpperCase()}: ${record.title} ---');
      buffer.writeln('ID: ${record.id}');
      buffer.writeln(
          'SCOPE: ${record.scope}${record.projectPath.isEmpty ? '' : ' • ${record.projectPath}'}');
      buffer.writeln(
          'PROVENANCE: ${record.provenance}; CONFIDENCE: ${(record.confidence * 100).round()}%; VERIFIED: ${record.verified}');
      if (record.source.isNotEmpty) buffer.writeln('SOURCE: ${record.source}');
      if (record.verification.isNotEmpty)
        buffer.writeln('VERIFICATION: ${record.verification}');
      if (record.failedApproaches.isNotEmpty) {
        buffer.writeln('RULED_OUT: ${record.failedApproaches.join(' | ')}');
      }
      if (record.tags.isNotEmpty)
        buffer.writeln('TAGS: ${record.tags.join(', ')}');
      buffer.writeln(record.content);
    }
    return buffer.toString().trimRight();
  }

  Future<String> formatConflicts() async {
    final found = await conflicts();
    if (found.isEmpty) return 'MEMORY_CONFLICTS_NONE';
    final buffer = StringBuffer('MEMORY_CONFLICTS: ${found.length}\n');
    for (final group in found) {
      buffer.writeln(
          '\n=== ${group.first.conflictGroup.isEmpty ? group.first.key : group.first.conflictGroup}: ${group.first.key} ===');
      for (final record in group) {
        buffer.writeln(
            '- ${record.updatedAt.toIso8601String()} [${record.provenance}; ${(record.confidence * 100).round()}%] ${record.content}');
      }
    }
    return buffer.toString().trimRight();
  }

  Future<void> migrateLegacy({
    required File knowledgeBase,
    required File solutionMemory,
  }) async {
    await initialize();
    if (await migrationMarker.exists()) return;
    if (await knowledgeBase.exists()) {
      for (final line in await knowledgeBase.readAsLines(encoding: utf8)) {
        try {
          final decoded = jsonDecode(line);
          if (decoded is! Map) continue;
          final data =
              decoded.map((key, value) => MapEntry(key.toString(), value));
          final title = data['topic']?.toString() ?? '';
          final content = data['content']?.toString() ?? '';
          if (title.trim().isEmpty || content.trim().isEmpty) continue;
          await remember(
            type: AgentMemoryType.fact,
            title: title,
            content: content,
            source: data['source']?.toString() ?? '',
            provenance: 'legacy-knowledge-base',
            confidence: 0.6,
            tags: _splitTags(data['tags']?.toString() ?? ''),
          );
        } catch (_) {}
      }
    }
    if (await solutionMemory.exists()) {
      for (final line in await solutionMemory.readAsLines(encoding: utf8)) {
        try {
          final decoded = jsonDecode(line);
          if (decoded is! Map) continue;
          final data =
              decoded.map((key, value) => MapEntry(key.toString(), value));
          final problem = data['problem']?.toString() ?? '';
          final solution = data['solution']?.toString() ?? '';
          if (problem.trim().isEmpty || solution.trim().isEmpty) continue;
          await remember(
            type: AgentMemoryType.learning,
            title: problem,
            content: solution,
            projectPath: data['project']?.toString() ?? '',
            provenance: 'legacy-solution-memory',
            confidence: 0.65,
            tags: _splitTags(data['tags']?.toString() ?? ''),
          );
        } catch (_) {}
      }
    }
    await migrationMarker.writeAsString(DateTime.now().toIso8601String(),
        encoding: utf8);
  }

  Future<List<AgentMemoryRecord>> _readAllRecords() async {
    await initialize();
    final records = <AgentMemoryRecord>[];
    for (final line in await ledgerFile.readAsLines(encoding: utf8)) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) {
          records.add(AgentMemoryRecord.fromJson(
              decoded.map((key, value) => MapEntry(key.toString(), value))));
        }
      } catch (_) {}
    }
    return records;
  }

  Future<void> _append(AgentMemoryRecord record) async {
    await ledgerFile.writeAsString(
      '${jsonEncode(record.toJson())}\n',
      mode: FileMode.append,
      encoding: utf8,
    );
  }

  List<String> _splitTags(String value) => value
      .split(RegExp(r'[,;]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);

  String _normalizeKey(String value) => _normalizeText(value)
      .replaceAll(RegExp(r'[^a-z0-9а-яё]+', caseSensitive: false), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  String _normalizeText(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
