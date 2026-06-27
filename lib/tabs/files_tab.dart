import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/agent_controller.dart';
import '../dialogs/settings_dialogs.dart';
import '../document_tools/office_document_tools.dart';
import '../utils/path_utils.dart';

class FilesTab extends StatefulWidget {
  const FilesTab({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onRunInConsole,
  });

  final AgentController controller;
  final VoidCallback onChanged;
  final void Function(String command, String cwd) onRunInConsole;

  @override
  State<FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<FilesTab> {
  final TextEditingController editorController = TextEditingController();
  final ScrollController horizontalScrollController = ScrollController();
  final ScrollController verticalScrollController = ScrollController();
  String? selectedRelativePath;
  bool selectedIsText = false;
  bool selectedIsStructuredDocument = false;
  bool cutMode = false;
  String? clipboardPath;
  String statusText = '';

  @override
  void dispose() {
    editorController.dispose();
    horizontalScrollController.dispose();
    verticalScrollController.dispose();
    super.dispose();
  }

  Future<void> openFile(TreeEntry entry) async {
    if (entry.isDirectory) return;
    final text =
        await widget.controller.readRelativeFileForEditor(entry.relativePath);
    final absolute = widget.controller.currentProject == null
        ? entry.relativePath
        : resolveProjectPath(
            widget.controller.currentProject!.path, entry.relativePath);
    final structured = isStructuredOfficeDocumentPath(absolute);
    setState(() {
      selectedRelativePath = entry.relativePath;
      selectedIsText = text != null;
      selectedIsStructuredDocument = structured;
      editorController.text = text ??
          'Файл не похож на поддерживаемый текстовый/документный формат или слишком большой для редактора.';
      statusText = structured
          ? 'Открыт структурированный документ: ${detectOfficeDocumentKind(absolute).label}'
          : '';
    });
  }

  Future<void> _showResult(String message) async {
    setState(() => statusText = message);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(truncateForSnack(message))));
  }

  String _targetDirectory(TreeEntry entry) =>
      entry.isDirectory ? entry.relativePath : pathDirname(entry.relativePath);

  Future<String?> _askText({
    required String title,
    required String label,
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
          onSubmitted: (_) => Navigator.pop(context, controller.text),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('ОК')),
        ],
      ),
    );
    controller.dispose();
    return result?.trim();
  }

  Future<void> _handleEntryAction(TreeEntry entry, String value) async {
    final controller = widget.controller;
    switch (value) {
      case 'copy':
      case 'cut':
        setState(() {
          clipboardPath = entry.relativePath;
          cutMode = value == 'cut';
          statusText =
              '${cutMode ? 'Вырезано' : 'Скопировано'}: ${entry.relativePath}';
        });
        return;
      case 'paste':
        if (clipboardPath == null) return;
        await controller.pasteProjectEntry(
            clipboardPath!, _targetDirectory(entry),
            move: cutMode);
        setState(() => clipboardPath = null);
        widget.onChanged();
        await _showResult('Вставлено в ${_targetDirectory(entry)}');
        return;
      case 'rename':
        final name = await _askText(
            title: 'Переименовать', label: 'Новое имя', initial: entry.name);
        if (name == null || name.isEmpty) return;
        final result =
            await controller.renameRelativePath(entry.relativePath, name);
        widget.onChanged();
        await _showResult(result);
        return;
      case 'upload':
        final picked = await showDialog<String>(
          context: context,
          builder: (_) => EmbeddedFilePickerDialog(
              initialDirectory: Directory.current.path),
        );
        if (picked == null || picked.isEmpty) return;
        final result = await controller.importExternalEntryToProject(
            picked, _targetDirectory(entry));
        widget.onChanged();
        await _showResult(result);
        return;
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Удалить'),
            content: Text(entry.relativePath),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Отмена')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Удалить')),
            ],
          ),
        );
        if (confirmed != true) return;
        final result = await controller.deleteRelativePath(entry.relativePath,
            recursive: entry.isDirectory);
        if (selectedRelativePath == entry.relativePath) {
          setState(() {
            selectedRelativePath = null;
            editorController.clear();
          });
        }
        widget.onChanged();
        await _showResult(result);
        return;
      case 'properties':
        final result = controller.relativePathProperties(entry.relativePath);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Свойства'),
            content: SizedBox(width: 520, child: SelectableText(result)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Закрыть'))
            ],
          ),
        );
        return;
      case 'run':
        final command =
            controller.commandForProjectExecutable(entry.relativePath);
        controller.ensureConsoleQuickLaunch('Запуск ${entry.name}', command,
            cwd: '.');
        widget.onRunInConsole(command, '.');
        return;
    }
  }

  Future<void> _handleRootAction(String value) async {
    final project = widget.controller.currentProject;
    if (project == null) return;
    switch (value) {
      case 'paste':
        if (clipboardPath == null) return;
        await widget.controller
            .pasteProjectEntry(clipboardPath!, '.', move: cutMode);
        setState(() => clipboardPath = null);
        widget.onChanged();
        await _showResult('Вставлено в корень проекта');
        return;
      case 'upload':
        final picked = await showDialog<String>(
          context: context,
          builder: (_) => EmbeddedFilePickerDialog(
              initialDirectory: Directory.current.path),
        );
        if (picked == null || picked.isEmpty) return;
        final result =
            await widget.controller.importExternalEntryToProject(picked, '.');
        widget.onChanged();
        await _showResult(result);
        return;
      case 'properties':
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Проект'),
            content: SizedBox(
              width: 560,
              child: SelectableText(
                  'NAME: ${project.name}\nPATH: ${project.path}\nFILES: ${widget.controller.projectTreeEntries().length}'),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Закрыть'))
            ],
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.controller.projectTreeEntries();
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 900;
        final tree = _tree(entries);
        final editor = _editor();
        if (narrow) {
          return Column(
            children: [
              Expanded(flex: 2, child: tree),
              const Divider(height: 1),
              Expanded(flex: 3, child: editor),
            ],
          );
        }
        return Row(
          children: [
            SizedBox(width: 360, child: tree),
            const VerticalDivider(width: 1),
            Expanded(child: editor),
          ],
        );
      },
    );
  }

  Widget _tree(List<TreeEntry> entries) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
          child: Row(
            children: [
              const Expanded(
                child: Text('Файлы проекта',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              PopupMenuButton<String>(
                tooltip: 'Действия с проектом',
                onSelected: (value) => unawaited(_handleRootAction(value)),
                itemBuilder: (_) => [
                  if (clipboardPath != null)
                    const PopupMenuItem(
                        value: 'paste', child: Text('Вставить')),
                  const PopupMenuItem(
                      value: 'upload', child: Text('Загрузить')),
                  const PopupMenuItem(
                      value: 'properties', child: Text('Свойства')),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
                dense: true,
                contentPadding:
                    EdgeInsets.only(left: 8 + entry.depth * 16.0, right: 4),
                leading:
                    Icon(entry.isDirectory ? Icons.folder : Icons.description),
                title: Text(entry.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(entry.relativePath,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                selected: entry.relativePath == selectedRelativePath,
                onTap: () => openFile(entry),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Действия',
                  onSelected: (value) =>
                      unawaited(_handleEntryAction(entry, value)),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'copy', child: Text('Копировать')),
                    const PopupMenuItem(value: 'cut', child: Text('Вырезать')),
                    if (clipboardPath != null && entry.isDirectory)
                      const PopupMenuItem(
                          value: 'paste', child: Text('Вставить')),
                    const PopupMenuItem(
                        value: 'rename', child: Text('Переименовать')),
                    const PopupMenuItem(
                        value: 'upload', child: Text('Загрузить')),
                    const PopupMenuItem(
                        value: 'delete', child: Text('Удалить')),
                    const PopupMenuItem(
                        value: 'properties', child: Text('Свойства')),
                    if (!entry.isDirectory &&
                        widget.controller
                            .isRunnableProjectFile(entry.relativePath))
                      const PopupMenuDivider(),
                    if (!entry.isDirectory &&
                        widget.controller
                            .isRunnableProjectFile(entry.relativePath))
                      const PopupMenuItem(
                          value: 'run', child: Text('Запустить в консоли')),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _editor() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Text(selectedRelativePath ?? 'Файл не выбран',
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              FilterChip(
                selected: widget.controller.editorWordWrap,
                label: const Text('Переносить по словам'),
                onSelected: (v) {
                  widget.controller.editorWordWrap = v;
                  widget.onChanged();
                  if (mounted) setState(() {});
                },
              ),
              FilledButton.icon(
                onPressed: selectedRelativePath == null || !selectedIsText
                    ? null
                    : () async {
                        final rel = selectedRelativePath!;
                        final result = selectedIsStructuredDocument
                            ? await widget.controller.editDocumentText(rel,
                                mode: 'replace_all',
                                text: editorController.text)
                            : await widget.controller
                                .writeRelativeFile(rel, editorController.text);
                        widget.onChanged();
                        await _showResult(result);
                      },
                icon: const Icon(Icons.save),
                label: Text(selectedIsStructuredDocument
                    ? 'Сохранить документ'
                    : 'Сохранить'),
              ),
            ],
          ),
          if (statusText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(statusText, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wrap = widget.controller.editorWordWrap;
                final longestLine = editorController.text.split('\n').fold<int>(
                    0, (value, line) => math.max(value, line.length));
                final editorWidth = wrap
                    ? constraints.maxWidth
                    : math.max(constraints.maxWidth, longestLine * 8.2 + 96);
                final field = SizedBox(
                  width: editorWidth,
                  child: TextField(
                    controller: editorController,
                    scrollController: verticalScrollController,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                        border: OutlineInputBorder(), alignLabelWithHint: true),
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                );
                final vertical = Scrollbar(
                  controller: verticalScrollController,
                  thumbVisibility: true,
                  child: field,
                );
                if (wrap) return vertical;
                return Scrollbar(
                  controller: horizontalScrollController,
                  thumbVisibility: true,
                  notificationPredicate: (notification) =>
                      notification.metrics.axis == Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: horizontalScrollController,
                    scrollDirection: Axis.horizontal,
                    child: vertical,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String truncateForSnack(String value) {
  final trimmed = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return trimmed.length <= 180 ? trimmed : '${trimmed.substring(0, 180)}...';
}
