# Проверка AI Agent 1.60.0+67

Дата проверки: 31 июля 2026 года.

## Исходный код

- `flutter analyze`: замечаний нет.
- `flutter test --reporter compact`: 81 тест выполнен успешно.
- Один тест нативной PTY штатно пропущен в `flutter test` на Windows, потому что тестовый процесс не поставляет `flutter_pty.dll`. Библиотека присутствует в релизном ZIP, а запуск собранного приложения проверен отдельно.
- Все 32 измененных текстовых файла прочитаны строгим UTF-8 декодером без ошибок.
- `git diff --check`: ошибок пробелов и конфликтных маркеров нет.

Новые тесты проверяют режимы проектов, рекурсивные цели, точное восстановление `handoff.md`, редактируемые промты, WSL, отдельное состояние ожидания ответа пользователя, уникальность описаний инструментов и выпускные пакеты с SHA-256.

## WSL

Фактический запуск команды выполнен в установленном Debian/WSL 2 с рабочим каталогом `/mnt/n/Codex/AIAgent`. Обнаружение дистрибутива, преобразование пути и выполнение команды завершились успешно. В данном дистрибутиве нет Flutter SDK, поэтому Linux runner не собирался.

## Windows

Команда:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Target Windows -SkipChecks -ForceRebuild
```

Результат: собран `AIAgent.exe`, создан архив:

```text
dist/AIAgent_v.1.60.0/AIAgent_v.1.60.0_win.zip
```

Архив содержит 35 файлов, включая `AIAgent.exe`, `flutter_windows.dll`, `flutter_pty.dll` и Flutter assets. После распаковки выполнен smoke-test: процесс оставался активным и отвечающим в течение восьми секунд, затем был завершен без оставшихся дочерних процессов.

## Android

Команда:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Target Android -SkipChecks
```

Результат:

```text
dist/AIAgent_v.1.60.0/AIAgent_v.1.60.0_android.apk
```

Проверка через Android SDK `aapt2`:

- package: `com.example.ii_agent`;
- versionName: `1.60.0`;
- versionCode: `67`;
- minSdk: `24`;
- targetSdk: `36`;
- ABI: `armeabi-v7a`, `arm64-v8a`, `x86_64`.

## SHA-256

```text
968845EDEE5F992ED8A26A7626A7BE6DC7903A05B953D0619DE8A65CD88C6E65  AIAgent_v.1.60.0_win.zip
C808222FB19981534DAC76F4948D7ECF284FB1B0D6C9F8A58A48560D0DB9C65C  AIAgent_v.1.60.0_android.apk
```
