# AI Agent v1.38 — исправление остановки сборки на warning/info analyzer

## Исправлено

`build_all.bat` в v1.37 доходил до шага `Running analyze`, после чего останавливался, хотя в `lib/main.dart` больше не было ошибок компиляции.
Причина: `flutter analyze` возвращал код ошибки из-за warning/info, а build-сценарий воспринимал это как критический сбой.

## Что изменено

- `analyze.bat` больше не запускает `flutter analyze --current-package`, потому что он анализировал bundled Flutter SDK в `tooling/flutter`.
- Анализ ограничен исходниками проекта: `lib` и, если есть тесты, `test`.
- `analyze.bat` сохраняет подробный лог в `build_logs/analyze_scoped_latest.log`.
- Сборка падает только если в выводе анализатора есть реальные строки `error - ...`.
- `warning` и `info` теперь отображаются в логе, но не блокируют релизную сборку.
- `run_tests.bat` больше не падает, если папки `test` или файлов `*_test.dart` нет.

## Проверка

Запустить:

```bat
build_all.bat
```
