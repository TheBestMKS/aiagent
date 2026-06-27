import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_constants.dart';
import '../controllers/agent_controller.dart';
import '../core/models.dart';
import '../utils/path_utils.dart';

class ModelProfilesDialog extends StatelessWidget {
  const ModelProfilesDialog(
      {super.key, required this.controller, required this.onChanged});
  final AgentController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Модели'),
      content: SizedBox(
        width: 760,
        height: 680,
        child: SettingsTab(controller: controller, onChanged: onChanged),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'))
      ],
    );
  }
}

class SettingsTab extends StatefulWidget {
  const SettingsTab(
      {super.key, required this.controller, required this.onChanged});

  final AgentController controller;
  final VoidCallback onChanged;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController baseUrlController = TextEditingController();
  final TextEditingController apiKeyController = TextEditingController();
  final TextEditingController modelController = TextEditingController();
  final TextEditingController contextController =
      TextEditingController(text: '131072');
  final TextEditingController outputController =
      TextEditingController(text: '16384');
  final TextEditingController probeHostController =
      TextEditingController(text: '127.0.0.1');
  final TextEditingController probePortsController =
      TextEditingController(text: '1234,8080,8000,5000');
  final TextEditingController llamaDirController = TextEditingController();
  final TextEditingController modelPathController = TextEditingController();
  final TextEditingController mmprojPathController = TextEditingController();
  final TextEditingController llamaPortController =
      TextEditingController(text: '1234');
  String profileKind = ProfileKind.openAiCompatible.name;
  String llamaMode = 'cpu';
  bool streamResponses = true;

  @override
  void dispose() {
    nameController.dispose();
    baseUrlController.dispose();
    apiKeyController.dispose();
    modelController.dispose();
    contextController.dispose();
    outputController.dispose();
    probeHostController.dispose();
    probePortsController.dispose();
    llamaDirController.dispose();
    modelPathController.dispose();
    mmprojPathController.dispose();
    llamaPortController.dispose();
    super.dispose();
  }

  void loadProfile(ModelProfile profile) {
    nameController.text = profile.name;
    baseUrlController.text = profile.baseUrl;
    apiKeyController.text = profile.apiKey;
    modelController.text = profile.model;
    contextController.text = profile.maxContextTokens.toString();
    outputController.text = profile.maxOutputTokens.toString();
    profileKind = profile.kind.name;
    llamaDirController.text = profile.llamaDir;
    modelPathController.text = profile.modelPath;
    mmprojPathController.text = profile.mmprojPath;
    llamaPortController.text = profile.llamaPort.toString();
    llamaMode = profile.llamaMode.trim().isEmpty ? 'cpu' : profile.llamaMode;
    streamResponses = profile.streamResponses;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final selected = controller.currentProfile;
    if (selected != null && nameController.text.isEmpty) loadProfile(selected);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Профили моделей',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: controller.profiles
              .map(
                (p) => ChoiceChip(
                  label: Text('${p.name} • ${p.kind.label}'),
                  selected: p.id == controller.selectedProfileId,
                  onSelected: (_) async {
                    await controller.selectProfile(p.id);
                    loadProfile(p);
                    widget.onChanged();
                    setState(() {});
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 16),
        TextField(
            controller: nameController,
            decoration: const InputDecoration(
                labelText: 'Название профиля', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: profileKind,
          decoration: const InputDecoration(
              labelText: 'Тип профиля', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(
                value: 'openAiCompatible', child: Text('Удаленная модель')),
            DropdownMenuItem(
                value: 'localLlama', child: Text('Локальная модель')),
          ],
          onChanged: (value) =>
              setState(() => profileKind = value ?? 'openAiCompatible'),
        ),
        const SizedBox(height: 8),
        if (profileKind == ProfileKind.localLlama.name) ...[
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: llamaMode,
                  decoration: const InputDecoration(
                      labelText: 'Backend', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'cpu', child: Text('CPU')),
                    DropdownMenuItem(value: 'vulkan', child: Text('Vulkan')),
                    DropdownMenuItem(value: 'cuda', child: Text('CUDA')),
                  ],
                  onChanged: (value) =>
                      setState(() => llamaMode = value ?? 'cpu'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: llamaPortController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Порт llama-server',
                      border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: llamaDirController,
            decoration: const InputDecoration(
                labelText: 'Папка llama.cpp backend',
                hintText: 'tools/llama.cpp/cpu',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: modelPathController,
            decoration: const InputDecoration(
                labelText: 'Файл модели .gguf', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: mmprojPathController,
            decoration: const InputDecoration(
                labelText: 'mmproj .gguf (необязательно)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
            controller: baseUrlController,
            decoration: const InputDecoration(
                labelText: 'Base URL /v1', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(
            controller: modelController,
            decoration: const InputDecoration(
                labelText: 'Model', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(
            controller: apiKeyController,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'API key', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: TextField(
                    controller: contextController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Context window tokens',
                        border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: outputController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Max output tokens',
                        border: OutlineInputBorder()))),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          value: streamResponses,
          title: const Text('Потоковое получение ответа'),
          subtitle: const Text(
              'Включено по умолчанию. Помогает тяжёлым моделям долго отвечать без TimeoutException.'),
          onChanged: (v) => setState(() => streamResponses = v),
        ),
        const SizedBox(height: 8),
        const Text(
            'Важно: контекст модели и длина ответа — разные лимиты. Для моделей с 131072 контекста можно оставить Context window = 131072, а Max output увеличить, чтобы tool-call не обрывался.'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () async {
                final profile = profileKind == ProfileKind.localLlama.name
                    ? ModelProfile.localLlama(
                        name: nameController.text.trim().isEmpty
                            ? 'llama.cpp'
                            : nameController.text.trim(),
                        baseUrl: baseUrlController.text.trim().isEmpty
                            ? 'http://127.0.0.1:${int.tryParse(llamaPortController.text.trim()) ?? 1234}/v1'
                            : baseUrlController.text.trim(),
                        model: modelController.text.trim().isEmpty
                            ? pathBasename(modelPathController.text.trim())
                            : modelController.text.trim(),
                        modelPath: modelPathController.text.trim(),
                        mmprojPath: mmprojPathController.text.trim(),
                        llamaMode: llamaMode,
                        llamaDir: llamaDirController.text.trim(),
                        llamaPort:
                            int.tryParse(llamaPortController.text.trim()) ??
                                1234,
                        llamaSettings:
                            controller.currentProfile?.llamaSettings ??
                                const LlamaSettings(),
                        maxOutputTokens:
                            int.tryParse(outputController.text.trim()) ?? 16384,
                        streamResponses: streamResponses,
                      )
                    : ModelProfile.openAiCompatible(
                        name: nameController.text.trim().isEmpty
                            ? 'OpenAI-compatible'
                            : nameController.text.trim(),
                        baseUrl: baseUrlController.text.trim(),
                        model: modelController.text.trim(),
                        apiKey: apiKeyController.text.trim(),
                        maxContextTokens:
                            int.tryParse(contextController.text.trim()) ??
                                131072,
                        maxOutputTokens:
                            int.tryParse(outputController.text.trim()) ?? 16384,
                        streamResponses: streamResponses,
                      );
                await controller.upsertProfile(profile, select: true);
                widget.onChanged();
                setState(() {});
              },
              icon: const Icon(Icons.save),
              label: const Text('Сохранить профиль'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await showDialog<void>(
                  context: context,
                  builder: (_) => LlamaSettingsDialog(
                      controller: controller, onChanged: widget.onChanged),
                );
                setState(() {});
              },
              icon: const Icon(Icons.tune),
              label: const Text('Настройки llama.cpp'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final candidates = await controller.scanLocalLlamaCandidates();
                if (!mounted) return;
                await showDialog<void>(
                  context: context,
                  builder: (_) => LocalLlamaStartupDialog(
                      candidates: candidates,
                      controller: controller,
                      onChanged: widget.onChanged),
                );
                setState(() {});
              },
              icon: const Icon(Icons.memory),
              label: const Text('Найти llama.cpp/models'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await showDialog<void>(
                  context: context,
                  builder: (_) => LlamaCppInstallDialog(
                      controller: controller, onChanged: widget.onChanged),
                );
                setState(() {});
              },
              icon: const Icon(Icons.download),
              label: const Text('Загрузить llama.cpp'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await showDialog<void>(
                  context: context,
                  builder: (_) => HuggingFaceModelDialog(
                      controller: controller, onChanged: widget.onChanged),
                );
                setState(() {});
              },
              icon: const Icon(Icons.cloud_download),
              label: const Text('Модели HuggingFace'),
            ),
          ],
        ),
        const Divider(height: 32),
        const Text('Опрос по IP и порту',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: TextField(
                    controller: probeHostController,
                    decoration: const InputDecoration(
                        labelText: 'IP/host', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: probePortsController,
                    decoration: const InputDecoration(
                        labelText: 'Порты через запятую',
                        border: OutlineInputBorder()))),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            final found = await controller.probeOpenAiCompatible(
                probeHostController.text, probePortsController.text);
            if (!mounted) return;
            await showDialog<void>(
              context: context,
              builder: (_) => ProbeResultsDialog(
                  found: found,
                  controller: controller,
                  onChanged: widget.onChanged),
            );
            setState(() {});
          },
          icon: const Icon(Icons.search),
          label: const Text('Опросить и создать профиль'),
        ),
        const Divider(height: 32),
        Text(
            'Текущий контекст: ${controller.estimatedContextTokens}/${controller.maxContextTokens}; max output: ${controller.maxOutputTokens}'),
        Text('Distrib: ${controller.distribRoot.path}'),
      ],
    );
  }
}

class LlamaCppInstallDialog extends StatefulWidget {
  const LlamaCppInstallDialog(
      {super.key, required this.controller, required this.onChanged});
  final AgentController controller;
  final VoidCallback onChanged;

  @override
  State<LlamaCppInstallDialog> createState() => _LlamaCppInstallDialogState();
}

class _LlamaCppInstallDialogState extends State<LlamaCppInstallDialog> {
  String mode = 'cpu';
  String result = '';
  bool busy = false;
  final TextEditingController archiveController = TextEditingController();

  @override
  void dispose() {
    archiveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Загрузка и установка llama.cpp'),
      content: SizedBox(
        width: 720,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Программа скачает подходящий архив из последнего релиза GitHub ggml-org/llama.cpp и распакует его в tooling/llama.cpp/<режим>. На Android будет выбран Android-архив, если он есть в релизе.'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: mode,
              decoration: const InputDecoration(
                  labelText: 'Вариант работы', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'cpu', child: Text('CPU')),
                DropdownMenuItem(value: 'vulkan', child: Text('Vulkan')),
                DropdownMenuItem(value: 'cuda', child: Text('CUDA')),
              ],
              onChanged: busy ? null : (v) => setState(() => mode = v ?? 'cpu'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: archiveController,
              decoration: const InputDecoration(
                labelText: 'ZIP/архив llama.cpp',
                hintText: 'Можно указать путь к скачанному архиву',
                border: OutlineInputBorder(),
              ),
              enabled: !busy,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          final picked = await showDialog<String>(
                            context: context,
                            builder: (_) => EmbeddedFilePickerDialog(
                              initialDirectory:
                                  widget.controller.downloadsRoot.path,
                            ),
                          );
                          if (picked != null && picked.isNotEmpty) {
                            archiveController.text = picked;
                          }
                        },
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('Выбрать архив'),
                ),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          setState(() {
                            busy = true;
                            result = 'Создание папок tools/llama.cpp...';
                          });
                          final r = await widget.controller
                              .createLlamaCppManualFolders();
                          widget.onChanged();
                          if (mounted) {
                            setState(() {
                              result = r;
                              busy = false;
                            });
                          }
                        },
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Создать папки'),
                ),
                OutlinedButton.icon(
                  onPressed: busy || archiveController.text.trim().isEmpty
                      ? null
                      : () async {
                          setState(() {
                            busy = true;
                            result = 'Установка llama.cpp из архива...';
                          });
                          final r = await widget.controller
                              .installLlamaCppFromArchive(
                            archiveController.text.trim(),
                            mode,
                          );
                          widget.onChanged();
                          if (mounted) {
                            setState(() {
                              result = r;
                              busy = false;
                            });
                          }
                        },
                  icon: const Icon(Icons.unarchive_outlined),
                  label: const Text('Установить из архива'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (busy) const LinearProgressIndicator(),
            if (result.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8)),
                child: SelectableText(result),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Закрыть')),
        FilledButton.icon(
          onPressed: busy
              ? null
              : () async {
                  setState(() {
                    busy = true;
                    result = 'Загрузка llama.cpp...';
                  });
                  final r =
                      await widget.controller.installLlamaCppFromGithub(mode);
                  widget.onChanged();
                  if (mounted)
                    setState(() {
                      result = r;
                      busy = false;
                    });
                },
          icon: const Icon(Icons.download),
          label: const Text('Скачать и установить'),
        ),
      ],
    );
  }
}

class HuggingFaceModelDialog extends StatefulWidget {
  const HuggingFaceModelDialog(
      {super.key, required this.controller, required this.onChanged});
  final AgentController controller;
  final VoidCallback onChanged;

  @override
  State<HuggingFaceModelDialog> createState() => _HuggingFaceModelDialogState();
}

class _HuggingFaceModelDialogState extends State<HuggingFaceModelDialog> {
  final TextEditingController queryController =
      TextEditingController(text: 'gguf');
  List<HfModelSearchResult> models = const [];
  List<HfFileEntry> files = const [];
  HfModelSearchResult? selectedModel;
  HfFileEntry? selectedFile;
  String result = '';
  bool busy = false;

  @override
  void dispose() {
    queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Поиск и загрузка моделей HuggingFace'),
      content: SizedBox(
        width: 820,
        height: 620,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                    child: TextField(
                        controller: queryController,
                        decoration: const InputDecoration(
                            labelText: 'Поиск на huggingface.co',
                            border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          setState(() {
                            busy = true;
                            result = 'Поиск моделей...';
                            models = const [];
                            files = const [];
                            selectedModel = null;
                            selectedFile = null;
                          });
                          try {
                            final r = await widget.controller
                                .searchHuggingFaceGgufModels(
                                    queryController.text);
                            if (mounted)
                              setState(() {
                                models = r;
                                result = 'Найдено моделей: ${r.length}';
                              });
                          } catch (e) {
                            if (mounted)
                              setState(() => result = 'Ошибка поиска: $e');
                          } finally {
                            if (mounted) setState(() => busy = false);
                          }
                        },
                  icon: const Icon(Icons.search),
                  label: const Text('Найти'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (busy) const LinearProgressIndicator(),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: ListView(
                      children: models
                          .map((m) => ListTile(
                                dense: true,
                                selected: selectedModel?.id == m.id,
                                title: Text(m.id),
                                subtitle: Text('downloads: ${m.downloads}'),
                                onTap: busy
                                    ? null
                                    : () async {
                                        setState(() {
                                          selectedModel = m;
                                          files = const [];
                                          selectedFile = null;
                                          busy = true;
                                          result = 'Чтение файлов ${m.id}...';
                                        });
                                        try {
                                          final f = await widget.controller
                                              .listHuggingFaceGgufFiles(m.id);
                                          if (mounted)
                                            setState(() {
                                              files = f;
                                              result =
                                                  'Файлов *.gguf/mmproj: ${f.length}';
                                            });
                                        } catch (e) {
                                          if (mounted)
                                            setState(() => result =
                                                'Ошибка чтения файлов: $e');
                                        } finally {
                                          if (mounted)
                                            setState(() => busy = false);
                                        }
                                      },
                              ))
                          .toList(),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: RadioGroup<HfFileEntry>(
                      groupValue: selectedFile,
                      onChanged: (v) {
                        if (!busy) setState(() => selectedFile = v);
                      },
                      child: ListView(
                        children: files
                            .map((f) => RadioListTile<HfFileEntry>(
                                  dense: true,
                                  value: f,
                                  enabled: !busy,
                                  title: Text(f.path),
                                  subtitle: Text(formatBytes(f.size)),
                                ))
                            .toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (result.isNotEmpty)
              Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(result)),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Закрыть')),
        FilledButton.icon(
          onPressed: busy || selectedFile == null
              ? null
              : () async {
                  final f = selectedFile!;
                  setState(() {
                    busy = true;
                    result = 'Загрузка ${f.path}...';
                  });
                  final r = await widget.controller.downloadHuggingFaceFile(f);
                  widget.onChanged();
                  if (mounted)
                    setState(() {
                      result = r;
                      busy = false;
                    });
                },
          icon: const Icon(Icons.download),
          label: const Text('Скачать выбранный файл'),
        ),
      ],
    );
  }
}

class LocalLlamaStartupDialog extends StatefulWidget {
  const LocalLlamaStartupDialog(
      {super.key,
      required this.candidates,
      required this.controller,
      required this.onChanged});

  final List<LocalLlamaCandidate> candidates;
  final AgentController controller;
  final VoidCallback onChanged;

  @override
  State<LocalLlamaStartupDialog> createState() =>
      _LocalLlamaStartupDialogState();
}

class _LocalLlamaStartupDialogState extends State<LocalLlamaStartupDialog> {
  LocalLlamaCandidate? selected;
  final TextEditingController portController =
      TextEditingController(text: '1234');

  @override
  void initState() {
    super.initState();
    selected = widget.candidates.isEmpty ? null : widget.candidates.first;
  }

  @override
  void dispose() {
    portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Найден локальный llama.cpp'),
      content: SizedBox(
        width: 650,
        child: widget.candidates.isEmpty
            ? const Text('Папки llama.cpp/cpu|vulkan|cuda и models не найдены.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<LocalLlamaCandidate>(
                    initialValue: selected,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Модель и режим',
                        border: OutlineInputBorder()),
                    items: widget.candidates
                        .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(
                                '${c.mode} • ${pathBasename(c.modelPath)}')))
                        .toList(),
                    onChanged: (value) => setState(() => selected = value),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                      controller: portController,
                      decoration: const InputDecoration(
                          labelText: 'Порт llama-server',
                          border: OutlineInputBorder())),
                  const SizedBox(height: 8),
                  const Text(
                      'Будет создан профиль. На Windows/Linux/macOS приложение запускает llama-server как внешний процесс. На Android загрузка llama.cpp и моделей поддержана в файловой структуре приложения; запуск доступен при наличии совместимого нативного llama-server в выбранной папке.'),
                ],
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Пропустить')),
        FilledButton(
          onPressed: selected == null
              ? null
              : () async {
                  await widget.controller.createLocalLlamaProfile(
                      selected!, int.tryParse(portController.text) ?? 1234,
                      startNow: true);
                  widget.onChanged();
                  if (context.mounted) Navigator.pop(context);
                },
          child: const Text('Создать и запустить'),
        ),
      ],
    );
  }
}

class LlamaSettingsDialog extends StatefulWidget {
  const LlamaSettingsDialog(
      {super.key, required this.controller, required this.onChanged});

  final AgentController controller;
  final VoidCallback onChanged;

  @override
  State<LlamaSettingsDialog> createState() => _LlamaSettingsDialogState();
}

class _LlamaSettingsDialogState extends State<LlamaSettingsDialog> {
  late LlamaSettings settings;

  @override
  void initState() {
    super.initState();
    settings = widget.controller.currentProfile?.llamaSettings ??
        const LlamaSettings();
  }

  @override
  Widget build(BuildContext context) {
    final fields = <Widget>[
      _intField('Длина контекста', settings.contextLength,
          (v) => settings = settings.copyWith(contextLength: v)),
      _intField('Максимально поддерживаемая',
          widget.controller.maxContextTokens, (_) {}),
      _intField('Max output tokens профиля', widget.controller.maxOutputTokens,
          (_) {}),
      _intField('Слоёв на GPU', settings.gpuLayers,
          (v) => settings = settings.copyWith(gpuLayers: v)),
      _intField('Пул потоков CPU', settings.cpuThreads,
          (v) => settings = settings.copyWith(cpuThreads: v)),
      _intField('Размер пакета оценки', settings.batchSize,
          (v) => settings = settings.copyWith(batchSize: v)),
      _intField('Max Concurrent Predictions', settings.maxConcurrentPredictions,
          (v) => settings = settings.copyWith(maxConcurrentPredictions: v)),
      _doubleField('Основа частоты RoPE', settings.ropeFreqBase,
          (v) => settings = settings.copyWith(ropeFreqBase: v)),
      _doubleField('Масштаб частоты RoPE', settings.ropeFreqScale,
          (v) => settings = settings.copyWith(ropeFreqScale: v)),
      _intField(
          'Сид', settings.seed, (v) => settings = settings.copyWith(seed: v)),
      _textField('Квант K-кэша', settings.cacheKQuantization,
          (v) => settings = settings.copyWith(cacheKQuantization: v)),
      _textField('Квант V-кэша', settings.cacheVQuantization,
          (v) => settings = settings.copyWith(cacheVQuantization: v)),
      SwitchListTile(
          value: settings.unifiedKvCache,
          title: const Text('Unified KV Cache'),
          onChanged: (v) =>
              setState(() => settings = settings.copyWith(unifiedKvCache: v))),
      SwitchListTile(
          value: settings.experimental,
          title: const Text('Experimental'),
          onChanged: (v) =>
              setState(() => settings = settings.copyWith(experimental: v))),
      SwitchListTile(
          value: settings.offloadKvCache,
          title: const Text('Offload KV Cache to GPU Memory'),
          onChanged: (v) =>
              setState(() => settings = settings.copyWith(offloadKvCache: v))),
      SwitchListTile(
          value: settings.keepModelInMemory,
          title: const Text('Хранить модель в памяти'),
          onChanged: (v) => setState(
              () => settings = settings.copyWith(keepModelInMemory: v))),
      SwitchListTile(
          value: settings.tryMmap,
          title: const Text('Попробовать mmap()'),
          onChanged: (v) =>
              setState(() => settings = settings.copyWith(tryMmap: v))),
      SwitchListTile(
          value: settings.randomSeed,
          title: const Text('Случайный сид'),
          onChanged: (v) =>
              setState(() => settings = settings.copyWith(randomSeed: v))),
      SwitchListTile(
          value: settings.flashAttention,
          title: const Text('Flash Attention'),
          onChanged: (v) =>
              setState(() => settings = settings.copyWith(flashAttention: v))),
    ];
    return AlertDialog(
      title: const Text('Дополнительные настройки модели'),
      content: SizedBox(
        width: 680,
        height: 620,
        child: ListView(children: fields),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена')),
        FilledButton(
          onPressed: () async {
            await widget.controller.updateCurrentLlamaSettings(settings);
            widget.onChanged();
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }

  Widget _intField(String label, int value, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: TextFormField(
        initialValue: value.toString(),
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        onChanged: (text) => onChanged(int.tryParse(text) ?? value),
      ),
    );
  }

  Widget _doubleField(
      String label, double value, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: TextFormField(
        initialValue: value.toString(),
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        onChanged: (text) =>
            onChanged(double.tryParse(text.replaceAll(',', '.')) ?? value),
      ),
    );
  }

  Widget _textField(
      String label, String value, ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: TextFormField(
        initialValue: value,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        onChanged: onChanged,
      ),
    );
  }
}

class ProbeResultsDialog extends StatelessWidget {
  const ProbeResultsDialog(
      {super.key,
      required this.found,
      required this.controller,
      required this.onChanged});

  final List<ModelProfile> found;
  final AgentController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Найденные профили'),
      content: SizedBox(
        width: 640,
        child: found.isEmpty
            ? const Text('Подходящие OpenAI-compatible endpoints не найдены.')
            : ListView.builder(
                shrinkWrap: true,
                itemCount: found.length,
                itemBuilder: (context, index) {
                  final profile = found[index];
                  return ListTile(
                    title: Text(profile.name),
                    subtitle: Text('${profile.baseUrl}\n${profile.model}'),
                    onTap: () async {
                      await controller.upsertProfile(profile, select: true);
                      onChanged();
                      if (context.mounted) Navigator.pop(context);
                    },
                  );
                },
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'))
      ],
    );
  }
}

class KnowledgeBaseDialog extends StatefulWidget {
  const KnowledgeBaseDialog({super.key, required this.controller});
  final AgentController controller;

  @override
  State<KnowledgeBaseDialog> createState() => _KnowledgeBaseDialogState();
}

class _KnowledgeBaseDialogState extends State<KnowledgeBaseDialog> {
  String text = 'Загрузка...';

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    final records = await widget.controller.readKnowledgeRecords();
    final buffer = StringBuffer('Записей: ${records.length}\n\n');
    for (final r in records.reversed.take(80)) {
      buffer.writeln('### ${r['topic'] ?? ''}');
      if ((r['source'] ?? '').toString().isNotEmpty)
        buffer.writeln('Источник: ${r['source']}');
      if ((r['tags'] ?? '').toString().isNotEmpty)
        buffer.writeln('Теги: ${r['tags']}');
      buffer.writeln(truncateMiddle((r['content'] ?? '').toString(), 1200));
      buffer.writeln('\n---\n');
    }
    if (mounted) setState(() => text = buffer.toString());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('База знаний агента'),
      content: SizedBox(
        width: 760,
        height: 620,
        child: DecoratedBox(
          decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8)),
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(12), child: SelectableText(text)),
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () async {
            final result = await widget.controller.exportKnowledgeBase();
            if (!mounted) return;
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(result)));
            await load();
          },
          icon: const Icon(Icons.archive),
          label: const Text('Экспорт ZIP'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await showDialog<String>(
                context: context,
                builder: (_) => EmbeddedFilePickerDialog(
                    initialDirectory: widget.controller.configRoot.path));
            if (picked == null) return;
            final result = await widget.controller.importKnowledgeBase(picked);
            if (!mounted) return;
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(result)));
            await load();
          },
          icon: const Icon(Icons.upload_file),
          label: const Text('Импорт ZIP/JSONL'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (context.mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('База знаний скопирована')));
          },
          icon: const Icon(Icons.copy),
          label: const Text('Копировать'),
        ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть')),
      ],
    );
  }
}

class ExecutionLogDialog extends StatefulWidget {
  const ExecutionLogDialog({super.key, required this.controller});

  final AgentController controller;

  @override
  State<ExecutionLogDialog> createState() => _ExecutionLogDialogState();
}

class _ExecutionLogDialogState extends State<ExecutionLogDialog> {
  @override
  Widget build(BuildContext context) {
    final text = widget.controller.executionLog.join('\n');
    return AlertDialog(
      title: const Text('Подробные логи выполнения'),
      content: SizedBox(
        width: 900,
        height: 650,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SelectableText(text.isEmpty ? 'Лог пока пуст.' : text),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.controller.clearExecutionLog();
            setState(() {});
          },
          child: const Text('Очистить'),
        ),
        FilledButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Лог скопирован')));
            }
          },
          icon: const Icon(Icons.copy),
          label: const Text('Копировать'),
        ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть')),
      ],
    );
  }
}

class AboutProgramDialog extends StatelessWidget {
  const AboutProgramDialog({super.key, required this.controller});

  final AgentController controller;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('О программе'),
      content: const SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(appName,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text('Версия: $appVersion'),
            SizedBox(height: 12),
            Text('Создатель программы: Редин Максим Юрьевич'),
            Text('Контактные данные: info@thebestmks.ru'),
            SizedBox(height: 12),
            Text(
                'AI Agent — локальная оболочка для работы с ИИ-агентом, проектами, файлами, консолью, Web и инструментами разработки.'),
          ],
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () async {
            await showDialog<void>(
                context: context,
                builder: (_) => ExecutionLogDialog(controller: controller));
          },
          icon: const Icon(Icons.article_outlined),
          label: const Text('Подробные логи выполнения'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final tools = controller.buildOpenAiToolDefinitions().map((tool) {
              final fn =
                  (tool['function'] as Map<String, Object?>?) ?? const {};
              return '- ${fn['name']}: ${fn['description']}';
            }).join('\n');
            await showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Инструменты агента'),
                content: SizedBox(
                  width: 760,
                  height: 560,
                  child: SingleChildScrollView(
                    child: SelectableText(
                        '$tools\n\nCustom/automation:\n${controller.automationSummaryForPrompt()}'),
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Закрыть'))
                ],
              ),
            );
          },
          icon: const Icon(Icons.construction_outlined),
          label: const Text('Инструменты агента'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            await showDialog<void>(
                context: context,
                builder: (_) =>
                    AutomationSettingsDialog(controller: controller));
          },
          icon: const Icon(Icons.schedule),
          label: const Text('Задачи по расписанию'),
        ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть')),
      ],
    );
  }
}

class AutomationSettingsDialog extends StatefulWidget {
  const AutomationSettingsDialog(
      {super.key, required this.controller, this.projectPath = ''});

  final AgentController controller;
  final String projectPath;

  @override
  State<AutomationSettingsDialog> createState() =>
      _AutomationSettingsDialogState();
}

class _AutomationSettingsDialogState extends State<AutomationSettingsDialog> {
  Future<String?> _editText(String title, String value,
      {int maxLines = 1}) async {
    final controller = TextEditingController(text: value);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 620,
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Сохранить')),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _editApi([ApiOutputTemplate? template]) async {
    final raw = await _editText(
        'API template JSON',
        const JsonEncoder.withIndent('  ').convert(
            (template ?? ApiOutputTemplate.telegramExample()).toJson()),
        maxLines: 12);
    if (raw == null) return;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    await widget.controller
        .upsertApiOutputTemplate(ApiOutputTemplate.fromJson(map));
    if (mounted) setState(() {});
  }

  Future<void> _editTrigger([AgentTriggerConfig? trigger]) async {
    final base = trigger ??
        AgentTriggerConfig(
            id: 'trigger_${DateTime.now().microsecondsSinceEpoch}',
            name: 'Новый триггер',
            type: 'message_contains_text',
            parametersJson: '{"text":""}',
            enabled: true);
    final raw = await _editText('Trigger JSON',
        const JsonEncoder.withIndent('  ').convert(base.toJson()),
        maxLines: 12);
    if (raw == null) return;
    await widget.controller
        .upsertTrigger(AgentTriggerConfig.fromJson(jsonDecode(raw)));
    if (mounted) setState(() {});
  }

  Future<void> _editSchedule([AgentScheduleConfig? schedule]) async {
    final projectPath = widget.projectPath.isNotEmpty
        ? widget.projectPath
        : (widget.controller.currentProject?.path ?? '');
    final base = schedule ??
        AgentScheduleConfig(
          id: 'schedule_${DateTime.now().microsecondsSinceEpoch}',
          projectPath: projectPath,
          name: 'Новое расписание',
          scheduleJson:
              '{"once":{"enabled":false,"date":""},"repeat":{"daily":false,"hourly":false},"triggerIds":[]}',
          prompt: '',
          attachmentPaths: const [],
          extraFolders: const [],
          permissionMode: 'askCriticalOnly',
          profileId: 'auto',
          apiTemplateIds: const [],
          emailAccountId: '',
          formatPrompt: '',
          enabled: true,
        );
    final raw = await _editText('Schedule JSON',
        const JsonEncoder.withIndent('  ').convert(base.toJson()),
        maxLines: 18);
    if (raw == null) return;
    await widget.controller
        .upsertSchedule(AgentScheduleConfig.fromJson(jsonDecode(raw)));
    if (mounted) setState(() {});
  }

  Future<void> _editCustomTool([CustomAgentToolConfig? tool]) async {
    final base = tool ??
        CustomAgentToolConfig(
          id: 'tool_${DateTime.now().microsecondsSinceEpoch}',
          name: 'custom_tool',
          description: 'Пользовательский инструмент',
          scriptPath: '',
          commandTemplate: Platform.isWindows
              ? 'powershell -NoProfile -Command "{{input}}"'
              : 'sh -lc \'{{input}}\'',
          temporary: true,
          enabled: true,
        );
    final raw = await _editText('Custom tool JSON',
        const JsonEncoder.withIndent('  ').convert(base.toJson()),
        maxLines: 14);
    if (raw == null) return;
    await widget.controller
        .upsertCustomTool(CustomAgentToolConfig.fromJson(jsonDecode(raw)));
    if (mounted) setState(() {});
  }

  Future<void> _addIndexLocation() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => EmbeddedFilePickerDialog(
          initialDirectory: Directory.current.path, selectDirectory: true),
    );
    if (picked == null || picked.isEmpty) return;
    await widget.controller.upsertIndexLocation(IndexLocationConfig(
        path: picked, indexNames: true, indexContents: false));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final schedules = widget.projectPath.isEmpty
        ? widget.controller.schedules
        : widget.controller.schedules
            .where((s) =>
                normalizePathForCompare(s.projectPath) ==
                normalizePathForCompare(widget.projectPath))
            .toList();
    return AlertDialog(
      title: const Text('Автоматизация'),
      content: SizedBox(
        width: 860,
        height: math.min(MediaQuery.of(context).size.height * 0.78, 760),
        child: ListView(
          children: [
            _sectionHeader('API вывод', onAdd: () => _editApi()),
            for (final item in widget.controller.apiOutputTemplates)
              ListTile(
                dense: true,
                title: Text(item.name),
                subtitle: Text('${item.method} ${item.endpoint}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                leading: Icon(item.enabled
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await widget.controller.deleteApiOutputTemplate(item.id);
                    if (mounted) setState(() {});
                  },
                ),
                onTap: () => _editApi(item),
              ),
            const Divider(),
            _sectionHeader('Триггеры', onAdd: () => _editTrigger()),
            for (final item in widget.controller.triggers)
              ListTile(
                dense: true,
                title: Text(item.name),
                subtitle: Text('${item.type} ${item.parametersJson}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                leading: Icon(item.enabled
                    ? Icons.bolt_outlined
                    : Icons.power_settings_new_outlined),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await widget.controller.deleteTrigger(item.id);
                    if (mounted) setState(() {});
                  },
                ),
                onTap: () => _editTrigger(item),
              ),
            const Divider(),
            _sectionHeader('Расписание', onAdd: () => _editSchedule()),
            for (final item in schedules)
              ListTile(
                dense: true,
                title: Text(item.name),
                subtitle: Text('${item.projectPath}\n${item.scheduleJson}',
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                leading: Icon(item.enabled
                    ? Icons.event_available_outlined
                    : Icons.event_busy_outlined),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'edit') await _editSchedule(item);
                    if (value == 'duplicate') {
                      await widget.controller
                          .upsertSchedule(AgentScheduleConfig.fromJson({
                        ...item.toJson(),
                        'id':
                            'schedule_${DateTime.now().microsecondsSinceEpoch}',
                        'name': '${item.name} copy'
                      }));
                    }
                    if (value == 'delete') {
                      await widget.controller.deleteSchedule(item.id);
                    }
                    if (mounted) setState(() {});
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Изменить')),
                    PopupMenuItem(
                        value: 'duplicate', child: Text('Дублировать')),
                    PopupMenuItem(value: 'delete', child: Text('Удалить')),
                  ],
                ),
                onTap: () => _editSchedule(item),
              ),
            const Divider(),
            _sectionHeader('Индексация расположений',
                onAdd: () => _addIndexLocation()),
            for (final item in widget.controller.indexLocations)
              CheckboxListTile(
                dense: true,
                value: item.indexContents,
                title: Text(item.path),
                subtitle: Text('Имена: ${item.indexNames ? 'да' : 'нет'}'),
                secondary: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await widget.controller.deleteIndexLocation(item.path);
                    if (mounted) setState(() {});
                  },
                ),
                onChanged: (v) async {
                  await widget.controller.upsertIndexLocation(
                      IndexLocationConfig(
                          path: item.path,
                          indexNames: item.indexNames,
                          indexContents: v ?? false));
                  if (mounted) setState(() {});
                },
              ),
            OutlinedButton.icon(
              onPressed: () async {
                final result = await widget.controller.rebuildDeviceIndex();
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(result)));
                }
              },
              icon: const Icon(Icons.manage_search),
              label: const Text('Переиндексировать'),
            ),
            const Divider(),
            _sectionHeader('Пользовательские инструменты',
                onAdd: () => _editCustomTool()),
            for (final item in widget.controller.customTools)
              ListTile(
                dense: true,
                title: Text(item.name),
                subtitle: Text(item.description,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                leading: Icon(item.temporary
                    ? Icons.construction_outlined
                    : Icons.handyman_outlined),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await widget.controller.deleteCustomTool(item.id);
                    if (mounted) setState(() {});
                  },
                ),
                onTap: () => _editCustomTool(item),
              ),
            const Divider(),
            _sectionHeader('Выполненные задачи'),
            for (final run in widget.controller.scheduledTaskRuns)
              ListTile(
                dense: true,
                title: Text('${run.projectName} • ${run.scheduleName}'),
                subtitle: Text(
                    '${run.createdAt} • ${run.triggerName} • ok=${run.successfulCommands}, errors=${run.errors}'),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Диалог выполнения'),
                    content: SizedBox(
                        width: 720,
                        height: 520,
                        child: SingleChildScrollView(
                            child: SelectableText(run.dialogText))),
                    actions: [
                      TextButton(
                          onPressed: () async => Clipboard.setData(
                              ClipboardData(text: run.dialogText)),
                          child: const Text('Копировать')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Закрыть')),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть')),
      ],
    );
  }

  Widget _sectionHeader(String title, {VoidCallback? onAdd}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Expanded(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.bold))),
          if (onAdd != null)
            IconButton(
                tooltip: 'Добавить',
                onPressed: onAdd,
                icon: const Icon(Icons.add)),
        ],
      ),
    );
  }
}

class ProgramSettingsDialog extends StatefulWidget {
  const ProgramSettingsDialog(
      {super.key, required this.controller, required this.onChanged});

  final AgentController controller;
  final VoidCallback onChanged;

  @override
  State<ProgramSettingsDialog> createState() => _ProgramSettingsDialogState();
}

class _ProgramSettingsDialogState extends State<ProgramSettingsDialog> {
  late TextEditingController iterationsController;
  late TextEditingController projectsPathController;

  @override
  void initState() {
    super.initState();
    iterationsController = TextEditingController(
        text: widget.controller.maxAgentIterations.toString());
    projectsPathController =
        TextEditingController(text: widget.controller.projectsRoot.path);
  }

  @override
  void dispose() {
    iterationsController.dispose();
    projectsPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Настройки AI Agent'),
      content: SizedBox(
        width: math.min(MediaQuery.of(context).size.width * 0.92, 760),
        height: math.min(MediaQuery.of(context).size.height * 0.78, 760),
        child: ListView(
          children: [
            const Text('Общие настройки',
                style: TextStyle(fontWeight: FontWeight.bold)),
            SwitchListTile(
              value: widget.controller.loggingEnabled,
              title: const Text('Включить логирование'),
              subtitle: const Text(
                  'По умолчанию включено. В лог пишутся проверки, запросы, ответы, действия и изменения файлов.'),
              onChanged: (v) =>
                  setState(() => widget.controller.loggingEnabled = v),
            ),
            SwitchListTile(
              value: widget.controller.qualityCheckEnabled,
              title: const Text('Проверка качества выполнения запроса'),
              onChanged: (v) =>
                  setState(() => widget.controller.qualityCheckEnabled = v),
            ),
            const SizedBox(height: 8),
            Text(
                'Масштаб интерфейса: ${(widget.controller.uiScale * 100).round()}%'),
            Slider(
              min: 0.60,
              max: 1.35,
              divisions: 15,
              value: widget.controller.uiScale.clamp(0.60, 1.35).toDouble(),
              label: '${(widget.controller.uiScale * 100).round()}%',
              onChanged: (v) async {
                setState(() => widget.controller.uiScale = v);
                await widget.controller.saveAppSettings();
                widget.controller.notifyAppUi();
              },
            ),
            const Divider(),
            const Text('Права по умолчанию для новых проектов',
                style: TextStyle(fontWeight: FontWeight.bold)),
            DropdownButtonFormField<String>(
              initialValue: widget.controller.defaultPermissionMode.name,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Разрешения действий',
                  border: OutlineInputBorder(),
                  isDense: true),
              items: PermissionMode.values
                  .map((m) => DropdownMenuItem(
                      value: m.name,
                      child: Text(m == PermissionMode.askEveryAction
                          ? 'Запрашивать каждое действие'
                          : m.label)))
                  .toList(),
              onChanged: (v) async {
                if (v == null) return;
                setState(() => widget.controller.defaultPermissionMode =
                    PermissionMode.values.firstWhere((m) => m.name == v));
                await widget.controller.saveAppSettings();
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: widget.controller.defaultCreationMode.name,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Режим создания проекта',
                  border: OutlineInputBorder(),
                  isDense: true),
              items: CreationMode.values
                  .map((m) =>
                      DropdownMenuItem(value: m.name, child: Text(m.label)))
                  .toList(),
              onChanged: (v) async {
                if (v == null) return;
                setState(() => widget.controller.defaultCreationMode =
                    CreationMode.values.firstWhere((m) => m.name == v));
                await widget.controller.saveAppSettings();
              },
            ),
            SwitchListTile(
              value: widget.controller.defaultAllowInternetUse,
              title:
                  const Text('Интернет-инструменты агента для новых проектов'),
              subtitle: const Text(
                  'По умолчанию включено. Отключается отдельно в правах проекта.'),
              onChanged: (v) async {
                setState(() => widget.controller.defaultAllowInternetUse = v);
                await widget.controller.saveAppSettings();
                widget.onChanged();
              },
            ),
            SwitchListTile(
              value: widget.controller.defaultAllowComputerSearch,
              title: const Text(
                  'Поиск по файловой системе устройства для новых проектов'),
              subtitle: const Text('По умолчанию выключено.'),
              onChanged: (v) async {
                setState(
                    () => widget.controller.defaultAllowComputerSearch = v);
                await widget.controller.saveAppSettings();
                widget.onChanged();
              },
            ),
            SwitchListTile(
              value: widget.controller.defaultAllowDeviceFileAccess,
              title:
                  const Text('Доступ к файлам устройства для новых проектов'),
              subtitle: const Text('По умолчанию выключено.'),
              onChanged: (v) async {
                setState(
                    () => widget.controller.defaultAllowDeviceFileAccess = v);
                await widget.controller.saveAppSettings();
                widget.onChanged();
              },
            ),
            SwitchListTile(
              value: widget.controller.defaultAllowFollowUpSuggestions,
              title: const Text(
                  'Предложения дальнейших действий для новых проектов'),
              subtitle: const Text(
                  'Если включено, агент добавляет краткие варианты дальнейших действий после ответа.'),
              onChanged: (v) async {
                setState(() =>
                    widget.controller.defaultAllowFollowUpSuggestions = v);
                await widget.controller.saveAppSettings();
                widget.onChanged();
              },
            ),
            SwitchListTile(
              value: widget.controller.llamaProcessLoggingEnabled,
              title: const Text('Логировать вывод llama.cpp'),
              subtitle: const Text(
                  'STDOUT/STDERR локального llama-server пишется в отдельный файл рядом с общими логами.'),
              onChanged: (v) async {
                setState(
                    () => widget.controller.llamaProcessLoggingEnabled = v);
                await widget.controller.saveAppSettings();
                widget.onChanged();
              },
            ),
            SwitchListTile(
              value: widget.controller.isolatedToolsEnabled,
              title: const Text('Изолировать tools и установки'),
              subtitle: const Text(
                  'По умолчанию новые инструменты, архивы и переносимые установки остаются внутри папки программы.'),
              onChanged: (v) async {
                setState(() => widget.controller.isolatedToolsEnabled = v);
                await widget.controller.saveAppSettings();
                widget.onChanged();
              },
            ),
            SwitchListTile(
              value: widget.controller.closeToTrayOnClose,
              title: const Text('Windows: сворачивать в трей при закрытии'),
              subtitle: const Text(
                  'Можно отключить, тогда кнопка закрытия завершает окно как обычно. Нативный трей включается через Windows bridge, если доступен.'),
              onChanged: (v) async {
                setState(() => widget.controller.closeToTrayOnClose = v);
                await widget.controller.saveAppSettings();
                await widget.controller.configureWindowsTrayBridge();
                widget.onChanged();
              },
            ),
            SwitchListTile(
              value: widget.controller.trayNotificationsEnabled,
              title: const Text('Windows: уведомления о ходе выполнения'),
              subtitle: const Text(
                  'При завершении/ошибке задачи программа пытается показать системное уведомление.'),
              onChanged: (v) async {
                setState(() => widget.controller.trayNotificationsEnabled = v);
                await widget.controller.saveAppSettings();
                await widget.controller.configureWindowsTrayBridge();
                widget.onChanged();
              },
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await showDialog<void>(
                    context: context,
                    builder: (_) => EmailAccountsDialog(
                        controller: widget.controller,
                        onChanged: widget.onChanged));
                setState(() {});
              },
              icon: const Icon(Icons.mail_outline),
              label: Text(
                  'Почта: ${widget.controller.emailAccounts.length} аккаунт(ов)'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                setState(() => widget.controller.permissionStatusText =
                    widget.controller.checkRuntimePermissionsStatus());
              },
              icon: const Icon(Icons.privacy_tip),
              label: const Text('Проверить доступность прав'),
            ),
            if (widget.controller.permissionStatusText.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child:
                      SelectableText(widget.controller.permissionStatusText)),
            const Divider(),
            OutlinedButton.icon(
              onPressed: () async {
                await showDialog<void>(
                    context: context,
                    builder: (_) =>
                        KnowledgeBaseDialog(controller: widget.controller));
              },
              icon: const Icon(Icons.library_books),
              label: const Text('База знаний агента'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await showDialog<void>(
                    context: context,
                    builder: (_) => AutomationSettingsDialog(
                        controller: widget.controller));
                setState(() {});
              },
              icon: const Icon(Icons.auto_mode),
              label: const Text('Автоматизация, API, индексация, tools'),
            ),
            TextField(
              controller: iterationsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Максимум действий агента',
                  border: OutlineInputBorder()),
              onChanged: (v) => widget.controller.maxAgentIterations =
                  int.tryParse(v) ?? widget.controller.maxAgentIterations,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: widget.controller.appLanguage,
              decoration: const InputDecoration(
                  labelText: 'Язык программы', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'ru', child: Text('Русский')),
                DropdownMenuItem(value: 'en', child: Text('English')),
              ],
              onChanged: (value) async {
                if (value == null) return;
                setState(() => widget.controller.appLanguage = value);
                await widget.controller.saveAppSettings();
                widget.onChanged();
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 430,
                  child: TextField(
                    controller: projectsPathController,
                    decoration: const InputDecoration(
                        labelText: 'Папка Projects',
                        border: OutlineInputBorder(),
                        isDense: true),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDialog<String>(
                      context: context,
                      builder: (_) => EmbeddedFilePickerDialog(
                          initialDirectory: widget.controller.projectsRoot.path,
                          selectDirectory: true),
                    );
                    if (picked != null)
                      setState(() => projectsPathController.text = picked);
                  },
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Выбрать'),
                ),
                FilledButton(
                  onPressed: () async {
                    await widget.controller.setProjectsRootPath(
                        projectsPathController.text.trim());
                    widget.onChanged();
                    setState(() {});
                  },
                  child: const Text('Применить'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                await showDialog<void>(
                  context: context,
                  builder: (_) => ModelProfilesDialog(
                      controller: widget.controller,
                      onChanged: widget.onChanged),
                );
                setState(() {});
              },
              icon: const Icon(Icons.smart_toy),
              label: const Text('Модели'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () async {
                await showDialog<void>(
                  context: context,
                  builder: (_) => ProgramFilesDialog(
                      controller: widget.controller,
                      initialDirectory: Directory.current.path),
                );
              },
              icon: const Icon(Icons.folder_open),
              label: const Text('Настройки файлов программы'),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () {
            widget.controller.log(
                'SETTINGS UPDATE: logging=${widget.controller.loggingEnabled}; quality=${widget.controller.qualityCheckEnabled}; maxIterations=${widget.controller.maxAgentIterations}');
            widget.onChanged();
            Navigator.pop(context);
          },
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}

class EmailAccountsDialog extends StatefulWidget {
  const EmailAccountsDialog(
      {super.key, required this.controller, required this.onChanged});
  final AgentController controller;
  final VoidCallback onChanged;

  @override
  State<EmailAccountsDialog> createState() => _EmailAccountsDialogState();
}

class _EmailAccountsDialogState extends State<EmailAccountsDialog> {
  final addressController = TextEditingController();
  final displayNameController = TextEditingController();
  final imapHostController = TextEditingController();
  final imapPortController = TextEditingController(text: '993');
  final smtpHostController = TextEditingController();
  final smtpPortController = TextEditingController(text: '465');
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  bool useSsl = true;
  String editingId = '';

  @override
  void dispose() {
    addressController.dispose();
    displayNameController.dispose();
    imapHostController.dispose();
    imapPortController.dispose();
    smtpHostController.dispose();
    smtpPortController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void load(EmailAccountConfig account) {
    editingId = account.id;
    addressController.text = account.address;
    displayNameController.text = account.displayName;
    imapHostController.text = account.imapHost;
    imapPortController.text = account.imapPort.toString();
    smtpHostController.text = account.smtpHost;
    smtpPortController.text = account.smtpPort.toString();
    usernameController.text = account.username;
    passwordController.text = account.password;
    useSsl = account.useSsl;
  }

  Future<void> save() async {
    final account = EmailAccountConfig(
      id: editingId.isEmpty
          ? 'mail_${DateTime.now().microsecondsSinceEpoch}'
          : editingId,
      address: addressController.text.trim(),
      displayName: displayNameController.text.trim(),
      imapHost: imapHostController.text.trim(),
      imapPort: int.tryParse(imapPortController.text.trim()) ?? 993,
      smtpHost: smtpHostController.text.trim(),
      smtpPort: int.tryParse(smtpPortController.text.trim()) ?? 465,
      username: usernameController.text.trim(),
      password: passwordController.text,
      useSsl: useSsl,
    );
    await widget.controller.saveEmailAccount(account);
    widget.onChanged();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Почтовые аккаунты'),
      content: SizedBox(
        width: 760,
        height: 640,
        child: ListView(
          children: [
            const Text(
                'Аккаунты используются агентом для задач с почтой. Пароль хранится локально в config/app_settings.json, поэтому используйте пароль приложения, если почтовый сервис это поддерживает.'),
            const SizedBox(height: 12),
            for (final account in widget.controller.emailAccounts)
              Card(
                child: ListTile(
                  title: Text(account.address),
                  subtitle: Text(account.safeSummary),
                  onTap: () => setState(() => load(account)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await widget.controller.deleteEmailAccount(account.id);
                      widget.onChanged();
                      if (mounted) setState(() {});
                    },
                  ),
                ),
              ),
            const Divider(height: 28),
            TextField(
                controller: addressController,
                decoration: const InputDecoration(
                    labelText: 'Почтовый адрес',
                    border: OutlineInputBorder(),
                    isDense: true)),
            const SizedBox(height: 8),
            TextField(
                controller: displayNameController,
                decoration: const InputDecoration(
                    labelText: 'Отображаемое имя',
                    border: OutlineInputBorder(),
                    isDense: true)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: imapHostController,
                      decoration: const InputDecoration(
                          labelText: 'IMAP host',
                          border: OutlineInputBorder(),
                          isDense: true))),
              const SizedBox(width: 8),
              SizedBox(
                  width: 110,
                  child: TextField(
                      controller: imapPortController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'IMAP port',
                          border: OutlineInputBorder(),
                          isDense: true))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: smtpHostController,
                      decoration: const InputDecoration(
                          labelText: 'SMTP host',
                          border: OutlineInputBorder(),
                          isDense: true))),
              const SizedBox(width: 8),
              SizedBox(
                  width: 110,
                  child: TextField(
                      controller: smtpPortController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'SMTP port',
                          border: OutlineInputBorder(),
                          isDense: true))),
            ]),
            const SizedBox(height: 8),
            TextField(
                controller: usernameController,
                decoration: const InputDecoration(
                    labelText: 'Логин',
                    border: OutlineInputBorder(),
                    isDense: true)),
            const SizedBox(height: 8),
            TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Пароль / пароль приложения',
                    border: OutlineInputBorder(),
                    isDense: true)),
            SwitchListTile(
                value: useSsl,
                title: const Text('SSL/TLS'),
                onChanged: (v) => setState(() => useSsl = v)),
            FilledButton.icon(
                onPressed: save,
                icon: const Icon(Icons.save),
                label: const Text('Сохранить аккаунт')),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'))
      ],
    );
  }
}

class EmbeddedFilePickerDialog extends StatefulWidget {
  const EmbeddedFilePickerDialog(
      {super.key,
      required this.initialDirectory,
      this.selectDirectory = false});
  final String initialDirectory;
  final bool selectDirectory;

  @override
  State<EmbeddedFilePickerDialog> createState() =>
      _EmbeddedFilePickerDialogState();
}

class _EmbeddedFilePickerDialogState extends State<EmbeddedFilePickerDialog> {
  late Directory current;
  String? selectedPath;

  @override
  void initState() {
    super.initState();
    current = Directory(widget.initialDirectory);
  }

  List<String> get roots {
    if (Platform.isWindows) {
      return List.generate(26, (i) => '${String.fromCharCode(65 + i)}:\\')
          .where((p) => Directory(p).existsSync())
          .toList();
    }
    return ['/', Directory.current.path];
  }

  @override
  Widget build(BuildContext context) {
    final entries = current.existsSync()
        ? (current.listSync()
          ..sort((a, b) => pathBasename(a.path)
              .toLowerCase()
              .compareTo(pathBasename(b.path).toLowerCase())))
        : <FileSystemEntity>[];
    return AlertDialog(
      title: Text(widget.selectDirectory
          ? 'Выбор папки внутри программы'
          : 'Выбор файла внутри программы'),
      content: SizedBox(
        width: 760,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              children: roots
                  .map((r) => OutlinedButton(
                      onPressed: () => setState(() => current = Directory(r)),
                      child: Text(r)))
                  .toList(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                    onPressed: current.parent.path == current.path
                        ? null
                        : () => setState(() => current = current.parent),
                    icon: const Icon(Icons.arrow_upward)),
                Expanded(child: SelectableText(current.path)),
              ],
            ),
            Expanded(
              child: ListView.builder(
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final e = entries[index];
                  final isDir = e is Directory;
                  return ListTile(
                    dense: true,
                    leading:
                        Icon(isDir ? Icons.folder : Icons.insert_drive_file),
                    title: Text(pathBasename(e.path),
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(e.path,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    selected: selectedPath == e.path,
                    onTap: () {
                      if (isDir) {
                        if (widget.selectDirectory)
                          setState(() => selectedPath = e.path);
                        setState(() => current = Directory(e.path));
                      } else if (!widget.selectDirectory) {
                        setState(() => selectedPath = e.path);
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена')),
        if (widget.selectDirectory)
          OutlinedButton(
              onPressed: () => Navigator.pop(context, current.path),
              child: const Text('Выбрать текущую папку')),
        FilledButton(
            onPressed: selectedPath == null
                ? null
                : () => Navigator.pop(context, selectedPath),
            child: Text(widget.selectDirectory ? 'Выбрать' : 'Добавить')),
      ],
    );
  }
}

class ProgramFilesDialog extends StatefulWidget {
  const ProgramFilesDialog(
      {super.key, required this.controller, required this.initialDirectory});
  final AgentController controller;
  final String initialDirectory;

  @override
  State<ProgramFilesDialog> createState() => _ProgramFilesDialogState();
}

class _ProgramFilesDialogState extends State<ProgramFilesDialog> {
  late Directory current;
  String? clipboardPath;
  bool cut = false;

  @override
  void initState() {
    super.initState();
    current = Directory(widget.initialDirectory);
  }

  @override
  Widget build(BuildContext context) {
    final entries = current.existsSync()
        ? (current.listSync()
          ..sort((a, b) => pathBasename(a.path)
              .toLowerCase()
              .compareTo(pathBasename(b.path).toLowerCase())))
        : <FileSystemEntity>[];
    return AlertDialog(
      title: const Text('Файлы программы'),
      content: SizedBox(
        width: 840,
        height: 620,
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                    onPressed: current.parent.path == current.path
                        ? null
                        : () => setState(() => current = current.parent),
                    icon: const Icon(Icons.arrow_upward)),
                Expanded(child: SelectableText(current.path)),
                OutlinedButton.icon(
                  onPressed: () async {
                    final path = await showDialog<String>(
                        context: context,
                        builder: (_) => EmbeddedFilePickerDialog(
                            initialDirectory: Directory.current.path));
                    if (path != null) {
                      await widget.controller.copyFileSystemEntry(
                          path, pathJoin(current.path, pathBasename(path)),
                          move: false);
                      widget.controller
                          .log('PROGRAM FILE LOAD: $path -> ${current.path}');
                      setState(() {});
                    }
                  },
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Загрузить файлы'),
                ),
              ],
            ),
            Expanded(
              child: ListView.builder(
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final e = entries[index];
                  final isDir = e is Directory;
                  return ListTile(
                    dense: true,
                    leading: Icon(isDir ? Icons.folder : Icons.description),
                    title: Text(pathBasename(e.path),
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(e.path,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      if (isDir) setState(() => current = Directory(e.path));
                    },
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'copy') {
                          clipboardPath = e.path;
                          cut = false;
                        }
                        if (value == 'cut') {
                          clipboardPath = e.path;
                          cut = true;
                        }
                        if (value == 'delete') await e.delete(recursive: true);
                        if (value == 'paste' && clipboardPath != null) {
                          await widget.controller.copyFileSystemEntry(
                              clipboardPath!,
                              pathJoin(
                                  current.path, pathBasename(clipboardPath!)),
                              move: cut);
                          clipboardPath = null;
                        }
                        setState(() {});
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'copy', child: Text('Копировать')),
                        const PopupMenuItem(
                            value: 'cut', child: Text('Вырезать')),
                        const PopupMenuItem(
                            value: 'delete', child: Text('Удалить')),
                        if (clipboardPath != null)
                          const PopupMenuItem(
                              value: 'paste', child: Text('Вставить сюда')),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'))
      ],
    );
  }
}
