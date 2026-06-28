import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/agent_controller.dart';
import '../core/models.dart';
import '../rendering/message_rendering.dart';
import '../utils/format_utils.dart';
import '../utils/path_utils.dart';
import '../dialogs/settings_dialogs.dart';

class ChatTab extends StatefulWidget {
  const ChatTab({
    super.key,
    required this.controller,
    required this.promptController,
    required this.attachmentPathController,
    required this.onChanged,
  });

  final AgentController controller;
  final TextEditingController promptController;
  final TextEditingController attachmentPathController;
  final VoidCallback onChanged;

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final ScrollController _scrollController = ScrollController();
  int _lastVisibleMessageCount = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.uiUpdater = _handleControllerUpdate;
    _scheduleScrollToBottom();
  }

  @override
  void didUpdateWidget(covariant ChatTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller.uiUpdater == _handleControllerUpdate) {
        oldWidget.controller.uiUpdater = null;
      }
      widget.controller.uiUpdater = _handleControllerUpdate;
    }
  }

  @override
  void dispose() {
    if (widget.controller.uiUpdater == _handleControllerUpdate) {
      widget.controller.uiUpdater = null;
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _handleControllerUpdate() {
    if (!mounted) return;
    final wasNearBottom = !_scrollController.hasClients ||
        (_scrollController.position.maxScrollExtent -
                _scrollController.position.pixels) <
            160;
    setState(() {});
    final visibleMessages = widget.controller.visibleMessages;
    final shouldFollow = wasNearBottom;
    if (shouldFollow && visibleMessages.isNotEmpty) _scheduleScrollToBottom();
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _submitPrompt() async {
    final controller = widget.controller;
    if (controller.busy) {
      controller.requestStop();
      widget.onChanged();
      return;
    }
    final prompt = widget.promptController.text;
    widget.promptController.clear();
    final future = controller.sendPrompt(prompt, '');
    widget.onChanged();
    await future;
    widget.attachmentPathController.clear();
    widget.onChanged();
  }

  Widget _adaptiveAction({
    required bool compact,
    required String tooltip,
    required Widget icon,
    required Widget label,
    required VoidCallback? onPressed,
    bool filled = false,
  }) {
    if (compact) {
      return filled
          ? IconButton.filled(
              tooltip: tooltip, onPressed: onPressed, icon: icon)
          : IconButton.outlined(
              tooltip: tooltip, onPressed: onPressed, icon: icon);
    }
    return filled
        ? FilledButton.icon(onPressed: onPressed, icon: icon, label: label)
        : OutlinedButton.icon(onPressed: onPressed, icon: icon, label: label);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final promptController = widget.promptController;
    final onChanged = widget.onChanged;
    final compactControls = MediaQuery.of(context).size.width < 720;
    final visibleMessages = controller.visibleMessages;
    if (_lastVisibleMessageCount != visibleMessages.length) {
      final shouldFollow = !_scrollController.hasClients ||
          (_scrollController.position.maxScrollExtent -
                  _scrollController.position.pixels) <
              160;
      _lastVisibleMessageCount = visibleMessages.length;
      if (shouldFollow) _scheduleScrollToBottom();
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Wrap(
            runSpacing: 8,
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 310,
                child: DropdownButtonFormField<String>(
                  initialValue: controller.selectedProfileId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Профиль',
                      border: OutlineInputBorder(),
                      isDense: true),
                  items: controller.profiles
                      .map((p) => DropdownMenuItem(
                          value: p.id,
                          child: Text('${p.name} • ${p.kind.label}')))
                      .toList(),
                  onChanged: (value) async {
                    if (value == null) return;
                    await controller.selectProfile(value);
                    onChanged();
                  },
                ),
              ),
              SizedBox(
                width: 330,
                child: DropdownButtonFormField<String>(
                  initialValue: controller.currentModelNameOrNull,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Модель',
                      border: OutlineInputBorder(),
                      isDense: true),
                  items: controller.availableModels
                      .map((m) => DropdownMenuItem(
                          value: m.name,
                          child: Text(m.name, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (value) async {
                    if (value == null) return;
                    await controller.selectModel(value);
                    onChanged();
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: controller.maxContextTokens == 0
                      ? 0
                      : (controller.estimatedContextTokens /
                              controller.maxContextTokens)
                          .clamp(0.0, 1.0)
                          .toDouble(),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Контекст: ${controller.estimatedContextTokens}/${controller.maxContextTokens} до сжатия',
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (controller.llamaMemoryStatus.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 3),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                controller.llamaMemoryStatus,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(fontSize: 10),
              ),
            ),
          ),
        Expanded(
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: ListView.builder(
              key: const PageStorageKey<String>('chat_messages_list'),
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: visibleMessages.length,
              itemBuilder: (context, index) {
                final message = visibleMessages[index];
                if (message.role == 'separator') {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(message.content,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                  );
                }
                return Align(
                  alignment: message.role == 'user'
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Card(
                    color: message.role == 'user'
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    message.role == 'user'
                                        ? 'Пользователь:'
                                        : 'Агент:',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                Text(formatMessageDateTime(message),
                                    style:
                                        Theme.of(context).textTheme.labelSmall),
                                PopupMenuButton<String>(
                                  tooltip: 'Действия с сообщением',
                                  onSelected: (value) async {
                                    if (value == 'copy') {
                                      await Clipboard.setData(
                                          ClipboardData(text: message.content));
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content: Text(
                                                    'Сообщение скопировано')));
                                      }
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                        value: 'copy',
                                        child: Text('Копировать'))
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            buildMessageContent(
                                context,
                                controller,
                                'msg:${message.id}',
                                message.content,
                                () => setState(() {})),
                            if (message.actionSummaries.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              ...message.actionSummaries.map((action) {
                                final key =
                                    '${message.id}:action:${action.key}';
                                final expanded =
                                    controller.expandedActionKey == key;
                                final okText =
                                    action.allSucceeded ? 'успешно' : 'ошибка';
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      InkWell(
                                        onTap: () {
                                          controller.expandedActionKey =
                                              expanded ? null : key;
                                          setState(() {});
                                        },
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                                expanded
                                                    ? Icons.expand_less
                                                    : Icons.expand_more,
                                                size: 18),
                                            const SizedBox(width: 4),
                                            Flexible(
                                                child: Text(action.title,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600))),
                                            const SizedBox(width: 8),
                                            Text(
                                                'попыток: ${action.attempts.length}, $okText'),
                                          ],
                                        ),
                                      ),
                                      if (!expanded &&
                                          action.latestPreview.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              left: 26, top: 3),
                                          child: Text(
                                            action.latestPreview,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant),
                                          ),
                                        ),
                                      if (expanded)
                                        Container(
                                          width: double.infinity,
                                          margin: const EdgeInsets.only(top: 6),
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                                color: Theme.of(context)
                                                    .dividerColor),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                                maxHeight: 420),
                                            child: SingleChildScrollView(
                                              child: buildMessageContent(
                                                  context,
                                                  controller,
                                                  '$key:expanded',
                                                  action.expandedText,
                                                  () => setState(() {})),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                            if (message.fileChanges.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              ...message.fileChanges.map((change) {
                                final key = '${message.id}:${change.path}';
                                final expanded =
                                    controller.expandedDiffKey == key;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      InkWell(
                                        onTap: () {
                                          controller.expandedDiffKey =
                                              expanded ? null : key;
                                          setState(() {});
                                        },
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                                expanded
                                                    ? Icons.expand_less
                                                    : Icons.expand_more,
                                                size: 18),
                                            const SizedBox(width: 4),
                                            Text(change.path,
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600)),
                                            const SizedBox(width: 8),
                                            Text(
                                                '+${change.addedLines} / -${change.removedLines}'),
                                          ],
                                        ),
                                      ),
                                      if (expanded)
                                        Container(
                                          width: double.infinity,
                                          margin: const EdgeInsets.only(top: 6),
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                                color: Theme.of(context)
                                                    .dividerColor),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                                maxHeight: 420),
                                            child: SingleChildScrollView(
                                              child: SelectableText(
                                                  change.diff.isEmpty
                                                      ? '(нет текстового diff)'
                                                      : change.diff),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _adaptiveAction(
                      compact: compactControls,
                      tooltip: 'Прикрепить файл',
                      onPressed: () async {
                        final picked = await showDialog<String>(
                          context: context,
                          builder: (_) => EmbeddedFilePickerDialog(
                              initialDirectory: Directory.current.path),
                        );
                        if (picked != null && picked.isNotEmpty) {
                          controller.addAttachment(picked);
                          onChanged();
                        }
                      },
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Прикрепить файл'),
                    ),
                    _adaptiveAction(
                      compact: compactControls,
                      tooltip: 'Выбрать расположение',
                      onPressed: () async {
                        final initial =
                            controller.lastDeviceDirectoryPath.trim().isNotEmpty
                                ? controller.lastDeviceDirectoryPath
                                : (controller.currentProject?.path ??
                                    Directory.current.path);
                        final picked = await showDialog<String>(
                          context: context,
                          builder: (_) => EmbeddedFilePickerDialog(
                              initialDirectory: initial, selectDirectory: true),
                        );
                        if (picked != null && picked.isNotEmpty) {
                          controller.addSelectedLocation(picked);
                          if (!controller.isPathInsideAllowedSandbox(picked)) {
                            controller.allowDeviceFileAccess = true;
                            await controller.saveProjectPermissions();
                          }
                          onChanged();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content:
                                    Text('Расположение выбрано: $picked')));
                          }
                        }
                      },
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Выбрать расположение'),
                    ),
                    _adaptiveAction(
                      compact: compactControls,
                      tooltip: 'Копировать весь диалог',
                      onPressed: controller.messages.isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(ClipboardData(
                                  text: controller.fullDialogText()));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Диалог скопирован')));
                              }
                            },
                      icon: const Icon(Icons.copy_all),
                      label: const Text('Копировать весь диалог'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...controller.attachedFiles.map((path) => InputChip(
                          avatar: const Icon(Icons.description, size: 18),
                          label: Text(pathBasename(path),
                              overflow: TextOverflow.ellipsis),
                          tooltip: path,
                          onDeleted: () {
                            controller.removeAttachment(path);
                            onChanged();
                          },
                        )),
                    ...controller.selectedLocations.map((path) => InputChip(
                          avatar: const Icon(Icons.folder, size: 18),
                          label: Text('Расположение: ${pathBasename(path)}',
                              overflow: TextOverflow.ellipsis),
                          tooltip: path,
                          onDeleted: () {
                            controller.removeSelectedLocation(path);
                            onChanged();
                          },
                        )),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Shortcuts(
                      shortcuts: const <ShortcutActivator, Intent>{
                        SingleActivator(LogicalKeyboardKey.enter, shift: true):
                            ActivateIntent(),
                      },
                      child: Actions(
                        actions: <Type, Action<Intent>>{
                          ActivateIntent: CallbackAction<ActivateIntent>(
                            onInvoke: (_) {
                              unawaited(_submitPrompt());
                              return null;
                            },
                          ),
                        },
                        child: TextField(
                          controller: promptController,
                          minLines: 3,
                          maxLines: 9,
                          keyboardType: TextInputType.multiline,
                          decoration: const InputDecoration(
                            labelText: 'Многострочный промт',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PopupMenuButton<String>(
                        tooltip: 'Права',
                        position: PopupMenuPosition.under,
                        onSelected: (selected) async {
                          if (selected == 'approval')
                            controller.permissionMode =
                                PermissionMode.askEveryAction;
                          if (selected == 'critical')
                            controller.permissionMode =
                                PermissionMode.askCriticalOnly;
                          if (selected == 'full')
                            controller.permissionMode =
                                PermissionMode.fullAccess;
                          if (selected == 'toggle_internet')
                            controller.allowInternetUse =
                                !controller.allowInternetUse;
                          if (selected == 'toggle_search')
                            controller.allowComputerSearch =
                                !controller.allowComputerSearch;
                          if (selected == 'toggle_files')
                            controller.allowDeviceFileAccess =
                                !controller.allowDeviceFileAccess;
                          if (selected == 'toggle_suggestions')
                            controller.allowFollowUpSuggestions =
                                !controller.allowFollowUpSuggestions;
                          if (selected.startsWith('mode:')) {
                            controller.creationMode = CreationMode.values
                                .firstWhere(
                                    (m) => m.name == selected.substring(5),
                                    orElse: () => controller.creationMode);
                          }
                          await controller.saveProjectPermissions();
                          onChanged();
                        },
                        itemBuilder: (_) => [
                          CheckedPopupMenuItem(
                              value: 'approval',
                              checked: controller.permissionMode ==
                                  PermissionMode.askEveryAction,
                              child: const Text('Запрашивать каждое действие',
                                  style: TextStyle(fontSize: 12))),
                          CheckedPopupMenuItem(
                              value: 'critical',
                              checked: controller.permissionMode ==
                                  PermissionMode.askCriticalOnly,
                              child: const Text('Запрашивать только критичные',
                                  style: TextStyle(fontSize: 12))),
                          CheckedPopupMenuItem(
                              value: 'full',
                              checked: controller.permissionMode ==
                                  PermissionMode.fullAccess,
                              child: const Text('Полный доступ',
                                  style: TextStyle(fontSize: 12))),
                          const PopupMenuDivider(),
                          CheckedPopupMenuItem(
                              value: 'toggle_internet',
                              checked: controller.allowInternetUse,
                              child: const Text('Интернет-инструменты агента',
                                  style: TextStyle(fontSize: 12))),
                          CheckedPopupMenuItem(
                              value: 'toggle_search',
                              checked: controller.allowComputerSearch,
                              child: const Text(
                                  'Поиск по файловой системе устройства',
                                  style: TextStyle(fontSize: 12))),
                          CheckedPopupMenuItem(
                              value: 'toggle_files',
                              checked: controller.allowDeviceFileAccess,
                              child: const Text('Доступ к файлам устройства',
                                  style: TextStyle(fontSize: 12))),
                          CheckedPopupMenuItem(
                              value: 'toggle_suggestions',
                              checked: controller.allowFollowUpSuggestions,
                              child: const Text(
                                  'Предложения дальнейших действий',
                                  style: TextStyle(fontSize: 12))),
                          const PopupMenuDivider(),
                          ...CreationMode.values.map((m) =>
                              CheckedPopupMenuItem(
                                  value: 'mode:${m.name}',
                                  checked: controller.creationMode == m,
                                  child: Text(m.label,
                                      style: const TextStyle(fontSize: 12)))),
                        ],
                        child: Container(
                          width: compactControls ? 40 : null,
                          height: compactControls ? 40 : null,
                          padding: EdgeInsets.symmetric(
                              horizontal: compactControls ? 0 : 12,
                              vertical: 8),
                          decoration: BoxDecoration(
                              border: Border.all(
                                  color: Theme.of(context).colorScheme.outline),
                              borderRadius: BorderRadius.circular(20)),
                          child: compactControls
                              ? const Icon(Icons.verified_user, size: 18)
                              : const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                      Icon(Icons.verified_user, size: 18),
                                      SizedBox(width: 8),
                                      Text('Права')
                                    ]),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _adaptiveAction(
                        compact: compactControls,
                        tooltip: controller.busy ? 'Стоп' : 'Отправить',
                        filled: true,
                        onPressed: () => unawaited(_submitPrompt()),
                        icon: Icon(controller.busy ? Icons.stop : Icons.send),
                        label: Text(controller.busy ? 'Стоп' : 'Отправить'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
