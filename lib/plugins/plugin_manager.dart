import 'dart:convert';
import 'dart:io';

import '../utils/path_utils.dart';
import 'plugin_catalog.dart';
import 'plugin_github_updater.dart';
import 'plugin_models.dart';
import 'plugin_reference_index.dart';

class PluginManager {
  PluginManager({
    required this.pluginsRoot,
    required this.networkAllowed,
    required this.onStatus,
    required this.onChanged,
  })  : _updater = PluginGithubUpdater(
          pluginsRoot: pluginsRoot,
          onStatus: onStatus,
        ),
        _referenceIndex = PluginReferenceIndex(
          sourceDirectory: (pluginId) => Directory(
            pathJoin(pluginsRoot.path, pluginId, 'source'),
          ),
        );

  final Directory pluginsRoot;
  final bool Function() networkAllowed;
  final void Function(PluginOperationStatus status) onStatus;
  final void Function() onChanged;
  final PluginGithubUpdater _updater;
  final PluginReferenceIndex _referenceIndex;

  List<AgentPlugin> plugins = const [];

  File get _stateFile => File(pathJoin(pluginsRoot.path, 'plugin_state.json'));

  Future<void> initialize() async {
    await pluginsRoot.create(recursive: true);
    await _updater.initialize();
    final states = await _readStates();
    plugins = bundledPluginCatalog
        .map((plugin) => states[plugin.id] == null
            ? plugin
            : plugin.applyState(states[plugin.id]!))
        .toList(growable: false);
    await _repairInstalledFlags();
    await saveState();
    onChanged();
  }

  AgentPlugin? byId(String id) {
    for (final plugin in plugins) {
      if (plugin.id == id) return plugin;
    }
    return null;
  }

  AgentPlugin? byToolName(String toolName) {
    for (final plugin in plugins) {
      if (plugin.toolName == toolName) return plugin;
    }
    return null;
  }

  Directory pluginDirectory(String pluginId) =>
      _updater.pluginDirectory(pluginId);

  Directory pluginSourceDirectory(String pluginId) =>
      _updater.pluginSourceDirectory(pluginId);

  Future<void> setEnabled(String pluginId, bool enabled) async {
    final plugin = byId(pluginId);
    if (plugin == null) return;
    _replace(pluginId, plugin.copyWith(enabled: enabled));
    await saveState();
    onChanged();
  }

  Future<void> saveState() async {
    await pluginsRoot.create(recursive: true);
    final temp = File('${_stateFile.path}.tmp');
    await temp.writeAsString(
      prettyPluginJson({
        'schemaVersion': 1,
        'savedAt': DateTime.now().toIso8601String(),
        'plugins': plugins.map((plugin) => plugin.toJson()).toList(),
      }),
      encoding: utf8,
    );
    if (await _stateFile.exists()) await _stateFile.delete();
    await temp.rename(_stateFile.path);
  }

  Future<List<PluginUpdateInfo>> checkForUpdates({
    bool includeNotInstalled = false,
  }) async {
    if (!networkAllowed()) {
      onStatus(const PluginOperationStatus(
        active: false,
        message: 'Проверка плагинов пропущена: интернет запрещён',
        error: true,
      ));
      return const [];
    }

    final candidates = plugins
        .where((plugin) => includeNotInstalled || plugin.sourceInstalled)
        .toList(growable: false);
    final updates = <PluginUpdateInfo>[];
    var failedChecks = 0;
    for (var i = 0; i < candidates.length; i++) {
      final plugin = candidates[i];
      onStatus(PluginOperationStatus(
        active: true,
        message: 'Проверка ${plugin.name}',
        progress: candidates.isEmpty ? null : i / candidates.length,
        pluginId: plugin.id,
      ));
      try {
        final latest = await _updater.fetchLatestCommit(plugin);
        _replace(
          plugin.id,
          plugin.copyWith(
            latestCommit: latest,
            lastCheckedAt: DateTime.now(),
            lastError: '',
          ),
        );
        if (plugin.sourceInstalled &&
            plugin.installedCommit.isNotEmpty &&
            latest != plugin.installedCommit) {
          updates.add(PluginUpdateInfo(
            pluginId: plugin.id,
            name: plugin.name,
            installedCommit: plugin.installedCommit,
            latestCommit: latest,
          ));
        }
      } catch (error) {
        failedChecks++;
        _replace(
          plugin.id,
          plugin.copyWith(
            lastCheckedAt: DateTime.now(),
            lastError: error.toString(),
          ),
        );
      }
    }
    await saveState();
    onStatus(PluginOperationStatus(
      active: false,
      message: failedChecks > 0
          ? 'Обновлений: ${updates.length}; ошибок проверки: $failedChecks'
          : updates.isEmpty
              ? 'Обновления плагинов не найдены'
              : 'Найдено обновлений: ${updates.length}',
      error: failedChecks > 0,
    ));
    onChanged();
    return updates;
  }

  Future<void> installOrUpdate(String pluginId) async {
    final plugin = byId(pluginId);
    if (plugin == null) throw StateError('Unknown plugin: $pluginId');
    if (!networkAllowed()) throw StateError('Internet access is disabled');

    try {
      var commit = plugin.latestCommit;
      if (commit.isEmpty) commit = await _updater.fetchLatestCommit(plugin);
      onStatus(PluginOperationStatus(
        active: true,
        message: 'Загрузка ${plugin.name}',
        progress: 0,
        pluginId: plugin.id,
      ));
      await _updater.installCommit(plugin, commit);
      _referenceIndex.invalidate(plugin.id);
      final current = byId(plugin.id) ?? plugin;
      _replace(
        plugin.id,
        current.copyWith(
          sourceInstalled: true,
          installedCommit: commit,
          latestCommit: commit,
          lastCheckedAt: DateTime.now(),
          lastError: '',
        ),
      );
      await saveState();
      onStatus(PluginOperationStatus(
        active: false,
        message: '${plugin.name}: обновлено до ${_shortSha(commit)}',
        progress: 1.0,
        pluginId: plugin.id,
      ));
      onChanged();
    } catch (error) {
      final current = byId(plugin.id) ?? plugin;
      _replace(plugin.id, current.copyWith(lastError: error.toString()));
      await saveState();
      onStatus(PluginOperationStatus(
        active: false,
        message: '${plugin.name}: ошибка обновления',
        pluginId: plugin.id,
        error: true,
      ));
      onChanged();
      rethrow;
    }
  }

  Future<void> updateMany(Iterable<String> pluginIds) async {
    final ids = pluginIds.toSet().toList(growable: false);
    final failures = <String>[];
    for (var i = 0; i < ids.length; i++) {
      final plugin = byId(ids[i]);
      if (plugin == null) continue;
      onStatus(PluginOperationStatus(
        active: true,
        message: 'Обновление ${plugin.name} (${i + 1}/${ids.length})',
        progress: ids.isEmpty ? null : i / ids.length,
        pluginId: plugin.id,
      ));
      try {
        await installOrUpdate(plugin.id);
      } catch (error) {
        failures.add('${plugin.name}: $error');
      }
    }
    if (failures.isNotEmpty) {
      onStatus(PluginOperationStatus(
        active: false,
        message: 'Не удалось обновить плагинов: ${failures.length}',
        error: true,
      ));
      throw StateError(failures.join(' | '));
    }
    onStatus(PluginOperationStatus(
      active: false,
      message: ids.isEmpty
          ? 'Плагины для обновления не выбраны'
          : 'Обновление плагинов завершено: ${ids.length}',
      progress: ids.isEmpty ? null : 1.0,
    ));
  }

  Future<String> searchDocumentation(
    String pluginId,
    String query, {
    int maxResults = 8,
  }) async {
    final plugin = byId(pluginId);
    if (plugin == null) return 'PLUGIN_NOT_FOUND: $pluginId';
    return _referenceIndex.search(
      plugin,
      query,
      maxResults: maxResults,
    );
  }

  String catalogSummaryForPrompt() {
    final enabled = plugins.where((plugin) => plugin.enabled).toList();
    if (enabled.isEmpty) return '(enabled plugins: none)';
    return enabled.map((plugin) {
      final status = plugin.sourceInstalled ? 'source synced' : 'adapter only';
      final permissions =
          plugin.permissions.map((permission) => permission.name).join(',');
      return '- ${plugin.toolName}: ${plugin.toolDescription} '
          '[$status; permissions=$permissions]';
    }).join('\n');
  }

  Future<Map<String, Map<String, dynamic>>> _readStates() async {
    final states = <String, Map<String, dynamic>>{};
    if (!await _stateFile.exists()) return states;
    try {
      final decoded = jsonDecode(await _stateFile.readAsString(encoding: utf8));
      if (decoded is Map && decoded['plugins'] is List) {
        for (final item in decoded['plugins'] as List) {
          if (item is! Map) continue;
          final state =
              item.map((key, value) => MapEntry(key.toString(), value));
          final id = state['id']?.toString() ?? '';
          if (id.isNotEmpty) states[id] = state;
        }
      }
    } catch (_) {
      // A damaged state file must not prevent the application from starting.
    }
    return states;
  }

  Future<void> _repairInstalledFlags() async {
    final repaired = <AgentPlugin>[];
    for (final plugin in plugins) {
      final sourceExists = await pluginSourceDirectory(plugin.id).exists();
      repaired.add(plugin.copyWith(
        sourceInstalled: sourceExists && plugin.installedCommit.isNotEmpty,
      ));
    }
    plugins = repaired.toList(growable: false);
  }

  void _replace(String id, AgentPlugin value) {
    final mutable = plugins.toList(growable: true);
    final index = mutable.indexWhere((plugin) => plugin.id == id);
    if (index >= 0) mutable[index] = value;
    plugins = mutable.toList(growable: false);
  }

  String _shortSha(String value) =>
      value.length <= 8 ? value : value.substring(0, 8);
}
