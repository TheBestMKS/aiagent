# AI Agent v1.37 — исправление вызова flutter.bat из build-скриптов

Исправлена ошибка, из-за которой `build_all.bat` доходил до шага `Flutter version` и сразу возвращался в командную строку.

Причина: в Windows, если из одного `.bat` запустить другой `.bat` без команды `call`, текущий сценарий прекращает выполнение. Portable Flutter запускается через `flutter.bat`, поэтому все вызовы `%FLUTTER%` теперь выполняются через `call "%FLUTTER%" ...`.

Исправлены файлы:

- `build_all.bat`
- `build_windows.bat`
- `build_android.bat`
- `analyze.bat`
- `run_tests.bat`
- `diagnose_build_env.bat`

Версия обновлена до v1.37.
