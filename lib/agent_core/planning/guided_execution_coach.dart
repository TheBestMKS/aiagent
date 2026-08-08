import '../build/project_build_recipe.dart';
import 'task_intent_analyzer.dart';

enum GuidedExecutionStage {
  inspect,
  retrieve,
  implement,
  diagnose,
  verify,
  package,
  deliver,
}

class GuidedExecutionInput {
  const GuidedExecutionInput({
    required this.intent,
    required this.taskToolActions,
    required this.fileMutations,
    required this.commandRuns,
    required this.failedCommands,
    required this.lastExitCode,
    required this.lastToolName,
    required this.buildFailureKind,
    required this.buildFailureSummary,
    required this.implicatedFile,
    required this.implicatedFileRead,
    required this.suggestedDiagnosticCommand,
    required this.buildRetryRequired,
    required this.hasPassingVerification,
    required this.completionReady,
    required this.completionBlocker,
    required this.buildRecipe,
  });

  final TaskIntentProfile intent;
  final int taskToolActions;
  final int fileMutations;
  final int commandRuns;
  final int failedCommands;
  final int? lastExitCode;
  final String lastToolName;
  final String buildFailureKind;
  final String buildFailureSummary;
  final String implicatedFile;
  final bool implicatedFileRead;
  final String suggestedDiagnosticCommand;
  final bool buildRetryRequired;
  final bool hasPassingVerification;
  final bool completionReady;
  final String completionBlocker;
  final ProjectBuildRecipe? buildRecipe;
}

class GuidedStepDirective {
  const GuidedStepDirective({
    required this.stage,
    required this.objective,
    required this.preferredTools,
    required this.successSignal,
    this.note = '',
  });

  final GuidedExecutionStage stage;
  final String objective;
  final List<String> preferredTools;
  final String successSignal;
  final String note;

  String toPromptBlock({required bool weakModel}) {
    final buffer = StringBuffer()
      ..writeln('[GUIDED_EXECUTION_STEP]')
      ..writeln('mode=${weakModel ? 'strict_small_model' : 'focused'}')
      ..writeln('stage=${stage.name}')
      ..writeln('single_objective=$objective')
      ..writeln('preferred_tools=${preferredTools.join(', ')}')
      ..writeln('success_signal=$successSignal');
    if (note.trim().isNotEmpty) buffer.writeln('note=${note.trim()}');
    buffer
      ..writeln('rules:')
      ..writeln(
          '- Выполни одно ближайшее проверяемое действие, затем изучи его результат.')
      ..writeln('- Не повторяй уже выполненную команду с теми же аргументами.')
      ..writeln('- Не переписывай весь проект из-за одной ошибки компилятора.')
      ..writeln(
          '- Если не хватает сведений, сначала используй context_search или read_file.')
      ..writeln('- Не объявляй успех без tool-result проверки.')
      ..writeln('[/GUIDED_EXECUTION_STEP]');
    return buffer.toString().trimRight();
  }
}

class GuidedExecutionCoach {
  const GuidedExecutionCoach();

  bool modelNeedsStrictGuidance({
    required String modelName,
    required int contextTokens,
    required int outputTokens,
    required bool localModel,
  }) {
    final normalized = modelName.toLowerCase();
    final parameterMatch = RegExp(
      r'(?:^|[^0-9])([0-9]+(?:\.[0-9]+)?)\s*b(?:[^a-z]|$)',
      caseSensitive: false,
    ).firstMatch(normalized);
    final parameters =
        double.tryParse(parameterMatch?.group(1)?.toString() ?? '');
    return (parameters != null && parameters <= 14) ||
        contextTokens <= 16384 ||
        outputTokens <= 4096 ||
        (localModel && parameters == null);
  }

  GuidedStepDirective nextStep(GuidedExecutionInput input) {
    if (input.taskToolActions > 0 && input.completionReady) {
      return const GuidedStepDirective(
        stage: GuidedExecutionStage.deliver,
        objective:
            'Сообщить фактический результат, выполненную проверку и созданные артефакты.',
        preferredTools: ['get_task_goal', 'get_task_status'],
        successSignal:
            'Итог прямо отвечает исходной задаче и опирается на сохранённые доказательства.',
      );
    }
    final domains = input.intent.domains;
    if (domains.contains(TaskDomain.software)) return _softwareStep(input);
    if (domains.contains(TaskDomain.documents) ||
        domains.contains(TaskDomain.spreadsheets) ||
        domains.contains(TaskDomain.presentations) ||
        domains.contains(TaskDomain.diagrams)) {
      return _documentStep(input);
    }
    if (domains.contains(TaskDomain.remoteAccess) ||
        domains.contains(TaskDomain.systemAdministration) ||
        domains.contains(TaskDomain.securityAssessment)) {
      return _remoteStep(input);
    }
    if (domains.contains(TaskDomain.webResearch)) {
      return const GuidedStepDirective(
        stage: GuidedExecutionStage.retrieve,
        objective:
            'Найти первичные источники и открыть содержимое наиболее релевантного результата.',
        preferredTools: ['web_research', 'duckduckgo_search', 'web_fetch'],
        successSignal:
            'Получен текст источника с URL и фактами, относящимися к запросу.',
      );
    }
    if (domains.contains(TaskDomain.deviceSearch) ||
        domains.contains(TaskDomain.fileOperations)) {
      return const GuidedStepDirective(
        stage: GuidedExecutionStage.inspect,
        objective:
            'Найти требуемые файлы или прочитать выбранное расположение до изменения данных.',
        preferredTools: [
          'search_device_index',
          'filesystem_search',
          'list_device_directory',
          'read_device_text_file',
        ],
        successSignal:
            'Найдены точные пути и прочитано релевантное содержимое.',
      );
    }
    return const GuidedStepDirective(
      stage: GuidedExecutionStage.inspect,
      objective:
          'Уточнить фактическое состояние задачи одним доступным инструментом.',
      preferredTools: ['get_task_goal', 'context_search', 'project_map'],
      successSignal: 'Получен новый проверяемый факт для следующего действия.',
    );
  }

  Set<String> routedTools(GuidedExecutionInput input) {
    final directive = nextStep(input);
    final tools = <String>{
      ...directive.preferredTools,
      'get_task_goal',
      'context_search',
      'context_read',
    };
    final domains = input.intent.domains;
    if (domains.contains(TaskDomain.software)) {
      switch (directive.stage) {
        case GuidedExecutionStage.inspect:
          tools.addAll(const {
            'project_map',
            'list_files',
            'read_file',
            'inspect_project_build',
            'list_local_tools',
            'record_task_context',
          });
          break;
        case GuidedExecutionStage.retrieve:
          tools.addAll(const {
            'context_search',
            'context_read',
            'memory_recall',
            'knowledge_search',
            'list_local_tools',
            'download_to_project',
            'download_to_tools',
          });
          break;
        case GuidedExecutionStage.implement:
          tools.addAll(const {
            'read_file',
            'write_file',
            'create_file',
            'append_file',
            'replace_text',
            'make_dir',
            'delete_path',
            'copy_path',
            'move_path',
            'update_task_subtask',
            'record_task_context',
          });
          break;
        case GuidedExecutionStage.diagnose:
          tools.addAll(const {
            'read_file',
            'replace_text',
            'inspect_project_build',
            'list_local_tools',
            'run_command',
            'run_tests',
            'context_search',
            'context_read',
            'download_to_tools',
            'extract_zip_to_tools',
            'memory_recall',
          });
          break;
        case GuidedExecutionStage.verify:
          tools.addAll(const {
            'inspect_project_build',
            'run_command',
            'run_tests',
            'read_file',
            'get_task_status',
          });
          break;
        case GuidedExecutionStage.package:
          tools.addAll(const {
            'package_project_release',
            'read_file',
            'list_files',
          });
          break;
        case GuidedExecutionStage.deliver:
          tools.addAll(const {
            'get_task_goal',
            'get_task_status',
            'update_task_subtask',
            'package_project_release',
            'memory_remember',
            'remember_solution',
            'promote_golden_path',
          });
          break;
      }
    }
    if (domains.contains(TaskDomain.documents) ||
        domains.contains(TaskDomain.spreadsheets) ||
        domains.contains(TaskDomain.presentations) ||
        domains.contains(TaskDomain.diagrams)) {
      tools.addAll(const {
        'read_document_structure',
        'create_document_from_text',
        'edit_document_text',
        'recognize_image_text',
        'literature_search',
        'literature_list',
        'read_device_text_file',
      });
    }
    if (domains.contains(TaskDomain.deviceSearch) ||
        domains.contains(TaskDomain.fileOperations)) {
      tools.addAll(const {
        'search_device_index',
        'filesystem_search',
        'list_device_directory',
        'read_device_text_file',
        'read_device_folder_texts',
        'search_device_documents',
        'archive_device_children',
        'copy_path',
        'move_path',
      });
    }
    if (domains.contains(TaskDomain.webResearch)) {
      tools.addAll(const {
        'duckduckgo_search',
        'web_fetch',
        'web_deep_fetch',
        'web_research',
        'download_to_project',
        'download_to_tools',
      });
    }
    if (domains.contains(TaskDomain.remoteAccess) ||
        domains.contains(TaskDomain.systemAdministration) ||
        domains.contains(TaskDomain.securityAssessment)) {
      tools.addAll(const {
        'list_local_tools',
        'wsl_list',
        'terminal_open',
        'terminal_write',
        'terminal_read',
        'terminal_list',
        'terminal_close',
        'run_command',
      });
    }
    if (domains.contains(TaskDomain.email)) {
      tools.addAll(const {'email_list_accounts', 'email_draft_smtp'});
    }
    if (input.intent.primaryDomain == TaskDomain.general ||
        domains.contains(TaskDomain.dataAnalysis) ||
        domains.contains(TaskDomain.applicationControl)) {
      tools.addAll(const {
        'project_map',
        'list_files',
        'read_file',
        'write_file',
        'replace_text',
        'run_command',
        'run_tests',
        'list_local_tools',
      });
    }
    return tools;
  }

  GuidedStepDirective _softwareStep(GuidedExecutionInput input) {
    if (input.lastExitCode != null && input.lastExitCode != 0) {
      if (input.failedCommands >= 2 && input.lastToolName != 'context_search') {
        return GuidedStepDirective(
          stage: GuidedExecutionStage.retrieve,
          objective:
              'Найти в памяти текущего и других проектов проверенную подсказку для фактической ошибки сборки.',
          preferredTools: const ['context_search', 'memory_recall'],
          successSignal:
              'Найдена применимая процедура либо подтверждено отсутствие совпадений.',
          note: input.buildFailureSummary,
        );
      }
      if (input.buildFailureKind == 'sourceCompile') {
        if (input.implicatedFile.isNotEmpty && !input.implicatedFileRead) {
          return GuidedStepDirective(
            stage: GuidedExecutionStage.diagnose,
            objective:
                'Прочитать указанный компилятором участок файла ${input.implicatedFile}.',
            preferredTools: const ['read_file'],
            successSignal:
                'Прочитан код около строки ошибки, доступен точный текст для минимальной правки.',
            note: input.buildFailureSummary,
          );
        }
        return GuidedStepDirective(
          stage: GuidedExecutionStage.implement,
          objective:
              'Исправить только причину ошибки компилятора в указанном файле и не менять остальной проект.',
          preferredTools: const ['replace_text', 'read_file'],
          successSignal:
              'Внесена локальная правка, после которой должна быть повторена исходная сборка.',
          note: input.buildFailureSummary,
        );
      }
      if (input.suggestedDiagnosticCommand.isNotEmpty) {
        return GuidedStepDirective(
          stage: GuidedExecutionStage.diagnose,
          objective:
              'Выполнить предложенную диагностическую команду: ${input.suggestedDiagnosticCommand}',
          preferredTools: const ['run_command'],
          successSignal: 'Получен фактический вывод справки или диагностики.',
          note: input.buildFailureSummary,
        );
      }
      return GuidedStepDirective(
        stage: GuidedExecutionStage.diagnose,
        objective:
            'Определить доступный компилятор и корректную команду проекта без переписывания исходников.',
        preferredTools: const ['inspect_project_build', 'list_local_tools'],
        successSignal:
            'Определены экосистема, команда и отсутствующие инструменты.',
        note: input.buildFailureSummary,
      );
    }
    if (input.taskToolActions == 0) {
      return GuidedStepDirective(
        stage: GuidedExecutionStage.inspect,
        objective:
            'Определить структуру проекта и штатный способ его проверки до записи кода.',
        preferredTools: const ['inspect_project_build', 'project_map'],
        successSignal:
            'Известны существующие файлы, экосистема и команда проверки.',
        note: input.buildRecipe?.detected == true
            ? 'Предварительно распознано: ${input.buildRecipe!.ecosystem.label}.'
            : 'Рецепт ещё не определён; вызови inspect_project_build.',
      );
    }
    if (input.fileMutations == 0 && !input.intent.expectsMutation) {
      if (input.intent.expectsVerification && !input.hasPassingVerification) {
        return const GuidedStepDirective(
          stage: GuidedExecutionStage.verify,
          objective:
              'Проверить или собрать существующий проект без изменения исходников.',
          preferredTools: ['run_tests', 'inspect_project_build'],
          successSignal:
              'Штатная команда проекта завершилась с EXIT_CODE: 0 и ожидаемым артефактом.',
        );
      }
      if (input.intent.expectsVerification) {
        return const GuidedStepDirective(
          stage: GuidedExecutionStage.deliver,
          objective:
              'Сообщить результат успешной проверки существующего проекта без изменения исходников.',
          preferredTools: ['get_task_goal', 'get_task_status'],
          successSignal:
              'Итог содержит фактически выполненную команду и её успешный результат.',
        );
      }
      if (input.lastToolName != 'read_file') {
        return const GuidedStepDirective(
          stage: GuidedExecutionStage.inspect,
          objective:
              'Прочитать наиболее релевантный исходный файл для требуемого анализа без изменений.',
          preferredTools: ['read_file', 'list_files'],
          successSignal:
              'Получено фактическое содержимое кода, относящееся к запросу.',
        );
      }
      return const GuidedStepDirective(
        stage: GuidedExecutionStage.deliver,
        objective:
            'Сформулировать результат анализа существующего проекта без изменения файлов.',
        preferredTools: ['get_task_goal', 'get_task_status'],
        successSignal:
            'Итог опирается на прочитанный код и отвечает исходному запросу.',
      );
    }
    if (input.fileMutations == 0) {
      return const GuidedStepDirective(
        stage: GuidedExecutionStage.implement,
        objective:
            'Создать минимальный полный набор исходных файлов для ближайшей подзадачи.',
        preferredTools: ['read_file', 'write_file', 'replace_text', 'make_dir'],
        successSignal:
            'Рабочие исходники записаны в обычные папки проекта без заглушек.',
      );
    }
    if (input.commandRuns == 0 || input.buildRetryRequired) {
      return GuidedStepDirective(
        stage: GuidedExecutionStage.verify,
        objective: input.buildRetryRequired
            ? 'Повторить обязательную исходную команду сборки после последней правки.'
            : 'Запустить автоматически определенную проверку или сборку проекта.',
        preferredTools: const ['run_tests', 'inspect_project_build'],
        successSignal:
            'Команда завершилась с EXIT_CODE: 0 и создала ожидаемый результат.',
        note: input.buildRecipe?.preferredVerificationCommand ?? '',
      );
    }
    if (!input.hasPassingVerification) {
      return const GuidedStepDirective(
        stage: GuidedExecutionStage.verify,
        objective:
            'Выполнить штатную сборку или тест: успешная диагностическая команда сама по себе не подтверждает проект.',
        preferredTools: ['run_tests', 'inspect_project_build'],
        successSignal:
            'Реальная сборка, тест или анализ завершились с EXIT_CODE: 0.',
      );
    }
    if (input.lastExitCode == 0 &&
        input.completionBlocker.contains('release')) {
      return const GuidedStepDirective(
        stage: GuidedExecutionStage.package,
        objective:
            'Упаковать проверенный результат в стандартный каталог release.',
        preferredTools: ['package_project_release'],
        successSignal:
            'Созданы README/CHANGE, source ZIP, артефакты и SHA256SUMS.txt.',
      );
    }
    return const GuidedStepDirective(
      stage: GuidedExecutionStage.deliver,
      objective:
          'Сверить артефакты и критерии задачи, затем сообщить фактический результат.',
      preferredTools: [
        'get_task_goal',
        'update_task_subtask',
        'package_project_release'
      ],
      successSignal:
          'Все подзадачи подтверждены, итог содержит файлы и выполненную проверку.',
    );
  }

  GuidedStepDirective _documentStep(GuidedExecutionInput input) {
    if (input.fileMutations == 0) {
      return const GuidedStepDirective(
        stage: GuidedExecutionStage.inspect,
        objective:
            'Прочитать структуру исходного документа или найти подходящую литературу.',
        preferredTools: [
          'read_document_structure',
          'literature_search',
          'read_device_text_file',
        ],
        successSignal:
            'Получены текст, таблицы, стили и структура исходного материала.',
      );
    }
    return const GuidedStepDirective(
      stage: GuidedExecutionStage.verify,
      objective:
          'Повторно прочитать созданный документ и проверить полноту содержимого.',
      preferredTools: ['read_document_structure', 'edit_document_text'],
      successSignal:
          'Документ читается, содержит все запрошенные разделы и не содержит заглушек.',
    );
  }

  GuidedStepDirective _remoteStep(GuidedExecutionInput input) {
    if (input.taskToolActions == 0) {
      return const GuidedStepDirective(
        stage: GuidedExecutionStage.inspect,
        objective:
            'Открыть постоянную терминальную сессию для целевой системы и сохранить ее идентификатор.',
        preferredTools: ['terminal_open', 'wsl_list'],
        successSignal: 'Сессия запущена и отображается в общей консоли.',
      );
    }
    return const GuidedStepDirective(
      stage: GuidedExecutionStage.diagnose,
      objective:
          'Выполнить одну диагностическую команду в существующей сессии и прочитать полный результат.',
      preferredTools: ['terminal_write', 'terminal_read', 'context_search'],
      successSignal:
          'Получен новый вывод удаленной команды без потери активной сессии.',
    );
  }
}
