import 'dart:convert';
import 'dart:io';

String decodeProcessOutput(Object? value) {
  if (value == null) return '';
  if (value is! List<int>) return value.toString();
  if (value.isEmpty) return '';
  final candidates = <String>[];
  void addCandidate(String text) {
    if (!candidates.contains(text)) candidates.add(text);
  }

  if (Platform.isWindows) addCandidate(decodeCp866(value));
  try {
    addCandidate(utf8.decode(value, allowMalformed: false));
  } catch (_) {
    addCandidate(utf8.decode(value, allowMalformed: true));
  }
  try {
    addCandidate(systemEncoding.decode(value));
  } catch (_) {}
  candidates
      .sort((a, b) => decodeQualityScore(b).compareTo(decodeQualityScore(a)));
  return candidates.first;
}

String decodeCp866(List<int> bytes) {
  const table =
      'АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдежзийклмноп░▒▓│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀рстуфхцчшщъыьэюяЁёЄєЇїЎў°∙·√№¤■ ';
  final buffer = StringBuffer();
  for (final byte in bytes) {
    final b = byte & 0xff;
    if (b < 0x80) {
      buffer.writeCharCode(b);
    } else {
      buffer.write(table[b - 0x80]);
    }
  }
  return buffer.toString();
}

int decodeQualityScore(String text) {
  var score = 0;
  for (final rune in text.runes) {
    if (rune == 0xfffd) score -= 200;
    if ((rune >= 0x0410 && rune <= 0x044f) || rune == 0x0401 || rune == 0x0451)
      score += 3;
    if ((rune >= 0x2500 && rune <= 0x259f)) score -= 5;
  }
  const mojibake = ['­', 'Ґ', 'ў', 'Є', '®', '¬', 'Ї'];
  for (final marker in mojibake) {
    score -= marker.allMatches(text).length * 4;
  }
  final lower = text.toLowerCase();
  if (lower.contains('не является внутренней') ||
      lower.contains('не является внешней')) score += 500;
  if (lower.contains('not recognized as an internal or external command'))
    score += 500;
  if (lower.contains('command not found')) score += 300;
  return score;
}

bool isCompilerOrBuildCommand(String command) {
  final trimmed = command.trim().toLowerCase();
  final normalized = trimmed.replaceAll('\\', '/');
  final tools = [
    'g++',
    'g++.exe',
    'clang++',
    'clang++.exe',
    'cl',
    'cl.exe',
    'gcc',
    'gcc.exe',
    'cmake',
    'cmake.exe',
    'ninja',
    'ninja.exe',
    'make',
    'make.exe',
    'msbuild',
    'msbuild.exe'
  ];
  return tools.any((name) =>
      normalized == name ||
      normalized.startsWith('$name ') ||
      normalized.contains('/$name '));
}

bool isMissingPythonModuleOutput(String output) {
  final lower = output.toLowerCase();
  return lower.contains('modulenotfounderror') &&
      lower.contains('no module named');
}

List<String> missingPythonModules(String output) {
  final found = <String>{};
  final patterns = [
    RegExp(r'''No module named ['\"]([^'\"]+)['\"]''', caseSensitive: false),
    RegExp(r'''ModuleNotFoundError:\s*No module named ['\"]([^'\"]+)['\"]''',
        caseSensitive: false),
  ];
  for (final pattern in patterns) {
    for (final match in pattern.allMatches(output)) {
      final raw = match.group(1)?.trim() ?? '';
      if (raw.isEmpty) continue;
      found.add(raw.split('.').first);
    }
  }
  return found.toList(growable: false);
}

String pythonModuleToPackageName(String module) {
  final normalized = module.trim();
  switch (normalized.toLowerCase()) {
    case 'cv2':
      return 'opencv-python';
    case 'pil':
      return 'pillow';
    case 'sklearn':
      return 'scikit-learn';
    case 'yaml':
      return 'pyyaml';
    case 'bs4':
      return 'beautifulsoup4';
    case 'serial':
      return 'pyserial';
    default:
      return normalized;
  }
}

bool isBuildConfigurationProblemOutput(String output) {
  final lower = output.toLowerCase();
  return lower.contains('does not appear to contain cmakelists.txt') ||
      lower.contains('cannot find source file') ||
      lower.contains('no sources given to target') ||
      lower.contains('cmake generate step failed') ||
      (lower.contains('cmakelists.txt') &&
          lower.contains('add_executable') &&
          lower.contains('source'));
}

bool isEnvironmentProblemOutput(String output) {
  final lower = output.toLowerCase();
  return lower.contains('not recognized as an internal or external command') ||
      lower.contains('не является внутренней') ||
      lower.contains('не является внешней') ||
      lower.contains('command not found') ||
      lower.contains('compiler not found') ||
      lower.contains('c++ compiler not found') ||
      lower.contains('modulenotfounderror') ||
      lower.contains('no module named') ||
      (lower.contains('no such file or directory') &&
          (lower.contains('g++') ||
              lower.contains('cl.exe') ||
              lower.contains('clang++') ||
              lower.contains('cmake')));
}

int? findFirstIntDeep(Object? value, List<String> keys) {
  final wanted = keys.map((k) => k.toLowerCase()).toSet();
  int? visit(Object? node) {
    if (node is Map) {
      for (final entry in node.entries) {
        final key = entry.key.toString().toLowerCase();
        if (wanted.contains(key)) {
          final parsed = int.tryParse(entry.value?.toString() ?? '');
          if (parsed != null) return parsed;
        }
      }
      for (final entry in node.entries) {
        final found = visit(entry.value);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final item in node) {
        final found = visit(item);
        if (found != null) return found;
      }
    }
    return null;
  }

  return visit(value);
}
