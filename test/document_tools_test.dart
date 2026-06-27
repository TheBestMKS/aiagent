import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_agent/document_tools/office_document_tools.dart';

void main() {
  test('builds and parses supported office documents', () async {
    final dir = await Directory.systemTemp.createTemp('ii_agent_docs_');
    addTearDown(() => dir.delete(recursive: true));

    const text =
        'Rundll32 notes\n\nTarget: rundll32.exe\nDetails: system helper';
    const extensions = [
      'rtf',
      'docx',
      'xlsx',
      'pptx',
      'odt',
      'ods',
      'odp',
      'odc'
    ];
    const builder = OfficeDocumentBuilder();
    const parser = OfficeDocumentParser();

    for (final extension in extensions) {
      final file = File('${dir.path}/sample.$extension');
      final built = await builder.buildFromText(file.path, text);

      expect(built.bytes, greaterThan(0), reason: extension);
      expect(await file.exists(), isTrue, reason: extension);

      final parsed = await parser.parseFile(file.path);
      expect(parsed.text.toLowerCase(), contains('rundll32'),
          reason: extension);
      expect(parsed.structure, isNotEmpty, reason: extension);
    }
  });

  test('edits generated docx text and keeps it parseable', () async {
    final dir = await Directory.systemTemp.createTemp('ii_agent_docx_edit_');
    addTearDown(() => dir.delete(recursive: true));

    final path = '${dir.path}/editable.docx';
    const builder = OfficeDocumentBuilder();
    const parser = OfficeDocumentParser();
    const editor = OfficeDocumentEditor();

    await builder.buildFromText(path, 'Original rundll32 note');
    final edited = await editor.editText(
      path: path,
      mode: DocumentEditMode.replaceText,
      oldText: 'Original',
      newText: 'Updated',
    );
    final parsed = await parser.parseFile(path);

    expect(edited.changed, isTrue);
    expect(parsed.text, contains('Updated rundll32 note'));
  });
}
