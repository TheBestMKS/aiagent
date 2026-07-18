import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../agent_core/terminal/interactive_terminal_service.dart';
import '../controllers/agent_controller.dart';
import '../core/runtime_types.dart';
import '../utils/html_utils.dart';
import '../utils/path_utils.dart';

class ConsoleSession {
  ConsoleSession({
    required this.id,
    required this.name,
    this.cwd = '.',
    this.output = '',
  }) {
    cwdController.text = cwd;
    if (output.isNotEmpty) terminal.write(output);
  }

  final String id;
  String name;
  String cwd;
  String output;
  final List<String> commandHistory = [];
  final TextEditingController commandController = TextEditingController();
  final TextEditingController cwdController = TextEditingController();
  final Terminal terminal = Terminal(maxLines: 20000);
  final TerminalController terminalController = TerminalController();

  void appendOutput(String value) {
    if (value.isEmpty) return;
    output += value;
    const maxChars = 2 * 1024 * 1024;
    if (output.length > maxChars) {
      output = output.substring(output.length - maxChars);
    }
    terminal.write(value);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cwd': cwd,
        'output': output.length <= 300000
            ? output
            : output.substring(output.length - 300000),
        'history': commandHistory.take(80).toList(),
        'command': commandController.text,
      };

  static ConsoleSession fromJson(Map<String, dynamic> json) {
    final session = ConsoleSession(
      id: json['id']?.toString().trim().isNotEmpty == true
          ? json['id'].toString()
          : 'console-${DateTime.now().microsecondsSinceEpoch}',
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
    terminal.onOutput = null;
    terminal.onResize = null;
    terminalController.dispose();
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
  final List<ConsoleSession> sessions = [
    ConsoleSession(id: 'agent-main', name: 'Команды агента')
  ];
  final List<ConsoleQuickAction> quickActions = [];
  StreamSubscription<TerminalSessionEvent>? terminalEventSubscription;
  Timer? stateSaveTimer;
  int selected = 0;
  bool running = false;
  bool showQuickPanel = false;
  bool stateLoaded = false;

  ConsoleSession get current =>
      sessions[selected.clamp(0, sessions.length - 1).toInt()];

  void bindTerminal(ConsoleSession session) {
    session.terminal.onOutput = (data) {
      unawaited(sendTerminalInput(session, data));
    };
    session.terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      widget.controller.terminalService.resize(session.id, height, width);
    };
  }

  Future<void> sendTerminalInput(ConsoleSession session, String data) async {
    var snapshot = widget.controller.terminalService.snapshot(session.id);
    if (snapshot == null || !snapshot.running) {
      try {
        snapshot = await widget.controller.terminalService.open(
          sessionId: session.id,
          name: session.name,
          cwd: session.cwd,
          environment: widget.controller.buildToolAwareEnvironment(),
          rows: session.terminal.viewHeight,
          columns: session.terminal.viewWidth,
        );
      } catch (error) {
        onTerminalEvent(TerminalSessionEvent(
          sessionId: session.id,
          kind: TerminalEventKind.error,
          text: '\r\n[Не удалось открыть PTY] $error\r\n',
          time: DateTime.now(),
        ));
        return;
      }
    }
    widget.controller.terminalService.writeRaw(snapshot.id, data);
  }

  void onTerminalEvent(TerminalSessionEvent event) {
    if (!mounted) return;
    final snapshot =
        widget.controller.terminalService.snapshot(event.sessionId);
    var index = sessions.indexWhere((session) => session.id == event.sessionId);
    var uiChanged = false;
    if (index < 0) {
      final session = ConsoleSession(
        id: event.sessionId,
        name: snapshot?.name ?? event.sessionId,
        cwd: snapshot?.cwd ?? '.',
      );
      bindTerminal(session);
      sessions.add(session);
      index = sessions.length - 1;
      uiChanged = true;
    }
    final session = sessions[index];
    if (snapshot != null) {
      uiChanged = uiChanged ||
          session.name != snapshot.name ||
          session.cwd != snapshot.cwd;
      session.name = snapshot.name;
      session.cwd = snapshot.cwd;
      session.cwdController.text = snapshot.cwd;
    }
    if (event.kind == TerminalEventKind.opened) {
      session.appendOutput(
          '\r\n\x1b[90m[PTY открыт: ${snapshot?.shell ?? ''}]\x1b[0m\r\n');
      uiChanged = true;
    } else if (event.text.isNotEmpty &&
        event.kind != TerminalEventKind.command &&
        event.kind != TerminalEventKind.closed) {
      session.appendOutput(event.text);
    }
    if (uiChanged) setState(() {});
    markStateChanged();
  }

  void syncTerminalServiceSessions() {
    if (!mounted) return;
    var changed = false;
    for (final snapshot in widget.controller.terminalService.snapshots) {
      final existing = sessions.indexWhere((item) => item.id == snapshot.id);
      if (existing >= 0) {
        final session = sessions[existing];
        session.name = snapshot.name;
        session.cwd = snapshot.cwd;
        session.cwdController.text = snapshot.cwd;
        if (session.output.isEmpty && snapshot.transcript.isNotEmpty) {
          session.appendOutput(snapshot.transcript);
          changed = true;
        }
        continue;
      }
      final session = ConsoleSession(
        id: snapshot.id,
        name: snapshot.name,
        cwd: snapshot.cwd,
        output: snapshot.transcript,
      );
      bindTerminal(session);
      sessions.add(session);
      changed = true;
    }
    if (changed) {
      setState(() {});
      markStateChanged();
    }
  }

  @override
  void initState() {
    super.initState();
    quickActions.addAll(defaultQuickActions());
    for (final session in sessions) {
      bindTerminal(session);
    }
    terminalEventSubscription =
        widget.controller.terminalService.events.listen(onTerminalEvent);
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
      unawaited(loadState().whenComplete(syncTerminalServiceSessions));
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
    stateSaveTimer?.cancel();
    unawaited(saveState());
    unawaited(terminalEventSubscription?.cancel());
    for (final session in sessions) {
      session.dispose();
    }
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
            ? [ConsoleSession(id: 'agent-main', name: 'Команды агента')]
            : loadedSessions);
      for (final session in sessions) {
        bindTerminal(session);
      }
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

  void markStateChanged() {
    stateSaveTimer?.cancel();
    stateSaveTimer = Timer(const Duration(milliseconds: 600), () {
      unawaited(saveState());
    });
  }

  void addSession({ConsoleSession? from}) {
    setState(() {
      final session = ConsoleSession(
        id: 'console-${DateTime.now().microsecondsSinceEpoch}',
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
      bindTerminal(session);
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
      final removedId = sessions[index].id;
      setState(() {
        sessions[index].dispose();
        sessions.removeAt(index);
        selected = selected.clamp(0, sessions.length - 1).toInt();
      });
      unawaited(widget.controller.terminalService.close(removedId));
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

  Future<void> run(String command) async {
    final clean = command.trim();
    if (clean.isEmpty || running) return;
    setState(() {
      running = true;
      current.commandHistory.remove(clean);
      current.commandHistory.insert(0, clean);
      if (current.commandHistory.length > 80) {
        current.commandHistory.removeRange(80, current.commandHistory.length);
      }
      current.commandController.clear();
    });
    markStateChanged();
    try {
      final snapshot = widget.controller.terminalService.snapshot(current.id);
      if (snapshot == null || !snapshot.running) {
        await widget.controller.terminalService.open(
          sessionId: current.id,
          name: current.name,
          cwd: current.cwd,
          environment: widget.controller.buildToolAwareEnvironment(),
          rows: current.terminal.viewHeight,
          columns: current.terminal.viewWidth,
        );
      }
      await widget.controller.terminalService.writeAndCollect(
        current.id,
        clean,
        timeout: const Duration(seconds: 3),
      );
    } catch (e) {
      current.appendOutput('\r\nОшибка консоли: $e\r\n');
    } finally {
      if (mounted) setState(() => running = false);
      markStateChanged();
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
    if (value == 'copy') {
      final selection = current.terminalController.selection;
      final text = selection == null
          ? current.output
          : current.terminal.buffer.getText(selection);
      await Clipboard.setData(ClipboardData(text: text));
      current.terminalController.clearSelection();
    }
    if (value == 'clear') {
      setState(() {
        current.output = '';
        current.terminal.write('\x1b[2J\x1b[H\x1b[3J');
      });
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
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(8),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TerminalView(
                    current.terminal,
                    controller: current.terminalController,
                    autofocus: true,
                    backgroundOpacity: 1,
                    onSecondaryTapDown: (details, offset) =>
                        showConsoleOutputMenu(details),
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
                    if (narrow)
                      IconButton.filled(
                        tooltip: running ? 'Выполняется' : 'Выполнить',
                        onPressed: running
                            ? null
                            : () =>
                                unawaited(run(current.commandController.text)),
                        icon: Icon(
                            running ? Icons.hourglass_top : Icons.play_arrow),
                      )
                    else
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
