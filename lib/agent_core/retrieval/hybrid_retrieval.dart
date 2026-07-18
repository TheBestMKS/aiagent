import 'dart:math' as math;

class HybridDocument {
  const HybridDocument({
    required this.id,
    required this.title,
    required this.text,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String title;
  final String text;
  final Map<String, Object?> metadata;
}

class HybridSearchResult {
  const HybridSearchResult({required this.document, required this.score});

  final HybridDocument document;
  final double score;
}

class HybridRetrievalEngine {
  const HybridRetrievalEngine();

  List<HybridSearchResult> search(
    String query,
    List<HybridDocument> documents, {
    int maxResults = 8,
  }) {
    final queryTerms = _tokenize(query);
    if (queryTerms.isEmpty || documents.isEmpty) return const [];

    final tokenized = <String, List<String>>{};
    var totalLength = 0;
    final documentFrequency = <String, int>{};
    for (final document in documents) {
      final terms = _tokenize('${document.title} ${document.text}');
      tokenized[document.id] = terms;
      totalLength += terms.length;
      for (final term in terms.toSet()) {
        documentFrequency[term] = (documentFrequency[term] ?? 0) + 1;
      }
    }

    final averageLength = math.max(1.0, totalLength / documents.length);
    final normalizedQuery = _normalize(query);
    final queryTrigrams = _trigrams(normalizedQuery);
    final results = <HybridSearchResult>[];

    for (final document in documents) {
      final terms = tokenized[document.id] ?? const <String>[];
      if (terms.isEmpty) continue;
      final frequencies = <String, int>{};
      for (final term in terms) {
        frequencies[term] = (frequencies[term] ?? 0) + 1;
      }

      var bm25 = 0.0;
      for (final queryTerm in queryTerms.toSet()) {
        final tf = frequencies[queryTerm] ?? 0;
        if (tf == 0) continue;
        final df = documentFrequency[queryTerm] ?? 0;
        final idf = math.log(1 + (documents.length - df + 0.5) / (df + 0.5));
        const k1 = 1.35;
        const b = 0.72;
        final lengthFactor = 1 - b + b * terms.length / averageLength;
        bm25 += idf * (tf * (k1 + 1)) / (tf + k1 * lengthFactor);
      }

      final normalizedDocument = _normalize('${document.title} ${document.text}');
      final exactPhrase = normalizedDocument.contains(normalizedQuery) ? 5.0 : 0.0;
      final titleBoost = _normalize(document.title).contains(normalizedQuery) ? 3.0 : 0.0;
      final trigramScore = _jaccard(queryTrigrams, _trigrams(normalizedDocument));
      final coverage = queryTerms
              .where((term) => frequencies.containsKey(term))
              .toSet()
              .length /
          queryTerms.toSet().length;
      final score = bm25 + exactPhrase + titleBoost + trigramScore * 3.0 + coverage * 2.0;
      if (score > 0.05) results.add(HybridSearchResult(document: document, score: score));
    }

    results.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.document.title.compareTo(b.document.title);
    });
    return results.take(math.max(1, maxResults)).toList(growable: false);
  }

  List<String> _tokenize(String text) => _normalize(text)
      .split(RegExp(r'[^a-z0-9а-яё_+-]+', caseSensitive: false))
      .where((term) => term.length > 1)
      .toList(growable: false);

  String _normalize(String text) =>
      text.toLowerCase().replaceAll('ё', 'е').replaceAll(RegExp(r'\s+'), ' ').trim();

  Set<String> _trigrams(String text) {
    final compact = text.replaceAll(' ', '_');
    if (compact.length < 3) return compact.isEmpty ? <String>{} : {compact};
    final result = <String>{};
    for (var i = 0; i <= compact.length - 3; i++) {
      result.add(compact.substring(i, i + 3));
      if (result.length >= 1200) break;
    }
    return result;
  }

  double _jaccard(Set<String> left, Set<String> right) {
    if (left.isEmpty || right.isEmpty) return 0;
    var intersection = 0;
    for (final value in left) {
      if (right.contains(value)) intersection++;
    }
    final union = left.length + right.length - intersection;
    return union == 0 ? 0 : intersection / union;
  }
}
