import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/app_constants.dart';
import '../controllers/agent_controller.dart';
import '../core/models.dart';
import '../core/runtime_types.dart';
import '../utils/html_utils.dart';
import '../utils/path_utils.dart';
import '../dialogs/settings_dialogs.dart';
import '../tabs/chat_tab.dart';
import '../tabs/files_tab.dart';
import '../tabs/console_tab.dart';
import '../tabs/web_tab.dart';

class AiAgentApp extends StatefulWidget {
  const AiAgentApp({super.key, this.disableStartupTasks = false});

  final bool disableStartupTasks;

  @override
  State<AiAgentApp> createState() => _AiAgentAppState();
}

class _AiAgentAppState extends State<AiAgentApp> {
  final AgentController controller = AgentController();

  @override
  void initState() {
    super.initState();
    controller.appUpdater = () {
      if (mounted) setState(() {});
    };
    if (widget.disableStartupTasks) {
      controller.initializationStarted = true;
      controller.initializationFinished = true;
      controller.initializationFailed = false;
      controller.status = 'Тестовый режим: фоновые задачи запуска отключены';
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(controller
            .initialize()
            .catchError((Object error, StackTrace stackTrace) {
          controller.markInitializationFailed(error, stackTrace);
        }).whenComplete(() {
          if (!mounted) return;
          setState(() {});
        }));
      });
    }
  }

  @override
  void dispose() {
    unawaited(controller.shutdown());
    if (controller.appUpdater != null) controller.appUpdater = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '$appName $appVersion',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: Platform.isAndroid
            ? const VisualDensity(horizontal: -2, vertical: -2)
            : VisualDensity.standard,
      ),
      builder: (context, child) {
        final shortest = MediaQuery.of(context).size.shortestSide;
        final scale = controller.effectiveUiScale(shortest);
        final base = MediaQuery.of(context);
        return MediaQuery(
          data: base.copyWith(textScaler: TextScaler.linear(scale)),
          child: IconTheme.merge(
            data: IconThemeData(size: 24 * scale),
            child: Theme(
              data: Theme.of(context).copyWith(
                iconButtonTheme: IconButtonThemeData(
                  style: IconButton.styleFrom(
                      iconSize: 24 * scale,
                      minimumSize: Size(40 * scale, 40 * scale)),
                ),
              ),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
      home: HomeScreen(
          controller: controller,
          disableStartupTasks: widget.disableStartupTasks),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen(
      {super.key, required this.controller, this.disableStartupTasks = false});

  final AgentController controller;
  final bool disableStartupTasks;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController promptController = TextEditingController();
  final TextEditingController attachmentPathController =
      TextEditingController();
  bool askedLocalLlama = false;
  int selectedTab = 0;
  bool projectPanelCollapsed = false;

  @override
  void initState() {
    super.initState();
    widget.controller.permissionApprover = _confirmAgentPermission;
    widget.controller.openUrlInWebTab = (url) {
      if (!mounted) return;
      setState(() => selectedTab = 3);
      widget.controller.requestOpenWebUrl(url);
    };
    widget.controller.uiUpdater = () {
      if (mounted) setState(() {});
    };
    if (!widget.disableStartupTasks) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _askLocalLlamaIfNeeded());
    }
  }

  Future<bool> _confirmAgentPermission(AgentPermissionRequest request) async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(request.critical
            ? 'Критичное действие агента'
            : 'Разрешение действия агента'),
        content: SingleChildScrollView(
          child: SelectableText(
            'Инструмент: ${request.toolName}\n'
            'Причина: ${request.reason}\n\n'
            '${request.details}',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Запретить')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Разрешить')),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  void dispose() {
    if (widget.controller.permissionApprover == _confirmAgentPermission) {
      widget.controller.permissionApprover = null;
    }
    if (widget.controller.openUrlInWebTab != null)
      widget.controller.openUrlInWebTab = null;
    unawaited(widget.controller.shutdown());
    promptController.dispose();
    attachmentPathController.dispose();
    super.dispose();
  }

  Future<void> _askLocalLlamaIfNeeded() async {
    if (askedLocalLlama || !mounted) return;
    if (!widget.controller.initializationFinished) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) unawaited(_askLocalLlamaIfNeeded());
      });
      return;
    }
    if (widget.controller.initializationFailed) return;
    askedLocalLlama = true;
    final candidates = await widget.controller.scanLocalLlamaCandidates();
    if (candidates.isEmpty || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => LocalLlamaStartupDialog(
        candidates: candidates,
        controller: widget.controller,
        onChanged: () => setState(() {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 820;
          if (narrow) {
            return Stack(
              children: [
                Positioned.fill(child: _mainArea(controller)),
                Positioned(
                  left: 12,
                  top: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'open_project_panel',
                    tooltip: 'Проекты',
                    onPressed: () async {
                      await showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => SafeArea(
                          child: SizedBox(
                            height: MediaQuery.of(context).size.height * 0.82,
                            child: ProjectPanel(
                                controller: controller,
                                onChanged: () => setState(() {})),
                          ),
                        ),
                      );
                    },
                    child: const Icon(Icons.menu_open),
                  ),
                ),
              ],
            );
          }
          return Row(
            children: [
              if (!projectPanelCollapsed) ...[
                SizedBox(
                  width: 290,
                  child: ProjectPanel(
                      controller: controller, onChanged: () => setState(() {})),
                ),
                const VerticalDivider(width: 1),
              ],
              Expanded(child: _mainArea(controller)),
            ],
          );
        },
      ),
    );
  }

  Widget _mainArea(AgentController controller) {
    return Column(
      children: [
        if (!controller.initializationFinished ||
            controller.initializationFailed)
          Material(
            color: controller.initializationFailed
                ? Colors.red.withValues(alpha: 0.08)
                : Colors.indigo.withValues(alpha: 0.06),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  if (!controller.initializationFinished) ...[
                    const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      controller.initializationFailed
                          ? 'Ошибка инициализации: ${controller.initializationError}'
                          : controller.status,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (controller.initializationFailed)
                    TextButton(
                      onPressed: () => unawaited(controller.initialize()),
                      child: const Text('Повторить'),
                    ),
                ],
              ),
            ),
          ),
        Material(
          elevation: 1,
          child: Row(
            children: [
              if (controller.projects.length < 0)
                IconButton(
                  tooltip: projectPanelCollapsed
                      ? 'Показать левую панель'
                      : 'Скрыть левую панель',
                  onPressed: () => setState(
                      () => projectPanelCollapsed = !projectPanelCollapsed),
                  icon: Icon(
                      projectPanelCollapsed ? Icons.menu_open : Icons.menu),
                ),
              Expanded(
                child: NavigationBar(
                  height: (64 *
                          controller.effectiveUiScale(
                              MediaQuery.of(context).size.shortestSide))
                      .clamp(44.0, 72.0)
                      .toDouble(),
                  selectedIndex: selectedTab,
                  onDestinationSelected: (index) =>
                      setState(() => selectedTab = index),
                  destinations: const [
                    NavigationDestination(icon: Icon(Icons.chat), label: 'Чат'),
                    NavigationDestination(
                        icon: Icon(Icons.folder), label: 'Файлы'),
                    NavigationDestination(
                        icon: Icon(Icons.terminal), label: 'Консоль'),
                    NavigationDestination(
                        icon: Icon(Icons.public), label: 'Web'),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (controller.projectLoading) const LinearProgressIndicator(),
        Expanded(
          child: switch (selectedTab) {
            0 => ChatTab(
                controller: controller,
                promptController: promptController,
                attachmentPathController: attachmentPathController,
                onChanged: () => setState(() {}),
              ),
            1 => FilesTab(
                controller: controller,
                onChanged: () => setState(() {}),
                onRunInConsole: (command, cwd) {
                  setState(() => selectedTab = 2);
                  controller.requestConsoleRun(
                      command: command, cwd: cwd, newTab: true);
                },
              ),
            2 => ConsoleTab(controller: controller),
            _ => WebTab(controller: controller),
          },
        ),
      ],
    );
  }
}

class ProjectPanel extends StatelessWidget {
  const ProjectPanel(
      {super.key, required this.controller, required this.onChanged});

  final AgentController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final nameController = TextEditingController();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(appName,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const Text('локальный агент программирования',
              style: TextStyle(fontSize: 11)),
          const SizedBox(height: 12),
          if (controller.projects.length >= 0)
            Row(
              children: [
                const Expanded(
                    child: Text('Проекты',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold))),
                IconButton(
                  tooltip: 'Создать проект',
                  onPressed: () async {
                    await showDialog<void>(
                      context: context,
                      builder: (_) => ProjectEditDialog(
                          controller: controller, onChanged: onChanged),
                    );
                    onChanged();
                  },
                  icon: const Icon(Icons.add),
                ),
                IconButton(
                  tooltip: 'Обновить проекты и модели',
                  onPressed: () async {
                    await controller.refreshProjects();
                    await controller.refreshAvailableModels();
                    onChanged();
                  },
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          const SizedBox(height: 8),
          if (controller.projects.length < 0)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Новый проект',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (value) async {
                      await controller.createProject(value);
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () async {
                    await controller.createProject(nameController.text);
                    onChanged();
                  },
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: controller.projects.length,
              itemBuilder: (context, index) {
                final project = controller.projects[index];
                final selected =
                    project.path == controller.currentProject?.path;
                return ListTile(
                  dense: true,
                  selected: selected,
                  title: Text(project.name),
                  subtitle: Text(project.path,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () async {
                    await controller.openProject(project);
                    onChanged();
                  },
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'edit') {
                        await showDialog<void>(
                          context: context,
                          builder: (_) => ProjectEditDialog(
                              controller: controller,
                              onChanged: onChanged,
                              project: project),
                        );
                      } else if (value == 'schedule') {
                        await showDialog<void>(
                          context: context,
                          builder: (_) => AutomationSettingsDialog(
                              controller: controller,
                              projectPath: project.path),
                        );
                      } else if (value == 'rename') {
                        final name = await askText(
                            context, 'Переименовать проект', 'Новое название',
                            initial: project.name);
                        if (name != null)
                          await controller.renameProject(project, name);
                      } else if (value == 'move') {
                        final path = await askText(context,
                            'Изменить расположение', 'Новый абсолютный путь',
                            initial: project.path);
                        if (path != null)
                          await controller.moveProject(project, path);
                      } else if (value == 'duplicate') {
                        final name = await askText(
                            context, 'Дублировать проект', 'Название копии',
                            initial: '${project.name}_copy');
                        if (name != null)
                          await controller.duplicateProject(project, name);
                      } else if (value == 'clear_dialog') {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Очистить диалог и контекст?'),
                            content: Text(
                                'Будут удалены сообщения диалога и рабочий контекст проекта «${project.name}». Файлы проекта, база знаний и логи не удаляются.'),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Отмена')),
                              FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Очистить')),
                            ],
                          ),
                        );
                        if (ok == true)
                          await controller
                              .clearProjectDialogAndContext(project);
                      } else if (value == 'delete') {
                        await controller.deleteProject(project);
                      }
                      onChanged();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'edit', child: Text('Настройки проекта')),
                      PopupMenuItem(
                          value: 'schedule', child: Text('Расписание')),
                      PopupMenuItem(
                          value: 'rename', child: Text('Переименовать')),
                      PopupMenuItem(
                          value: 'move', child: Text('Изменить расположение')),
                      PopupMenuItem(
                          value: 'duplicate',
                          child: Text('Дублировать проект с новым названием')),
                      PopupMenuDivider(),
                      PopupMenuItem(
                          value: 'clear_dialog',
                          child: Text('Очистить диалог и контекст')),
                      PopupMenuDivider(),
                      PopupMenuItem(value: 'delete', child: Text('Удалить')),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  await showDialog<void>(
                    context: context,
                    builder: (_) => ProgramSettingsDialog(
                        controller: controller, onChanged: onChanged),
                  );
                  onChanged();
                },
                icon: const Icon(Icons.settings_applications),
                label: const Text('Настройки'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await showDialog<void>(
                    context: context,
                    builder: (_) => AboutProgramDialog(controller: controller),
                  );
                },
                icon: const Icon(Icons.info_outline),
                label: const Text('О программе'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Projects: ${controller.projectsRoot.path}',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class ProjectEditDialog extends StatefulWidget {
  const ProjectEditDialog(
      {super.key,
      required this.controller,
      required this.onChanged,
      this.project});

  final AgentController controller;
  final VoidCallback onChanged;
  final ProjectInfo? project;

  @override
  State<ProjectEditDialog> createState() => _ProjectEditDialogState();
}

class _ProjectEditDialogState extends State<ProjectEditDialog> {
  late final TextEditingController nameController;
  late final TextEditingController pathController;
  bool projectIndexingEnabled = false;

  @override
  void initState() {
    super.initState();
    final project = widget.project;
    final name = project?.name ?? 'NewProject';
    nameController = TextEditingController(text: name);
    pathController = TextEditingController(
        text: project?.path ??
            pathJoin(widget.controller.projectsRoot.path, name));
  }

  @override
  void dispose() {
    nameController.dispose();
    pathController.dispose();
    super.dispose();
  }

  void syncDefaultPath() {
    if (widget.project != null) return;
    final name = sanitizeFileName(nameController.text.trim().isEmpty
        ? 'NewProject'
        : nameController.text.trim());
    pathController.text = pathJoin(widget.controller.projectsRoot.path, name);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.project != null;
    return AlertDialog(
      title: Text(editing ? 'Проект' : 'Создать проект'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                  labelText: 'Название проекта', border: OutlineInputBorder()),
              onChanged: (_) => syncDefaultPath(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: pathController,
                    decoration: const InputDecoration(
                        labelText: 'Путь к папке проекта',
                        border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Выбрать папку',
                  onPressed: () async {
                    final picked = await showDialog<String>(
                      context: context,
                      builder: (_) => EmbeddedFilePickerDialog(
                          initialDirectory: pathController.text.trim().isEmpty
                              ? widget.controller.projectsRoot.path
                              : pathController.text.trim(),
                          selectDirectory: true),
                    );
                    if (picked != null)
                      setState(() => pathController.text = picked);
                  },
                  icon: const Icon(Icons.folder_open),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              value: projectIndexingEnabled,
              onChanged: (value) =>
                  setState(() => projectIndexingEnabled = value),
              title:
                  const Text('Индивидуальная индексация содержимого проекта'),
              secondary: IconButton(
                tooltip: 'Переиндексировать',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content:
                          Text('Индексация проекта будет выполнена агентом.')));
                },
                icon: const Icon(Icons.manage_search),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    await showDialog<void>(
                      context: context,
                      builder: (_) => ProgramSettingsDialog(
                          controller: widget.controller,
                          onChanged: widget.onChanged),
                    );
                  },
                  icon: const Icon(Icons.security),
                  label: const Text('Права'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await showDialog<void>(
                      context: context,
                      builder: (_) => AutomationSettingsDialog(
                          controller: widget.controller,
                          projectPath: pathController.text.trim()),
                    );
                  },
                  icon: const Icon(Icons.schedule),
                  label: const Text('Расписание'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена')),
        FilledButton(
          onPressed: () async {
            final name = nameController.text.trim();
            final targetPath = pathController.text.trim();
            if (editing) {
              final project = widget.project!;
              if (name.isNotEmpty && name != project.name) {
                await widget.controller.renameProject(project, name);
              }
              if (targetPath.isNotEmpty &&
                  targetPath != widget.controller.currentProject?.path) {
                await widget.controller.moveProject(
                    widget.controller.currentProject ?? project, targetPath);
              }
            } else {
              await widget.controller.createProjectAt(name, targetPath);
            }
            widget.onChanged();
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(editing ? 'Сохранить' : 'Создать'),
        ),
      ],
    );
  }
}
