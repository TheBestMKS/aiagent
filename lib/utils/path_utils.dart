import 'dart:async';
import 'dart:io';

class ToolCall {
  const ToolCall({required this.name, required this.args});
  final String name;
  final Map<String, dynamic> args;
}

class ExtractedFile {
  const ExtractedFile({required this.path, required this.content});
  final String path;
  final String content;
}

class TreeEntry {
  const TreeEntry(
      {required this.name,
      required this.relativePath,
      required this.isDirectory,
      required this.depth});
  final String name;
  final String relativePath;
  final bool isDirectory;
  final int depth;
}

int? firstInt(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null) return parsed;
  }
  return null;
}

String safeCurrentDirectoryPath() {
  try {
    return Directory.current.path;
  } catch (_) {
    return '';
  }
}

String resolveDefaultAppRootPath() {
  if (Platform.isAndroid) {
    return pathJoin(Directory.systemTemp.path, 'ii_agent_data');
  }
  try {
    return Directory.current.path;
  } catch (_) {
    return pathJoin(Directory.systemTemp.path, 'ii_agent_data');
  }
}

String pathJoin(String a, String b,
    [String? c, String? d, String? e, String? f, String? g, String? h]) {
  final parts = [
    a,
    b,
    if (c != null) c,
    if (d != null) d,
    if (e != null) e,
    if (f != null) f,
    if (g != null) g,
    if (h != null) h
  ];
  return parts.where((p) => p.isNotEmpty).join(Platform.pathSeparator);
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  final units = ['КБ', 'МБ', 'ГБ', 'ТБ'];
  var value = bytes / 1024.0;
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[index]}';
}

String pathBasename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
  return parts.isEmpty ? normalized : parts.last;
}

String pathDirname(String path) {
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  if (index <= 0) return '.';
  return normalized.substring(0, index);
}

String fileExtension(String path) {
  final name = pathBasename(path);
  final index = name.lastIndexOf('.');
  if (index <= 0 || index == name.length - 1) return '';
  return name.substring(index);
}

String pathRelative(String root, String child) {
  final normalizedRoot = root.replaceAll('\\', '/');
  final normalizedChild = child.replaceAll('\\', '/');
  if (normalizedChild.startsWith(normalizedRoot))
    return normalizedChild
        .substring(normalizedRoot.length)
        .replaceFirst(RegExp(r'^/'), '');
  return child;
}

String resolveProjectPath(String root, String relativePath) {
  final normalized = relativePath.replaceAll('\\', '/').trim();
  if (normalized.isEmpty) return root;
  final segments =
      normalized.split('/').where((part) => part.isNotEmpty).toList();
  if (segments.any((part) => part == '..'))
    throw ArgumentError('Parent paths are not allowed: $relativePath');
  if (isAbsolutePath(relativePath)) {
    final absolute = normalizePathForCompare(relativePath);
    final normalizedRoot = normalizePathForCompare(root);
    if (absolute == normalizedRoot || absolute.startsWith('$normalizedRoot/'))
      return relativePath;
    throw ArgumentError(
        'Absolute paths outside the project are not allowed for this tool: $relativePath');
  }
  return pathJoin(root, normalized.replaceAll('/', Platform.pathSeparator));
}

String normalizePathForCompare(String path) =>
    path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '').toLowerCase();

bool isAbsolutePath(String path) {
  if (path.startsWith('/') || path.startsWith('\\\\')) return true;
  return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path);
}

String sanitizeFileName(String value) {
  final result = value.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
  return result.isEmpty ? 'NewProject' : result;
}

String truncateMiddle(String text, int maxChars) {
  if (text.length <= maxChars) return text;
  final half = maxChars ~/ 2;
  return '${text.substring(0, half)}\n\n...[truncated ${text.length - maxChars} chars]...\n\n${text.substring(text.length - half)}';
}

Future<void> copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(recursive: false)) {
    final newPath = pathJoin(destination.path, pathBasename(entity.path));
    if (entity is Directory) {
      await copyDirectory(entity, Directory(newPath));
    } else if (entity is File) {
      await File(newPath).parent.create(recursive: true);
      await entity.copy(newPath);
    }
  }
}
