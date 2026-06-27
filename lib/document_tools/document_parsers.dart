import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'document_models.dart';
import 'document_utils.dart';

class OfficeDocumentParser {
  const OfficeDocumentParser();

  Future<DocumentParseResult> parseFile(String path,
      {int maxBytes = 80 * 1024 * 1024}) async {
    final file = File(path);
    if (!await file.exists()) {
      return DocumentParseResult(
          path: path,
          kind: OfficeDocumentKind.unknown,
          text: '',
          structure: 'File not found');
    }
    final length = await file.length();
    if (length > maxBytes) {
      return DocumentParseResult(
          path: path,
          kind: detectOfficeDocumentKind(path),
          text: '',
          structure: 'File is too large: $length bytes');
    }
    final bytes = await file.readAsBytes();
    return parseBytes(path, bytes);
  }

  DocumentParseResult parseBytes(String path, List<int> bytes) {
    final kind = detectOfficeDocumentKind(path);
    try {
      return switch (kind) {
        OfficeDocumentKind.rtf => _parseRtf(path, bytes),
        OfficeDocumentKind.docx => _parseDocx(path, bytes),
        OfficeDocumentKind.xlsx => _parseXlsx(path, bytes),
        OfficeDocumentKind.pptx => _parsePptx(path, bytes),
        OfficeDocumentKind.odt ||
        OfficeDocumentKind.ods ||
        OfficeDocumentKind.odp ||
        OfficeDocumentKind.odc =>
          _parseOpenDocument(path, bytes, kind),
        OfficeDocumentKind.plainText => _parsePlain(path, bytes),
        OfficeDocumentKind.unknown =>
          _parsePlain(path, bytes, forcedKind: OfficeDocumentKind.unknown),
      };
    } catch (error) {
      final text = _decodeBytesBestEffort(bytes);
      return DocumentParseResult(
        path: path,
        kind: kind,
        text: text,
        structure: 'Parse error for ${kind.label}: $error',
      );
    }
  }

  DocumentParseResult _parsePlain(String path, List<int> bytes,
      {OfficeDocumentKind forcedKind = OfficeDocumentKind.plainText}) {
    final text = _decodeBytesBestEffort(bytes);
    return DocumentParseResult(
      path: path,
      kind: forcedKind,
      text: text,
      structure:
          'Plain text, ${text.split(RegExp(r'\r?\n')).length} lines, ${text.length} chars',
    );
  }

  DocumentParseResult _parseRtf(String path, List<int> bytes) {
    final rtf = _decodeBytesBestEffort(bytes);
    final text = stripRtfToPlainText(rtf);
    final paragraphs = splitParagraphs(text);
    return DocumentParseResult(
      path: path,
      kind: OfficeDocumentKind.rtf,
      text: text,
      structure:
          'RTF document\nparagraphs=${paragraphs.length}\nchars=${text.length}',
    );
  }

  DocumentParseResult _parseDocx(String path, List<int> bytes) {
    final archive = decodeZipBytes(bytes);
    final documentXml = archiveText(archive, 'word/document.xml');
    if (documentXml == null) {
      return DocumentParseResult(
          path: path,
          kind: OfficeDocumentKind.docx,
          text: '',
          structure: 'word/document.xml not found');
    }
    final document = XmlDocument.parse(documentXml);
    final paragraphs = <String>[];
    for (final paragraph in allElements(document, 'p')) {
      final text = elementText(paragraph, {'t'});
      if (text.isNotEmpty) paragraphs.add(text);
    }
    final tables = <String>[];
    for (final table in allElements(document, 'tbl')) {
      final rows = <String>[];
      for (final row in allElements(table, 'tr')) {
        final cells = <String>[];
        for (final cell in allElements(row, 'tc')) {
          final value = elementText(cell, {'t'});
          if (value.isNotEmpty) cells.add(value);
        }
        if (cells.isNotEmpty) rows.add(cells.join(' | '));
      }
      if (rows.isNotEmpty) tables.add(rows.join('\n'));
    }
    final text = paragraphs.join('\n');
    final structure = StringBuffer()
      ..writeln('DOCX package')
      ..writeln('paragraphs=${paragraphs.length}')
      ..writeln('tables=${tables.length}')
      ..writeln(
          "media=${archive.files.where((f) => f.name.startsWith('word/media/')).length}");
    for (var i = 0; i < math.min(3, tables.length); i++) {
      structure.writeln('table_${i + 1}:');
      structure.writeln(tables[i]);
    }
    return DocumentParseResult(
        path: path,
        kind: OfficeDocumentKind.docx,
        text: text,
        structure: structure.toString());
  }

  DocumentParseResult _parseXlsx(String path, List<int> bytes) {
    final archive = decodeZipBytes(bytes);
    final sharedStrings = _readSharedStrings(archive);
    final sheetNames = _readWorkbookSheetNames(archive);
    final sheetFiles = archive.files
        .where((f) =>
            f.isFile &&
            f.name.replaceAll('\\', '/').startsWith('xl/worksheets/') &&
            f.name.toLowerCase().endsWith('.xml'))
        .toList()
      ..sort((a, b) => _naturalCompare(a.name, b.name));
    final text = StringBuffer();
    final structure = StringBuffer()
      ..writeln('XLSX workbook')
      ..writeln('sheets=${sheetFiles.length}')
      ..writeln('shared_strings=${sharedStrings.length}');
    for (var i = 0; i < sheetFiles.length; i++) {
      final file = sheetFiles[i];
      final name = i < sheetNames.length ? sheetNames[i] : _fileBase(file.name);
      final xml = utf8.decode(file.content, allowMalformed: true);
      final sheet = XmlDocument.parse(xml);
      final rows = <String>[];
      var cellCount = 0;
      for (final row in allElements(sheet, 'row')) {
        final cells = <String>[];
        for (final cell in row.children
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'c')) {
          final value = _xlsxCellValue(cell, sharedStrings);
          cells.add(value);
          if (value.isNotEmpty) cellCount++;
        }
        if (cells.any((c) => c.isNotEmpty)) rows.add(cells.join('\t'));
      }
      structure.writeln(
          'sheet_${i + 1}="$name" rows=${rows.length} cells=$cellCount');
      text.writeln('## $name');
      text.writeln(rows.join('\n'));
      text.writeln();
    }
    return DocumentParseResult(
        path: path,
        kind: OfficeDocumentKind.xlsx,
        text: text.toString().trim(),
        structure: structure.toString());
  }

  DocumentParseResult _parsePptx(String path, List<int> bytes) {
    final archive = decodeZipBytes(bytes);
    final slideFiles = archive.files
        .where((f) =>
            f.isFile &&
            RegExp(r'^ppt/slides/slide\d+\.xml$', caseSensitive: false)
                .hasMatch(f.name.replaceAll('\\', '/')))
        .toList()
      ..sort((a, b) => _naturalCompare(a.name, b.name));
    final text = StringBuffer();
    final structure = StringBuffer()
      ..writeln('PPTX presentation')
      ..writeln('slides=${slideFiles.length}');
    for (var i = 0; i < slideFiles.length; i++) {
      final xml = utf8.decode(slideFiles[i].content, allowMalformed: true);
      final slide = XmlDocument.parse(xml);
      final lines = <String>[];
      for (final item in allElements(slide, 't')) {
        final value = collapseWhitespace(item.innerText);
        if (value.isNotEmpty) lines.add(value);
      }
      structure.writeln('slide_${i + 1} text_items=${lines.length}');
      text.writeln('## Slide ${i + 1}');
      text.writeln(lines.join('\n'));
      text.writeln();
    }
    return DocumentParseResult(
        path: path,
        kind: OfficeDocumentKind.pptx,
        text: text.toString().trim(),
        structure: structure.toString());
  }

  DocumentParseResult _parseOpenDocument(
      String path, List<int> bytes, OfficeDocumentKind kind) {
    Archive? archive;
    try {
      archive = decodeZipBytes(bytes);
    } catch (_) {
      if (kind == OfficeDocumentKind.odc) {
        final text = _decodeBytesBestEffort(bytes);
        return DocumentParseResult(
            path: path,
            kind: kind,
            text: text,
            structure:
                'ODC/XML or text connection document\nchars=${text.length}');
      }
      rethrow;
    }
    final contentXml = archiveText(archive, 'content.xml');
    if (contentXml == null) {
      return DocumentParseResult(
          path: path, kind: kind, text: '', structure: 'content.xml not found');
    }
    final document = XmlDocument.parse(contentXml);
    final text = StringBuffer();
    final structure = StringBuffer()
      ..writeln('${kind.label} package')
      ..writeln('manifest_entries=${archive.files.length}');
    final headings = allElements(document, 'h')
        .map((e) => collapseWhitespace(e.innerText))
        .where((s) => s.isNotEmpty)
        .toList();
    final paragraphs = allElements(document, 'p')
        .map((e) => collapseWhitespace(e.innerText))
        .where((s) => s.isNotEmpty)
        .toList();
    final tables = allElements(document, 'table').toList();
    final pages = allElements(document, 'page').toList();
    structure
      ..writeln('headings=${headings.length}')
      ..writeln('paragraphs=${paragraphs.length}')
      ..writeln('tables=${tables.length}')
      ..writeln('pages=${pages.length}');
    if (headings.isNotEmpty)
      text.writeln(headings.map((h) => '# $h').join('\n'));
    if (paragraphs.isNotEmpty) text.writeln(paragraphs.join('\n'));
    for (var i = 0; i < tables.length; i++) {
      final rows = <String>[];
      for (final row in allElements(tables[i], 'table-row')) {
        final cells = allElements(row, 'table-cell')
            .map((cell) => collapseWhitespace(cell.innerText))
            .where((s) => s.isNotEmpty)
            .toList();
        if (cells.isNotEmpty) rows.add(cells.join('\t'));
      }
      if (rows.isNotEmpty) {
        text
          ..writeln()
          ..writeln('## Table ${i + 1}')
          ..writeln(rows.join('\n'));
      }
    }
    return DocumentParseResult(
        path: path,
        kind: kind,
        text: text.toString().trim(),
        structure: structure.toString());
  }

  List<String> _readSharedStrings(Archive archive) {
    final xml = archiveText(archive, 'xl/sharedStrings.xml');
    if (xml == null) return const [];
    final document = XmlDocument.parse(xml);
    return allElements(document, 'si')
        .map((e) => allElements(e, 't').map((t) => t.innerText).join())
        .toList();
  }

  List<String> _readWorkbookSheetNames(Archive archive) {
    final xml = archiveText(archive, 'xl/workbook.xml');
    if (xml == null) return const [];
    final document = XmlDocument.parse(xml);
    return allElements(document, 'sheet')
        .map((e) => e.getAttribute('name') ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  String _xlsxCellValue(XmlElement cell, List<String> sharedStrings) {
    final type = cell.getAttribute('t') ?? '';
    if (type == 'inlineStr') {
      return allElements(cell, 't').map((e) => e.innerText).join();
    }
    final raw = allElements(cell, 'v').map((e) => e.innerText).join();
    if (type == 's') {
      final index = int.tryParse(raw);
      if (index != null && index >= 0 && index < sharedStrings.length)
        return sharedStrings[index];
    }
    if (type == 'b') return raw == '1' ? 'TRUE' : 'FALSE';
    return raw;
  }

  String _decodeBytesBestEffort(List<int> bytes) {
    final utf8Text =
        utf8.decode(bytes, allowMalformed: true).replaceAll('\u0000', '');
    final bad = RegExp('\uFFFD').allMatches(utf8Text).length;
    if (bad < math.max(4, utf8Text.length ~/ 100))
      return collapseWhitespace(utf8Text);
    return collapseWhitespace(latin1.decode(bytes, allowInvalid: true));
  }

  String stripRtfToPlainText(String rtf) {
    var text = rtf.replaceAllMapped(
        RegExp(r'\\u(-?\d+).', caseSensitive: false), (match) {
      var code = int.tryParse(match.group(1) ?? '') ?? 32;
      if (code < 0) code += 65536;
      return String.fromCharCode(code);
    });
    text = text.replaceAllMapped(RegExp(r"\\'([0-9a-fA-F]{2})"), (match) {
      final code = int.tryParse(match.group(1) ?? '', radix: 16) ?? 32;
      return String.fromCharCode(code);
    });
    text = text.replaceAll(RegExp(r'\\par[d]?'), '\n');
    text = text.replaceAll(RegExp(r'\\line'), '\n');
    text = text.replaceAll(RegExp(r'\\tab'), '\t');
    text = text.replaceAll(RegExp(r'\\[a-zA-Z]+-?\d* ?'), '');
    text = text.replaceAll(RegExp(r'[{}]'), '');
    return collapseWhitespace(text);
  }

  int _naturalCompare(String a, String b) {
    final ai = int.tryParse(RegExp(r'(\d+)').firstMatch(a)?.group(1) ?? '');
    final bi = int.tryParse(RegExp(r'(\d+)').firstMatch(b)?.group(1) ?? '');
    if (ai != null && bi != null && ai != bi) return ai.compareTo(bi);
    return a.compareTo(b);
  }

  String _fileBase(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }
}
