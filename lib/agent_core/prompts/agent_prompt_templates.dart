import '../planning/project_task_mode.dart';

class AgentPromptTemplateSpec {
  const AgentPromptTemplateSpec({
    required this.key,
    required this.title,
    required this.description,
    required this.defaultText,
  });

  final String key;
  final String title;
  final String description;
  final String defaultText;
}

class AgentPromptLibrary {
  AgentPromptLibrary([Map<String, String>? overrides])
      : _overrides = Map<String, String>.from(overrides ?? const {});

  final Map<String, String> _overrides;

  static const specs = <AgentPromptTemplateSpec>[
    AgentPromptTemplateSpec(
      key: 'core.execution',
      title: 'Общая логика выполнения',
      description: 'Инварианты выполнения любой задачи.',
      defaultText: '''
Сохраняй исходную формулировку пользователя как авторитетную цель. Работай
до наблюдаемого результата, а не до правдоподобного ответа. Выбирай следующий
инструмент по текущему препятствию, используй уже подтвержденные результаты и
не повторяй действие с теми же аргументами без нового факта или новой гипотезы.
''',
    ),
    AgentPromptTemplateSpec(
      key: 'stage.classify',
      title: 'Определение типа задачи',
      description: 'Используется до планирования в автоматическом режиме.',
      defaultText: '''
Если режим проекта автоматический, сначала определи основной и дополнительные
домены задачи, требуемые действия, ограничения и наблюдаемый конечный результат.
Классификация служит маршрутизацией и никогда не заменяет запрос пользователя.
''',
    ),
    AgentPromptTemplateSpec(
      key: 'stage.goal',
      title: 'Определение конечного результата',
      description: 'Правила фиксации цели задачи.',
      defaultText: '''
Перед существенными действиями проверь CANONICAL_TASK_STATE. Уточни ожидаемый
конечный результат через define_task_goal: перечисли реальные артефакты,
наблюдаемое состояние и критерии проверки. Не считай намерение результатом.
''',
    ),
    AgentPromptTemplateSpec(
      key: 'stage.decompose',
      title: 'Разбиение на подзадачи',
      description: 'Правила иерархического плана.',
      defaultText: '''
Разбей сложную цель на минимальные проверяемые подзадачи. Для каждой зафиксируй
ожидаемый результат. Если подзадача остается сложной, добавь дочерние шаги через
add_task_subtask. Одновременно выполняй только следующий доступный шаг.
''',
    ),
    AgentPromptTemplateSpec(
      key: 'stage.execute',
      title: 'Выполнение подзадачи',
      description: 'Правила действий и обновления прогресса.',
      defaultText: '''
После каждого значимого результата обновляй соответствующую подзадачу через
update_task_subtask. Сохраняй полезные пути, команды, сессии и найденные данные
через record_task_context. При ошибке изучай фактический вывод, меняй гипотезу и
сохраняй уже успешную часть работы.
''',
    ),
    AgentPromptTemplateSpec(
      key: 'stage.verify',
      title: 'Проверка результата',
      description: 'Критерии проверки подзадач и общей цели.',
      defaultText: '''
Сверяй результат каждой подзадачи с ее expected result. После выполнения всех
шагов повторно проверь каждое требование исходной задачи подходящим способом:
тестом, сборкой, повторным чтением документа, командой состояния или сверкой
источников. Исправь расхождения до финального ответа.
''',
    ),
    AgentPromptTemplateSpec(
      key: 'stage.recover',
      title: 'Восстановление после ошибок',
      description: 'Смена стратегии и обращение к пользователю.',
      defaultText: '''
Не повторяй безрезультатную попытку. После нескольких разных неудачных подходов
сохрани blocker, выполненные попытки и один конкретный вопрос пользователю о
факте или решении, без которого продолжение невозможно. Ответ пользователя
продолжает ту же задачу из сохраненной контрольной точки.
''',
    ),
    AgentPromptTemplateSpec(
      key: 'stage.handoff',
      title: 'Передача состояния при сжатии',
      description: 'Что должно пережить сжатие контекста.',
      defaultText: '''
CANONICAL_TASK_STATE является неизменяемой опорой между сжатиями контекста.
Не пересказывай его по памяти и не начинай задачу заново. Продолжай с первого
незавершенного шага, используя сохраненные команды, файлы, результаты и blocker.
''',
    ),
    AgentPromptTemplateSpec(
      key: 'stage.release',
      title: 'Сборка и выпуск программ',
      description: 'Стандарт результирующей папки release.',
      defaultText: '''
Для созданной программы после успешных тестов и сборки вызови
package_project_release. Результат хранится в release/{{program}}_{{version}} и
включает SHA256SUMS.txt, CHANGE_en.md, CHANGE_ru.md, README_en.md, README_ru.md,
source_{{version}}.zip и платформенные артефакты с версией, ОС и архитектурой в
имени. Не упаковывай непроверенную сборку и не вставляй TODO/заглушки в описания.
''',
    ),
    AgentPromptTemplateSpec(
      key: 'mode.automatic',
      title: 'Режим: автоматически',
      description: 'Маршрутизация смешанных задач.',
      defaultText: '''
Определи тип задачи до первого изменяющего действия. Допускай несколько доменов
одновременно и выбирай инструменты по фактической следующей подзадаче.
''',
    ),
    AgentPromptTemplateSpec(
      key: 'mode.software',
      title: 'Режим: программирование',
      description: 'Разработка, скрипты, сборка и тестирование.',
      defaultText: '''
Сначала изучи структуру и локальные соглашения проекта. Вноси связанные
изменения, используй фактическую диагностику компилятора, запускай тесты и
проверяй исполняемый артефакт. Ошибку окружения не маскируй переписыванием кода.
Поддерживай корректную структуру языка и заверши работу выпуском release.
''',
    ),
    AgentPromptTemplateSpec(
      key: 'mode.documents',
      title: 'Режим: документы',
      description: 'Документы, таблицы, презентации и диаграммы.',
      defaultText: '''
До изменения прочитай структуру документа, стили, таблицы, формулы, изображения
и координаты объектов. Сохраняй исходную компоновку при точечных правках. Для
создания передавай полный материал без многоточий и текстовых заменителей
изображений. После записи повторно разбери файл и проверь обязательные элементы.
''',
    ),
    AgentPromptTemplateSpec(
      key: 'mode.filesystem',
      title: 'Режим: файловая система',
      description: 'Поиск и операции с файлами устройства.',
      defaultText: '''
Работай только в разрешенной области. Для поиска используй индекс, имена и
содержимое, затем читай релевантные кандидаты. Сохраняй точные пути и результаты
операций. Не изменяй файлы, если пользователь просил только поиск или анализ.
''',
    ),
    AgentPromptTemplateSpec(
      key: 'mode.remote',
      title: 'Режим: удаленные системы',
      description: 'SSH, telnet, WSL, серверы и сетевые устройства.',
      defaultText: '''
Используй постоянные PTY-сессии для SSH, telnet, REPL и переходов через
промежуточные узлы. Для Linux на Windows сначала проверь wsl_list и открывай WSL
через terminal_open с backend=wsl. Не переподключай уже живую сессию. Сохраняй
идентификатор цели, команды и вывод, а полезную сессию оставляй пользователю.
''',
    ),
    AgentPromptTemplateSpec(
      key: 'mode.pentesting',
      title: 'Режим: пентестинг',
      description: 'Разрешенная проверка безопасности.',
      defaultText: '''
До активных действий зафиксируй явно разрешенный scope, целевые адреса и
ограничения. Используй постоянные PTY-сессии для nmap, msfconsole и удаленных
оболочек. Не выходи за scope, не скрывай команды и сохраняй доказательства,
ошибки, найденные риски и безопасные рекомендации по устранению.
''',
    ),
    AgentPromptTemplateSpec(
      key: 'question.blocked',
      title: 'Вопрос при блокировке',
      description: 'Формат минимального вопроса после нескольких неудач.',
      defaultText: '''
После нескольких подтвержденных неудач задай один короткий вопрос: назови
конкретный blocker, перечисли уже проверенные подходы одной строкой и спроси
только недостающий факт или выбор стратегии. Не предлагай переопределить задачу.
''',
    ),
  ];

  String value(String key) {
    final custom = _overrides[key];
    if (custom != null) return custom;
    return specs.firstWhere((item) => item.key == key).defaultText.trim();
  }

  void update(String key, String text) {
    if (!specs.any((item) => item.key == key)) {
      throw ArgumentError.value(key, 'key', 'Unknown prompt template');
    }
    _overrides[key] = text.trim();
  }

  void reset(String key) => _overrides.remove(key);

  void resetAll() => _overrides.clear();

  Map<String, String> toJson() => Map<String, String>.from(_overrides);

  factory AgentPromptLibrary.fromJson(Object? value) {
    if (value is! Map) return AgentPromptLibrary();
    final known = specs.map((item) => item.key).toSet();
    final overrides = <String, String>{};
    for (final entry in value.entries) {
      final key = entry.key.toString();
      if (!known.contains(key)) continue;
      overrides[key] = entry.value.toString();
    }
    return AgentPromptLibrary(overrides);
  }

  String render({
    required ProjectTaskMode mode,
    required String taskType,
    required String expectedResult,
    String program = 'program',
    String version = 'version',
  }) {
    final keys = <String>[
      'core.execution',
      'stage.classify',
      'stage.goal',
      'stage.decompose',
      'stage.execute',
      'stage.verify',
      'stage.recover',
      'stage.handoff',
      if (mode == ProjectTaskMode.software || mode == ProjectTaskMode.automatic)
        'stage.release',
      mode.promptKey,
      'question.blocked',
    ];
    final replacements = <String, String>{
      '{{task_mode}}': mode.label,
      '{{task_type}}': taskType,
      '{{expected_result}}': expectedResult,
      '{{program}}': program,
      '{{version}}': version,
    };
    String replace(String text) {
      var result = text;
      for (final entry in replacements.entries) {
        result = result.replaceAll(entry.key, entry.value);
      }
      return result.trim();
    }

    final buffer = StringBuffer('[EDITABLE_AGENT_PROMPTS]\n');
    for (final key in keys) {
      buffer
        ..writeln('\n[$key]')
        ..writeln(replace(value(key)))
        ..writeln('[/$key]');
    }
    buffer.writeln('[/EDITABLE_AGENT_PROMPTS]');
    return buffer.toString().trimRight();
  }
}
