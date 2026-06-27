import 'document_models.dart';
import 'document_parsers.dart';

class SpreadsheetCell {
  const SpreadsheetCell({
    required this.row,
    required this.column,
    required this.value,
    this.formula = '',
  });

  final int row;
  final int column;
  final String value;
  final String formula;
}

class SpreadsheetSheetView {
  const SpreadsheetSheetView({
    required this.name,
    required this.rows,
  });

  final String name;
  final List<List<SpreadsheetCell>> rows;
}

class SpreadsheetViewModel {
  const SpreadsheetViewModel({
    required this.path,
    required this.kind,
    required this.sheets,
    required this.structure,
  });

  final String path;
  final OfficeDocumentKind kind;
  final List<SpreadsheetSheetView> sheets;
  final String structure;
}

class SpreadsheetViewEngine {
  const SpreadsheetViewEngine({this.parser = const OfficeDocumentParser()});

  final OfficeDocumentParser parser;

  Future<SpreadsheetViewModel> load(String path) async {
    final parsed = await parser.parseFile(path);
    return fromParseResult(parsed);
  }

  SpreadsheetViewModel fromParseResult(DocumentParseResult parsed) {
    final sheets = <SpreadsheetSheetView>[];
    final sections = parsed.text.split(RegExp(r'^##\s+', multiLine: true));
    for (final section in sections) {
      final trimmed = section.trim();
      if (trimmed.isEmpty) continue;
      final lines = trimmed.split(RegExp(r'\r?\n'));
      final name = lines.first.trim().isEmpty
          ? 'Sheet ${sheets.length + 1}'
          : lines.first.trim();
      final rows = <List<SpreadsheetCell>>[];
      for (var r = 1; r < lines.length; r++) {
        final rawCells = lines[r].split('\t');
        if (rawCells.every((cell) => cell.trim().isEmpty)) continue;
        rows.add([
          for (var c = 0; c < rawCells.length; c++)
            SpreadsheetCell(
              row: rows.length,
              column: c,
              value: _evaluateLiteral(rawCells[c].trim()),
              formula:
                  rawCells[c].trim().startsWith('=') ? rawCells[c].trim() : '',
            )
        ]);
      }
      sheets.add(SpreadsheetSheetView(name: name, rows: rows));
    }
    if (sheets.isEmpty) {
      final rows = parsed.text
          .split(RegExp(r'\r?\n'))
          .where((line) => line.trim().isNotEmpty)
          .map((line) => line.split(RegExp(r'[\t;,]')))
          .map((cells) => [
                for (var c = 0; c < cells.length; c++)
                  SpreadsheetCell(row: 0, column: c, value: cells[c].trim())
              ])
          .toList();
      sheets.add(SpreadsheetSheetView(name: 'Sheet 1', rows: rows));
    }
    return SpreadsheetViewModel(
      path: parsed.path,
      kind: parsed.kind,
      sheets: sheets,
      structure: parsed.structure,
    );
  }

  String _evaluateLiteral(String value) {
    if (!value.startsWith('=')) return value;
    final body = value.substring(1);
    final sum = RegExp(r'^SUM\(([-0-9.,;\s]+)\)$', caseSensitive: false)
        .firstMatch(body);
    if (sum != null) {
      final total = sum
          .group(1)!
          .split(RegExp(r'[;,\s]+'))
          .map((item) => num.tryParse(item.trim()) ?? 0)
          .fold<num>(0, (a, b) => a + b);
      return total.toString();
    }
    final simple =
        RegExp(r'^\s*(-?\d+(?:\.\d+)?)\s*([+\-*/])\s*(-?\d+(?:\.\d+)?)\s*$')
            .firstMatch(body);
    if (simple == null) return value;
    final a = num.parse(simple.group(1)!);
    final b = num.parse(simple.group(3)!);
    return switch (simple.group(2)) {
      '+' => (a + b).toString(),
      '-' => (a - b).toString(),
      '*' => (a * b).toString(),
      '/' => b == 0 ? '#DIV/0!' : (a / b).toString(),
      _ => value,
    };
  }
}
