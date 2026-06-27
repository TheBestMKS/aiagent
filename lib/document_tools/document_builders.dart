import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import 'document_models.dart';
import 'document_utils.dart';

class OfficeDocumentBuilder {
  const OfficeDocumentBuilder();

  Future<DocumentBuildResult> buildFromText(String path, String text) async {
    final kind = detectOfficeDocumentKind(path);
    final bytes = switch (kind) {
      OfficeDocumentKind.docx => buildDocxBytes(text),
      OfficeDocumentKind.xlsx => buildXlsxBytes(text),
      OfficeDocumentKind.pptx => buildPptxBytes(text),
      OfficeDocumentKind.odt => buildOdtBytes(text),
      OfficeDocumentKind.ods => buildOdsBytes(text),
      OfficeDocumentKind.odp => buildOdpBytes(text),
      OfficeDocumentKind.odc => buildOdcBytes(text),
      OfficeDocumentKind.rtf => buildRtfBytes(text),
      OfficeDocumentKind.plainText ||
      OfficeDocumentKind.unknown =>
        utf8.encode(text),
    };
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return DocumentBuildResult(
        path: path,
        kind: kind,
        bytes: bytes.length,
        message: 'Created ${kind.label} document from plain text');
  }

  List<int> buildRtfBytes(String text) {
    final body = text
        .replaceAll('\\', r'\\')
        .replaceAll('{', r'\{')
        .replaceAll('}', r'\}')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => '${_rtfUnicode(line)}\\par')
        .join('\n');
    return '{\\rtf1\\ansi\\deff0\n$body\n}'.codeUnits;
  }

  List<int> buildDocxBytes(String text) {
    final paragraphs = splitParagraphs(text)
        .map((p) =>
            '<w:p><w:r><w:t xml:space="preserve">${xmlEscape(p)}</w:t></w:r></w:p>')
        .join();
    final archive = Archive();
    archiveAddUtf8(archive, '[Content_Types].xml', _docxContentTypes());
    archiveAddUtf8(
        archive,
        '_rels/.rels',
        _packageRels(
            'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument',
            'word/document.xml'));
    archiveAddUtf8(
        archive, 'word/_rels/document.xml.rels', _emptyRelationships());
    archiveAddUtf8(archive, 'word/styles.xml', _docxStyles());
    archiveAddUtf8(archive, 'word/document.xml',
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    $paragraphs
    <w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>
  </w:body>
</w:document>''');
    return encodeZipArchive(archive);
  }

  List<int> buildXlsxBytes(String text) {
    final rows = splitTableRows(text);
    final sheetRows = StringBuffer();
    for (var r = 0; r < rows.length; r++) {
      sheetRows.write('<row r="${r + 1}">');
      for (var c = 0; c < rows[r].length; c++) {
        final ref = '${_xlsxColumnName(c + 1)}${r + 1}';
        sheetRows.write(
            '<c r="$ref" t="inlineStr"><is><t>${xmlEscape(rows[r][c])}</t></is></c>');
      }
      sheetRows.write('</row>');
    }
    final archive = Archive();
    archiveAddUtf8(archive, '[Content_Types].xml', _xlsxContentTypes());
    archiveAddUtf8(
        archive,
        '_rels/.rels',
        _packageRels(
            'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument',
            'xl/workbook.xml'));
    archiveAddUtf8(archive, 'xl/_rels/workbook.xml.rels',
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''');
    archiveAddUtf8(archive, 'xl/workbook.xml',
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>
</workbook>''');
    archiveAddUtf8(archive, 'xl/styles.xml',
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>
  <fills count="1"><fill><patternFill patternType="none"/></fill></fills>
  <borders count="1"><border/></borders>
  <cellStyleXfs count="1"><xf/></cellStyleXfs>
  <cellXfs count="1"><xf xfId="0"/></cellXfs>
</styleSheet>''');
    archiveAddUtf8(archive, 'xl/worksheets/sheet1.xml',
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>$sheetRows</sheetData>
</worksheet>''');
    return encodeZipArchive(archive);
  }

  List<int> buildPptxBytes(String text) {
    final slides = splitSlides(text);
    final archive = Archive();
    archiveAddUtf8(
        archive, '[Content_Types].xml', _pptxContentTypes(slides.length));
    archiveAddUtf8(
        archive,
        '_rels/.rels',
        _packageRels(
            'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument',
            'ppt/presentation.xml'));
    final slideIds = StringBuffer();
    final rels =
        StringBuffer('''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">''');
    for (var i = 0; i < slides.length; i++) {
      slideIds.write('<p:sldId id="${256 + i}" r:id="rId${i + 1}"/>');
      rels.write(
          '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide${i + 1}.xml"/>');
      archiveAddUtf8(archive, 'ppt/slides/slide${i + 1}.xml',
          _pptxSlideXml(slides[i], i + 1));
    }
    rels.write('</Relationships>');
    archiveAddUtf8(archive, 'ppt/_rels/presentation.xml.rels', rels.toString());
    archiveAddUtf8(archive, 'ppt/presentation.xml',
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:sldIdLst>$slideIds</p:sldIdLst>
  <p:sldSz cx="9144000" cy="5143500" type="screen16x9"/>
  <p:notesSz cx="6858000" cy="9144000"/>
</p:presentation>''');
    return encodeZipArchive(archive);
  }

  List<int> buildOdtBytes(String text) => _buildOdfBytes(
        mimeType: 'application/vnd.oasis.opendocument.text',
        contentXml: _odtContent(text),
      );

  List<int> buildOdsBytes(String text) => _buildOdfBytes(
        mimeType: 'application/vnd.oasis.opendocument.spreadsheet',
        contentXml: _odsContent(text),
      );

  List<int> buildOdpBytes(String text) => _buildOdfBytes(
        mimeType: 'application/vnd.oasis.opendocument.presentation',
        contentXml: _odpContent(text),
      );

  List<int> buildOdcBytes(String text) => _buildOdfBytes(
        mimeType: 'application/vnd.oasis.opendocument.chart',
        contentXml: _odtContent(text),
      );

  List<int> _buildOdfBytes(
      {required String mimeType, required String contentXml}) {
    final archive = Archive();
    archiveAddUtf8(archive, 'mimetype', mimeType, noCompress: true);
    archiveAddUtf8(archive, 'META-INF/manifest.xml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">
  <manifest:file-entry manifest:full-path="/" manifest:media-type="$mimeType"/>
  <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
  <manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>
</manifest:manifest>''');
    archiveAddUtf8(archive, 'styles.xml', _odfStyles());
    archiveAddUtf8(archive, 'content.xml', contentXml);
    return encodeZipArchive(archive);
  }

  String _rtfUnicode(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      if (rune >= 32 && rune <= 126) {
        buffer.write(String.fromCharCode(rune));
      } else if (rune == 10) {
        buffer.write(r'\par ');
      } else {
        final signed = rune > 32767 ? rune - 65536 : rune;
        buffer.write('\\u$signed?');
      }
    }
    return buffer.toString();
  }

  String _xlsxColumnName(int index) {
    var n = index;
    final chars = <String>[];
    while (n > 0) {
      n--;
      chars.insert(0, String.fromCharCode(65 + (n % 26)));
      n ~/= 26;
    }
    return chars.join();
  }

  String _packageRels(String type, String target) =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="$type" Target="$target"/>
</Relationships>''';

  String _emptyRelationships() =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>''';

  String _docxContentTypes() =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>''';

  String _docxStyles() =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
</w:styles>''';

  String _xlsxContentTypes() =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>''';

  String _pptxContentTypes(int slideCount) {
    final slideOverrides = List.generate(
            slideCount,
            (i) =>
                '<Override PartName="/ppt/slides/slide${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>')
        .join();
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
  $slideOverrides
</Types>''';
  }

  String _pptxSlideXml(String slideText, int index) {
    final lines = slideText
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final title = lines.isEmpty ? 'Slide $index' : lines.first;
    final body = (lines.length <= 1 ? lines : lines.skip(1))
        .map((l) => '<a:p><a:r><a:t>${xmlEscape(l)}</a:t></a:r></a:p>')
        .join();
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
      <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
      <p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="685800" y="342900"/><a:ext cx="7772400" cy="685800"/></a:xfrm></p:spPr><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>${xmlEscape(title)}</a:t></a:r></a:p></p:txBody></p:sp>
      <p:sp><p:nvSpPr><p:cNvPr id="3" name="Body"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="685800" y="1371600"/><a:ext cx="7772400" cy="3200400"/></a:xfrm></p:spPr><p:txBody><a:bodyPr/><a:lstStyle/>$body</p:txBody></p:sp>
    </p:spTree>
  </p:cSld>
</p:sld>''';
  }

  String _odfStyles() => '''<?xml version="1.0" encoding="UTF-8"?>
<office:document-styles xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" office:version="1.2">
  <office:styles/>
</office:document-styles>''';

  String _odtContent(String text) {
    final paragraphs = splitParagraphs(text)
        .map((p) => '<text:p>${xmlEscape(p)}</text:p>')
        .join();
    return '''<?xml version="1.0" encoding="UTF-8"?>
<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" office:version="1.2">
  <office:body><office:text>$paragraphs</office:text></office:body>
</office:document-content>''';
  }

  String _odsContent(String text) {
    final rows = splitTableRows(text).map((row) {
      final cells = row
          .map((cell) =>
              '<table:table-cell office:value-type="string"><text:p>${xmlEscape(cell)}</text:p></table:table-cell>')
          .join();
      return '<table:table-row>$cells</table:table-row>';
    }).join();
    return '''<?xml version="1.0" encoding="UTF-8"?>
<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" office:version="1.2">
  <office:body><office:spreadsheet><table:table table:name="Sheet1">$rows</table:table></office:spreadsheet></office:body>
</office:document-content>''';
  }

  String _odpContent(String text) {
    final slides = splitSlides(text).asMap().entries.map((entry) {
      final lines = entry.value
          .split(RegExp(r'\r?\n'))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      final paragraphs = (lines.isEmpty ? ['Slide ${entry.key + 1}'] : lines)
          .map((l) => '<text:p>${xmlEscape(l)}</text:p>')
          .join();
      return '<draw:page draw:name="Slide ${entry.key + 1}"><draw:frame draw:name="Text ${entry.key + 1}"><draw:text-box>$paragraphs</draw:text-box></draw:frame></draw:page>';
    }).join();
    return '''<?xml version="1.0" encoding="UTF-8"?>
<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" office:version="1.2">
  <office:body><office:presentation>$slides</office:presentation></office:body>
</office:document-content>''';
  }
}
