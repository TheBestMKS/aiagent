import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'document_builders.dart';
import 'document_models.dart';
import 'document_parsers.dart';
import 'document_utils.dart';

class OfficeDocumentEditor {
  const OfficeDocumentEditor(
      {this.parser = const OfficeDocumentParser(),
      this.builder = const OfficeDocumentBuilder()});

  final OfficeDocumentParser parser;
  final OfficeDocumentBuilder builder;

  Future<DocumentEditResult> editText({
    required String path,
    required DocumentEditMode mode,
    required String newText,
    String oldText = '',
  }) async {
    final kind = detectOfficeDocumentKind(path);
    if (!await File(path).exists()) {
      if (mode == DocumentEditMode.replaceAll ||
          mode == DocumentEditMode.appendText ||
          mode == DocumentEditMode.prependText) {
        final built = await builder.buildFromText(path, newText);
        return DocumentEditResult(
            path: path,
            kind: built.kind,
            changed: true,
            message:
                'Document did not exist; created ${built.kind.label}. Bytes: ${built.bytes}');
      }
      return DocumentEditResult(
          path: path,
          kind: kind,
          changed: false,
          message: 'File not found: $path');
    }

    if (mode == DocumentEditMode.replaceText && oldText.trim().isEmpty) {
      return DocumentEditResult(
          path: path,
          kind: kind,
          changed: false,
          message: 'old_text is required for replace_text mode');
    }

    if (mode == DocumentEditMode.replaceText && _canPatchXmlPackage(kind)) {
      final patched = await _patchXmlPackage(path, kind, oldText, newText);
      if (patched) {
        return DocumentEditResult(
            path: path,
            kind: kind,
            changed: true,
            message: 'Replaced text in ${kind.label} XML text nodes');
      }
    }

    final parsed = await parser.parseFile(path);
    final updatedText = switch (mode) {
      DocumentEditMode.replaceAll => newText,
      DocumentEditMode.appendText => '${parsed.text.trimRight()}\n$newText',
      DocumentEditMode.prependText => '$newText\n${parsed.text.trimLeft()}',
      DocumentEditMode.replaceText => parsed.text.replaceAll(oldText, newText),
    };
    if (mode == DocumentEditMode.replaceText && updatedText == parsed.text) {
      return DocumentEditResult(
          path: path,
          kind: kind,
          changed: false,
          message: 'Text not found: $oldText');
    }
    final built = await builder.buildFromText(path, updatedText);
    return DocumentEditResult(
        path: path,
        kind: built.kind,
        changed: true,
        message:
            'Rebuilt ${built.kind.label} with edited plain text. Bytes: ${built.bytes}');
  }

  bool _canPatchXmlPackage(OfficeDocumentKind kind) => const {
        OfficeDocumentKind.docx,
        OfficeDocumentKind.xlsx,
        OfficeDocumentKind.pptx,
        OfficeDocumentKind.odt,
        OfficeDocumentKind.ods,
        OfficeDocumentKind.odp,
        OfficeDocumentKind.odc,
      }.contains(kind);

  Future<bool> _patchXmlPackage(String path, OfficeDocumentKind kind,
      String oldText, String newText) async {
    final file = File(path);
    final archive = decodeZipBytes(await file.readAsBytes());
    final targets = _xmlTargets(archive, kind);
    var changed = false;
    for (final target in targets) {
      final entry = findArchiveFile(archive, target);
      if (entry == null || !entry.isFile) continue;
      final xmlText = utf8.decode(entry.content, allowMalformed: true);
      XmlDocument document;
      try {
        document = XmlDocument.parse(xmlText);
      } catch (_) {
        continue;
      }
      var documentChanged = false;
      for (final element in _textPatchElements(document, kind)) {
        final value = element.innerText;
        if (!value.contains(oldText)) continue;
        element.innerText = value.replaceAll(oldText, newText);
        documentChanged = true;
      }
      if (documentChanged) {
        changed = true;
        archive.addFile(ArchiveFile.bytes(
            target, utf8.encode(xmlDocumentToString(document))));
      }
    }
    if (changed) {
      await file.writeAsBytes(encodeZipArchive(archive), flush: true);
    }
    return changed;
  }

  List<String> _xmlTargets(Archive archive, OfficeDocumentKind kind) {
    final names =
        archive.files.map((f) => f.name.replaceAll('\\', '/')).toList();
    return switch (kind) {
      OfficeDocumentKind.docx => names
          .where((n) =>
              n == 'word/document.xml' ||
              (n.startsWith('word/header') && n.endsWith('.xml')) ||
              (n.startsWith('word/footer') && n.endsWith('.xml')))
          .toList(),
      OfficeDocumentKind.xlsx => names
          .where((n) =>
              n == 'xl/sharedStrings.xml' ||
              (n.startsWith('xl/worksheets/') && n.endsWith('.xml')))
          .toList(),
      OfficeDocumentKind.pptx => names
          .where((n) => n.startsWith('ppt/slides/') && n.endsWith('.xml'))
          .toList(),
      OfficeDocumentKind.odt ||
      OfficeDocumentKind.ods ||
      OfficeDocumentKind.odp ||
      OfficeDocumentKind.odc =>
        names.where((n) => n == 'content.xml').toList(),
      _ => const [],
    };
  }

  Iterable<XmlElement> _textPatchElements(
      XmlDocument document, OfficeDocumentKind kind) {
    final names = switch (kind) {
      OfficeDocumentKind.docx => {'t'},
      OfficeDocumentKind.xlsx => {'t', 'v'},
      OfficeDocumentKind.pptx => {'t'},
      OfficeDocumentKind.odt ||
      OfficeDocumentKind.ods ||
      OfficeDocumentKind.odp ||
      OfficeDocumentKind.odc =>
        {'p', 'h'},
      _ => <String>{},
    };
    return document.descendants
        .whereType<XmlElement>()
        .where((element) => names.contains(element.name.local));
  }
}
