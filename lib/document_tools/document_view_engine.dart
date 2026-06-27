import 'dart:math' as math;

import 'document_models.dart';
import 'document_parsers.dart';
import 'document_utils.dart';

class DocumentViewBlock {
  const DocumentViewBlock({
    required this.kind,
    required this.text,
    this.level = 0,
  });

  final String kind;
  final String text;
  final int level;
}

class DocumentViewModel {
  const DocumentViewModel({
    required this.path,
    required this.kind,
    required this.title,
    required this.blocks,
    required this.structure,
  });

  final String path;
  final OfficeDocumentKind kind;
  final String title;
  final List<DocumentViewBlock> blocks;
  final String structure;
}

class OfficeDocumentViewEngine {
  const OfficeDocumentViewEngine({this.parser = const OfficeDocumentParser()});

  final OfficeDocumentParser parser;

  Future<DocumentViewModel> load(String path) async {
    final parsed = await parser.parseFile(path);
    return fromParseResult(parsed);
  }

  DocumentViewModel fromParseResult(DocumentParseResult parsed) {
    final paragraphs = splitParagraphs(parsed.text);
    final blocks = <DocumentViewBlock>[];
    for (final paragraph in paragraphs) {
      final trimmed = paragraph.trim();
      if (trimmed.isEmpty) continue;
      final heading = _headingLevel(trimmed);
      blocks.add(DocumentViewBlock(
        kind: heading > 0 ? 'heading' : 'paragraph',
        level: heading,
        text: trimmed,
      ));
    }
    if (blocks.isEmpty && parsed.text.trim().isNotEmpty) {
      blocks
          .add(DocumentViewBlock(kind: 'paragraph', text: parsed.text.trim()));
    }
    return DocumentViewModel(
      path: parsed.path,
      kind: parsed.kind,
      title: _titleFrom(parsed),
      blocks: blocks,
      structure: parsed.structure,
    );
  }

  int _headingLevel(String text) {
    if (text.length > 120) return 0;
    if (text.startsWith('#')) {
      final firstTextIndex = text.indexOf(RegExp(r'[^#]'));
      return math.min(firstTextIndex < 0 ? 1 : firstTextIndex, 6).toInt();
    }
    if (RegExp(r'^[0-9]+(\.[0-9]+)*\s+\S').hasMatch(text)) return 2;
    if (text == text.toUpperCase() && text.length > 4) return 2;
    return 0;
  }

  String _titleFrom(DocumentParseResult parsed) {
    final first = parsed.text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .cast<String?>()
        .firstWhere((line) => line != null, orElse: () => null);
    if (first != null && first.length <= 120) return first;
    return '${parsed.kind.label} document';
  }
}
