# AI Agent v1.46 — исправление импорта AgentPermissionRequest

Версия исправляет ошибку сборки после перехода на настоящие Dart-модули.

## Исправлено

- `AgentPermissionRequest` подключён в `lib/app/ai_agent_app.dart` через `lib/core/runtime_types.dart`.
- Модульная структура сохранена: `part`/`part of` не возвращались.
- `main.dart` остаётся короткой точкой входа.

## Причина ошибки

После разделения монолитного файла на отдельные библиотеки Dart тип `AgentPermissionRequest` остался в `core/runtime_types.dart`, но `ai_agent_app.dart` его не импортировал.
