import 'dart:convert';
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
      'vsdx',
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

  test('preserves document structure, formulas, media and diagram geometry',
      () async {
    final dir = await Directory.systemTemp.createTemp('ii_agent_rich_docs_');
    addTearDown(() => dir.delete(recursive: true));
    const builder = OfficeDocumentBuilder();
    const parser = OfficeDocumentParser();

    final image = File('${dir.path}/tiny.png');
    await image.writeAsBytes(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='));
    final docx = '${dir.path}/rich.docx';
    await builder.buildFromText(docx, '''# Report

| Item | Value |
| --- | --- |
| Alpha | 42 |

![Tiny chart](tiny.png)''');
    final parsedDocx = await parser.parseFile(docx);
    expect(parsedDocx.structure, contains('tables=1'));
    expect(parsedDocx.structure, contains('media=1'));
    expect(parsedDocx.metadata['tables'], isNotEmpty);

    final xlsx = '${dir.path}/formula.xlsx';
    await builder.buildFromText(
        xlsx, 'Name,Value,Total\nAlpha,2,=B2*3\nBeta,4,=SUM(B2:B3)');
    final parsedXlsx = await parser.parseFile(xlsx);
    expect(parsedXlsx.structure, contains('formulas=2'));
    expect(parsedXlsx.structure, contains('formula="B2*3"'));
    expect(parsedXlsx.text, contains('C3==SUM(B2:B3)'));

    final pptx = '${dir.path}/layout.pptx';
    await builder.buildFromText(pptx, 'Title\nBody\n\n---\n\nSecond slide');
    final parsedPptx = await parser.parseFile(pptx);
    expect(parsedPptx.structure, contains('canvas='));
    expect(parsedPptx.structure, contains('slide_1_shape'));

    final vsdx = '${dir.path}/diagram.vsdx';
    await builder.buildFromText(vsdx, 'Start\n\nProcess\n\nFinish');
    final parsedVsdx = await parser.parseFile(vsdx);
    expect(parsedVsdx.kind, OfficeDocumentKind.vsdx);
    expect(parsedVsdx.structure, contains('shapes=3'));
    expect(parsedVsdx.structure, contains('pin_x=4.25'));
    expect(parsedVsdx.text, contains('Process'));
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
