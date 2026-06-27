enum OfficeDocumentKind {
  rtf,
  docx,
  xlsx,
  pptx,
  odt,
  ods,
  odp,
  odc,
  plainText,
  unknown,
}

extension OfficeDocumentKindLabel on OfficeDocumentKind {
  String get label => switch (this) {
        OfficeDocumentKind.rtf => 'RTF',
        OfficeDocumentKind.docx => 'DOCX',
        OfficeDocumentKind.xlsx => 'XLSX',
        OfficeDocumentKind.pptx => 'PPTX',
        OfficeDocumentKind.odt => 'ODT',
        OfficeDocumentKind.ods => 'ODS',
        OfficeDocumentKind.odp => 'ODP',
        OfficeDocumentKind.odc => 'ODC',
        OfficeDocumentKind.plainText => 'TEXT',
        OfficeDocumentKind.unknown => 'UNKNOWN',
      };
}

class DocumentParseResult {
  const DocumentParseResult({
    required this.path,
    required this.kind,
    required this.text,
    required this.structure,
    this.metadata = const {},
  });

  final String path;
  final OfficeDocumentKind kind;
  final String text;
  final String structure;
  final Map<String, Object?> metadata;

  String toAgentText({int maxTextChars = 30000}) {
    final clippedText = text.length <= maxTextChars
        ? text
        : '${text.substring(0, maxTextChars ~/ 2)}\n...[middle truncated]...\n${text.substring(text.length - maxTextChars ~/ 2)}';
    final buffer = StringBuffer()
      ..writeln('DOCUMENT: $path')
      ..writeln('FORMAT: ${kind.label}')
      ..writeln('STRUCTURE:')
      ..writeln(
          structure.trim().isEmpty ? '(empty structure)' : structure.trim())
      ..writeln('TEXT:')
      ..writeln(clippedText.trim());
    return buffer.toString().trimRight();
  }
}

class DocumentBuildResult {
  const DocumentBuildResult({
    required this.path,
    required this.kind,
    required this.bytes,
    required this.message,
  });

  final String path;
  final OfficeDocumentKind kind;
  final int bytes;
  final String message;
}

enum DocumentEditMode {
  replaceAll,
  appendText,
  prependText,
  replaceText,
}

class DocumentEditResult {
  const DocumentEditResult({
    required this.path,
    required this.kind,
    required this.changed,
    required this.message,
  });

  final String path;
  final OfficeDocumentKind kind;
  final bool changed;
  final String message;
}
