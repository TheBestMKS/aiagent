# AIAgent

AIAgent is a Flutter desktop/mobile shell for a local AI coding and document agent. It manages projects, model profiles, console and web sessions, file editing, office-document tools, automation settings, and local `llama.cpp` execution.

## Platforms

- Windows: supported and built as `AIAgent.exe`.
- Android: supported and built as release APK.
- Linux: source is present, but release builds must be produced on a Linux host because Flutter does not support `flutter build linux` from Windows.

## Latest Version

Version: `1.49.0+49`

New in this version:

- Fixed `llama.cpp` CPU startup arguments: CPU profiles use `--n-gpu-layers 0`, and `--flash-attn` is passed with an explicit value.
- Added local llama lifecycle handling: local profiles start/keep the server, remote profiles stop it, and app shutdown stops it.
- Moved default llama layout to `tools/llama.cpp/<cpu|vulkan|cuda>` and downloads to `tools/downloads`.
- Added install from archive and manual folder creation for llama.cpp.
- Added native Windows tray restore/context menu behavior and `AIAgent.exe` naming.
- Reworked Console and Web tabs with persistent per-project tabs and quick actions.
- Reworked Files tab context menus and editor scrolling.
- Added office document parsing/build/edit libraries and document/spreadsheet view engines.
- Added automation storage and UI for API output templates, triggers, schedules, indexing locations, custom tools, OCR, and scheduled task run records.
- Added device indexing tool, OCR tool hook, and custom-tool execution hook for the agent.

## Run

```powershell
tooling\flutter\flutter\bin\flutter.bat run -d windows
```

## Build

```powershell
tooling\flutter\flutter\bin\flutter.bat build windows --release
tooling\flutter\flutter\bin\flutter.bat build apk --release
```

Linux builds must be run on Linux:

```bash
flutter build linux --release
```

## Project Layout

- `lib/controllers/agent_controller.dart` - main agent runtime, tools, model profiles, llama lifecycle, settings.
- `lib/tabs/` - Chat, Files, Console, Web UI.
- `lib/dialogs/` - settings, model, automation, file picker dialogs.
- `lib/document_tools/` - office document parsing/build/edit/view libraries.
- `tools/` - portable tools, downloads, llama.cpp backends, models, isolated user utilities.
- `Projects/` - user projects.

## Verification

Latest local verification on Windows:

- `flutter analyze` - passed.
- `flutter test` - passed.
- `flutter build windows --release` - passed, produced `build/windows/x64/runner/Release/AIAgent.exe`.
- `flutter build apk --release` - passed, produced `build/app/outputs/flutter-apk/app-release.apk`.
- `flutter build linux --release` - blocked on Windows host by Flutter platform rule.
