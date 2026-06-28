import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'document_models.dart';

OfficeDocumentKind detectOfficeDocumentKind(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.rtf')) return OfficeDocumentKind.rtf;
  if (lower.endsWith('.docx')) return OfficeDocumentKind.docx;
  if (lower.endsWith('.xlsx')) return OfficeDocumentKind.xlsx;
  if (lower.endsWith('.pptx') || lower.endsWith('.ppts'))
    return OfficeDocumentKind.pptx;
  if (lower.endsWith('.odt')) return OfficeDocumentKind.odt;
  if (lower.endsWith('.ods')) return OfficeDocumentKind.ods;
  if (lower.endsWith('.odp')) return OfficeDocumentKind.odp;
  if (lower.endsWith('.odc')) return OfficeDocumentKind.odc;
  if (lower.endsWith('.txt') ||
      lower.endsWith('.md') ||
      lower.endsWith('.csv') ||
      lower.endsWith('.xml') ||
      lower.endsWith('.html') ||
      lower.endsWith('.htm')) {
    return OfficeDocumentKind.plainText;
  }
  return OfficeDocumentKind.unknown;
}

bool isStructuredOfficeDocumentPath(String path) {
  final kind = detectOfficeDocumentKind(path);
  return kind != OfficeDocumentKind.unknown &&
      kind != OfficeDocumentKind.plainText;
}

String xmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String collapseWhitespace(String value) => value
    .replaceAll(RegExp(r'[ \t]+'), ' ')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

List<String> splitParagraphs(String text) {
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final parts = normalized
      .split(RegExp(r'\n{2,}'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty && normalized.trim().isNotEmpty) return [normalized.trim()];
  return parts;
}

List<List<String>> splitTableRows(String text) {
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .toList();
  if (lines.isEmpty)
    return [
      ['']
    ];
  final markdownRows = <List<String>>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (!line.contains('|')) continue;
    if (i + 1 < lines.length &&
        RegExp(r'^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$')
            .hasMatch(lines[i + 1].trim())) {
      markdownRows.add(_splitMarkdownTableRow(line));
      i += 2;
      while (i < lines.length && lines[i].contains('|')) {
        markdownRows.add(_splitMarkdownTableRow(lines[i].trim()));
        i++;
      }
      break;
    }
  }
  if (markdownRows.isNotEmpty) return markdownRows;
  return lines.map((line) {
    final separator =
        line.contains('\t') ? '\t' : (line.contains(';') ? ';' : ',');
    final cells = line.split(separator).map((c) => c.trim()).toList();
    return cells.isEmpty ? [''] : cells;
  }).toList();
}

List<String> _splitMarkdownTableRow(String line) {
  var raw = line.trim();
  if (raw.startsWith('|')) raw = raw.substring(1);
  if (raw.endsWith('|')) raw = raw.substring(0, raw.length - 1);
  return raw.split('|').map((cell) => cell.trim()).toList();
}

List<String> splitSlides(String text) {
  final normalized =
      text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  if (normalized.isEmpty) return [''];
  final byMarker = normalized
      .split(RegExp(r'^\s*---+\s*$', multiLine: true))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (byMarker.length > 1) return byMarker;
  final byBlank = normalized
      .split(RegExp(r'\n{2,}'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  return byBlank.isEmpty ? [normalized] : byBlank;
}

Archive decodeZipBytes(List<int> bytes) =>
    ZipDecoder().decodeBytes(bytes, verify: true);

ArchiveFile? findArchiveFile(Archive archive, String name) {
  final normalized = name.replaceAll('\\', '/');
  for (final file in archive.files) {
    if (file.name.replaceAll('\\', '/') == normalized) return file;
  }
  return null;
}

String? archiveText(Archive archive, String name) {
  final file = findArchiveFile(archive, name);
  if (file == null || !file.isFile) return null;
  return utf8.decode(file.content, allowMalformed: true);
}

void archiveAddUtf8(Archive archive, String name, String content,
    {bool noCompress = false}) {
  final bytes = utf8.encode(content);
  archive.addFile(noCompress
      ? ArchiveFile.noCompress(name, bytes.length, bytes)
      : ArchiveFile.bytes(name, bytes));
}

List<int> encodeZipArchive(Archive archive) =>
    ZipEncoder().encodeBytes(archive);

Iterable<XmlElement> allElements(XmlNode node, String localName) =>
    node.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == localName);

String elementText(XmlElement element, Set<String> textElementNames) {
  final buffer = StringBuffer();
  for (final child in element.descendants) {
    if (child is XmlElement && textElementNames.contains(child.name.local)) {
      buffer.write(child.innerText);
    } else if (child is XmlElement &&
        (child.name.local == 'tab' || child.name.local == 's')) {
      buffer.write('\t');
    } else if (child is XmlElement &&
        (child.name.local == 'br' || child.name.local == 'line-break')) {
      buffer.write('\n');
    }
  }
  return collapseWhitespace(buffer.toString());
}

String textFromNamedElements(XmlNode node, Set<String> names,
    {String separator = '\n'}) {
  final parts = <String>[];
  for (final element in node.descendants.whereType<XmlElement>()) {
    if (!names.contains(element.name.local)) continue;
    final text = collapseWhitespace(element.innerText);
    if (text.isNotEmpty) parts.add(text);
  }
  return parts.join(separator);
}

String xmlDocumentToString(XmlDocument document) =>
    document.toXmlString(pretty: false);
