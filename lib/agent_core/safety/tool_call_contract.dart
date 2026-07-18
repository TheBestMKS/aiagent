import '../../utils/path_utils.dart';
import '../build/build_failure_analyzer.dart';

class ToolCallContractResolution {
  const ToolCallContractResolution({
    required this.call,
    required this.valid,
    this.repaired = false,
    this.message = '',
  });

  final ToolCall call;
  final bool valid;
  final bool repaired;
  final String message;
}

class ToolCallContract {
  const ToolCallContract._();

  static const Map<String, List<String>> _requiredArguments = {
    'set_task_plan': ['plan'],
    'read_file': ['path'],
    'write_file': ['path', 'content'],
    'create_file': ['path', 'content'],
    'append_file': ['path', 'content'],
    'replace_text': ['path', 'old_text', 'new_text'],
    'make_dir': ['path'],
    'delete_path': ['path'],
    'copy_path': ['from', 'to'],
    'move_path': ['from', 'to'],
    'run_command': ['command'],
    'terminal_write': ['session_id', 'input'],
    'terminal_read': ['session_id'],
    'terminal_close': ['session_id'],
    'inspect_zip': ['path'],
    'extract_zip': ['path', 'dest'],
    'download_to_project': ['url'],
    'download_to_tools': ['url'],
    'extract_zip_to_tools': ['path', 'dest'],
    'memory_recall': ['query'],
    'memory_remember': ['type', 'title', 'content'],
    'promote_golden_path': [
      'problem',
      'solution',
      'verification',
      'failed_approaches',
    ],
    'knowledge_search': ['query'],
    'knowledge_store': ['topic', 'content'],
  };

  static ToolCallContractResolution resolve(
    ToolCall original, {
    BuildFailureAnalysis? buildFailureAnalysis,
  }) {
    var call = original;
    var repaired = false;
    var repairMessage = '';
    final args = Map<String, dynamic>.from(original.args);

    if (original.name == 'replace_text' && _blank(args['path'])) {
      final inferred = _inferReplacePath(args, buildFailureAnalysis);
      if (inferred != null) {
        args['path'] = inferred;
        call = ToolCall(name: original.name, args: args);
        repaired = true;
        repairMessage =
            'TOOL_ARGUMENT_AUTO_REPAIRED: обязательный `path` однозначно '
            'восстановлен как `$inferred` по содержимому правки и диагностике.';
      }
    }

    final required = _requiredArguments[call.name] ?? const <String>[];
    final missing = <String>[];
    for (final key in required) {
      if (!call.args.containsKey(key)) {
        missing.add(key);
        continue;
      }
      if (_mustBeNonEmpty(key) && _blank(call.args[key])) missing.add(key);
    }

    final path = call.args['path']?.toString().trim() ?? '';
    if (const {'write_file', 'create_file', 'append_file', 'replace_text'}
            .contains(call.name) &&
        _looksLikeDirectoryPath(path)) {
      return ToolCallContractResolution(
        call: call,
        valid: false,
        message:
            'TOOL_ARGUMENT_VALIDATION_FAILED: `${call.name}` получил путь '
            '`$path`, похожий на каталог. Для каталога используй `make_dir`; '
            'для файла передай имя файла внутри каталога.',
      );
    }

    if (missing.isNotEmpty) {
      return ToolCallContractResolution(
        call: call,
        valid: false,
        message:
            'TOOL_ARGUMENT_VALIDATION_FAILED: инструмент `${call.name}` не '
            'выполнен, отсутствуют обязательные аргументы: '
            '${missing.map((item) => '`$item`').join(', ')}. Повтори один '
            'корректный tool-call с полным набором параметров.',
      );
    }

    return ToolCallContractResolution(
      call: call,
      valid: true,
      repaired: repaired,
      message: repairMessage,
    );
  }

  static String? _inferReplacePath(
    Map<String, dynamic> args,
    BuildFailureAnalysis? analysis,
  ) {
    final implicated = analysis?.implicatedFiles
            .map((item) => item.replaceAll('\\', '/').trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList(growable: false) ??
        const <String>[];
    if (implicated.length == 1 && _isBuildConfigurationFile(implicated.first)) {
      return implicated.first;
    }

    final content = '${args['old_text'] ?? ''}\n${args['new_text'] ?? ''}'
        .toLowerCase();
    if (content.contains('cmake_minimum_required') ||
        content.contains('find_package(') ||
        content.contains('target_link_libraries(') ||
        content.contains('target_include_directories(') ||
        content.contains('cmake_prefix_path') ||
        content.contains('add_executable(')) {
      return 'CMakeLists.txt';
    }
    return null;
  }

  static bool _isBuildConfigurationFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('cmakelists.txt') ||
        lower.endsWith('.cmake') ||
        lower.endsWith('meson.build') ||
        lower.endsWith('build.gradle') ||
        lower.endsWith('build.gradle.kts');
  }

  static bool _mustBeNonEmpty(String key) => const {
        'path',
        'from',
        'to',
        'command',
        'session_id',
        'input',
        'plan',
        'query',
        'url',
        'dest',
        'topic',
        'type',
        'title',
        'problem',
        'solution',
        'verification',
        'failed_approaches',
      }.contains(key);

  static bool _blank(Object? value) => value == null || value.toString().trim().isEmpty;

  static bool _looksLikeDirectoryPath(String path) {
    if (path.isEmpty) return false;
    return path.endsWith('/') || path.endsWith('\\');
  }
}
