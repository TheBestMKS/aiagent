import 'dart:convert';

class ToolGuardDecision {
  const ToolGuardDecision.allow()
      : allowed = true,
        message = '';

  const ToolGuardDecision.block(this.message) : allowed = false;

  final bool allowed;
  final String message;
}

class ToolExecutionGuard {
  ToolExecutionGuard({
    this.maxIdenticalCallsWithoutProgress = 3,
    this.maxFailuresPerSignature = 3,
    this.maxCallsWithoutGlobalProgress = 12,
  });

  final int maxIdenticalCallsWithoutProgress;
  final int maxFailuresPerSignature;
  final int maxCallsWithoutGlobalProgress;
  final Map<String, int> _callCounts = {};
  final Map<String, int> _failureCounts = {};
  final Map<String, int> _lastProgressRevision = {};
  final Map<String, String> _lastResultFingerprints = {};
  final List<String> _recentSignatures = [];
  int blockedCalls = 0;
  int _callsWithoutGlobalProgress = 0;
  int _lastGlobalProgressRevision = 0;

  void reset() {
    _callCounts.clear();
    _failureCounts.clear();
    _lastProgressRevision.clear();
    _lastResultFingerprints.clear();
    _recentSignatures.clear();
    blockedCalls = 0;
    _callsWithoutGlobalProgress = 0;
    _lastGlobalProgressRevision = 0;
  }

  void restore(Map<String, dynamic> json) {
    reset();
    _restoreIntMap(_callCounts, json['callCounts']);
    _restoreIntMap(_failureCounts, json['failureCounts']);
    _restoreIntMap(_lastProgressRevision, json['lastProgressRevision']);
    final fingerprints = json['lastResultFingerprints'];
    if (fingerprints is Map) {
      for (final entry in fingerprints.entries.take(300)) {
        _lastResultFingerprints[entry.key.toString()] =
            entry.value?.toString() ?? '';
      }
    }
    final recent = json['recentSignatures'];
    if (recent is List) {
      _recentSignatures.addAll(
        recent.map((item) => item.toString()).take(20),
      );
    }
    blockedCalls = _asInt(json['blockedCalls']).clamp(0, 100000).toInt();
    _callsWithoutGlobalProgress =
        _asInt(json['callsWithoutGlobalProgress']).clamp(0, 100000).toInt();
    _lastGlobalProgressRevision =
        _asInt(json['lastGlobalProgressRevision']).clamp(0, 100000).toInt();
  }

  Map<String, dynamic> snapshot() => {
        'schemaVersion': 1,
        'callCounts': _boundedMap(_callCounts),
        'failureCounts': _boundedMap(_failureCounts),
        'lastProgressRevision': _boundedMap(_lastProgressRevision),
        'lastResultFingerprints': _boundedMap(_lastResultFingerprints),
        'recentSignatures': _recentSignatures.take(20).toList(growable: false),
        'blockedCalls': blockedCalls,
        'callsWithoutGlobalProgress': _callsWithoutGlobalProgress,
        'lastGlobalProgressRevision': _lastGlobalProgressRevision,
      };

  ToolGuardDecision evaluate({
    required String toolName,
    required Map<String, dynamic> args,
    required int progressRevision,
  }) {
    if (_callsWithoutGlobalProgress >= maxCallsWithoutGlobalProgress &&
        progressRevision <= _lastGlobalProgressRevision) {
      blockedCalls++;
      return ToolGuardDecision.block(
        'TOOL_GLOBAL_STALL: выполнено $_callsWithoutGlobalProgress действий '
        'без измеримого прогресса. Останови перебор инструментов, '
        'проанализируй последнюю ошибку и выбери проверяемую новую стратегию. '
        'Повторный get_task_status не считается прогрессом.',
      );
    }
    final signature = signatureFor(toolName, args);
    final failures = _failureCounts[signature] ?? 0;
    if (failures >= maxFailuresPerSignature) {
      blockedCalls++;
      return ToolGuardDecision.block(
        'TOOL_CIRCUIT_BREAKER: действие "$toolName" уже завершилось ошибкой '
        '$failures раз(а) с теми же аргументами. Измени подход, аргументы или '
        'используй другой инструмент вместо слепого повтора.',
      );
    }

    final count = _callCounts[signature] ?? 0;
    final lastRevision = _lastProgressRevision[signature];
    if (count >= maxIdenticalCallsWithoutProgress &&
        lastRevision == progressRevision) {
      blockedCalls++;
      return ToolGuardDecision.block(
        'TOOL_CIRCUIT_BREAKER: одинаковый вызов "$toolName" повторён '
        '$count раз(а) без изменения состояния задачи. Проанализируй последний '
        'результат, обнови план и выбери иное действие.',
      );
    }
    return const ToolGuardDecision.allow();
  }

  void recordBlockedAttempt({required int progressRevision}) {
    if (progressRevision > _lastGlobalProgressRevision) {
      _lastGlobalProgressRevision = progressRevision;
      _callsWithoutGlobalProgress = 1;
    } else {
      _callsWithoutGlobalProgress++;
    }
  }

  bool isNovelResult({
    required String toolName,
    required Map<String, dynamic> args,
    required String result,
  }) {
    final signature = signatureFor(toolName, args);
    final previous = _lastResultFingerprints[signature];
    return previous == null || previous != _resultFingerprint(result);
  }

  void record({
    required String toolName,
    required Map<String, dynamic> args,
    required String result,
    required int progressRevision,
    required bool successful,
  }) {
    final signature = signatureFor(toolName, args);
    final fingerprint = _resultFingerprint(result);
    final previousFingerprint = _lastResultFingerprints[signature];
    final resultChanged = previousFingerprint != null &&
        previousFingerprint.isNotEmpty &&
        previousFingerprint != fingerprint;

    if (progressRevision > _lastGlobalProgressRevision) {
      _lastGlobalProgressRevision = progressRevision;
      _callsWithoutGlobalProgress = 0;
    } else {
      _callsWithoutGlobalProgress++;
    }

    _callCounts[signature] = (_callCounts[signature] ?? 0) + 1;
    _failureCounts[signature] =
        successful ? 0 : (_failureCounts[signature] ?? 0) + 1;
    _lastProgressRevision[signature] =
        resultChanged ? progressRevision + 1 : progressRevision;
    _lastResultFingerprints[signature] = fingerprint;
    _recentSignatures.add(signature);
    if (_recentSignatures.length > 20) _recentSignatures.removeAt(0);
    _pruneMaps(maxItems: 300);
  }

  String statusSummary() {
    final failed = _failureCounts.values.where((value) => value > 0).length;
    return 'TOOL_GUARD: signatures=${_callCounts.length}; '
        'failed_signatures=$failed; blocked=$blockedCalls; '
        'calls_without_progress=$_callsWithoutGlobalProgress';
  }

  String signatureFor(String toolName, Map<String, dynamic> args) {
    final canonical = jsonEncode(_canonicalize(args));
    return '${_safeToolName(toolName)}:${_hashText(canonical)}';
  }

  Object? _canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is List) return value.map(_canonicalize).toList(growable: false);
    return value;
  }

  String _safeToolName(String value) {
    final safe = value.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]+'), '_');
    return safe.substring(0, safe.length.clamp(0, 80).toInt());
  }

  String _resultFingerprint(String result) {
    final normalized = result
        .replaceAll(RegExp(r'\d{4}-\d{2}-\d{2}T\S+'), '<time>')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return _hashText(normalized.length > 12000
        ? normalized.substring(0, 12000)
        : normalized);
  }

  String _hashText(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  void _restoreIntMap(Map<String, int> target, Object? raw) {
    if (raw is! Map) return;
    for (final entry in raw.entries.take(300)) {
      target[entry.key.toString()] =
          _asInt(entry.value).clamp(0, 100000).toInt();
    }
  }

  Map<String, Object?> _boundedMap<T>(Map<String, T> source) {
    final entries = source.entries.toList(growable: false);
    final start = entries.length > 300 ? entries.length - 300 : 0;
    return <String, Object?>{
      for (final entry in entries.skip(start)) entry.key: entry.value,
    };
  }

  void _pruneMaps({required int maxItems}) {
    if (_callCounts.length <= maxItems) return;
    final keep = _recentSignatures.reversed.toSet();
    for (final key in _callCounts.keys.toList(growable: false)) {
      if (_callCounts.length <= maxItems) break;
      if (keep.contains(key)) continue;
      _callCounts.remove(key);
      _failureCounts.remove(key);
      _lastProgressRevision.remove(key);
      _lastResultFingerprints.remove(key);
    }
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
