# v1.35 — исправление молчаливого завершения build_all.bat

Исправлена ошибка в `_flutter_env.bat`: в v1.34 был повреждён блок `for`, из-за чего `build_all.bat` доходил до этапа проверки Flutter и сразу возвращался в командную строку без понятной ошибки.

Изменения:

- полностью переписан `_flutter_env.bat`;
- добавлена корректная проверка portable Flutter в `tooling\flutter\flutter\bin\flutter.bat`;
- добавлен fallback на `flutter.bat`, `flutter.exe`, `flutter` из `PATH`;
- `build_all.bat` теперь печатает код возврата `_flutter_env.bat`;
- если переменные `FLUTTER` или `PROJECT_ROOT` не установлены, выводится явная ошибка;
- `diagnose_build_env.bat` обновлён и показывает подробную диагностику.

Проверка:

```bat
diagnose_build_env.bat
build_all.bat
```
