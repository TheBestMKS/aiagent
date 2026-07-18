import 'dart:convert';

enum AgentPluginKind { reference, command, integration }

enum AgentPluginPermission { network, process, projectFiles, deviceFiles, secrets }

class AgentPlugin {
  const AgentPlugin({
    required this.id,
    required this.name,
    required this.description,
    required this.repository,
    required this.defaultBranch,
    required this.kind,
    required this.toolName,
    required this.toolDescription,
    required this.commandTemplate,
    required this.permissions,
    required this.bundledSummary,
    required this.enabled,
    required this.sourceInstalled,
    required this.installedCommit,
    required this.latestCommit,
    required this.lastCheckedAt,
    required this.lastError,
    required this.sensitive,
  });

  final String id;
  final String name;
  final String description;
  final String repository;
  final String defaultBranch;
  final AgentPluginKind kind;
  final String toolName;
  final String toolDescription;
  final String commandTemplate;
  final List<AgentPluginPermission> permissions;
  final String bundledSummary;
  final bool enabled;
  final bool sourceInstalled;
  final String installedCommit;
  final String latestCommit;
  final DateTime? lastCheckedAt;
  final String lastError;
  final bool sensitive;

  bool get requiresNetwork => permissions.contains(AgentPluginPermission.network);
  bool get requiresProcess => permissions.contains(AgentPluginPermission.process);
  bool get updateAvailable => sourceInstalled &&
      latestCommit.isNotEmpty &&
      installedCommit.isNotEmpty &&
      latestCommit != installedCommit;

  String get repositoryUrl => 'https://github.com/$repository';

  AgentPlugin copyWith({
    bool? enabled,
    bool? sourceInstalled,
    String? installedCommit,
    String? latestCommit,
    DateTime? lastCheckedAt,
    String? lastError,
  }) =>
      AgentPlugin(
        id: id,
        name: name,
        description: description,
        repository: repository,
        defaultBranch: defaultBranch,
        kind: kind,
        toolName: toolName,
        toolDescription: toolDescription,
        commandTemplate: commandTemplate,
        permissions: permissions,
        bundledSummary: bundledSummary,
        enabled: enabled ?? this.enabled,
        sourceInstalled: sourceInstalled ?? this.sourceInstalled,
        installedCommit: installedCommit ?? this.installedCommit,
        latestCommit: latestCommit ?? this.latestCommit,
        lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
        lastError: lastError ?? this.lastError,
        sensitive: sensitive,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'enabled': enabled,
        'sourceInstalled': sourceInstalled,
        'installedCommit': installedCommit,
        'latestCommit': latestCommit,
        'lastCheckedAt': lastCheckedAt?.toIso8601String(),
        'lastError': lastError,
      };

  AgentPlugin applyState(Map<String, dynamic> state) => copyWith(
        enabled: state['enabled'] is bool ? state['enabled'] as bool : enabled,
        sourceInstalled: state['sourceInstalled'] == true,
        installedCommit: state['installedCommit']?.toString() ?? installedCommit,
        latestCommit: state['latestCommit']?.toString() ?? latestCommit,
        lastCheckedAt: DateTime.tryParse(state['lastCheckedAt']?.toString() ?? ''),
        lastError: state['lastError']?.toString() ?? '',
      );
}

class PluginUpdateInfo {
  const PluginUpdateInfo({
    required this.pluginId,
    required this.name,
    required this.installedCommit,
    required this.latestCommit,
  });

  final String pluginId;
  final String name;
  final String installedCommit;
  final String latestCommit;

  String get installedShort => _shortSha(installedCommit);
  String get latestShort => _shortSha(latestCommit);

  static String _shortSha(String value) =>
      value.length <= 8 ? value : value.substring(0, 8);
}

class PluginOperationStatus {
  const PluginOperationStatus({
    required this.active,
    required this.message,
    this.progress,
    this.pluginId = '',
    this.error = false,
  });

  const PluginOperationStatus.idle()
      : active = false,
        message = 'Плагины готовы',
        progress = null,
        pluginId = '',
        error = false;

  final bool active;
  final String message;
  final double? progress;
  final String pluginId;
  final bool error;
}

String prettyPluginJson(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);
