class ToolCallJsonRepair {
  const ToolCallJsonRepair._();

  static String removeTrailingCommas(String source) {
    final output = StringBuffer();
    var inString = false;
    var escaping = false;
    for (var index = 0; index < source.length; index++) {
      final char = source[index];
      if (inString) {
        output.write(char);
        if (escaping) {
          escaping = false;
        } else if (char == r'\') {
          escaping = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
        output.write(char);
        continue;
      }
      if (char == ',') {
        var lookahead = index + 1;
        while (lookahead < source.length &&
            _isJsonWhitespace(source.codeUnitAt(lookahead))) {
          lookahead++;
        }
        if (lookahead < source.length &&
            (source[lookahead] == '}' || source[lookahead] == ']')) {
          continue;
        }
      }
      output.write(char);
    }
    return output.toString();
  }

  static bool _isJsonWhitespace(int codeUnit) =>
      codeUnit == 0x20 || codeUnit == 0x09 || codeUnit == 0x0A || codeUnit == 0x0D;
}
