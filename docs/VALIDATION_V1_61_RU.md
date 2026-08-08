# Проверка AI Agent 1.61.0+68

Дата проверки: 6 августа 2026 года.

## Исходный код

- `flutter analyze --no-pub`: замечаний нет.
- `flutter test --no-pub --reporter compact`: 93 теста выполнены успешно, один нативный PTY-тест штатно пропущен вне собранного Windows runner.
- Строгим UTF-8 декодером проверены 183 отслеживаемых и новых текстовых файла: ошибок кодировки нет.
- `git diff --check`: ошибок пробелов и конфликтных маркеров нет.

Тесты версии 1.61 отдельно проверяют определение Flutter, Dart, Node.js, Python, CMake, Rust, Go, .NET, Maven, Gradle, Meson, Make, Zig, Swift, Ruby, PHP, C, C++ и Java проектов; пошаговое выполнение слабой моделью; запрет подмены успешной сборки диагностикой; поиск в текущем и других проектах; поиск в пользовательской литературе; повторное использование индекса; области типизированной памяти; ограниченный набор инструментов и учёт размера их JSON-схем в контекстном окне.

## Windows

Команда финальной сборки:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Target Windows -SkipChecks -ForceRebuild
```

Артефакт:

```text
dist/AIAgent_v.1.61.0/AIAgent_v.1.61.0_win.zip
```

Архив содержит 39 записей, включая `AIAgent.exe` и `documents/README_RU.txt`; ошибочного вложенного каталога `documents/documents` нет. Приложение запущено с рабочим каталогом вне папки бинарника: через восемь секунд процесс оставался активным и отвечающим. Библиотека `documents` корректно определилась рядом с исполняемым файлом.

## Android

Команда финальной сборки:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Target Android -SkipChecks -ForceRebuild
```

Артефакт:

```text
dist/AIAgent_v.1.61.0/AIAgent_v.1.61.0_android.apk
```

Проверка через Android SDK `aapt2` и содержимое APK:

- package: `com.example.ii_agent`;
- versionName: `1.61.0`;
- versionCode: `68`;
- minSdk: `24`;
- targetSdk: `36`;
- ABI: `arm64-v8a`, `armeabi-v7a`, `x86_64`.

`adb devices -l` не обнаружил подключённого Android-устройства, поэтому запуск этого APK на физическом устройстве в рамках проверки невозможен. Сборка, манифест и нативные ABI проверены.

## SHA-256

```text
2AAFE0E9634D3F7D16C6FFEF47E0D84F2C6D5DA9421311F82262C1296A9D4636  AIAgent_v.1.61.0_win.zip
12B0A0A2895B49EFF41DA4D58E74FBE5519152D24BC1B9F7614506D08256134C  AIAgent_v.1.61.0_android.apk
```
