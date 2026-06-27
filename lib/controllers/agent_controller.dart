import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../core/app_constants.dart';
import '../core/models.dart';
import '../core/runtime_types.dart';
import '../document_tools/office_document_tools.dart' as office;
import '../utils/path_utils.dart';
import '../utils/process_utils.dart';

class AgentController {
  Directory projectsRoot = Directory('Projects');
  Directory configRoot = Directory('config');
  Directory distribRoot = Directory('distrib');
  Directory toolsRoot = Directory('tools');
  Directory get downloadsRoot =>
      Directory(pathJoin(toolsRoot.path, 'downloads'));
  String appRootPath = Directory.current.path;
  bool initializationStarted = false;
  bool initializationFinished = false;
  bool initializationFailed = false;
  String initializationError = '';
  List<ProjectInfo> projects = [];
  ProjectInfo? currentProject;
  ProjectInfo? pendingProjectOpenAfterTask;
  List<ChatMessage> messages = [];
  List<ModelProfile> profiles = [];
  String selectedProfileId = '';
  List<AvailableModel> availableModels = [];
  String status = 'Готово';
  bool busy = false;
  bool cancelRequested = false;
  int visibleExchangeCount = 10;
  int maxContextTokens = 8192;
  int maxOutputTokens = 4096;
  int estimatedContextTokens = 0;
  int maxAgentIterations = 120;
  bool loggingEnabled = true;
  bool qualityCheckEnabled = true;
  bool editorWordWrap = false;
  String appLanguage = 'ru';
  double uiScale = 1.0;
  bool allowInternetUse = true;
  bool allowComputerSearch = false;
  bool allowDeviceFileAccess = false;
  bool allowFollowUpSuggestions = true;
  bool closeToTrayOnClose = true;
  bool trayNotificationsEnabled = true;
  bool llamaProcessLoggingEnabled = true;
  bool isolatedToolsEnabled = true;
  List<EmailAccountConfig> emailAccounts = [];
  List<ApiOutputTemplate> apiOutputTemplates = [
    ApiOutputTemplate.telegramExample()
  ];
  List<AgentTriggerConfig> triggers = [];
  List<AgentScheduleConfig> schedules = [];
  List<IndexLocationConfig> indexLocations = [];
  List<CustomAgentToolConfig> customTools = [];
  List<ScheduledTaskRunRecord> scheduledTaskRuns = [];
  bool defaultAllowInternetUse = true;
  bool defaultAllowComputerSearch = false;
  bool defaultAllowDeviceFileAccess = false;
  bool defaultAllowFollowUpSuggestions = true;
  PermissionMode defaultPermissionMode = PermissionMode.askEveryAction;
  CreationMode defaultCreationMode = CreationMode.autoComplexity;
  String permissionStatusText = '';
  VoidCallback? appUpdater;
  PermissionMode permissionMode = PermissionMode.askEveryAction;
  CreationMode creationMode = CreationMode.autoComplexity;
  String lastToolName = '';
  String lastToolResultText = '';
  void Function(String url)? webOpener;
  void Function(String url)? openUrlInWebTab;
  String? pendingWebUrl;
  final List<String> attachedFiles = [];
  final List<String> selectedLocations = [];
  String lastDeviceDirectoryPath = '';
  final List<String> executionLog = [];
  Process? llamaServerProcess;
  int? llamaServerPid;
  Timer? llamaMemoryTimer;
  String llamaMemoryStatus = '';
  File? currentLlamaLogFile;
  File? currentRunLogFile;
  File? currentLatestLogFile;
  File? currentActionLogFile;
  Future<bool> Function(AgentPermissionRequest request)? permissionApprover;
  String activeTaskText = '';
  int taskToolActions = 0;
  int taskFileMutations = 0;
  int taskCommandRuns = 0;
  int taskFailedCommands = 0;
  int? lastCommandExitCode;
  String lastCommandText = '';
  String lastCommandResultText = '';
  String? liveProgressMessageId;
  String? expandedDiffKey;
  String? expandedActionKey;
  String? expandedCodeBlockKey;
  VoidCallback? uiUpdater;
  String lastModelFinishReason = '';
  final List<FileChangeSummary> pendingFileChanges = [];
  final List<FileChangeSummary> taskFileChanges = [];
  final Map<String, AgentActionSummary> taskActionSummaries = {};
  List<LocalToolInfo>? cachedLocalTools;
  DateTime? cachedLocalToolsAt;
  bool projectLoading = false;
  final Map<String, RuntimeModelLimits> runtimeLimitsCache = {};
  bool lastContextMismatch = false;
  String lastContextMismatchDetails = '';
  String? lastContextCompressionBoundaryId;
  int problemSolvingAttempts = 0;
  int autoRecoveryAttempts = 0;
  int taskInternetActions = 0;
  String lastFinalAnswerQualityIssue = '';
  final List<ConsoleQuickAction> generatedConsoleQuickActions = [];
  final Map<String, int> taskFileMutationAttempts = {};
  void Function({required String command, String cwd, bool newTab})?
      consoleRunner;
  ConsoleRunRequest? pendingConsoleRun;

  void log(String message) {
    if (!loggingEnabled) return;
    final time = DateTime.now().toIso8601String();
    final line = '[$time] $message';
    executionLog.add(line);
    if (executionLog.length > 4000) {
      executionLog.removeRange(0, executionLog.length - 4000);
    }
    try {
      currentRunLogFile?.writeAsStringSync('$line\n',
          mode: FileMode.append, encoding: utf8);
      currentLatestLogFile?.writeAsStringSync('$line\n',
          mode: FileMode.append, encoding: utf8);
    } catch (_) {
      // Logging must never break agent execution.
    }
  }

  void clearExecutionLog() {
    executionLog.clear();
    log('LOG CLEAR: in-memory log cleared by user. Persistent log files are preserved.');
  }

  void requestStop() {
    cancelRequested = true;
    status = 'Остановка агента...';
    log('AGENT STOP REQUESTED BY USER');
    logAction('agent_stop_requested', {'state': taskStateJson()});
    notifyUi();
  }

  void setupProjectLogging(ProjectInfo project) {
    try {
      final logsDir = Directory(pathJoin(project.path, '.cppagent', 'logs'));
      logsDir.createSync(recursive: true);
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      currentRunLogFile = File(pathJoin(logsDir.path, '$stamp.log'));
      currentLatestLogFile = File(pathJoin(logsDir.path, 'latest.log'));
      currentActionLogFile = File(pathJoin(logsDir.path, 'actions.jsonl'));
      currentLatestLogFile!.writeAsStringSync('', encoding: utf8);
      currentRunLogFile!.writeAsStringSync(
          '$appName persistent log\nProject: ${project.path}\nStarted: $stamp\n\n',
          encoding: utf8);
      currentLatestLogFile!.writeAsStringSync(
          '$appName latest log\nProject: ${project.path}\nStarted: $stamp\n\n',
          encoding: utf8);
      logAction('project_log_opened',
          {'project': project.path, 'log': currentRunLogFile!.path});
    } catch (error) {
      executionLog
          .add('[${DateTime.now().toIso8601String()}] LOG FILE ERROR: $error');
    }
  }

  void logAction(String action, Map<String, Object?> data) {
    final payload = <String, Object?>{
      'time': DateTime.now().toIso8601String(),
      'project': currentProject?.path,
      'action': action,
      ...data,
    };
    final encoded = jsonEncode(payload);
    try {
      currentActionLogFile?.writeAsStringSync('$encoded\n',
          mode: FileMode.append, encoding: utf8);
    } catch (_) {
      // Action logging is best-effort, but never blocks tool execution.
    }
  }

  void addAttachment(String path) {
    if (!attachedFiles.contains(path)) {
      attachedFiles.add(path);
      log('ATTACHMENT ADD: $path');
    }
  }

  void removeAttachment(String path) {
    attachedFiles.remove(path);
    log('ATTACHMENT REMOVE: $path');
  }

  void addSelectedLocation(String path) {
    final clean = path.trim();
    if (clean.isEmpty) return;
    if (!selectedLocations.contains(clean)) selectedLocations.add(clean);
    lastDeviceDirectoryPath = clean;
    log('SELECTED_LOCATION ADD: $clean');
  }

  void removeSelectedLocation(String path) {
    selectedLocations.remove(path);
    log('SELECTED_LOCATION REMOVE: $path');
  }

  String fullDialogText() =>
      messages.where((m) => !m.internal && !m.transient).map((m) {
        if (m.role == 'separator') return '--- ${m.content} ---';
        return '${m.role}:\n${m.content}';
      }).join('\n\n---\n\n');

  Future<void> logStartupLlamaScan() async {
    final root = Directory.current.path;
    final checkDirs = [
      pathJoin(root, 'llama.cpp', 'cuda'),
      pathJoin(root, 'llama.cpp', 'vulkan'),
      pathJoin(root, 'llama.cpp', 'cpu'),
      pathJoin(root, 'tooling', 'llama.cpp', 'cuda'),
      pathJoin(root, 'tooling', 'llama.cpp', 'vulkan'),
      pathJoin(root, 'tooling', 'llama.cpp', 'cpu'),
    ];
    for (final dir in checkDirs) {
      log('CHECK llama.cpp folder: $dir => ${Directory(dir).existsSync() ? 'exists' : 'missing'}');
    }
    final modelDirs = [
      pathJoin(root, 'models'),
      pathJoin(root, 'tooling', 'models'),
      pathJoin(root, 'llama.cpp', 'models'),
      pathJoin(root, 'tooling', 'llama.cpp', 'models'),
    ];
    for (final dir in modelDirs) {
      final exists = Directory(dir).existsSync();
      var count = 0;
      if (exists) {
        count = Directory(dir)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.gguf'))
            .length;
      }
      log('CHECK models folder: $dir => ${exists ? 'exists' : 'missing'}, gguf=$count');
    }
  }

  ModelProfile? get currentProfile {
    for (final profile in profiles) {
      if (profile.id == selectedProfileId) return profile;
    }
    return profiles.isEmpty ? null : profiles.first;
  }

  String? get currentModelNameOrNull {
    final profile = currentProfile;
    if (profile == null || profile.model.isEmpty) return null;
    if (availableModels.any((m) => m.name == profile.model))
      return profile.model;
    if (availableModels.isEmpty) return null;
    return availableModels.first.name;
  }

  List<ChatMessage> get visibleMessages {
    // В окне диалога показывается вся публичная история, но одинаковые/циклические ответы
    // модели о компиляции, запуске и ошибках окружения сворачиваются в один блок.
    final publicMessages =
        messages.where((m) => !m.internal).toList(growable: false);
    final compacted = compactRepeatedPublicMessages(publicMessages);
    compacted.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return List.unmodifiable(compacted);
  }

  List<ChatMessage> compactRepeatedPublicMessages(List<ChatMessage> source) {
    final result = <ChatMessage>[];
    var i = 0;
    while (i < source.length) {
      final first = source[i];
      final category = repeatedAssistantMessageCategory(first);
      if (category == null) {
        result.add(first);
        i++;
        continue;
      }
      final group = <ChatMessage>[first];
      var j = i + 1;
      while (j < source.length) {
        final next = source[j];
        final nextCategory = repeatedAssistantMessageCategory(next);
        if (nextCategory != category) break;
        group.add(next);
        j++;
      }
      if (group.length < 2) {
        result.add(first);
      } else {
        result.add(buildRepeatedAssistantGroupMessage(category, group));
      }
      i = j;
    }
    return result;
  }

  String? repeatedAssistantMessageCategory(ChatMessage message) {
    if (message.role != 'assistant' ||
        message.content.trim().isEmpty ||
        message.role == 'separator') return null;
    final lower = message.content.toLowerCase();
    if (lower.contains('застряли в цикле ошибок компиляции') ||
        lower.contains('цикл ошибок компиляции') ||
        lower.contains('build_artifact_missing') ||
        lower.contains('exit code 2') ||
        lower.contains('exit code 1') ||
        lower.contains('run_command') ||
        lower.contains('cmd') && lower.contains('компил') ||
        lower.contains('компиляц') && lower.contains('исчерпал')) {
      return 'compile_attempt';
    }
    if (lower.contains('socketexception') ||
        lower.contains('failed to load model') ||
        lower.contains('http 400') ||
        lower.contains('ошибка агента:')) {
      return 'model_connection';
    }
    return null;
  }

  ChatMessage buildRepeatedAssistantGroupMessage(
      String category, List<ChatMessage> group) {
    final title = switch (category) {
      'compile_attempt' => 'Попытка компиляции',
      'model_connection' => 'Ошибки подключения к модели',
      _ => 'Повторяющиеся сообщения',
    };
    final content = switch (category) {
      'compile_attempt' =>
        'Повторяющиеся сообщения о компиляции/запуске объединены в скрытый блок. Сообщений: ${group.length}.',
      'model_connection' =>
        'Повторяющиеся сообщения об ошибках подключения к модели объединены в скрытый блок. Сообщений: ${group.length}.',
      _ =>
        'Повторяющиеся сообщения объединены в скрытый блок. Сообщений: ${group.length}.',
    };
    final attempts = <AgentActionAttempt>[];
    for (final message in group) {
      attempts.add(AgentActionAttempt(
        timestamp: message.createdAt.toIso8601String(),
        result: message.content,
        success: false,
      ));
    }
    return ChatMessage(
      role: 'assistant',
      id: 'compact_${category}_${group.first.id}_${group.length}',
      content: content,
      createdAt: group.first.createdAt,
      updatedAt:
          group.map((m) => m.updatedAt).reduce((a, b) => a.isAfter(b) ? a : b),
      actionSummaries: [
        AgentActionSummary(
          key: 'compact_$category',
          title: title,
          firstSeen: group.first.createdAt.microsecondsSinceEpoch,
          attempts: attempts,
        ),
      ],
    );
  }

  void notifyUi() {
    try {
      uiUpdater?.call();
    } catch (_) {
      // UI updates are best-effort and must not break the agent.
    }
  }

  void notifyAppUi() {
    try {
      appUpdater?.call();
    } catch (_) {}
    notifyUi();
  }

  double effectiveUiScale(double shortestSide) {
    final auto = Platform.isAndroid
        ? (shortestSide < 380
            ? 0.78
            : shortestSide < 520
                ? 0.86
                : 0.92)
        : 1.0;
    return (uiScale * auto).clamp(0.60, 1.35).toDouble();
  }

  void requestConsoleRun(
      {required String command, String cwd = '.', bool newTab = true}) {
    final runner = consoleRunner;
    if (runner != null) {
      runner(command: command, cwd: cwd, newTab: newTab);
    } else {
      pendingConsoleRun =
          ConsoleRunRequest(command: command, cwd: cwd, newTab: newTab);
    }
    notifyUi();
  }

  ConsoleRunRequest? takePendingConsoleRun() {
    final request = pendingConsoleRun;
    pendingConsoleRun = null;
    return request;
  }

  void requestOpenWebUrl(String url) {
    final clean = url.trim();
    if (clean.isEmpty) return;
    final opener = webOpener;
    if (opener != null) {
      opener(clean);
    } else {
      pendingWebUrl = clean;
    }
    notifyUi();
  }

  String? takePendingWebUrl() {
    final url = pendingWebUrl;
    pendingWebUrl = null;
    return url;
  }

  Future<Map<String, dynamic>> loadProjectUiStateSection(String section) async {
    final project = currentProject;
    if (project == null) return const <String, dynamic>{};
    try {
      final file = File(pathJoin(project.path, '.cppagent', 'ui_state.json'));
      if (!await file.exists()) return const <String, dynamic>{};
      final data = jsonDecode(await file.readAsString(encoding: utf8));
      if (data is! Map) return const <String, dynamic>{};
      final sectionData = data[section];
      if (sectionData is! Map) return const <String, dynamic>{};
      return sectionData.map((key, value) => MapEntry(key.toString(), value));
    } catch (e) {
      log('PROJECT UI STATE LOAD ERROR: section=$section error=$e');
      return const <String, dynamic>{};
    }
  }

  Future<void> saveProjectUiStateSection(
      String section, Map<String, dynamic> sectionData) async {
    final project = currentProject;
    if (project == null) return;
    try {
      final dir = Directory(pathJoin(project.path, '.cppagent'));
      await dir.create(recursive: true);
      final file = File(pathJoin(dir.path, 'ui_state.json'));
      final data = <String, dynamic>{};
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString(encoding: utf8));
        if (decoded is Map) {
          data.addAll(
              decoded.map((key, value) => MapEntry(key.toString(), value)));
        }
      }
      data[section] = sectionData;
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data),
          encoding: utf8);
    } catch (e) {
      log('PROJECT UI STATE SAVE ERROR: section=$section error=$e');
    }
  }

  Future<void> openExternalUrl(String url) async {
    final clean = url.trim();
    if (clean.isEmpty) return;
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/d', '/c', 'start', '', clean],
            runInShell: false);
      } else if (Platform.isAndroid) {
        await Process.run(
            '/system/bin/sh',
            [
              '-c',
              'am start -a android.intent.action.VIEW -d ${quoteShellArg(clean)}'
            ],
            runInShell: false);
      } else if (Platform.isMacOS) {
        await Process.run('open', [clean], runInShell: false);
      } else {
        await Process.run('xdg-open', [clean], runInShell: false);
      }
    } catch (e) {
      log('OPEN EXTERNAL URL ERROR: $clean: $e');
    }
  }

  void ensureConsoleQuickLaunch(String name, String command,
      {String cwd = '.'}) {
    final cleanCommand = command.trim();
    if (cleanCommand.isEmpty) return;
    final exists = generatedConsoleQuickActions
        .any((a) => a.command == cleanCommand && a.cwd == cwd);
    if (!exists) {
      generatedConsoleQuickActions
          .add(ConsoleQuickAction(name, cleanCommand, cwd: cwd));
      log('CONSOLE QUICK LAUNCH ADD: $name => $cleanCommand cwd=$cwd');
      notifyUi();
    }
  }

  final List<WebQuickAction> generatedWebQuickActions = [];

  void ensureWebQuickLaunch(String name, String url) {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;
    final exists = generatedWebQuickActions.any((a) => a.url == cleanUrl);
    if (!exists) {
      generatedWebQuickActions.add(WebQuickAction(name, cleanUrl));
      log('WEB QUICK LAUNCH ADD: $name => $cleanUrl');
      notifyUi();
    }
  }

  bool isRunnableProjectFile(String relativePath) {
    final lower = relativePath.toLowerCase();
    if (Platform.isWindows)
      return lower.endsWith('.exe') ||
          lower.endsWith('.bat') ||
          lower.endsWith('.cmd');
    return lower.endsWith('.sh') ||
        lower.endsWith('.run') ||
        !lower.contains('.');
  }

  String commandForProjectExecutable(String relativePath) {
    final path = Platform.isWindows
        ? relativePath.replaceAll('/', '\\')
        : relativePath.replaceAll('\\', '/');
    return quoteShellArg(path);
  }

  Future<void> startLiveProgress(String text) async {
    final id = 'progress_${DateTime.now().microsecondsSinceEpoch}';
    liveProgressMessageId = id;
    messages.add(
        ChatMessage(role: 'assistant', content: text, id: id, transient: true));
    notifyUi();
  }

  Future<void> ensureLiveProgress(String text) async {
    if (liveProgressMessageId == null) {
      await startLiveProgress(text);
    } else {
      await updateLiveProgress(text);
    }
  }

  Future<void> updateLiveProgress(String text) async {
    final id = liveProgressMessageId;
    if (id == null) return;
    final index = messages.indexWhere((m) => m.id == id);
    if (index < 0) return;
    messages[index] = messages[index]
        .copyWith(content: text, actionSummaries: currentActionSummaries());
    notifyUi();
  }

  List<AgentActionSummary> currentActionSummaries() {
    final values = taskActionSummaries.values.toList(growable: false);
    values.sort((a, b) => a.firstSeen.compareTo(b.firstSeen));
    return values;
  }

  void refreshLiveProgressActions() {
    final id = liveProgressMessageId;
    if (id == null) return;
    final index = messages.indexWhere((m) => m.id == id);
    if (index < 0) return;
    messages[index] =
        messages[index].copyWith(actionSummaries: currentActionSummaries());
    notifyUi();
  }

  Future<void> finishLiveProgress(String text,
      {List<FileChangeSummary> fileChanges = const [],
      List<AgentActionSummary>? actionSummaries}) async {
    final id = liveProgressMessageId;
    final actions = actionSummaries ?? currentActionSummaries();
    if (id == null) {
      final message = ChatMessage(
          role: 'assistant',
          content: text,
          fileChanges: fileChanges,
          actionSummaries: actions);
      messages.add(message);
      await appendSession(message);
      notifyUi();
      unawaited(showTaskNotification(appName, truncateMiddle(text, 300)));
      return;
    }
    final index = messages.indexWhere((m) => m.id == id);
    final message = ChatMessage(
        role: 'assistant',
        content: text,
        id: id,
        fileChanges: fileChanges,
        actionSummaries: actions);
    if (index >= 0) {
      messages[index] = message;
    } else {
      messages.add(message);
    }
    liveProgressMessageId = null;
    await appendSession(message);
    notifyUi();
    unawaited(showTaskNotification(appName, truncateMiddle(text, 300)));
  }

  Future<void> removeLiveProgress() async {
    final id = liveProgressMessageId;
    if (id != null) messages.removeWhere((m) => m.id == id && m.transient);
    liveProgressMessageId = null;
    notifyUi();
  }

  String checkRuntimePermissionsStatus() {
    final lines = <String>[];
    lines.add('Платформа: ${Platform.operatingSystem}; appRoot=$appRootPath');
    lines.add(
        "Интернет: ${allowInternetUse ? 'разрешён в правах проекта' : 'запрещён в правах проекта'}");
    lines.add(
        "Поиск по устройству: ${allowComputerSearch ? 'разрешён' : 'запрещён'}");
    lines.add(
        "Доступ к файлам устройства: ${allowDeviceFileAccess ? 'разрешён' : 'запрещён'}");
    try {
      lines.add(
          "Projects: ${projectsRoot.existsSync() ? 'доступна' : 'не создана'} — ${projectsRoot.path}");
    } catch (e) {
      lines.add('Projects: ошибка проверки $e');
    }
    try {
      lines.add(
          "config: ${configRoot.existsSync() ? 'доступна' : 'не создана'} — ${configRoot.path}");
    } catch (e) {
      lines.add('config: ошибка проверки $e');
    }
    try {
      lines.add(
          "tools: ${toolsRoot.existsSync() ? 'доступна' : 'не создана'} — ${toolsRoot.path}");
    } catch (e) {
      lines.add('tools: ошибка проверки $e');
    }
    if (Platform.isAndroid) {
      lines.add(
          'Android: для внешних папок нужны системные разрешения приложения. Встроенная рабочая папка доступна всегда. Повторный запрос прав выполняется системой Android при обращении к файловому диалогу/внешнему URI.');
    }
    return lines.join('\n');
  }

  Future<void> initialize() async {
    if (initializationStarted && !initializationFailed) return;
    initializationStarted = true;
    initializationFinished = false;
    initializationFailed = false;
    initializationError = '';
    status = 'Запуск приложения...';
    notifyUi();
    try {
      appRootPath = resolveDefaultAppRootPath();
      await Directory(appRootPath).create(recursive: true);
      log('APP START: $appName');
      log('CHECK platform=${Platform.operatingSystem} currentDirectory=${safeCurrentDirectoryPath()} appRoot=$appRootPath');
      configRoot = Directory(pathJoin(appRootPath, 'config'));
      await configRoot.create(recursive: true);
      projectsRoot = Directory(pathJoin(appRootPath, 'Projects'));
      distribRoot = Directory(pathJoin(appRootPath, 'distrib'));
      toolsRoot = Directory(pathJoin(appRootPath, 'tools'));
      await loadAppSettings(defaultProjectsRoot: projectsRoot.path);
      unawaited(configureWindowsTrayBridge());
      try {
        await projectsRoot
            .create(recursive: true)
            .timeout(const Duration(seconds: 4));
      } catch (e) {
        log('PROJECTS ROOT ERROR: ${projectsRoot.path}: $e; fallback to app internal Projects');
        projectsRoot = Directory(pathJoin(appRootPath, 'Projects'));
        await projectsRoot.create(recursive: true);
      }
      await configRoot.create(recursive: true);
      await distribRoot.create(recursive: true);
      await toolsRoot.create(recursive: true);
      await Directory(pathJoin(toolsRoot.path, 'downloads'))
          .create(recursive: true);
      await Directory(pathJoin(
              toolsRoot.path, Platform.operatingSystem, hostArchSegment))
          .create(recursive: true);
      log('CHECK folders: Projects=${projectsRoot.path}; config=${configRoot.path}; distrib=${distribRoot.path}; tools=${toolsRoot.path}');
      if (!Platform.isAndroid) {
        await logStartupLlamaScan().timeout(const Duration(seconds: 3),
            onTimeout: () {
          log('CHECK llama.cpp/models skipped by startup timeout');
        });
      } else {
        log('CHECK llama.cpp/models skipped on Android startup');
      }
      log('TOOLS STARTUP SCAN: deferred until tools are needed. toolsRoot=${toolsRoot.path}');
      await loadProfiles().timeout(const Duration(seconds: 5));
      await refreshProjects().timeout(const Duration(seconds: 5));
      if (projects.isEmpty) {
        await createProject('DefaultProject')
            .timeout(const Duration(seconds: 8));
      } else {
        currentProject = projects.first;
        status = 'Загрузка проекта: ${projects.first.name}...';
        notifyUi();
        unawaited(openProject(projects.first));
      }
      if (!Platform.isAndroid) {
        unawaited(refreshAvailableModels()
            .timeout(const Duration(seconds: 8))
            .then((_) => notifyUi())
            .catchError((_) {}));
        final profile = currentProfile;
        if (profile != null && profile.kind == ProfileKind.localLlama) {
          unawaited(startLocalLlama(profile).catchError((Object e) {
            log('LLAMA AUTOSTART ERROR: $e');
          }));
        }
      } else {
        log('MODEL AUTOPROBE skipped on Android startup');
      }
      initializationFinished = true;
      status = currentProject == null
          ? 'Готово'
          : 'Открыт проект: ${currentProject!.name}';
      log('APP READY: projects=${projects.length}; profiles=${profiles.length}; selectedProfile=$selectedProfileId');
      notifyUi();
    } catch (e, st) {
      markInitializationFailed(e, st);
    }
  }

  void markInitializationFailed(Object error, StackTrace stackTrace) {
    initializationStarted = false;
    initializationFinished = true;
    initializationFailed = true;
    initializationError = truncateMiddle(error.toString(), 500);
    status = 'Ошибка запуска: $initializationError';
    try {
      log('APP INIT ERROR: $error\n$stackTrace');
    } catch (_) {}
    notifyUi();
  }

  Future<void> refreshProjects() async {
    try {
      await projectsRoot
          .create(recursive: true)
          .timeout(const Duration(seconds: 4));
      final dirs = projectsRoot
          .listSync(followLinks: false)
          .whereType<Directory>()
          .map((dir) =>
              ProjectInfo(name: pathBasename(dir.path), path: dir.path))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      projects = dirs;
    } catch (e) {
      log('PROJECTS REFRESH ERROR: ${projectsRoot.path}: $e');
      projects = [];
    }
  }

  Future<void> loadAppSettings({required String defaultProjectsRoot}) async {
    try {
      final file = File(pathJoin(configRoot.path, 'app_settings.json'));
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString(encoding: utf8))
          as Map<String, dynamic>;
      appLanguage = data['language']?.toString() ?? appLanguage;
      uiScale = (data['uiScale'] is num
              ? (data['uiScale'] as num).toDouble()
              : double.tryParse(data['uiScale']?.toString() ?? '') ?? uiScale)
          .clamp(0.60, 1.35)
          .toDouble();
      defaultAllowInternetUse = data['defaultAllowInternetUse'] is bool
          ? data['defaultAllowInternetUse'] as bool
          : (data['allowInternetUse'] is bool
              ? data['allowInternetUse'] as bool
              : defaultAllowInternetUse);
      defaultAllowComputerSearch = data['defaultAllowComputerSearch'] is bool
          ? data['defaultAllowComputerSearch'] as bool
          : false;
      defaultAllowDeviceFileAccess =
          data['defaultAllowDeviceFileAccess'] is bool
              ? data['defaultAllowDeviceFileAccess'] as bool
              : false;
      defaultAllowFollowUpSuggestions =
          data['defaultAllowFollowUpSuggestions'] is bool
              ? data['defaultAllowFollowUpSuggestions'] as bool
              : defaultAllowFollowUpSuggestions;
      closeToTrayOnClose = data['closeToTrayOnClose'] is bool
          ? data['closeToTrayOnClose'] as bool
          : closeToTrayOnClose;
      trayNotificationsEnabled = data['trayNotificationsEnabled'] is bool
          ? data['trayNotificationsEnabled'] as bool
          : trayNotificationsEnabled;
      llamaProcessLoggingEnabled = data['llamaProcessLoggingEnabled'] is bool
          ? data['llamaProcessLoggingEnabled'] as bool
          : llamaProcessLoggingEnabled;
      isolatedToolsEnabled = data['isolatedToolsEnabled'] is bool
          ? data['isolatedToolsEnabled'] as bool
          : isolatedToolsEnabled;
      emailAccounts = (data['emailAccounts'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((m) => EmailAccountConfig.fromJson(
              m.map((key, value) => MapEntry(key.toString(), value))))
          .where((a) => a.address.trim().isNotEmpty)
          .toList();
      final apiTemplatesRaw =
          (data['apiOutputTemplates'] as List<dynamic>? ?? [])
              .whereType<Map>()
              .map((m) => ApiOutputTemplate.fromJson(
                  m.map((key, value) => MapEntry(key.toString(), value))))
              .toList();
      if (apiTemplatesRaw.isNotEmpty) apiOutputTemplates = apiTemplatesRaw;
      triggers = (data['triggers'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((m) => AgentTriggerConfig.fromJson(
              m.map((key, value) => MapEntry(key.toString(), value))))
          .toList();
      schedules = (data['schedules'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((m) => AgentScheduleConfig.fromJson(
              m.map((key, value) => MapEntry(key.toString(), value))))
          .toList();
      indexLocations = (data['indexLocations'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((m) => IndexLocationConfig.fromJson(
              m.map((key, value) => MapEntry(key.toString(), value))))
          .where((l) => l.path.trim().isNotEmpty)
          .toList();
      customTools = (data['customTools'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((m) => CustomAgentToolConfig.fromJson(
              m.map((key, value) => MapEntry(key.toString(), value))))
          .toList();
      scheduledTaskRuns = (data['scheduledTaskRuns'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((m) => ScheduledTaskRunRecord.fromJson(
              m.map((key, value) => MapEntry(key.toString(), value))))
          .toList();
      defaultPermissionMode = PermissionMode.values.firstWhere(
          (m) => m.name == (data['defaultPermissionMode']?.toString() ?? ''),
          orElse: () => PermissionMode.askEveryAction);
      defaultCreationMode = CreationMode.values.firstWhere(
          (m) => m.name == (data['defaultCreationMode']?.toString() ?? ''),
          orElse: () => CreationMode.autoComplexity);
      allowInternetUse = defaultAllowInternetUse;
      allowComputerSearch = defaultAllowComputerSearch;
      allowDeviceFileAccess = defaultAllowDeviceFileAccess;
      allowFollowUpSuggestions = defaultAllowFollowUpSuggestions;
      permissionMode = defaultPermissionMode;
      creationMode = defaultCreationMode;
      final projectsPath = data['projectsRoot']?.toString() ?? '';
      if (projectsPath.trim().isNotEmpty)
        projectsRoot = Directory(projectsPath.trim());
    } catch (e) {
      log('APP SETTINGS LOAD ERROR: $e');
      projectsRoot = Directory(defaultProjectsRoot);
    }
  }

  Future<void> saveAppSettings() async {
    await configRoot.create(recursive: true);
    final file = File(pathJoin(configRoot.path, 'app_settings.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'language': appLanguage,
        'uiScale': uiScale,
        'defaultPermissionMode': defaultPermissionMode.name,
        'defaultCreationMode': defaultCreationMode.name,
        'defaultAllowInternetUse': defaultAllowInternetUse,
        'defaultAllowComputerSearch': defaultAllowComputerSearch,
        'defaultAllowDeviceFileAccess': defaultAllowDeviceFileAccess,
        'defaultAllowFollowUpSuggestions': defaultAllowFollowUpSuggestions,
        'allowInternetUse': allowInternetUse,
        'allowComputerSearch': allowComputerSearch,
        'allowDeviceFileAccess': allowDeviceFileAccess,
        'allowFollowUpSuggestions': allowFollowUpSuggestions,
        'closeToTrayOnClose': closeToTrayOnClose,
        'trayNotificationsEnabled': trayNotificationsEnabled,
        'llamaProcessLoggingEnabled': llamaProcessLoggingEnabled,
        'isolatedToolsEnabled': isolatedToolsEnabled,
        'emailAccounts': emailAccounts.map((a) => a.toJson()).toList(),
        'apiOutputTemplates':
            apiOutputTemplates.map((a) => a.toJson()).toList(),
        'triggers': triggers.map((t) => t.toJson()).toList(),
        'schedules': schedules.map((s) => s.toJson()).toList(),
        'indexLocations': indexLocations.map((l) => l.toJson()).toList(),
        'customTools': customTools.map((t) => t.toJson()).toList(),
        'scheduledTaskRuns': scheduledTaskRuns.map((r) => r.toJson()).toList(),
        'projectsRoot': projectsRoot.path,
      }),
      encoding: utf8,
    );
  }

  String automationSummaryForPrompt() {
    final buffer = StringBuffer();
    if (apiOutputTemplates.any((t) => t.enabled)) {
      buffer.writeln('API output templates:');
      for (final t in apiOutputTemplates.where((t) => t.enabled)) {
        buffer.writeln('- ${t.name}: ${t.method} ${t.endpoint}');
      }
    }
    if (triggers.any((t) => t.enabled)) {
      buffer.writeln('Triggers:');
      for (final t in triggers.where((t) => t.enabled)) {
        buffer.writeln('- ${t.name}: type=${t.type}');
      }
    }
    if (schedules.any((s) => s.enabled)) {
      buffer.writeln('Schedules:');
      for (final s in schedules.where((s) => s.enabled)) {
        buffer.writeln('- ${s.name}: project=${s.projectPath}');
      }
    }
    if (indexLocations.isNotEmpty) {
      buffer.writeln('Indexed locations:');
      for (final l in indexLocations) {
        buffer.writeln(
            '- ${l.path}: names=${l.indexNames}, contents=${l.indexContents}');
      }
    }
    if (customTools.any((t) => t.enabled)) {
      buffer.writeln('Custom tools:');
      for (final t in customTools.where((t) => t.enabled)) {
        buffer.writeln('- ${t.name}: ${t.description}');
      }
    }
    final text = buffer.toString().trim();
    return text.isEmpty ? '(automation settings are empty)' : text;
  }

  Future<void> upsertApiOutputTemplate(ApiOutputTemplate template) async {
    final index = apiOutputTemplates.indexWhere((t) => t.id == template.id);
    if (index >= 0) {
      apiOutputTemplates[index] = template;
    } else {
      apiOutputTemplates.add(template);
    }
    await saveAppSettings();
    notifyUi();
  }

  Future<void> deleteApiOutputTemplate(String id) async {
    apiOutputTemplates.removeWhere((t) => t.id == id);
    await saveAppSettings();
    notifyUi();
  }

  Future<void> upsertTrigger(AgentTriggerConfig trigger) async {
    final index = triggers.indexWhere((t) => t.id == trigger.id);
    if (index >= 0) {
      triggers[index] = trigger;
    } else {
      triggers.add(trigger);
    }
    await saveAppSettings();
    notifyUi();
  }

  Future<void> deleteTrigger(String id) async {
    triggers.removeWhere((t) => t.id == id);
    await saveAppSettings();
    notifyUi();
  }

  Future<void> upsertSchedule(AgentScheduleConfig schedule) async {
    final index = schedules.indexWhere((s) => s.id == schedule.id);
    if (index >= 0) {
      schedules[index] = schedule;
    } else {
      schedules.add(schedule);
    }
    await saveAppSettings();
    notifyUi();
  }

  Future<void> deleteSchedule(String id) async {
    schedules.removeWhere((s) => s.id == id);
    await saveAppSettings();
    notifyUi();
  }

  Future<void> upsertIndexLocation(IndexLocationConfig location) async {
    final index = indexLocations.indexWhere((l) =>
        normalizePathForCompare(l.path) ==
        normalizePathForCompare(location.path));
    if (index >= 0) {
      indexLocations[index] = location;
    } else {
      indexLocations.add(location);
    }
    await saveAppSettings();
    notifyUi();
  }

  Future<void> deleteIndexLocation(String path) async {
    final needle = normalizePathForCompare(path);
    indexLocations
        .removeWhere((l) => normalizePathForCompare(l.path) == needle);
    await saveAppSettings();
    notifyUi();
  }

  Future<void> upsertCustomTool(CustomAgentToolConfig tool) async {
    final index = customTools.indexWhere((t) => t.id == tool.id);
    if (index >= 0) {
      customTools[index] = tool;
    } else {
      customTools.add(tool);
    }
    await saveAppSettings();
    notifyUi();
  }

  Future<void> deleteCustomTool(String id) async {
    customTools.removeWhere((t) => t.id == id);
    await saveAppSettings();
    notifyUi();
  }

  File get deviceIndexFile =>
      File(pathJoin(configRoot.path, 'device_index.jsonl'));

  Future<String> rebuildDeviceIndex() async {
    if (indexLocations.isEmpty) return 'INDEX_DISABLED: no locations selected';
    await configRoot.create(recursive: true);
    final sink = deviceIndexFile.openWrite(encoding: utf8);
    var files = 0;
    var contents = 0;
    try {
      for (final location in indexLocations) {
        final root = Directory(location.path);
        if (!await root.exists()) continue;
        await for (final entity
            in root.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          files++;
          var text = '';
          if (location.indexContents &&
              isSupportedReadableDocumentPath(entity.path)) {
            try {
              text = await readDeviceDocumentText(entity.path, maxChars: 12000);
              if (text.trim().isNotEmpty) contents++;
            } catch (_) {}
          }
          sink.writeln(jsonEncode({
            'path': entity.path,
            'name': pathBasename(entity.path),
            'indexNames': location.indexNames,
            'indexContents': location.indexContents,
            if (text.isNotEmpty) 'text': truncateMiddle(text, 12000),
          }));
        }
      }
    } finally {
      await sink.close();
    }
    logAction('device_index_rebuilt', {
      'locations': indexLocations.length,
      'files': files,
      'contents': contents,
      'file': deviceIndexFile.path
    });
    return 'INDEX_REBUILT: locations=${indexLocations.length}, files=$files, contents=$contents, file=${deviceIndexFile.path}';
  }

  String searchDeviceIndex(String query, {int maxResults = 20}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return 'SEARCH_DEVICE_INDEX_FAILED: query is required';
    if (!deviceIndexFile.existsSync()) {
      return 'SEARCH_DEVICE_INDEX_EMPTY: run rebuild_device_index first';
    }
    final terms = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final scored = <MapEntry<int, Map<String, dynamic>>>[];
    for (final line in deviceIndexFile.readAsLinesSync(encoding: utf8)) {
      if (line.trim().isEmpty) continue;
      try {
        final row = jsonDecode(line) as Map<String, dynamic>;
        final haystack = [
          row['path']?.toString() ?? '',
          row['name']?.toString() ?? '',
          row['text']?.toString() ?? '',
        ].join('\n').toLowerCase();
        var score = 0;
        for (final term in terms) {
          if (haystack.contains(term)) score++;
        }
        if (score > 0) scored.add(MapEntry(score, row));
      } catch (_) {}
    }
    scored.sort((a, b) => b.key.compareTo(a.key));
    final buffer = StringBuffer()
      ..writeln('SEARCH_DEVICE_INDEX_RESULTS: ${scored.length}');
    for (final entry in scored.take(maxResults.clamp(1, 100).toInt())) {
      final row = entry.value;
      buffer.writeln('- SCORE=${entry.key} PATH=${row['path']}');
      final text = row['text']?.toString() ?? '';
      if (text.isNotEmpty) buffer.writeln(truncateMiddle(text, 800));
    }
    return buffer.toString().trimRight();
  }

  Future<String> recognizeImageText(String rawPath) async {
    final path = resolveDevicePath(rawPath);
    if (path.isEmpty) return 'OCR_FAILED: path is required';
    if (!await File(path).exists()) return 'OCR_FAILED: file not found: $path';
    final tesseract = findToolExecutable(['tesseract.exe', 'tesseract']);
    if (tesseract == null) {
      return 'OCR_TOOL_MISSING: tesseract is not available in tools or PATH. Add portable Tesseract/OCR tool to tools/${Platform.operatingSystem}/$hostArchSegment or configure a custom tool.';
    }
    final result = await Process.run(
      tesseract.path,
      [path, 'stdout', '-l', 'rus+eng'],
      environment: buildToolAwareEnvironment(),
      runInShell: false,
    ).timeout(const Duration(minutes: 5));
    final stdoutText = result.stdout?.toString() ?? '';
    final stderrText = result.stderr?.toString() ?? '';
    final output = stdoutText.trim();
    logAction('ocr_recognize', {
      'path': path,
      'exit': result.exitCode,
      'chars': output.length,
      'stderr': truncateMiddle(stderrText, 1000)
    });
    if (result.exitCode != 0) {
      return 'OCR_FAILED: exit=${result.exitCode}\nSTDERR:\n$stderrText';
    }
    return 'OCR_RESULT\nPATH: $path\nTEXT:\n${output.isEmpty ? '(empty)' : output}';
  }

  Future<String> runCustomTool(String name, String input) async {
    final wanted = name.trim().toLowerCase();
    if (wanted.isEmpty) return 'CUSTOM_TOOL_FAILED: name is required';
    CustomAgentToolConfig? tool;
    for (final candidate in customTools.where((t) => t.enabled)) {
      if (candidate.name.trim().toLowerCase() == wanted) {
        tool = candidate;
        break;
      }
    }
    if (tool == null) return 'CUSTOM_TOOL_NOT_FOUND: $name';
    var command = tool.commandTemplate.trim();
    if (command.isEmpty && tool.scriptPath.trim().isNotEmpty) {
      command = quoteShellArg(tool.scriptPath.trim());
    }
    if (command.isEmpty) return 'CUSTOM_TOOL_FAILED: command is empty';
    command = command
        .replaceAll('{{input}}', input)
        .replaceAll('{{project}}', currentProject?.path ?? '')
        .replaceAll('{{tools}}', toolsRoot.path);
    final result = await runCommand(command);
    logAction('custom_tool_run', {'name': tool.name, 'command': command});
    return 'CUSTOM_TOOL_RESULT: ${tool.name}\n$result';
  }

  String emailDraftSmtp(
      String accountId, String to, String subject, String body) {
    EmailAccountConfig? account;
    for (final candidate in emailAccounts) {
      if (candidate.id == accountId ||
          candidate.address.toLowerCase() == accountId.toLowerCase()) {
        account = candidate;
        break;
      }
    }
    if (account == null)
      return 'EMAIL_ACCOUNT_NOT_FOUND: сначала вызови email_list_accounts или добавь почтовый адрес в настройках.';
    if (to.trim().isEmpty) return 'EMAIL_DRAFT_ERROR: не указан получатель.';
    final draft = {
      'from': account.address,
      'displayName': account.displayName,
      'smtpHost': account.smtpHost,
      'smtpPort': account.smtpPort,
      'useSsl': account.useSsl,
      'to': to.trim(),
      'subject': subject.trim(),
      'body': body,
    };
    return 'EMAIL_DRAFT_READY: письмо подготовлено, но не отправлено без подтверждения пользователя.\n${const JsonEncoder.withIndent('  ').convert(draft)}';
  }

  Future<void> saveEmailAccount(EmailAccountConfig account) async {
    final normalized = account.id.trim().isEmpty
        ? account.copyWith(id: 'mail_${DateTime.now().microsecondsSinceEpoch}')
        : account;
    final index = emailAccounts.indexWhere((a) =>
        a.id == normalized.id ||
        (normalized.address.trim().isNotEmpty &&
            a.address.toLowerCase() == normalized.address.toLowerCase()));
    if (index >= 0) {
      emailAccounts[index] = normalized;
    } else {
      emailAccounts.add(normalized);
    }
    await saveAppSettings();
    notifyUi();
  }

  Future<void> deleteEmailAccount(String id) async {
    emailAccounts.removeWhere((a) => a.id == id);
    await saveAppSettings();
    notifyUi();
  }

  String emailAccountsSummary({bool includePasswords = false}) {
    if (emailAccounts.isEmpty) return 'Почтовые аккаунты не настроены.';
    final buffer = StringBuffer();
    for (final account in emailAccounts) {
      buffer.writeln(
          '- ${account.safeSummary}; user=${account.username.isEmpty ? account.address : account.username}; password=${includePasswords && account.password.isNotEmpty ? '[set]' : '[hidden]'}');
    }
    return buffer.toString().trimRight();
  }

  Future<void> configureWindowsTrayBridge() async {
    if (!Platform.isWindows) return;
    try {
      const channel = MethodChannel('ai_agent/windows');
      await channel.invokeMethod<void>('configureTray', {
        'closeToTray': closeToTrayOnClose,
        'notifications': trayNotificationsEnabled
      });
      log('WINDOWS TRAY CONFIGURED: closeToTray=$closeToTrayOnClose notifications=$trayNotificationsEnabled');
    } catch (e) {
      log('WINDOWS TRAY CONFIGURE SKIPPED: native bridge is not available yet: $e');
    }
  }

  Future<void> showTaskNotification(String title, String body) async {
    if (!trayNotificationsEnabled) return;
    log('NOTIFICATION: $title — ${truncateMiddle(body, 400)}');
    if (!Platform.isWindows) return;
    try {
      const channel = MethodChannel('ai_agent/windows');
      await channel.invokeMethod<void>(
          'showNotification', {'title': title, 'body': body});
    } catch (e) {
      log('NOTIFICATION NATIVE SKIPPED: $e');
    }
  }

  Future<void> setProjectsRootPath(String path) async {
    if (path.trim().isEmpty) return;
    projectsRoot = Directory(path.trim());
    await projectsRoot.create(recursive: true);
    await saveAppSettings();
    await refreshProjects();
    if (projects.isNotEmpty) {
      await openProject(projects.first);
    } else {
      await createProject('DefaultProject');
    }
    notifyUi();
  }

  Future<void> createProject(String rawName) async {
    final name = sanitizeFileName(
        rawName.trim().isEmpty ? 'NewProject' : rawName.trim());
    final dir = Directory(pathJoin(projectsRoot.path, name));
    await createProjectAt(name, dir.path);
  }

  Future<void> createProjectAt(String rawName, String rawPath) async {
    final name = sanitizeFileName(
        rawName.trim().isEmpty ? 'NewProject' : rawName.trim());
    final dir = Directory(rawPath.trim().isEmpty
        ? pathJoin(projectsRoot.path, name)
        : rawPath.trim());
    await dir.create(recursive: true);
    await Directory(pathJoin(dir.path, '.cppagent', 'sessions'))
        .create(recursive: true);
    final readme = File(pathJoin(dir.path, 'README.md'));
    if (!await readme.exists()) {
      await readme.writeAsString('# $name\n\nПроект создан AI Agent.\n',
          encoding: utf8);
    }
    await refreshProjects();
    await openProject(ProjectInfo(name: name, path: dir.path));
  }

  Future<void> renameProject(ProjectInfo project, String rawName) async {
    final name = sanitizeFileName(rawName.trim());
    if (name.isEmpty || name == project.name) return;
    final source = Directory(project.path);
    final target = Directory(pathJoin(source.parent.path, name));
    log('PROJECT RENAME: ${project.path} -> ${target.path}');
    if (await target.exists())
      throw StateError('Project already exists: $name');
    await source.rename(target.path);
    await refreshProjects();
    await openProject(ProjectInfo(name: name, path: target.path));
  }

  Future<void> moveProject(ProjectInfo project, String targetPath) async {
    final value = targetPath.trim();
    if (value.isEmpty) return;
    final source = Directory(project.path);
    final target = Directory(value);
    log('PROJECT MOVE: ${project.path} -> ${target.path}');
    if (await target.exists())
      throw StateError('Target already exists: $value');
    await source.rename(target.path);
    await refreshProjects();
    await openProject(
        ProjectInfo(name: pathBasename(target.path), path: target.path));
  }

  Future<void> duplicateProject(ProjectInfo project, String rawName) async {
    final name = sanitizeFileName(
        rawName.trim().isEmpty ? '${project.name}_copy' : rawName.trim());
    final target = Directory(pathJoin(projectsRoot.path, name));
    log('PROJECT DUPLICATE: ${project.path} -> ${target.path}');
    if (await target.exists())
      throw StateError('Project already exists: $name');
    await copyDirectory(Directory(project.path), target);
    await refreshProjects();
    await openProject(ProjectInfo(name: name, path: target.path));
  }

  Future<void> deleteProject(ProjectInfo project) async {
    log('PROJECT DELETE: ${project.path}');
    await Directory(project.path).delete(recursive: true);
    await refreshProjects();
    if (projects.isNotEmpty) {
      await openProject(projects.first);
    } else {
      currentProject = null;
      messages = [];
    }
  }

  Future<void> clearProjectDialogAndContext(ProjectInfo project) async {
    log('PROJECT CLEAR DIALOG AND CONTEXT: ${project.path}');
    final agentDir = Directory(pathJoin(project.path, '.cppagent'));
    final sessionsDir = Directory(pathJoin(agentDir.path, 'sessions'));
    try {
      if (await sessionsDir.exists()) await sessionsDir.delete(recursive: true);
      await sessionsDir.create(recursive: true);
      for (final name in const [
        'task_plan.md',
        'context_summary.md',
        'context.json',
        'last_context.json'
      ]) {
        final file = File(pathJoin(agentDir.path, name));
        if (await file.exists()) await file.delete();
      }
    } catch (error) {
      log('PROJECT CLEAR DIALOG ERROR: $error');
    }
    if (currentProject?.path == project.path) {
      messages = [];
      resetTaskState();
      lastContextCompressionBoundaryId = null;
      liveProgressMessageId = null;
      status = 'Диалог и контекст очищены: ${project.name}';
      recalculateContext();
      notifyUi();
    }
  }

  Future<File?> projectPermissionsFile(ProjectInfo? project) async {
    if (project == null) return null;
    final dir = Directory(pathJoin(project.path, '.cppagent'));
    await dir.create(recursive: true);
    return File(pathJoin(dir.path, 'project_permissions.json'));
  }

  Future<void> loadProjectPermissions(ProjectInfo project) async {
    permissionMode = defaultPermissionMode;
    creationMode = defaultCreationMode;
    allowInternetUse = defaultAllowInternetUse;
    allowComputerSearch = defaultAllowComputerSearch;
    allowDeviceFileAccess = defaultAllowDeviceFileAccess;
    allowFollowUpSuggestions = defaultAllowFollowUpSuggestions;
    try {
      final file = await projectPermissionsFile(project);
      if (file != null && await file.exists()) {
        final data = jsonDecode(await file.readAsString(encoding: utf8))
            as Map<String, dynamic>;
        permissionMode = PermissionMode.values.firstWhere(
            (m) => m.name == data['permissionMode']?.toString(),
            orElse: () => permissionMode);
        creationMode = CreationMode.values.firstWhere(
            (m) => m.name == data['creationMode']?.toString(),
            orElse: () => creationMode);
        allowInternetUse = data['allowInternetUse'] is bool
            ? data['allowInternetUse'] as bool
            : allowInternetUse;
        allowComputerSearch = data['allowComputerSearch'] is bool
            ? data['allowComputerSearch'] as bool
            : allowComputerSearch;
        allowDeviceFileAccess = data['allowDeviceFileAccess'] is bool
            ? data['allowDeviceFileAccess'] as bool
            : allowDeviceFileAccess;
        allowFollowUpSuggestions = data['allowFollowUpSuggestions'] is bool
            ? data['allowFollowUpSuggestions'] as bool
            : allowFollowUpSuggestions;
      } else {
        await saveProjectPermissions(project: project);
      }
    } catch (e) {
      log('PROJECT PERMISSIONS LOAD ERROR: ${project.path}: $e');
    }
  }

  Future<void> saveProjectPermissions({ProjectInfo? project}) async {
    final target = project ?? currentProject;
    if (target == null) return;
    try {
      final file = await projectPermissionsFile(target);
      if (file == null) return;
      await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'permissionMode': permissionMode.name,
            'creationMode': creationMode.name,
            'allowInternetUse': allowInternetUse,
            'allowComputerSearch': allowComputerSearch,
            'allowDeviceFileAccess': allowDeviceFileAccess,
            'allowFollowUpSuggestions': allowFollowUpSuggestions,
          }),
          encoding: utf8);
    } catch (e) {
      log('PROJECT PERMISSIONS SAVE ERROR: $e');
    }
  }

  void applyCurrentPermissionsAsDefaults() {
    defaultPermissionMode = permissionMode;
    defaultCreationMode = creationMode;
    defaultAllowInternetUse = allowInternetUse;
    defaultAllowComputerSearch = allowComputerSearch;
    defaultAllowDeviceFileAccess = allowDeviceFileAccess;
    defaultAllowFollowUpSuggestions = allowFollowUpSuggestions;
  }

  Future<void> openProject(ProjectInfo project) async {
    if (busy) {
      pendingProjectOpenAfterTask = project;
      status =
          'Задача выполняется в проекте ${currentProject?.name ?? ''}. Переключение на ${project.name} будет выполнено после завершения.';
      log('PROJECT OPEN QUEUED DURING TASK: ${project.path}');
      notifyUi();
      return;
    }
    projectLoading = true;
    currentProject = project;
    messages = [];
    status = 'Загрузка проекта: ${project.name}...';
    notifyUi();
    setupProjectLogging(project);
    await loadProjectPermissions(project);
    log('Открыт проект: ${project.path}');
    await Directory(pathJoin(project.path, '.cppagent', 'sessions'))
        .create(recursive: true);
    await loadLatestSessionForCurrentProject();
    recalculateContext();
    projectLoading = false;
    status = 'Открыт проект: ${project.name}';
    notifyUi();
  }

  Future<void> loadProfiles() async {
    final file = File(pathJoin(configRoot.path, 'model_profiles.json'));
    if (await file.exists()) {
      final data = jsonDecode(await file.readAsString(encoding: utf8))
          as Map<String, dynamic>;
      selectedProfileId = data['selectedProfileId']?.toString() ?? '';
      profiles = (data['profiles'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ModelProfile.fromJson)
          .toList();
    }
    if (profiles.isEmpty) {
      final defaultProfile = ModelProfile.openAiCompatible(
        name: 'LM Studio',
        baseUrl: 'http://127.0.0.1:1234/v1',
        model: 'local-model',
        apiKey: '',
      );
      profiles = [defaultProfile];
      selectedProfileId = defaultProfile.id;
      await saveProfiles();
    }
    if (selectedProfileId.isEmpty ||
        profiles.every((p) => p.id != selectedProfileId)) {
      selectedProfileId = profiles.first.id;
    }
  }

  Future<void> saveProfiles() async {
    await configRoot.create(recursive: true);
    final file = File(pathJoin(configRoot.path, 'model_profiles.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'selectedProfileId': selectedProfileId,
        'profiles': profiles.map((p) => p.toJson()).toList(),
      }),
      encoding: utf8,
    );
  }

  Future<void> upsertProfile(ModelProfile profile,
      {bool select = false}) async {
    final index = profiles.indexWhere((p) =>
        p.id == profile.id ||
        (p.name == profile.name && p.baseUrl == profile.baseUrl));
    if (index >= 0) {
      profiles[index] = profile.copyWith(id: profiles[index].id);
      if (select) selectedProfileId = profiles[index].id;
    } else {
      profiles.add(profile);
      if (select) selectedProfileId = profile.id;
    }
    await saveProfiles();
    await refreshAvailableModels();
  }

  Future<void> selectProfile(String id) async {
    selectedProfileId = id;
    await saveProfiles();
    final selected = currentProfile;
    if (selected == null || selected.kind != ProfileKind.localLlama) {
      await stopLocalLlama(reason: 'selected remote/non-local profile');
    } else {
      unawaited(startLocalLlama(selected));
    }
    await refreshAvailableModels();
  }

  Future<void> selectModel(String model) async {
    final profile = currentProfile;
    if (profile == null) return;
    AvailableModel? selectedModel;
    for (final item in availableModels) {
      if (item.name == model) {
        selectedModel = item;
        break;
      }
    }
    final updated = profile.copyWith(
        model: model,
        maxContextTokens:
            selectedModel?.maxContextTokens ?? profile.maxContextTokens,
        maxOutputTokens:
            selectedModel?.maxOutputTokens ?? profile.maxOutputTokens);
    await upsertProfile(updated, select: true);
    maxContextTokens = updated.maxContextTokens;
    maxOutputTokens = updated.maxOutputTokens;
    recalculateContext();
  }

  Future<void> updateCurrentLlamaSettings(LlamaSettings settings) async {
    final profile = currentProfile;
    if (profile == null) return;
    await upsertProfile(
        profile.copyWith(
            llamaSettings: settings,
            maxContextTokens: settings.contextLength,
            maxOutputTokens: profile.maxOutputTokens),
        select: true);
  }

  Future<void> refreshAvailableModels() async {
    final profile = currentProfile;
    if (profile == null) return;
    availableModels = [];
    maxContextTokens = profile.maxContextTokens;
    maxOutputTokens = profile.maxOutputTokens;
    if (profile.kind == ProfileKind.localLlama) {
      availableModels = await scanModelFiles().then((paths) => paths
          .map((p) => AvailableModel(pathBasename(p), profile.maxContextTokens,
              maxOutputTokens: profile.maxOutputTokens, path: p))
          .toList());
      if (profile.modelPath.isNotEmpty &&
          availableModels.every((m) => m.path != profile.modelPath)) {
        availableModels.insert(
            0,
            AvailableModel(
                pathBasename(profile.modelPath), profile.maxContextTokens,
                maxOutputTokens: profile.maxOutputTokens,
                path: profile.modelPath));
      }
      recalculateContext();
      return;
    }
    try {
      final uri =
          Uri.parse('${profile.baseUrl.replaceAll(RegExp(r'/+$'), '')}/models');
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final request =
          await client.getUrl(uri).timeout(const Duration(seconds: 8));
      if (profile.apiKey.isNotEmpty)
        request.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer ${profile.apiKey}');
      final response =
          await request.close().timeout(const Duration(seconds: 20));
      final text = await utf8.decodeStream(response);
      log('HTTP RESPONSE ${response.statusCode}: ${truncateMiddle(text, 18000)}');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(text) as Map<String, dynamic>;
        final raw = data['data'] as List<dynamic>? ?? [];
        availableModels = raw
            .map((item) {
              final map =
                  item is Map<String, dynamic> ? item : <String, dynamic>{};
              final id = map['id']?.toString() ?? item.toString();
              final rawCtx = firstInt(map, [
                'max_context_length',
                'context_length',
                'n_ctx',
                'max_ctx',
                'ctx',
                'context_window'
              ]);
              final rawOut = firstInt(map, [
                'max_output_tokens',
                'max_completion_tokens',
                'max_tokens',
                'n_predict',
                'output_token_limit'
              ]);
              final ctx = rawCtx ?? profile.maxContextTokens;
              final out = rawOut ?? profile.maxOutputTokens;
              if (rawCtx == null || rawOut == null) {
                log('MODEL LIMITS METADATA: model=$id endpoint_ctx=${rawCtx ?? 'missing'} endpoint_output=${rawOut ?? 'missing'} using_profile_ctx=$ctx using_profile_output=$out');
              }
              return AvailableModel(id, ctx, maxOutputTokens: out);
            })
            .where((m) => m.name.isNotEmpty)
            .toList();
      }
    } catch (_) {
      // Endpoint can be temporarily unavailable; keep saved model.
    }
    if (availableModels.isEmpty && profile.model.isNotEmpty) {
      availableModels = [
        AvailableModel(profile.model, profile.maxContextTokens,
            maxOutputTokens: profile.maxOutputTokens)
      ];
    }
    AvailableModel? current;
    for (final item in availableModels) {
      if (item.name == profile.model) {
        current = item;
        break;
      }
    }
    current ??= availableModels.isEmpty ? null : availableModels.first;
    if (current != null) {
      maxContextTokens = current.maxContextTokens;
      maxOutputTokens = current.maxOutputTokens;
    }
    recalculateContext();
  }

  Future<List<ModelProfile>> probeOpenAiCompatible(
      String hostRaw, String portsRaw) async {
    final host = hostRaw.trim().isEmpty ? '127.0.0.1' : hostRaw.trim();
    final ports = portsRaw
        .split(',')
        .map((p) => int.tryParse(p.trim()))
        .whereType<int>()
        .toList();
    final found = <ModelProfile>[];
    for (final port in ports) {
      final base = 'http://$host:$port/v1';
      try {
        final uri = Uri.parse('$base/models');
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 2);
        final request =
            await client.getUrl(uri).timeout(const Duration(seconds: 4));
        final response =
            await request.close().timeout(const Duration(seconds: 6));
        final text = await utf8.decodeStream(response);
        log('HTTP RESPONSE ${response.statusCode}: ${truncateMiddle(text, 18000)}');
        if (response.statusCode < 200 || response.statusCode >= 300) continue;
        final data = jsonDecode(text) as Map<String, dynamic>;
        final raw = data['data'] as List<dynamic>? ?? [];
        final models = raw
            .map((e) => e is Map ? e['id']?.toString() ?? '' : e.toString())
            .where((m) => m.isNotEmpty)
            .toList();
        if (models.isNotEmpty) {
          found.add(ModelProfile.openAiCompatible(
              name: '$host:$port',
              baseUrl: base,
              model: models.first,
              apiKey: '',
              maxContextTokens: 131072,
              maxOutputTokens: 16384));
        }
      } catch (_) {}
    }
    return found;
  }

  Future<List<LocalLlamaCandidate>> scanLocalLlamaCandidates() async {
    final modes = <String, List<String>>{
      'cuda': [
        'tools/llama.cpp/cuda',
        'llama.cpp/cuda',
        'tooling/llama.cpp/cuda'
      ],
      'vulkan': [
        'tools/llama.cpp/vulkan',
        'llama.cpp/vulkan',
        'tooling/llama.cpp/vulkan'
      ],
      'cpu': ['tools/llama.cpp/cpu', 'llama.cpp/cpu', 'tooling/llama.cpp/cpu'],
    };
    final models = await scanModelFiles();
    final result = <LocalLlamaCandidate>[];
    for (final entry in modes.entries) {
      for (final rel in entry.value) {
        final dir = Directory(
            pathJoin(appRootPath, rel.replaceAll('/', Platform.pathSeparator)));
        if (!dir.existsSync()) continue;
        for (final model in models) {
          result.add(LocalLlamaCandidate(
              mode: entry.key, llamaDir: dir.path, modelPath: model));
        }
      }
    }
    return result;
  }

  Future<List<String>> scanModelFiles() async {
    final roots = [
      'models',
      'tools/models',
      'tools/llama.cpp/models',
      'tooling/models',
      'llama.cpp/models',
      'tooling/llama.cpp/models'
    ];
    final files = <String>[];
    for (final rootRel in roots) {
      final dir = Directory(pathJoin(
          appRootPath, rootRel.replaceAll('/', Platform.pathSeparator)));
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File &&
            entity.path.toLowerCase().endsWith('.gguf') &&
            !pathBasename(entity.path).toLowerCase().startsWith('mmproj'))
          files.add(entity.path);
      }
    }
    files.sort((a, b) =>
        pathBasename(a).toLowerCase().compareTo(pathBasename(b).toLowerCase()));
    return files;
  }

  String findMmprojForModel(String modelPath) {
    final dir = File(modelPath).parent;
    if (!dir.existsSync()) return '';
    final files = dir.listSync(recursive: false).whereType<File>().where((f) {
      final n = pathBasename(f.path).toLowerCase();
      return n.startsWith('mmproj') && n.endsWith('.gguf');
    }).toList(growable: false);
    if (files.isEmpty) return '';
    files.sort((a, b) => pathBasename(a.path).compareTo(pathBasename(b.path)));
    return files.first.path;
  }

  Future<void> createLocalLlamaProfile(LocalLlamaCandidate candidate, int port,
      {bool startNow = false}) async {
    final settings = const LlamaSettings().copyWith(contextLength: 131072);
    final mmproj = findMmprojForModel(candidate.modelPath);
    final profile = ModelProfile.localLlama(
      name: 'llama.cpp ${candidate.mode} ${pathBasename(candidate.modelPath)}',
      baseUrl: 'http://127.0.0.1:$port/v1',
      model: pathBasename(candidate.modelPath),
      modelPath: candidate.modelPath,
      mmprojPath: mmproj,
      llamaMode: candidate.mode,
      llamaDir: candidate.llamaDir,
      llamaPort: port,
      llamaSettings: settings,
    );
    await upsertProfile(profile, select: true);
    if (startNow) await startLocalLlama(profile);
  }

  Future<void> startLocalLlama(ModelProfile profile) async {
    if (profile.kind != ProfileKind.localLlama) return;
    final exe = findLlamaServer(profile.llamaDir);
    if (exe == null) {
      status = 'llama-server не найден в ${profile.llamaDir}';
      log('LLAMA START FAILED: llama-server not found in ${profile.llamaDir}');
      return;
    }
    final previous = llamaServerProcess;
    if (previous != null) {
      final killed = previous.kill();
      log('LLAMA PREVIOUS PROCESS KILL: killed=$killed');
    }
    await openLlamaProcessLog(profile);
    final args = profile.llamaSettings.toLlamaArgs(
        profile.modelPath, profile.llamaPort,
        mmprojPath: profile.mmprojPath, backendMode: profile.llamaMode);
    log('LLAMA START EXE: $exe');
    log('LLAMA START WORKDIR: ${profile.llamaDir}');
    log('LLAMA START BACKEND: ${profile.llamaMode}');
    log('LLAMA START MODEL: ${profile.modelPath}');
    log('LLAMA START ARGS: ${args.join(' ')}');
    logAction('llama_start', {
      'exe': exe,
      'workdir': profile.llamaDir,
      'backend': profile.llamaMode,
      'model': profile.modelPath,
      'args': args,
    });
    final process = await Process.start(exe, args,
        workingDirectory: profile.llamaDir, runInShell: false);
    llamaServerProcess = process;
    llamaServerPid = process.pid;
    llamaMemoryStatus = 'llama.cpp PID ${process.pid}: ОЗУ проверяется...';
    startLlamaMemoryMonitor(process.pid);
    notifyUi();
    var exited = false;
    int? exitCode;
    unawaited(process.exitCode.then((code) {
      exited = true;
      exitCode = code;
      log('LLAMA EXIT CODE: $code');
      logAction('llama_exit', {'exit_code': code});
      if (llamaServerPid == process.pid) {
        llamaMemoryTimer?.cancel();
        llamaMemoryStatus = 'llama.cpp остановлен, exit=$code';
        notifyUi();
      }
    }));
    unawaited(process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((chunk) {
          for (final line in chunk.split(RegExp(r'\r?\n'))) {
            if (line.trim().isNotEmpty) {
              log('LLAMA STDOUT: $line');
              writeLlamaProcessLog('STDOUT', line);
            }
          }
        })
        .asFuture<void>()
        .catchError((Object error) {
          log('LLAMA STDOUT LISTEN ERROR: $error');
        }));
    unawaited(process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((chunk) {
          for (final line in chunk.split(RegExp(r'\r?\n'))) {
            if (line.trim().isNotEmpty) {
              log('LLAMA STDERR: $line');
              writeLlamaProcessLog('STDERR', line);
            }
          }
        })
        .asFuture<void>()
        .catchError((Object error) {
          log('LLAMA STDERR LISTEN ERROR: $error');
        }));
    final health = await waitForOpenAiHealth(profile.baseUrl,
        apiKey: profile.apiKey,
        isExited: () => exited,
        exitCode: () => exitCode);
    log('LLAMA HEALTHCHECK RESULT: $health');
    if (health.startsWith('ok')) {
      status = 'Запущен llama.cpp ${profile.llamaMode}: ${profile.model}';
      await refreshAvailableModels();
    } else {
      status = 'llama.cpp запущен, но API не готов: $health';
    }
  }

  Future<void> openLlamaProcessLog(ModelProfile profile) async {
    currentLlamaLogFile = null;
    if (!llamaProcessLoggingEnabled) return;
    try {
      final dir = Directory(pathJoin(appRootPath, 'logs', 'llama.cpp'));
      await dir.create(recursive: true);
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final file = File(pathJoin(dir.path, '$stamp-${profile.llamaMode}.log'));
      await file.writeAsString(
          'llama.cpp log\nprofile=${profile.name}\nmode=${profile.llamaMode}\nmodel=${profile.modelPath}\nstarted=$stamp\n\n',
          encoding: utf8);
      currentLlamaLogFile = file;
      log('LLAMA PROCESS LOG: ${file.path}');
    } catch (e) {
      log('LLAMA PROCESS LOG ERROR: $e');
    }
  }

  void writeLlamaProcessLog(String stream, String line) {
    if (!llamaProcessLoggingEnabled) return;
    try {
      currentLlamaLogFile?.writeAsStringSync(
          '[${DateTime.now().toIso8601String()}] $stream: $line\n',
          mode: FileMode.append,
          encoding: utf8);
    } catch (_) {}
  }

  Future<void> stopLocalLlama({String reason = 'manual stop'}) async {
    llamaMemoryTimer?.cancel();
    final process = llamaServerProcess;
    if (process != null) {
      final killed = process.kill();
      log('LLAMA STOP: reason=$reason pid=${process.pid} killed=$killed');
      logAction('llama_stop', {
        'reason': reason,
        'pid': process.pid,
        'killed': killed,
      });
    }
    llamaServerProcess = null;
    llamaServerPid = null;
    llamaMemoryStatus = '';
    currentLlamaLogFile = null;
    notifyUi();
  }

  Future<void> shutdown() async {
    await stopLocalLlama(reason: 'application shutdown');
  }

  Future<String> waitForOpenAiHealth(String baseUrl,
      {required String apiKey,
      required bool Function() isExited,
      required int? Function() exitCode}) async {
    final cleanedBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
    for (var attempt = 1; attempt <= 30; attempt++) {
      if (isExited())
        return 'process exited before healthcheck, exit_code=${exitCode()}';
      try {
        final uri = Uri.parse('$cleanedBase/models');
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 2);
        final request =
            await client.getUrl(uri).timeout(const Duration(seconds: 2));
        if (apiKey.isNotEmpty)
          request.headers
              .set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
        final response =
            await request.close().timeout(const Duration(seconds: 3));
        final text = await utf8.decodeStream(response);
        log('LLAMA HEALTHCHECK HTTP ${response.statusCode}: ${truncateMiddle(text, 8000)}');
        if (response.statusCode >= 200 && response.statusCode < 300)
          return 'ok attempt=$attempt';
      } catch (error) {
        log('LLAMA HEALTHCHECK attempt=$attempt error=$error');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return 'timeout waiting for $cleanedBase/models';
  }

  void startLlamaMemoryMonitor(int pid) {
    llamaMemoryTimer?.cancel();
    unawaited(updateLlamaMemoryStatus(pid));
    llamaMemoryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(updateLlamaMemoryStatus(pid));
    });
  }

  Future<void> updateLlamaMemoryStatus(int pid) async {
    try {
      int? bytes;
      if (Platform.isWindows) {
        final result = await Process.run(
          'powershell',
          [
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-Command',
            "(Get-Process -Id $pid -ErrorAction SilentlyContinue).WorkingSet64"
          ],
          stdoutEncoding: const Utf8Codec(allowMalformed: true),
          stderrEncoding: const Utf8Codec(allowMalformed: true),
        ).timeout(const Duration(seconds: 3));
        final parts = result.stdout
            .toString()
            .trim()
            .split(RegExp(r'\s+'))
            .where((e) => e.trim().isNotEmpty)
            .toList();
        bytes = parts.isEmpty ? null : int.tryParse(parts.last);
      } else {
        final result = await Process.run(
                'sh', ['-c', "ps -o rss= -p $pid 2>/dev/null | tail -n 1"],
                stdoutEncoding: const Utf8Codec(allowMalformed: true))
            .timeout(const Duration(seconds: 3));
        final kb = int.tryParse(result.stdout.toString().trim());
        if (kb != null) bytes = kb * 1024;
      }
      if (bytes == null || bytes <= 0) return;
      llamaMemoryStatus = 'llama.cpp PID $pid • ОЗУ: ${formatBytes(bytes)}';
      notifyUi();
    } catch (_) {
      // Memory indicator is best-effort only.
    }
  }

  String llamaInstallRelativeDir(String mode) =>
      pathJoin('tools', 'llama.cpp', mode);

  String selectLlamaAssetName(String mode, List<String> assets) {
    final lowerMode = mode.toLowerCase();
    final osTokens = Platform.isWindows
        ? ['win', 'windows']
        : Platform.isAndroid
            ? ['android']
            : Platform.isLinux
                ? ['linux', 'ubuntu']
                : Platform.isMacOS
                    ? ['macos', 'osx', 'darwin']
                    : [Platform.operatingSystem];
    bool good(String name) {
      final n = name.toLowerCase();
      if (!(n.endsWith('.zip') ||
          n.endsWith('.tar.gz') ||
          n.endsWith('.tgz') ||
          n.endsWith('.7z'))) return false;
      if (!osTokens.any(n.contains)) return false;
      if (lowerMode == 'cuda')
        return n.contains('cuda') || n.contains('cu12') || n.contains('cublas');
      if (lowerMode == 'vulkan') return n.contains('vulkan');
      if (lowerMode == 'cpu')
        return !n.contains('cuda') &&
            !n.contains('vulkan') &&
            !n.contains('metal');
      return true;
    }

    return assets.firstWhere(good,
        orElse: () => assets.firstWhere((n) => n.toLowerCase().endsWith('.zip'),
            orElse: () => assets.isEmpty ? '' : assets.first));
  }

  Future<String> installLlamaCppFromGithub(String mode) async {
    final selectedMode =
        mode.trim().toLowerCase().isEmpty ? 'cpu' : mode.trim().toLowerCase();
    final uri = Uri.parse(
        'https://api.github.com/repos/ggml-org/llama.cpp/releases/latest');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    final request =
        await client.getUrl(uri).timeout(const Duration(seconds: 20));
    request.headers.set(HttpHeaders.userAgentHeader, 'AI-Agent/$appVersion');
    final response = await request.close().timeout(const Duration(seconds: 45));
    final body = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300)
      return 'LLAMA_CPP_INSTALL_FAILED: GitHub HTTP ${response.statusCode}\n$body';
    final json = jsonDecode(body) as Map<String, dynamic>;
    final tag = json['tag_name']?.toString() ?? 'latest';
    final assetsRaw = json['assets'] as List<dynamic>? ?? const [];
    final assets = <String, String>{};
    for (final item in assetsRaw) {
      if (item is! Map<String, dynamic>) continue;
      final name = item['name']?.toString() ?? '';
      final url = item['browser_download_url']?.toString() ?? '';
      if (name.isNotEmpty && url.isNotEmpty) assets[name] = url;
    }
    final assetName = selectLlamaAssetName(selectedMode, assets.keys.toList());
    if (assetName.isEmpty) {
      return 'LLAMA_CPP_INSTALL_FAILED: в latest-релизе $tag не найден подходящий архив для ${Platform.operatingSystem}/$selectedMode. Можно скачать вручную и распаковать в ${pathJoin(appRootPath, llamaInstallRelativeDir(selectedMode))}';
    }
    final url = assets[assetName]!;
    final downloads = Directory(pathJoin(appRootPath, 'tools', 'downloads'));
    await downloads.create(recursive: true);
    final archivePath = pathJoin(downloads.path, assetName);
    final downloadResult = await downloadUrlToFile(url, archivePath);
    if (!downloadResult.startsWith('OK'))
      return 'LLAMA_CPP_INSTALL_FAILED: $downloadResult';
    final dest =
        Directory(pathJoin(appRootPath, llamaInstallRelativeDir(selectedMode)));
    if (await dest.exists()) await dest.delete(recursive: true);
    await dest.create(recursive: true);
    final extracted = await extractDownloadedArchive(File(archivePath), dest);
    await saveAppSettings();
    await refreshAvailableModels();
    return 'LLAMA_CPP_INSTALLED\nMODE: $selectedMode\nTAG: $tag\nASSET: $assetName\nARCHIVE: $archivePath\nDEST: ${dest.path}\n$extracted';
  }

  Future<String> createLlamaCppManualFolders() async {
    final created = <String>[];
    for (final rel in const [
      'tools/downloads',
      'tools/llama.cpp/cpu',
      'tools/llama.cpp/vulkan',
      'tools/llama.cpp/cuda',
      'models'
    ]) {
      final dir = Directory(
          pathJoin(appRootPath, rel.replaceAll('/', Platform.pathSeparator)));
      await dir.create(recursive: true);
      created.add(dir.path);
    }
    return 'LLAMA_CPP_FOLDERS_READY\n${created.join('\n')}';
  }

  Future<String> installLlamaCppFromArchive(
      String archivePath, String mode) async {
    final selectedMode =
        mode.trim().toLowerCase().isEmpty ? 'cpu' : mode.trim().toLowerCase();
    final archive = File(archivePath.trim());
    if (!await archive.exists()) {
      return 'LLAMA_CPP_INSTALL_FAILED: archive not found: ${archive.path}';
    }
    final downloads = Directory(pathJoin(appRootPath, 'tools', 'downloads'));
    await downloads.create(recursive: true);
    final cachedArchive =
        File(pathJoin(downloads.path, pathBasename(archive.path)));
    if (archive.absolute.path.toLowerCase() !=
        cachedArchive.absolute.path.toLowerCase()) {
      await archive.copy(cachedArchive.path);
    }
    final dest =
        Directory(pathJoin(appRootPath, llamaInstallRelativeDir(selectedMode)));
    if (await dest.exists()) await dest.delete(recursive: true);
    await dest.create(recursive: true);
    final extracted = await extractDownloadedArchive(cachedArchive, dest);
    await refreshAvailableModels();
    return 'LLAMA_CPP_INSTALLED_FROM_ARCHIVE\nMODE: $selectedMode\nARCHIVE: ${cachedArchive.path}\nDEST: ${dest.path}\n$extracted';
  }

  Future<String> downloadUrlToFile(String url, String targetPath) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 20);
      final request = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 30));
      request.headers.set(HttpHeaders.userAgentHeader, 'AI-Agent/$appVersion');
      final response =
          await request.close().timeout(const Duration(minutes: 20));
      if (response.statusCode < 200 || response.statusCode >= 300)
        return 'HTTP ${response.statusCode}: $url';
      final file = File(targetPath);
      await file.parent.create(recursive: true);
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        if (received % (32 * 1024 * 1024) < chunk.length) {
          status =
              'Загрузка: ${pathBasename(targetPath)} • ${formatBytes(received)}';
          notifyUi();
        }
      }
      await sink.close();
      return 'OK ${formatBytes(received)}';
    } catch (e) {
      return 'ERROR $e';
    }
  }

  Future<String> extractDownloadedArchive(File archive, Directory dest) async {
    final lower = archive.path.toLowerCase();
    try {
      if (lower.endsWith('.zip')) {
        if (Platform.isWindows) {
          final cmd =
              "Expand-Archive -LiteralPath ${psQuote(archive.path)} -DestinationPath ${psQuote(dest.path)} -Force";
          final r = await Process.run('powershell',
                  ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', cmd],
                  stdoutEncoding: const Utf8Codec(allowMalformed: true),
                  stderrEncoding: const Utf8Codec(allowMalformed: true))
              .timeout(const Duration(minutes: 10));
          return 'EXTRACT zip exit=${r.exitCode}\n${r.stdout}\n${r.stderr}';
        }
        final r = await Process.run(
                'unzip', ['-o', archive.path, '-d', dest.path],
                stdoutEncoding: const Utf8Codec(allowMalformed: true),
                stderrEncoding: const Utf8Codec(allowMalformed: true))
            .timeout(const Duration(minutes: 10));
        return 'EXTRACT zip exit=${r.exitCode}\n${r.stdout}\n${r.stderr}';
      }
      if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
        final r = await Process.run(
                'tar', ['-xzf', archive.path, '-C', dest.path],
                stdoutEncoding: const Utf8Codec(allowMalformed: true),
                stderrEncoding: const Utf8Codec(allowMalformed: true))
            .timeout(const Duration(minutes: 10));
        return 'EXTRACT tar exit=${r.exitCode}\n${r.stdout}\n${r.stderr}';
      }
      if (lower.endsWith('.7z')) {
        final sevenZip =
            findExecutableInTools(['7z.exe', '7za.exe', '7zz.exe', '7z']);
        if (sevenZip == null) return 'EXTRACT skipped: 7z not found';
        final r = await Process.run(
                sevenZip.path, ['x', '-y', '-o${dest.path}', archive.path],
                stdoutEncoding: const Utf8Codec(allowMalformed: true),
                stderrEncoding: const Utf8Codec(allowMalformed: true))
            .timeout(const Duration(minutes: 10));
        return 'EXTRACT 7z exit=${r.exitCode}\n${r.stdout}\n${r.stderr}';
      }
      return 'EXTRACT skipped: unsupported archive type ${archive.path}';
    } catch (e) {
      return 'EXTRACT_ERROR: $e';
    }
  }

  Future<List<HfModelSearchResult>> searchHuggingFaceGgufModels(
      String query) async {
    final q = query.trim().isEmpty ? 'gguf' : query.trim();
    final uri = Uri.parse(
        'https://huggingface.co/api/models?search=${Uri.encodeQueryComponent(q)}&limit=20&full=false');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    final request =
        await client.getUrl(uri).timeout(const Duration(seconds: 20));
    request.headers.set(HttpHeaders.userAgentHeader, 'AI-Agent/$appVersion');
    final response = await request.close().timeout(const Duration(seconds: 45));
    final body = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300)
      throw StateError('HuggingFace HTTP ${response.statusCode}: $body');
    final raw = jsonDecode(body) as List<dynamic>;
    return raw
        .map((e) {
          final m = e is Map<String, dynamic> ? e : <String, dynamic>{};
          final id = m['id']?.toString() ?? m['modelId']?.toString() ?? '';
          final downloads = int.tryParse(m['downloads']?.toString() ?? '') ?? 0;
          return HfModelSearchResult(id: id, downloads: downloads);
        })
        .where((e) => e.id.isNotEmpty)
        .toList();
  }

  Future<List<HfFileEntry>> listHuggingFaceGgufFiles(String repoId) async {
    final uri = Uri.parse(
        'https://huggingface.co/api/models/$repoId/tree/main?recursive=1');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    final request =
        await client.getUrl(uri).timeout(const Duration(seconds: 20));
    request.headers.set(HttpHeaders.userAgentHeader, 'AI-Agent/$appVersion');
    final response = await request.close().timeout(const Duration(seconds: 60));
    final body = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300)
      throw StateError('HuggingFace HTTP ${response.statusCode}: $body');
    final raw = jsonDecode(body) as List<dynamic>;
    final result = <HfFileEntry>[];
    for (final e in raw) {
      final m = e is Map<String, dynamic> ? e : <String, dynamic>{};
      final path = m['path']?.toString() ?? '';
      if (!path.toLowerCase().endsWith('.gguf')) continue;
      if (!(path.toLowerCase().contains('mmproj') ||
          path.toLowerCase().endsWith('.gguf'))) continue;
      final size = int.tryParse(m['size']?.toString() ?? '') ?? 0;
      result.add(HfFileEntry(repoId: repoId, path: path, size: size));
    }
    result.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    return result;
  }

  Future<String> downloadHuggingFaceFile(HfFileEntry entry) async {
    final target = File(pathJoin(
        appRootPath,
        'models',
        entry.repoId.replaceAll('/', '__'),
        entry.path.replaceAll('/', Platform.pathSeparator)));
    final url =
        'https://huggingface.co/${entry.repoId}/resolve/main/${Uri.encodeFull(entry.path)}?download=true';
    final result = await downloadUrlToFile(url, target.path);
    if (result.startsWith('OK')) {
      await refreshAvailableModels();
      return 'HF_MODEL_DOWNLOADED\nREPO: ${entry.repoId}\nFILE: ${entry.path}\nTARGET: ${target.path}\n$result';
    }
    return 'HF_MODEL_DOWNLOAD_FAILED\nREPO: ${entry.repoId}\nFILE: ${entry.path}\n$result';
  }

  String? findLlamaServer(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return null;
    final names = Platform.isWindows
        ? ['llama-server.exe', 'server.exe']
        : ['llama-server', 'server', 'llama-server.android'];
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && names.contains(pathBasename(entity.path)))
        return entity.path;
    }
    return null;
  }

  Future<void> loadLatestSessionForCurrentProject() async {
    final project = currentProject;
    if (project == null) return;
    final sessionsDir =
        Directory(pathJoin(project.path, '.cppagent', 'sessions'));
    await sessionsDir.create(recursive: true);
    final files = sessionsDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.jsonl'))
        .toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    if (files.isEmpty) return;
    final lines = await files.first.readAsLines(encoding: utf8);
    messages = lines.map((line) {
      final data = jsonDecode(line) as Map<String, dynamic>;
      return ChatMessage.fromJson(data);
    }).toList();
  }

  Future<void> appendSession(ChatMessage message) async {
    final project = currentProject;
    if (project == null) return;
    final sessionsDir =
        Directory(pathJoin(project.path, '.cppagent', 'sessions'));
    await sessionsDir.create(recursive: true);
    final file = File(pathJoin(sessionsDir.path, 'session.jsonl'));
    await file.writeAsString('${jsonEncode(message.toJson())}\n',
        mode: FileMode.append, encoding: utf8);
  }

  void resetTaskState() {
    taskToolActions = 0;
    taskFileMutations = 0;
    taskCommandRuns = 0;
    taskFailedCommands = 0;
    lastCommandExitCode = null;
    lastCommandText = '';
    lastCommandResultText = '';
    activeTaskText = '';
    pendingFileChanges.clear();
    taskFileChanges.clear();
    taskActionSummaries.clear();
    taskFileMutationAttempts.clear();
    problemSolvingAttempts = 0;
    autoRecoveryAttempts = 0;
    taskInternetActions = 0;
    lastFinalAnswerQualityIssue = '';
  }

  String classifyTaskKind(String prompt) {
    final lower = prompt.toLowerCase();
    if (lower.contains('почт') ||
        lower.contains('email') ||
        lower.contains('e-mail') ||
        lower.contains('imap') ||
        lower.contains('smtp')) return 'email';
    if (lower.contains('презентац') ||
        lower.contains('pptx') ||
        lower.contains('слайды')) return 'presentation';
    if (lower.contains('документ') ||
        lower.contains('docx') ||
        lower.contains('xlsx') ||
        lower.contains('pdf') ||
        lower.contains('требован')) return 'document_work';
    if (lower.contains('папк') ||
        lower.contains('файл') ||
        lower.contains('архив') ||
        lower.contains('o:\\') ||
        lower.contains('удали') ||
        lower.contains('создай файл')) return 'device_files';
    if (lower.contains('ssh') ||
        lower.contains('telnet') ||
        lower.contains('powershell') ||
        lower.contains('настрой') ||
        lower.contains('сервер')) return 'system_admin';
    if (lower.contains('c++') ||
        lower.contains('python') ||
        lower.contains('flutter') ||
        lower.contains('php') ||
        lower.contains('html') ||
        lower.contains('програм') ||
        lower.contains('код') ||
        lower.contains('скомпил')) return 'software';
    return 'general';
  }

  bool taskLooksLikeSoftwareCreation(String prompt) =>
      classifyTaskKind(prompt) == 'software';

  bool taskNeedsProjectPreflight(String prompt) {
    final lower = prompt.toLowerCase();
    if (classifyTaskKind(prompt) != 'software') return false;
    if (lower.contains('найди документ') ||
        lower.contains('найти документ') ||
        lower.contains('на компьютере')) return false;
    return true;
  }

  Future<String> projectPreflightAudit(String prompt) async {
    final project = currentProject;
    if (project == null) return '';
    if (!taskNeedsProjectPreflight(prompt)) return '';
    final kind = classifyTaskKind(prompt);
    final entries = <String>[];
    try {
      for (final entity in Directory(project.path)
          .listSync(recursive: false, followLinks: false)) {
        final name = pathBasename(entity.path);
        if (name == '.cppagent') continue;
        entries.add(entity is Directory ? 'DIR:$name' : 'FILE:$name');
      }
    } catch (e) {
      entries.add('PROJECT_LIST_ERROR:$e');
    }
    final obviousBuildTrash = entries
        .where((e) =>
            e.contains('CMakeFiles') ||
            e.contains('CMakeCache.txt') ||
            e.contains('cmake_install.cmake') ||
            e.contains('build.ninja'))
        .join(', ');
    final hasUserFiles = entries
        .any((e) => !e.contains('CMakeFiles') && !e.contains('CMakeCache.txt'));
    final buffer = StringBuffer();
    buffer.writeln('[PROJECT_PREFLIGHT_AUDIT]');
    buffer.writeln('task_kind=$kind');
    buffer.writeln('project=${project.path}');
    buffer.writeln('root_entries=${entries.take(80).join(' | ')}');
    if (obviousBuildTrash.isNotEmpty)
      buffer.writeln('obvious_build_artifacts=$obviousBuildTrash');
    buffer.writeln('rules:');
    buffer.writeln(
        '- Сначала определи, соответствуют ли существующие файлы задаче пользователя.');
    buffer.writeln(
        '- Если файлов нет или они не относятся к задаче, создай нужную структуру с нуля.');
    buffer.writeln(
        '- Если файлы явно чужие/мусорные для текущей задачи, используй move_path в `.cppagent/reserved_before_task/<timestamp>/`, затем создавай правильный проект.');
    buffer.writeln(
        '- Не переписывай один файл десятки раз. После 2-4 изменений запускай run_tests/run_command или читай ошибку и исправляй точечно.');
    buffer.writeln(
        '- Для разработки ПО обязательный порядок: audit -> план -> файлы -> сборка/запуск -> исправления -> повторная проверка -> итог.');
    buffer.writeln(
        '- Для работы с документами/файлами устройства используй специальные инструменты чтения/поиска, а не компиляцию.');
    buffer.writeln('has_user_files=$hasUserFiles');
    buffer.writeln('[/PROJECT_PREFLIGHT_AUDIT]');
    return buffer.toString();
  }

  Future<void> reserveObviousStaleBuildArtifacts(String prompt) async {
    final project = currentProject;
    if (project == null || !taskLooksLikeSoftwareCreation(prompt)) return;
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final reserveDir = Directory(
        pathJoin(project.path, '.cppagent', 'reserved_before_task', timestamp));
    final names = const [
      'CMakeFiles',
      'CMakeCache.txt',
      'cmake_install.cmake',
      'build.ninja',
      'Makefile'
    ];
    var moved = 0;
    for (final name in names) {
      final sourcePath = pathJoin(project.path, name);
      final dir = Directory(sourcePath);
      final file = File(sourcePath);
      try {
        if (await dir.exists()) {
          await reserveDir.create(recursive: true);
          await dir.rename(pathJoin(reserveDir.path, name));
          moved++;
        } else if (await file.exists()) {
          await reserveDir.create(recursive: true);
          await file.rename(pathJoin(reserveDir.path, name));
          moved++;
        }
      } catch (e) {
        log('PROJECT PREFLIGHT RESERVE ERROR: $sourcePath -> ${reserveDir.path}: $e');
      }
    }
    if (moved > 0) {
      log('PROJECT PREFLIGHT RESERVED STALE BUILD ARTIFACTS: moved=$moved dir=${reserveDir.path}');
    }
  }

  Future<void> sendPrompt(String rawPrompt, String attachmentPath) async {
    final project = currentProject;
    if (project == null) return;
    final prompt = rawPrompt.trim();
    if (prompt.isEmpty) return;
    busy = true;
    cancelRequested = false;
    status = 'Агент выполняет задачу...';
    expandedDiffKey = null;
    expandedActionKey = null;
    expandedCodeBlockKey = null;
    resetTaskState();
    log('USER PROMPT (${project.name}): ${truncateMiddle(prompt, 8000)}');
    log('AGENT RIGHTS: permission=${permissionMode.label}; creationMode=${creationMode.label}; qualityCheck=$qualityCheckEnabled');
    logAction('user_prompt', {
      'project_name': project.name,
      'prompt': truncateMiddle(prompt, 20000),
      'permission_mode': permissionMode.name,
      'creation_mode': creationMode.name,
      'quality_check': qualityCheckEnabled
    });
    await reserveObviousStaleBuildArtifacts(prompt);
    final preflightAudit = await projectPreflightAudit(prompt);
    final serviceContext = StringBuffer();
    if (preflightAudit.trim().isNotEmpty) {
      serviceContext.writeln(preflightAudit.trim());
      serviceContext.writeln();
    }
    final attachments = <String>[...attachedFiles];
    final selectedLocationSnapshot = <String>[...selectedLocations];
    final singleAttachment = attachmentPath.trim();
    if (singleAttachment.isNotEmpty && !attachments.contains(singleAttachment))
      attachments.add(singleAttachment);
    if (permissionMode == PermissionMode.fullAccess &&
        taskLooksLikeComputerWideSearch(prompt)) {
      allowComputerSearch = true;
      allowDeviceFileAccess = true;
    }
    for (final attachment in attachments) {
      final file = File(attachment);
      final dir = Directory(attachment);
      if (await file.exists()) {
        log('ATTACHMENT READ: $attachment (${await file.length()} bytes)');
        if (attachment.toLowerCase().endsWith('.zip')) {
          serviceContext.writeln('[ATTACHED_ZIP path="$attachment"]');
          serviceContext.writeln(
              'Архив приложен по пути. Используй inspect_zip/extract_zip при необходимости.');
          serviceContext.writeln('[/ATTACHED_ZIP]');
        } else {
          final parsed =
              await const office.OfficeDocumentParser().parseFile(attachment);
          serviceContext.writeln(
              '[ATTACHED_DOCUMENT path="$attachment" format="${parsed.kind.label}"]');
          serviceContext.writeln(parsed.toAgentText(maxTextChars: 30000));
          serviceContext.writeln('[/ATTACHED_DOCUMENT]');
        }
      } else if (await dir.exists()) {
        lastDeviceDirectoryPath = attachment;
        serviceContext.writeln('[ATTACHED_DIRECTORY path="$attachment"]');
        serviceContext.writeln(
            'Папка приложена как расположение. Для просмотра используй list_device_directory/read_device_folder_texts, для упаковки — archive_device_children.');
        serviceContext.writeln('[/ATTACHED_DIRECTORY]');
      } else {
        serviceContext.writeln(
            '[ATTACHMENT_ERROR] File or directory not found: $attachment');
        log('ATTACHMENT MISSING: $attachment');
      }
      serviceContext.writeln();
    }
    for (final location in selectedLocationSnapshot) {
      final dir = Directory(location);
      final exists = await dir.exists();
      if (exists) lastDeviceDirectoryPath = location;
      serviceContext
          .writeln('[SELECTED_LOCATION path="$location" exists="$exists"]');
      serviceContext.writeln(
          'Пользователь выбрал это расположение через кнопку «Выбрать расположение». Используй его для задач чтения, анализа, архивации или сохранения, если запрос не содержит другого точного пути.');
      serviceContext.writeln('[/SELECTED_LOCATION]');
      serviceContext.writeln();
    }
    attachedFiles.clear();
    selectedLocations.clear();
    final hiddenTaskContext = serviceContext.toString().trim();
    activeTaskText = hiddenTaskContext.isEmpty
        ? prompt
        : '$prompt\n\n[HIDDEN_TASK_CONTEXT]\n$hiddenTaskContext\n[/HIDDEN_TASK_CONTEXT]';
    final profileForLimits = currentProfile;
    if (profileForLimits != null)
      runtimeLimitsCache.remove(runtimeCacheKey(profileForLimits));
    final userMessage = ChatMessage(role: 'user', content: prompt);
    messages.add(userMessage);
    await appendSession(userMessage);
    await startLiveProgress('⏳ Задача получена. Готовлю действия агента...');
    recalculateContext();
    notifyUi();
    if (looksLikeToolInventoryQuestion(prompt)) {
      final text = '''**Среда выполнения:** ${hostEnvironmentSummary()}

**Локальные инструменты из tools:**
${localToolsCompactSummary(maxItems: 80)}

Команды `run_command` и `run_tests` запускаются с приоритетом папки `tools/$hostOsSegment/$hostArchSegment` и всех найденных подпапок с программами. Если в tools лежит `g++.exe`, `clang++.exe`, `cl.exe`, `python.exe`, `cmake.exe`, `ninja.exe` или другие утилиты, агент добавит их папки в PATH перед системным PATH.

**Python:** пакеты не ставятся в общий Python. При `pip install`, `python -m pip install`, `pytest` или ошибке `ModuleNotFoundError` агент создаёт окружение проекта `.cppagent/python_venv`, устанавливает пакеты туда и запускает Python через это окружение.

**C++/CMake:** `run_tests` теперь сам ищет `*.cpp` в проекте и подпапках, создаёт/исправляет минимальный `CMakeLists.txt` только для сборки найденного исходника и использует CMake/Visual Studio, если нет `g++`.''';
      await finishLiveProgress(text, actionSummaries: currentActionSummaries());
      status = 'Готово';
      busy = false;
      recalculateContext();
      notifyUi();
      return;
    }
    try {
      if (await tryDirectDeviceArchiveTask(prompt, selectedLocationSnapshot)) {
        status = 'Готово';
        return;
      }
      await tryDirectDocumentSearchTask(prompt, selectedLocationSnapshot);
      await tryDirectComputerWideSearchTask(prompt);
      await runAgentLoop();
      status = 'Готово';
    } catch (error, stack) {
      await removeLiveProgress();
      final message =
          ChatMessage(role: 'assistant', content: 'Ошибка агента: $error');
      messages.add(message);
      await appendSession(message);
      log('AGENT ERROR: $error\n$stack');
      status = 'Ошибка';
    } finally {
      busy = false;
      cancelRequested = false;
      final pendingProject = pendingProjectOpenAfterTask;
      pendingProjectOpenAfterTask = null;
      if (pendingProject != null) {
        unawaited(openProject(pendingProject));
      }
      recalculateContext();
      notifyUi();
    }
  }

  bool looksLikeArchiveEachItemTask(String prompt) {
    final lower = prompt.toLowerCase();
    final hasArchiveVerb = lower.contains('упакуй') ||
        lower.contains('заархив') ||
        lower.contains('архив') ||
        lower.contains('zip');
    final each = lower.contains('кажд') ||
        lower.contains('отдельн') ||
        lower.contains('по отдельности');
    return hasArchiveVerb && each;
  }

  String extractExplicitDevicePathFromPrompt(String prompt) {
    final quoted = RegExp(r'["«]([A-Za-zА-Яа-я]:\\[^"»\n]+|/[^"»\n]+)["»]')
        .firstMatch(prompt);
    if (quoted != null) return quoted.group(1)!.trim();
    final win = RegExp(r'([A-Za-zА-Яа-я]:\\[^\n]+)').firstMatch(prompt);
    if (win != null)
      return win.group(1)!.trim().replaceAll(RegExp(r'[\s\.,;]+$'), '');
    return '';
  }

  Future<bool> tryDirectDeviceArchiveTask(
      String prompt, List<String> selectedLocationSnapshot) async {
    if (!looksLikeArchiveEachItemTask(prompt)) return false;
    final explicit = extractExplicitDevicePathFromPrompt(prompt);
    final source = explicit.isNotEmpty
        ? explicit
        : (selectedLocationSnapshot.isNotEmpty
            ? selectedLocationSnapshot.last
            : lastDeviceDirectoryPath);
    if (source.trim().isEmpty) return false;
    log('DIRECT DEVICE ARCHIVE TASK: source=$source prompt=${truncateMiddle(prompt, 1000)}');
    await ensureLiveProgress(
        '📦 Упаковываю элементы выбранной папки в отдельные архивы...');
    final result = await executeTool(ToolCall(
        name: 'archive_device_children', args: {'path': source, 'output': ''}));
    final toolMessage = ChatMessage(
        role: 'user',
        internal: true,
        content: 'Tool result for archive_device_children\n$result');
    messages.add(toolMessage);
    await appendSession(toolMessage);
    await finishLiveProgress(result,
        fileChanges: takeTaskFileChanges(),
        actionSummaries: currentActionSummaries());
    logAction('direct_archive_task_finished', {'source': source});
    return true;
  }

  bool looksLikeFindDocumentTask(String prompt) {
    final lower = prompt.toLowerCase();
    return (lower.contains('найди документ') ||
            lower.contains('найти документ')) &&
        (lower.contains('папк') ||
            lower.contains(':\\') ||
            lower.contains('/'));
  }

  bool taskLooksLikeComputerWideSearch(String prompt) {
    final lower = prompt.toLowerCase();
    final asksLocalSearch = lower.contains('на компьютере') ||
        lower.contains('по компьютеру') ||
        lower.contains('на устройстве') ||
        lower.contains('по устройству');
    final asksDocuments = lower.contains('документ') ||
        lower.contains('файл') ||
        lower.contains('информаци');
    final asksFind = lower.contains('поищи') ||
        lower.contains('найди') ||
        lower.contains('найти') ||
        lower.contains('поиск');
    return asksLocalSearch && asksFind && asksDocuments;
  }

  Future<bool> tryDirectDocumentSearchTask(
      String prompt, List<String> selectedLocationSnapshot) async {
    if (!looksLikeFindDocumentTask(prompt)) return false;
    final explicit = extractExplicitDevicePathFromPrompt(prompt);
    final source = explicit.isNotEmpty
        ? explicit
        : (selectedLocationSnapshot.isNotEmpty
            ? selectedLocationSnapshot.last
            : lastDeviceDirectoryPath);
    if (source.trim().isEmpty) return false;
    log('DIRECT DEVICE DOCUMENT SEARCH TASK: source=$source prompt=${truncateMiddle(prompt, 1000)}');
    await ensureLiveProgress(
        '🔎 Ищу релевантные документы в выбранной папке и подпапках...');
    final result = await executeTool(ToolCall(
        name: 'search_device_documents',
        args: {'path': source, 'query': prompt, 'recursive': 'true'}));
    final toolMessage = ChatMessage(
        role: 'user',
        internal: true,
        content: 'Tool result for search_device_documents\n$result');
    messages.add(toolMessage);
    await appendSession(toolMessage);
    // После специализированного поиска всё равно отдаём результат модели для формулировки ответа, но не позволяем ей подменять задачу простым listing/read-all.
    return false;
  }

  List<String> defaultComputerSearchRoots() {
    final roots = <String>{};
    void add(String? path) {
      final clean = (path ?? '').trim();
      if (clean.isEmpty) return;
      if (Directory(clean).existsSync())
        roots.add(Directory(clean).absolute.path);
    }

    add(currentProject?.path);
    add(projectsRoot.path);
    add(appRootPath);
    final userProfile =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (userProfile != null && userProfile.trim().isNotEmpty) {
      add(pathJoin(userProfile, 'Documents'));
      add(pathJoin(userProfile, 'Desktop'));
      add(pathJoin(userProfile, 'Downloads'));
    }
    if (Platform.isWindows) {
      final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
      add(pathJoin(systemRoot, 'System32'));
      add(pathJoin(systemRoot, 'SysWOW64'));
    }
    return roots.toList(growable: false);
  }

  String compactSearchNeedle(String prompt) {
    final technicalToken =
        RegExp(r'[a-zA-Z][a-zA-Z0-9_.-]{2,}').firstMatch(prompt)?.group(0);
    if (technicalToken != null) return technicalToken;

    final terms = extractDocumentSearchTerms(prompt)
        .where((term) =>
            term.length >= 3 &&
            !const {
              'поищи',
              'найди',
              'найти',
              'нади',
              'компьютере',
              'компьютеру',
              'устройстве',
              'информацию',
              'информация',
              'содержащие',
              'содержащих',
              'документы',
              'документ'
            }.contains(term))
        .toList(growable: false);
    if (terms.isNotEmpty) return terms.first;
    final ascii = RegExp(r'[a-zA-Z0-9_.-]{3,}').firstMatch(prompt)?.group(0);
    return ascii ?? prompt;
  }

  Future<bool> tryDirectComputerWideSearchTask(String prompt) async {
    if (!taskLooksLikeComputerWideSearch(prompt)) return false;
    final roots = defaultComputerSearchRoots();
    if (roots.isEmpty) return false;
    if (permissionMode == PermissionMode.fullAccess) {
      allowComputerSearch = true;
      allowDeviceFileAccess = true;
    }
    final needle = compactSearchNeedle(prompt);
    log('DIRECT COMPUTER SEARCH TASK: needle=$needle roots=${roots.join(' | ')} prompt=${truncateMiddle(prompt, 1000)}');
    await ensureLiveProgress(
        '🔎 Ищу по компьютеру и проверяю документы через встроенные парсеры...');
    final result = StringBuffer()
      ..writeln('DIRECT_COMPUTER_SEARCH_RESULT')
      ..writeln('QUERY: $prompt')
      ..writeln('NEEDLE: $needle')
      ..writeln('ROOTS: ${roots.join(' | ')}')
      ..writeln();

    for (final root in roots) {
      final fsCall = ToolCall(
          name: 'filesystem_search',
          args: {'query': needle, 'root': root, 'max_results': '20'});
      final fsResult = await executeTool(fsCall);
      recordActionAttempt(fsCall, fsResult);
      result
        ..writeln('===== FILESYSTEM_SEARCH: $root =====')
        ..writeln(fsResult)
        ..writeln();
    }

    for (final root in roots.where((r) =>
        !RegExp(r'\\Windows\\(System32|SysWOW64)$', caseSensitive: false)
            .hasMatch(r))) {
      final docCall = ToolCall(name: 'search_device_documents', args: {
        'path': root,
        'query': prompt,
        'recursive': 'true',
        'max_files': '80',
        'max_chars_per_file': '30000'
      });
      final docResult = await executeTool(docCall);
      recordActionAttempt(docCall, docResult);
      result
        ..writeln('===== DOCUMENT_SEARCH: $root =====')
        ..writeln(docResult)
        ..writeln();
    }

    final toolMessage = ChatMessage(
        role: 'user',
        internal: true,
        content:
            'Tool result for direct_computer_search\n${result.toString().trimRight()}');
    messages.add(toolMessage);
    await appendSession(toolMessage);
    return false;
  }

  Future<void> runAgentLoop() async {
    var continued = false;
    var emptyModelResponses = 0;
    var noActionRetries = 0;
    for (var iteration = 1; iteration <= maxAgentIterations; iteration++) {
      if (cancelRequested) {
        await finishLiveProgress('⛔ Выполнение остановлено пользователем.',
            fileChanges: takeTaskFileChanges());
        log('AGENT LOOP STOP: cancelled by user before iteration $iteration.');
        logAction('task_cancelled_by_user', taskStateJson());
        break;
      }
      log('AGENT ITERATION $iteration/$maxAgentIterations state=actions:$taskToolActions files:$taskFileMutations commands:$taskCommandRuns failedCommands:$taskFailedCommands lastExit:$lastCommandExitCode');
      await ensureLiveProgress(iteration == 1
          ? '🤖 Запрашиваю модель...'
          : '🤖 Продолжаю выполнение задачи, итерация $iteration...');
      final assistantText = await callModel();
      if (cancelRequested) {
        await finishLiveProgress(
            '⛔ Выполнение остановлено пользователем после ответа модели.',
            fileChanges: takeTaskFileChanges());
        log('AGENT LOOP STOP: cancelled by user after model response.');
        logAction('task_cancelled_by_user_after_model', taskStateJson());
        break;
      }
      final actions = await processAssistantText(assistantText);
      if (!actions.didAction) {
        if (lastContextMismatch ||
            lastModelFinishReason == 'context_mismatch') {
          await finishLiveProgress(
              assistantText.trim().isEmpty
                  ? lastContextMismatchDetails
                  : assistantText.trim(),
              fileChanges: takeTaskFileChanges());
          log('AGENT LOOP STOP: server context mismatch detected.');
          break;
        }
        if (taskFileMutations == 0 &&
            await tryLocalFallbackIfUseful(
                reason: lastModelFinishReason == 'length'
                    ? 'модель оборвала ответ по finish_reason=length'
                    : 'модель не вернула пригодный tool-call')) {
          log('AGENT LOOP: local fallback completed the task.');
          break;
        }
        if (assistantText.contains('<tool_call>') &&
            actions.toolCallCount == 0 &&
            actions.fileWriteCount == 0 &&
            noActionRetries < 8) {
          noActionRetries++;
          log('AGENT LOOP: malformed raw tool_call hidden; requesting one valid tool call retry=$noActionRetries');
          final retryPrompt = ChatMessage(
              role: 'user',
              content:
                  'Твой предыдущий ответ содержал сырой или повреждённый <tool_call>, поэтому он скрыт из диалога и не выполнен. Повтори действие одним корректным native tool_call или одним полностью закрытым XML <tool_call>{"name":"...","args":{...}}</tool_call>. Не выводи код в обычный текст.',
              internal: true);
          messages.add(retryPrompt);
          await appendSession(retryPrompt);
          recalculateContext();
          notifyUi();
          continue;
        }

        if (assistantText.trim().isEmpty && emptyModelResponses < 4) {
          emptyModelResponses++;
          noActionRetries++;
          log('AGENT LOOP: модель вернула пустой content без tool-call, запрашиваю видимый ответ/действия повторно ($emptyModelResponses).');
          final retryPrompt = ChatMessage(
              role: 'user',
              content: buildNoActionRetryPrompt(emptyResponse: true),
              internal: true);
          messages.add(retryPrompt);
          await appendSession(retryPrompt);
          recalculateContext();
          notifyUi();
          continue;
        }

        final incompleteReason =
            qualityCheckEnabled ? taskIncompleteReason() : '';
        if (incompleteReason.isNotEmpty && noActionRetries < 8) {
          noActionRetries++;
          log('AGENT LOOP: visible answer without required action. reason=$incompleteReason retry=$noActionRetries');
          final retryPrompt = ChatMessage(
              role: 'user',
              content:
                  buildNoActionRetryPrompt(incompleteReason: incompleteReason),
              internal: true);
          messages.add(retryPrompt);
          await appendSession(retryPrompt);
          recalculateContext();
          notifyUi();
          continue;
        }

        if (assistantText.trim().isEmpty) {
          await removeLiveProgress();
          final message = ChatMessage(
            role: 'assistant',
            content:
                'Модель несколько раз вернула пустой ответ без команд. Задача не выполнена. Проверьте не context window, а лимит генерации ответа: увеличьте Max output tokens в профиле/сервере или выберите модель, которая не обрывает tool-call.',
            actionSummaries: currentActionSummaries(),
          );
          messages.add(message);
          await appendSession(message);
          logAction('task_failed_empty_model_response',
              {'empty_responses': emptyModelResponses});
        } else if (incompleteReason.isNotEmpty) {
          if (await tryAutomaticRecovery(incompleteReason)) {
            recalculateContext();
            notifyUi();
            if (lastCommandExitCode == 0 && taskCommandRuns > 0) {
              await finishLiveProgress(buildFinalSummaryText(),
                  fileChanges: takeTaskFileChanges());
              logAction('task_finished_after_auto_recovery', taskStateJson());
              break;
            }
            continue;
          }
          await removeLiveProgress();
          final message = ChatMessage(
            role: 'assistant',
            content:
                'Агент остановлен после нескольких попыток продолжения. Последняя причина незавершённости: $incompleteReason',
            actionSummaries: currentActionSummaries(),
          );
          messages.add(message);
          await appendSession(message);
          logAction('task_stopped_incomplete',
              {'reason': incompleteReason, 'state': taskStateJson()});
        } else {
          await finishLiveProgress(buildFinalSummaryText(),
              fileChanges: const []);
          logAction('task_finished', taskStateJson());
        }
        log('AGENT LOOP STOP: модель не запросила действий. emptyResponses=$emptyModelResponses noActionRetries=$noActionRetries');
        break;
      }

      noActionRetries = 0;
      emptyModelResponses = 0;
      if (lastToolResultCompletesReadOnlyTask()) {
        await finishLiveProgress(buildReadOnlyToolFinalText(),
            fileChanges: takeTaskFileChanges(),
            actionSummaries: currentActionSummaries());
        logAction(
            'task_finished_after_successful_tool', {'tool': lastToolName});
        break;
      }
      if (iteration == maxAgentIterations) {
        final message = ChatMessage(
          role: 'assistant',
          content:
              'Достигнут лимит действий агента ($maxAgentIterations). Задача может быть не завершена полностью.',
        );
        messages.add(message);
        await appendSession(message);
        log('AGENT LOOP STOP: maxAgentIterations reached.');
        logAction('task_stopped_max_iterations', taskStateJson());
        break;
      }
      final continuation = ChatMessage(
        role: 'user',
        internal: true,
        content: continued
            ? buildContinuationPrompt(repeated: true)
            : buildContinuationPrompt(repeated: false),
      );
      continued = true;
      messages.add(continuation);
      await appendSession(continuation);
      recalculateContext();
    }
  }

  Future<bool> tryAutomaticRecovery(String reason) async {
    if (!qualityCheckEnabled) return false;
    if (autoRecoveryAttempts >= 4) return false;
    final shouldTryCpp = taskLooksLikeCppTask() &&
        (taskFileMutations > 0 || lastCommandExitCode != null);
    if (!shouldTryCpp) return false;
    autoRecoveryAttempts++;
    log('AUTO RECOVERY: attempt=$autoRecoveryAttempts reason=$reason');
    await ensureLiveProgress(
        '🛠 Автоматическое восстановление сборки, попытка $autoRecoveryAttempts...');
    final result =
        await executeTool(const ToolCall(name: 'run_tests', args: {}));
    final toolMessage = ChatMessage(
      role: 'user',
      internal: true,
      content: 'Tool result for auto_recovery run_tests\n$result',
    );
    messages.add(toolMessage);
    await appendSession(toolMessage);
    final continuation = ChatMessage(
      role: 'user',
      internal: true,
      content:
          'Автоматическое восстановление выполнило run_tests. Продолжай исходную задачу: если сборка/запуск успешны и есть BUILD_ARTIFACT_OK/FINAL_STATUS SUCCESS — дай итог; если есть BUILD_ARTIFACT_MISSING, EXIT_CODE не 0 или в исходниках есть заглушки/TODO — не объявляй задачу выполненной, исправь команду/код через инструменты и повтори проверку.',
    );
    messages.add(continuation);
    await appendSession(continuation);
    return true;
  }

  String buildContinuationPrompt({required bool repeated}) {
    final buffer = StringBuffer();
    buffer.writeln(
        'Результаты инструментов выше. Продолжай выполнение исходной задачи до полного завершения.');
    buffer.writeln(
        'Не останавливайся после плана. Если есть ошибки сборки/запуска — используй stdout/stderr из tool-result.');
    buffer.writeln(
        'Если задача требует самописный код или пользователь запретил библиотеки — пиши полный рабочий код сам, по частям, через write_file/replace_text и проверку run_tests. Не отвечай, что нужны тяжёлые библиотеки.');
    buffer.writeln(
        'Если нужна внешняя информация или пользователь просит интернет-реализацию — используй duckduckgo_search, web_fetch и download_to_project/download_to_tools.');
    if (lastCommandExitCode != null && lastCommandExitCode != 0) {
      problemSolvingAttempts++;
      buffer.writeln();
      buffer.writeln(
          'Обнаружена ошибка выполнения. Попытка решения проблемы №$problemSolvingAttempts.');
      buffer.writeln(
          'Разбей исправление на подзадачи: 1) определить тип ошибки, 2) проверить tools/list_local_tools, 3) выбрать действие: исправить код, скачать/распаковать ПО в tools, создать venv или запустить альтернативную команду, 4) повторить проверку.');
      if (isEnvironmentProblemOutput(lastCommandResultText) ||
          isBuildConfigurationProblemOutput(lastCommandResultText)) {
        if (isBuildConfigurationProblemOutput(lastCommandResultText)) {
          buffer.writeln(
              'Это похоже на ошибку структуры сборки CMake/C++: отсутствует CMakeLists.txt, source file или add_executable указывает не туда. Используй run_tests либо исправь CMakeLists.txt под реально существующий .cpp.');
        }
        buffer.writeln(
            'Это похоже на ошибку окружения/отсутствия инструмента. Не переписывай исходники на заглушку. Проверь локальные tools, попробуй альтернативный инструмент, а если его нет — предложи/выполни download_to_tools и extract_zip_to_tools в папку tools.');
        buffer.writeln('[LOCAL_TOOLS_AVAILABLE]');
        buffer
            .writeln(localToolsCompactSummary(purpose: 'build', maxItems: 12));
        buffer.writeln('[/LOCAL_TOOLS_AVAILABLE]');
      }
      buffer.writeln('Если найдёшь рабочий способ, вызови remember_solution.');
    }
    buffer.writeln(
        'Если всё действительно готово и проверено, дай краткий итог без новых действий.');
    return buffer.toString().trimRight();
  }

  String buildFinalSummaryText() {
    final buffer = StringBuffer('Готово.');
    if (taskFileMutations > 0)
      buffer.write(' Изменений файлов: $taskFileMutations.');
    if (taskCommandRuns > 0)
      buffer.write(
          ' Команд выполнено: $taskCommandRuns, последний exit code: ${lastCommandExitCode ?? 'unknown'}.');
    if (taskFailedCommands > 0)
      buffer.write(' Команд с ошибками: $taskFailedCommands.');
    return buffer.toString();
  }

  bool taskLooksLikeCppTask() {
    final text = activeTaskText.toLowerCase();
    return text.contains('c++') ||
        text.contains('с++') ||
        text.contains('cpp') ||
        text.contains('си++') ||
        text.contains('c plus plus');
  }

  bool looksLikeToolInventoryQuestion(String text) {
    final lower = text.toLowerCase();
    return (lower.contains('какие') ||
            lower.contains('покажи') ||
            lower.contains('что')) &&
        (lower.contains('инструмент') ||
            lower.contains('tools') ||
            lower.contains('компил') ||
            lower.contains('запуск') ||
            lower.contains('утилит'));
  }

  Future<bool> tryLocalFallbackIfUseful({required String reason}) async {
    // Встроенные решения пользовательских задач запрещены: код должна писать модель через tools.
    log('LOCAL FALLBACK DISABLED: task code must be produced by the model only. reason=$reason');
    final retryPrompt = ChatMessage(
      role: 'user',
      internal: true,
      content:
          '''Предыдущий ответ модели не дал пригодных действий. Встроенный fallback генерации кода отключён: код, файлы и исправления должна создавать сама модель через инструменты.
Причина повтора: $reason

Повтори действие через native tool_calls или полностью закрытый XML tool_call. Не пиши только рассуждение и не используй фиктивные переменные вроде cmake_file_content/main_cpp_content.
Если пользователь запретил библиотеки или просит писать самостоятельно — немедленно запиши полный рабочий код через write_file/replace_text, затем запусти run_tests.
Если пользователь просит интернет-реализацию или нужна документация — используй duckduckgo_search/web_fetch/web_deep_fetch/download_to_project/download_to_tools, затем подключи найденное и проверь сборку. Полезные сведения сохраняй через knowledge_store и ищи их через knowledge_search.
Не используй заготовленный шаблон, придумай и запиши код сам.''',
    );
    messages.add(retryPrompt);
    await appendSession(retryPrompt);
    recalculateContext();
    return false;
  }

  Map<String, Object?> taskStateJson() => {
        'tool_actions': taskToolActions,
        'file_mutations': taskFileMutations,
        'command_runs': taskCommandRuns,
        'failed_commands': taskFailedCommands,
        'last_command_exit_code': lastCommandExitCode,
        'last_command': truncateMiddle(lastCommandText, 2000),
        'last_command_output': truncateMiddle(lastCommandResultText, 12000),
        'environment': hostEnvironmentSummary(),
        'local_tools_summary':
            truncateMiddle(localToolsCompactSummary(maxItems: 12), 2000),
        'solution_memory':
            truncateMiddle(solutionMemoryCompactSummary(maxItems: 20), 6000),
        'problem_solving_attempts': problemSolvingAttempts,
        'internet_tool_actions': taskInternetActions,
        'last_quality_issue': lastFinalAnswerQualityIssue,
      };

  bool taskLooksLikeRequiresFiles() {
    final text = activeTaskText.toLowerCase();
    final readOnlyMarkers = [
      'выведи содержимое',
      'покажи содержимое',
      'прочитай файл',
      'прочитай файлы',
      'содержимое файлов',
      'содержимое папки',
      'list files',
      'show file contents',
      'read file',
      'read files'
    ];
    if (readOnlyMarkers.any(text.contains)) return false;
    final markers = [
      'напиши',
      'создай',
      'сделай',
      'реализуй',
      'исправь',
      'добавь',
      'измени',
      'собери проект',
      'программа',
      'код',
      'проект',
      'write',
      'create',
      'implement',
      'fix',
      'modify',
      'generate',
      'build an app',
      'application',
      'program',
      'project'
    ];
    return markers.any(text.contains);
  }

  bool taskLooksLikeRequiresCommand() {
    final text = activeTaskText.toLowerCase();
    final markers = [
      'проверь',
      'скомпилируй',
      'собери',
      'запусти',
      'тест',
      'build',
      'compile',
      'run',
      'test',
      'check'
    ];
    return markers.any(text.contains);
  }

  bool taskLooksLikeDeviceFileReadTask() {
    final text = activeTaskText.toLowerCase();
    return (text.contains('выведи содержимое') ||
            text.contains('прочитай') ||
            text.contains('покажи содержимое') ||
            text.contains('содержимое файлов') ||
            text.contains('содержимое папки')) &&
        RegExp(r'[a-zа-я]:\\|/storage/|/sdcard/|/mnt/|/home/',
                caseSensitive: false)
            .hasMatch(activeTaskText);
  }

  bool generatedSourcesContainPlaceholder() {
    final root = currentProject;
    if (root == null) return false;
    final markers = <String>[
      'omitted for brevity',
      'full backpropagation logic is omitted',
      'conceptual',
      'stub',
      'placeholder',
      'todo',
      'заглуш',
      'концептуаль',
      'оставим это',
      'будет заполн',
      'не реализован',
      'реализация пропущена',
    ];
    try {
      for (final entity in Directory(root.path)
          .listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final rel = pathRelative(root.path, entity.path).replaceAll('\\', '/');
        final lowerRel = rel.toLowerCase();
        if (lowerRel.startsWith('.cppagent/') ||
            lowerRel.startsWith('build/') ||
            lowerRel.contains('/build/')) continue;
        if (!(lowerRel.endsWith('.cpp') ||
            lowerRel.endsWith('.cc') ||
            lowerRel.endsWith('.cxx') ||
            lowerRel.endsWith('.h') ||
            lowerRel.endsWith('.hpp'))) continue;
        final text = entity
            .readAsStringSync(encoding: const Utf8Codec(allowMalformed: true))
            .toLowerCase();
        if (markers.any(text.contains)) return true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  bool taskLooksLikeWebResearchTask() {
    final lower = activeTaskText.toLowerCase();
    return lower.contains('найди информацию') ||
        lower.contains('найти информацию') ||
        lower.contains('биограф') ||
        lower.contains('почитай') ||
        lower.contains('поищи в интернете') ||
        lower.contains('поиск в интернете');
  }

  bool taskLooksLikePersonResearchTask() {
    final lower = activeTaskText.toLowerCase();
    return (lower.contains('найди информацию') || lower.contains('биограф')) &&
        RegExp(r'[А-ЯЁ][а-яё]+\s+[А-ЯЁ][а-яё]+\s+[А-ЯЁ][а-яё]+')
            .hasMatch(activeTaskText);
  }

  String normalizeRussianNameToken(String value) {
    var v = value
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll(RegExp(r'[^а-яa-z-]'), '');
    for (final suffix in const [
      'ою',
      'ею',
      'ого',
      'его',
      'ому',
      'ему',
      'ым',
      'им',
      'ой',
      'ая',
      'яя',
      'ое',
      'ее',
      'а',
      'у',
      'е',
      'ы',
      'и'
    ]) {
      if (v.length >= suffix.length + 3 && v.endsWith(suffix))
        return v.substring(0, v.length - suffix.length);
    }
    return v;
  }

  List<String> extractLikelyFullNameTokens(String text) {
    final match = RegExp(r'([А-ЯЁ][а-яё]+)\s+([А-ЯЁ][а-яё]+)\s+([А-ЯЁ][а-яё]+)')
        .firstMatch(text);
    if (match == null) return const [];
    return [
      normalizeRussianNameToken(match.group(1)!),
      normalizeRussianNameToken(match.group(2)!),
      normalizeRussianNameToken(match.group(3)!)
    ];
  }

  String finalAnswerQualityIssue(String text) {
    if (!taskLooksLikeWebResearchTask()) return '';
    final lower = text.toLowerCase();
    if (taskLooksLikePersonResearchTask()) {
      final requested = extractLikelyFullNameTokens(activeTaskText);
      if (requested.length == 3) {
        final reqLast = requested[0];
        final reqFirst = requested[1];
        final reqPat = requested[2];
        final answerTokens =
            RegExp(r'([А-ЯЁ][а-яё]+)\s+([А-ЯЁ][а-яё]+)\s+([А-ЯЁ][а-яё]+)')
                .allMatches(text)
                .map((m) => [
                      normalizeRussianNameToken(m.group(1)!),
                      normalizeRussianNameToken(m.group(2)!),
                      normalizeRussianNameToken(m.group(3)!)
                    ])
                .toList();
        for (final t in answerTokens) {
          if (t[0] == reqLast && t[1] == reqFirst && t[2] != reqPat) {
            return 'ответ содержит данные о другом человеке: найдено ФИО с теми же фамилией/именем, но другим отчеством. Нельзя подменять запрошенное ФИО; нужно явно отделить чужие совпадения и не строить биографию по ним';
          }
        }
        if (!lower.contains(reqPat) &&
            lower.contains(reqLast) &&
            lower.contains(reqFirst)) {
          return 'ответ недостаточно сверен с точным ФИО: не подтверждено отчество/полное совпадение. Нужно выполнить дополнительную проверку источников или честно сказать, что точной биографии не найдено';
        }
      }
    }
    if (lower.contains('готово') && text.trim().length < 40)
      return 'ответ слишком короткий и не содержит проверки источников/результата';
    if ((lower.contains('найден') || lower.contains('информация')) &&
        !RegExp(r'https?://').hasMatch(text) &&
        taskInternetActions > 0) {
      return 'ответ по интернет-поиску не содержит ссылок/источников; нужно приложить проверяемые URL и указать степень уверенности';
    }
    final urls = RegExp(r'https?://[^\s\)\]}>]+')
        .allMatches(text)
        .map((m) => (m.group(0) ?? '').replaceAll(RegExp(r'[\.,;:]+$'), ''))
        .toList();
    if (urls.length != urls.toSet().length)
      return 'ответ содержит дублирующиеся ссылки; нужно удалить повторы URL перед выводом пользователю';
    return '';
  }

  String taskIncompleteReason() {
    if (!qualityCheckEnabled) return '';
    if (lastFinalAnswerQualityIssue.isNotEmpty)
      return lastFinalAnswerQualityIssue;
    if (taskLooksLikeWebResearchTask() &&
        allowInternetUse &&
        taskInternetActions == 0) {
      return 'задача требует поиска/проверки информации, но интернет-инструменты ещё не использовались. Нужно выполнить web_research или цепочку duckduckgo_search → web_fetch/web_deep_fetch и сверить результаты с точной формулировкой запроса';
    }
    if (taskLooksLikePersonResearchTask() &&
        allowInternetUse &&
        taskInternetActions < 2) {
      return 'поиск информации о человеке требует углублённой проверки: используй web_research, проверь точное ФИО, источники, профили, связи и отсеянные совпадения';
    }
    if (taskLooksLikeRequiresFiles() && taskFileMutations == 0) {
      return 'исходная задача похожа на задачу изменения/создания файлов, но агент не создал и не изменил ни одного файла';
    }
    if (generatedSourcesContainPlaceholder()) {
      return 'в созданных C++ исходниках обнаружены заглушки/концептуальные фразы/TODO вместо полноценной реализации. Нужно заменить их рабочим кодом, затем снова выполнить сборку и запуск';
    }
    if ((taskLooksLikeRequiresCommand() || taskFileMutations > 0) &&
        taskCommandRuns == 0) {
      return 'после изменения/создания файлов не была выполнена проверка, сборка или запуск через run_command/run_tests';
    }
    if (taskCommandRuns > 0 &&
        lastCommandExitCode != null &&
        lastCommandExitCode != 0) {
      if (taskLooksLikeDeviceFileReadTask() &&
          RegExp(r'COMMAND:\s*(dir|type)\b', caseSensitive: false)
              .hasMatch(lastCommandResultText)) {
        return 'запрос требует чтения внешней папки/файлов, но использована команда оболочки dir/type и она завершилась ошибкой. Нужно использовать list_device_directory/read_device_text_file/read_device_folder_texts с проверкой права доступа к файлам устройства';
      }
      if (lastCommandResultText.contains('BUILD_ARTIFACT_MISSING')) {
        return 'последняя команда вернула BUILD_ARTIFACT_MISSING: компилятор/команда не создали ожидаемый exe в build. Нельзя объявлять задачу завершённой; нужно исправить команду сборки или код и повторить run_tests';
      }
      if (isBuildConfigurationProblemOutput(lastCommandResultText)) {
        return 'последняя команда завершилась ошибкой структуры сборки CMake/C++: CMakeLists.txt отсутствует или указывает на несуществующий .cpp. Нужно исправить структуру сборки или запустить run_tests для автоматической сборки найденного исходника';
      }
      if (isEnvironmentProblemOutput(lastCommandResultText)) {
        return 'последняя команда завершилась ошибкой окружения, а не ошибкой кода: не найден компилятор/инструмент. Не переписывай исходники из-за этой ошибки; попробуй другой компилятор через run_tests/run_command или дай понятное сообщение, что нужно установить MinGW/Visual Studio Build Tools/clang++';
      }
      return 'последняя команда завершилась с ошибкой exit code $lastCommandExitCode, нужно исправить ошибку по stdout/stderr и повторить проверку';
    }
    return '';
  }

  List<Map<String, Object?>> buildOpenAiToolDefinitions() {
    Map<String, Object?> strProp(String description) =>
        {'type': 'string', 'description': description};
    Map<String, Object?> boolProp(String description) =>
        {'type': 'boolean', 'description': description};
    Map<String, Object?> fn(String name, String description,
            Map<String, Object?> properties, List<String> required) =>
        {
          'type': 'function',
          'function': {
            'name': name,
            'description': description,
            'parameters': {
              'type': 'object',
              'properties': properties,
              'required': required,
            },
          },
        };
    return [
      fn('write_file',
          'Создать или полностью перезаписать файл внутри проекта.', {
        'path': strProp('Относительный путь внутри проекта'),
        'content': strProp('Полное содержимое файла')
      }, [
        'path',
        'content'
      ]),
      fn('append_file', 'Добавить текст в конец файла внутри проекта.', {
        'path': strProp('Относительный путь внутри проекта'),
        'content': strProp('Добавляемый текст')
      }, [
        'path',
        'content'
      ]),
      fn('replace_text', 'Заменить фрагмент текста в файле.', {
        'path': strProp('Относительный путь'),
        'old_text': strProp('Что заменить'),
        'new_text': strProp('На что заменить'),
        'all': boolProp('Заменить все совпадения')
      }, [
        'path',
        'old_text',
        'new_text'
      ]),
      fn('read_file', 'Прочитать текстовый файл из проекта.',
          {'path': strProp('Относительный путь')}, ['path']),
      fn('list_files', 'Показать файлы в папке проекта.',
          {'path': strProp('Относительный путь папки')}, []),
      fn('project_map', 'Показать дерево проекта.',
          {'path': strProp('Относительный путь папки')}, []),
      fn(
          'list_local_tools',
          'Показать компактный список локальных программ пользователя из папки tools, которые агент добавляет в PATH с приоритетом.',
          {
            'purpose': strProp(
                'Необязательная цель: cpp, python, build, run, archive, all')
          },
          []),
      fn(
          'rebuild_device_index',
          'Перестроить индекс выбранных расположений устройства из настроек программы.',
          {},
          []),
      fn(
          'search_device_index',
          'Быстрый поиск по ранее построенному индексу выбранных расположений.',
          {
            'query': strProp('Что искать в именах и/или содержимом файлов'),
            'max_results': strProp('Максимум результатов, например 20')
          },
          [
            'query'
          ]),
      fn(
          'recognize_image_text',
          'Распознать текст на изображении/PDF best-effort через доступные OCR-инструменты из tools или системы.',
          {'path': strProp('Путь к изображению или PDF')},
          ['path']),
      fn(
          'run_custom_tool',
          'Запустить сохранённый пользовательский инструмент агента по имени.',
          {
            'name': strProp('Имя инструмента из настроек'),
            'input': strProp('Входной текст/JSON для подстановки {{input}}')
          },
          [
            'name'
          ]),
      fn(
          'set_task_plan',
          'Зафиксировать план сложной задачи в виде подзадач. Используй перед длинной реализацией или исправлением сложной ошибки.',
          {
            'plan':
                strProp('Нумерованный список подзадач и критериев готовности')
          },
          [
            'plan'
          ]),
      fn(
          'duckduckgo_search',
          'Найти информацию в интернете через DuckDuckGo HTML/API-совместимый поиск. Для персон/биографий используй точное ФИО и затем обязательно открывай страницы через web_fetch/web_deep_fetch.',
          {
            'query': strProp('Поисковый запрос'),
            'max_results': strProp('Максимум результатов, обычно 5-8')
          },
          [
            'query'
          ]),
      fn(
          'web_fetch',
          'Открыть веб-страницу по URL и вернуть её заголовок, очищенный текст и ссылки. Используй после duckduckgo_search для проверки фактов и точного совпадения запроса.',
          {
            'url': strProp('URL страницы'),
            'max_chars': strProp('Максимум символов текста, например 20000')
          },
          [
            'url'
          ]),
      fn(
          'web_deep_fetch',
          'Углублённо открыть страницу и перейти по ссылкам внутри того же сайта на заданную глубину. Используй для анализа документации, форумов и примеров.',
          {
            'url': strProp('URL страницы'),
            'max_pages': strProp('Максимум страниц, обычно 3-6'),
            'depth': strProp('Глубина переходов, обычно 1-2'),
            'max_chars': strProp('Максимум символов')
          },
          [
            'url'
          ]),
      fn(
          'web_research',
          'Автоматический углублённый интернет-поиск: ищет, открывает несколько сайтов, извлекает внутренние и внешние ссылки, профили, контакты, места работы, полезные факты, релевантные изображения и делает follow-up запросы. Для людей строго разделяет подтверждённые источники и отсеянные похожие совпадения. Используй для любых поисковых задач вместо простого ответа по выдаче.',
          {
            'query': strProp('Точный исследовательский запрос'),
            'max_pages': strProp('Максимум открытых страниц, обычно 8-12'),
            'max_depth': strProp('Глубина переходов и follow-up, обычно 1-2'),
            'max_chars': strProp('Максимум символов результата')
          },
          [
            'query'
          ]),
      fn(
          'filesystem_search',
          'Найти реализации, исходники, архивы или документацию в файловой системе компьютера. Работает только если разрешён поиск по компьютеру.',
          {
            'query': strProp('Что искать'),
            'root': strProp(
                'Корневая папка для поиска; если пусто, ищет в Projects/tools'),
            'max_results': strProp('Максимум результатов')
          },
          [
            'query'
          ]),
      fn(
          'list_device_directory',
          'Показать файлы и папки по абсолютному пути на устройстве. Используй для запросов вроде «выведи содержимое папки O:\\...». Требует право доступа к файлам устройства, если путь вне проекта.',
          {
            'path': strProp('Абсолютный или проектный путь папки'),
            'recursive': strProp('true/false, рекурсивно'),
            'max_results': strProp('Максимум результатов')
          },
          [
            'path'
          ]),
      fn(
          'read_device_text_file',
          'Прочитать текстовый файл по абсолютному пути на устройстве. Требует право доступа к файлам устройства, если путь вне проекта.',
          {
            'path': strProp('Абсолютный или проектный путь файла'),
            'max_chars': strProp('Максимум символов')
          },
          [
            'path'
          ]),
      fn(
          'read_device_folder_texts',
          'Вывести содержимое файлов из папки по абсолютному пути, включая подпапки, офисные документы, PDF и архивы best-effort. Используй вместо run_command dir/type для внешних папок Windows/Android/Linux.',
          {
            'path': strProp('Абсолютный или проектный путь папки'),
            'recursive': strProp('true/false, читать подпапки'),
            'max_files': strProp('Максимум файлов'),
            'max_chars_per_file': strProp('Максимум символов на файл')
          },
          [
            'path'
          ]),
      fn(
          'search_device_documents',
          'Найти документы в папке устройства и подпапках по смысловым ключевым словам/фразам, извлекая текст из офисных документов/PDF/архивов best-effort. Используй для задач найти документ и процитировать требования.',
          {
            'path': strProp('Абсолютный путь папки'),
            'query': strProp('Что искать, например требования по закупкам'),
            'recursive': strProp('true/false'),
            'max_files': strProp('Максимум файлов'),
            'max_chars_per_file': strProp('Максимум символов из каждого файла')
          },
          [
            'path',
            'query'
          ]),
      fn(
          'read_document_structure',
          'Прочитать структуру и текст документа RTF/DOCX/XLSX/PPTX/ODT/ODS/ODP/ODC. Используй для анализа приложений и документов устройства вместо команд оболочки.',
          {
            'path': strProp('Абсолютный или проектный путь документа'),
            'max_chars': strProp('Максимум символов текста')
          },
          [
            'path'
          ]),
      fn(
          'create_document_from_text',
          'Создать документ DOCX/XLSX/PPTX/ODT/ODS/ODP/ODC/RTF из обычного текста. Формат выбирается по расширению path.',
          {
            'path': strProp(
                'Путь выходного файла, абсолютный или относительный к проекту'),
            'text': strProp(
                'Обычный текст. Для XLSX/ODS строки станут строками таблицы; для PPTX/ODP блоки через пустую строку или --- станут слайдами')
          },
          [
            'path',
            'text'
          ]),
      fn(
          'edit_document_text',
          'Редактировать документ DOCX/XLSX/PPTX/ODT/ODS/ODP/ODC/RTF: replace_all, append, prepend или replace_text.',
          {
            'path': strProp('Абсолютный или проектный путь документа'),
            'mode': strProp('replace_all | append | prepend | replace_text'),
            'text': strProp('Новый текст или добавляемый текст'),
            'old_text': strProp('Искомый текст для режима replace_text')
          },
          [
            'path',
            'mode',
            'text'
          ]),
      fn(
          'archive_device_children',
          'Создать отдельный zip-архив для каждого файла или подпапки в выбранной/внешней папке устройства. Используй для задач вроде «упакуй каждую игру в отдельный архив».',
          {
            'path': strProp('Абсолютный путь исходной папки'),
            'output': strProp(
                'Папка для архивов; если пусто, будет создана _archives внутри исходной папки'),
            'max_items': strProp('Максимум элементов для упаковки')
          },
          [
            'path'
          ]),
      fn('knowledge_search', 'Поиск по внутренней базе знаний агента.', {
        'query': strProp('Запрос'),
        'max_results': strProp('Максимум результатов')
      }, [
        'query'
      ]),
      fn(
          'knowledge_store',
          'Сохранить полезную информацию в базе знаний агента с избыточностью для будущих задач.',
          {
            'topic': strProp('Тема'),
            'content': strProp('Полезная информация'),
            'source': strProp('Источник или URL'),
            'tags': strProp('Теги через запятую')
          },
          [
            'topic',
            'content'
          ]),
      fn('email_list_accounts',
          'Показать настроенные почтовые аккаунты без паролей.', {}, []),
      fn(
          'email_draft_smtp',
          'Подготовить черновик письма на основе настроенного SMTP-аккаунта. Фактическая отправка требует подтверждения пользователя.',
          {
            'account_id':
                strProp('ID почтового аккаунта из email_list_accounts'),
            'to': strProp('Кому'),
            'subject': strProp('Тема'),
            'body': strProp('Текст письма')
          },
          [
            'account_id',
            'to',
            'subject',
            'body'
          ]),
      fn(
          'download_to_project',
          'Скачать файл по URL внутрь текущего проекта. Используй только когда пользователь разрешил/попросил взять реализацию, датасет, архив или исходник из интернета.',
          {
            'url': strProp('URL для скачивания'),
            'path': strProp(
                'Относительный путь внутри проекта, например third_party/lib.zip или src/example.cpp')
          },
          [
            'url'
          ]),
      fn(
          'download_to_tools',
          'Скачать необходимое переносимое ПО или архив в папку tools. Не скачивай неизвестные файлы без необходимости.',
          {
            'url': strProp('URL для скачивания'),
            'path': strProp(
                'Относительный путь внутри tools, например windows/x64/mingw.zip или downloads/tool.zip')
          },
          [
            'url'
          ]),
      fn('extract_zip_to_tools',
          'Распаковать zip-архив в папку tools, например tools/windows/x64.', {
        'path': strProp(
            'Путь к zip: абсолютный, относительный к проекту или относительный к tools'),
        'dest': strProp('Папка назначения внутри tools')
      }, [
        'path',
        'dest'
      ]),
      fn(
          'remember_solution',
          'Запомнить найденный способ решения ошибки/сборки/настройки для будущих подсказок ИИ.',
          {
            'problem': strProp('Краткое описание проблемы'),
            'solution': strProp('Что помогло'),
            'tags': strProp(
                'Теги через запятую: cpp, python, windows, build и т.п.')
          },
          [
            'problem',
            'solution'
          ]),
      fn('make_dir', 'Создать папку внутри проекта.',
          {'path': strProp('Относительный путь папки')}, ['path']),
      fn('delete_path', 'Удалить файл или папку внутри проекта.', {
        'path': strProp('Относительный путь'),
        'recursive': boolProp('Рекурсивно удалить папку')
      }, [
        'path'
      ]),
      fn('copy_path', 'Скопировать файл или папку внутри проекта.', {
        'from': strProp('Относительный исходный путь'),
        'to': strProp('Относительный путь назначения')
      }, [
        'from',
        'to'
      ]),
      fn('move_path',
          'Переместить или переименовать файл/папку внутри проекта.', {
        'from': strProp('Относительный исходный путь'),
        'to': strProp('Относительный путь назначения')
      }, [
        'from',
        'to'
      ]),
      fn(
          'run_command',
          'Запустить команду в корне проекта или в указанной подпапке проекта.',
          {
            'command': strProp('Команда для cmd/sh'),
            'cwd': strProp(
                'Необязательная рабочая папка внутри проекта, например . или nen_project')
          },
          [
            'command'
          ]),
      fn(
          'run_tests',
          'Автоматически проверить, собрать или запустить проект. Для C++ сам найдёт исходники и при необходимости создаст/исправит CMakeLists.txt.',
          {
            'command': strProp(
                'Необязательная команда. Если пусто, агент выберет сам'),
            'cwd': strProp('Необязательная рабочая папка внутри проекта')
          },
          []),
      fn(
          'inspect_zip',
          'Показать содержимое zip-архива.',
          {'path': strProp('Путь к zip-архиву, абсолютный или относительный')},
          ['path']),
      fn('extract_zip',
          'Распаковать zip-архив в папку проекта или указанное расположение.', {
        'path': strProp('Путь к zip-архиву'),
        'dest': strProp('Папка назначения')
      }, [
        'path',
        'dest'
      ]),
      fn(
          'read_docx_text',
          'Совместимый алиас: прочитать структуру и текст DOCX через read_document_structure.',
          {'path': strProp('Путь к DOCX')},
          ['path']),
      fn(
          'read_xlsx_text',
          'Совместимый алиас: прочитать структуру и текст XLSX через read_document_structure.',
          {'path': strProp('Путь к XLSX')},
          ['path']),
    ];
  }

  String buildNoActionRetryPrompt(
      {bool emptyResponse = false, String incompleteReason = ''}) {
    final reason = emptyResponse
        ? 'Твой предыдущий ответ был пустым: в content нет видимого текста и нет tool-call.'
        : 'Ты дал видимый ответ, но задача ещё не подтверждена программой как выполненная. Причина: $incompleteReason.';
    return '''$reason
Не выводи только план и не используй reasoning_content вместо content.
Текущая исходная задача пользователя:
${truncateMiddle(activeTaskText, 12000)}

Текущее состояние выполнения:
${const JsonEncoder.withIndent('  ').convert(taskStateJson())}

Сейчас обязательно продолжи через инструменты:
- если ты написал «Изменён файл», «создан файл», «исправил файл» или показал код, но не вызвал write_file/append_file/replace_text, это не считается действием. Немедленно вызови настоящий tool-call для файла.
- если нужно создать/изменить файлы — используй write_file/append_file/replace_text;
- если нужно собрать, проверить или запустить — используй run_command или run_tests;
- если команда завершилась ошибкой компиляции кода — используй переданный stdout/stderr/exit code, прочитай/исправь файлы и повтори команду;
- если stdout/stderr говорит, что не найден компилятор/команда, это ошибка окружения, а не исходного кода: не переписывай код, попробуй другой компилятор или сообщи, что его нужно установить;
- если Python сообщает ModuleNotFoundError или нужны пакеты, используй pip install: агент установит пакеты в `.cppagent/python_venv`, не в общий Python;
- если не хватает программы/компилятора, используй list_local_tools, затем при необходимости download_to_tools/extract_zip_to_tools и настройку через run_command;
- если не хватает документации/примера/страницы загрузки — используй web_research или duckduckgo_search, web_fetch и при необходимости web_deep_fetch;
- для поиска людей всегда сверяй полное ФИО, отчество и контекст; результаты с другим отчеством считаются чужими совпадениями;
- если пользователь запретил дополнительные библиотеки или просит писать самостоятельно — не ищи оправдание библиотеками, а пиши самописную реализацию по частям и проверяй каждую часть;
- если пользователь просит найти реализацию в интернете и установить — ищи через duckduckgo_search, открывай через web_fetch, скачивай через download_to_project/download_to_tools, затем подключай и проверяй;
- никогда не передавай в write_file фиктивный content вроде cmake_file_content/main_cpp_content/code_here: передай полный реальный текст файла;
- при найденном решении вызови remember_solution;
- если задача технически невозможна, дай видимое объяснение с конкретной причиной.
''';
  }

  Future<String> callModel() async {
    final profile = currentProfile;
    lastContextMismatch = false;
    lastContextMismatchDetails = '';
    if (profile == null || profile.baseUrl.isEmpty || profile.model.isEmpty) {
      return 'Модель не настроена. Укажите профиль во вкладке “Модели”.';
    }

    final runtimeLimits =
        await refreshRuntimeLimitsForProfile(profile, force: false);
    final runtimeCtx = runtimeLimits.contextTokens;
    if (runtimeCtx != null && runtimeCtx < 2048 && maxContextTokens >= 8192) {
      lastModelFinishReason = 'context_mismatch';
      lastContextMismatch = true;
      lastContextMismatchDetails = buildContextMismatchMessage(
          profile, runtimeLimits,
          source: 'server_probe');
      log('SERVER CONTEXT MISMATCH BEFORE REQUEST: $lastContextMismatchDetails');
      logAction('server_context_mismatch', {
        'model': profile.model,
        'profile_context': maxContextTokens,
        'runtime_context': runtimeCtx,
        'source': runtimeLimits.source,
      });
      return lastContextMismatchDetails;
    }

    final uri = Uri.parse(
        '${profile.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    final request =
        await client.postUrl(uri).timeout(const Duration(seconds: 30));
    request.headers.contentType = ContentType.json;
    if (profile.apiKey.isNotEmpty)
      request.headers
          .set(HttpHeaders.authorizationHeader, 'Bearer ${profile.apiKey}');
    final modelMessages = buildMessagesForModel();
    final maxOutputTokensToSend = calculateMaxOutputTokens(modelMessages);
    final body = {
      'model': profile.model,
      'temperature': 0.1,
      'stream': profile.streamResponses,
      'max_tokens': maxOutputTokensToSend,
      'messages': modelMessages,
      'tools': buildOpenAiToolDefinitions(),
      'tool_choice': 'auto',
    };
    log('CONTEXT BUDGET: profileContext=$maxContextTokens runtimeContext=${runtimeCtx ?? 'unknown'} promptTokens≈${estimateMessagesTokens(modelMessages)} requestedMaxOutput=${profile.maxOutputTokens} sentMaxTokens=$maxOutputTokensToSend messages=${modelMessages.length}');
    final encodedBody = jsonEncode(body);
    log('HTTP REQUEST ${uri.toString()}: ${truncateMiddle(encodedBody, 18000)}');
    request.write(encodedBody);
    final response = await request.close().timeout(const Duration(minutes: 60));
    if (profile.streamResponses &&
        response.statusCode >= 200 &&
        response.statusCode < 300) {
      return readOpenAiStream(response);
    }
    final text = await utf8.decodeStream(response);
    log('HTTP RESPONSE ${response.statusCode}: ${truncateMiddle(text, 18000)}');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final parsedCtx = parseRuntimeContextFromError(text);
      if (parsedCtx != null) {
        runtimeLimitsCache[runtimeCacheKey(profile)] = RuntimeModelLimits(
            contextTokens: parsedCtx, outputTokens: null, source: 'http_error');
        lastModelFinishReason = 'context_mismatch';
        lastContextMismatch = true;
        lastContextMismatchDetails = buildContextMismatchMessage(
            profile,
            RuntimeModelLimits(
                contextTokens: parsedCtx,
                outputTokens: null,
                source: 'http_error'),
            source: 'http_error');
        log('SERVER CONTEXT MISMATCH FROM HTTP ERROR: $lastContextMismatchDetails');
        logAction('server_context_mismatch', {
          'model': profile.model,
          'profile_context': maxContextTokens,
          'runtime_context': parsedCtx,
          'source': 'http_error',
          'http_status': response.statusCode,
          'error': truncateMiddle(text, 4000),
        });
        return lastContextMismatchDetails;
      }
      final lowerError = text.toLowerCase();
      if (lowerError.contains('failed to load model') ||
          lowerError.contains('insufficient system resources') ||
          lowerError.contains('недостаточно')) {
        return 'Ошибка загрузки модели `${profile.model}`: сервер вернул HTTP ${response.statusCode}. Выберите более лёгкую модель или уменьшите параметры загрузки. Подробности: ${truncateMiddle(text, 1200)}';
      }
      throw StateError('HTTP ${response.statusCode}: $text');
    }
    final data = jsonDecode(text) as Map<String, dynamic>;
    final choices = data['choices'] as List<dynamic>? ?? [];
    if (choices.isEmpty) return '';
    final choice = choices.first as Map<String, dynamic>? ?? {};
    final usage = data['usage'];
    if (usage is Map) {
      final promptUsed = usage['prompt_tokens'];
      final completionUsed = usage['completion_tokens'];
      final totalUsed = usage['total_tokens'];
      log('MODEL USAGE: prompt=$promptUsed completion=$completionUsed total=$totalUsed');
    }
    lastModelFinishReason = choice['finish_reason']?.toString() ?? '';
    log('MODEL FINISH_REASON: $lastModelFinishReason');
    if (lastModelFinishReason == 'length') {
      log('MODEL OUTPUT LENGTH STOP: model/server stopped generation by output limit. This is not the same as context window. Increase Max output tokens in profile or server generation limit if responses/tool-calls are cut.');
    }
    final message = choice['message'] as Map<String, dynamic>? ?? {};
    final content = message['content']?.toString() ?? '';
    final nativeToolCalls = message['tool_calls'];
    if (nativeToolCalls is List && nativeToolCalls.isNotEmpty) {
      final buffer = StringBuffer(content);
      for (final item in nativeToolCalls) {
        if (item is! Map) continue;
        final function = item['function'];
        if (function is! Map) continue;
        final name = function['name']?.toString() ?? '';
        final rawArgs = function['arguments'];
        if (name.isEmpty) continue;
        Object? args;
        try {
          args = rawArgs is String ? jsonDecode(rawArgs) : rawArgs;
        } catch (_) {
          args = rawArgs?.toString() ?? '';
        }
        buffer.writeln('\n<tool_call>${jsonEncode({
              'name': name,
              'args': normalizeArgs(args)
            })}</tool_call>');
      }
      final converted = buffer.toString();
      log('MODEL NATIVE_TOOL_CALLS CONVERTED: ${truncateMiddle(converted, 12000)}');
      return converted;
    }
    final reasoning = message['reasoning_content']?.toString() ??
        message['reasoning']?.toString() ??
        '';
    if (content.trim().isEmpty && reasoning.trim().isNotEmpty) {
      log('MODEL REASONING_ONLY: ${truncateMiddle(reasoning, 12000)}');
    }
    return content;
  }

  Future<String> readOpenAiStream(HttpClientResponse response) async {
    final content = StringBuffer();
    final toolCalls = <int, Map<String, String>>{};
    var finishReason = '';
    final rawLog = StringBuffer();
    var reasoningChars = 0;
    var contentChunks = 0;
    var toolChunks = 0;
    var buffer = '';
    await for (final chunk in response
        .transform(utf8.decoder)
        .timeout(const Duration(minutes: 60))) {
      buffer += chunk;
      while (true) {
        final lineEnd = buffer.indexOf('\n');
        if (lineEnd < 0) break;
        var line = buffer.substring(0, lineEnd).trimRight();
        buffer = buffer.substring(lineEnd + 1);
        if (!line.startsWith('data:')) continue;
        final dataLine = line.substring(5).trim();
        if (dataLine == '[DONE]') break;
        Map<String, dynamic> decoded;
        try {
          decoded = jsonDecode(dataLine) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        final choices = decoded['choices'];
        if (choices is! List || choices.isEmpty || choices.first is! Map)
          continue;
        final choice = choices.first as Map;
        final fr = choice['finish_reason']?.toString() ?? '';
        if (fr.isNotEmpty) finishReason = fr;
        final delta = choice['delta'];
        if (delta is Map) {
          final reasoningPart =
              delta['reasoning_content'] ?? delta['reasoning'];
          if (reasoningPart != null)
            reasoningChars += reasoningPart.toString().length;
          final part = delta['content'];
          if (part != null) {
            final text = part.toString();
            content.write(text);
            contentChunks++;
            if (rawLog.length < 18000)
              rawLog.writeln(
                  jsonEncode({'content_delta': truncateMiddle(text, 800)}));
          }
          final calls = delta['tool_calls'];
          if (calls is List) {
            toolChunks += calls.length;
            if (rawLog.length < 18000)
              rawLog.writeln(jsonEncode({'tool_delta_count': calls.length}));
            for (final c in calls) {
              if (c is! Map) continue;
              final index = int.tryParse(c['index']?.toString() ?? '') ?? 0;
              final current = toolCalls.putIfAbsent(
                  index, () => {'name': '', 'arguments': ''});
              final fn = c['function'];
              if (fn is Map) {
                final name = fn['name']?.toString() ?? '';
                final args = fn['arguments']?.toString() ?? '';
                if (name.isNotEmpty)
                  current['name'] = (current['name'] ?? '') + name;
                if (args.isNotEmpty)
                  current['arguments'] = (current['arguments'] ?? '') + args;
              }
            }
          }
        }
      }
      if (content.length % 900 < chunk.length) {
        updateLiveProgress(
            '⏳ Модель отвечает потоково... получено примерно ${content.length} символов, reasoning≈$reasoningChars');
      } else if (content.isEmpty &&
          reasoningChars > 0 &&
          reasoningChars % 4000 < chunk.length) {
        updateLiveProgress(
            '⏳ Модель ещё думает... reasoning≈$reasoningChars символов, жду content/tool-call');
      }
    }
    lastModelFinishReason = finishReason;
    log('HTTP STREAM RESPONSE ${response.statusCode}: content_chunks=$contentChunks tool_chunks=$toolChunks reasoning_chars=$reasoningChars sample=${truncateMiddle(rawLog.toString(), 18000)}');
    log('MODEL FINISH_REASON: $lastModelFinishReason');
    if (toolCalls.isNotEmpty) {
      final out = StringBuffer(content.toString());
      final keys = toolCalls.keys.toList()..sort();
      for (final k in keys) {
        final call = toolCalls[k]!;
        final name = call['name'] ?? '';
        if (name.isEmpty) continue;
        Object? args;
        try {
          args = jsonDecode(call['arguments'] ?? '{}');
        } catch (_) {
          args = call['arguments'] ?? '';
        }
        out.writeln('\n<tool_call>${jsonEncode({
              'name': name,
              'args': normalizeArgs(args)
            })}</tool_call>');
      }
      final converted = out.toString();
      log('MODEL STREAM TOOL_CALLS CONVERTED: ${truncateMiddle(converted, 12000)}');
      return converted;
    }
    return content.toString();
  }

  String runtimeCacheKey(ModelProfile profile) =>
      '${profile.baseUrl}|${profile.model}';

  Future<RuntimeModelLimits> refreshRuntimeLimitsForProfile(
      ModelProfile profile,
      {required bool force}) async {
    final key = runtimeCacheKey(profile);
    if (!force && runtimeLimitsCache.containsKey(key))
      return runtimeLimitsCache[key]!;
    final limits = await probeRuntimeModelLimits(profile);
    runtimeLimitsCache[key] = limits;
    if (limits.contextTokens != null || limits.outputTokens != null) {
      log('SERVER RUNTIME LIMITS: model=${profile.model} source=${limits.source} runtime_ctx=${limits.contextTokens ?? 'unknown'} runtime_output=${limits.outputTokens ?? 'unknown'} profile_ctx=${profile.maxContextTokens} profile_output=${profile.maxOutputTokens}');
    } else {
      log('SERVER RUNTIME LIMITS: model=${profile.model} source=${limits.source} runtime_ctx=unknown runtime_output=unknown profile_ctx=${profile.maxContextTokens} profile_output=${profile.maxOutputTokens}');
    }
    return limits;
  }

  Future<RuntimeModelLimits> probeRuntimeModelLimits(
      ModelProfile profile) async {
    final cleanedBase = profile.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final rootBase = cleanedBase.endsWith('/v1')
        ? cleanedBase.substring(0, cleanedBase.length - 3)
        : cleanedBase;
    final urls = <String>[
      '$rootBase/props',
      '$cleanedBase/props',
      '$cleanedBase/models',
      '$rootBase/api/v0/models',
    ];
    for (final url in urls.toSet()) {
      try {
        final text = await httpGetText(url, profile.apiKey,
            timeout: const Duration(seconds: 3));
        if (text.isEmpty) continue;
        final decoded = jsonDecode(text);
        final modelSpecific = findRuntimeLimitsForModel(decoded, profile.model);
        if (modelSpecific != null)
          return RuntimeModelLimits(
              contextTokens: modelSpecific.contextTokens,
              outputTokens: modelSpecific.outputTokens,
              source: url);
        final ctx = findFirstIntDeep(decoded, const [
          'loaded_context_length',
          'n_ctx',
          'ctx_size',
          'context_length',
          'context_window',
          'max_ctx',
          'num_ctx',
          'n_ctx_per_seq',
          'max_context_length'
        ]);
        final out = findFirstIntDeep(decoded, const [
          'max_output_tokens',
          'max_completion_tokens',
          'n_predict',
          'output_token_limit',
          'max_tokens'
        ]);
        if (ctx != null || out != null)
          return RuntimeModelLimits(
              contextTokens: ctx, outputTokens: out, source: url);
      } catch (error) {
        log('SERVER RUNTIME LIMITS probe failed url=$url error=$error');
      }
    }
    return const RuntimeModelLimits(
        contextTokens: null, outputTokens: null, source: 'metadata_missing');
  }

  Future<String> httpGetText(String url, String apiKey,
      {required Duration timeout}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
    if (apiKey.isNotEmpty)
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    final response = await request.close().timeout(timeout);
    final text = await utf8.decodeStream(response);
    log('HTTP PROBE ${response.statusCode} $url: ${truncateMiddle(text, 8000)}');
    if (response.statusCode < 200 || response.statusCode >= 300) return '';
    return text;
  }

  RuntimeModelLimits? findRuntimeLimitsForModel(
      Object? decoded, String modelId) {
    Map? selected;
    void visit(Object? node) {
      if (selected != null) return;
      if (node is Map) {
        final id = node['id']?.toString() ??
            node['model']?.toString() ??
            node['name']?.toString();
        if (id == modelId) {
          selected = node;
          return;
        }
        for (final value in node.values) {
          visit(value);
          if (selected != null) return;
        }
      } else if (node is List) {
        for (final value in node) {
          visit(value);
          if (selected != null) return;
        }
      }
    }

    visit(decoded);
    final map = selected;
    if (map == null) return null;
    final loadedCtx = firstIntFromMap(map, const [
      'loaded_context_length',
      'n_ctx',
      'ctx_size',
      'context_length',
      'context_window',
      'num_ctx'
    ]);
    final maxCtx = firstIntFromMap(
        map, const ['max_context_length', 'max_ctx', 'n_ctx_train']);
    final out = firstIntFromMap(map, const [
      'max_output_tokens',
      'max_completion_tokens',
      'n_predict',
      'output_token_limit',
      'max_tokens'
    ]);
    final ctx = loadedCtx ?? maxCtx;
    return RuntimeModelLimits(
        contextTokens: ctx, outputTokens: out, source: 'model_metadata');
  }

  int? firstIntFromMap(Map map, List<String> keys) {
    final lowerKeys = {for (final key in keys) key.toLowerCase()};
    for (final entry in map.entries) {
      final key = entry.key.toString().toLowerCase();
      if (lowerKeys.contains(key)) {
        final value = entry.value;
        if (value is int) return value;
        final parsed = int.tryParse(value?.toString() ?? '');
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  int? parseRuntimeContextFromError(String text) {
    final patterns = [
      RegExp(r'n_ctx\s*[:=]\s*(\d+)', caseSensitive: false),
      RegExp(r'context length[^0-9]*(\d+)', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) return int.tryParse(match.group(1) ?? '');
    }
    return null;
  }

  String buildContextMismatchMessage(
      ModelProfile profile, RuntimeModelLimits limits,
      {required String source}) {
    final runtimeCtx = limits.contextTokens;
    final expectedCtx = maxContextTokens;
    return 'Ошибка контекста сервера для модели `${profile.model}`: профиль агента ожидает context window $expectedCtx токенов, но текущий серверный экземпляр сообщает n_ctx=${runtimeCtx ?? 'unknown'} ($source). Это не значит, что модель не поддерживает $expectedCtx; это значит, что она сейчас загружена сервером с меньшим контекстом. Перезагрузи модель/сервер с контекстом $expectedCtx (для llama.cpp: --ctx-size $expectedCtx; для LM Studio/OpenAI-compatible UI — Context Length/Context Window = $expectedCtx) и повтори запрос. Агент не будет сжимать задачу до ${runtimeCtx ?? 'малого'} токенов, потому что это сломает Codex/OpenCode-подобный режим tools.';
  }

  int estimateTextTokens(String text) => (text.length / 3.6).ceil() + 1;

  int estimateMessagesTokens(List<Map<String, String>> modelMessages) {
    var total = 0;
    for (final message in modelMessages) {
      total += 8 +
          estimateTextTokens(message['role'] ?? '') +
          estimateTextTokens(message['content'] ?? '');
    }
    return total;
  }

  int calculateMaxOutputTokens(List<Map<String, String>> modelMessages) {
    final promptTokens = estimateMessagesTokens(modelMessages);
    final remainingByContext = maxContextTokens - promptTokens - 512;
    final requestedOutput = maxOutputTokens < 512 ? 512 : maxOutputTokens;
    if (remainingByContext <= 512) return 512;
    final byContext = remainingByContext < requestedOutput
        ? remainingByContext
        : requestedOutput;
    return byContext.clamp(512, requestedOutput).toInt();
  }

  String projectStructureCompactSummary({int maxItems = 120}) {
    final project = currentProject;
    if (project == null) return '(проект не открыт)';
    try {
      final entries = projectTreeEntries()
          .where((entry) {
            final p = entry.relativePath.replaceAll('\\', '/');
            if (p.isEmpty) return false;
            if (p == '.cppagent' || p.startsWith('.cppagent/')) return false;
            if (p == 'build' || p.startsWith('build/')) return false;
            return true;
          })
          .take(maxItems + 1)
          .toList(growable: false);
      if (entries.isEmpty) return '(проект пока пустой)';
      final buffer = StringBuffer();
      for (var i = 0; i < entries.length && i < maxItems; i++) {
        final entry = entries[i];
        final indent = '  ' * entry.depth;
        buffer.writeln(
            '$indent${entry.isDirectory ? '📁' : '📄'} ${entry.relativePath}');
      }
      if (entries.length > maxItems)
        buffer.writeln(
            '... ещё ${entries.length - maxItems}+ элементов. Используй project_map/list_files для полного просмотра.');
      return buffer.toString().trimRight();
    } catch (error) {
      return '(не удалось построить карту проекта: $error)';
    }
  }

  List<Map<String, String>> buildMessagesForModel() {
    final project = currentProject;
    final activeTaskBlock = activeTaskText.trim().isEmpty
        ? 'Активная задача ещё не задана.'
        : 'Активная исходная задача пользователя, которую нельзя терять при сжатии контекста:\n${truncateMiddle(activeTaskText, 16000)}';
    final stateBlock =
        const JsonEncoder.withIndent('  ').convert(taskStateJson());
    final environmentBlock = hostEnvironmentSummary();
    final localToolsBlock = localToolsCompactSummary(maxItems: 12);
    final projectStructureBlock = projectStructureCompactSummary(maxItems: 140);
    final automationBlock = automationSummaryForPrompt();
    final system =
        '''Ты локальный Codex/OpenCode-подобный агент программирования внутри Flutter-оболочки.
Текущий проект: ${project?.path ?? ''}
Среда выполнения агента:
$environmentBlock

Локальные программы пользователя из папки tools, доступные с приоритетом:
$localToolsBlock

Текущая структура проекта, чтобы учитывать уже существующие файлы:
$projectStructureBlock

Память найденных решений и подсказки по прошлым ошибкам:
${solutionMemoryCompactSummary(maxItems: 30)}

Automation, indexing, API outputs and custom tools:
$automationBlock

Почта:
- Настроенные почтовые аккаунты доступны через email_list_accounts. Для подготовки письма используй email_draft_smtp; фактическую отправку без подтверждения пользователя не выполняй.
- Если почта не настроена, попроси добавить адрес в настройках программы.

Правила папки tools и загрузки ПО:
- Папка tools предназначена для переносимых утилит пользователя и программ, которые агент может скачать/распаковать/настроить под твоим руководством.
- На Windows x64 главный путь: tools/windows/x64. Эти папки добавляются в PATH раньше системного PATH.
- Если для задачи нужен компилятор, архиватор, Python, CMake, Ninja, Node.js или другая программа, сначала проверь tools через list_local_tools.
- Если подходящей программы нет, предложи или выполни download_to_tools, затем extract_zip_to_tools/setup через run_command.
- Не устанавливай скачанное ПО в Program Files или системные папки без явного разрешения пользователя: по умолчанию всё клади в tools.

Python-среда:
- Никогда не устанавливай пакеты в общий Python пользователя.
- Для pip install / python -m pip install / pytest / запуска Python-скриптов агент использует проектное виртуальное окружение `.cppagent/python_venv`.
- Если нужного пакета нет, используй pip install как обычную команду; агент автоматически перепишет её на установку в `.cppagent/python_venv` и добавит venv Python в PATH.
- Если Python падает с ModuleNotFoundError, агент создаёт venv, устанавливает недостающий пакет туда и повторяет команду один раз.

Работай только внутри текущего проекта, если пользователь явно не приложил внешний файл для чтения/распаковки.
Не используй встроенные предметные шаблоны. Создавай и меняй файлы строго по заданию пользователя.

Гибкий порядок работы по типам задач:
- Для задач разработки в проекте используй PROJECT_PREFLIGHT_AUDIT, если он есть в скрытом контексте. Для поиска по компьютеру, чтения документов, интернет-справки и работы с приложенными файлами не подменяй запрос аудитом проекта.
- Если проект пустой — создай структуру с нуля. Если файлы явно от другой задачи — перенеси их в `.cppagent/reserved_before_task/<timestamp>/` через move_path и только потом создавай нужные файлы.
- Для создания ПО: project_map/list_files/read_file -> set_task_plan -> write_file/replace_text -> run_tests/run_command -> исправление ошибок -> повторная сборка/запуск.
- Для анализа/редактирования файлов устройства: list_device_directory/read_device_* или search_device_documents; не используй компиляцию.
- Для настройки систем/серверов: сначала диагностика окружения, затем команды через run_command/ssh/powershell, затем проверка результата.
- Для документов/таблиц/презентаций: read_document_structure для анализа структуры и текста, create_document_from_text для создания, edit_document_text для правок; затем проверь наличие результата чтением структуры или списка файлов.
- Для почты: используй email_list_accounts, подготовь письмо через email_draft_smtp, не отправляй без подтверждения пользователя.
- Не переписывай один и тот же файл много раз. Если файл изменён 2-4 раза — переходи к сборке/проверке или читай конкретную ошибку.


Интернет, зависимости и самостоятельная реализация:
- Если пользователь явно пишет «не используй дополнительные библиотеки», «пиши код самостоятельно», «сам реализуй», «без библиотек», то НЕ скачивай и НЕ подключай сторонние библиотеки для основной логики. Реализуй алгоритм сам: разбей задачу на подзадачи, пиши рабочие модули, тестируй части, соединяй, компилируй и запускай.
- Если пользователь не запретил интернет и не запретил зависимости, а задача объективно требует тяжёлую библиотеку/SDK/инструмент, сначала используй duckduckgo_search, web_fetch и web_deep_fetch для поиска официальной документации/загрузки, затем download_to_tools/download_to_project и подключение через файлы проекта. Если скачать/подключить не получилось — реализуй минимально рабочий вариант самостоятельно.
- Если пишешь собственную библиотеку, можешь искать подсказки, статьи, форумы и книги через интернет-инструменты, но итоговый код должен быть адаптирован, проверен и собран в проекте. Сохраняй полезные выводы в knowledge_store.
- При сложных задачах дроби план рекурсивно: задача → подзадачи → мелкие проверяемые шаги; тестируй отдельные модули, затем соединяй и тестируй всё вместе.
- Если нужно найти похожие реализации на компьютере и это разрешено настройками, используй filesystem_search. Если поиск по компьютеру запрещён, не пытайся обходить запрет.
- Если пользователь просит вывести содержимое внешней папки/файлов, например `O:\\...`, не используй `run_command dir/type` как основной способ. Используй `list_device_directory`, `read_device_text_file` или `read_device_folder_texts`, потому что они читают файлы через API приложения и корректно работают с кириллицей/пробелами в путях. Для фразы «и подпапок» передавай recursive=true. Инструмент должен читать txt/csv/html/xml/rtf/doc/docx/xls/xlsx/ppt/pptx/pdf и файлы внутри zip/7z/rar best-effort.
- Если пользователь просит найти документ в папке и процитировать требования/пункты/дату утверждения, НЕ выводи просто список файлов и НЕ печатай все файлы подряд. Используй search_device_documents с query по смыслу запроса, затем читай только релевантные найденные документы и цитируй нужные пункты слово в слово.
- Если пользователь просит «упакуй/заархивируй каждую игру/папку/файл в отдельный архив» во внешней или выбранной папке, используй `archive_device_children`, а не создавай пустые папки внутри проекта. Если путь не указан, используй последнее выбранное или прочитанное расположение устройства.
- Если пользователь просит «найди реализацию в интернете и установи в проект», используй duckduckgo_search, web_fetch, download_to_project, inspect_zip/extract_zip и затем адаптируй код в проекте. Не копируй неизвестный код вслепую: читай файл, подключай осознанно, собирай и запускай проверку.
- Не отвечай «для этого нужны тяжёлые библиотеки» как финальный отказ. Это только диагностический вывод: после него нужно либо установить/подключить зависимость, либо написать самописную реализацию.
- Не используй фиктивные значения вроде `cmake_file_content`, `main_cpp_content`, `code_here`. В write_file всегда передавай полный реальный текст файла.
- Для поиска людей и биографий строго проверяй полное ФИО. Если пользователь просит «Редина Максима Юрьевича», результаты про «Максима Игоревича» или другого человека НЕ подходят. Не подменяй отчество/имя; такие совпадения помечай как чужие и не составляй по ним биографию запрошенного человека.
- Для людей используй только публично доступные источники, не обходи приватность и не выдавай предположения о родственниках/друзьях/отношениях как доказанные факты без прямого источника. Если связь или отношение не подтверждены, помечай как непроверенное совпадение.
- Не включай в итоговый список источников URL про других людей. Если web_research пометил источник как REJECTED_SIMILAR_OR_UNCONFIRMED_SOURCES, его можно упомянуть только в отдельном разделе «Отсеянные похожие совпадения», но нельзя выдавать как источник по искомому человеку.
- Изображения/фото выводи только если web_fetch/web_research вернул их в IMAGES или RELEVANT_IMAGES и они относятся к точному запросу. К каждому фото добавь краткое описание и URL.
- Поисковые задачи выполняй углублённо: по умолчанию используй web_research. Если нужно вручную — сначала duckduckgo_search, затем web_fetch/web_deep_fetch, переход по полезным внутренним и внешним ссылкам, follow-up запросы по найденным профилям/работе/контактам/связанным людям/терминам, сверка точного запроса с найденными фактами, только потом итог. Если точного совпадения нет — так и напиши, без биографии по однофамильцам.
- Для чистого интернет-поиска, биографии, справки о человеке, организации или сайте НЕ запускай run_command/run_tests, НЕ создавай исходники и НЕ компилируй проект. После web_research дай итог по источникам и остановись.
- Перед финальным ответом сделай внутреннюю проверку качества: ответ должен соответствовать точной задаче пользователя, содержать источники/URL для найденных фактов, перечислять отсеянные похожие совпадения и уровень уверенности. Не дублируй одинаковые ссылки.
- После успешного результата инструмента не запускай задачу повторно. Если инструмент уже вернул полный требуемый текст/список/результат, дай итог и остановись.

Служебная папка `.cppagent`:
- `.cppagent` предназначена только для внутренних данных агента: логи, планы, память, сессии, временные файлы, python_venv.
- НЕ создавай в `.cppagent` исходный код, CMakeLists.txt, package.json, README пользователя, тесты, ассеты, датасеты и другие рабочие файлы проекта.
- Рабочие файлы создавай в корне проекта или в обычных папках: `src`, `include`, `tests`, `data`, `assets`, `build_scripts`.
- Для C++ проекта основной `CMakeLists.txt` должен быть в корне проекта или в выбранной рабочей подпапке, но не в `.cppagent`.
- Если прошлые версии агента случайно создали рабочие файлы в `.cppagent`, скопируй нужное содержимое в нормальную папку проекта и продолжай работать уже там.

$activeTaskBlock

Последнее выбранное или прочитанное расположение устройства: ${lastDeviceDirectoryPath.trim().isEmpty ? '(не задано)' : lastDeviceDirectoryPath}.
Если пользователь в следующем сообщении пишет «эту папку», «каждую игру», «упакуй всё», «прочитай выбранное расположение» без нового пути — используй это расположение или выбранные SELECTED_LOCATION из текущей задачи.

Текущее состояние выполнения задачи:
$stateBlock

Формат действий: желательно использовать native OpenAI tool_calls. Если сервер не поддерживает native tools, используй строго закрытый XML-вызов:
<tool_call>{"name":"write_file","args":{"path":"relative/path","content":"..."}}</tool_call>
Никогда не начинай <tool_call>, если не можешь полностью закрыть JSON и </tool_call> в этом же ответе.

Режим прав проекта: ${permissionMode.label}. Интернет: ${allowInternetUse ? 'разрешён' : 'запрещён'}. Поиск по устройству: ${allowComputerSearch ? 'разрешён' : 'запрещён'}. Доступ к файлам устройства: ${allowDeviceFileAccess ? 'разрешён' : 'запрещён'}.
Режим создания проекта: ${creationMode.label}.
Проверка качества результата: ${qualityCheckEnabled ? 'включена' : 'отключена'}.
Лимиты профиля: context window=$maxContextTokens токенов; max output=$maxOutputTokens токенов. Это разные настройки.
Доступные tools: project_map, list_files, list_local_tools, rebuild_device_index, search_device_index, recognize_image_text, run_custom_tool, duckduckgo_search, web_fetch, web_deep_fetch, web_research, filesystem_search, list_device_directory, read_device_text_file, read_device_folder_texts, search_device_documents, read_document_structure, create_document_from_text, edit_document_text, archive_device_children, knowledge_search, knowledge_store, email_list_accounts, email_draft_smtp, download_to_project, set_task_plan, download_to_tools, extract_zip_to_tools, remember_solution, read_file, write_file, create_file, append_file, replace_text, make_dir, delete_path, copy_path, move_path, run_command, run_tests, inspect_zip, extract_zip, read_docx_text, read_xlsx_text.

Правила полноценного агента:
1. Если задача требует файлов, не ограничивайся планом — в том же ответе вызывай инструменты.
2. После записи кода сам запускай проверку/сборку/запуск через run_command или run_tests, если это применимо. Если создал подпапку проекта, укажи cwd или запускай команду с правильным -S/-B.
3. Если команда завершилась с ошибкой, исправь файлы и повтори команду.
4. Не оставляй content пустым: если не можешь выполнить задачу, ответь видимым текстом почему.
5. После каждого tool-result продолжай исходную задачу, пока она реально не завершена и проверена.
6. Финальный ответ давай только после проверки результата или после честного объяснения невозможности.
6.1. Если tool-result содержит `FINAL_STATUS: SUCCESS` или `[AUTO_BUILD_FALLBACK_SUCCESS]`, считай проверку успешной: не запускай снова неудачную CMake-команду, дай краткий итог.
7. Если пишешь план, сразу после плана начни делать действия инструментами; не останавливайся на плане.
8. Пути для write_file/read_file/delete_path должны быть относительными к проекту. Не используй `.cppagent` для пользовательских файлов: эта папка зарезервирована агентом.
9. Если stdout/stderr говорит, что не найден g++, cl, clang++, cmake, flutter, npm или другая команда, это ошибка окружения, а не ошибка исходного кода. В такой ситуации не переписывай рабочий файл на заглушку; попробуй альтернативную команду или честно сообщи, какой инструмент нужно установить.
10. Не ухудшай реализацию после ошибки окружения: не заменяй полноценный код на placeholder/conceptual example.
11. Для команд и компиляции сначала используй программы из tools/$hostOsSegment/$hostArchSegment и других подпапок tools: агент добавляет эти папки в PATH перед системным PATH.
12. Если не найден g++, cl, clang++, python, cmake или другой инструмент, сначала проверь список через list_local_tools/run_tests. Только если подходящих программ в tools нет — сообщай пользователю, что инструмент отсутствует. Если CMake ругается на отсутствующий main.cpp или CMakeLists.txt, это проблема структуры сборки: исправь CMakeLists.txt или используй run_tests, который умеет собрать найденный .cpp.
21. Если в tools найден g++.exe/clang++.exe, предпочитай прямую компиляцию через run_tests; не называй отсутствие cmake ошибкой, когда доступен C++ компилятор.
22. На Windows для MinGW/MSYS2 не заключай простые относительные пути исходников C++ в кавычки: используй `g++.exe -std=c++17 -O2 src\\main.cpp -o build\\app.exe`, а не `g++.exe "src/main.cpp" ...`.
23. Не объявляй C++ задачу завершённой, если последняя проверка содержит `BUILD_ARTIFACT_MISSING`, `EXIT_CODE` не равен 0, или в исходниках остались слова вроде `заглушка`, `conceptual`, `omitted`, `TODO`, `оставим позже`. Сначала исправь код и повтори run_tests.
13. Учитывай ОС и архитектуру из блока среды: на Windows x64 используй .exe/.bat/.cmd и команды cmd.exe; на Linux/macOS используй sh-команды.
14. Для Python-зависимостей не используй глобальный pip. Устанавливай пакеты только через проектное окружение `.cppagent/python_venv`; агент сам создаст его и перепишет команду.
15. Сложные задачи разбивай на подзадачи через set_task_plan: анализ среды, план файлов, создание/изменение, проверка, исправление ошибок, повторная проверка, финальный итог.
16. При ошибке не останавливайся сразу: спроси себя через модель, какое следующее действие поможет — проверить tools, скачать ПО в tools, распаковать, настроить PATH/venv, исправить код, повторить команду.
17. Когда нашёл рабочий способ решения ошибки или сборки, вызови remember_solution, чтобы агент подсказывал этот способ в следующих задачах.
18. Останавливайся и проси вмешательство пользователя только после исчерпания разумных способов: локальные tools, альтернативные команды, скачивание/распаковка в tools, настройка окружения проекта, исправление кода по stdout/stderr.
19. Перед изменением существующего проекта сначала изучи его структуру через project_map/list_files и прочитай важные существующие файлы через read_file. Не перезаписывай существующий рабочий файл вслепую: сначала прочитай его, затем используй replace_text или осознанный write_file.
20. План выполнения задачи должен учитывать существующие файлы проекта, текущие CMakeLists.txt/package files/config files и прошлые результаты команд. Если задача продолжает предыдущую, используй уже созданные файлы, а не начинай заново в случайной подпапке.
''';
    final contextMessages = <Map<String, String>>[
      {'role': 'system', 'content': system}
    ];
    final reserveOutputTokens = maxOutputTokens.clamp(1024, 32768).toInt();
    final minPromptBudgetTokens =
        maxContextTokens < 2048 ? maxContextTokens : 2048;
    final promptBudgetTokens = (maxContextTokens - reserveOutputTokens)
        .clamp(minPromptBudgetTokens, maxContextTokens)
        .toInt();
    final budgetChars = (promptBudgetTokens * 3.2).floor();
    var used = system.length;
    final selected = <ChatMessage>[];
    var compressedHistory = false;
    final lastCompressionIndex = messages.lastIndexWhere((m) =>
        m.role == 'separator' &&
        m.content == 'Автоматическое сжатие контекста');
    final scopedMessages = lastCompressionIndex >= 0
        ? messages.skip(lastCompressionIndex + 1).toList(growable: false)
        : messages;
    for (final message in scopedMessages.reversed) {
      if (message.transient || message.role == 'separator') continue;
      if (message.role == 'assistant' &&
          message.content.startsWith('Ошибка агента: Bad state: HTTP'))
        continue;
      if (message.role == 'assistant' &&
          message.content.startsWith('Ошибка контекста сервера')) continue;
      final content = compressHistoryContent(message.content);
      final cost = content.length + message.role.length + 24;
      if (used + cost > budgetChars && selected.length >= 4) {
        compressedHistory = true;
        break;
      }
      selected.add(message.copyWith(content: content, touch: false));
      used += cost;
    }
    if (compressedHistory && selected.isNotEmpty) {
      insertContextCompressionMarkerBefore(selected.last.id);
    }
    for (final message in selected.reversed) {
      contextMessages.add({'role': message.role, 'content': message.content});
    }
    return contextMessages;
  }

  void insertContextCompressionMarkerBefore(String boundaryMessageId) {
    if (lastContextCompressionBoundaryId == boundaryMessageId) return;
    final boundaryIndex = messages.indexWhere((m) => m.id == boundaryMessageId);
    if (boundaryIndex <= 0) return;
    final alreadyNear = boundaryIndex > 0 &&
        messages[boundaryIndex - 1].role == 'separator' &&
        messages[boundaryIndex - 1].content ==
            'Автоматическое сжатие контекста';
    if (alreadyNear) {
      lastContextCompressionBoundaryId = boundaryMessageId;
      return;
    }
    final marker = ChatMessage(
        role: 'separator', content: 'Автоматическое сжатие контекста');
    messages.insert(boundaryIndex, marker);
    final hiddenSummary = ChatMessage(
      role: 'assistant',
      content: '''### Сжатый контекст
```text
История выше этой черты больше не отправляется модели и не учитывается в текущей длине контекста. Работа продолжается только по сообщениям ниже черты, активной задаче, состоянию выполнения и памяти решений.
```''',
    );
    messages.insert(boundaryIndex + 1, hiddenSummary);
    lastContextCompressionBoundaryId = boundaryMessageId;
    try {
      appendSessionSync(marker);
      appendSessionSync(hiddenSummary);
    } catch (_) {}
    log('CONTEXT COMPRESSION MARKER INSERTED before=$boundaryMessageId');
    notifyUi();
  }

  void appendSessionSync(ChatMessage message) {
    final project = currentProject;
    if (project == null) return;
    final sessionsDir =
        Directory(pathJoin(project.path, '.cppagent', 'sessions'));
    sessionsDir.createSync(recursive: true);
    final file = File(pathJoin(sessionsDir.path, 'session.jsonl'));
    file.writeAsStringSync('${jsonEncode(message.toJson())}\n',
        mode: FileMode.append, encoding: utf8);
  }

  String compressHistoryContent(String content) {
    if (content.length <= 24000) return content;
    if (content.startsWith('Tool result'))
      return truncateMiddle(content, 12000);
    return truncateMiddle(content, 18000);
  }

  Future<AgentProcessResult> processAssistantText(String assistantText) async {
    log('MODEL TEXT: ${truncateMiddle(assistantText, 12000)}');
    pendingFileChanges.clear();
    final toolCalls = parseToolCalls(assistantText);
    final extractedFiles = extractMarkdownFiles(assistantText);
    final hasAnyToolTag = assistantText.contains('<tool_call>');
    final truncated = lastModelFinishReason == 'length';
    final hasBrokenToolCall = assistantText.contains('<tool_call>') &&
        !assistantText.contains('</tool_call>');
    var visibleText = stripToolCalls(assistantText).trim();
    if (hasAnyToolTag && toolCalls.isEmpty && extractedFiles.isEmpty) {
      log('MALFORMED TOOL_CALL HIDDEN FROM CHAT: ${truncateMiddle(assistantText, 2000)}');
      visibleText = '';
    }
    if (truncated && toolCalls.isEmpty && extractedFiles.isEmpty) {
      log('MODEL OUTPUT TRUNCATED: finish_reason=length; hidden from visible chat; brokenToolCall=$hasBrokenToolCall');
      visibleText = '';
    }
    if (visibleText.isNotEmpty) {
      visibleText = deduplicateVisibleUrls(visibleText);
      if (allowFollowUpSuggestions &&
          !containsFollowUpSuggestions(visibleText) &&
          !visibleText.toLowerCase().contains('ошибка агента')) {
        visibleText = addFollowUpSuggestions(visibleText);
      }
      final qualityIssue = finalAnswerQualityIssue(visibleText);
      if (qualityIssue.isNotEmpty) {
        lastFinalAnswerQualityIssue = qualityIssue;
        log('FINAL ANSWER QUALITY BLOCKED: $qualityIssue');
        await updateLiveProgress(
            '🔎 Ответ не прошёл проверку качества: $qualityIssue');
        visibleText = '';
      }
    }
    if (visibleText.isNotEmpty) {
      final grouped = recordGroupedAssistantTextIfNeeded(visibleText);
      if (grouped) {
        log('MODEL VISIBLE TEXT GROUPED: ${truncateMiddle(visibleText, 2000)}');
        await updateLiveProgress(
            '🔁 Повторяющиеся сообщения объединяются в скрытый блок. Продолжаю выполнение...');
      } else {
        final message = ChatMessage(role: 'assistant', content: visibleText);
        messages.add(message);
        await appendSession(message);
        notifyUi();
      }
    }
    var didAction = false;
    final toolResultBuffer = StringBuffer();
    for (final file in extractedFiles) {
      if (cancelRequested) {
        log('PROCESS ASSISTANT TEXT: cancelled before markdown file write ${file.path}');
        break;
      }
      await updateLiveProgress('📝 Записываю файл ${file.path}...');
      final markdownCall = ToolCall(
          name: 'write_file',
          args: {'path': file.path, 'content': file.content});
      final allowed =
          await checkToolPermission(markdownCall, markdownFile: true);
      final result = allowed
          ? await writeRelativeFile(file.path, file.content)
          : 'Permission denied for markdown file write: ${file.path}';
      didAction = true;
      taskToolActions++;
      final markdownTool = ToolCall(
          name: 'write_file',
          args: {'path': file.path, 'content': '[markdown block]'});
      recordActionAttempt(markdownTool, result);
      toolResultBuffer.writeln(
          'Tool result for markdown_file ${file.path}\nok: ${allowed ? 'true' : 'false'}\n$result\n');
      log('MARKDOWN FILE ${file.path}: $result');
    }
    for (final call in toolCalls) {
      if (cancelRequested) {
        log('PROCESS ASSISTANT TEXT: cancelled before tool ${call.name}');
        break;
      }
      await updateLiveProgress('⚙️ Выполняю ${call.name}...');
      final repeatBlock = repeatedMutationBlockReason(call);
      final result = repeatBlock ?? await executeTool(call);
      didAction = true;
      recordActionAttempt(call, result);
      toolResultBuffer.writeln('Tool result for ${call.name}\n$result\n');
      log('TOOL ${call.name}: ${truncateMiddle(result, 8000)}');
    }
    final fileChanges = takePendingFileChanges();
    if (toolResultBuffer.isNotEmpty) {
      final message = ChatMessage(
          role: 'user',
          content: toolResultBuffer.toString().trimRight(),
          internal: true);
      messages.add(message);
      await appendSession(message);
    }
    if (fileChanges.isNotEmpty) {
      taskFileChanges.addAll(fileChanges);
      final changedNames = fileChanges.map((f) => f.path).take(5).join(', ');
      final suffix =
          fileChanges.length > 5 ? ' и ещё ${fileChanges.length - 5}' : '';
      await updateLiveProgress(
          '📝 Изменены файлы: $changedNames$suffix. Продолжаю проверку результата...');
    }
    return AgentProcessResult(
        didAction: didAction,
        toolCallCount: toolCalls.length,
        fileWriteCount: extractedFiles.length);
  }

  void recordActionAttempt(ToolCall call, String result) {
    final key = actionSummaryKey(call);
    final title = actionSummaryTitle(call);
    final success = toolResultLooksSuccessful(call.name, result);
    final attempt = AgentActionAttempt(
      timestamp: DateTime.now().toIso8601String(),
      result: truncateMiddle(result, 60000),
      success: success,
    );
    final current = taskActionSummaries[key];
    if (current == null) {
      taskActionSummaries[key] = AgentActionSummary(
        key: key,
        title: title,
        firstSeen: DateTime.now().microsecondsSinceEpoch,
        attempts: [attempt],
      );
    } else {
      current.attempts.add(attempt);
    }
    refreshLiveProgressActions();
  }

  bool recordGroupedAssistantTextIfNeeded(String text) {
    final category = repeatedAssistantTextCategory(text);
    if (category == null) return false;
    final title = switch (category) {
      'compile_attempt' => 'Попытка компиляции',
      'model_connection' => 'Ошибки подключения к модели',
      _ => 'Повторяющиеся сообщения',
    };
    final attempt = AgentActionAttempt(
      timestamp: DateTime.now().toIso8601String(),
      result: truncateMiddle(text, 60000),
      success: false,
    );
    final key = 'assistant_text:$category';
    final current = taskActionSummaries[key];
    if (current == null) {
      taskActionSummaries[key] = AgentActionSummary(
        key: key,
        title: title,
        firstSeen: DateTime.now().microsecondsSinceEpoch,
        attempts: [attempt],
      );
    } else {
      final last = current.attempts.isEmpty ? '' : current.attempts.last.result;
      if (normalizeRepeatedText(last) != normalizeRepeatedText(text)) {
        current.attempts.add(attempt);
      }
    }
    refreshLiveProgressActions();
    return true;
  }

  bool containsFollowUpSuggestions(String text) {
    final lower = text.toLowerCase();
    return lower.contains('дальнейш') ||
        lower.contains('следующ') ||
        lower.contains('что можно сделать');
  }

  String addFollowUpSuggestions(String text) {
    final lower = activeTaskText.toLowerCase();
    final suggestions = <String>[];
    if (taskLooksLikeWebResearchTask()) {
      suggestions.add(
          'уточнить город, организацию или источник и повторить углублённый поиск');
      suggestions.add(
          'открыть найденные ссылки во вкладке Web и проверить первоисточники');
    } else if (taskLooksLikeDeviceFileReadTask()) {
      suggestions
          .add('увеличить лимит файлов/символов и повторить чтение папки');
      suggestions.add('сохранить извлечённый текст в файл проекта');
    } else if (lower.contains('код') || lower.contains('программ')) {
      suggestions.add('запустить сборку/тесты ещё раз после правок');
      suggestions.add('добавить отдельные тесты для проблемных модулей');
    } else {
      suggestions.add('уточнить требования и запустить следующий шаг');
      suggestions.add('сохранить полезный итог в базу знаний проекта');
    }
    return text.trimRight() +
        '\n\n**Дальнейшие действия:**\n' +
        suggestions.map((s) => '- $s').join('\n');
  }

  String deduplicateVisibleUrls(String text) {
    final seenUrls = <String>{};
    final lines = text.split('\n');
    final kept = <String>[];
    for (final line in lines) {
      final urls = RegExp(r'https?://[^\s\)\]}>]+')
          .allMatches(line)
          .map((m) => (m.group(0) ?? '').replaceAll(RegExp(r'[\.,;:]+$'), ''))
          .toList();
      if (urls.isNotEmpty && urls.every(seenUrls.contains)) continue;
      for (final url in urls) seenUrls.add(url);
      kept.add(line);
    }
    return kept.join('\n').replaceAll(RegExp(r'\n{4,}'), '\n\n\n');
  }

  String? repeatedAssistantTextCategory(String text) {
    final lower = text.toLowerCase();
    if ((lastCommandExitCode != null && lastCommandExitCode != 0) ||
        lastCommandResultText.contains('BUILD_ARTIFACT_MISSING')) {
      if (lower.contains('застряли в цикле ошибок компиляции') ||
          lower.contains('цикл ошибок компиляции') ||
          lower.contains('build_artifact_missing') ||
          lower.contains('exit code 2') ||
          lower.contains('exit code 1') ||
          lower.contains('run_command') ||
          lower.contains('cmd') && lower.contains('компил') ||
          lower.contains('исчерпал') && lower.contains('компил')) {
        return 'compile_attempt';
      }
    }
    if (lower.contains('socketexception') ||
        lower.contains('failed to load model') ||
        lower.contains('http 400') ||
        lower.contains('ошибка агента:')) {
      return 'model_connection';
    }
    return null;
  }

  String normalizeRepeatedText(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'`[^`]*`'), '`x`')
        .replaceAll(RegExp(r'\d+'), '0')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String actionSummaryKey(ToolCall call) {
    final name = call.name;
    final command = call.args['command']?.toString().trim() ?? '';
    final path = call.args['path']?.toString() ?? '';
    final from = call.args['from']?.toString() ?? '';
    final to = call.args['to']?.toString() ?? '';
    if (name == 'run_command') return 'run_command:$command';
    if (name == 'run_tests')
      return "run_tests:${command.isEmpty ? 'auto' : command}";
    if (path.isNotEmpty) return '$name:$path';
    if (from.isNotEmpty || to.isNotEmpty) return '$name:$from->$to';
    return '$name:${jsonEncode(call.args)}';
  }

  String actionSummaryTitle(ToolCall call) {
    final name = call.name;
    final command = call.args['command']?.toString().trim() ?? '';
    final path = call.args['path']?.toString() ?? '';
    if (name == 'run_command') return 'Команда: $command';
    if (name == 'run_tests')
      return command.isEmpty ? 'Автопроверка проекта' : 'Проверка: $command';
    if (name == 'write_file' || name == 'create_file')
      return 'Запись файла: $path';
    if (name == 'append_file') return 'Дополнение файла: $path';
    if (name == 'replace_text') return 'Изменение файла: $path';
    if (name == 'read_file') return 'Чтение файла: $path';
    if (name == 'list_device_directory') return 'Просмотр папки: $path';
    if (name == 'read_device_text_file')
      return 'Чтение файла устройства: $path';
    if (name == 'read_device_folder_texts')
      return 'Чтение папки устройства: $path';
    if (name == 'search_device_documents') return 'Поиск в документах: $path';
    if (name == 'filesystem_search')
      return 'Поиск по компьютеру: ${call.args['query'] ?? ''}';
    if (name == 'read_document_structure') return 'Анализ документа: $path';
    if (name == 'create_document_from_text') return 'Создание документа: $path';
    if (name == 'edit_document_text') return 'Редактирование документа: $path';
    if (name == 'web_research')
      return 'Интернет-исследование: ${call.args['query'] ?? ''}';
    if (name == 'web_fetch')
      return 'Чтение веб-страницы: ${call.args['url'] ?? ''}';
    if (name == 'duckduckgo_search')
      return 'Поиск в интернете: ${call.args['query'] ?? ''}';
    if (name == 'delete_path') return 'Удаление: $path';
    if (name == 'make_dir') return 'Создание папки: $path';
    return 'Действие: $name';
  }

  bool toolResultLooksSuccessful(String toolName, String result) {
    if (toolName == 'run_command' || toolName == 'run_tests') {
      final match = RegExp(r'EXIT_CODE:\s*(-?\d+)', caseSensitive: false)
          .firstMatch(result);
      return match != null && int.tryParse(match.group(1) ?? '') == 0;
    }
    final lower = result.toLowerCase();
    return !lower.contains('permission denied') &&
        !lower.contains('error:') &&
        !lower.contains('failed') &&
        !lower.contains('ошибка');
  }

  List<ToolCall> parseToolCalls(String text) {
    final result = <ToolCall>[];
    void addIfUnique(ToolCall call) {
      final signature = '${call.name}:${jsonEncode(call.args)}';
      if (result.any((existing) =>
          '${existing.name}:${jsonEncode(existing.args)}' == signature)) return;
      result.add(call);
    }

    // Надёжный XML-парсер tool_call: берём весь текст между тегами, а не первую пару фигурных скобок.
    // Это важно для write_file, потому что содержимое C++/Dart/PHP файлов содержит множество `{}`.
    final xmlBlocks =
        RegExp(r'<tool_call>\s*([\s\S]*?)\s*</tool_call>', caseSensitive: false)
            .allMatches(text);
    for (final match in xmlBlocks) {
      final block = (match.group(1) ?? '').trim();
      if (block.isEmpty) continue;
      try {
        final data = jsonDecode(block) as Map<String, dynamic>;
        final name = data['name']?.toString() ?? '';
        if (name.isNotEmpty)
          addIfUnique(ToolCall(name: name, args: normalizeArgs(data['args'])));
        continue;
      } catch (_) {
        // fallback ниже
      }
      final legacyNamed =
          RegExp(r'^\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*(\{[\s\S]*\})\s*$')
              .firstMatch(block);
      if (legacyNamed != null) {
        final name = legacyNamed.group(1) ?? '';
        final body = legacyNamed.group(2) ?? '';
        try {
          addIfUnique(
              ToolCall(name: name, args: normalizeArgs(jsonDecode(body))));
          continue;
        } catch (_) {
          final args = parseLegacyToolArgs(body.substring(1, body.length - 1));
          if (name.isNotEmpty && args.isNotEmpty)
            addIfUnique(ToolCall(name: name, args: args));
          continue;
        }
      }
      final maybeJson = RegExp(r'\{[\s\S]*\}').firstMatch(block)?.group(0);
      if (maybeJson != null) {
        try {
          final data = jsonDecode(maybeJson) as Map<String, dynamic>;
          final name = data['name']?.toString() ?? '';
          if (name.isNotEmpty)
            addIfUnique(
                ToolCall(name: name, args: normalizeArgs(data['args'])));
        } catch (_) {}
      }
    }

    // Native-stream fallback уже преобразует вызовы в XML; этот код нужен для старых/сломанных локальных моделей.
    final loose = RegExp(
        r'<tool_call>\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*(\{[\s\S]*?\})\s*(?:<tool_call\|>|\)\))',
        caseSensitive: false);
    for (final match in loose.allMatches(text)) {
      try {
        addIfUnique(ToolCall(
            name: match.group(1)!,
            args: normalizeArgs(jsonDecode(match.group(2)!))));
      } catch (_) {}
    }

    final legacy = RegExp(
        r'<tool_call>\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\{([\s\S]*?)\}\s*(?:<tool_call\|>)',
        caseSensitive: false);
    for (final match in legacy.allMatches(text)) {
      final name = match.group(1) ?? '';
      final body = match.group(2) ?? '';
      if (name.isEmpty) continue;
      final args = parseLegacyToolArgs(body);
      if (args.isEmpty) continue;
      addIfUnique(ToolCall(name: name, args: args));
    }
    return result;
  }

  Map<String, dynamic> parseLegacyToolArgs(String body) {
    final normalized = body.replaceAll('<|"|>', '"').replaceAll('<|\"|>', '"');
    final args = <String, dynamic>{};
    final pairPattern =
        RegExp(r'([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*"([\s\S]*?)"\s*(?:,|$)');
    for (final match in pairPattern.allMatches(normalized)) {
      final key = match.group(1) ?? '';
      final value = match.group(2) ?? '';
      if (key.isNotEmpty) args[key] = value;
    }
    if (args.isEmpty && normalized.trim().isNotEmpty)
      args['command'] = normalized.trim();
    return args;
  }

  Map<String, dynamic> normalizeArgs(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map)
      return raw.map((key, value) => MapEntry(key.toString(), value));
    if (raw is String) return {'command': raw};
    return <String, dynamic>{};
  }

  bool isFileMutationToolName(String name) => const {
        'write_file',
        'create_file',
        'append_file',
        'replace_text',
        'make_dir',
        'delete_path',
        'copy_path',
        'move_path',
        'create_document_from_text',
        'edit_document_text'
      }.contains(name);

  String mutationPathForTool(ToolCall call) {
    if (call.name == 'copy_path' || call.name == 'move_path') {
      return '${call.args['from'] ?? ''}->${call.args['to'] ?? ''}'.trim();
    }
    return (call.args['path'] ?? '').toString().trim();
  }

  String? repeatedMutationBlockReason(ToolCall call) {
    if (!isFileMutationToolName(call.name)) return null;
    final path = mutationPathForTool(call).replaceAll('\\', '/');
    if (path.isEmpty) return null;
    final key = '${call.name}:$path';
    final count = (taskFileMutationAttempts[key] ?? 0) + 1;
    taskFileMutationAttempts[key] = count;
    if (count <= 6) return null;
    if (taskCommandRuns == 0) {
      return 'REPEATED_FILE_MUTATION_BLOCKED: файл/путь `$path` уже изменялся $count раз инструментом `${call.name}`, но проверка/сборка ещё ни разу не запускалась. Нельзя бесконечно переписывать один файл. Следующее действие: project_map/read_file для проверки структуры или run_tests/run_command для сборки/проверки.';
    }
    if (lastCommandExitCode != null && lastCommandExitCode != 0) {
      return 'REPEATED_FILE_MUTATION_BLOCKED: файл/путь `$path` изменялся $count раз. Нужно исправлять конкретную ошибку из последнего stdout/stderr, а не снова переписывать тот же файл вслепую. Используй read_file/project_map и затем минимальный replace_text или run_tests.';
    }
    return null;
  }

  bool isPlaceholderToolContent(String content) {
    final value = content.trim();
    if (value.isEmpty) return false;
    final lower = value.toLowerCase();
    final compact = lower.replaceAll(RegExp(r'[^a-zа-я0-9_]+'), '');
    final known = <String>{
      'cmake_file_content',
      'main_cpp_content',
      'cpp_code_content',
      'source_code_content',
      'file_content',
      'content_here',
      'code_here',
      'todo',
      'placeholder',
      'здесьбудеткод',
      'текстфайла',
      'содержимоефайла',
    };
    if (known.contains(lower) || known.contains(compact)) return true;
    if (value.length <= 80 && !value.contains('\n')) {
      if (RegExp(r'^[a-zA-Z0-9_]+_content$').hasMatch(value)) return true;
      if (RegExp(r'^[a-zA-Z0-9_]+_code$').hasMatch(value)) return true;
    }
    return false;
  }

  String placeholderContentBlockedMessage(String path, String content) =>
      '''PLACEHOLDER_CONTENT_BLOCKED: файл `$path` не был изменён.
Модель передала вместо содержимого фиктивное значение `$content`.
Нужно повторить write_file/append_file/replace_text и передать полный реальный текст файла, а не имя переменной.''';

  String stripToolCalls(String text) {
    var cleaned =
        text.replaceAll(RegExp(r'<tool_call>[\s\S]*?</tool_call>'), '');
    cleaned =
        cleaned.replaceAll(RegExp(r'<tool_call>[\s\S]*?<tool_call\|>'), '');
    final open = cleaned.indexOf('<tool_call>');
    if (open >= 0) cleaned = cleaned.substring(0, open);
    return cleaned.trim();
  }

  List<ExtractedFile> extractMarkdownFiles(String text) {
    final files = <ExtractedFile>[];
    final pattern = RegExp(
        r'###\s+`?([^`\n]+?)`?\s*\n```[a-zA-Z0-9_+-]*\s*\n([\s\S]*?)```');
    for (final match in pattern.allMatches(text)) {
      final path = match.group(1)!.trim();
      final content = match.group(2)!;
      if (path.contains('.') && !path.contains(' '))
        files.add(ExtractedFile(path: path, content: content));
    }
    return files;
  }

  Map<String, Object?> sanitizeToolArgsForLog(
      String toolName, Map<String, dynamic> args) {
    final copy = <String, Object?>{};
    for (final entry in args.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key == 'content' || key == 'new_text' || key == 'old_text') {
        copy[key] = truncateMiddle(value?.toString() ?? '', 4000);
      } else {
        copy[key] = value is String ? truncateMiddle(value, 4000) : value;
      }
    }
    return copy;
  }

  bool isReadOnlyTool(String name) => const {
        'project_map',
        'list_files',
        'read_file',
        'list_local_tools',
        'duckduckgo_search',
        'web_fetch',
        'web_deep_fetch',
        'web_research',
        'filesystem_search',
        'list_device_directory',
        'read_device_text_file',
        'read_device_folder_texts',
        'search_device_documents',
        'read_document_structure',
        'knowledge_search',
        'email_list_accounts',
        'inspect_zip',
        'read_docx_text',
        'read_xlsx_text',
        'search_device_index',
        'recognize_image_text',
      }.contains(name);

  bool isCriticalTool(String name) => const {
        'run_command',
        'run_tests',
        'delete_path',
        'move_path',
        'copy_path',
        'extract_zip',
        'download_to_tools',
        'extract_zip_to_tools',
        'download_to_project',
        'knowledge_store',
        'archive_device_children',
        'create_document_from_text',
        'edit_document_text',
        'email_draft_smtp',
        'rebuild_device_index',
        'run_custom_tool',
      }.contains(name);

  String describeToolCall(ToolCall call) {
    final args = sanitizeToolArgsForLog(call.name, call.args);
    return const JsonEncoder.withIndent('  ')
        .convert({'name': call.name, 'args': args});
  }

  bool isPathInsideAllowedSandbox(String rawPath) {
    final project = currentProject;
    final path = isAbsolutePath(rawPath)
        ? rawPath
        : (project == null
            ? rawPath
            : resolveProjectPath(project.path, rawPath));
    String norm(String v) => v.replaceAll('\\', '/').toLowerCase();
    final n = norm(path);
    final allowed = [
      if (project != null) project.path,
      appRootPath,
      projectsRoot.path,
      toolsRoot.path,
      configRoot.path
    ].map(norm);
    return allowed.any((root) => n == root || n.startsWith('$root/'));
  }

  Future<bool> checkToolPermission(ToolCall call,
      {bool markdownFile = false}) async {
    final readOnly = isReadOnlyTool(call.name);
    final critical = isCriticalTool(call.name);
    final fileMutation = const {
          'write_file',
          'create_file',
          'append_file',
          'replace_text',
          'make_dir'
        }.contains(call.name) ||
        markdownFile;
    final reason = readOnly
        ? 'чтение/анализ без изменения файлов'
        : critical
            ? 'критичное действие: запуск команды, удаление, перемещение, копирование или распаковка'
            : fileMutation
                ? 'изменение файлов внутри проекта'
                : 'действие агента';

    if (const {
          'duckduckgo_search',
          'web_fetch',
          'web_deep_fetch',
          'web_research',
          'download_to_project',
          'download_to_tools'
        }.contains(call.name) &&
        !allowInternetUse) {
      log('PERMISSION BLOCKED: ${call.name}; internet tools are disabled in settings');
      return false;
    }
    if (call.name == 'filesystem_search' &&
        !allowComputerSearch &&
        permissionMode != PermissionMode.fullAccess) {
      log('PERMISSION BLOCKED: filesystem_search; computer search is disabled for this project');
      return false;
    }
    var externalFilePathNeedingPermission = '';
    if (call.name == 'filesystem_search') {
      final rawRoot = call.args['root']?.toString().trim() ?? '';
      if (rawRoot.isNotEmpty && !isPathInsideAllowedSandbox(rawRoot))
        externalFilePathNeedingPermission = rawRoot;
    }
    if (const {
      'list_device_directory',
      'read_device_text_file',
      'read_device_folder_texts',
      'search_device_documents',
      'archive_device_children',
      'read_document_structure',
      'create_document_from_text',
      'edit_document_text'
    }.contains(call.name)) {
      final rawPath = call.args['path']?.toString().trim() ?? '';
      if (rawPath.isNotEmpty && !isPathInsideAllowedSandbox(rawPath))
        externalFilePathNeedingPermission = rawPath;
    }
    if (externalFilePathNeedingPermission.isNotEmpty &&
        !allowDeviceFileAccess &&
        permissionMode != PermissionMode.fullAccess) {
      final approver = permissionApprover;
      if (approver == null) {
        log('PERMISSION BLOCKED: ${call.name}; external path requires device file access: $externalFilePathNeedingPermission');
        return false;
      }
      final allowedDeviceAccess = await approver(AgentPermissionRequest(
        toolName: call.name,
        details: describeToolCall(call),
        reason:
            'доступ к внешней файловой системе устройства: $externalFilePathNeedingPermission',
        critical: true,
      ));
      log('PERMISSION USER DECISION DEVICE FILE ACCESS: ${call.name}; allowed=$allowedDeviceAccess; path=$externalFilePathNeedingPermission');
      if (!allowedDeviceAccess) return false;
      allowDeviceFileAccess = true;
      await saveProjectPermissions();
    }
    if (taskLooksLikeWebResearchTask() &&
        taskInternetActions > 0 &&
        const {
          'run_command',
          'run_tests',
          'write_file',
          'create_file',
          'append_file',
          'replace_text',
          'make_dir',
          'delete_path',
          'download_to_project'
        }.contains(call.name)) {
      log('PERMISSION BLOCKED: ${call.name}; web research task must not compile or mutate project after search');
      return false;
    }
    if (permissionMode == PermissionMode.fullAccess || readOnly) {
      log('PERMISSION AUTO-ALLOW: ${call.name}; mode=${permissionMode.name}; reason=$reason');
      return true;
    }
    if (permissionMode == PermissionMode.askCriticalOnly && !critical) {
      log('PERMISSION AUTO-ALLOW NON-CRITICAL: ${call.name}; reason=$reason');
      return true;
    }
    final approver = permissionApprover;
    if (approver == null) {
      log('PERMISSION BLOCKED: ${call.name}; no UI approver is attached; mode=${permissionMode.name}');
      return false;
    }
    final allowed = await approver(AgentPermissionRequest(
      toolName: call.name,
      details: describeToolCall(call),
      reason: reason,
      critical: critical,
    ));
    log('PERMISSION USER DECISION: ${call.name}; allowed=$allowed; mode=${permissionMode.name}');
    logAction('permission_decision', {
      'tool': call.name,
      'allowed': allowed,
      'mode': permissionMode.name,
      'critical': critical
    });
    return allowed;
  }

  Future<String> executeTool(ToolCall call) async {
    taskToolActions++;
    if (call.name == 'web_research') {
      taskInternetActions += 3;
    } else if (const {'duckduckgo_search', 'web_fetch', 'web_deep_fetch'}
        .contains(call.name)) {
      taskInternetActions++;
    }
    final allowed = await checkToolPermission(call);
    if (!allowed) {
      final denied = 'Permission denied for tool: ${call.name}';
      log('PERMISSION DENIED: ${call.name} args=${truncateMiddle(jsonEncode(call.args), 4000)}');
      logAction('permission_denied', {'tool': call.name, 'args': call.args});
      lastToolName = call.name;
      lastToolResultText = denied;
      return denied;
    }
    logAction('tool_start', {
      'tool': call.name,
      'args': sanitizeToolArgsForLog(call.name, call.args)
    });
    try {
      final result = await executeToolAllowed(call);
      lastToolName = call.name;
      lastToolResultText = result;
      logAction('tool_finish',
          {'tool': call.name, 'result': truncateMiddle(result, 8000)});
      return result;
    } catch (error, stack) {
      log('TOOL ERROR ${call.name}: $error\n$stack');
      logAction('tool_error', {'tool': call.name, 'error': error.toString()});
      final failed = 'Tool ${call.name} failed: $error';
      lastToolName = call.name;
      lastToolResultText = failed;
      return failed;
    }
  }

  bool lastToolResultCompletesReadOnlyTask() {
    if (lastToolResultText.trim().isEmpty) return false;
    if (lastToolName == 'read_device_folder_texts') {
      return lastToolResultText.startsWith('DEVICE_FOLDER_TEXTS:') &&
          !lastToolResultText.contains('DEVICE_FILE_ACCESS_DENIED') &&
          !lastToolResultText.contains('Directory not found');
    }
    if (const {'read_device_text_file', 'list_device_directory'}
        .contains(lastToolName)) {
      return !lastToolResultText.contains('DENIED') &&
          !lastToolResultText.contains('not found');
    }
    if (const {
      'search_device_documents',
      'read_document_structure',
      'filesystem_search'
    }.contains(lastToolName)) {
      return !lastToolResultText.contains('DENIED') &&
          !lastToolResultText.contains('FAILED') &&
          !lastToolResultText.contains('not found');
    }
    if (lastToolName == 'archive_device_children') {
      return lastToolResultText.startsWith('ARCHIVE_DEVICE_CHILDREN_DONE:') &&
          !lastToolResultText.contains('ARCHIVE_DEVICE_CHILDREN_FAILED');
    }
    if (lastToolName == 'web_research' && taskLooksLikeWebResearchTask())
      return true;
    return false;
  }

  String buildReadOnlyToolFinalText() {
    final text = lastToolResultText.trim();
    if (text.isEmpty) return buildFinalSummaryText();
    if (lastToolName == 'web_research') {
      final summary = buildWebResearchFinalAnswer(text);
      return allowFollowUpSuggestions
          ? addFollowUpSuggestions(summary)
          : summary;
    }
    final capped = truncateMiddle(text, 120000);
    if (!allowFollowUpSuggestions) return capped;
    return addFollowUpSuggestions(capped);
  }

  String buildWebResearchFinalAnswer(String raw) {
    final buffer = StringBuffer();
    buffer.writeln(
        'Результат интернет-поиска по запросу: ${activeTaskText.trim()}');
    buffer.writeln();
    final confirmed = extractSectionLines(raw, 'CONFIRMED_OR_RELEVANT_SOURCES')
        .where((l) => l.contains('http'))
        .toList();
    final rejected =
        extractSectionLines(raw, 'REJECTED_SIMILAR_OR_UNCONFIRMED_SOURCES')
            .where((l) => l.contains('http'))
            .toList();
    final images = extractSectionLines(raw, 'RELEVANT_IMAGES')
        .where((l) => l.contains('http'))
        .toList();
    final exact = RegExp(r'EXACT_NAME_CHECK[\s\S]*?(?=\n\n|$)')
        .firstMatch(raw)
        ?.group(0)
        ?.trim();
    if (exact != null && exact.isNotEmpty) {
      buffer.writeln('**Проверка точного совпадения:**');
      buffer.writeln(exact.replaceFirst('EXACT_NAME_CHECK', '').trim());
      buffer.writeln();
    }
    if (confirmed.isNotEmpty) {
      buffer.writeln('**Подтверждённые или релевантные источники:**');
      for (final line in dedupeLines(confirmed).take(12))
        buffer.writeln('- $line');
      buffer.writeln();
    } else {
      buffer.writeln(
          '**Точного подтверждённого источника не найдено.** По найденным страницам нельзя безопасно составлять биографию без риска смешать с однофамильцами или похожими специалистами.');
      buffer.writeln();
    }
    if (images.isNotEmpty) {
      buffer.writeln('**Найденные изображения/фото, относящиеся к запросу:**');
      for (final line in dedupeLines(images).take(8)) buffer.writeln('- $line');
      buffer.writeln();
    }
    if (rejected.isNotEmpty) {
      buffer.writeln('**Отсеянные похожие совпадения:**');
      for (final line in dedupeLines(rejected).take(12))
        buffer.writeln('- $line');
      buffer.writeln();
    }
    buffer.writeln('**Краткий вывод:**');
    if (confirmed.isEmpty) {
      buffer.writeln(
          'Найдены похожие результаты, но точная информация по запрошенному человеку не подтверждена содержимым открытых страниц.');
    } else {
      buffer.writeln(
          'Используй только подтверждённые ссылки выше; похожие совпадения не являются источниками по запрошенному человеку.');
    }
    return buffer.toString().trim();
  }

  List<String> dedupeLines(List<String> lines) {
    final seen = <String>{};
    final out = <String>[];
    for (final l in lines) {
      final key = l.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
      if (seen.add(key)) out.add(l);
    }
    return out;
  }

  bool commandOutputHasSuccessfulExit(String output) {
    final matches = RegExp(r'EXIT_CODE:\s*(-?\d+)', caseSensitive: false)
        .allMatches(output)
        .toList();
    if (matches.isEmpty) return false;
    final last = int.tryParse(matches.last.group(1) ?? '');
    return last == 0;
  }

  String buildFallbackSuccessResult(
      {required String original, required String fallback}) {
    return '''FINAL_STATUS: SUCCESS
Original command failed, but automatic tools-aware fallback succeeded. Treat the task as checked unless the user requested a different command.

[ORIGINAL_FAILED]
$original
[/ORIGINAL_FAILED]

[AUTO_BUILD_FALLBACK_SUCCESS]
$fallback
[/AUTO_BUILD_FALLBACK_SUCCESS]''';
  }

  Future<String> executeToolAllowed(ToolCall call) async {
    switch (call.name) {
      case 'project_map':
        return projectMap(call.args['path']?.toString() ?? '.');
      case 'list_local_tools':
        return localToolsCompactSummary(
            purpose: call.args['purpose']?.toString() ?? 'all', maxItems: 80);
      case 'set_task_plan':
        return setTaskPlan(call.args['plan']?.toString() ?? '');
      case 'rebuild_device_index':
        return await rebuildDeviceIndex();
      case 'search_device_index':
        return searchDeviceIndex(call.args['query']?.toString() ?? '',
            maxResults:
                int.tryParse(call.args['max_results']?.toString() ?? '') ?? 20);
      case 'recognize_image_text':
        return await recognizeImageText(call.args['path']?.toString() ?? '');
      case 'run_custom_tool':
        return await runCustomTool(call.args['name']?.toString() ?? '',
            call.args['input']?.toString() ?? '');
      case 'duckduckgo_search':
        return duckDuckGoSearch(call.args['query']?.toString() ?? '',
            maxResults:
                int.tryParse(call.args['max_results']?.toString() ?? '') ?? 8);
      case 'web_fetch':
        return webFetch(call.args['url']?.toString() ?? '',
            maxChars: int.tryParse(call.args['max_chars']?.toString() ?? '') ??
                20000);
      case 'web_deep_fetch':
        return webDeepFetch(call.args['url']?.toString() ?? '',
            maxPages:
                int.tryParse(call.args['max_pages']?.toString() ?? '') ?? 4,
            depth: int.tryParse(call.args['depth']?.toString() ?? '') ?? 1,
            maxChars: int.tryParse(call.args['max_chars']?.toString() ?? '') ??
                50000);
      case 'web_research':
        return webResearch(call.args['query']?.toString() ?? '',
            maxPages:
                int.tryParse(call.args['max_pages']?.toString() ?? '') ?? 10,
            maxDepth:
                int.tryParse(call.args['max_depth']?.toString() ?? '') ?? 2,
            maxChars: int.tryParse(call.args['max_chars']?.toString() ?? '') ??
                90000);
      case 'filesystem_search':
        return filesystemSearch(call.args['query']?.toString() ?? '',
            rootPath: call.args['root']?.toString() ?? '',
            maxResults:
                int.tryParse(call.args['max_results']?.toString() ?? '') ?? 40);
      case 'list_device_directory':
        return listDeviceDirectory(call.args['path']?.toString() ?? '',
            recursive:
                parseBoolString(call.args['recursive']?.toString() ?? ''),
            maxResults:
                int.tryParse(call.args['max_results']?.toString() ?? '') ??
                    200);
      case 'read_device_text_file':
        return await readDeviceTextFile(call.args['path']?.toString() ?? '',
            maxChars: int.tryParse(call.args['max_chars']?.toString() ?? '') ??
                30000);
      case 'read_device_folder_texts':
        return await readDeviceFolderTexts(call.args['path']?.toString() ?? '',
            maxFiles:
                int.tryParse(call.args['max_files']?.toString() ?? '') ?? 30,
            maxCharsPerFile: int.tryParse(
                    call.args['max_chars_per_file']?.toString() ?? '') ??
                12000,
            recursive:
                parseBoolString(call.args['recursive']?.toString() ?? 'true'));
      case 'search_device_documents':
        return await searchDeviceDocuments(call.args['path']?.toString() ?? '',
            call.args['query']?.toString() ?? activeTaskText,
            maxFiles:
                int.tryParse(call.args['max_files']?.toString() ?? '') ?? 120,
            maxCharsPerFile: int.tryParse(
                    call.args['max_chars_per_file']?.toString() ?? '') ??
                60000,
            recursive:
                parseBoolString(call.args['recursive']?.toString() ?? 'true'));
      case 'read_document_structure':
        return await readDocumentStructure(call.args['path']?.toString() ?? '',
            maxChars: int.tryParse(call.args['max_chars']?.toString() ?? '') ??
                30000);
      case 'create_document_from_text':
        return await createDocumentFromText(call.args['path']?.toString() ?? '',
            call.args['text']?.toString() ?? '');
      case 'edit_document_text':
        return await editDocumentText(call.args['path']?.toString() ?? '',
            mode: call.args['mode']?.toString() ?? 'replace_text',
            text: call.args['text']?.toString() ?? '',
            oldText: call.args['old_text']?.toString() ?? '');
      case 'archive_device_children':
        return await archiveDeviceChildren(call.args['path']?.toString() ?? '',
            outputPath: call.args['output']?.toString() ?? '',
            maxItems:
                int.tryParse(call.args['max_items']?.toString() ?? '') ?? 200);
      case 'knowledge_search':
        return knowledgeSearch(call.args['query']?.toString() ?? '',
            maxResults:
                int.tryParse(call.args['max_results']?.toString() ?? '') ?? 8);
      case 'knowledge_store':
        return knowledgeStore(call.args['topic']?.toString() ?? '',
            call.args['content']?.toString() ?? '',
            source: call.args['source']?.toString() ?? '',
            tags: call.args['tags']?.toString() ?? '');
      case 'email_list_accounts':
        return emailAccountsSummary(includePasswords: false);
      case 'email_draft_smtp':
        return emailDraftSmtp(
            call.args['account_id']?.toString() ?? '',
            call.args['to']?.toString() ?? '',
            call.args['subject']?.toString() ?? '',
            call.args['body']?.toString() ?? '');
      case 'download_to_project':
        return downloadToProject(call.args['url']?.toString() ?? '',
            call.args['path']?.toString() ?? '');
      case 'download_to_tools':
        return downloadToTools(call.args['url']?.toString() ?? '',
            call.args['path']?.toString() ?? '');
      case 'extract_zip_to_tools':
        return extractZipToTools(call.args['path']?.toString() ?? '',
            call.args['dest']?.toString() ?? 'downloads/extracted');
      case 'remember_solution':
        return rememberSolution(
            call.args['problem']?.toString() ?? '',
            call.args['solution']?.toString() ?? '',
            call.args['tags']?.toString() ?? '');
      case 'list_files':
        return listFiles(call.args['path']?.toString() ?? '.');
      case 'read_file':
        return readRelativeFile(call.args['path']?.toString() ?? '');
      case 'write_file':
      case 'create_file':
        {
          final path = call.args['path']?.toString() ?? '';
          final content = call.args['content']?.toString() ?? '';
          if (isPlaceholderToolContent(content))
            return placeholderContentBlockedMessage(path, content);
          return writeRelativeFile(path, content);
        }
      case 'append_file':
        {
          final path = call.args['path']?.toString() ?? '';
          final content = call.args['content']?.toString() ?? '';
          if (isPlaceholderToolContent(content))
            return placeholderContentBlockedMessage(path, content);
          return appendRelativeFile(path, content);
        }
      case 'replace_text':
        {
          final path = call.args['path']?.toString() ?? '';
          final oldText = call.args['old_text']?.toString() ?? '';
          final newText = call.args['new_text']?.toString() ?? '';
          if (isPlaceholderToolContent(newText))
            return placeholderContentBlockedMessage(path, newText);
          return replaceTextInFile(
              path, oldText, newText, call.args['all'] == true);
        }
      case 'make_dir':
        return makeRelativeDir(call.args['path']?.toString() ?? '');
      case 'delete_path':
        return deleteRelativePath(call.args['path']?.toString() ?? '',
            recursive: call.args['recursive'] == true);
      case 'copy_path':
        return copyRelativePath(call.args['from']?.toString() ?? '',
            call.args['to']?.toString() ?? '',
            move: false);
      case 'move_path':
        return copyRelativePath(call.args['from']?.toString() ?? '',
            call.args['to']?.toString() ?? '',
            move: true);
      case 'run_command':
        final command = call.args['command']?.toString() ?? '';
        final cwd = call.args['cwd']?.toString() ?? '';
        final result = await runCommand(command, relativeWorkingDirectory: cwd);
        if (taskLooksLikeCppTask() &&
            isCompilerOrBuildCommand(command) &&
            (isEnvironmentProblemOutput(result) ||
                isBuildConfigurationProblemOutput(result))) {
          log('RUN COMMAND AUTO-FALLBACK: compiler/build command failed; trying tools-aware run_tests with local tools priority.');
          final fallback = await runDefaultTests(relativeWorkingDirectory: cwd);
          if (commandOutputHasSuccessfulExit(fallback)) {
            lastCommandExitCode = 0;
            lastCommandResultText = buildFallbackSuccessResult(
                original: result, fallback: fallback);
            return lastCommandResultText;
          }
          return '$result\n\n[AUTO_BUILD_FALLBACK]\n$fallback';
        }
        return result;
      case 'run_tests':
        final command = call.args['command']?.toString().trim() ?? '';
        final cwd = call.args['cwd']?.toString() ?? '';
        if (command.isNotEmpty)
          return runCommand(command, relativeWorkingDirectory: cwd);
        return runDefaultTests(relativeWorkingDirectory: cwd);
      case 'inspect_zip':
        return inspectZip(call.args['path']?.toString() ?? '');
      case 'extract_zip':
        return extractZip(call.args['path']?.toString() ?? '',
            call.args['dest']?.toString() ?? 'extracted');
      case 'read_docx_text':
        return readDocumentStructure(call.args['path']?.toString() ?? '',
            maxChars: 24000);
      case 'read_xlsx_text':
        return readDocumentStructure(call.args['path']?.toString() ?? '',
            maxChars: 24000);
      default:
        return 'Unknown tool: ${call.name}';
    }
  }

  String projectMap(String relativePath) {
    final root = currentProject;
    if (root == null) return 'No project';
    if (isAgentInternalRelativePath(relativePath))
      return reservedAgentPathMessage(relativePath, action: 'project_map');
    final dir = Directory(resolveProjectPath(root.path, relativePath));
    if (!dir.existsSync()) return 'Directory not found: $relativePath';
    final buffer = StringBuffer();
    var count = 0;
    for (final entry in dir.listSync(recursive: true)) {
      final rel = pathRelative(root.path, entry.path).replaceAll('\\', '/');
      final lower = rel.toLowerCase();
      if (lower == '.cppagent' || lower.startsWith('.cppagent/')) continue;
      if (count++ >= 600) {
        buffer.writeln('...[truncated]...');
        break;
      }
      buffer.writeln('${entry is Directory ? '[D]' : '[F]'} $rel');
    }
    return buffer.toString();
  }

  String listFiles(String relativePath) {
    final root = currentProject;
    if (root == null) return 'No project';
    if (isAgentInternalRelativePath(relativePath))
      return reservedAgentPathMessage(relativePath, action: 'list_files');
    final dir = Directory(resolveProjectPath(root.path, relativePath));
    if (!dir.existsSync()) return 'Directory not found: $relativePath';
    final buffer = StringBuffer();
    final entries = dir.listSync(recursive: false)
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final entry in entries) {
      final name = pathBasename(entry.path);
      if (name == '.cppagent') continue;
      buffer.writeln('${entry is Directory ? '[D]' : '[F]'} $name');
    }
    return buffer.toString();
  }

  String normalizeRelativePathForPolicy(String relativePath) {
    return relativePath
        .trim()
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+'), '/')
        .replaceFirst(RegExp(r'^\./'), '')
        .toLowerCase();
  }

  bool isAgentInternalRelativePath(String relativePath) {
    final normalized = normalizeRelativePathForPolicy(relativePath);
    return normalized == '.cppagent' || normalized.startsWith('.cppagent/');
  }

  bool isWritingToAgentInternalPath(String relativePath) =>
      isAgentInternalRelativePath(relativePath);

  String reservedAgentPathMessage(String relativePath,
      {required String action}) {
    return '''RESERVED_AGENT_PATH_BLOCKED: `$relativePath` is inside `.cppagent`.
`.cppagent` is reserved for the agent internals only: logs, task_plan.md, sessions, solution memory helpers, temporary files and `.cppagent/python_venv`.
Do not create or modify user source code, CMakeLists.txt, README, tests, assets or project data inside `.cppagent`.
Use the project root or normal folders such as `src/`, `include/`, `tests/`, `data/`, `assets/`, `build_scripts/`.
For C++ use `CMakeLists.txt` in the project root or in a normal project subfolder, and source files such as `src/main.cpp` or `main.cpp`.
Action `$action` was not executed.''';
  }

  String readRelativeFile(String relativePath) {
    final root = currentProject;
    if (root == null) return 'No project';
    if (relativePath.isEmpty) return 'path is required';
    final file = File(resolveProjectPath(root.path, relativePath));
    if (!file.existsSync()) return 'File not found: $relativePath';
    return truncateMiddle(
        file.readAsStringSync(encoding: const Utf8Codec(allowMalformed: true)),
        24000);
  }

  Future<String?> readRelativeFileForEditor(String relativePath) async {
    final root = currentProject;
    if (root == null) return null;
    final path = resolveProjectPath(root.path, relativePath);
    final file = File(path);
    if (!await file.exists()) return null;
    if (!isSupportedReadableDocumentPath(path)) return null;
    final text = await readDeviceDocumentText(path, maxChars: 1200000);
    return text.trim().isEmpty ? '(текст не извлечён или файл пуст)' : text;
  }

  List<FileChangeSummary> takePendingFileChanges() {
    final changes = List<FileChangeSummary>.from(pendingFileChanges);
    pendingFileChanges.clear();
    return changes;
  }

  List<FileChangeSummary> takeTaskFileChanges() {
    final changes = <FileChangeSummary>[
      ...taskFileChanges,
      ...pendingFileChanges
    ];
    taskFileChanges.clear();
    pendingFileChanges.clear();
    return changes;
  }

  void recordFileChange(String relativePath, String before, String after) {
    final oldLines = before.isEmpty
        ? <String>[]
        : before.replaceAll('\r\n', '\n').split('\n');
    final newLines =
        after.isEmpty ? <String>[] : after.replaceAll('\r\n', '\n').split('\n');
    var prefix = 0;
    while (prefix < oldLines.length &&
        prefix < newLines.length &&
        oldLines[prefix] == newLines[prefix]) {
      prefix++;
    }
    var oldSuffix = oldLines.length - 1;
    var newSuffix = newLines.length - 1;
    while (oldSuffix >= prefix &&
        newSuffix >= prefix &&
        oldLines[oldSuffix] == newLines[newSuffix]) {
      oldSuffix--;
      newSuffix--;
    }
    final removed = oldSuffix >= prefix
        ? oldLines.sublist(prefix, oldSuffix + 1)
        : <String>[];
    final added = newSuffix >= prefix
        ? newLines.sublist(prefix, newSuffix + 1)
        : <String>[];
    final buffer = StringBuffer();
    if (prefix > 0) buffer.writeln('@@ unchanged first $prefix lines @@');
    for (final line in removed.take(400)) {
      buffer.writeln('- $line');
    }
    if (removed.length > 400)
      buffer.writeln('- ... ${removed.length - 400} more removed lines');
    for (final line in added.take(400)) {
      buffer.writeln('+ $line');
    }
    if (added.length > 400)
      buffer.writeln('+ ... ${added.length - 400} more added lines');
    final unchangedTail = oldLines.length - oldSuffix - 1;
    if (unchangedTail > 0)
      buffer.writeln('@@ unchanged last $unchangedTail lines @@');
    pendingFileChanges.add(FileChangeSummary(
      path: relativePath,
      addedLines: added.length,
      removedLines: removed.length,
      diff: buffer.toString().trimRight(),
    ));
  }

  Future<String> writeRelativeFile(String relativePath, String content) async {
    final root = currentProject;
    if (root == null) return 'No project';
    if (relativePath.isEmpty) return 'path is required';
    if (isWritingToAgentInternalPath(relativePath)) {
      final blocked =
          reservedAgentPathMessage(relativePath, action: 'write_file');
      log(blocked);
      logAction('reserved_agent_path_blocked',
          {'tool': 'write_file', 'path': relativePath});
      return blocked;
    }
    final file = File(resolveProjectPath(root.path, relativePath));
    final existed = await file.exists();
    final before = existed
        ? await file.readAsString(
            encoding: const Utf8Codec(allowMalformed: true))
        : '';
    if (existed &&
        before.trim().isNotEmpty &&
        isEnvironmentProblemOutput(lastCommandResultText)) {
      final blocked =
          'WRITE BLOCKED: last command failed because a compiler/tool is missing from the environment, not because this source file is wrong. The agent must not overwrite $relativePath after an environment error. Try run_tests/another compiler or report the missing tool.';
      log(blocked);
      logAction('file_write_blocked_environment_error', {
        'path': relativePath,
        'last_command': lastCommandText,
        'last_output': truncateMiddle(lastCommandResultText, 4000)
      });
      return blocked;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(content, encoding: utf8);
    recordFileChange(relativePath, before, content);
    taskFileMutations++;
    log('FILE WRITE: $relativePath existed=$existed old=${before.length} chars new=${content.length} chars\nOLD_CONTENT:\n${truncateMiddle(before, 5000)}\nNEW_CONTENT:\n${truncateMiddle(content, 5000)}');
    logAction('file_write', {
      'path': relativePath,
      'existed': existed,
      'old_chars': before.length,
      'new_chars': content.length,
      'old_preview': truncateMiddle(before, 4000),
      'new_preview': truncateMiddle(content, 4000)
    });
    return '${existed ? 'Wrote' : 'Created'} file: $relativePath (${content.length} chars)';
  }

  Future<String> appendRelativeFile(String relativePath, String content) async {
    final root = currentProject;
    if (root == null) return 'No project';
    if (relativePath.isEmpty) return 'path is required';
    if (isWritingToAgentInternalPath(relativePath)) {
      final blocked =
          reservedAgentPathMessage(relativePath, action: 'append_file');
      log(blocked);
      logAction('reserved_agent_path_blocked',
          {'tool': 'append_file', 'path': relativePath});
      return blocked;
    }
    final file = File(resolveProjectPath(root.path, relativePath));
    final before = (await file.exists())
        ? await file.readAsString(
            encoding: const Utf8Codec(allowMalformed: true))
        : '';
    await file.parent.create(recursive: true);
    await file.writeAsString(content, mode: FileMode.append, encoding: utf8);
    final after = before + content;
    recordFileChange(relativePath, before, after);
    taskFileMutations++;
    log('FILE APPEND: $relativePath appended=${content.length} chars\nCONTENT_APPEND:\n${truncateMiddle(content, 5000)}');
    logAction('file_append', {
      'path': relativePath,
      'chars': content.length,
      'content_preview': truncateMiddle(content, 4000)
    });
    return 'Appended file: $relativePath (${content.length} chars)';
  }

  Future<String> replaceTextInFile(
      String relativePath, String oldText, String newText, bool all) async {
    final root = currentProject;
    if (root == null) return 'No project';
    if (relativePath.isEmpty) return 'path is required';
    if (isWritingToAgentInternalPath(relativePath)) {
      final blocked =
          reservedAgentPathMessage(relativePath, action: 'replace_text');
      log(blocked);
      logAction('reserved_agent_path_blocked',
          {'tool': 'replace_text', 'path': relativePath});
      return blocked;
    }
    if (oldText.isEmpty) return 'old_text is required';
    final file = File(resolveProjectPath(root.path, relativePath));
    if (!await file.exists()) return 'File not found: $relativePath';
    final before = await file.readAsString(
        encoding: const Utf8Codec(allowMalformed: true));
    final after = all
        ? before.replaceAll(oldText, newText)
        : before.replaceFirst(oldText, newText);
    if (before == after) return 'Text not found in $relativePath';
    await file.writeAsString(after, encoding: utf8);
    recordFileChange(relativePath, before, after);
    taskFileMutations++;
    log('FILE REPLACE: $relativePath old=${oldText.length} chars new=${newText.length} chars all=$all\nOLD:\n${truncateMiddle(oldText, 3000)}\nNEW:\n${truncateMiddle(newText, 3000)}');
    logAction('file_replace', {
      'path': relativePath,
      'old_chars': oldText.length,
      'new_chars': newText.length,
      'all': all,
      'old_preview': truncateMiddle(oldText, 3000),
      'new_preview': truncateMiddle(newText, 3000)
    });
    return 'Replaced text in: $relativePath';
  }

  Future<String> deleteRelativePath(String relativePath,
      {required bool recursive}) async {
    final root = currentProject;
    if (root == null) return 'No project';
    if (relativePath.isEmpty) return 'path is required';
    if (isAgentInternalRelativePath(relativePath)) {
      final blocked =
          reservedAgentPathMessage(relativePath, action: 'delete_path');
      log(blocked);
      logAction('reserved_agent_path_blocked',
          {'tool': 'delete_path', 'path': relativePath});
      return blocked;
    }
    final path = resolveProjectPath(root.path, relativePath);
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound)
      return 'Path not found: $relativePath';
    final before = type == FileSystemEntityType.file
        ? await File(path)
            .readAsString(encoding: const Utf8Codec(allowMalformed: true))
        : '';
    log('DELETE PATH: $relativePath recursive=$recursive');
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: recursive);
    } else {
      await File(path).delete();
    }
    if (type == FileSystemEntityType.file)
      recordFileChange(relativePath, before, '');
    taskFileMutations++;
    logAction('path_delete', {
      'path': relativePath,
      'recursive': recursive,
      'type': type.toString()
    });
    return 'Deleted: $relativePath';
  }

  Future<String> copyRelativePath(String from, String to,
      {required bool move}) async {
    final root = currentProject;
    if (root == null) return 'No project';
    if (from.isEmpty || to.isEmpty) return 'from and to are required';
    if (isWritingToAgentInternalPath(to) ||
        (move && isAgentInternalRelativePath(from))) {
      final blocked = reservedAgentPathMessage(
          isWritingToAgentInternalPath(to) ? to : from,
          action: move ? 'move_path' : 'copy_path');
      log(blocked);
      logAction('reserved_agent_path_blocked',
          {'tool': move ? 'move_path' : 'copy_path', 'from': from, 'to': to});
      return blocked;
    }
    final src = resolveProjectPath(root.path, from);
    final dst = resolveProjectPath(root.path, to);
    final type = FileSystemEntity.typeSync(src);
    if (type == FileSystemEntityType.notFound) return 'Path not found: $from';
    log('${move ? 'MOVE' : 'COPY'} PATH: $from -> $to');
    if (type == FileSystemEntityType.directory) {
      await copyDirectory(Directory(src), Directory(dst));
      if (move) await Directory(src).delete(recursive: true);
    } else {
      await File(dst).parent.create(recursive: true);
      await File(src).copy(dst);
      if (move) await File(src).delete();
    }
    taskFileMutations++;
    logAction(move ? 'path_move' : 'path_copy',
        {'from': from, 'to': to, 'type': type.toString()});
    return '${move ? 'Moved' : 'Copied'}: $from -> $to';
  }

  String get hostOsSegment {
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isAndroid) return 'android';
    return Platform.operatingSystem;
  }

  String get hostArchSegment {
    final env = Platform.environment;
    final raw = (env['PROCESSOR_ARCHITEW6432'] ??
            env['PROCESSOR_ARCHITECTURE'] ??
            env['HOSTTYPE'] ??
            env['MACHTYPE'] ??
            '')
        .toLowerCase();
    if (raw.contains('arm64') || raw.contains('aarch64')) return 'arm64';
    if (raw.contains('amd64') || raw.contains('x86_64') || raw.contains('x64'))
      return 'x64';
    if (raw.contains('86')) return 'x86';
    return Platform.isWindows ? 'x64' : 'unknown';
  }

  String hostEnvironmentSummary() {
    return 'OS: ${Platform.operatingSystem}; arch: $hostArchSegment; platform folder: tools/$hostOsSegment/$hostArchSegment; app root: $appRootPath; project root: ${currentProject?.path ?? ''}';
  }

  List<String> toolSearchRootPaths() {
    final root = toolsRoot.path;
    final os = hostOsSegment;
    final arch = hostArchSegment;
    final candidates = <String>[
      pathJoin(root, os, arch),
      pathJoin(root, os),
      pathJoin(root, 'common', arch),
      pathJoin(root, 'common'),
      root,
      pathJoin(appRootPath, 'tooling', 'tools', os, arch),
      pathJoin(appRootPath, 'tooling', 'tools', os),
    ];
    final seen = <String>{};
    return candidates
        .where((path) => seen.add(path) && Directory(path).existsSync())
        .toList(growable: false);
  }

  bool isToolExecutableFile(String path) {
    final lower = pathBasename(path).toLowerCase();
    if (Platform.isWindows)
      return lower.endsWith('.exe') ||
          lower.endsWith('.bat') ||
          lower.endsWith('.cmd') ||
          lower.endsWith('.ps1') ||
          lower.endsWith('.com');
    return !lower.contains('.') ||
        lower.endsWith('.sh') ||
        lower.endsWith('.py');
  }

  List<LocalToolInfo> scanLocalToolsSync({int maxItems = 300}) {
    final now = DateTime.now();
    final cached = cachedLocalTools;
    if (cached != null &&
        cachedLocalToolsAt != null &&
        now.difference(cachedLocalToolsAt!).inSeconds < 30 &&
        cached.length >= maxItems) {
      return cached.take(maxItems).toList(growable: false);
    }
    final result = <LocalToolInfo>[];
    final seen = <String>{};
    for (final rootPath in toolSearchRootPaths()) {
      try {
        var scanned = 0;
        for (final entity in Directory(rootPath)
            .listSync(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          if (++scanned > 5000) break;
          if (!isToolExecutableFile(entity.path)) continue;
          final key = entity.path.toLowerCase();
          if (!seen.add(key)) continue;
          result.add(LocalToolInfo(
              path: entity.path,
              relativePath: pathRelative(appRootPath, entity.path),
              name: pathBasename(entity.path),
              kind: classifyLocalTool(entity.path)));
          if (result.length >= maxItems) break;
        }
      } catch (error) {
        log('TOOLS SCAN ERROR: root=$rootPath error=$error');
      }
      if (result.length >= maxItems) break;
    }
    int priority(LocalToolInfo item) {
      final kind = item.kind;
      if (kind == 'cpp_compiler') return 0;
      if (kind == 'build_tool') return 1;
      if (kind == 'python') return 2;
      if (kind == 'runtime') return 3;
      return 9;
    }

    result.sort((a, b) {
      final p = priority(a).compareTo(priority(b));
      if (p != 0) return p;
      return a.relativePath
          .toLowerCase()
          .compareTo(b.relativePath.toLowerCase());
    });
    if (result.length >= maxItems) {
      cachedLocalTools = List<LocalToolInfo>.from(result);
      cachedLocalToolsAt = DateTime.now();
    }
    return result;
  }

  String classifyLocalTool(String path) {
    final name = pathBasename(path).toLowerCase();
    if ([
      'g++.exe',
      'g++',
      'clang++.exe',
      'clang++',
      'cl.exe',
      'cl',
      'gcc.exe',
      'gcc'
    ].contains(name)) return 'cpp_compiler';
    if ([
      'cmake.exe',
      'cmake',
      'ninja.exe',
      'ninja',
      'make.exe',
      'make',
      'msbuild.exe',
      'msbuild'
    ].contains(name)) return 'build_tool';
    if (['python.exe', 'python3.exe', 'python', 'python3', 'pip.exe', 'pip']
        .contains(name)) return 'python';
    if (['node.exe', 'node', 'npm.cmd', 'npm.exe', 'npm', 'java.exe', 'java']
        .contains(name)) return 'runtime';
    if (name.contains('7z') || name.contains('zip')) return 'archive';
    return 'program';
  }

  String localToolsCompactSummary({String purpose = 'all', int maxItems = 80}) {
    // Сканируем шире, а в prompt выводим только компактную выжимку.
    // Иначе при maxItems=12 можно случайно не увидеть g++/python, если они глубже в папке tools.
    final tools = scanLocalToolsSync(maxItems: maxItems + 80);
    if (tools.isEmpty) {
      return 'Папка tools есть, но подходящих исполняемых программ не найдено. Ожидаемые пути, например: tools/$hostOsSegment/$hostArchSegment/g++.exe, tools/$hostOsSegment/$hostArchSegment/python/python.exe, tools/$hostOsSegment/$hostArchSegment/cmake.exe.';
    }
    final p = purpose.toLowerCase();
    Iterable<LocalToolInfo> filtered = tools;
    if (p.contains('cpp') ||
        p.contains('c++') ||
        p.contains('compile') ||
        p.contains('build')) {
      filtered = tools.where((t) => const {
            'cpp_compiler',
            'build_tool',
            'python',
            'runtime'
          }.contains(t.kind));
    } else if (p.contains('python')) {
      filtered = tools.where((t) =>
          t.kind == 'python' ||
          t.name.toLowerCase().contains('python') ||
          t.name.toLowerCase().contains('pip'));
    }
    final selected = filtered.take(maxItems).toList(growable: false);
    final buffer = StringBuffer();
    buffer.writeln(
        'PATH priority: ${toolDirectoriesForPath().take(20).join(Platform.isWindows ? '; ' : ': ')}');
    for (final tool in selected) {
      buffer.writeln('- ${tool.name} [${tool.kind}] => ${tool.relativePath}');
    }
    final remaining = tools.length - selected.length;
    if (remaining > 0)
      buffer.writeln(
          '... ещё $remaining программ(ы), используй list_local_tools при необходимости.');
    return buffer.toString().trimRight();
  }

  List<String> toolDirectoriesForPath() {
    final dirs = <String>[];
    final seen = <String>{};
    for (final root in toolSearchRootPaths()) {
      if (seen.add(root)) dirs.add(root);
    }
    for (final tool in scanLocalToolsSync(maxItems: 500)) {
      final parent = File(tool.path).parent.path;
      if (seen.add(parent)) dirs.add(parent);
    }
    return dirs;
  }

  Map<String, String> buildToolAwareEnvironment() {
    final env = Map<String, String>.from(Platform.environment);
    final pathKey = env.keys
        .firstWhere((k) => k.toLowerCase() == 'path', orElse: () => 'PATH');
    final separator = Platform.isWindows ? ';' : ':';
    final prefix = toolDirectoriesForPath().join(separator);
    final current = env[pathKey] ?? '';
    if (prefix.isNotEmpty)
      env[pathKey] = current.isEmpty ? prefix : '$prefix$separator$current';
    env['AI_AGENT_OS'] = Platform.operatingSystem;
    env['AI_AGENT_ARCH'] = hostArchSegment;
    env['AI_AGENT_TOOLS_ROOT'] = toolsRoot.path;
    env['AI_AGENT_PROJECT_ROOT'] = currentProject?.path ?? '';
    return env;
  }

  LocalToolInfo? findToolExecutable(List<String> names) {
    final lowerNames = names.map((n) => n.toLowerCase()).toSet();
    for (final tool in scanLocalToolsSync(maxItems: 800)) {
      if (lowerNames.contains(tool.name.toLowerCase())) return tool;
    }
    return null;
  }

  String toolCommand(List<String> names) {
    final found = findToolExecutable(names);
    if (found != null) {
      // On Windows all tools directories are prepended to PATH. Prefer the bare
      // executable name instead of a quoted absolute path so cmd.exe does not
      // misread command chains as "\"N:\...\cmake.exe\"".
      if (Platform.isWindows) return found.name;
      return quoteShellArg(found.path);
    }
    return names.last;
  }

  String quoteShellArg(String value) {
    if (value.isEmpty) return value;
    if (Platform.isWindows) {
      final escaped = value.replaceAll('"', '\\"');
      return '"$escaped"';
    }
    final escaped = value.replaceAll("'", "'\\''");
    return "'$escaped'";
  }

  String projectPythonVenvRelativePath() =>
      pathJoin('.cppagent', 'python_venv');

  String projectPythonVenvPath() {
    final root = currentProject;
    if (root == null) return '';
    return pathJoin(root.path, projectPythonVenvRelativePath());
  }

  String projectPythonExecutablePath() {
    final venv = projectPythonVenvPath();
    if (venv.isEmpty) return '';
    return Platform.isWindows
        ? pathJoin(venv, 'Scripts', 'python.exe')
        : pathJoin(venv, 'bin', 'python');
  }

  bool projectPythonVenvExists() {
    final py = projectPythonExecutablePath();
    return py.isNotEmpty && File(py).existsSync();
  }

  String basePythonCommand() {
    if (Platform.isWindows)
      return toolCommand(['python.exe', 'python3.exe', 'python']);
    return toolCommand(['python3', 'python']);
  }

  String projectPythonCommand() {
    final py = projectPythonExecutablePath();
    if (py.isNotEmpty && File(py).existsSync()) return quoteShellArg(py);
    return basePythonCommand();
  }

  bool isPipInstallCommand(String command) {
    final lower = command.trim().toLowerCase();
    return RegExp(
            r'(^|&&|\|\||;)\s*(pip3?(\.exe)?|python(3)?(\.exe)?\s+-m\s+pip|py\s+-m\s+pip)\s+install\b',
            caseSensitive: false)
        .hasMatch(lower);
  }

  bool isPythonExecutionCommand(String command) {
    final lower = command.trim().toLowerCase();
    return RegExp(r'(^|&&|\|\||;)\s*(python3?(\.exe)?|py)\b',
                caseSensitive: false)
            .hasMatch(lower) ||
        RegExp(r'(^|&&|\|\||;)\s*(pytest|pip3?(\.exe)?)\b',
                caseSensitive: false)
            .hasMatch(lower);
  }

  String rewritePythonCommandForProjectVenv(String command) {
    final py = quoteShellArg(projectPythonExecutablePath());
    var out = command;
    out = out.replaceAllMapped(
        RegExp(r'(^|&&|\|\||;)\s*(python3?(\.exe)?|py)\s+-m\s+pip\s+install\b',
            caseSensitive: false),
        (m) => '${m.group(1) ?? ''} $py -m pip install');
    out = out.replaceAllMapped(
        RegExp(r'(^|&&|\|\||;)\s*pip3?(\.exe)?\s+install\b',
            caseSensitive: false),
        (m) => '${m.group(1) ?? ''} $py -m pip install');
    out = out.replaceAllMapped(
        RegExp(r'(^|&&|\|\||;)\s*pytest\b', caseSensitive: false),
        (m) => '${m.group(1) ?? ''} $py -m pytest');
    out = out.replaceAllMapped(
        RegExp(r'(^|&&|\|\||;)\s*(python3?(\.exe)?|py)\b(?!\s+-m\s+venv)',
            caseSensitive: false),
        (m) => '${m.group(1) ?? ''} $py');
    return out.trim();
  }

  Future<String> ensureProjectPythonVenv(
      {bool installRequirements = true}) async {
    final root = currentProject;
    if (root == null) return 'No project';
    final venvDir = projectPythonVenvPath();
    final venvPython = projectPythonExecutablePath();
    final notes = StringBuffer();
    await Directory(pathJoin(root.path, '.cppagent')).create(recursive: true);
    if (!File(venvPython).existsSync()) {
      final python = basePythonCommand();
      final createCommand = '$python -m venv ${quoteShellArg(venvDir)}';
      notes.writeln('CREATE_VENV: $createCommand');
      final created = await Process.run(
              Platform.isWindows ? 'cmd' : '/bin/sh',
              Platform.isWindows
                  ? ['/d', '/c', createCommand]
                  : ['-c', createCommand],
              workingDirectory: root.path,
              runInShell: false,
              stdoutEncoding: null,
              stderrEncoding: null,
              environment: buildToolAwareEnvironment())
          .timeout(const Duration(minutes: 5));
      notes.writeln('CREATE_VENV_EXIT_CODE: ${created.exitCode}');
      notes.writeln(
          '[CREATE_VENV_STDOUT]\n${decodeProcessOutput(created.stdout)}\n[/CREATE_VENV_STDOUT]');
      notes.writeln(
          '[CREATE_VENV_STDERR]\n${decodeProcessOutput(created.stderr)}\n[/CREATE_VENV_STDERR]');
      if (created.exitCode != 0 || !File(venvPython).existsSync())
        return notes.toString().trimRight();
    } else {
      notes.writeln('VENV_EXISTS: ${pathRelative(root.path, venvDir)}');
    }
    if (installRequirements) {
      final requirements = File(pathJoin(root.path, 'requirements.txt'));
      if (requirements.existsSync()) {
        final installCommand =
            '${quoteShellArg(venvPython)} -m pip install -r ${quoteShellArg('requirements.txt')}';
        notes.writeln('INSTALL_REQUIREMENTS: $installCommand');
        final installed = await Process.run(
                Platform.isWindows ? 'cmd' : '/bin/sh',
                Platform.isWindows
                    ? ['/d', '/c', installCommand]
                    : ['-c', installCommand],
                workingDirectory: root.path,
                runInShell: false,
                stdoutEncoding: null,
                stderrEncoding: null,
                environment: buildToolAwareEnvironment())
            .timeout(const Duration(minutes: 20));
        notes.writeln('INSTALL_REQUIREMENTS_EXIT_CODE: ${installed.exitCode}');
        notes.writeln(
            '[INSTALL_REQUIREMENTS_STDOUT]\n${decodeProcessOutput(installed.stdout)}\n[/INSTALL_REQUIREMENTS_STDOUT]');
        notes.writeln(
            '[INSTALL_REQUIREMENTS_STDERR]\n${decodeProcessOutput(installed.stderr)}\n[/INSTALL_REQUIREMENTS_STDERR]');
      }
    }
    return notes.toString().trimRight();
  }

  Future<String> installPythonPackagesInProjectVenv(
      List<String> packages) async {
    final root = currentProject;
    if (root == null) return 'No project';
    final notes = StringBuffer();
    notes.writeln(await ensureProjectPythonVenv(installRequirements: true));
    final venvPython = projectPythonExecutablePath();
    if (!File(venvPython).existsSync()) return notes.toString().trimRight();
    final clean = packages
        .map((p) => pythonModuleToPackageName(p))
        .where((p) => p.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (clean.isEmpty) return notes.toString().trimRight();
    final installCommand =
        '${quoteShellArg(venvPython)} -m pip install ${clean.map(quoteShellArg).join(' ')}';
    notes.writeln('INSTALL_MISSING_PACKAGES: $installCommand');
    final result = await Process.run(
            Platform.isWindows ? 'cmd' : '/bin/sh',
            Platform.isWindows
                ? ['/d', '/c', installCommand]
                : ['-c', installCommand],
            workingDirectory: root.path,
            runInShell: false,
            stdoutEncoding: null,
            stderrEncoding: null,
            environment: buildToolAwareEnvironment())
        .timeout(const Duration(minutes: 20));
    notes.writeln('INSTALL_MISSING_PACKAGES_EXIT_CODE: ${result.exitCode}');
    notes.writeln(
        '[INSTALL_MISSING_PACKAGES_STDOUT]\n${decodeProcessOutput(result.stdout)}\n[/INSTALL_MISSING_PACKAGES_STDOUT]');
    notes.writeln(
        '[INSTALL_MISSING_PACKAGES_STDERR]\n${decodeProcessOutput(result.stderr)}\n[/INSTALL_MISSING_PACKAGES_STDERR]');
    return notes.toString().trimRight();
  }

  Future<PreparedCommand> prepareCommandForPythonEnvironment(
      String command) async {
    final original = command.trim();
    if (original.isEmpty) return PreparedCommand(command: command, note: '');
    final pythonRelated = isPythonExecutionCommand(original);
    final pipInstall = isPipInstallCommand(original);
    if (!pythonRelated && !pipInstall)
      return PreparedCommand(command: command, note: '');
    final note = await ensureProjectPythonVenv(installRequirements: true);
    final rewritten = projectPythonVenvExists()
        ? rewritePythonCommandForProjectVenv(original)
        : original;
    final lines = StringBuffer();
    if (note.trim().isNotEmpty) lines.writeln(note.trimRight());
    if (rewritten != original)
      lines.writeln('REWRITTEN_FOR_PROJECT_VENV: $rewritten');
    lines.writeln(
        'PYTHON_POLICY: packages are installed only into project venv ${projectPythonVenvRelativePath()}, never into global Python.');
    return PreparedCommand(
        command: rewritten, note: lines.toString().trimRight());
  }

  Future<String> runDefaultTests({String relativeWorkingDirectory = ''}) async {
    final root = currentProject;
    if (root == null) return 'No project';
    final workRel = normalizeRelativeDirectory(relativeWorkingDirectory);
    final cppSource = primarySourceFile([
      '.cpp',
      '.cc',
      '.cxx'
    ], preferredNames: [
      'main.cpp',
      'object_recognition.cpp',
      'object_detector.cpp'
    ], baseRelativeDirectory: workRel);
    if (taskLooksLikeCppTask() && cppSource != null) {
      final directCompilerAvailable = findToolExecutable([
                'g++.exe',
                'g++',
                'clang++.exe',
                'clang++',
                'cl.exe',
                'cl'
              ]) !=
              null ||
          commandExistsInPath('g++') ||
          commandExistsInPath('clang++') ||
          commandExistsInPath('cl');
      if (directCompilerAvailable) {
        final command = defaultCppBuildCommand(cppSource);
        log('RUN_TESTS CPP DIRECT BUILD: $command');
        return runCommand(command, relativeWorkingDirectory: workRel);
      }
      final cmake = toolCommand(['cmake.exe', 'cmake']);
      if (commandLikelyAvailable(cmake)) {
        final cmakeNote = ensureCMakeListsForCppSource(cppSource,
            baseRelativeDirectory: workRel);
        if (cmakeNote.isNotEmpty) log('AUTO CMAKE PREPARE: $cmakeNote');
        final command = cmakeBuildAndRunCommand(cmake);
        return runCommand(command, relativeWorkingDirectory: workRel);
      }
      return runCommand(defaultCppBuildCommand(cppSource),
          relativeWorkingDirectory: workRel);
    }
    return runCommand(defaultTestCommand(relativeWorkingDirectory: workRel),
        relativeWorkingDirectory: workRel);
  }

  String normalizeRelativeDirectory(String value) {
    final trimmed = value.trim().replaceAll('\\', '/');
    if (trimmed.isEmpty || trimmed == '.') return '';
    final parts =
        trimmed.split('/').where((p) => p.isNotEmpty && p != '.').toList();
    if (parts.any((p) => p == '..')) return '';
    return parts.join('/');
  }

  String cmakeBuildAndRunCommand(String cmake) {
    if (Platform.isWindows) {
      const releaseExe = 'build\\Release\\agent_app.exe';
      const singleExe = 'build\\agent_app.exe';
      return '$cmake -S . -B build && $cmake --build build --config Release && (if exist $releaseExe ($releaseExe) else if exist $singleExe ($singleExe) else (echo Build completed but executable agent_app.exe was not found. && exit /b 1))';
    }
    return '$cmake -S . -B build && $cmake --build build && (if [ -x build/agent_app ]; then ./build/agent_app; else echo Build completed but executable agent_app was not found.; exit 1; fi)';
  }

  String ensureCMakeListsForCppSource(String relativeSource,
      {String baseRelativeDirectory = ''}) {
    final root = currentProject;
    if (root == null) return '';
    final baseRel = normalizeRelativeDirectory(baseRelativeDirectory);
    final baseDir = baseRel.isEmpty
        ? Directory(root.path)
        : Directory(resolveProjectPath(root.path, baseRel));
    if (!baseDir.existsSync())
      return 'CMake base directory not found: $baseRel';
    final cmakeFile = File(pathJoin(baseDir.path, 'CMakeLists.txt'));
    final sourceForCmake = normalizeSourcePathForCMake(relativeSource,
        baseRelativeDirectory: baseRel);
    var shouldWrite = true;
    if (cmakeFile.existsSync()) {
      final existing = cmakeFile.readAsStringSync(
          encoding: const Utf8Codec(allowMalformed: true));
      final existingSources =
          existingCppSourcesReferencedByCMake(existing, baseDir.path);
      // Keep an existing CMakeLists only when it references real sources and
      // builds the predictable target name used by run_tests. Otherwise repair it.
      if (existing.contains('add_executable') &&
          existingSources.isNotEmpty &&
          existing.contains('agent_app')) shouldWrite = false;
    }
    if (!shouldWrite) return '';
    final content = '''cmake_minimum_required(VERSION 3.10)
project(AgentGeneratedCpp LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(agent_app "$sourceForCmake")
''';
    cmakeFile.writeAsStringSync(content, encoding: utf8);
    taskFileMutations++;
    logAction('cmake_auto_write', {
      'file': pathRelative(root.path, cmakeFile.path),
      'source': relativeSource
    });
    return 'Created/repaired ${pathRelative(root.path, cmakeFile.path)} for source $relativeSource';
  }

  List<String> existingCppSourcesReferencedByCMake(
      String cmakeText, String baseDirPath) {
    final result = <String>[];
    final candidates =
        RegExp(r'''[^\s()"']+\.(?:cpp|cc|cxx)''', caseSensitive: false)
            .allMatches(cmakeText);
    for (final match in candidates) {
      final raw = match.group(0) ?? '';
      final path = raw
          .replaceAll('\\', Platform.pathSeparator)
          .replaceAll('/', Platform.pathSeparator);
      if (File(pathJoin(baseDirPath, path)).existsSync()) result.add(raw);
    }
    return result;
  }

  String normalizeSourcePathForCMake(String relativeSource,
      {String baseRelativeDirectory = ''}) {
    final baseRel = normalizeRelativeDirectory(baseRelativeDirectory);
    var rel = relativeSource.replaceAll('\\', '/');
    if (baseRel.isNotEmpty &&
        rel.toLowerCase().startsWith('${baseRel.toLowerCase()}/')) {
      rel = rel.substring(baseRel.length + 1);
    }
    return rel;
  }

  bool commandLikelyAvailable(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return false;
    final unquoted =
        trimmed.startsWith('"') && trimmed.endsWith('"') && trimmed.length > 1
            ? trimmed.substring(1, trimmed.length - 1)
            : trimmed;
    if (isAbsolutePath(unquoted)) return File(unquoted).existsSync();
    return findToolExecutable(
                [unquoted, Platform.isWindows ? '$unquoted.exe' : unquoted]) !=
            null ||
        commandExistsInPath(unquoted);
  }

  bool commandExistsInPath(String command) {
    final path = buildToolAwareEnvironment()['PATH'] ??
        Platform.environment['PATH'] ??
        '';
    final dirs = path
        .split(Platform.isWindows ? ';' : ':')
        .where((d) => d.trim().isNotEmpty);
    final names = <String>{command};
    final lower = command.toLowerCase();
    if (Platform.isWindows &&
        !lower.endsWith('.exe') &&
        !lower.endsWith('.bat') &&
        !lower.endsWith('.cmd')) {
      names.add('$command.exe');
      names.add('$command.bat');
      names.add('$command.cmd');
    }
    for (final dir in dirs) {
      for (final name in names) {
        if (File(pathJoin(dir, name)).existsSync()) return true;
      }
    }
    return false;
  }

  String defaultTestCommand({String relativeWorkingDirectory = ''}) {
    final root = currentProject;
    if (root == null) return '';
    final workRel = normalizeRelativeDirectory(relativeWorkingDirectory);
    final workDir =
        workRel.isEmpty ? root.path : resolveProjectPath(root.path, workRel);
    final python = Platform.isWindows ? 'python' : 'python3';
    final flutter = toolCommand(['flutter.bat', 'flutter.exe', 'flutter']);
    final npm = toolCommand(['npm.cmd', 'npm.exe', 'npm']);
    final cargo = toolCommand(['cargo.exe', 'cargo']);
    final cmake = toolCommand(['cmake.exe', 'cmake']);
    if (File(pathJoin(workDir, 'pubspec.yaml')).existsSync())
      return '$flutter test';
    if (File(pathJoin(workDir, 'CMakeLists.txt')).existsSync())
      return '$cmake -S . -B build && $cmake --build build';
    if (File(pathJoin(workDir, 'package.json')).existsSync())
      return '$npm test';
    if (File(pathJoin(workDir, 'Cargo.toml')).existsSync())
      return '$cargo test';
    if (File(pathJoin(workDir, 'pyproject.toml')).existsSync() ||
        Directory(pathJoin(workDir, 'test')).existsSync() ||
        Directory(pathJoin(workDir, 'tests')).existsSync())
      return '$python -m pytest';
    final py = primarySourceFile(['.py'],
        preferredNames: ['main.py'], baseRelativeDirectory: workRel);
    if (py != null) return '$python ${quoteShellArg(py)}';
    final cpp = primarySourceFile([
      '.cpp',
      '.cc',
      '.cxx'
    ], preferredNames: [
      'main.cpp',
      'object_recognition.cpp',
      'object_detector.cpp'
    ], baseRelativeDirectory: workRel);
    if (cpp != null) return defaultCppBuildCommand(cpp);
    return Platform.isWindows
        ? 'echo No default tests detected. Tools available: && where g++ 2>nul && where clang++ 2>nul && where cl 2>nul && where python 2>nul'
        : 'echo No default tests detected. Tools available:; command -v g++ || true; command -v clang++ || true; command -v python3 || true';
  }

  List<String> cppSourcesForBuild(String preferredSource) {
    final root = currentProject;
    if (root == null) return [preferredSource];
    final files = <String>[];
    try {
      for (final entity in Directory(root.path)
          .listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final rel = pathRelative(root.path, entity.path).replaceAll('\\', '/');
        final lower = rel.toLowerCase();
        if (lower.startsWith('.cppagent/') || lower == '.cppagent') continue;
        if (lower.startsWith('build/') ||
            lower.contains('/build/') ||
            lower.startsWith('cmake-build-')) continue;
        if (lower.endsWith('.cpp') ||
            lower.endsWith('.cc') ||
            lower.endsWith('.cxx')) files.add(rel);
      }
    } catch (_) {
      // Best effort; fall back to the selected source.
    }
    if (!files.contains(preferredSource)) files.insert(0, preferredSource);
    files.sort((a, b) {
      if (a == preferredSource) return -1;
      if (b == preferredSource) return 1;
      return a.compareTo(b);
    });
    final seen = <String>{};
    return files.where((f) => seen.add(f)).toList(growable: false);
  }

  String compilerSourceArg(String value) {
    if (!Platform.isWindows) return quoteShellArg(value);
    final cleaned =
        value.replaceAll('/', '\\').replaceAll(RegExp(r'^[.][\\/]'), '');
    // MinGW/MSYS2 g++.exe under cmd.exe can pass literal quotes to the linker for
    // simple relative files. For normal src\\main.cpp paths use no quotes.
    if (!RegExp(r'\s').hasMatch(cleaned)) return cleaned;
    return quoteShellArg(cleaned);
  }

  String defaultCppBuildCommand(String relativeSource) {
    final sources = cppSourcesForBuild(relativeSource);
    final sourceArgs = sources.map(compilerSourceArg).join(' ');
    if (Platform.isWindows) {
      final gpp = findToolExecutable(['g++.exe', 'g++']);
      final clang = findToolExecutable(['clang++.exe', 'clang++']);
      final cl = findToolExecutable(['cl.exe', 'cl']);
      final prepare =
          'if not exist build mkdir build & if exist build\\app.exe del /q build\\app.exe';
      if (gpp != null) {
        const exe = 'build\\app.exe';
        return '$prepare & ${gpp.name} -std=c++17 -O2 $sourceArgs -o $exe && if exist $exe ($exe) else (echo BUILD_ARTIFACT_MISSING: $exe && exit /b 2)';
      }
      if (clang != null) {
        const exe = 'build\\app.exe';
        return '$prepare & ${clang.name} -std=c++17 -O2 $sourceArgs -o $exe && if exist $exe ($exe) else (echo BUILD_ARTIFACT_MISSING: $exe && exit /b 2)';
      }
      if (cl != null) {
        const exe = 'build\\app.exe';
        return '$prepare & ${cl.name} /nologo /EHsc /std:c++17 $sourceArgs /Fe:$exe && if exist $exe ($exe) else (echo BUILD_ARTIFACT_MISSING: $exe && exit /b 2)';
      }
      return '$prepare & (where g++ >nul 2>nul && (g++ -std=c++17 -O2 $sourceArgs -o build\\app.exe && if exist build\\app.exe (build\\app.exe) else (echo BUILD_ARTIFACT_MISSING: build\\app.exe && exit /b 2)) || (where clang++ >nul 2>nul && (clang++ -std=c++17 -O2 $sourceArgs -o build\\app.exe && if exist build\\app.exe (build\\app.exe) else (echo BUILD_ARTIFACT_MISSING: build\\app.exe && exit /b 2)) || (where cl >nul 2>nul && (cl /nologo /EHsc /std:c++17 $sourceArgs /Fe:build\\app.exe && if exist build\\app.exe (build\\app.exe) else (echo BUILD_ARTIFACT_MISSING: build\\app.exe && exit /b 2)) || (echo C++ compiler not found in tools/windows/x64 or PATH. Put MinGW/LLVM/MSVC tools into tools\\windows\\x64 or install compiler. && exit /b 9009))))';
    }
    final gpp = findToolExecutable(['g++']);
    final clang = findToolExecutable(['clang++']);
    if (gpp != null)
      return 'mkdir -p build && rm -f build/app && ${quoteShellArg(gpp.path)} -std=c++17 -O2 $sourceArgs -o build/app && test -f build/app && ./build/app';
    if (clang != null)
      return 'mkdir -p build && rm -f build/app && ${quoteShellArg(clang.path)} -std=c++17 -O2 $sourceArgs -o build/app && test -f build/app && ./build/app';
    return 'mkdir -p build && rm -f build/app && (command -v g++ >/dev/null 2>&1 && g++ -std=c++17 -O2 $sourceArgs -o build/app && test -f build/app && ./build/app || (command -v clang++ >/dev/null 2>&1 && clang++ -std=c++17 -O2 $sourceArgs -o build/app && test -f build/app && ./build/app || (echo C++ compiler not found in tools or PATH && exit 127)))';
  }

  String? primarySourceFile(List<String> extensions,
      {List<String> preferredNames = const [],
      String baseRelativeDirectory = ''}) {
    final root = currentProject;
    if (root == null) return null;
    final baseRel = normalizeRelativeDirectory(baseRelativeDirectory);
    final basePath =
        baseRel.isEmpty ? root.path : resolveProjectPath(root.path, baseRel);
    for (final name in preferredNames) {
      final rel = baseRel.isEmpty ? name : '$baseRel/$name';
      if (File(resolveProjectPath(root.path, rel)).existsSync()) return rel;
    }
    final files = <String>[];
    try {
      final baseDir = Directory(basePath);
      if (!baseDir.existsSync()) return null;
      for (final entity
          in baseDir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final rel = pathRelative(root.path, entity.path);
        final lower = rel.toLowerCase().replaceAll('\\', '/');
        if (lower.startsWith('.cppagent/') || lower.startsWith('build/'))
          continue;
        if (extensions.any(lower.endsWith)) files.add(rel);
        if (files.length >= 100) break;
      }
    } catch (_) {}
    files.sort((a, b) => a.length.compareTo(b.length));
    return files.isEmpty ? null : files.first;
  }

  Future<String> makeRelativeDir(String relativePath) async {
    final root = currentProject;
    if (root == null) return 'No project';
    if (relativePath.isEmpty) return 'path is required';
    if (isWritingToAgentInternalPath(relativePath)) {
      final blocked =
          reservedAgentPathMessage(relativePath, action: 'make_dir');
      log(blocked);
      logAction('reserved_agent_path_blocked',
          {'tool': 'make_dir', 'path': relativePath});
      return blocked;
    }
    await Directory(resolveProjectPath(root.path, relativePath))
        .create(recursive: true);
    taskFileMutations++;
    logAction('directory_create', {'path': relativePath});
    return 'Directory created: $relativePath';
  }

  String normalizeCommandForHost(String command) {
    var value = command.trim();
    if (value.isEmpty) return command;
    if (Platform.isAndroid) {
      final lower = value.toLowerCase();
      if (lower == 'cls') return 'clear';
      if (lower == 'dir') return 'ls -la';
      if (lower == 'cd') return 'pwd';
    }
    if (Platform.isWindows) {
      final lower = value.toLowerCase();
      if (lower == 'ls') return 'dir';
      if (lower.startsWith('ls ')) return 'dir ${value.substring(3)}';
      if (lower == 'pwd') return 'cd';
      value = value.replaceAll(
          RegExp(r'^if\s+not\s+exist\s+build\s+mkdir\s+build\s+&&\s+',
              caseSensitive: false),
          'if not exist build mkdir build & if exist build\\app.exe del /q build\\app.exe & ');
      value = value.replaceAllMapped(
        RegExp(r'"([^"\r\n]+\.(?:cpp|cc|cxx|c|h|hpp))"', caseSensitive: false),
        (match) {
          final path = (match.group(1) ?? '').replaceAll('/', '\\');
          return RegExp(r'\s').hasMatch(path) ? match.group(0)! : path;
        },
      );
      if (value.toLowerCase().startsWith('tools/') ||
          value.toLowerCase().startsWith('tools\\')) {
        final firstSpace = value.indexOf(' ');
        final firstToken =
            firstSpace < 0 ? value : value.substring(0, firstSpace);
        final rest = firstSpace < 0 ? '' : value.substring(firstSpace);
        final absolute = pathJoin(
            appRootPath,
            firstToken
                .replaceAll('/', Platform.pathSeparator)
                .replaceAll('\\', Platform.pathSeparator));
        return '"$absolute"$rest';
      }
    }
    return value;
  }

  BuildArtifactInfo? detectExpectedBuildArtifact(
      String command, String workDir) {
    final matches = <String>[];
    for (final match
        in RegExp(r'(?:^|\s)-o\s+("[^"]+"|[^\s&|]+)', caseSensitive: false)
            .allMatches(command)) {
      final raw = match.group(1);
      if (raw != null) matches.add(raw);
    }
    for (final match
        in RegExp(r'/Fe:?\s*("[^"]+"|[^\s&|]+)', caseSensitive: false)
            .allMatches(command)) {
      final raw = match.group(1);
      if (raw != null) matches.add(raw);
    }
    if (matches.isEmpty) return null;
    var path = matches.last.trim();
    if ((path.startsWith('"') && path.endsWith('"')) ||
        (path.startsWith("'") && path.endsWith("'"))) {
      path = path.substring(1, path.length - 1);
    }
    if (path.trim().isEmpty) return null;
    final absolute = isAbsolutePath(path)
        ? path
        : pathJoin(
            workDir,
            path
                .replaceAll('/', Platform.pathSeparator)
                .replaceAll('\\', Platform.pathSeparator));
    return BuildArtifactInfo(
        path: absolute, exists: File(absolute).existsSync());
  }

  String? relativePathFromProject(String absolutePath) {
    final project = currentProject;
    if (project == null) return null;
    try {
      return pathRelative(project.path, absolutePath).replaceAll('\\', '/');
    } catch (_) {
      return null;
    }
  }

  String buildArtifactNote(BuildArtifactInfo artifact) {
    final relative = relativePathFromProject(artifact.path) ?? artifact.path;
    if (artifact.exists) return 'BUILD_ARTIFACT_OK: $relative';
    return 'BUILD_ARTIFACT_MISSING: $relative';
  }

  bool isAndroidPackageManagerCommand(String command) {
    final trimmed = command.trim().toLowerCase();
    return trimmed == 'pkg' ||
        trimmed.startsWith('pkg ') ||
        trimmed == 'apt' ||
        trimmed.startsWith('apt ') ||
        trimmed.startsWith('ai-pkg ');
  }

  Future<String> runAndroidPackageManagerCommand(String command) async {
    final root =
        Directory(pathJoin(appRootPath, 'tools', 'android', 'packages'));
    await root.create(recursive: true);
    final db = File(pathJoin(root.path, 'packages.json'));
    Map<String, dynamic> data = {};
    if (await db.exists()) {
      try {
        data = jsonDecode(await db.readAsString(encoding: utf8))
            as Map<String, dynamic>;
      } catch (_) {
        data = {};
      }
    }
    final parts = command
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    final action = parts.length >= 2 ? parts[1].toLowerCase() : 'help';
    final buffer = StringBuffer();
    buffer.writeln('COMMAND: $command');
    buffer.writeln('WORKDIR: ${currentProject?.path ?? appRootPath}');
    buffer.writeln('ANDROID_ISOLATED_PACKAGE_ROOT: ${root.path}');
    int exitCode = 0;
    if (action == 'install' && parts.length >= 3) {
      for (final name in parts.skip(2)) {
        if (name.startsWith('-')) continue;
        final dir = Directory(pathJoin(root.path, name));
        await dir.create(recursive: true);
        data[name] = {
          'name': name,
          'installedAt': DateTime.now().toIso8601String(),
          'root': dir.path,
          'manager': parts.first
        };
        buffer.writeln('installed: $name -> ${dir.path}');
      }
    } else if ((action == 'remove' ||
            action == 'uninstall' ||
            action == 'delete') &&
        parts.length >= 3) {
      for (final name in parts.skip(2)) {
        data.remove(name);
        final dir = Directory(pathJoin(root.path, name));
        if (await dir.exists()) await dir.delete(recursive: true);
        buffer.writeln('removed: $name');
      }
    } else if (action == 'update' || action == 'upgrade') {
      data['_lastUpdate'] = DateTime.now().toIso8601String();
      buffer.writeln('package index updated in isolated AI Agent space');
    } else if (action == 'list' || action == 'list-installed') {
      final names = data.keys.where((k) => !k.startsWith('_')).toList()..sort();
      buffer.writeln(names.isEmpty
          ? '(no isolated packages installed)'
          : names.join('\n'));
    } else {
      buffer.writeln(
          'AI Agent Android package manager commands: pkg install <name>, pkg remove <name>, pkg update, pkg list-installed.');
      buffer.writeln(
          'This is an isolated app-space package database; real compilers/SDK files can be downloaded into tools/android by the agent.');
    }
    await db.writeAsString(const JsonEncoder.withIndent('  ').convert(data),
        encoding: utf8);
    buffer.writeln('EXIT_CODE: $exitCode');
    return buffer.toString();
  }

  Future<String> runCommand(String command,
      {bool allowPythonAutoInstall = true,
      String relativeWorkingDirectory = ''}) async {
    final root = currentProject;
    if (root == null) return 'No project';
    if (command.trim().isEmpty) return 'command is required';
    if (cancelRequested)
      return 'CANCELLED: command was not started because the user pressed Stop.';
    if (!(Platform.isWindows ||
        Platform.isLinux ||
        Platform.isMacOS ||
        Platform.isAndroid))
      return 'run_command is not available on this platform: ${Platform.operatingSystem}';
    final workRel = normalizeRelativeDirectory(relativeWorkingDirectory);
    final workDir =
        workRel.isEmpty ? root.path : resolveProjectPath(root.path, workRel);
    if (!Directory(workDir).existsSync())
      return 'working directory not found: $workRel';
    final normalizedCommand = normalizeCommandForHost(command);
    if (Platform.isAndroid &&
        isAndroidPackageManagerCommand(normalizedCommand)) {
      final pkgResult =
          await runAndroidPackageManagerCommand(normalizedCommand);
      lastCommandExitCode = pkgResult.contains('EXIT_CODE: 0') ? 0 : 1;
      lastCommandText = command;
      lastCommandResultText = pkgResult;
      return pkgResult;
    }
    final prepared =
        await prepareCommandForPythonEnvironment(normalizedCommand);
    final effectiveCommand = prepared.command;
    final env = buildToolAwareEnvironment();
    final toolPathPreview = toolDirectoriesForPath()
        .take(25)
        .join(Platform.isWindows ? '; ' : ': ');
    log('RUN COMMAND START: $command');
    if (normalizedCommand != command)
      log('RUN COMMAND NORMALIZED: $normalizedCommand');
    if (effectiveCommand != normalizedCommand)
      log('RUN COMMAND EFFECTIVE: $effectiveCommand');
    if (prepared.note.isNotEmpty)
      log('RUN COMMAND PYTHON PREPARE:\n${prepared.note}');
    log('RUN COMMAND ENVIRONMENT: ${hostEnvironmentSummary().replaceAll('\n', ' | ')}');
    log('RUN COMMAND TOOLS PATH PRIORITY: $toolPathPreview');
    final executable = Platform.isWindows
        ? 'cmd'
        : (Platform.isAndroid ? '/system/bin/sh' : '/bin/sh');
    final args = Platform.isWindows
        ? ['/d', '/c', effectiveCommand]
        : ['-c', effectiveCommand];
    taskCommandRuns++;
    lastCommandText = command;
    final startedAt = DateTime.now();
    try {
      final process = await Process.run(executable, args,
              workingDirectory: workDir,
              runInShell: false,
              stdoutEncoding: null,
              stderrEncoding: null,
              environment: env)
          .timeout(const Duration(minutes: 10));
      final stdoutText = decodeProcessOutput(process.stdout);
      final stderrText = decodeProcessOutput(process.stderr);
      var effectiveExitCode = process.exitCode;
      final artifact = process.exitCode == 0
          ? detectExpectedBuildArtifact(effectiveCommand, workDir)
          : null;
      final artifactText =
          artifact == null ? '' : '\n${buildArtifactNote(artifact)}';
      if (artifact != null && artifact.exists) {
        final rel = relativePathFromProject(artifact.path) ?? artifact.path;
        ensureConsoleQuickLaunch('Запуск ${pathBasename(artifact.path)}',
            commandForProjectExecutable(rel),
            cwd: '.');
      }
      if (artifact != null && !artifact.exists) {
        effectiveExitCode = 2;
      }
      lastCommandExitCode = effectiveExitCode;
      if (effectiveExitCode != 0) taskFailedCommands++;
      final normalizedHeader = normalizedCommand != command
          ? 'NORMALIZED_COMMAND: $normalizedCommand\n'
          : '';
      final effectiveHeader = effectiveCommand != normalizedCommand
          ? 'EFFECTIVE_COMMAND: $effectiveCommand\n'
          : '';
      final pythonHeader = prepared.note.isNotEmpty
          ? 'PYTHON_ENVIRONMENT:\n${prepared.note}\n'
          : '';
      final result = '''COMMAND: $command
${normalizedHeader}${effectiveHeader}${pythonHeader}WORKDIR: $workDir
ENVIRONMENT: ${hostEnvironmentSummary().replaceAll('\n', ' | ')}
TOOLS_PATH_PRIORITY: $toolPathPreview
EXIT_CODE: $effectiveExitCode
PROCESS_EXIT_CODE: ${process.exitCode}
DURATION_MS: ${DateTime.now().difference(startedAt).inMilliseconds}$artifactText

[STDOUT]
$stdoutText

[STDERR]
$stderrText
[/STDERR]
''';
      var enrichedResult = result;
      if (effectiveExitCode != 0 &&
          (isEnvironmentProblemOutput(result) ||
              isBuildConfigurationProblemOutput(result) ||
              result.contains('BUILD_ARTIFACT_MISSING'))) {
        enrichedResult +=
            '\n[LOCAL_TOOLS_AVAILABLE]\n${localToolsCompactSummary(purpose: 'build', maxItems: 12)}\n[/LOCAL_TOOLS_AVAILABLE]\n';
      }
      lastCommandResultText = enrichedResult;
      final outputLogPath =
          await writeCommandOutputLog(command: command, result: enrichedResult);
      log('RUN COMMAND RESULT FULL SAVED: $outputLogPath');
      log('RUN COMMAND RESULT: ${truncateMiddle(enrichedResult, 30000)}');
      logAction('command_run', {
        'command': command,
        'effective_command': effectiveCommand,
        'exit_code': effectiveExitCode,
        'process_exit_code': process.exitCode,
        'artifact': artifactText.trim(),
        'output_log': outputLogPath,
        'stdout': truncateMiddle(stdoutText, 20000),
        'stderr': truncateMiddle(stderrText, 20000),
        'local_tools': truncateMiddle(
            localToolsCompactSummary(purpose: 'build', maxItems: 12), 2000)
      });
      final commandReturn =
          '${truncateMiddle(enrichedResult, 60000)}\nFULL_OUTPUT_LOG: $outputLogPath';
      if (effectiveExitCode == 0 &&
          taskFailedCommands > 0 &&
          command.trim().isNotEmpty) {
        await rememberSolution(
            'После предыдущих ошибок команда успешно выполнилась',
            'Успешная команда: $command',
            'auto,command,${Platform.operatingSystem},${hostArchSegment}');
      }
      if (allowPythonAutoInstall &&
          effectiveExitCode != 0 &&
          isPythonExecutionCommand(effectiveCommand) &&
          isMissingPythonModuleOutput(enrichedResult)) {
        final missingPackages = missingPythonModules(enrichedResult);
        if (missingPackages.isNotEmpty) {
          log('PYTHON AUTO INSTALL: missing modules=${missingPackages.join(', ')}');
          final installResult =
              await installPythonPackagesInProjectVenv(missingPackages);
          log('PYTHON AUTO INSTALL RESULT:\n${truncateMiddle(installResult, 20000)}');
          final retry =
              await runCommand(command, allowPythonAutoInstall: false);
          return '$commandReturn\n\n[PYTHON_VENV_AUTO_INSTALL]\n$installResult\n[/PYTHON_VENV_AUTO_INSTALL]\n\n[PYTHON_COMMAND_RETRY]\n$retry\n[/PYTHON_COMMAND_RETRY]';
        }
      }
      return commandReturn;
    } on TimeoutException catch (error) {
      lastCommandExitCode = -1;
      taskFailedCommands++;
      final result = '''COMMAND: $command
WORKDIR: $workDir
EXIT_CODE: -1
ERROR: command timed out after 10 minutes
DETAILS: $error
''';
      lastCommandResultText = result;
      final outputLogPath =
          await writeCommandOutputLog(command: command, result: result);
      log('RUN COMMAND TIMEOUT: ${truncateMiddle(result, 12000)}');
      logAction(
          'command_timeout', {'command': command, 'output_log': outputLogPath});
      return '$result\nFULL_OUTPUT_LOG: $outputLogPath';
    } catch (error, stack) {
      lastCommandExitCode = -1;
      taskFailedCommands++;
      final result = '''COMMAND: $command
WORKDIR: $workDir
EXIT_CODE: -1
ERROR: failed to start or execute command
DETAILS: $error
STACK:
$stack
''';
      lastCommandResultText = result;
      final outputLogPath =
          await writeCommandOutputLog(command: command, result: result);
      log('RUN COMMAND ERROR: ${truncateMiddle(result, 12000)}');
      logAction('command_error', {
        'command': command,
        'error': error.toString(),
        'output_log': outputLogPath
      });
      return '$result\nFULL_OUTPUT_LOG: $outputLogPath';
    }
  }

  Future<String> writeCommandOutputLog(
      {required String command, required String result}) async {
    final root = currentProject;
    if (root == null) return '';
    try {
      final dir =
          Directory(pathJoin(root.path, '.cppagent', 'logs', 'commands'));
      await dir.create(recursive: true);
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final file = File(pathJoin(dir.path, '${stamp}_command.log'));
      await file.writeAsString('COMMAND:\n$command\n\n$result', encoding: utf8);
      return file.path;
    } catch (error) {
      log('COMMAND OUTPUT LOG WRITE ERROR: $error');
      return '';
    }
  }

  String resolvePossiblyRelativePath(String rawPath) {
    final project = currentProject;
    final value = rawPath.trim();
    if (value.isEmpty) return value;
    if (isAbsolutePath(value)) return value;
    if (project == null) return value;
    return resolveProjectPath(project.path, value);
  }

  Future<String> setTaskPlan(String plan) async {
    final project = currentProject;
    if (project == null) return 'No project';
    final trimmed = plan.trim();
    if (trimmed.isEmpty) return 'plan is required';
    final dir = Directory(pathJoin(project.path, '.cppagent'));
    await dir.create(recursive: true);
    final file = File(pathJoin(dir.path, 'task_plan.md'));
    await file.writeAsString('# План задачи\n\n$trimmed\n', encoding: utf8);
    logAction('task_plan_set',
        {'plan': truncateMiddle(trimmed, 12000), 'file': file.path});
    return 'TASK_PLAN_SET: .cppagent/task_plan.md\n$trimmed';
  }

  File get solutionMemoryFile =>
      File(pathJoin(configRoot.path, 'solution_memory.jsonl'));

  String solutionMemoryCompactSummary({int maxItems = 20}) {
    final file = solutionMemoryFile;
    if (!file.existsSync()) return '(память решений пока пуста)';
    try {
      final lines = file.readAsLinesSync(encoding: utf8);
      final recent = lines.reversed.take(maxItems * 3).toList().reversed;
      final buffer = StringBuffer();
      final seen = <String>{};
      for (final line in recent) {
        final data = jsonDecode(line) as Map<String, dynamic>;
        final tags = data['tags']?.toString() ?? 'general';
        final problem = data['problem']?.toString() ?? '';
        var solution = data['solution']?.toString() ?? '';
        if (solution.trim().toLowerCase() == 'успешная команда: cd') continue;
        solution = solution.replaceAllMapped(
          RegExp(r'"([^"\r\n]+\.(?:cpp|cc|cxx|c|h|hpp))"',
              caseSensitive: false),
          (match) {
            final path = match.group(1) ?? '';
            return RegExp(r'\s').hasMatch(path)
                ? match.group(0)!
                : path.replaceAll('/', '\\');
          },
        );
        final rendered = '- [$tags] $problem: $solution';
        if (seen.add(rendered)) buffer.writeln(rendered);
        if (seen.length >= maxItems) break;
      }
      final text = buffer.toString().trimRight();
      return text.isEmpty
          ? '(память решений пока пуста)'
          : truncateMiddle(text, 8000);
    } catch (error) {
      return '(ошибка чтения памяти решений: $error)';
    }
  }

  Future<String> rememberSolution(
      String problem, String solution, String tags) async {
    if (problem.trim().isEmpty || solution.trim().isEmpty)
      return 'problem and solution are required';
    await configRoot.create(recursive: true);
    final item = {
      'time': DateTime.now().toIso8601String(),
      'project': currentProject?.path,
      'problem': problem.trim(),
      'solution': solution.trim(),
      'tags': tags.trim().isEmpty ? 'general' : tags.trim(),
      'environment': hostEnvironmentSummary(),
    };
    await solutionMemoryFile.writeAsString('${jsonEncode(item)}\n',
        mode: FileMode.append, encoding: utf8);
    logAction('solution_remembered', item);
    return 'Solution remembered: ${item['problem']}';
  }

  String resolveToolsPath(String relativePath) {
    final cleaned = relativePath.trim().replaceAll('\\', '/');
    if (cleaned.isEmpty) return toolsRoot.path;
    if (isAbsolutePath(cleaned)) {
      final normalizedRoot =
          toolsRoot.absolute.path.replaceAll('\\', '/').toLowerCase();
      final normalizedPath =
          File(cleaned).absolute.path.replaceAll('\\', '/').toLowerCase();
      if (!normalizedPath.startsWith(normalizedRoot)) {
        throw StateError('Absolute tools path is outside tools: $relativePath');
      }
      return cleaned;
    }
    if (cleaned.split('/').contains('..'))
      throw StateError(
          'Path traversal is not allowed in tools path: $relativePath');
    return pathJoin(toolsRoot.path, cleaned);
  }

  String guessFileNameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final last = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
      if (last.trim().isNotEmpty) return last;
    } catch (_) {}
    return 'download_${DateTime.now().millisecondsSinceEpoch}.bin';
  }

  Future<String> downloadToTools(String url, String relativePath) async {
    if (!allowInternetUse)
      return 'INTERNET_DISABLED: включите интернет-инструменты в настройках.';
    if (url.trim().isEmpty) return 'url is required';
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https'))
      return 'Only http/https URLs are supported: $url';
    final destRel = relativePath.trim().isEmpty
        ? pathJoin('downloads', guessFileNameFromUrl(url))
        : relativePath.trim();
    final destPath = resolveToolsPath(destRel);
    final destFile = File(destPath);
    await destFile.parent.create(recursive: true);
    log('DOWNLOAD TOOLS START: $url -> $destPath');
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.getUrl(uri);
      final response =
          await request.close().timeout(const Duration(minutes: 2));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return 'DOWNLOAD_FAILED: HTTP ${response.statusCode} ${response.reasonPhrase} for $url';
      }
      final sink = destFile.openWrite();
      var bytes = 0;
      await for (final chunk in response.timeout(const Duration(minutes: 20))) {
        bytes += chunk.length;
        sink.add(chunk);
      }
      await sink.close();
      logAction(
          'download_to_tools', {'url': url, 'dest': destPath, 'bytes': bytes});
      return 'DOWNLOADED_TO_TOOLS: $destPath\nBYTES: $bytes\nTOOLS_HINT: после скачивания архива используй extract_zip_to_tools, затем list_local_tools.';
    } finally {
      client.close(force: true);
    }
  }

  String resolveArchivePathForTools(String rawPath) {
    final raw = rawPath.trim();
    if (raw.isEmpty) return '';
    if (isAbsolutePath(raw)) return raw;
    final asTools = File(resolveToolsPath(raw));
    if (asTools.existsSync()) return asTools.path;
    return resolvePossiblyRelativePath(raw);
  }

  Future<String> extractZipToTools(String rawPath, String rawDest) async {
    final archivePath = resolveArchivePathForTools(rawPath);
    if (archivePath.isEmpty) return 'path is required';
    if (!await File(archivePath).exists()) return 'ZIP not found: $rawPath';
    final destPath = resolveToolsPath(rawDest.trim().isEmpty
        ? pathJoin(hostOsSegment, hostArchSegment)
        : rawDest);
    await Directory(destPath).create(recursive: true);
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS))
      return 'extract_zip_to_tools currently needs desktop tar support.';
    final result = await Process.run(
            'tar', ['-xf', archivePath, '-C', destPath],
            stdoutEncoding: null,
            stderrEncoding: null,
            environment: buildToolAwareEnvironment())
        .timeout(const Duration(minutes: 10));
    final text =
        'COMMAND: tar -xf $archivePath -C $destPath\nEXIT_CODE: ${result.exitCode}\n[STDOUT]\n${decodeProcessOutput(result.stdout)}\n[STDERR]\n${decodeProcessOutput(result.stderr)}\n[/STDERR]\nExtracted to tools: $destPath\n\n[TOOLS_AFTER_EXTRACT]\n${localToolsCompactSummary(maxItems: 40)}\n[/TOOLS_AFTER_EXTRACT]';
    logAction('extract_zip_to_tools', {
      'archive': archivePath,
      'dest': destPath,
      'exit_code': result.exitCode
    });
    return text;
  }

  String htmlEntityDecodeBasic(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1) ?? '');
      return code == null ? m.group(0)! : String.fromCharCode(code);
    });
  }

  String stripHtmlToText(String html) {
    var text = html.replaceAll(
        RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ');
    text = text.replaceAll(
        RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ');
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'</h[1-6]\s*>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
    text = htmlEntityDecodeBasic(text);
    text = text
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n\s+'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  String normalizeResearchText(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^а-яa-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  bool textContainsAllNameTokens(String text, List<String> tokens) {
    if (tokens.length != 3) return true;
    final words = normalizeResearchText(text)
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    bool hasToken(String token) => words.any((w) =>
        normalizeRussianNameToken(w) == token ||
        w.contains(token) ||
        token.contains(w));
    return tokens.every(hasToken);
  }

  String resolveUrlAgainst(Uri base, String raw) {
    final value = htmlEntityDecodeBasic(raw.trim());
    if (value.isEmpty ||
        value.startsWith('data:') ||
        value.startsWith('javascript:')) return '';
    final parsed = Uri.tryParse(value);
    final resolved = parsed == null
        ? null
        : (parsed.hasScheme ? parsed : base.resolveUri(parsed));
    if (resolved == null ||
        !(resolved.scheme == 'http' || resolved.scheme == 'https')) return '';
    return resolved.toString();
  }

  List<String> extractRelevantImageLines(String html, Uri baseUri, String query,
      {int max = 12}) {
    final result = <String>[];
    final seen = <String>{};
    final tokens = extractLikelyFullNameTokens(query);
    final queryWords = normalizeResearchText(query)
        .split(' ')
        .where((w) => w.length > 2)
        .toSet();
    bool relevant(String text) {
      final normalized = normalizeResearchText(text);
      if (tokens.length == 3 && !textContainsAllNameTokens(text, tokens))
        return false;
      if (queryWords.isEmpty) return true;
      return queryWords.any((w) => normalized.contains(w));
    }

    void addImage(String rawUrl, String description) {
      if (result.length >= max) return;
      final url = resolveUrlAgainst(baseUri, rawUrl);
      if (url.isEmpty || !seen.add(url)) return;
      final desc = htmlEntityDecodeBasic(
          stripHtmlToText(description).replaceAll('=>', ' ').trim());
      if (desc.isNotEmpty && !relevant(desc)) return;
      final lower = url.toLowerCase();
      final looksImage = RegExp(r'\.(png|jpe?g|webp|gif|bmp|svg)(\?|#|$)',
                  caseSensitive: false)
              .hasMatch(lower) ||
          lower.contains('image') ||
          lower.contains('photo') ||
          lower.contains('avatar');
      if (!looksImage) return;
      result
          .add('- ${desc.isEmpty ? 'изображение без описания' : desc} => $url');
    }

    for (final m in RegExp(
            r'''<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']''',
            caseSensitive: false)
        .allMatches(html)) {
      addImage(m.group(1) ?? '', 'og:image');
    }
    for (final m
        in RegExp(r'<img\b([^>]+)>', caseSensitive: false).allMatches(html)) {
      final attrs = m.group(1) ?? '';
      final src = RegExp(r'''(?:src|data-src|data-original)=["']([^"']+)["']''',
                  caseSensitive: false)
              .firstMatch(attrs)
              ?.group(1) ??
          '';
      final alt = RegExp(r'''alt=["']([^"']*)["']''', caseSensitive: false)
              .firstMatch(attrs)
              ?.group(1) ??
          '';
      final title = RegExp(r'''title=["']([^"']*)["']''', caseSensitive: false)
              .firstMatch(attrs)
              ?.group(1) ??
          '';
      addImage(src, [alt, title].where((e) => e.trim().isNotEmpty).join(' / '));
    }
    return result;
  }

  String normalizeDuckDuckGoUrl(String raw) {
    var url = htmlEntityDecodeBasic(raw.trim());
    if (url.startsWith('//')) url = 'https:$url';
    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.queryParameters.containsKey('uddg')) {
      return parsed.queryParameters['uddg'] ?? url;
    }
    return url;
  }

  Future<String> duckDuckGoSearch(String query, {int maxResults = 8}) async {
    if (!allowInternetUse)
      return 'INTERNET_DISABLED: включите интернет-инструменты в настройках.';
    final q = query.trim();
    if (q.isEmpty) return 'query is required';
    final limit = maxResults.clamp(1, 12).toInt();
    final uri =
        Uri.parse('https://duckduckgo.com/html/?q=${Uri.encodeComponent(q)}');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request =
          await client.getUrl(uri).timeout(const Duration(seconds: 30));
      request.headers
          .set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 AI-Agent/$appVersion');
      final response =
          await request.close().timeout(const Duration(minutes: 2));
      final html = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return 'DUCKDUCKGO_SEARCH_FAILED: HTTP ${response.statusCode}\n$query';
      }
      final results = <String>[];
      final resultPattern = RegExp(
          r'<a[^>]+class="result__a"[^>]+href="([^"]+)"[^>]*>([\s\S]*?)</a>',
          caseSensitive: false);
      for (final match in resultPattern.allMatches(html)) {
        if (results.length >= limit) break;
        final url = normalizeDuckDuckGoUrl(match.group(1) ?? '');
        final title =
            stripHtmlToText(match.group(2) ?? '').replaceAll('\n', ' ').trim();
        if (url.isEmpty || title.isEmpty) continue;
        results.add('${results.length + 1}. $title\nURL: $url');
      }
      if (results.isEmpty) {
        final links = RegExp(
                r"""<a[^>]+href=["']([^"']+)["'][^>]*>([\s\S]*?)</a>""",
                caseSensitive: false)
            .allMatches(html);
        for (final match in links) {
          if (results.length >= limit) break;
          final url = normalizeDuckDuckGoUrl(match.group(1) ?? '');
          final title = stripHtmlToText(match.group(2) ?? '')
              .replaceAll('\n', ' ')
              .trim();
          if (!url.startsWith('http') || title.length < 3) continue;
          results.add('${results.length + 1}. $title\nURL: $url');
        }
      }
      logAction('duckduckgo_search', {'query': q, 'results': results.length});
      if (results.isEmpty) return 'DUCKDUCKGO_SEARCH_NO_RESULTS: $q';
      return 'DUCKDUCKGO_SEARCH_RESULTS for "$q"\n${results.join('\n\n')}\n\nNEXT: use web_fetch with a URL to read a page, or download_to_project/download_to_tools for files.';
    } catch (error) {
      return 'DUCKDUCKGO_SEARCH_FAILED: $error';
    } finally {
      client.close(force: true);
    }
  }

  Future<String> webFetch(String url,
      {int maxChars = 20000, String researchQuery = ''}) async {
    if (!allowInternetUse)
      return 'INTERNET_DISABLED: включите интернет-инструменты в настройках.';
    final raw = url.trim();
    if (raw.isEmpty) return 'url is required';
    final uri = Uri.tryParse(raw);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https'))
      return 'Only http/https URLs are supported: $url';
    final limit = maxChars.clamp(1000, 120000).toInt();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request =
          await client.getUrl(uri).timeout(const Duration(seconds: 30));
      request.headers
          .set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 AI-Agent/$appVersion');
      final response =
          await request.close().timeout(const Duration(minutes: 3));
      final bytes =
          await response.expand((chunk) => chunk).take(limit * 4).toList();
      final html = utf8.decode(bytes, allowMalformed: true);
      final titleMatch =
          RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false)
              .firstMatch(html);
      final title = titleMatch == null
          ? ''
          : stripHtmlToText(titleMatch.group(1) ?? '').replaceAll('\n', ' ');
      final text = stripHtmlToText(html);
      final linkLines = <String>[];
      for (final match in RegExp(
              r"""<a[^>]+href=["']([^"']+)["'][^>]*>([\s\S]*?)</a>""",
              caseSensitive: false)
          .allMatches(html)) {
        if (linkLines.length >= 80) break;
        final href = htmlEntityDecodeBasic(match.group(1) ?? '').trim();
        final label =
            stripHtmlToText(match.group(2) ?? '').replaceAll('\n', ' ').trim();
        if (href.isEmpty || label.isEmpty) continue;
        Uri? linkUri = Uri.tryParse(href);
        if (linkUri != null && !linkUri.hasScheme)
          linkUri = uri.resolveUri(linkUri);
        if (linkUri == null ||
            !(linkUri.scheme == 'http' || linkUri.scheme == 'https')) continue;
        linkLines.add('- $label => ${linkUri.toString()}');
      }
      final imageLines = extractRelevantImageLines(
          html, uri, researchQuery.trim().isEmpty ? raw : researchQuery,
          max: 12);
      final contacts = <String>[];
      for (final match in RegExp(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}',
              caseSensitive: false)
          .allMatches('$text\n$html')) {
        final value = match.group(0) ?? '';
        if (value.isNotEmpty &&
            !contacts.contains(value) &&
            contacts.length < 30) contacts.add(value);
      }
      final usefulLines = <String>[];
      final usefulMarkers = [
        'работ',
        'должн',
        'компан',
        'организац',
        'университет',
        'школ',
        'профиль',
        'биограф',
        'родствен',
        'комментар',
        'контакт',
        'сотруд',
        'автор',
        'руковод'
      ];
      for (final line in text.split('\n')) {
        final cleanLine = line.trim();
        if (cleanLine.length < 12) continue;
        final lowerLine = cleanLine.toLowerCase();
        if (usefulMarkers.any(lowerLine.contains) && usefulLines.length < 40)
          usefulLines.add('- $cleanLine');
      }
      logAction('web_fetch', {
        'url': raw,
        'status': response.statusCode,
        'chars': text.length,
        'links': linkLines.length
      });
      return '''WEB_FETCH_RESULT
URL: $raw
HTTP_STATUS: ${response.statusCode}
TITLE: $title

[CONTACTS]
${contacts.map((e) => '- $e').join('\n')}
[/CONTACTS]

[USEFUL_LINES]
${usefulLines.join('\n')}
[/USEFUL_LINES]

[IMAGES]
${imageLines.join('\n')}
[/IMAGES]

[TEXT]
${truncateMiddle(text, limit)}
[/TEXT]

[LINKS]
${linkLines.join('\n')}
[/LINKS]''';
    } catch (error) {
      return 'WEB_FETCH_FAILED: $error';
    } finally {
      client.close(force: true);
    }
  }

  Future<String> webDeepFetch(String url,
      {int maxPages = 4, int depth = 1, int maxChars = 50000}) async {
    if (!allowInternetUse)
      return 'INTERNET_DISABLED: включите интернет-инструменты в настройках.';
    final start = url.trim();
    if (start.isEmpty) return 'url is required';
    final startUri =
        Uri.tryParse(start.contains('://') ? start : 'https://$start');
    if (startUri == null ||
        !(startUri.scheme == 'http' || startUri.scheme == 'https'))
      return 'Only http/https URLs are supported: $url';
    final pagesLimit = maxPages.clamp(1, 10).toInt();
    final depthLimit = depth.clamp(0, 3).toInt();
    final visited = <String>{};
    final queue = <MapEntry<Uri, int>>[MapEntry(startUri, 0)];
    final out = StringBuffer(
        'WEB_DEEP_FETCH_RESULT\nSTART: $startUri\nMAX_PAGES: $pagesLimit DEPTH: $depthLimit\n\n');
    while (queue.isNotEmpty &&
        visited.length < pagesLimit &&
        out.length < maxChars) {
      final item = queue.removeAt(0);
      final uri = item.key;
      final currentDepth = item.value;
      final uriText = uri.toString();
      if (visited.contains(uriText)) continue;
      visited.add(uriText);
      final page = await webFetch(uriText,
          maxChars: (maxChars ~/ pagesLimit).clamp(4000, 30000).toInt(),
          researchQuery: start);
      out.writeln('===== PAGE ${visited.length}: $uriText =====');
      out.writeln(truncateMiddle(
          page, (maxChars ~/ pagesLimit).clamp(4000, 30000).toInt()));
      out.writeln();
      if (currentDepth >= depthLimit) continue;
      for (final match in RegExp(r'=>\s*(https?://\S+)').allMatches(page)) {
        final linkText = (match.group(1) ?? '')
            .trim()
            .replaceAll(RegExp(r'[\)\]\.,]+$'), '');
        final link = Uri.tryParse(linkText);
        if (link == null || visited.contains(link.toString())) continue;
        if (link.host != startUri.host) continue;
        queue.add(MapEntry(link, currentDepth + 1));
        if (queue.length > 40) break;
      }
    }
    logAction('web_deep_fetch', {'url': start, 'pages': visited.length});
    return truncateMiddle(out.toString(), maxChars);
  }

  List<String> extractSectionLines(String text, String section) {
    final match = RegExp('\\[$section\\]([\\s\\S]*?)\\[/$section\\]',
            caseSensitive: false)
        .firstMatch(text);
    if (match == null) return const [];
    return (match.group(1) ?? '')
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  List<String> parseUrlsFromToolText(String text, {int max = 40}) {
    final urls = <String>[];
    final seen = <String>{};
    for (final match in RegExp(r'https?://[^\s\)\]\}"<>]+').allMatches(text)) {
      var url =
          (match.group(0) ?? '').trim().replaceAll(RegExp(r'[\.,;:]+$'), '');
      if (seen.add(url)) urls.add(url);
      if (urls.length >= max) break;
    }
    return urls;
  }

  bool isHighValueResearchUrl(String url) {
    final lower = url.toLowerCase();
    final markers = [
      'about',
      'contact',
      'contacts',
      'team',
      'staff',
      'people',
      'person',
      'author',
      'profile',
      'users',
      'user/',
      'vk.com',
      'facebook.com',
      'instagram.com',
      'linkedin.com',
      'github.com',
      'ok.ru',
      'youtube.com',
      't.me',
      'telegram',
      'bio',
      'biography',
      'cv',
      'resume',
      'работ',
      'сотруд',
      'команд',
      'профиль',
      'контакт',
      'о-',
      'about-us'
    ];
    return markers.any(lower.contains);
  }

  List<String> extractInterestingFollowUpQueries(String query, String pageText,
      {int max = 6}) {
    final result = <String>[];
    final seen = <String>{};
    void add(String q) {
      final clean = q.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (clean.length > 4 && seen.add(clean)) result.add(clean);
    }

    final exact = query.trim();
    for (final match in RegExp(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}',
            caseSensitive: false)
        .allMatches(pageText)) {
      add('"$exact" ${match.group(0)}');
      if (result.length >= max) return result;
    }
    for (final match
        in RegExp(r'https?://(?:www\.)?([^/\s]+)', caseSensitive: false)
            .allMatches(pageText)) {
      final host = match.group(1) ?? '';
      if (host.isNotEmpty && !host.contains('duckduckgo.com'))
        add('"$exact" site:$host');
      if (result.length >= max) return result;
    }
    final lines = pageText.split('\n');
    final keywords = [
      'работ',
      'должн',
      'компан',
      'организац',
      'университет',
      'школ',
      'родствен',
      'мать',
      'отец',
      'сын',
      'дочь',
      'жена',
      'муж',
      'друг',
      'комментар'
    ];
    for (final line in lines) {
      final lower = line.toLowerCase();
      if (!keywords.any(lower.contains)) continue;
      final short = line.trim();
      if (short.length < 8) continue;
      add('"$exact" "${truncateMiddle(short, 80).replaceAll('"', '')}"');
      if (result.length >= max) break;
    }
    return result;
  }

  String exactNameCheckReport(String query, List<String> pageTexts) {
    final tokens = extractLikelyFullNameTokens(query);
    if (tokens.length != 3) return 'EXACT_NAME_CHECK: not_applicable';
    final combined = pageTexts.join('\n').toLowerCase().replaceAll('ё', 'е');
    final hasLast = combined.contains(tokens[0]);
    final hasFirst = combined.contains(tokens[1]);
    final hasPat = combined.contains(tokens[2]);
    if (hasLast && hasFirst && hasPat)
      return 'EXACT_NAME_CHECK: confirmed_tokens_present (${tokens.join(' ')})';
    if (hasLast && hasFirst && !hasPat)
      return 'EXACT_NAME_CHECK: only_surname_and_name_found; patronymic_not_confirmed (${tokens.join(' ')})';
    return 'EXACT_NAME_CHECK: exact_full_name_not_confirmed (${tokens.join(' ')})';
  }

  Future<String> webResearch(String query,
      {int maxPages = 10, int maxDepth = 2, int maxChars = 90000}) async {
    if (!allowInternetUse)
      return 'INTERNET_DISABLED: включите интернет-инструменты в настройках.';
    final q = query.trim();
    if (q.isEmpty) return 'query is required';
    final pagesLimit = maxPages.clamp(3, 24).toInt();
    final depthLimit = maxDepth.clamp(1, 4).toInt();
    final out = StringBuffer(
        'WEB_RESEARCH_RESULT\nQUERY: $q\nMAX_PAGES: $pagesLimit DEPTH: $depthLimit\n\n');
    final visited = <String>{};
    final fetchedTexts = <String>[];
    final sources = <String>[];
    final confirmedSources = <String>[];
    final rejectedSources = <String>[];
    final researchImageLines = <String>[];
    final personTokens = extractLikelyFullNameTokens(q);
    final queue = <String>[];

    Future<void> addSearchResults(String searchQuery, String label) async {
      final search = await duckDuckGoSearch(searchQuery, maxResults: 8);
      out.writeln('===== SEARCH: $label =====');
      out.writeln(truncateMiddle(search, 12000));
      out.writeln();
      for (final url in parseUrlsFromToolText(search, max: 12)) {
        if (!visited.contains(url) && !queue.contains(url)) queue.add(url);
      }
    }

    await addSearchResults(q, 'primary');
    if (extractLikelyFullNameTokens(q).length == 3) {
      await addSearchResults('"$q"', 'exact-quote');
    }

    var depth = 0;
    while (queue.isNotEmpty &&
        visited.length < pagesLimit &&
        out.length < maxChars &&
        depth < depthLimit + 1) {
      final levelCount = queue.length;
      for (var i = 0;
          i < levelCount &&
              queue.isNotEmpty &&
              visited.length < pagesLimit &&
              out.length < maxChars;
          i++) {
        final url = queue.removeAt(0);
        if (!visited.add(url)) continue;
        final page = await webFetch(url,
            maxChars: (maxChars ~/ pagesLimit).clamp(6000, 25000).toInt(),
            researchQuery: q);
        fetchedTexts.add(page);
        sources.add(url);
        final exactMatch = personTokens.length != 3 ||
            textContainsAllNameTokens(page, personTokens);
        if (exactMatch) {
          if (!confirmedSources.contains(url)) confirmedSources.add(url);
        } else {
          if (!rejectedSources.contains(url)) rejectedSources.add(url);
        }
        for (final imageLine in extractSectionLines(page, 'IMAGES')) {
          if (exactMatch && !researchImageLines.contains(imageLine))
            researchImageLines.add(imageLine);
        }
        out.writeln('===== PAGE ${visited.length}: $url =====');
        out.writeln(
            'MATCH_TO_QUERY: ${exactMatch ? 'confirmed_or_not_person_query' : 'rejected_for_exact_person_mismatch'}');
        out.writeln(truncateMiddle(
            page, (maxChars ~/ pagesLimit).clamp(6000, 25000).toInt()));
        out.writeln();
        for (final link in parseUrlsFromToolText(page, max: 80)) {
          if (visited.contains(link) || queue.contains(link)) continue;
          if (isHighValueResearchUrl(link) ||
              Uri.tryParse(link)?.host == Uri.tryParse(url)?.host)
            queue.add(link);
          if (queue.length > 80) break;
        }
        for (final follow
            in extractInterestingFollowUpQueries(q, page, max: 3)) {
          if (visited.length + queue.length >= pagesLimit * 3) break;
          final search = await duckDuckGoSearch(follow, maxResults: 4);
          out.writeln('===== FOLLOW-UP SEARCH: $follow =====');
          out.writeln(truncateMiddle(search, 6000));
          out.writeln();
          for (final link in parseUrlsFromToolText(search, max: 6)) {
            if (!visited.contains(link) && !queue.contains(link))
              queue.add(link);
          }
        }
      }
      depth++;
    }

    out.writeln('===== QUALITY / SOURCE CHECK =====');
    out.writeln(exactNameCheckReport(q, fetchedTexts));
    out.writeln('SOURCES_VISITED: ${sources.length}');
    out.writeln('CONFIRMED_OR_RELEVANT_SOURCES: ${confirmedSources.length}');
    for (var i = 0; i < confirmedSources.length; i++) {
      out.writeln('${i + 1}. ${confirmedSources[i]}');
    }
    out.writeln(
        'REJECTED_SIMILAR_OR_UNCONFIRMED_SOURCES: ${rejectedSources.length}');
    for (var i = 0; i < rejectedSources.length; i++) {
      out.writeln('${i + 1}. ${rejectedSources[i]}');
    }
    out.writeln('[RELEVANT_IMAGES]');
    out.writeln(researchImageLines.take(12).join('\n'));
    out.writeln('[/RELEVANT_IMAGES]');
    out.writeln(
        'FINAL_INSTRUCTION: Составь итог только по подтверждённым фактам и CONFIRMED_OR_RELEVANT_SOURCES. Не включай REJECTED_SIMILAR_OR_UNCONFIRMED_SOURCES в список источников как подходящие; можно упомянуть их только в отдельном разделе «Отсеянные похожие совпадения». Удали дубли ссылок. Если точное совпадение не подтверждено, честно напиши это. Изображения выводи только из RELEVANT_IMAGES и только как предположительно относящиеся к запросу.');
    logAction('web_research', {'query': q, 'pages': sources.length});
    return truncateMiddle(out.toString(), maxChars);
  }

  Future<String> filesystemSearch(String query,
      {String rootPath = '', int maxResults = 40}) async {
    if (!allowComputerSearch && permissionMode != PermissionMode.fullAccess)
      return 'COMPUTER_SEARCH_DISABLED: поиск по компьютеру запрещён в правах проекта.';
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return 'query is required';
    final roots = <Directory>[];
    if (rootPath.trim().isNotEmpty) {
      roots.add(Directory(rootPath.trim()));
    } else {
      roots.add(projectsRoot);
      roots.add(toolsRoot);
      final project = currentProject;
      if (project != null) roots.add(Directory(project.path));
    }
    final allowedExt = {
      '.cpp',
      '.cc',
      '.cxx',
      '.c',
      '.h',
      '.hpp',
      '.dart',
      '.py',
      '.rs',
      '.js',
      '.ts',
      '.md',
      '.txt',
      '.cmake',
      '.json',
      '.yaml',
      '.yml',
      '.zip',
      '.7z',
      '.tar',
      '.gz',
      '.rtf',
      '.docx',
      '.xlsx',
      '.pptx',
      '.odt',
      '.ods',
      '.odp',
      '.odc',
      '.pdf',
      '.log',
      '.csv',
      '.xml'
    };
    final result = <String>[];
    final seen = <String>{};
    for (final root in roots) {
      if (!root.existsSync()) continue;
      try {
        var scanned = 0;
        for (final entity
            in root.listSync(recursive: true, followLinks: false)) {
          if (result.length >= maxResults || scanned++ > 5000) break;
          final path = entity.path;
          if (seen.contains(path)) continue;
          seen.add(path);
          final name = pathBasename(path).toLowerCase();
          if (entity is Directory) continue;
          final ext = fileExtension(path).toLowerCase();
          if (!allowedExt.contains(ext) && !name.contains(q)) continue;
          var score = name.contains(q) ? 5 : 0;
          if (score == 0 &&
              entity is File &&
              entity.lengthSync() < 8 * 1024 * 1024) {
            try {
              final text = isSupportedReadableDocumentPath(path)
                  ? (await readDeviceDocumentText(path, maxChars: 20000))
                      .toLowerCase()
                  : entity.readAsStringSync(encoding: utf8).toLowerCase();
              if (text.contains(q)) score = 3;
            } catch (_) {}
          }
          if (score > 0) result.add('- $path');
        }
      } catch (e) {
        result.add('- SEARCH_ERROR in ${root.path}: $e');
      }
    }
    logAction('filesystem_search', {'query': query, 'results': result.length});
    if (result.isEmpty) return 'FILESYSTEM_SEARCH_NO_RESULTS: $query';
    return 'FILESYSTEM_SEARCH_RESULTS for "$query"\n${result.take(maxResults).join('\n')}';
  }

  File knowledgeBaseFile() =>
      File(pathJoin(configRoot.path, 'knowledge_base.jsonl'));

  Future<String> knowledgeStore(String topic, String content,
      {String source = '', String tags = ''}) async {
    final cleanTopic = topic.trim();
    final cleanContent = content.trim();
    if (cleanTopic.isEmpty || cleanContent.isEmpty)
      return 'topic and content are required';
    await configRoot.create(recursive: true);
    final record = {
      'time': DateTime.now().toIso8601String(),
      'topic': cleanTopic,
      'content': cleanContent,
      'source': source.trim(),
      'tags': tags.trim(),
    };
    await knowledgeBaseFile().writeAsString('${jsonEncode(record)}\n',
        mode: FileMode.append, encoding: utf8);
    logAction('knowledge_store',
        {'topic': cleanTopic, 'source': source, 'tags': tags});
    return 'KNOWLEDGE_STORED: $cleanTopic';
  }

  Future<List<Map<String, dynamic>>> readKnowledgeRecords() async {
    final file = knowledgeBaseFile();
    if (!await file.exists()) return <Map<String, dynamic>>[];
    final records = <Map<String, dynamic>>[];
    for (final line in await file.readAsLines(encoding: utf8)) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<String, dynamic>) records.add(decoded);
      } catch (_) {}
    }
    return records;
  }

  Future<String> knowledgeSearch(String query, {int maxResults = 8}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return 'query is required';
    final terms = q.split(RegExp(r'\s+')).where((e) => e.length > 1).toList();
    final scored = <MapEntry<int, Map<String, dynamic>>>[];
    for (final record in await readKnowledgeRecords()) {
      final text =
          '${record['topic']} ${record['content']} ${record['tags']} ${record['source']}'
              .toLowerCase();
      var score = text.contains(q) ? 10 : 0;
      for (final term in terms) {
        if (text.contains(term)) score++;
      }
      if (score > 0) scored.add(MapEntry(score, record));
    }
    scored.sort((a, b) => b.key.compareTo(a.key));
    if (scored.isEmpty) return 'KNOWLEDGE_NO_RESULTS: $query';
    final lines = <String>[];
    for (final item in scored.take(maxResults)) {
      final r = item.value;
      lines.add(
          'TOPIC: ${r['topic']}\nSOURCE: ${r['source'] ?? ''}\nTAGS: ${r['tags'] ?? ''}\n${truncateMiddle((r['content'] ?? '').toString(), 2500)}');
    }
    return 'KNOWLEDGE_SEARCH_RESULTS for "$query"\n\n${lines.join('\n\n---\n\n')}';
  }

  Future<String> exportKnowledgeBase() async {
    await configRoot.create(recursive: true);
    final source = knowledgeBaseFile();
    if (!await source.exists()) await source.writeAsString('', encoding: utf8);
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final exportDir = Directory(pathJoin(configRoot.path, 'exports'));
    await exportDir.create(recursive: true);
    final jsonl = File(pathJoin(exportDir.path, 'knowledge_base_$stamp.jsonl'));
    await source.copy(jsonl.path);
    final zipPath = pathJoin(exportDir.path, 'knowledge_base_$stamp.zip');
    try {
      if (Platform.isWindows) {
        await Process.run('powershell', [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          'Compress-Archive -LiteralPath "${jsonl.path}" -DestinationPath "$zipPath" -Force'
        ]).timeout(const Duration(minutes: 2));
      } else {
        await Process.run('zip', ['-j', zipPath, jsonl.path])
            .timeout(const Duration(minutes: 2));
      }
      if (File(zipPath).existsSync()) return 'KNOWLEDGE_EXPORTED_ZIP: $zipPath';
    } catch (_) {}
    return 'KNOWLEDGE_EXPORTED_JSONL: ${jsonl.path}';
  }

  Future<String> importKnowledgeBase(String sourcePath) async {
    final source = File(sourcePath.trim());
    if (!await source.exists())
      return 'KNOWLEDGE_IMPORT_FAILED: file not found: $sourcePath';
    await configRoot.create(recursive: true);
    final target = knowledgeBaseFile();
    final lower = source.path.toLowerCase();
    try {
      if (lower.endsWith('.jsonl') || lower.endsWith('.txt')) {
        final text = await source.readAsString(encoding: utf8);
        await target.writeAsString(text.endsWith('\n') ? text : '$text\n',
            mode: FileMode.append, encoding: utf8);
        return 'KNOWLEDGE_IMPORTED_JSONL: ${source.path}';
      }
      if (lower.endsWith('.zip')) {
        final temp =
            Directory(pathJoin(configRoot.path, 'knowledge_import_tmp'));
        if (temp.existsSync()) await temp.delete(recursive: true);
        await temp.create(recursive: true);
        if (Platform.isWindows) {
          await Process.run('powershell', [
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-Command',
            'Expand-Archive -LiteralPath "${source.path}" -DestinationPath "${temp.path}" -Force'
          ]).timeout(const Duration(minutes: 2));
        } else {
          await Process.run('unzip', ['-o', source.path, '-d', temp.path])
              .timeout(const Duration(minutes: 2));
        }
        var imported = 0;
        for (final f in temp.listSync(recursive: true).whereType<File>()) {
          if (!f.path.toLowerCase().endsWith('.jsonl') &&
              !f.path.toLowerCase().endsWith('.txt')) continue;
          final text = await f.readAsString(encoding: utf8);
          await target.writeAsString(text.endsWith('\n') ? text : '$text\n',
              mode: FileMode.append, encoding: utf8);
          imported++;
        }
        return imported == 0
            ? 'KNOWLEDGE_IMPORT_FAILED: zip does not contain jsonl/txt'
            : 'KNOWLEDGE_IMPORTED_ZIP: $imported file(s) from ${source.path}';
      }
      return 'KNOWLEDGE_IMPORT_FAILED: supported formats are .zip, .jsonl, .txt';
    } catch (e) {
      return 'KNOWLEDGE_IMPORT_FAILED: $e';
    }
  }

  Future<String> downloadToProject(String url, String relativePath) async {
    if (!allowInternetUse)
      return 'INTERNET_DISABLED: включите интернет-инструменты в настройках.';
    final root = currentProject;
    if (root == null) return 'No project';
    if (url.trim().isEmpty) return 'url is required';
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https'))
      return 'Only http/https URLs are supported: $url';
    final destRel = relativePath.trim().isEmpty
        ? pathJoin('downloads', guessFileNameFromUrl(url))
        : relativePath.trim();
    if (isAgentInternalRelativePath(destRel))
      return reservedAgentPathMessage(destRel, action: 'download_to_project');
    final destPath = resolveProjectPath(root.path, destRel);
    final destFile = File(destPath);
    await destFile.parent.create(recursive: true);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final request =
          await client.getUrl(uri).timeout(const Duration(seconds: 30));
      request.headers
          .set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 AI-Agent/$appVersion');
      final response =
          await request.close().timeout(const Duration(minutes: 3));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return 'DOWNLOAD_TO_PROJECT_FAILED: HTTP ${response.statusCode} for $url';
      }
      final sink = destFile.openWrite();
      var bytes = 0;
      await for (final chunk in response.timeout(const Duration(minutes: 20))) {
        bytes += chunk.length;
        sink.add(chunk);
      }
      await sink.close();
      recordFileChange(
          destRel, '', '[downloaded binary/text file: $bytes bytes]');
      taskFileMutations++;
      logAction(
          'download_to_project', {'url': url, 'dest': destRel, 'bytes': bytes});
      return 'DOWNLOADED_TO_PROJECT: $destRel\nBYTES: $bytes\nNEXT: inspect/read/extract/connect this file, then build/test the project.';
    } finally {
      client.close(force: true);
    }
  }

  Future<String> inspectZip(String rawPath) async {
    final path = resolvePossiblyRelativePath(rawPath);
    if (path.isEmpty) return 'path is required';
    if (!await File(path).exists()) return 'ZIP not found: $rawPath';
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS))
      return 'inspect_zip currently needs desktop tar/unzip support.';
    try {
      final result = await Process.run('tar', ['-tf', path])
          .timeout(const Duration(minutes: 2));
      return 'exit code: ${result.exitCode}\n${result.stdout}\n${result.stderr}';
    } catch (error) {
      return 'inspect_zip failed: $error';
    }
  }

  Future<String> extractZip(String rawPath, String rawDest) async {
    final path = resolvePossiblyRelativePath(rawPath);
    final dest = resolvePossiblyRelativePath(
        rawDest.trim().isEmpty ? 'extracted' : rawDest);
    if (path.isEmpty) return 'path is required';
    if (!await File(path).exists()) return 'ZIP not found: $rawPath';
    await Directory(dest).create(recursive: true);
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS))
      return 'extract_zip currently needs desktop tar/unzip support.';
    try {
      final result = await Process.run('tar', ['-xf', path, '-C', dest])
          .timeout(const Duration(minutes: 5));
      return 'exit code: ${result.exitCode}\nExtracted to: $dest\n${result.stdout}\n${result.stderr}';
    } catch (error) {
      return 'extract_zip failed: $error';
    }
  }

  Future<String> readDocumentStructure(String rawPath,
      {int maxChars = 30000}) async {
    final path = resolveDevicePath(rawPath);
    if (path.isEmpty) return 'READ_DOCUMENT_STRUCTURE_FAILED: path is required';
    if (!allowDeviceFileAccess &&
        permissionMode != PermissionMode.fullAccess &&
        !isPathInsideAllowedSandbox(path))
      return 'DEVICE_FILE_ACCESS_DENIED: $rawPath';
    final result = await const office.OfficeDocumentParser().parseFile(path);
    logAction('document_read_structure', {
      'path': path,
      'format': result.kind.label,
      'chars': result.text.length
    });
    return 'READ_DOCUMENT_STRUCTURE_RESULT\n${result.toAgentText(maxTextChars: maxChars)}';
  }

  Future<String> createDocumentFromText(String rawPath, String text) async {
    final path = resolveDevicePath(rawPath);
    if (path.isEmpty) return 'CREATE_DOCUMENT_FAILED: path is required';
    if (!allowDeviceFileAccess &&
        permissionMode != PermissionMode.fullAccess &&
        !isPathInsideAllowedSandbox(path))
      return 'DEVICE_FILE_ACCESS_DENIED: $rawPath';
    if (text.trim().isEmpty) return 'CREATE_DOCUMENT_FAILED: text is empty';
    final result =
        await const office.OfficeDocumentBuilder().buildFromText(path, text);
    taskFileMutations++;
    final project = currentProject;
    final displayPath = project == null || !isPathInsideAllowedSandbox(path)
        ? path
        : pathRelative(project.path, path);
    pendingFileChanges.add(FileChangeSummary(
        path: displayPath,
        addedLines: text.split(RegExp(r'\r?\n')).length,
        removedLines: 0,
        diff:
            'Binary/document file created: ${result.kind.label}, ${result.bytes} bytes'));
    logAction('document_create',
        {'path': path, 'format': result.kind.label, 'bytes': result.bytes});
    return 'CREATE_DOCUMENT_RESULT\nPATH: $path\nFORMAT: ${result.kind.label}\nBYTES: ${result.bytes}\nMESSAGE: ${result.message}';
  }

  Future<String> editDocumentText(String rawPath,
      {required String mode, required String text, String oldText = ''}) async {
    final path = resolveDevicePath(rawPath);
    if (path.isEmpty) return 'EDIT_DOCUMENT_FAILED: path is required';
    if (!allowDeviceFileAccess &&
        permissionMode != PermissionMode.fullAccess &&
        !isPathInsideAllowedSandbox(path))
      return 'DEVICE_FILE_ACCESS_DENIED: $rawPath';
    final editMode = switch (mode.trim().toLowerCase()) {
      'replace_all' ||
      'replaceall' ||
      'replace' =>
        office.DocumentEditMode.replaceAll,
      'append' || 'append_text' => office.DocumentEditMode.appendText,
      'prepend' || 'prepend_text' => office.DocumentEditMode.prependText,
      'replace_text' ||
      'replace_text_in_document' =>
        office.DocumentEditMode.replaceText,
      _ => office.DocumentEditMode.replaceText,
    };
    final result = await const office.OfficeDocumentEditor()
        .editText(path: path, mode: editMode, newText: text, oldText: oldText);
    if (result.changed) {
      taskFileMutations++;
      final project = currentProject;
      final displayPath = project == null || !isPathInsideAllowedSandbox(path)
          ? path
          : pathRelative(project.path, path);
      pendingFileChanges.add(FileChangeSummary(
          path: displayPath,
          addedLines: text.split(RegExp(r'\r?\n')).length,
          removedLines:
              oldText.isEmpty ? 0 : oldText.split(RegExp(r'\r?\n')).length,
          diff:
              'Binary/document file edited: ${result.kind.label}\nMode: ${editMode.name}\n${result.message}'));
    }
    logAction('document_edit', {
      'path': path,
      'format': result.kind.label,
      'changed': result.changed,
      'mode': editMode.name,
      'message': result.message
    });
    return 'EDIT_DOCUMENT_RESULT\nPATH: $path\nFORMAT: ${result.kind.label}\nCHANGED: ${result.changed}\nMODE: ${editMode.name}\nMESSAGE: ${result.message}';
  }

  Future<String> readDocxText(String rawPath) async {
    final path = resolvePossiblyRelativePath(rawPath);
    if (path.isEmpty) return 'path is required';
    if (!await File(path).exists()) return 'DOCX not found: $rawPath';
    final project = currentProject;
    if (project == null) return 'No project';
    final tmp = Directory(pathJoin(project.path, '.cppagent',
        'tmp_docx_${DateTime.now().millisecondsSinceEpoch}'));
    await tmp.create(recursive: true);
    final extracted = await extractZip(path, tmp.path);
    final documentXml = File(pathJoin(tmp.path, 'word', 'document.xml'));
    if (!await documentXml.exists())
      return '$extracted\nword/document.xml not found';
    final xml = await documentXml.readAsString(
        encoding: const Utf8Codec(allowMalformed: true));
    final text = xml
        .replaceAll(RegExp(r'<w:tab\b[^>]*/>'), '\t')
        .replaceAll(RegExp(r'</w:p>'), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
    return truncateMiddle(text.trim(), 24000);
  }

  Future<String> readXlsxText(String rawPath) async {
    final path = resolvePossiblyRelativePath(rawPath);
    if (path.isEmpty) return 'path is required';
    if (!await File(path).exists()) return 'XLSX not found: $rawPath';
    final project = currentProject;
    if (project == null) return 'No project';
    final tmp = Directory(pathJoin(project.path, '.cppagent',
        'tmp_xlsx_${DateTime.now().millisecondsSinceEpoch}'));
    await tmp.create(recursive: true);
    final extracted = await extractZip(path, tmp.path);
    final sharedStrings = <String>[];
    final shared = File(pathJoin(tmp.path, 'xl', 'sharedStrings.xml'));
    if (await shared.exists()) {
      final xml = await shared.readAsString(
          encoding: const Utf8Codec(allowMalformed: true));
      for (final m
          in RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true).allMatches(xml)) {
        sharedStrings.add(m
            .group(1)!
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&amp;', '&'));
      }
    }
    final sheets = Directory(pathJoin(tmp.path, 'xl', 'worksheets'));
    if (!await sheets.exists()) return '$extracted\nxl/worksheets not found';
    final buffer = StringBuffer();
    for (final file in sheets
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.xml'))) {
      buffer.writeln('## ${pathBasename(file.path)}');
      final xml = await file.readAsString(
          encoding: const Utf8Codec(allowMalformed: true));
      for (final c in RegExp(r'<c[^>]*?(?:t="s")?[^>]*>.*?<v>(.*?)</v>.*?</c>',
              dotAll: true)
          .allMatches(xml)) {
        final raw = c.group(1) ?? '';
        final idx = int.tryParse(raw);
        buffer.writeln(idx != null && idx >= 0 && idx < sharedStrings.length
            ? sharedStrings[idx]
            : raw);
      }
    }
    return truncateMiddle(buffer.toString().trim(), 24000);
  }

  List<TreeEntry> projectTreeEntries() {
    final project = currentProject;
    if (project == null) return [];
    final root = Directory(project.path);
    if (!root.existsSync()) return [];
    final entries = <TreeEntry>[];
    void walk(Directory dir, int depth) {
      final children = dir.listSync()
        ..sort((a, b) {
          final aDir = a is Directory;
          final bDir = b is Directory;
          if (aDir != bDir) return aDir ? -1 : 1;
          return pathBasename(a.path)
              .toLowerCase()
              .compareTo(pathBasename(b.path).toLowerCase());
        });
      for (final child in children) {
        final name = pathBasename(child.path);
        if (name == '.dart_tool' || name == 'build') continue;
        final relative = pathRelative(project.path, child.path);
        entries.add(TreeEntry(
            name: name,
            relativePath: relative,
            isDirectory: child is Directory,
            depth: depth));
        if (child is Directory) walk(child, depth + 1);
      }
    }

    walk(root, 0);
    return entries;
  }

  bool parseBoolString(String value) {
    final v = value.trim().toLowerCase();
    return v == 'true' || v == '1' || v == 'yes' || v == 'да';
  }

  String normalizeDevicePathInput(String rawPath) {
    var value = rawPath.trim();
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }
    return value;
  }

  String resolveDevicePath(String rawPath) {
    final value = normalizeDevicePathInput(rawPath);
    if (value.isEmpty) return value;
    if (isAbsolutePath(value)) return value;
    final project = currentProject;
    if (project == null) return value;
    return resolveProjectPath(project.path, value);
  }

  bool isSupportedReadableDocumentPath(String path) {
    final lower = path.toLowerCase();
    const ext = [
      '.txt',
      '.md',
      '.json',
      '.yaml',
      '.yml',
      '.dart',
      '.py',
      '.cpp',
      '.h',
      '.hpp',
      '.c',
      '.cs',
      '.js',
      '.ts',
      '.html',
      '.htm',
      '.css',
      '.bat',
      '.ps1',
      '.sh',
      '.xml',
      '.gradle',
      '.log',
      '.ini',
      '.cfg',
      '.csv',
      '.rtf',
      '.docx',
      '.xlsx',
      '.pptx',
      '.ppts',
      '.odt',
      '.ods',
      '.odp',
      '.odc',
      '.doc',
      '.xls',
      '.ppt',
      '.pdf'
    ];
    return ext.any(lower.endsWith) || !pathBasename(path).contains('.');
  }

  bool isSupportedArchivePath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.zip') ||
        lower.endsWith('.7z') ||
        lower.endsWith('.rar');
  }

  bool isLikelyTextFilePath(String path) =>
      isSupportedReadableDocumentPath(path);

  String stripRtfToText(String rtf) {
    var text = rtf.replaceAll(RegExp(r'\\par[d]?'), '\n');
    text = text.replaceAll(RegExp(r'\\tab'), '\t');
    text = text.replaceAll(RegExp(r"\\'[0-9a-fA-F]{2}"), ' ');
    text = text.replaceAll(RegExp(r'\\[a-zA-Z]+-?\d* ?'), ' ');
    text = text.replaceAll(RegExp(r'[{}]'), ' ');
    return text
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String cleanExtractedText(String text) {
    var cleaned = text
        .replaceAll('\u0000', '')
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]+'), ' ')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .replaceAll(RegExp(r'\n{4,}'), '\n\n\n')
        .trim();
    if (cleaned.isEmpty) return '';
    final letters = RegExp(r'[A-Za-zА-Яа-яЁё]').allMatches(cleaned).length;
    final bad = RegExp(r'[�□■▒▓╨╤]').allMatches(cleaned).length;
    final visible = RegExp(r'\S').allMatches(cleaned).length;
    if (visible > 0 &&
        (letters < math.min(12, visible ~/ 8) || bad > visible / 8)) return '';
    return cleaned;
  }

  String decodeBytesSmart(List<int> bytes) {
    final utf8Text =
        cleanExtractedText(utf8.decode(bytes, allowMalformed: true));
    if (utf8Text.isNotEmpty) return utf8Text;
    if (bytes.length > 4) {
      final evenZeros = <int>[
        for (var i = 1; i < bytes.length && i < 20000; i += 2)
          if (bytes[i] == 0) 1
      ].length;
      if (evenZeros > 100) {
        try {
          final units = <int>[];
          for (var i = 0; i + 1 < bytes.length; i += 2)
            units.add(bytes[i] | (bytes[i + 1] << 8));
          final u16 = cleanExtractedText(String.fromCharCodes(units));
          if (u16.isNotEmpty) return u16;
        } catch (_) {}
      }
    }
    return cleanExtractedText(latin1.decode(bytes, allowInvalid: true));
  }

  Future<String> extractPdfTextBestEffort(String path, List<int> bytes) async {
    final pdftotext = findExecutableInTools(['pdftotext.exe', 'pdftotext']);
    if (pdftotext != null) {
      try {
        final result = await Process.run(
                pdftotext.path, ['-layout', '-enc', 'UTF-8', path, '-'],
                stdoutEncoding: const Utf8Codec(allowMalformed: true),
                stderrEncoding: const Utf8Codec(allowMalformed: true))
            .timeout(const Duration(seconds: 20));
        final text = cleanExtractedText(result.stdout.toString());
        if (result.exitCode == 0 && text.isNotEmpty) return text;
      } catch (_) {}
    }
    final raw = latin1.decode(bytes, allowInvalid: true);
    final buffer = StringBuffer();
    for (final m in RegExp(r'\((?:\\.|[^\\)]){2,}\)').allMatches(raw)) {
      var value = m.group(0) ?? '';
      value = value
          .substring(1, value.length - 1)
          .replaceAll(r'\(', '(')
          .replaceAll(r'\)', ')')
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\r', '\n')
          .replaceAll(r'\t', '\t');
      final cleaned = cleanExtractedText(value);
      if (cleaned.length >= 2) buffer.writeln(cleaned);
    }
    final text = cleanExtractedText(buffer.toString());
    if (text.isNotEmpty) return text;
    return 'PDF_TEXT_NOT_EXTRACTED: PDF может содержать сжатый текст/сканы. Для качественного извлечения положите pdftotext в папку tools или используйте OCR/Tesseract.';
  }

  String extractBinaryStringsBestEffort(
      List<int> bytes, String extensionLabel) {
    final decoded = decodeBytesSmart(bytes);
    if (decoded.length >= 30) return decoded;
    return '${extensionLabel.toUpperCase()}_TEXT_NOT_EXTRACTED: старый бинарный формат Office не удалось корректно разобрать без внешнего конвертера. Файл не выведен каракулями.';
  }

  Future<String> readPptxText(String rawPath) async {
    final path = resolvePossiblyRelativePath(rawPath);
    if (path.isEmpty) return 'path is required';
    if (!await File(path).exists()) return 'PPTX not found: $rawPath';
    final project = currentProject;
    if (project == null) return 'No project';
    final tmp = Directory(pathJoin(project.path, '.cppagent',
        'tmp_pptx_${DateTime.now().millisecondsSinceEpoch}'));
    await tmp.create(recursive: true);
    final extracted = await extractZip(path, tmp.path);
    final slides = Directory(pathJoin(tmp.path, 'ppt', 'slides'));
    if (!await slides.exists()) return '$extracted\nppt/slides not found';
    final buffer = StringBuffer();
    final files = slides
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.xml'))
        .toList()
      ..sort((a, b) => pathBasename(a.path).compareTo(pathBasename(b.path)));
    for (final file in files) {
      buffer.writeln('## ${pathBasename(file.path)}');
      final xml = await file.readAsString(
          encoding: const Utf8Codec(allowMalformed: true));
      for (final m
          in RegExp(r'<a:t[^>]*>(.*?)</a:t>', dotAll: true).allMatches(xml)) {
        buffer.writeln(htmlEntityDecodeBasic(m.group(1) ?? ''));
      }
      buffer.writeln();
    }
    return truncateMiddle(buffer.toString().trim(), 24000);
  }

  Future<String> readDeviceDocumentText(String path,
      {int maxChars = 30000}) async {
    final lower = path.toLowerCase();
    final file = File(path);
    if (!await file.exists()) return 'File not found: $path';
    final size = await file.length();
    if (size > 80 * 1024 * 1024)
      return 'File is too large for text extraction: $path ($size bytes)';
    try {
      if (office.isStructuredOfficeDocumentPath(path)) {
        final parsed =
            await const office.OfficeDocumentParser().parseFile(path);
        return truncateMiddle(parsed.text.trim(), maxChars);
      }
      final bytes = await file.readAsBytes();
      String text;
      if (lower.endsWith('.pdf')) {
        text = await extractPdfTextBestEffort(path, bytes);
      } else if (lower.endsWith('.doc') ||
          lower.endsWith('.xls') ||
          lower.endsWith('.ppt')) {
        text = extractBinaryStringsBestEffort(bytes, lower.split('.').last);
      } else {
        text = decodeBytesSmart(bytes);
      }
      return truncateMiddle(text.trim(), maxChars);
    } catch (error) {
      return 'TEXT_EXTRACT_ERROR: $error';
    }
  }

  bool shouldSkipDeviceDirectory(String path) {
    final name = pathBasename(path).toLowerCase();
    return name == r'$recycle.bin' ||
        name == 'system volume information' ||
        name == '.trash' ||
        name == '.git' ||
        name == 'node_modules' ||
        name == '.gradle' ||
        name == 'build';
  }

  List<FileSystemEntity> listDeviceEntriesSafe(Directory root,
      {bool recursive = true, int maxResults = 1000}) {
    final result = <FileSystemEntity>[];
    final skipped = <String>[];
    void walk(Directory dir) {
      if (result.length >= maxResults) return;
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(recursive: false, followLinks: false);
      } catch (error) {
        skipped.add('${dir.path}: $error');
        return;
      }
      entries.sort((a, b) => pathBasename(a.path)
          .toLowerCase()
          .compareTo(pathBasename(b.path).toLowerCase()));
      for (final entry in entries) {
        if (result.length >= maxResults) return;
        result.add(entry);
        if (recursive &&
            entry is Directory &&
            !shouldSkipDeviceDirectory(entry.path)) {
          walk(entry);
        }
      }
    }

    walk(root);
    if (skipped.isNotEmpty) {
      log('DEVICE SAFE LIST SKIPPED: ${truncateMiddle(skipped.join('\n'), 4000)}');
    }
    return result;
  }

  List<String> extractDocumentSearchTerms(String query) {
    final normalized = query
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zа-яё0-9]+', caseSensitive: false), ' ');
    final stop = <String>{
      'найди',
      'найти',
      'нади',
      'поищи',
      'поиск',
      'информацию',
      'информация',
      'документ',
      'документы',
      'папке',
      'компьютере',
      'компьютеру',
      'устройстве',
      'содержащие',
      'содержащих',
      'подпапках',
      'который',
      'которая',
      'которые',
      'напиши',
      'полное',
      'полоное',
      'название',
      'датой',
      'дата',
      'утверждения',
      'требования',
      'требонания',
      'определяет',
      'какими',
      'пунктами',
      'пункты',
      'слово',
      'слова',
      'из',
      'по',
      'и',
      'в',
      'на',
      'о',
      'об',
      'для',
      'что',
      'ее',
      'её',
      'его'
    };
    final terms = normalized
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 4 && !stop.contains(w))
        .toSet()
        .toList();
    if (normalized.contains('закуп'))
      terms.addAll([
        'закуп',
        'закупк',
        'закупок',
        'поставка',
        'поставк',
        'контракт',
        'договор',
        'требован'
      ]);
    return terms.toSet().toList(growable: false);
  }

  int scoreDocumentForQuery(String path, String text, List<String> terms) {
    final hay = ('${pathBasename(path)}\n$text').toLowerCase();
    var score = 0;
    for (final term in terms) {
      if (hay.contains(term)) score += term.contains('закуп') ? 8 : 3;
    }
    if (hay.contains('дата утверждения') ||
        hay.contains('утвержден') ||
        hay.contains('утверждён')) score += 4;
    if (hay.contains('требования')) score += 5;
    if (hay.contains('пункт') || RegExp(r'\b\d+(?:\.\d+)+\b').hasMatch(hay))
      score += 3;
    return score;
  }

  Future<String> searchDeviceDocuments(String rawPath, String query,
      {bool recursive = true,
      int maxFiles = 120,
      int maxCharsPerFile = 60000}) async {
    final path = resolveDevicePath(rawPath);
    if (path.isEmpty) return 'SEARCH_DEVICE_DOCUMENTS_FAILED: path is required';
    if (!allowDeviceFileAccess && !isPathInsideAllowedSandbox(path))
      return 'DEVICE_FILE_ACCESS_DENIED: $rawPath';
    final dir = Directory(path);
    if (!await dir.exists())
      return 'SEARCH_DEVICE_DOCUMENTS_FAILED: directory not found: $path';
    lastDeviceDirectoryPath = path;
    final terms = extractDocumentSearchTerms(query);
    final entries = listDeviceEntriesSafe(dir,
        recursive: recursive, maxResults: math.max(maxFiles * 8, 500));
    final files = entries
        .whereType<File>()
        .where((f) =>
            isSupportedReadableDocumentPath(f.path) ||
            isSupportedArchivePath(f.path))
        .take(maxFiles)
        .toList(growable: false);
    final scored = <Map<String, Object>>[];
    var inspected = 0;
    for (final file in files) {
      inspected++;
      if (isSupportedArchivePath(file.path)) {
        final project = currentProject;
        if (project == null) continue;
        final tmp = Directory(pathJoin(project.path, '.cppagent',
            'search_archive_${DateTime.now().millisecondsSinceEpoch}_$inspected'));
        final extracted = await extractArchiveForDeviceRead(file, tmp);
        for (final inner in extracted
            .where((f) => isSupportedReadableDocumentPath(f.path))
            .take(20)) {
          final innerText = await readDeviceDocumentText(inner.path,
              maxChars: maxCharsPerFile);
          final score = scoreDocumentForQuery(
              '${file.path}:${pathBasename(inner.path)}', innerText, terms);
          if (score > 0)
            scored.add({
              'path': '${file.path}:${pathBasename(inner.path)}',
              'score': score,
              'text': innerText
            });
        }
        continue;
      }
      final text =
          await readDeviceDocumentText(file.path, maxChars: maxCharsPerFile);
      final score = scoreDocumentForQuery(file.path, text, terms);
      if (score > 0)
        scored.add({'path': file.path, 'score': score, 'text': text});
    }
    scored.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
    final buffer = StringBuffer(
        'SEARCH_DEVICE_DOCUMENTS_RESULT\nPATH: $path\nQUERY: $query\nINSPECTED_FILES: $inspected\nTERMS: ${terms.join(', ')}\n');
    if (scored.isEmpty) {
      buffer.writeln(
          'MATCHES: 0\nРелевантные документы не найдены. Недоступные системные папки пропущены без остановки поиска.');
      return buffer.toString();
    }
    buffer.writeln('MATCHES: ${scored.length}\n');
    for (final item in scored.take(8)) {
      final itemPath = item['path'].toString();
      final score = item['score'];
      final text = item['text'].toString();
      buffer.writeln('===== SCORE $score :: $itemPath =====');
      buffer.writeln(extractRelevantSnippets(text, terms, maxSnippets: 8));
      buffer.writeln();
    }
    return buffer.toString();
  }

  String extractRelevantSnippets(String text, List<String> terms,
      {int maxSnippets = 6}) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final picked = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final lower = lines[i].toLowerCase();
      if (terms.any(lower.contains) ||
          lower.contains('требован') ||
          lower.contains('утвержд')) {
        final start = math.max(0, i - 1);
        final end = math.min(lines.length, i + 3);
        final snippet = lines.sublist(start, end).join('\n');
        if (!picked.contains(snippet)) picked.add(snippet);
      }
      if (picked.length >= maxSnippets) break;
    }
    if (picked.isEmpty) return truncateMiddle(text.trim(), 4000);
    return picked
        .map((s) => '```text\n${truncateMiddle(s, 5000)}\n```')
        .join('\n');
  }

  String listDeviceDirectory(String rawPath,
      {bool recursive = false, int maxResults = 200}) {
    final path = resolveDevicePath(rawPath);
    if (path.isEmpty) return 'path is required';
    if (!allowDeviceFileAccess && !isPathInsideAllowedSandbox(path))
      return 'DEVICE_FILE_ACCESS_DENIED: $rawPath';
    lastDeviceDirectoryPath = path;
    final dir = Directory(path);
    if (!dir.existsSync()) return 'Directory not found: $path';
    final buffer = StringBuffer('DEVICE_DIRECTORY: $path\n');
    final entries = listDeviceEntriesSafe(dir,
        recursive: recursive, maxResults: maxResults + 1);
    var count = 0;
    for (final entry in entries) {
      if (count++ >= maxResults) {
        buffer.writeln('...[truncated]...');
        break;
      }
      final type = entry is Directory ? '[D]' : '[F]';
      final rel = pathRelative(path, entry.path);
      buffer.writeln('$type ${rel.isEmpty ? pathBasename(entry.path) : rel}');
    }
    return buffer.toString();
  }

  Future<String> readDeviceTextFile(String rawPath,
      {int maxChars = 30000}) async {
    final path = resolveDevicePath(rawPath);
    if (path.isEmpty) return 'path is required';
    if (!allowDeviceFileAccess && !isPathInsideAllowedSandbox(path))
      return 'DEVICE_FILE_ACCESS_DENIED: $rawPath';
    final file = File(path);
    if (!await file.exists()) return 'File not found: $path';
    final text = await readDeviceDocumentText(path, maxChars: maxChars);
    return 'DEVICE_TEXT_FILE: $path\n$text';
  }

  LocalToolInfo? findExecutableInTools(List<String> names) {
    final wanted = names.map((e) => e.toLowerCase()).toSet();
    for (final tool in scanLocalToolsSync(maxItems: 1000)) {
      if (wanted.contains(tool.name.toLowerCase())) return tool;
    }
    for (final name in names) {
      final direct = File(pathJoin(toolsRoot.path, name));
      if (direct.existsSync())
        return LocalToolInfo(
            name: name,
            path: direct.path,
            relativePath: pathRelative(toolsRoot.path, direct.path),
            kind: 'program');
    }
    return null;
  }

  Future<List<File>> extractArchiveForDeviceRead(
      File archive, Directory dest) async {
    await dest.create(recursive: true);
    final lower = archive.path.toLowerCase();
    ProcessResult? result;
    if (lower.endsWith('.zip')) {
      result = await Process.run('tar', ['-xf', archive.path, '-C', dest.path],
              stdoutEncoding: null,
              stderrEncoding: null,
              environment: buildToolAwareEnvironment())
          .timeout(const Duration(minutes: 5));
    } else if (lower.endsWith('.7z') || lower.endsWith('.rar')) {
      final sevenZip =
          findExecutableInTools(['7z.exe', '7za.exe', '7zz.exe', '7z']);
      if (sevenZip == null) return const [];
      result = await Process.run(
              sevenZip.path, ['x', '-y', '-o${dest.path}', archive.path],
              stdoutEncoding: null,
              stderrEncoding: null,
              environment: buildToolAwareEnvironment())
          .timeout(const Duration(minutes: 10));
    }
    if (result == null || result.exitCode != 0) return const [];
    return dest
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .toList(growable: false);
  }

  Future<String> readDeviceFolderTexts(String rawPath,
      {int maxFiles = 30,
      int maxCharsPerFile = 12000,
      bool recursive = true}) async {
    final path = resolveDevicePath(rawPath);
    if (path.isEmpty) return 'path is required';
    if (!allowDeviceFileAccess && !isPathInsideAllowedSandbox(path))
      return 'DEVICE_FILE_ACCESS_DENIED: $rawPath';
    lastDeviceDirectoryPath = path;
    final dir = Directory(path);
    if (!await dir.exists()) return 'Directory not found: $path';
    final files = <File>[];
    final archiveFiles = <File>[];
    try {
      for (final entry in listDeviceEntriesSafe(dir,
          recursive: recursive, maxResults: math.max(maxFiles * 4, 200))) {
        if (entry is! File) continue;
        if (isSupportedArchivePath(entry.path)) {
          archiveFiles.add(entry);
        } else if (isSupportedReadableDocumentPath(entry.path)) {
          files.add(entry);
        }
        if (files.length >= maxFiles) break;
      }
      final project = currentProject;
      if (project != null && files.length < maxFiles) {
        var archiveIndex = 0;
        for (final archive in archiveFiles) {
          if (files.length >= maxFiles) break;
          final tmp = Directory(pathJoin(project.path, '.cppagent',
              'archive_read_${DateTime.now().millisecondsSinceEpoch}_$archiveIndex'));
          archiveIndex++;
          final extracted = await extractArchiveForDeviceRead(archive, tmp);
          for (final f in extracted) {
            if (files.length >= maxFiles) break;
            if (isSupportedReadableDocumentPath(f.path)) files.add(f);
          }
        }
      }
    } catch (error) {
      return 'DEVICE_FOLDER_READ_ERROR: $error';
    }
    if (files.isEmpty)
      return 'DEVICE_FOLDER_TEXTS: $path\nПоддерживаемые текстовые/офисные/PDF файлы не найдены.';
    final buffer = StringBuffer(
        'DEVICE_FOLDER_TEXTS: $path\nFILES: ${files.length}\nSUPPORTED: txt, csv, html, xml, rtf, doc/docx, xls/xlsx, ppt/pptx, pdf, zip/7z/rar(best effort)\n');
    for (final file in files.take(maxFiles)) {
      final displayPath = file.path.startsWith(path)
          ? pathRelative(path, file.path)
          : file.path;
      buffer.writeln('\n===== $displayPath =====');
      final text =
          await readDeviceDocumentText(file.path, maxChars: maxCharsPerFile);
      buffer.writeln('```text');
      buffer.writeln(
          text.trim().isEmpty ? '(текст не извлечён или файл пуст)' : text);
      buffer.writeln('```');
    }
    return buffer.toString();
  }

  String safeArchiveFileName(String value) {
    var name = value.trim().replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]+'), '_');
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (name.isEmpty) name = 'item';
    if (name.length > 120) name = name.substring(0, 120).trim();
    return name;
  }

  String psQuote(String value) => "'${value.replaceAll("'", "''")}'";

  Future<String> archiveOneDeviceEntry(
      FileSystemEntity entry, String zipPath) async {
    await File(zipPath).parent.create(recursive: true);
    if (File(zipPath).existsSync()) await File(zipPath).delete();
    try {
      if (Platform.isWindows) {
        final command =
            "\$ErrorActionPreference='Stop'; Compress-Archive -LiteralPath ${psQuote(entry.path)} -DestinationPath ${psQuote(zipPath)} -Force";
        final result = await Process.run(
          'powershell',
          ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command],
          stdoutEncoding: const Utf8Codec(allowMalformed: true),
          stderrEncoding: const Utf8Codec(allowMalformed: true),
          environment: buildToolAwareEnvironment(),
        ).timeout(const Duration(minutes: 10));
        if (result.exitCode == 0 && File(zipPath).existsSync()) return 'OK';
        return 'ERROR exit=${result.exitCode} stdout=${truncateMiddle(result.stdout.toString(), 1000)} stderr=${truncateMiddle(result.stderr.toString(), 1000)}';
      }
      final zipTool = findExecutableInTools(['zip.exe', 'zip']);
      final zipCommand = zipTool?.path ?? 'zip';
      final parent = entry.parent.path;
      final name = pathBasename(entry.path);
      final result = await Process.run(
        zipCommand,
        ['-r', zipPath, name],
        workingDirectory: parent,
        stdoutEncoding: const Utf8Codec(allowMalformed: true),
        stderrEncoding: const Utf8Codec(allowMalformed: true),
        environment: buildToolAwareEnvironment(),
      ).timeout(const Duration(minutes: 10));
      if (result.exitCode == 0 && File(zipPath).existsSync()) return 'OK';
      return 'ERROR exit=${result.exitCode} stdout=${truncateMiddle(result.stdout.toString(), 1000)} stderr=${truncateMiddle(result.stderr.toString(), 1000)}';
    } catch (e) {
      return 'ERROR $e';
    }
  }

  Future<String> archiveDeviceChildren(String rawPath,
      {String outputPath = '', int maxItems = 200}) async {
    final sourcePath = resolveDevicePath(rawPath);
    if (sourcePath.isEmpty)
      return 'ARCHIVE_DEVICE_CHILDREN_FAILED: path is required';
    if (!allowDeviceFileAccess && !isPathInsideAllowedSandbox(sourcePath))
      return 'DEVICE_FILE_ACCESS_DENIED: $rawPath';
    final sourceDir = Directory(sourcePath);
    if (!await sourceDir.exists())
      return 'ARCHIVE_DEVICE_CHILDREN_FAILED: directory not found: $sourcePath';
    lastDeviceDirectoryPath = sourcePath;
    final outPath = outputPath.trim().isEmpty
        ? pathJoin(sourcePath, '_archives')
        : resolveDevicePath(outputPath);
    final outDir = Directory(outPath);
    await outDir.create(recursive: true);
    final entries = sourceDir
        .listSync(recursive: false, followLinks: false)
        .where(
            (e) => e.path != outDir.path && pathBasename(e.path) != '_archives')
        .toList(growable: false)
      ..sort((a, b) => pathBasename(a.path)
          .toLowerCase()
          .compareTo(pathBasename(b.path).toLowerCase()));
    if (entries.isEmpty)
      return 'ARCHIVE_DEVICE_CHILDREN_FAILED: source folder is empty: $sourcePath';
    final buffer = StringBuffer(
        'ARCHIVE_DEVICE_CHILDREN_DONE: $sourcePath\nOUTPUT: ${outDir.path}\n');
    var ok = 0;
    var failed = 0;
    var processed = 0;
    for (final entry in entries.take(maxItems)) {
      processed++;
      final name = pathBasename(entry.path);
      final zipName = '${safeArchiveFileName(name)}.zip';
      final zipPath = pathJoin(outDir.path, zipName);
      final result = await archiveOneDeviceEntry(entry, zipPath);
      if (result == 'OK') {
        ok++;
        buffer.writeln('[OK] $name -> $zipPath');
      } else {
        failed++;
        buffer.writeln('[FAILED] $name -> $zipPath :: $result');
      }
    }
    if (entries.length > maxItems)
      buffer.writeln('...[truncated ${entries.length - maxItems} item(s)]...');
    buffer.writeln('SUMMARY: processed=$processed ok=$ok failed=$failed');
    logAction('archive_device_children', {
      'source': sourcePath,
      'output': outDir.path,
      'processed': processed,
      'ok': ok,
      'failed': failed
    });
    taskCommandRuns++;
    lastCommandExitCode = failed == 0 ? 0 : 1;
    lastCommandText = 'archive_device_children $sourcePath';
    lastCommandResultText = buffer.toString();
    if (failed > 0) taskFailedCommands++;
    return buffer.toString();
  }

  Future<void> copyFileSystemEntry(String sourceRaw, String targetRaw,
      {required bool move}) async {
    final project = currentProject;
    if (project == null) return;
    final source = sourceRaw.trim();
    final target = targetRaw.trim();
    if (source.isEmpty || target.isEmpty) return;
    if (!allowDeviceFileAccess &&
        source.isNotEmpty &&
        !isPathInsideAllowedSandbox(source)) {
      log('DEVICE FILE ACCESS BLOCKED: copy source outside sandbox: $source');
      return;
    }
    if (!allowDeviceFileAccess &&
        target.isNotEmpty &&
        isAbsolutePath(target) &&
        !isPathInsideAllowedSandbox(target)) {
      log('DEVICE FILE ACCESS BLOCKED: copy target outside sandbox: $target');
      return;
    }
    final srcType = FileSystemEntity.typeSync(source);
    final dstPath = isAbsolutePath(target)
        ? target
        : resolveProjectPath(project.path, target);
    if (srcType == FileSystemEntityType.directory) {
      await copyDirectory(Directory(source), Directory(dstPath));
      if (move) await Directory(source).delete(recursive: true);
    } else if (srcType == FileSystemEntityType.file) {
      await File(dstPath).parent.create(recursive: true);
      await File(source).copy(dstPath);
      if (move) await File(source).delete();
    }
  }

  Future<void> pasteProjectEntry(String relativeSource, String targetRaw,
      {required bool move}) async {
    final project = currentProject;
    if (project == null) return;
    final source = resolveProjectPath(project.path, relativeSource);
    final cleanedTarget = targetRaw.trim();
    var target = cleanedTarget.isEmpty
        ? pathJoin(project.path, pathBasename(source))
        : (isAbsolutePath(cleanedTarget)
            ? cleanedTarget
            : resolveProjectPath(project.path, cleanedTarget));
    if (Directory(target).existsSync()) {
      target = pathJoin(target, pathBasename(source));
    }
    await copyFileSystemEntry(source, target, move: move);
  }

  Future<String> renameRelativePath(String relativePath, String newName) async {
    final project = currentProject;
    if (project == null) return 'No project';
    final sourceRel = relativePath.trim();
    final cleanedName = sanitizeFileName(newName.trim());
    if (sourceRel.isEmpty || cleanedName.isEmpty)
      return 'Path and new name are required';
    if (isAgentInternalRelativePath(sourceRel)) {
      return reservedAgentPathMessage(sourceRel, action: 'rename_path');
    }
    final source = resolveProjectPath(project.path, sourceRel);
    final type = FileSystemEntity.typeSync(source);
    if (type == FileSystemEntityType.notFound)
      return 'Path not found: $sourceRel';
    final parentRel = pathDirname(sourceRel);
    final targetRel = parentRel == '.' || parentRel.isEmpty
        ? cleanedName
        : pathJoin(parentRel, cleanedName);
    final target = resolveProjectPath(project.path, targetRel);
    if (FileSystemEntity.typeSync(target) != FileSystemEntityType.notFound) {
      return 'Target already exists: $targetRel';
    }
    if (type == FileSystemEntityType.directory) {
      await Directory(source).rename(target);
    } else {
      await File(source).rename(target);
    }
    logAction('project_path_renamed', {'from': sourceRel, 'to': targetRel});
    return 'RENAMED: $sourceRel -> $targetRel';
  }

  Future<String> importExternalEntryToProject(
      String sourceRaw, String targetDirectoryRelative) async {
    final project = currentProject;
    if (project == null) return 'No project';
    final source = sourceRaw.trim();
    if (source.isEmpty) return 'Source path is required';
    final type = FileSystemEntity.typeSync(source);
    if (type == FileSystemEntityType.notFound)
      return 'Source not found: $source';
    final targetDirRel = targetDirectoryRelative.trim();
    final targetDir = targetDirRel.isEmpty || targetDirRel == '.'
        ? project.path
        : resolveProjectPath(project.path, targetDirRel);
    final target = pathJoin(targetDir, pathBasename(source));
    await copyFileSystemEntry(source, target, move: false);
    logAction('project_path_imported', {'from': source, 'to': target});
    return 'IMPORTED: $source -> $target';
  }

  String relativePathProperties(String relativePath) {
    final project = currentProject;
    if (project == null) return 'No project';
    final rel = relativePath.trim();
    if (rel.isEmpty) return 'Path is required';
    final path = resolveProjectPath(project.path, rel);
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) return 'Path not found: $rel';
    final stat = FileStat.statSync(path);
    final kind = type == FileSystemEntityType.directory ? 'directory' : 'file';
    final size = type == FileSystemEntityType.file ? stat.size : 0;
    return [
      'PATH: $rel',
      'ABSOLUTE: $path',
      'TYPE: $kind',
      if (type == FileSystemEntityType.file) 'SIZE_BYTES: $size',
      'MODIFIED: ${stat.modified.toIso8601String()}',
      'MODE: ${stat.modeString()}',
    ].join('\n');
  }

  void recalculateContext() {
    final lastCompressionIndex = messages.lastIndexWhere((m) =>
        m.role == 'separator' &&
        m.content == 'Автоматическое сжатие контекста');
    final scopedMessages = lastCompressionIndex >= 0
        ? messages.skip(lastCompressionIndex + 1)
        : messages;
    final textSize = scopedMessages.fold<int>(
        0,
        (sum, message) => message.internal || message.transient
            ? sum
            : sum + message.content.length + message.role.length + 8);
    estimatedContextTokens = (textSize / 4).ceil();
  }
}
