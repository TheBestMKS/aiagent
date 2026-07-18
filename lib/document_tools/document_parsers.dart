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
        OfficeDocumentKind.vsdx => _parseVsdx(path, bytes),
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
    final styles = _docxStyleNames(archive);
    final paragraphMetadata = <Map<String, Object?>>[];
    final tableMetadata = <Map<String, Object?>>[];
    final text = StringBuffer();
    final body = allElements(document, 'body').firstOrNull;
    var paragraphIndex = 0;
    var tableIndex = 0;

    for (final child
        in body?.children.whereType<XmlElement>() ?? const <XmlElement>[]) {
      if (child.name.local == 'p') {
        final paragraphText = elementText(child, {'t'});
        final pPr = _directElement(child, 'pPr');
        final styleId = _attributeLocal(
                pPr == null ? null : allElements(pPr, 'pStyle').firstOrNull,
                'val') ??
            '';
        final styleName = styles[styleId] ?? styleId;
        final alignment = _attributeLocal(
                pPr == null ? null : allElements(pPr, 'jc').firstOrNull,
                'val') ??
            '';
        final numId = _attributeLocal(
                pPr == null ? null : allElements(pPr, 'numId').firstOrNull,
                'val') ??
            '';
        final ilvl = _attributeLocal(
                pPr == null ? null : allElements(pPr, 'ilvl').firstOrNull,
                'val') ??
            '';
        final runs = _directElements(child, 'r')
            .map((run) {
              final rPr = _directElement(run, 'rPr');
              return <String, Object?>{
                'text': elementText(run, {'t'}),
                'bold': rPr != null && allElements(rPr, 'b').isNotEmpty,
                'italic': rPr != null && allElements(rPr, 'i').isNotEmpty,
                'underline': rPr != null && allElements(rPr, 'u').isNotEmpty,
              };
            })
            .where((run) => (run['text']?.toString() ?? '').isNotEmpty)
            .toList();
        paragraphIndex++;
        paragraphMetadata.add({
          'index': paragraphIndex,
          'text': paragraphText,
          'style_id': styleId,
          'style': styleName,
          'alignment': alignment,
          'numbering_id': numId,
          'numbering_level': ilvl,
          'runs': runs,
        });
        if (paragraphText.isNotEmpty) {
          final headingLevel = _headingLevel(styleId, styleName);
          if (headingLevel > 0) {
            text.writeln('${'#' * headingLevel} $paragraphText');
          } else if (numId.isNotEmpty) {
            text.writeln('- $paragraphText');
          } else {
            text.writeln(paragraphText);
          }
        }
      } else if (child.name.local == 'tbl') {
        tableIndex++;
        final rows = <List<Map<String, Object?>>>[];
        for (final row in _directElements(child, 'tr')) {
          final cells = <Map<String, Object?>>[];
          for (final cell in _directElements(row, 'tc')) {
            final tcPr = _directElement(cell, 'tcPr');
            final gridSpan = int.tryParse(_attributeLocal(
                        tcPr == null
                            ? null
                            : allElements(tcPr, 'gridSpan').firstOrNull,
                        'val') ??
                    '') ??
                1;
            final verticalMerge = _attributeLocal(
                    tcPr == null
                        ? null
                        : allElements(tcPr, 'vMerge').firstOrNull,
                    'val') ??
                (tcPr != null && allElements(tcPr, 'vMerge').isNotEmpty
                    ? 'continue'
                    : '');
            cells.add({
              'text': elementText(cell, {'t'}),
              'column_span': gridSpan,
              'vertical_merge': verticalMerge,
            });
          }
          if (cells.isNotEmpty) rows.add(cells);
        }
        tableMetadata.add({
          'index': tableIndex,
          'rows': rows,
          'row_count': rows.length,
          'column_count': rows.fold<int>(
              0,
              (maxColumns, row) => math.max(
                  maxColumns,
                  row.fold<int>(
                      0, (sum, cell) => sum + (cell['column_span'] as int)))),
        });
        text.writeln('\n## Table $tableIndex');
        for (final row in rows) {
          text.writeln('| ${row.map((cell) => cell['text']).join(' | ')} |');
        }
        text.writeln();
      }
    }

    final headers = _docxPartTexts(archive, 'word/header');
    final footers = _docxPartTexts(archive, 'word/footer');
    final section = allElements(document, 'sectPr').lastOrNull;
    final pageSize =
        section == null ? null : allElements(section, 'pgSz').firstOrNull;
    final pageMargins =
        section == null ? null : allElements(section, 'pgMar').firstOrNull;
    final page = <String, Object?>{
      'width_twips': _attributeLocal(pageSize, 'w'),
      'height_twips': _attributeLocal(pageSize, 'h'),
      'orientation': _attributeLocal(pageSize, 'orient'),
      'margin_top_twips': _attributeLocal(pageMargins, 'top'),
      'margin_right_twips': _attributeLocal(pageMargins, 'right'),
      'margin_bottom_twips': _attributeLocal(pageMargins, 'bottom'),
      'margin_left_twips': _attributeLocal(pageMargins, 'left'),
    };
    final media = archive.files
        .where((file) => file.isFile && file.name.startsWith('word/media/'))
        .map((file) => file.name)
        .toList(growable: false);
    final structure = StringBuffer()
      ..writeln('DOCX package')
      ..writeln('paragraphs=${paragraphMetadata.length}')
      ..writeln('tables=${tableMetadata.length}')
      ..writeln('headers=${headers.length}')
      ..writeln('footers=${footers.length}')
      ..writeln('media=${media.length}')
      ..writeln('page=${jsonEncode(page)}');
    for (final paragraph in paragraphMetadata.take(250)) {
      structure.writeln(
          'paragraph_${paragraph['index']} style="${paragraph['style']}" align=${paragraph['alignment']} numbering=${paragraph['numbering_id']}:${paragraph['numbering_level']} text="${_preview(paragraph['text']?.toString() ?? '')}"');
    }
    for (final table in tableMetadata.take(50)) {
      structure.writeln(
          'table_${table['index']} rows=${table['row_count']} columns=${table['column_count']}');
    }
    return DocumentParseResult(
        path: path,
        kind: OfficeDocumentKind.docx,
        text: text.toString().trim(),
        structure: structure.toString(),
        metadata: {
          'paragraphs': paragraphMetadata,
          'tables': tableMetadata,
          'headers': headers,
          'footers': footers,
          'media': media,
          'page': page,
        });
  }

  DocumentParseResult _parseXlsx(String path, List<int> bytes) {
    final archive = decodeZipBytes(bytes);
    final sharedStrings = _readSharedStrings(archive);
    final workbookSheets = _readWorkbookSheets(archive);
    final fallbackSheetFiles = archive.files
        .where((file) =>
            file.isFile &&
            file.name.replaceAll('\\', '/').startsWith('xl/worksheets/') &&
            file.name.toLowerCase().endsWith('.xml'))
        .toList()
      ..sort((a, b) => _naturalCompare(a.name, b.name));
    final sheets = workbookSheets.isNotEmpty
        ? workbookSheets
        : fallbackSheetFiles
            .map((file) => <String, String>{
                  'name': _fileBase(file.name),
                  'path': file.name.replaceAll('\\', '/'),
                  'state': 'visible',
                })
            .toList(growable: false);
    final text = StringBuffer();
    final sheetMetadata = <Map<String, Object?>>[];
    final stylesXml = archiveText(archive, 'xl/styles.xml');
    final styleCount = stylesXml == null
        ? 0
        : allElements(XmlDocument.parse(stylesXml), 'cellXfs')
            .expand((element) => _directElements(element, 'xf'))
            .length;
    final structure = StringBuffer()
      ..writeln('XLSX workbook')
      ..writeln('sheets=${sheets.length}')
      ..writeln('shared_strings=${sharedStrings.length}')
      ..writeln('cell_styles=$styleCount');
    for (var i = 0; i < sheets.length; i++) {
      final sheetDescriptor = sheets[i];
      final name = sheetDescriptor['name'] ?? 'Sheet ${i + 1}';
      final partPath = sheetDescriptor['path'] ?? '';
      final file = findArchiveFile(archive, partPath);
      if (file == null || !file.isFile) {
        structure.writeln(
            'sheet_${i + 1}="$name" state=${sheetDescriptor['state']} missing_part="$partPath"');
        continue;
      }
      final xml = utf8.decode(file.content, allowMalformed: true);
      final sheet = XmlDocument.parse(xml);
      final cells = <Map<String, Object?>>[];
      final rows = <Map<String, Object?>>[];
      for (final row in allElements(sheet, 'row')) {
        final rowCells = <Map<String, Object?>>[];
        for (final cell in _directElements(row, 'c')) {
          final reference = _attributeLocal(cell, 'r') ?? '';
          final formula = allElements(cell, 'f').firstOrNull?.innerText ?? '';
          final value = _xlsxCellValue(cell, sharedStrings);
          final cellInfo = <String, Object?>{
            'reference': reference,
            'value': value,
            'formula': formula,
            'type': _attributeLocal(cell, 't') ?? '',
            'style': int.tryParse(_attributeLocal(cell, 's') ?? ''),
          };
          rowCells.add(cellInfo);
          cells.add(cellInfo);
        }
        rows.add({
          'index': int.tryParse(_attributeLocal(row, 'r') ?? ''),
          'height': double.tryParse(_attributeLocal(row, 'ht') ?? ''),
          'hidden': _attributeLocal(row, 'hidden') == '1',
          'cells': rowCells,
        });
      }
      final columns = allElements(sheet, 'col')
          .map((column) => <String, Object?>{
                'min': int.tryParse(_attributeLocal(column, 'min') ?? ''),
                'max': int.tryParse(_attributeLocal(column, 'max') ?? ''),
                'width':
                    double.tryParse(_attributeLocal(column, 'width') ?? ''),
                'hidden': _attributeLocal(column, 'hidden') == '1',
                'style': int.tryParse(_attributeLocal(column, 'style') ?? ''),
              })
          .toList(growable: false);
      final mergedCells = allElements(sheet, 'mergeCell')
          .map((cell) => _attributeLocal(cell, 'ref') ?? '')
          .where((reference) => reference.isNotEmpty)
          .toList(growable: false);
      final dimension =
          _attributeLocal(allElements(sheet, 'dimension').firstOrNull, 'ref') ??
              '';
      final formulaCount = cells
          .where((cell) => (cell['formula']?.toString() ?? '').isNotEmpty)
          .length;
      structure.writeln(
          'sheet_${i + 1}="$name" state=${sheetDescriptor['state']} dimension="$dimension" rows=${rows.length} cells=${cells.length} formulas=$formulaCount merged=${mergedCells.length}');
      if (columns.isNotEmpty) {
        structure.writeln('sheet_${i + 1}_columns=${jsonEncode(columns)}');
      }
      if (mergedCells.isNotEmpty) {
        structure
            .writeln('sheet_${i + 1}_merged_cells=${mergedCells.join(',')}');
      }
      for (final cell in cells.take(1000)) {
        final formula = cell['formula']?.toString() ?? '';
        structure.writeln(
            'cell ${cell['reference']} style=${cell['style']} type=${cell['type']} ${formula.isEmpty ? '' : 'formula="${_preview(formula)}" '}value="${_preview(cell['value']?.toString() ?? '')}"');
      }
      text.writeln('## $name');
      for (final row in rows) {
        final rowCells = (row['cells'] as List<Map<String, Object?>>);
        final values = rowCells.map((cell) {
          final formula = cell['formula']?.toString() ?? '';
          final value = cell['value']?.toString() ?? '';
          return '${cell['reference']}=${formula.isEmpty ? value : '=$formula${value.isEmpty ? '' : ' -> $value'}'}';
        }).join(' | ');
        if (values.isNotEmpty) text.writeln(values);
      }
      text.writeln();
      sheetMetadata.add({
        'index': i + 1,
        'name': name,
        'state': sheetDescriptor['state'],
        'path': partPath,
        'dimension': dimension,
        'columns': columns,
        'merged_cells': mergedCells,
        'rows': rows,
        'formula_count': formulaCount,
      });
    }
    return DocumentParseResult(
        path: path,
        kind: OfficeDocumentKind.xlsx,
        text: text.toString().trim(),
        structure: structure.toString(),
        metadata: {
          'sheets': sheetMetadata,
          'shared_string_count': sharedStrings.length,
          'style_count': styleCount,
        });
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
    final slideMetadata = <Map<String, Object?>>[];
    final presentationXml = archiveText(archive, 'ppt/presentation.xml');
    final presentation =
        presentationXml == null ? null : XmlDocument.parse(presentationXml);
    final slideSize = presentation == null
        ? null
        : allElements(presentation, 'sldSz').firstOrNull;
    final canvas = <String, Object?>{
      'width_emu': int.tryParse(_attributeLocal(slideSize, 'cx') ?? ''),
      'height_emu': int.tryParse(_attributeLocal(slideSize, 'cy') ?? ''),
      'type': _attributeLocal(slideSize, 'type') ?? '',
    };
    final structure = StringBuffer()
      ..writeln('PPTX presentation')
      ..writeln('slides=${slideFiles.length}')
      ..writeln('canvas=${jsonEncode(canvas)}');
    for (var i = 0; i < slideFiles.length; i++) {
      final xml = utf8.decode(slideFiles[i].content, allowMalformed: true);
      final slide = XmlDocument.parse(xml);
      final relationships = _partRelationships(
          archive, _relationshipPartPath(slideFiles[i].name));
      final shapes = slide.descendants
          .whereType<XmlElement>()
          .where((element) => const {'sp', 'pic', 'graphicFrame', 'cxnSp'}
              .contains(element.name.local))
          .map((shape) => _pptxShapeInfo(shape, relationships))
          .toList(growable: false);
      final visualShapes = [...shapes]..sort((a, b) {
          final ay = (a['y_emu'] as int?) ?? 0;
          final by = (b['y_emu'] as int?) ?? 0;
          if (ay != by) return ay.compareTo(by);
          return ((a['x_emu'] as int?) ?? 0)
              .compareTo((b['x_emu'] as int?) ?? 0);
        });
      final notesRelationship = relationships.entries
          .where(
              (entry) => entry.value['type']?.endsWith('/notesSlide') == true)
          .firstOrNull;
      final notesPath = notesRelationship?.value['target'] ?? '';
      final notesXml =
          notesPath.isEmpty ? null : archiveText(archive, notesPath);
      final notes = notesXml == null
          ? <String>[]
          : allElements(XmlDocument.parse(notesXml), 't')
              .map((element) => collapseWhitespace(element.innerText))
              .where((value) => value.isNotEmpty)
              .toList(growable: false);
      structure.writeln(
          'slide_${i + 1} shapes=${shapes.length} text_shapes=${shapes.where((shape) => (shape['text']?.toString() ?? '').isNotEmpty).length} notes=${notes.length}');
      for (final shape in shapes.take(500)) {
        structure.writeln(
            'slide_${i + 1}_shape id=${shape['id']} name="${_preview(shape['name']?.toString() ?? '')}" type=${shape['type']} x=${shape['x_emu']} y=${shape['y_emu']} width=${shape['width_emu']} height=${shape['height_emu']} target="${shape['relationship_target']}" text="${_preview(shape['text']?.toString() ?? '')}"');
      }
      text.writeln('## Slide ${i + 1}');
      for (final shape in visualShapes) {
        final value = shape['text']?.toString() ?? '';
        if (value.isNotEmpty) text.writeln(value);
      }
      if (notes.isNotEmpty) {
        text.writeln('\n### Speaker notes');
        text.writeln(notes.join('\n'));
      }
      text.writeln();
      slideMetadata.add({
        'index': i + 1,
        'path': slideFiles[i].name,
        'shapes': shapes,
        'notes': notes,
        'relationships': relationships,
      });
    }
    return DocumentParseResult(
        path: path,
        kind: OfficeDocumentKind.pptx,
        text: text.toString().trim(),
        structure: structure.toString(),
        metadata: {'canvas': canvas, 'slides': slideMetadata});
  }

  DocumentParseResult _parseVsdx(String path, List<int> bytes) {
    final archive = decodeZipBytes(bytes);
    final pagesXml = archiveText(archive, 'visio/pages/pages.xml');
    final pageRelationships =
        _partRelationships(archive, 'visio/pages/_rels/pages.xml.rels');
    final descriptors = <Map<String, String>>[];
    if (pagesXml != null) {
      final pages = XmlDocument.parse(pagesXml);
      for (final page in allElements(pages, 'Page')) {
        final relationshipId = _attributeLocal(page, 'id') ?? '';
        final target = pageRelationships[relationshipId]?['target'] ?? '';
        descriptors.add({
          'id': _attributeLocal(page, 'ID') ?? '',
          'name': _attributeLocal(page, 'Name') ??
              _attributeLocal(page, 'NameU') ??
              'Page ${descriptors.length + 1}',
          'relationship_id': relationshipId,
          'path': target,
          'background': _attributeLocal(page, 'Background') ?? '0',
        });
      }
    }
    if (descriptors.isEmpty) {
      final files = archive.files
          .where((file) =>
              file.isFile &&
              RegExp(r'^visio/pages/page\d+\.xml$', caseSensitive: false)
                  .hasMatch(file.name.replaceAll('\\', '/')))
          .toList()
        ..sort((a, b) => _naturalCompare(a.name, b.name));
      for (final file in files) {
        descriptors.add({
          'id': '${descriptors.length + 1}',
          'name': 'Page ${descriptors.length + 1}',
          'relationship_id': '',
          'path': file.name.replaceAll('\\', '/'),
          'background': '0',
        });
      }
    }

    final text = StringBuffer();
    final structure = StringBuffer()
      ..writeln('VSDX diagram package')
      ..writeln('pages=${descriptors.length}');
    final pageMetadata = <Map<String, Object?>>[];
    for (var pageIndex = 0; pageIndex < descriptors.length; pageIndex++) {
      final descriptor = descriptors[pageIndex];
      final pagePath = descriptor['path'] ?? '';
      final pageXml = archiveText(archive, pagePath);
      if (pageXml == null) {
        structure.writeln(
            'page_${pageIndex + 1}="${descriptor['name']}" missing_part="$pagePath"');
        continue;
      }
      final page = XmlDocument.parse(pageXml);
      final pageSheet = allElements(page, 'PageSheet').firstOrNull;
      final pageCells = _visioCells(pageSheet);
      final shapes = allElements(page, 'Shape')
          .map(_visioShapeInfo)
          .toList(growable: false);
      final connections = allElements(page, 'Connect')
          .map((connection) => <String, Object?>{
                'from_shape': _attributeLocal(connection, 'FromSheet'),
                'from_cell': _attributeLocal(connection, 'FromCell'),
                'from_part': _attributeLocal(connection, 'FromPart'),
                'to_shape': _attributeLocal(connection, 'ToSheet'),
                'to_cell': _attributeLocal(connection, 'ToCell'),
                'to_part': _attributeLocal(connection, 'ToPart'),
              })
          .toList(growable: false);
      structure.writeln(
          'page_${pageIndex + 1} id=${descriptor['id']} name="${descriptor['name']}" background=${descriptor['background']} width=${pageCells['PageWidth']} height=${pageCells['PageHeight']} shapes=${shapes.length} connections=${connections.length}');
      for (final shape in shapes.take(1000)) {
        structure.writeln(
            'page_${pageIndex + 1}_shape id=${shape['id']} parent=${shape['parent_id']} name="${_preview(shape['name']?.toString() ?? '')}" type=${shape['type']} pin_x=${shape['pin_x']} pin_y=${shape['pin_y']} width=${shape['width']} height=${shape['height']} angle=${shape['angle']} text="${_preview(shape['text']?.toString() ?? '')}"');
      }
      for (final connection in connections.take(1000)) {
        structure.writeln(
            'page_${pageIndex + 1}_connect from=${connection['from_shape']}:${connection['from_cell']} to=${connection['to_shape']}:${connection['to_cell']}');
      }
      text.writeln('## ${descriptor['name']}');
      for (final shape in shapes) {
        final value = shape['text']?.toString() ?? '';
        if (value.isNotEmpty) {
          text.writeln(
              '[shape ${shape['id']} at ${shape['pin_x']},${shape['pin_y']}] $value');
        }
      }
      text.writeln();
      pageMetadata.add({
        ...descriptor,
        'page_cells': pageCells,
        'shapes': shapes,
        'connections': connections,
      });
    }
    return DocumentParseResult(
      path: path,
      kind: OfficeDocumentKind.vsdx,
      text: text.toString().trim(),
      structure: structure.toString(),
      metadata: {'pages': pageMetadata},
    );
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

  Map<String, String> _docxStyleNames(Archive archive) {
    final xml = archiveText(archive, 'word/styles.xml');
    if (xml == null) return const {};
    final document = XmlDocument.parse(xml);
    final result = <String, String>{};
    for (final style in allElements(document, 'style')) {
      final id = _attributeLocal(style, 'styleId') ?? '';
      final name =
          _attributeLocal(allElements(style, 'name').firstOrNull, 'val') ?? id;
      if (id.isNotEmpty) result[id] = name;
    }
    return result;
  }

  List<Map<String, Object?>> _docxPartTexts(
      Archive archive, String partPrefix) {
    final result = <Map<String, Object?>>[];
    final files = archive.files
        .where((file) =>
            file.isFile &&
            file.name.startsWith(partPrefix) &&
            file.name.toLowerCase().endsWith('.xml'))
        .toList()
      ..sort((a, b) => _naturalCompare(a.name, b.name));
    for (final file in files) {
      final document =
          XmlDocument.parse(utf8.decode(file.content, allowMalformed: true));
      result.add({
        'path': file.name,
        'text': allElements(document, 'p')
            .map((paragraph) => elementText(paragraph, {'t'}))
            .where((value) => value.isNotEmpty)
            .join('\n'),
      });
    }
    return result;
  }

  int _headingLevel(String styleId, String styleName) {
    final combined = '$styleId $styleName'.toLowerCase();
    final match =
        RegExp(r'(?:heading|заголовок)\s*([1-6])').firstMatch(combined);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  List<Map<String, String>> _readWorkbookSheets(Archive archive) {
    final workbookXml = archiveText(archive, 'xl/workbook.xml');
    if (workbookXml == null) return const [];
    final relationships =
        _partRelationships(archive, 'xl/_rels/workbook.xml.rels');
    final workbook = XmlDocument.parse(workbookXml);
    final result = <Map<String, String>>[];
    for (final sheet in allElements(workbook, 'sheet')) {
      final relationshipId = _attributeLocal(sheet, 'id') ?? '';
      final target = relationships[relationshipId]?['target'] ?? '';
      result.add({
        'name': _attributeLocal(sheet, 'name') ?? 'Sheet ${result.length + 1}',
        'state': _attributeLocal(sheet, 'state') ?? 'visible',
        'relationship_id': relationshipId,
        'path': target,
      });
    }
    return result;
  }

  Map<String, Map<String, String>> _partRelationships(
      Archive archive, String relationshipPath) {
    final xml = archiveText(archive, relationshipPath);
    if (xml == null) return const {};
    final document = XmlDocument.parse(xml);
    final sourcePart = _sourcePartFromRelationships(relationshipPath);
    final sourceDirectory = sourcePart.contains('/')
        ? sourcePart.substring(0, sourcePart.lastIndexOf('/'))
        : '';
    final result = <String, Map<String, String>>{};
    for (final relationship in allElements(document, 'Relationship')) {
      final id = _attributeLocal(relationship, 'Id') ?? '';
      final rawTarget = _attributeLocal(relationship, 'Target') ?? '';
      if (id.isEmpty) continue;
      final external =
          (_attributeLocal(relationship, 'TargetMode') ?? '') == 'External';
      result[id] = {
        'type': _attributeLocal(relationship, 'Type') ?? '',
        'target': external
            ? rawTarget
            : _normalizePackagePath('$sourceDirectory/$rawTarget'),
        'target_mode': external ? 'External' : 'Internal',
      };
    }
    return result;
  }

  String _relationshipPartPath(String sourcePart) {
    final normalized = sourcePart.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    if (slash < 0) return '_rels/$normalized.rels';
    return '${normalized.substring(0, slash)}/_rels/${normalized.substring(slash + 1)}.rels';
  }

  String _sourcePartFromRelationships(String relationshipPath) {
    final normalized = relationshipPath.replaceAll('\\', '/');
    final marker = '/_rels/';
    final markerIndex = normalized.indexOf(marker);
    if (markerIndex < 0 || !normalized.endsWith('.rels')) return normalized;
    return '${normalized.substring(0, markerIndex)}/${normalized.substring(markerIndex + marker.length, normalized.length - 5)}';
  }

  String _normalizePackagePath(String path) {
    final segments = <String>[];
    for (final segment in path.replaceAll('\\', '/').split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (segments.isNotEmpty) segments.removeLast();
      } else {
        segments.add(segment);
      }
    }
    return segments.join('/');
  }

  Map<String, Object?> _pptxShapeInfo(
      XmlElement shape, Map<String, Map<String, String>> relationships) {
    final properties = allElements(shape, 'cNvPr').firstOrNull;
    final transform = allElements(shape, 'xfrm').firstOrNull;
    final offset =
        transform == null ? null : allElements(transform, 'off').firstOrNull;
    final extent =
        transform == null ? null : allElements(transform, 'ext').firstOrNull;
    final text = allElements(shape, 't')
        .map((element) => collapseWhitespace(element.innerText))
        .where((value) => value.isNotEmpty)
        .join('\n');
    final preset =
        _attributeLocal(allElements(shape, 'prstGeom').firstOrNull, 'prst') ??
            '';
    final relationshipIds = <String>[];
    for (final element in shape.descendants.whereType<XmlElement>()) {
      for (final attribute in element.attributes) {
        if (relationships.containsKey(attribute.value) &&
            !relationshipIds.contains(attribute.value)) {
          relationshipIds.add(attribute.value);
        }
      }
    }
    final targets = relationshipIds
        .map((id) => relationships[id]?['target'] ?? '')
        .where((target) => target.isNotEmpty)
        .toList(growable: false);
    return {
      'id': int.tryParse(_attributeLocal(properties, 'id') ?? ''),
      'name': _attributeLocal(properties, 'name') ?? '',
      'type': preset.isNotEmpty ? preset : shape.name.local,
      'x_emu': int.tryParse(_attributeLocal(offset, 'x') ?? ''),
      'y_emu': int.tryParse(_attributeLocal(offset, 'y') ?? ''),
      'width_emu': int.tryParse(_attributeLocal(extent, 'cx') ?? ''),
      'height_emu': int.tryParse(_attributeLocal(extent, 'cy') ?? ''),
      'rotation': int.tryParse(_attributeLocal(transform, 'rot') ?? ''),
      'text': text,
      'relationship_ids': relationshipIds,
      'relationship_target': targets.join(', '),
    };
  }

  Map<String, String> _visioCells(XmlElement? root) {
    if (root == null) return const {};
    final result = <String, String>{};
    for (final cell in allElements(root, 'Cell')) {
      final name = _attributeLocal(cell, 'N') ?? '';
      final value = _attributeLocal(cell, 'V') ??
          _attributeLocal(cell, 'F') ??
          cell.innerText.trim();
      if (name.isNotEmpty && value.isNotEmpty) result[name] = value;
    }
    return result;
  }

  Map<String, Object?> _visioShapeInfo(XmlElement shape) {
    final cells = _visioCells(shape);
    XmlElement? parentShape;
    XmlNode? current = shape.parent;
    while (current != null) {
      if (current is XmlElement && current.name.local == 'Shape') {
        parentShape = current;
        break;
      }
      current = current.parent;
    }
    final textElement = allElements(shape, 'Text').firstOrNull;
    final text = textElement == null
        ? ''
        : collapseWhitespace(textElement.descendants
            .whereType<XmlText>()
            .map((node) => node.value)
            .join());
    return {
      'id': int.tryParse(_attributeLocal(shape, 'ID') ?? ''),
      'parent_id': int.tryParse(_attributeLocal(parentShape, 'ID') ?? ''),
      'name': _attributeLocal(shape, 'Name') ??
          _attributeLocal(shape, 'NameU') ??
          '',
      'type': _attributeLocal(shape, 'Type') ?? 'Shape',
      'master_id': int.tryParse(_attributeLocal(shape, 'Master') ?? ''),
      'pin_x': cells['PinX'],
      'pin_y': cells['PinY'],
      'width': cells['Width'],
      'height': cells['Height'],
      'angle': cells['Angle'],
      'begin_x': cells['BeginX'],
      'begin_y': cells['BeginY'],
      'end_x': cells['EndX'],
      'end_y': cells['EndY'],
      'text': text,
      'cells': cells,
    };
  }

  Iterable<XmlElement> _directElements(XmlElement parent, String localName) =>
      parent.children
          .whereType<XmlElement>()
          .where((element) => element.name.local == localName);

  XmlElement? _directElement(XmlElement parent, String localName) =>
      _directElements(parent, localName).firstOrNull;

  String? _attributeLocal(XmlElement? element, String localName) {
    if (element == null) return null;
    for (final attribute in element.attributes) {
      if (attribute.name.local == localName) return attribute.value;
    }
    return null;
  }

  String _preview(String value, {int max = 180}) {
    final clean = value
        .replaceAll(RegExp(r'[\r\n\t ]+'), ' ')
        .replaceAll('"', '\\"')
        .trim();
    if (clean.length <= max) return clean;
    return '${clean.substring(0, max - 3)}...';
  }

  List<String> _readSharedStrings(Archive archive) {
    final xml = archiveText(archive, 'xl/sharedStrings.xml');
    if (xml == null) return const [];
    final document = XmlDocument.parse(xml);
    return allElements(document, 'si')
        .map((e) => allElements(e, 't').map((t) => t.innerText).join())
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

extension _IterableEnds<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
  E? get lastOrNull => isEmpty ? null : last;
}
