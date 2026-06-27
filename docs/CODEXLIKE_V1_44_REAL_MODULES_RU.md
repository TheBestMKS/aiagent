# AI Agent v1.46 — настоящее разделение main.dart на модули

В v1.43 файл был разрезан через `part/part of`, что фактически оставляло одну библиотеку Dart.
В v1.46 код переведён на реальные Dart-модули с обычными `import`, без `part`.

Основная структура:

- `lib/main.dart` — только точка входа.
- `lib/app/ai_agent_app.dart` — оболочка приложения и главный экран.
- `lib/tabs/chat_tab.dart` — вкладка чата.
- `lib/tabs/files_tab.dart` — вкладка файлов и редактор.
- `lib/tabs/console_tab.dart` — консоль.
- `lib/tabs/web_tab.dart` — Web-вкладка.
- `lib/dialogs/settings_dialogs.dart` — настройки и диалоги.
- `lib/controllers/agent_controller.dart` — контроллер агента.
- `lib/core/models.dart` — модели данных.
- `lib/core/runtime_types.dart` — служебные runtime-типы.
- `lib/rendering/message_rendering.dart` — рендер Markdown, таблиц, ссылок и блоков кода.
- `lib/utils/*.dart` — пути, форматирование, HTML и обработка вывода процессов.

Цель: уменьшить риск ошибок при изменениях и убрать монолитный `main.dart`.
