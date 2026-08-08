import 'dart:convert';

import 'project_task_mode.dart';

enum TaskDomain {
  software,
  documents,
  spreadsheets,
  presentations,
  diagrams,
  email,
  remoteAccess,
  systemAdministration,
  securityAssessment,
  webResearch,
  deviceSearch,
  fileOperations,
  applicationControl,
  dataAnalysis,
  general,
}

enum TaskAction {
  analyze,
  search,
  create,
  edit,
  execute,
  connect,
  configure,
  test,
  verify,
  install,
  send,
  delete,
}

class TaskIntentProfile {
  const TaskIntentProfile({
    required this.originalPrompt,
    required this.projectMode,
    required this.automaticallyDetected,
    required this.primaryDomain,
    required this.domains,
    required this.actions,
    required this.capabilities,
    required this.completionCriteria,
    required this.recommendedInitialTools,
    required this.requiresProjectAudit,
    required this.readOnly,
    required this.externalTarget,
    required this.highImpact,
  });

  final String originalPrompt;
  final ProjectTaskMode projectMode;
  final bool automaticallyDetected;
  final TaskDomain primaryDomain;
  final Set<TaskDomain> domains;
  final Set<TaskAction> actions;
  final Set<String> capabilities;
  final List<String> completionCriteria;
  final List<String> recommendedInitialTools;
  final bool requiresProjectAudit;
  final bool readOnly;
  final bool externalTarget;
  final bool highImpact;

  bool hasDomain(TaskDomain domain) => domains.contains(domain);

  bool get expectsMutation => actions.any(const {
        TaskAction.create,
        TaskAction.edit,
        TaskAction.configure,
        TaskAction.install,
        TaskAction.delete,
      }.contains);

  bool get expectsVerification =>
      expectsMutation ||
      actions.any(const {
        TaskAction.execute,
        TaskAction.connect,
        TaskAction.test,
        TaskAction.verify,
      }.contains);

  Map<String, Object?> toJson() => {
        'project_task_mode': projectMode.name,
        'automatically_detected': automaticallyDetected,
        'primary_domain': primaryDomain.name,
        'domains': domains.map((value) => value.name).toList(growable: false),
        'actions': actions.map((value) => value.name).toList(growable: false),
        'capabilities': capabilities.toList(growable: false),
        'requires_project_audit': requiresProjectAudit,
        'read_only': readOnly,
        'external_target': externalTarget,
        'high_impact': highImpact,
        'recommended_initial_tools': recommendedInitialTools,
        'completion_criteria': completionCriteria,
      };

  String toPromptBlock({
    required String projectPath,
    required Iterable<String> projectEntries,
  }) {
    final snapshot = projectEntries.take(100).toList(growable: false);
    final data = <String, Object?>{
      ...toJson(),
      'project': projectPath,
      'project_root_entries': snapshot,
    };
    return '''[TASK_EXECUTION_FRAME]
The user's original request is authoritative and must not be rewritten or
replaced by this frame. The frame may contain several simultaneous domains.
${const JsonEncoder.withIndent('  ').convert(data)}

Operating rules:
- Preserve every explicit user requirement and correction across all domains.
- Choose tools from the actual next obstacle; do not force a software workflow
  onto document, mail, device-search, remote-access, or research work.
- Inspect available context before asking. Ask one short neutral clarification
  only when a missing fact makes safe progress impossible (for example an
  unknown target, missing credentials, or authorization for a high-impact
  external action). Do not offer a one-directional reinterpretation.
- Break long work into verifiable subtasks. Re-plan when evidence invalidates
  the current approach, and continue from successful work instead of restarting.
- A task is complete only when the listed completion criteria are evidenced.
[/TASK_EXECUTION_FRAME]''';
  }
}

class TaskIntentAnalyzer {
  const TaskIntentAnalyzer();

  TaskIntentProfile analyze(
    String prompt, {
    ProjectTaskMode projectMode = ProjectTaskMode.automatic,
  }) {
    final normalized = _normalize(prompt);
    final scores = <TaskDomain, int>{};

    void score(TaskDomain domain, int weight, Iterable<String> patterns) {
      for (final pattern in patterns) {
        if (normalized.contains(pattern)) {
          scores[domain] = (scores[domain] ?? 0) + weight;
        }
      }
    }

    score(TaskDomain.email, 4, const [
      'почт',
      'email',
      'e-mail',
      'imap',
      'smtp',
      'письм',
      'gmail',
      'outlook'
    ]);
    score(TaskDomain.documents, 3, const [
      'документ',
      'docx',
      'word',
      'rtf',
      'odt',
      'pdf',
      'текст в документ'
    ]);
    score(TaskDomain.spreadsheets, 4, const [
      'xlsx',
      'xls',
      'таблиц',
      'spreadsheet',
      'ods',
      'csv',
      'ячейк',
      'формул'
    ]);
    score(TaskDomain.presentations, 4,
        const ['pptx', 'ppt', 'презентац', 'слайд', 'odp']);
    score(TaskDomain.diagrams, 4,
        const ['vsdx', 'visio', 'диаграм', 'блок-схем', 'схем']);
    score(TaskDomain.remoteAccess, 5, const [
      'ssh',
      'telnet',
      'удаленн',
      'remote host',
      'jump host',
      'bastion'
    ]);
    score(TaskDomain.securityAssessment, 5, const [
      'nmap',
      'metasploit',
      'msfconsole',
      'пентест',
      'pentest',
      'сканировани порт',
      'уязвимост',
      'эксплойт'
    ]);
    score(TaskDomain.systemAdministration, 3, const [
      'настрой сервер',
      'настроить сервер',
      'powershell',
      'служб',
      'service',
      'systemctl',
      'реестр',
      'registry',
      'администр',
      'исправь систем'
    ]);
    score(TaskDomain.webResearch, 3, const [
      'поищи в интернет',
      'найди в интернет',
      'web search',
      'исследуй сайт',
      'проанализируй сайт',
      'сайт',
      'источник',
      'ссылк'
    ]);
    score(TaskDomain.deviceSearch, 4, const [
      'на компьютере',
      'на устройстве',
      'файловой систем',
      'найди документ',
      'найти документ',
      'поиск файлов',
      'по всему диску',
      'список ip'
    ]);
    score(TaskDomain.fileOperations, 2, const [
      'файл',
      'папк',
      'каталог',
      'архив',
      'распак',
      'скопир',
      'перемест'
    ]);
    score(TaskDomain.applicationControl, 4, const [
      'открой прилож',
      'запусти прилож',
      'управляй прилож',
      'браузер',
      'работать с прилож',
      'gui',
      'окно программ'
    ]);
    score(TaskDomain.software, 3, const [
      'напиши программ',
      'создай программ',
      'собери программ',
      'сборка программ',
      'собери существующ',
      'выполни сборк',
      'запусти сборк',
      'напиши приложени',
      'создай приложени',
      'разработай приложени',
      'код',
      'исходник',
      'flutter',
      'python',
      'c++',
      'javascript',
      'typescript',
      'скрипт',
      'сценари',
      'java',
      'kotlin',
      'rust',
      'скомпил',
      'компиляц',
      'собери проект',
      'реализуй функц',
      'исправь проект',
      'репозитор'
    ]);
    score(TaskDomain.dataAnalysis, 3, const [
      'проанализируй данные',
      'анализ данных',
      'статистик',
      'dataset',
      'набор данных',
      'агрегац',
      'график'
    ]);

    if (scores.isEmpty) scores[TaskDomain.general] = 1;
    final ranked = scores.entries.toList(growable: false)
      ..sort((a, b) {
        final byScore = b.value.compareTo(a.value);
        return byScore != 0 ? byScore : a.key.index.compareTo(b.key.index);
      });
    final peak = ranked.first.value;
    final domains = ranked
        .where((entry) => entry.value >= 3 || entry.value >= peak - 1)
        .map((entry) => entry.key)
        .toSet();
    if (domains.isEmpty) domains.add(ranked.first.key);
    domains.addAll(_domainsForProjectMode(projectMode));
    final primaryDomain =
        _primaryDomainForProjectMode(projectMode) ?? ranked.first.key;

    final actions = _detectActions(normalized);
    if (actions.isEmpty) actions.add(TaskAction.analyze);
    final capabilities = _capabilities(domains);
    final externalTarget = domains.any(const {
      TaskDomain.remoteAccess,
      TaskDomain.securityAssessment,
      TaskDomain.email,
    }.contains);
    final highImpact = actions.any(const {
          TaskAction.delete,
          TaskAction.install,
          TaskAction.send,
          TaskAction.configure,
        }.contains) &&
        externalTarget;
    final readOnly = !actions.any(const {
      TaskAction.create,
      TaskAction.edit,
      TaskAction.configure,
      TaskAction.install,
      TaskAction.send,
      TaskAction.delete,
      TaskAction.execute,
    }.contains);
    final requiresProjectAudit = domains.contains(TaskDomain.software) &&
        actions.any(const {
          TaskAction.create,
          TaskAction.edit,
          TaskAction.test,
          TaskAction.execute,
        }.contains);

    return TaskIntentProfile(
      originalPrompt: prompt,
      projectMode: projectMode,
      automaticallyDetected: projectMode == ProjectTaskMode.automatic,
      primaryDomain: primaryDomain,
      domains: domains,
      actions: actions,
      capabilities: capabilities,
      completionCriteria: _completionCriteria(domains, actions),
      recommendedInitialTools: _recommendedTools(domains, actions),
      requiresProjectAudit: requiresProjectAudit,
      readOnly: readOnly,
      externalTarget: externalTarget,
      highImpact: highImpact,
    );
  }

  Set<TaskDomain> _domainsForProjectMode(ProjectTaskMode mode) =>
      switch (mode) {
        ProjectTaskMode.automatic => const <TaskDomain>{},
        ProjectTaskMode.software => const {TaskDomain.software},
        ProjectTaskMode.documents => const {TaskDomain.documents},
        ProjectTaskMode.fileSystem => const {
            TaskDomain.fileOperations,
            TaskDomain.deviceSearch,
          },
        ProjectTaskMode.remoteSystems => const {
            TaskDomain.remoteAccess,
            TaskDomain.systemAdministration,
          },
        ProjectTaskMode.pentesting => const {
            TaskDomain.securityAssessment,
            TaskDomain.remoteAccess,
          },
      };

  TaskDomain? _primaryDomainForProjectMode(ProjectTaskMode mode) =>
      switch (mode) {
        ProjectTaskMode.automatic => null,
        ProjectTaskMode.software => TaskDomain.software,
        ProjectTaskMode.documents => TaskDomain.documents,
        ProjectTaskMode.fileSystem => TaskDomain.fileOperations,
        ProjectTaskMode.remoteSystems => TaskDomain.remoteAccess,
        ProjectTaskMode.pentesting => TaskDomain.securityAssessment,
      };

  Set<TaskAction> _detectActions(String text) {
    final result = <TaskAction>{};
    void add(TaskAction action, Iterable<String> markers) {
      if (markers.any(text.contains)) result.add(action);
    }

    add(TaskAction.search,
        const ['найд', 'поищ', 'поиск', 'search', 'locate', 'scan']);
    add(TaskAction.create,
        const ['созда', 'сделай', 'напиши', 'сгенер', 'build ', 'create']);
    add(TaskAction.edit,
        const ['измени', 'исправ', 'доработ', 'редакт', 'обнов', 'modify']);
    add(TaskAction.execute,
        const ['запусти', 'выполни', 'execute', 'run ', 'открой']);
    add(TaskAction.connect,
        const ['подключ', 'соедини', 'connect', 'ssh', 'telnet']);
    add(TaskAction.configure,
        const ['настрой', 'сконфигур', 'configure', 'исправь систем']);
    add(TaskAction.test,
        const ['тест', 'проверь код', 'собери', 'скомпил', 'pentest']);
    add(TaskAction.verify, const ['проверь', 'убедись', 'verify', 'валидир']);
    add(TaskAction.install,
        const ['установ', 'инсталл', 'install', 'разверни']);
    add(TaskAction.send, const ['отправ', 'send ', 'опубликуй', 'publish']);
    add(TaskAction.delete, const ['удали', 'delete', 'remove', 'очисти']);
    add(TaskAction.analyze,
        const ['анализ', 'изучи', 'разбер', 'оцени', 'прочитай', 'summar']);
    return result;
  }

  Set<String> _capabilities(Set<TaskDomain> domains) {
    final result = <String>{'planning', 'evidence-ledger', 'adaptive-recovery'};
    for (final domain in domains) {
      result.addAll(switch (domain) {
        TaskDomain.software => const {
            'project-files',
            'command-execution',
            'build-and-test'
          },
        TaskDomain.documents => const {
            'document-structure',
            'document-editing',
            'document-build'
          },
        TaskDomain.spreadsheets => const {
            'workbook-structure',
            'formulas',
            'spreadsheet-editing'
          },
        TaskDomain.presentations => const {
            'slide-layout',
            'presentation-editing'
          },
        TaskDomain.diagrams => const {'diagram-pages', 'shape-geometry'},
        TaskDomain.email => const {'mail-search', 'mail-draft'},
        TaskDomain.remoteAccess => const {
            'persistent-terminal',
            'ssh',
            'terminal-handoff'
          },
        TaskDomain.systemAdministration => const {
            'persistent-terminal',
            'system-diagnostics'
          },
        TaskDomain.securityAssessment => const {
            'persistent-terminal',
            'network-tools',
            'scope-and-authorization'
          },
        TaskDomain.webResearch => const {
            'search',
            'article-extraction',
            'source-comparison'
          },
        TaskDomain.deviceSearch => const {
            'device-index',
            'filesystem-search',
            'document-search'
          },
        TaskDomain.fileOperations => const {'file-operations'},
        TaskDomain.applicationControl => const {
            'persistent-terminal',
            'application-control'
          },
        TaskDomain.dataAnalysis => const {
            'data-parsing',
            'calculation',
            'visualization'
          },
        TaskDomain.general => const {'general-tools'},
      });
    }
    return result;
  }

  List<String> _recommendedTools(
      Set<TaskDomain> domains, Set<TaskAction> actions) {
    final result = <String>[];
    void addAll(Iterable<String> values) {
      for (final value in values) {
        if (!result.contains(value)) result.add(value);
      }
    }

    if (domains.contains(TaskDomain.software)) {
      addAll(const ['project_map', 'read_file', 'set_task_plan']);
    }
    if (domains.intersection(const {
      TaskDomain.documents,
      TaskDomain.spreadsheets,
      TaskDomain.presentations,
      TaskDomain.diagrams,
    }).isNotEmpty) {
      addAll(const ['read_document_structure']);
    }
    if (domains.intersection(const {
      TaskDomain.remoteAccess,
      TaskDomain.systemAdministration,
      TaskDomain.securityAssessment,
    }).isNotEmpty) {
      addAll(const [
        'wsl_list',
        'terminal_open',
        'terminal_write',
        'terminal_read'
      ]);
    }
    if (domains.contains(TaskDomain.webResearch)) {
      addAll(const ['web_research', 'web_fetch']);
    }
    if (domains.contains(TaskDomain.deviceSearch)) {
      if (domains.intersection(const {
        TaskDomain.documents,
        TaskDomain.spreadsheets,
        TaskDomain.presentations,
        TaskDomain.diagrams,
      }).isNotEmpty) {
        addAll(const ['search_device_documents']);
      }
      addAll(const ['search_device_index', 'filesystem_search']);
    }
    if (actions.contains(TaskAction.verify) &&
        domains.contains(TaskDomain.software)) {
      addAll(const ['run_tests']);
    }
    return result.take(10).toList(growable: false);
  }

  List<String> _completionCriteria(
      Set<TaskDomain> domains, Set<TaskAction> actions) {
    final result = <String>[];
    void add(String value) {
      if (!result.contains(value)) result.add(value);
    }

    if (domains.contains(TaskDomain.software)) {
      add('Requested behavior is implemented in the intended project files.');
      add('Relevant build, tests, or runtime check completed with captured output.');
    }
    if (domains.intersection(const {
      TaskDomain.documents,
      TaskDomain.spreadsheets,
      TaskDomain.presentations,
      TaskDomain.diagrams,
    }).isNotEmpty) {
      add('Document structure and placement are inspected before editing.');
      add('Created or edited document is reparsed and requested content/layout is present.');
    }
    if (domains.intersection(const {
      TaskDomain.remoteAccess,
      TaskDomain.systemAdministration,
      TaskDomain.securityAssessment,
    }).isNotEmpty) {
      add('The terminal session and target context remain identifiable and inspectable.');
      add('The requested remote/system result is verified from command output.');
    }
    if (domains.contains(TaskDomain.webResearch)) {
      add('Relevant page content, not only snippets/navigation, is extracted.');
      add('Material claims are compared across sources and URLs are retained.');
    }
    if (domains.contains(TaskDomain.deviceSearch)) {
      add('Search covers the user-selected scope and returns content-level matches when requested.');
    }
    if (actions.contains(TaskAction.send)) {
      add('External sending is performed only with the required user confirmation.');
    }
    if (result.isEmpty)
      add('The exact user request is answered with observable evidence.');
    return result;
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
