class ToolOutputCompactor {
  const ToolOutputCompactor({this.maxChars = 24000});

  final int maxChars;

  String compact(String toolName, String output) {
    if (output.length <= maxChars) return output;
    final lines = output.split(RegExp(r'\r?\n'));
    final signals = <String>[];
    final signalPattern = RegExp(
      r'(error|exception|failed|warning|exit_code|full_output_log|created|wrote|deleted|updated|artifact|permission|denied|timeout|not found)',
      caseSensitive: false,
    );
    for (final line in lines) {
      if (signalPattern.hasMatch(line) && line.trim().isNotEmpty) {
        signals.add(line);
        if (signals.length >= 160) break;
      }
    }
    final headLength = (maxChars * 0.28).round();
    final tailLength = (maxChars * 0.46).round();
    final head = output.substring(0, headLength.clamp(0, output.length).toInt());
    final tailStart = (output.length - tailLength).clamp(0, output.length).toInt();
    final tail = output.substring(tailStart);
    final signalText = signals.join('\n');
    return '''[TOOL_OUTPUT_COMPACTED]
Tool: $toolName
Original characters: ${output.length}
The full result remains in persistent command/action logs. Important lines and the beginning/end are preserved below.

[IMPORTANT_LINES]
$signalText
[/IMPORTANT_LINES]

[BEGINNING]
$head
[/BEGINNING]

[END]
$tail
[/END]
[/TOOL_OUTPUT_COMPACTED]''';
  }
}
