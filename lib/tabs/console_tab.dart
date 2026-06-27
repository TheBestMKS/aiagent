import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/agent_controller.dart';
import '../core/runtime_types.dart';
import '../utils/html_utils.dart';
import '../utils/path_utils.dart';

class ConsoleSession {
  ConsoleSession({required this.name, this.cwd = '.', this.output = ''}) {
    cwdController.text = cwd;
  }

  String name;
  String cwd;
  String output;
  final List<String> commandHistory = [];
  final TextEditingController commandController = TextEditingController();
  final TextEditingController cwdController = TextEditingController();

  Map<String, dynamic> toJson() => {
        'name': name,
        'cwd': cwd,
        'output': output,
        'history': commandHistory.take(80).toList(),
        'command': commandController.text,
      };

  static ConsoleSession fromJson(Map<String, dynamic> json) {
    final session = ConsoleSession(
      name: json['name']?.toString() ?? 'Консоль',
      cwd: json['cwd']?.toString() ?? '.',
      output: json['output']?.toString() ?? '',
    );
    session.commandHistory.addAll((json['history'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty));
    session.commandController.text = json['command']?.toString() ?? '';
    return session;
  }

  void dispose() {
    commandController.dispose();
    cwdController.dispose();
  }
}

class ConsoleTab extends StatefulWidget {
  const ConsoleTab({super.key, required this.controller});

  final AgentController controller;

  @override
  State<ConsoleTab> createState() => _ConsoleTabState();
}

class _ConsoleTabState extends State<ConsoleTab> {
  final List<ConsoleSession> sessions = [ConsoleSession(name: 'Консоль 1')];
  final List<ConsoleQuickAction> quickActions = [];
  final ScrollController verticalScrollController = ScrollController();
  final ScrollController horizontalScrollController = ScrollController();
  int selected = 0;
  bool running = false;
  bool showQuickPanel = false;
  bool stateLoaded = false;

  ConsoleSession get current =>
      sessions[selected.clamp(0, sessions.length - 1).toInt()];

  @override
  void initState() {
    super.initState();
    quickActions.addAll(defaultQuickActions());
    widget.controller.consoleRunner =
        ({required String command, String cwd = '.', bool newTab = false}) {
      if (!mounted) return;
      if (newTab) addSession();
      setState(() {
        current.cwd = cwd.trim().isEmpty ? '.' : cwd.trim();
        current.cwdController.text = current.cwd;
        current.commandController.text = command;
      });
      unawaited(run(command));
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(loadState());
      final pending = widget.controller.takePendingConsoleRun();
      if (pending != null) {
        widget.controller.consoleRunner?.call(
            command: pending.command, cwd: pending.cwd, newTab: pending.newTab);
      }
    });
  }

  @override
  void dispose() {
    if (widget.controller.consoleRunner != null) {
      widget.controller.consoleRunner = null;
    }
    unawaited(saveState());
    for (final session in sessions) {
      session.dispose();
    }
    verticalScrollController.dispose();
    horizontalScrollController.dispose();
    super.dispose();
  }

  List<ConsoleQuickAction> defaultQuickActions() => [
        ConsoleQuickAction(
            'Список файлов', Platform.isWindows ? 'dir' : 'ls -la'),
        ConsoleQuickAction('Текущая папка', Platform.isWindows ? 'cd' : 'pwd'),
        ConsoleQuickAction(
            'Процессы', Platform.isWindows ? 'tasklist' : 'ps aux | head -40'),
        ConsoleQuickAction('Создать папку',
            Platform.isWindows ? 'mkdir new_folder' : 'mkdir -p new_folder'),
      ];

  Future<void> loadState() async {
    if (stateLoaded) return;
    stateLoaded = true;
    final data = await widget.controller.loadProjectUiStateSection('console');
    if (!mounted || data.isEmpty) return;
    final loadedSessions = (data['sessions'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((m) => ConsoleSession.fromJson(
            m.map((key, value) => MapEntry(key.toString(), value))))
        .toList(growable: false);
    final loadedQuick = (data['quickActions'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((m) {
          final map = m.map((key, value) => MapEntry(key.toString(), value));
          return ConsoleQuickAction(
            map['name']?.toString() ?? 'Команда',
            map['command']?.toString() ?? '',
            cwd: map['cwd']?.toString() ?? '.',
          );
        })
        .where((a) => a.command.trim().isNotEmpty)
        .toList(growable: false);
    setState(() {
      for (final session in sessions) {
        session.dispose();
      }
      sessions
        ..clear()
        ..addAll(loadedSessions.isEmpty
            ? [ConsoleSession(name: 'Консоль 1')]
            : loadedSessions);
      quickActions
        ..clear()
        ..addAll(loadedQuick.isEmpty ? defaultQuickActions() : loadedQuick);
      selected = (int.tryParse(data['selected']?.toString() ?? '') ?? 0)
          .clamp(0, sessions.length - 1)
          .toInt();
      showQuickPanel = data['showQuickPanel'] == true;
    });
  }

  Future<void> saveState() async {
    await widget.controller.saveProjectUiStateSection('console', {
      'selected': selected,
      'showQuickPanel': showQuickPanel,
      'sessions': sessions.map((s) => s.toJson()).toList(),
      'quickActions': quickActions
          .map((a) => {'name': a.name, 'command': a.command, 'cwd': a.cwd})
          .toList(),
    });
  }

  void markStateChanged() => unawaited(saveState());

  void addSession({ConsoleSession? from}) {
    setState(() {
      final session = ConsoleSession(
        name: from == null
            ? 'Консоль ${sessions.length + 1}'
            : '${from.name} копия',
        cwd: from?.cwd ?? '.',
        output: from?.output ?? '',
      );
      if (from != null) {
        session.commandHistory.addAll(from.commandHistory);
        session.commandController.text = from.commandController.text;
      }
      sessions.add(session);
      selected = sessions.length - 1;
    });
    markStateChanged();
  }

  Future<void> showSessionMenu(TapDownDetails details, int index) async {
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          details.globalPosition.dx,
          details.globalPosition.dy,
          details.globalPosition.dx,
          details.globalPosition.dy),
      items: const [
        PopupMenuItem(value: 'duplicate', child: Text('Дублировать')),
        PopupMenuItem(value: 'rename', child: Text('Переименовать')),
        PopupMenuItem(value: 'delete', child: Text('Удалить')),
      ],
    );
    if (value == 'duplicate') addSession(from: sessions[index]);
    if (value == 'rename') {
      final name = await askText(context, 'Переименовать консоль', 'Название',
          initial: sessions[index].name);
      if (name != null && name.trim().isNotEmpty) {
        setState(() => sessions[index].name = name.trim());
        markStateChanged();
      }
    }
    if (value == 'delete' && sessions.length > 1) {
      setState(() {
        sessions[index].dispose();
        sessions.removeAt(index);
        selected = selected.clamp(0, sessions.length - 1).toInt();
      });
      markStateChanged();
    }
  }

  Future<void> showQuickActionMenu(TapDownDetails details, int index) async {
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          details.globalPosition.dx,
          details.globalPosition.dy,
          details.globalPosition.dx,
          details.globalPosition.dy),
      items: const [
        PopupMenuItem(value: 'edit', child: Text('Изменить')),
        PopupMenuItem(value: 'duplicate', child: Text('Дублировать')),
        PopupMenuItem(value: 'delete', child: Text('Удалить')),
      ],
    );
    if (value == 'edit') {
      final name = await askText(context, 'Название кнопки', 'Название',
          initial: quickActions[index].name);
      if (name == null) return;
      final command = await askText(context, 'Команда', 'Команда',
          initial: quickActions[index].command);
      if (command == null) return;
      setState(() {
        quickActions[index].name = name;
        quickActions[index].command = command;
      });
      markStateChanged();
    }
    if (value == 'duplicate') {
      setState(() => quickActions.add(ConsoleQuickAction(
          '${quickActions[index].name} копия', quickActions[index].command,
          cwd: quickActions[index].cwd)));
      markStateChanged();
    }
    if (value == 'delete') {
      setState(() => quickActions.removeAt(index));
      markStateChanged();
    }
  }

  String consolePrompt() {
    final projectName = widget.controller.currentProject?.name ?? 'project';
    final cwd = current.cwd.trim().isEmpty || current.cwd.trim() == '.'
        ? ''
        : current.cwd.trim();
    if (Platform.isWindows)
      return '$projectName${cwd.isEmpty ? '' : '\\$cwd'}>';
    return '~$projectName${cwd.isEmpty ? '' : '/$cwd'}>';
  }

  String consoleStdoutOnly(String result) {
    final stdoutMatch =
        RegExp(r'\[STDOUT\]\n([\s\S]*?)\n\[STDERR\]', multiLine: true)
            .firstMatch(result);
    final stdout = stdoutMatch?.group(1)?.trimRight() ?? '';
    if (stdout.isNotEmpty) return stdout;
    final stderrMatch =
        RegExp(r'\[STDERR\]\n([\s\S]*?)\n\[/STDERR\]', multiLine: true)
            .firstMatch(result);
    final stderr = stderrMatch?.group(1)?.trimRight() ?? '';
    return stderr.isNotEmpty ? stderr : result.trimRight();
  }

  Future<void> run(String command) async {
    final clean = command.trim();
    if (clean.isEmpty || running) return;
    setState(() {
      running = true;
      current.output += '\n${consolePrompt()} $clean\n';
      current.commandHistory.remove(clean);
      current.commandHistory.insert(0, clean);
      if (current.commandHistory.length > 80) {
        current.commandHistory.removeRange(80, current.commandHistory.length);
      }
    });
    markStateChanged();
    try {
      final result = await widget.controller
          .runCommand(clean, relativeWorkingDirectory: current.cwd);
      final visible = consoleStdoutOnly(result);
      setState(() {
        current.output +=
            '${visible.isEmpty ? '(команда завершилась без stdout)' : visible}\n';
      });
    } catch (e) {
      setState(() => current.output += 'Ошибка консоли: $e\n');
    } finally {
      if (mounted) setState(() => running = false);
      markStateChanged();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (verticalScrollController.hasClients) {
          verticalScrollController
              .jumpTo(verticalScrollController.position.maxScrollExtent);
        }
      });
    }
  }

  Future<String?> askInsertMode(String text) async {
    if (current.commandController.text.trim().isEmpty) return 'replace';
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Вставить в строку команды'),
        content: Text(
            'В строке уже есть текст. Добавить выбранный фрагмент в позицию курсора или заменить строку?\n\n$text'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, 'append'),
              child: const Text('Добавить')),
          FilledButton(
              onPressed: () => Navigator.pop(context, 'replace'),
              child: const Text('Заменить')),
        ],
      ),
    );
  }

  void insertCommandText(String text) {
    final controller = current.commandController;
    final old = controller.text;
    final selection = controller.selection;
    final start = selection.isValid
        ? selection.start.clamp(0, old.length).toInt()
        : old.length;
    final end = selection.isValid
        ? selection.end.clamp(0, old.length).toInt()
        : old.length;
    final separator =
        old.isNotEmpty && start == old.length && !old.endsWith(' ') ? ' ' : '';
    final next = old.replaceRange(start, end, '$separator$text');
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
          offset: start + separator.length + text.length),
    );
    markStateChanged();
  }

  Future<void> applyCommandSuggestion(String text) async {
    final mode = await askInsertMode(text);
    if (mode == null) return;
    if (mode == 'replace') {
      current.commandController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      markStateChanged();
      return;
    }
    insertCommandText(text);
  }

  Future<void> showInsertList(TapDownDetails details, String title,
      List<PopupMenuEntry<String>> items) async {
    if (items.isEmpty) return;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          details.globalPosition.dx + 12,
          details.globalPosition.dy + 12,
          details.globalPosition.dx + 12,
          details.globalPosition.dy + 12),
      items: [
        PopupMenuItem(
            enabled: false,
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.bold))),
        ...items,
      ],
    );
    if (value != null) await applyCommandSuggestion(value);
  }

  List<PopupMenuEntry<String>> currentFolderItems() {
    final project = widget.controller.currentProject;
    if (project == null) return const [];
    final cwd = widget.controller.normalizeRelativeDirectory(current.cwd);
    final dir = Directory(
        cwd.isEmpty ? project.path : resolveProjectPath(project.path, cwd));
    if (!dir.existsSync()) return const [];
    final entries = dir.listSync(followLinks: false)
      ..sort((a, b) => pathBasename(a.path)
          .toLowerCase()
          .compareTo(pathBasename(b.path).toLowerCase()));
    return entries.take(80).map((entry) {
      final name = pathBasename(entry.path);
      final value = entry is Directory
          ? '$name${Platform.pathSeparator}'
          : (name.contains(' ') ? widget.controller.quoteShellArg(name) : name);
      return PopupMenuItem<String>(
        value: value,
        child: Text(value, overflow: TextOverflow.ellipsis),
      );
    }).toList(growable: false);
  }

  List<PopupMenuEntry<String>> programItems() {
    return widget.controller
        .scanLocalToolsSync(maxItems: 260)
        .where((t) => const {
              'cpp_compiler',
              'build_tool',
              'python',
              'runtime',
              'archive',
              'program'
            }.contains(t.kind))
        .take(80)
        .map((tool) {
      final relativeFolder = relativeDirname(tool.relativePath);
      return PopupMenuItem<String>(
        value: tool.name.contains(' ')
            ? widget.controller.quoteShellArg(tool.name)
            : tool.name,
        child: Text('${tool.name}  —  $relativeFolder',
            overflow: TextOverflow.ellipsis),
      );
    }).toList(growable: false);
  }

  List<PopupMenuEntry<String>> historyItems() => current.commandHistory
      .take(60)
      .map((command) => PopupMenuItem<String>(
          value: command,
          child: Text(command, overflow: TextOverflow.ellipsis)))
      .toList(growable: false);

  String relativeDirname(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index <= 0 ? '.' : normalized.substring(0, index);
  }

  Future<void> showCommandContextMenu(TapDownDetails details) async {
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          details.globalPosition.dx,
          details.globalPosition.dy,
          details.globalPosition.dx,
          details.globalPosition.dy),
      items: const [
        PopupMenuItem(value: 'select_all', child: Text('Выделить все')),
        PopupMenuItem(value: 'copy', child: Text('Копировать')),
        PopupMenuItem(value: 'paste', child: Text('Вставить')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'history', child: Text('История команд')),
        PopupMenuItem(value: 'programs', child: Text('Программы')),
        PopupMenuItem(value: 'folder_files', child: Text('Файлы из папки')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'clear', child: Text('Очистить')),
      ],
    );
    if (value == null) return;
    if (value == 'select_all') {
      current.commandController.selection = TextSelection(
          baseOffset: 0, extentOffset: current.commandController.text.length);
    } else if (value == 'copy') {
      await Clipboard.setData(
          ClipboardData(text: current.commandController.text));
    } else if (value == 'paste') {
      final data = await Clipboard.getData('text/plain');
      if (data?.text != null) insertCommandText(data!.text!);
    } else if (value == 'clear') {
      current.commandController.clear();
      markStateChanged();
    } else if (value == 'history') {
      await showInsertList(details, 'История команд', historyItems());
    } else if (value == 'programs') {
      await showInsertList(details, 'Программы из tools', programItems());
    } else if (value == 'folder_files') {
      await showInsertList(
          details, 'Файлы из текущей папки', currentFolderItems());
    }
  }

  Future<void> showConsoleOutputMenu(TapDownDetails details) async {
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          details.globalPosition.dx,
          details.globalPosition.dy,
          details.globalPosition.dx,
          details.globalPosition.dy),
      items: const [
        PopupMenuItem(value: 'copy', child: Text('Копировать')),
        PopupMenuItem(value: 'clear', child: Text('Очистить')),
      ],
    );
    if (value == 'copy')
      await Clipboard.setData(ClipboardData(text: current.output));
    if (value == 'clear') {
      setState(() => current.output = '');
      markStateChanged();
    }
  }

  Widget quickPanel() {
    syncGeneratedQuickActions();
    return SizedBox(
      width: 240,
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          Row(children: [
            const Expanded(
                child: Text('Быстрый запуск',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            IconButton(
              tooltip: 'Добавить',
              onPressed: () async {
                final name =
                    await askText(context, 'Название кнопки', 'Название');
                if (name == null) return;
                final command =
                    await askText(context, 'Команда или скрипт', 'Команда');
                if (command == null) return;
                setState(
                    () => quickActions.add(ConsoleQuickAction(name, command)));
                markStateChanged();
              },
              icon: const Icon(Icons.add),
            ),
          ]),
          for (var i = 0; i < quickActions.length; i++)
            GestureDetector(
              onSecondaryTapDown: (details) => showQuickActionMenu(details, i),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: OutlinedButton(
                  onPressed: () {
                    current.cwd = quickActions[i].cwd;
                    current.cwdController.text = current.cwd;
                    unawaited(run(quickActions[i].command));
                  },
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(quickActions[i].name,
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void syncGeneratedQuickActions() {
    for (final generated in widget.controller.generatedConsoleQuickActions) {
      final exists = quickActions
          .any((a) => a.command == generated.command && a.cwd == generated.cwd);
      if (!exists) {
        quickActions.add(ConsoleQuickAction(generated.name, generated.command,
            cwd: generated.cwd));
        markStateChanged();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    syncGeneratedQuickActions();
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 900;
        final main = Expanded(
          child: Column(
            children: [
              Material(
                elevation: 1,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (narrow)
                        IconButton(
                          onPressed: () {
                            setState(() => showQuickPanel = !showQuickPanel);
                            markStateChanged();
                          },
                          icon: const Icon(Icons.bolt),
                          tooltip: 'Быстрый запуск',
                        ),
                      for (var i = 0; i < sessions.length; i++)
                        GestureDetector(
                          onSecondaryTapDown: (details) =>
                              showSessionMenu(details, i),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 6),
                            child: ChoiceChip(
                              label: Text(sessions[i].name),
                              selected: selected == i,
                              onSelected: (_) {
                                setState(() => selected = i);
                                markStateChanged();
                              },
                            ),
                          ),
                        ),
                      IconButton(
                          onPressed: () => addSession(),
                          icon: const Icon(Icons.add),
                          tooltip: 'Новая консоль'),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onSecondaryTapDown: showConsoleOutputMenu,
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(8)),
                    child: Scrollbar(
                      controller: verticalScrollController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: verticalScrollController,
                        child: Scrollbar(
                          controller: horizontalScrollController,
                          thumbVisibility: true,
                          notificationPredicate: (n) =>
                              n.metrics.axis == Axis.horizontal,
                          child: SingleChildScrollView(
                            controller: horizontalScrollController,
                            scrollDirection: Axis.horizontal,
                            child: SelectableText(
                              current.output.isEmpty
                                  ? 'Консоль готова.'
                                  : current.output,
                              style: const TextStyle(
                                  fontFamily: 'monospace', color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    SizedBox(
                      width: narrow ? 120 : 180,
                      child: TextField(
                        decoration: const InputDecoration(
                            labelText: 'Папка',
                            border: OutlineInputBorder(),
                            isDense: true),
                        controller: current.cwdController,
                        onSubmitted: (value) {
                          current.cwd =
                              value.trim().isEmpty ? '.' : value.trim();
                          current.cwdController.text = current.cwd;
                          markStateChanged();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onSecondaryTapDown: showCommandContextMenu,
                        child: TextField(
                          controller: current.commandController,
                          decoration: const InputDecoration(
                              labelText: 'Команда',
                              helperText: 'ПКМ: меню консоли',
                              border: OutlineInputBorder(),
                              isDense: true),
                          onChanged: (_) => markStateChanged(),
                          onSubmitted: run,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: running
                          ? null
                          : () =>
                              unawaited(run(current.commandController.text)),
                      icon: const Icon(Icons.play_arrow),
                      label: Text(running ? 'Выполняется' : 'Выполнить'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
        if (narrow) {
          return Row(children: [
            main,
            if (showQuickPanel) const VerticalDivider(width: 1),
            if (showQuickPanel) quickPanel(),
          ]);
        }
        return Row(
            children: [main, const VerticalDivider(width: 1), quickPanel()]);
      },
    );
  }
}
