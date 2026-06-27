class AgentProcessResult {
  const AgentProcessResult(
      {required this.didAction,
      required this.toolCallCount,
      required this.fileWriteCount});
  final bool didAction;
  final int toolCallCount;
  final int fileWriteCount;
}

class ProjectInfo {
  const ProjectInfo({required this.name, required this.path});
  final String name;
  final String path;
}

class PreparedCommand {
  const PreparedCommand({required this.command, required this.note});
  final String command;
  final String note;
}

class LocalToolInfo {
  const LocalToolInfo(
      {required this.name,
      required this.path,
      required this.relativePath,
      required this.kind});
  final String name;
  final String path;
  final String relativePath;
  final String kind;
}

class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    String? id,
    this.internal = false,
    this.transient = false,
    this.fileChanges = const [],
    this.actionSummaries = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? 'msg_${DateTime.now().microsecondsSinceEpoch}_${_nextId++}',
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  static int _nextId = 1;
  final String id;
  final String role;
  final String content;
  final bool internal;
  final bool transient;
  final List<FileChangeSummary> fileChanges;
  final List<AgentActionSummary> actionSummaries;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatMessage copyWith(
          {String? content,
          bool? internal,
          bool? transient,
          List<FileChangeSummary>? fileChanges,
          List<AgentActionSummary>? actionSummaries,
          DateTime? updatedAt,
          bool touch = true}) =>
      ChatMessage(
        role: role,
        content: content ?? this.content,
        id: id,
        internal: internal ?? this.internal,
        transient: transient ?? this.transient,
        fileChanges: fileChanges ?? this.fileChanges,
        actionSummaries: actionSummaries ?? this.actionSummaries,
        createdAt: createdAt,
        updatedAt: updatedAt ?? (touch ? DateTime.now() : this.updatedAt),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'content': content,
        'internal': internal,
        'transient': false,
        'fileChanges': fileChanges.map((f) => f.toJson()).toList(),
        'actionSummaries': actionSummaries.map((a) => a.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id']?.toString(),
        role: json['role']?.toString() ?? 'assistant',
        content: json['content']?.toString() ?? '',
        internal: json['internal'] == true,
        transient: false,
        fileChanges: (json['fileChanges'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .map((m) => FileChangeSummary.fromJson(
                m.map((key, value) => MapEntry(key.toString(), value))))
            .toList(),
        actionSummaries: (json['actionSummaries'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .map((m) => AgentActionSummary.fromJson(
                m.map((key, value) => MapEntry(key.toString(), value))))
            .toList(),
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
            DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class AgentActionSummary {
  AgentActionSummary(
      {required this.key,
      required this.title,
      required this.firstSeen,
      required this.attempts});

  final String key;
  final String title;
  final int firstSeen;
  final List<AgentActionAttempt> attempts;

  bool get allSucceeded =>
      attempts.isNotEmpty && attempts.every((a) => a.success);

  String get latestPreview {
    if (attempts.isEmpty) return '';
    final text = attempts.last.result.trim();
    if (text.isEmpty) return '';
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !line.startsWith('Tool result for '))
        .take(4)
        .join('  ');
    if (lines.length <= 260) return lines;
    return '${lines.substring(0, 260)}...';
  }

  String get expandedText {
    final buffer = StringBuffer();
    for (var i = 0; i < attempts.length; i++) {
      final attempt = attempts[i];
      buffer.writeln(
          "**Попытка ${i + 1}: ${attempt.success ? 'успешно' : 'ошибка'}**");
      buffer.writeln('Время: ${attempt.timestamp}');
      buffer.writeln();
      buffer.writeln(attempt.result.trimRight());
      if (i != attempts.length - 1) buffer.writeln('\n---\n');
    }
    return buffer.toString().trimRight();
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'title': title,
        'firstSeen': firstSeen,
        'attempts': attempts.map((a) => a.toJson()).toList(),
      };

  factory AgentActionSummary.fromJson(Map<String, dynamic> json) =>
      AgentActionSummary(
        key: json['key']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        firstSeen: json['firstSeen'] is int
            ? json['firstSeen'] as int
            : int.tryParse(json['firstSeen']?.toString() ?? '') ?? 0,
        attempts: (json['attempts'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .map((m) => AgentActionAttempt.fromJson(
                m.map((key, value) => MapEntry(key.toString(), value))))
            .toList(),
      );
}

class AgentActionAttempt {
  AgentActionAttempt(
      {required this.timestamp, required this.result, required this.success});

  final String timestamp;
  final String result;
  final bool success;

  Map<String, dynamic> toJson() =>
      {'timestamp': timestamp, 'result': result, 'success': success};

  factory AgentActionAttempt.fromJson(Map<String, dynamic> json) =>
      AgentActionAttempt(
        timestamp: json['timestamp']?.toString() ?? '',
        result: json['result']?.toString() ?? '',
        success: json['success'] == true,
      );
}

class FileChangeSummary {
  FileChangeSummary(
      {required this.path,
      required this.addedLines,
      required this.removedLines,
      required this.diff});

  final String path;
  final int addedLines;
  final int removedLines;
  final String diff;

  Map<String, dynamic> toJson() => {
        'path': path,
        'addedLines': addedLines,
        'removedLines': removedLines,
        'diff': diff
      };

  factory FileChangeSummary.fromJson(Map<String, dynamic> json) =>
      FileChangeSummary(
        path: json['path']?.toString() ?? '',
        addedLines: json['addedLines'] is int
            ? json['addedLines'] as int
            : int.tryParse(json['addedLines']?.toString() ?? '') ?? 0,
        removedLines: json['removedLines'] is int
            ? json['removedLines'] as int
            : int.tryParse(json['removedLines']?.toString() ?? '') ?? 0,
        diff: json['diff']?.toString() ?? '',
      );
}

enum ProfileKind { openAiCompatible, localLlama }

extension ProfileKindLabel on ProfileKind {
  String get label => switch (this) {
        ProfileKind.openAiCompatible => 'OpenAI API',
        ProfileKind.localLlama => 'llama.cpp'
      };
}

class ModelProfile {
  const ModelProfile({
    required this.id,
    required this.name,
    required this.kind,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    required this.maxContextTokens,
    required this.maxOutputTokens,
    required this.streamResponses,
    required this.modelPath,
    required this.mmprojPath,
    required this.llamaMode,
    required this.llamaDir,
    required this.llamaPort,
    required this.llamaSettings,
  });

  factory ModelProfile.openAiCompatible(
          {required String name,
          required String baseUrl,
          required String model,
          required String apiKey,
          int maxContextTokens = 131072,
          int maxOutputTokens = 16384,
          bool streamResponses = true}) =>
      ModelProfile(
        id: 'openai_${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        kind: ProfileKind.openAiCompatible,
        baseUrl: baseUrl,
        model: model,
        apiKey: apiKey,
        maxContextTokens: maxContextTokens,
        maxOutputTokens: maxOutputTokens,
        streamResponses: streamResponses,
        modelPath: '',
        mmprojPath: '',
        llamaMode: '',
        llamaDir: '',
        llamaPort: 1234,
        llamaSettings: const LlamaSettings(),
      );

  factory ModelProfile.localLlama(
          {required String name,
          required String baseUrl,
          required String model,
          required String modelPath,
          String mmprojPath = '',
          required String llamaMode,
          required String llamaDir,
          required int llamaPort,
          required LlamaSettings llamaSettings,
          int maxOutputTokens = 16384,
          bool streamResponses = true}) =>
      ModelProfile(
        id: 'llama_${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        kind: ProfileKind.localLlama,
        baseUrl: baseUrl,
        model: model,
        apiKey: '',
        maxContextTokens: llamaSettings.contextLength,
        maxOutputTokens: maxOutputTokens,
        streamResponses: streamResponses,
        modelPath: modelPath,
        mmprojPath: mmprojPath,
        llamaMode: llamaMode,
        llamaDir: llamaDir,
        llamaPort: llamaPort,
        llamaSettings: llamaSettings,
      );

  factory ModelProfile.fromJson(Map<String, dynamic> json) => ModelProfile(
        id: json['id']?.toString() ??
            'profile_${DateTime.now().microsecondsSinceEpoch}',
        name: json['name']?.toString() ?? 'Profile',
        kind: json['kind'] == 'localLlama'
            ? ProfileKind.localLlama
            : ProfileKind.openAiCompatible,
        baseUrl: json['baseUrl']?.toString() ?? '',
        model: json['model']?.toString() ?? '',
        apiKey: json['apiKey']?.toString() ?? '',
        maxContextTokens:
            int.tryParse(json['maxContextTokens']?.toString() ?? '') ?? 131072,
        maxOutputTokens:
            int.tryParse(json['maxOutputTokens']?.toString() ?? '') ?? 16384,
        streamResponses: json['streamResponses'] != false,
        modelPath: json['modelPath']?.toString() ?? '',
        mmprojPath: json['mmprojPath']?.toString() ?? '',
        llamaMode: json['llamaMode']?.toString() ?? '',
        llamaDir: json['llamaDir']?.toString() ?? '',
        llamaPort: int.tryParse(json['llamaPort']?.toString() ?? '') ?? 1234,
        llamaSettings: LlamaSettings.fromJson(
            json['llamaSettings'] is Map<String, dynamic>
                ? json['llamaSettings'] as Map<String, dynamic>
                : const <String, dynamic>{}),
      );

  final String id;
  final String name;
  final ProfileKind kind;
  final String baseUrl;
  final String model;
  final String apiKey;
  final int maxContextTokens;
  final int maxOutputTokens;
  final bool streamResponses;
  final String modelPath;
  final String mmprojPath;
  final String llamaMode;
  final String llamaDir;
  final int llamaPort;
  final LlamaSettings llamaSettings;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'baseUrl': baseUrl,
        'model': model,
        'apiKey': apiKey,
        'maxContextTokens': maxContextTokens,
        'maxOutputTokens': maxOutputTokens,
        'streamResponses': streamResponses,
        'modelPath': modelPath,
        'mmprojPath': mmprojPath,
        'llamaMode': llamaMode,
        'llamaDir': llamaDir,
        'llamaPort': llamaPort,
        'llamaSettings': llamaSettings.toJson(),
      };

  ModelProfile copyWith(
          {String? id,
          String? name,
          String? baseUrl,
          String? model,
          String? apiKey,
          int? maxContextTokens,
          int? maxOutputTokens,
          bool? streamResponses,
          String? modelPath,
          String? mmprojPath,
          String? llamaMode,
          String? llamaDir,
          int? llamaPort,
          LlamaSettings? llamaSettings}) =>
      ModelProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        kind: kind,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        apiKey: apiKey ?? this.apiKey,
        maxContextTokens: maxContextTokens ?? this.maxContextTokens,
        maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
        streamResponses: streamResponses ?? this.streamResponses,
        modelPath: modelPath ?? this.modelPath,
        mmprojPath: mmprojPath ?? this.mmprojPath,
        llamaMode: llamaMode ?? this.llamaMode,
        llamaDir: llamaDir ?? this.llamaDir,
        llamaPort: llamaPort ?? this.llamaPort,
        llamaSettings: llamaSettings ?? this.llamaSettings,
      );
}

class LlamaSettings {
  const LlamaSettings({
    this.contextLength = 8192,
    this.gpuLayers = 999,
    this.cpuThreads = 8,
    this.batchSize = 512,
    this.maxConcurrentPredictions = 1,
    this.unifiedKvCache = false,
    this.experimental = false,
    this.ropeFreqBase = 0.0,
    this.ropeFreqScale = 0.0,
    this.offloadKvCache = true,
    this.keepModelInMemory = true,
    this.tryMmap = true,
    this.seed = -1,
    this.randomSeed = true,
    this.flashAttention = true,
    this.cacheKQuantization = 'f16',
    this.cacheVQuantization = 'f16',
  });

  factory LlamaSettings.fromJson(Map<String, dynamic> json) => LlamaSettings(
        contextLength:
            int.tryParse(json['contextLength']?.toString() ?? '') ?? 8192,
        gpuLayers: int.tryParse(json['gpuLayers']?.toString() ?? '') ?? 999,
        cpuThreads: int.tryParse(json['cpuThreads']?.toString() ?? '') ?? 8,
        batchSize: int.tryParse(json['batchSize']?.toString() ?? '') ?? 512,
        maxConcurrentPredictions:
            int.tryParse(json['maxConcurrentPredictions']?.toString() ?? '') ??
                1,
        unifiedKvCache: json['unifiedKvCache'] == true,
        experimental: json['experimental'] == true,
        ropeFreqBase:
            double.tryParse(json['ropeFreqBase']?.toString() ?? '') ?? 0.0,
        ropeFreqScale:
            double.tryParse(json['ropeFreqScale']?.toString() ?? '') ?? 0.0,
        offloadKvCache: json['offloadKvCache'] != false,
        keepModelInMemory: json['keepModelInMemory'] != false,
        tryMmap: json['tryMmap'] != false,
        seed: int.tryParse(json['seed']?.toString() ?? '') ?? -1,
        randomSeed: json['randomSeed'] != false,
        flashAttention: json['flashAttention'] != false,
        cacheKQuantization: json['cacheKQuantization']?.toString() ?? 'f16',
        cacheVQuantization: json['cacheVQuantization']?.toString() ?? 'f16',
      );

  final int contextLength;
  final int gpuLayers;
  final int cpuThreads;
  final int batchSize;
  final int maxConcurrentPredictions;
  final bool unifiedKvCache;
  final bool experimental;
  final double ropeFreqBase;
  final double ropeFreqScale;
  final bool offloadKvCache;
  final bool keepModelInMemory;
  final bool tryMmap;
  final int seed;
  final bool randomSeed;
  final bool flashAttention;
  final String cacheKQuantization;
  final String cacheVQuantization;

  Map<String, dynamic> toJson() => {
        'contextLength': contextLength,
        'gpuLayers': gpuLayers,
        'cpuThreads': cpuThreads,
        'batchSize': batchSize,
        'maxConcurrentPredictions': maxConcurrentPredictions,
        'unifiedKvCache': unifiedKvCache,
        'experimental': experimental,
        'ropeFreqBase': ropeFreqBase,
        'ropeFreqScale': ropeFreqScale,
        'offloadKvCache': offloadKvCache,
        'keepModelInMemory': keepModelInMemory,
        'tryMmap': tryMmap,
        'seed': seed,
        'randomSeed': randomSeed,
        'flashAttention': flashAttention,
        'cacheKQuantization': cacheKQuantization,
        'cacheVQuantization': cacheVQuantization,
      };

  LlamaSettings copyWith(
          {int? contextLength,
          int? gpuLayers,
          int? cpuThreads,
          int? batchSize,
          int? maxConcurrentPredictions,
          bool? unifiedKvCache,
          bool? experimental,
          double? ropeFreqBase,
          double? ropeFreqScale,
          bool? offloadKvCache,
          bool? keepModelInMemory,
          bool? tryMmap,
          int? seed,
          bool? randomSeed,
          bool? flashAttention,
          String? cacheKQuantization,
          String? cacheVQuantization}) =>
      LlamaSettings(
        contextLength: contextLength ?? this.contextLength,
        gpuLayers: gpuLayers ?? this.gpuLayers,
        cpuThreads: cpuThreads ?? this.cpuThreads,
        batchSize: batchSize ?? this.batchSize,
        maxConcurrentPredictions:
            maxConcurrentPredictions ?? this.maxConcurrentPredictions,
        unifiedKvCache: unifiedKvCache ?? this.unifiedKvCache,
        experimental: experimental ?? this.experimental,
        ropeFreqBase: ropeFreqBase ?? this.ropeFreqBase,
        ropeFreqScale: ropeFreqScale ?? this.ropeFreqScale,
        offloadKvCache: offloadKvCache ?? this.offloadKvCache,
        keepModelInMemory: keepModelInMemory ?? this.keepModelInMemory,
        tryMmap: tryMmap ?? this.tryMmap,
        seed: seed ?? this.seed,
        randomSeed: randomSeed ?? this.randomSeed,
        flashAttention: flashAttention ?? this.flashAttention,
        cacheKQuantization: cacheKQuantization ?? this.cacheKQuantization,
        cacheVQuantization: cacheVQuantization ?? this.cacheVQuantization,
      );

  List<String> toLlamaArgs(String modelPath, int port,
      {String mmprojPath = '', String backendMode = ''}) {
    final mode = backendMode.toLowerCase();
    final effectiveGpuLayers = mode == 'cpu' ? 0 : gpuLayers;
    final args = <String>[
      '--model',
      modelPath,
      '--host',
      '127.0.0.1',
      '--port',
      port.toString(),
      '--ctx-size',
      contextLength.toString(),
      '--n-gpu-layers',
      effectiveGpuLayers.toString(),
      '--threads',
      cpuThreads.toString(),
      '--batch-size',
      batchSize.toString(),
      '--parallel',
      maxConcurrentPredictions.toString(),
      '--cache-type-k',
      cacheKQuantization,
      '--cache-type-v',
      cacheVQuantization
    ];
    if (mmprojPath.trim().isNotEmpty) args.addAll(['--mmproj', mmprojPath]);
    if (flashAttention) args.addAll(['--flash-attn', 'auto']);
    if (!tryMmap) args.add('--no-mmap');
    if (keepModelInMemory) args.add('--mlock');
    if (!offloadKvCache) args.add('--no-kv-offload');
    if (ropeFreqBase > 0)
      args.addAll(['--rope-freq-base', ropeFreqBase.toString()]);
    if (ropeFreqScale > 0)
      args.addAll(['--rope-freq-scale', ropeFreqScale.toString()]);
    if (!randomSeed && seed >= 0) args.addAll(['--seed', seed.toString()]);
    return args;
  }
}

enum PermissionMode { askEveryAction, askCriticalOnly, fullAccess }

extension PermissionModeLabel on PermissionMode {
  String get label => switch (this) {
        PermissionMode.askEveryAction =>
          'Работа с запросами разрешений у пользователя',
        PermissionMode.askCriticalOnly =>
          'Работа с запросами у пользователя критичный действий',
        PermissionMode.fullAccess => 'Работа в режиме полного доступа',
      };
}

enum CreationMode {
  autoComplexity,
  onePassFull,
  stagedOnePass,
  stagedWithUserPauses,
  infiniteImprove
}

extension CreationModeLabel on CreationMode {
  String get label => switch (this) {
        CreationMode.autoComplexity =>
          'Автоматически с учетом сложности проекта',
        CreationMode.onePassFull =>
          'Пытаться сделать полностью за один проход весь проект с учетом задания',
        CreationMode.stagedOnePass =>
          'Пытаться сделать полностью за один проход, предварительно разбив проект на этапы, в процессе работы собирать промежуточные версии',
        CreationMode.stagedWithUserPauses =>
          'Разбить проект на этапы, собирать промежуточные версии с паузами для тестирования и доработок пользователя',
        CreationMode.infiniteImprove =>
          'Бесконечное выполнение и совершенствование',
      };
}

class EmailAccountConfig {
  const EmailAccountConfig({
    required this.id,
    required this.address,
    required this.displayName,
    required this.imapHost,
    required this.imapPort,
    required this.smtpHost,
    required this.smtpPort,
    required this.username,
    required this.password,
    required this.useSsl,
  });

  final String id;
  final String address;
  final String displayName;
  final String imapHost;
  final int imapPort;
  final String smtpHost;
  final int smtpPort;
  final String username;
  final String password;
  final bool useSsl;

  EmailAccountConfig copyWith(
          {String? id,
          String? address,
          String? displayName,
          String? imapHost,
          int? imapPort,
          String? smtpHost,
          int? smtpPort,
          String? username,
          String? password,
          bool? useSsl}) =>
      EmailAccountConfig(
        id: id ?? this.id,
        address: address ?? this.address,
        displayName: displayName ?? this.displayName,
        imapHost: imapHost ?? this.imapHost,
        imapPort: imapPort ?? this.imapPort,
        smtpHost: smtpHost ?? this.smtpHost,
        smtpPort: smtpPort ?? this.smtpPort,
        username: username ?? this.username,
        password: password ?? this.password,
        useSsl: useSsl ?? this.useSsl,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'address': address,
        'displayName': displayName,
        'imapHost': imapHost,
        'imapPort': imapPort,
        'smtpHost': smtpHost,
        'smtpPort': smtpPort,
        'username': username,
        'password': password,
        'useSsl': useSsl,
      };

  factory EmailAccountConfig.fromJson(Map<String, dynamic> json) =>
      EmailAccountConfig(
        id: json['id']?.toString() ??
            'mail_${DateTime.now().microsecondsSinceEpoch}',
        address: json['address']?.toString() ?? '',
        displayName: json['displayName']?.toString() ?? '',
        imapHost: json['imapHost']?.toString() ?? '',
        imapPort: int.tryParse(json['imapPort']?.toString() ?? '') ?? 993,
        smtpHost: json['smtpHost']?.toString() ?? '',
        smtpPort: int.tryParse(json['smtpPort']?.toString() ?? '') ?? 465,
        username: json['username']?.toString() ?? '',
        password: json['password']?.toString() ?? '',
        useSsl: json['useSsl'] != false,
      );

  String get safeSummary =>
      '$address • IMAP $imapHost:$imapPort • SMTP $smtpHost:$smtpPort • SSL=${useSsl ? 'yes' : 'no'}';
}

class ApiOutputTemplate {
  const ApiOutputTemplate({
    required this.id,
    required this.name,
    required this.endpoint,
    required this.method,
    required this.headersJson,
    required this.bodyTemplate,
    required this.enabled,
  });

  final String id;
  final String name;
  final String endpoint;
  final String method;
  final String headersJson;
  final String bodyTemplate;
  final bool enabled;

  factory ApiOutputTemplate.telegramExample() => ApiOutputTemplate(
        id: 'api_${DateTime.now().microsecondsSinceEpoch}',
        name: 'Telegram bot message',
        endpoint: 'https://api.telegram.org/bot<token>/sendMessage',
        method: 'POST',
        headersJson: '{"Content-Type":"application/json"}',
        bodyTemplate:
            '{"chat_id":"<chat_id>","text":"{{text}}","parse_mode":"HTML"}',
        enabled: true,
      );

  factory ApiOutputTemplate.fromJson(Map<String, dynamic> json) =>
      ApiOutputTemplate(
        id: json['id']?.toString() ??
            'api_${DateTime.now().microsecondsSinceEpoch}',
        name: json['name']?.toString() ?? 'API',
        endpoint: json['endpoint']?.toString() ?? '',
        method: json['method']?.toString() ?? 'POST',
        headersJson: json['headersJson']?.toString() ?? '{}',
        bodyTemplate: json['bodyTemplate']?.toString() ?? '{"text":"{{text}}"}',
        enabled: json['enabled'] != false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'endpoint': endpoint,
        'method': method,
        'headersJson': headersJson,
        'bodyTemplate': bodyTemplate,
        'enabled': enabled,
      };
}

class AgentTriggerConfig {
  const AgentTriggerConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.parametersJson,
    required this.enabled,
  });

  final String id;
  final String name;
  final String type;
  final String parametersJson;
  final bool enabled;

  factory AgentTriggerConfig.fromJson(Map<String, dynamic> json) =>
      AgentTriggerConfig(
        id: json['id']?.toString() ??
            'trigger_${DateTime.now().microsecondsSinceEpoch}',
        name: json['name']?.toString() ?? 'Trigger',
        type: json['type']?.toString() ?? 'manual',
        parametersJson: json['parametersJson']?.toString() ?? '{}',
        enabled: json['enabled'] != false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'parametersJson': parametersJson,
        'enabled': enabled,
      };
}

class AgentScheduleConfig {
  const AgentScheduleConfig({
    required this.id,
    required this.projectPath,
    required this.name,
    required this.scheduleJson,
    required this.prompt,
    required this.attachmentPaths,
    required this.extraFolders,
    required this.permissionMode,
    required this.profileId,
    required this.apiTemplateIds,
    required this.emailAccountId,
    required this.formatPrompt,
    required this.enabled,
  });

  final String id;
  final String projectPath;
  final String name;
  final String scheduleJson;
  final String prompt;
  final List<String> attachmentPaths;
  final List<String> extraFolders;
  final String permissionMode;
  final String profileId;
  final List<String> apiTemplateIds;
  final String emailAccountId;
  final String formatPrompt;
  final bool enabled;

  factory AgentScheduleConfig.fromJson(Map<String, dynamic> json) =>
      AgentScheduleConfig(
        id: json['id']?.toString() ??
            'schedule_${DateTime.now().microsecondsSinceEpoch}',
        projectPath: json['projectPath']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Schedule',
        scheduleJson: json['scheduleJson']?.toString() ?? '{}',
        prompt: json['prompt']?.toString() ?? '',
        attachmentPaths: (json['attachmentPaths'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        extraFolders: (json['extraFolders'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        permissionMode: json['permissionMode']?.toString() ?? 'askCriticalOnly',
        profileId: json['profileId']?.toString() ?? 'auto',
        apiTemplateIds: (json['apiTemplateIds'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        emailAccountId: json['emailAccountId']?.toString() ?? '',
        formatPrompt: json['formatPrompt']?.toString() ?? '',
        enabled: json['enabled'] != false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectPath': projectPath,
        'name': name,
        'scheduleJson': scheduleJson,
        'prompt': prompt,
        'attachmentPaths': attachmentPaths,
        'extraFolders': extraFolders,
        'permissionMode': permissionMode,
        'profileId': profileId,
        'apiTemplateIds': apiTemplateIds,
        'emailAccountId': emailAccountId,
        'formatPrompt': formatPrompt,
        'enabled': enabled,
      };
}

class IndexLocationConfig {
  const IndexLocationConfig({
    required this.path,
    required this.indexNames,
    required this.indexContents,
  });

  final String path;
  final bool indexNames;
  final bool indexContents;

  factory IndexLocationConfig.fromJson(Map<String, dynamic> json) =>
      IndexLocationConfig(
        path: json['path']?.toString() ?? '',
        indexNames: json['indexNames'] != false,
        indexContents: json['indexContents'] == true,
      );

  Map<String, dynamic> toJson() => {
        'path': path,
        'indexNames': indexNames,
        'indexContents': indexContents,
      };
}

class CustomAgentToolConfig {
  const CustomAgentToolConfig({
    required this.id,
    required this.name,
    required this.description,
    required this.scriptPath,
    required this.commandTemplate,
    required this.temporary,
    required this.enabled,
  });

  final String id;
  final String name;
  final String description;
  final String scriptPath;
  final String commandTemplate;
  final bool temporary;
  final bool enabled;

  factory CustomAgentToolConfig.fromJson(Map<String, dynamic> json) =>
      CustomAgentToolConfig(
        id: json['id']?.toString() ??
            'tool_${DateTime.now().microsecondsSinceEpoch}',
        name: json['name']?.toString() ?? 'tool',
        description: json['description']?.toString() ?? '',
        scriptPath: json['scriptPath']?.toString() ?? '',
        commandTemplate: json['commandTemplate']?.toString() ?? '',
        temporary: json['temporary'] == true,
        enabled: json['enabled'] != false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'scriptPath': scriptPath,
        'commandTemplate': commandTemplate,
        'temporary': temporary,
        'enabled': enabled,
      };
}

class ScheduledTaskRunRecord {
  const ScheduledTaskRunRecord({
    required this.id,
    required this.projectName,
    required this.scheduleName,
    required this.triggerName,
    required this.successfulCommands,
    required this.errors,
    required this.dialogText,
    required this.createdAt,
  });

  final String id;
  final String projectName;
  final String scheduleName;
  final String triggerName;
  final int successfulCommands;
  final int errors;
  final String dialogText;
  final DateTime createdAt;

  factory ScheduledTaskRunRecord.fromJson(Map<String, dynamic> json) =>
      ScheduledTaskRunRecord(
        id: json['id']?.toString() ??
            'run_${DateTime.now().microsecondsSinceEpoch}',
        projectName: json['projectName']?.toString() ?? '',
        scheduleName: json['scheduleName']?.toString() ?? '',
        triggerName: json['triggerName']?.toString() ?? '',
        successfulCommands:
            int.tryParse(json['successfulCommands']?.toString() ?? '') ?? 0,
        errors: int.tryParse(json['errors']?.toString() ?? '') ?? 0,
        dialogText: json['dialogText']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectName': projectName,
        'scheduleName': scheduleName,
        'triggerName': triggerName,
        'successfulCommands': successfulCommands,
        'errors': errors,
        'dialogText': dialogText,
        'createdAt': createdAt.toIso8601String(),
      };
}

class HfModelSearchResult {
  const HfModelSearchResult({required this.id, required this.downloads});
  final String id;
  final int downloads;
}

class HfFileEntry {
  const HfFileEntry(
      {required this.repoId, required this.path, required this.size});
  final String repoId;
  final String path;
  final int size;
}

class AvailableModel {
  const AvailableModel(this.name, this.maxContextTokens,
      {this.maxOutputTokens = 16384, this.path = ''});
  final String name;
  final int maxContextTokens;
  final int maxOutputTokens;
  final String path;
}

class LocalLlamaCandidate {
  const LocalLlamaCandidate(
      {required this.mode, required this.llamaDir, required this.modelPath});
  final String mode;
  final String llamaDir;
  final String modelPath;
}
