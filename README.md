# AIAgent

AIAgent is a Flutter desktop/mobile shell for a local AI coding and document agent. It manages projects, model profiles, console and web sessions, file editing, office-document tools, automation settings, and local `llama.cpp` execution.

## Platforms

- Windows: supported and built as `AIAgent.exe`.
- Android: supported and built as release APK.
- Linux: runner source is present and configured as `AIAgent`; release builds must be produced on a Linux host because Flutter does not support `flutter build linux` from Windows.

## Latest Version

Version: `1.52.0+52`

New in this version:

- CUDA local profiles now resolve to the matching installed `tools/llama.cpp/<os_arch>/cuda12` or `cuda13` backend and refuse to start from an incompatible CPU folder.
- The local llama status line shows RAM and, when NVIDIA tooling is available, per-process VRAM usage so GPU offload is visible during model startup and inference.
- Android startup was fixed by aligning the runner package with the app manifest.

Previous 1.51 highlights:

- Reworked `llama.cpp` layout to `tools/llama.cpp/<os_arch>/<backend>` and added strict release-asset matching for Windows/Linux/Android CPU, Vulkan, CUDA 12/13, ROCm, OpenVINO, SYCL, HIP, and OpenCL Adreno variants.
- `llama.cpp` install now reuses matching archives from `tools/downloads` when GitHub is unavailable and only shows installed local backends when creating local profiles.
- Added draggable heavy-task status overlay for model startup/download/install and token-limit pauses.
- Added local `llama-server` restart button in Chat, process-tree shutdown on Windows, periodic process/API health checks, and optional auto-restore per app/profile.
- Model profiles now store API style, runtime-only auto-detected remote limits, token-limit pause duration, and context-menu actions for availability check/edit/delete.
- Project schedules now save time for one-time runs and structured parameters for yearly/monthly/weekly/daily/hourly/minutely repeats, with a lightweight scheduler executing due prompts.
- Office document generation now blocks placeholder content, writes XLSX formulas as formulas, converts markdown tables into real DOCX/XLSX tables, and embeds local markdown images into DOCX.

Previous 1.50 highlights:

- Added native WebView browsing in the Web tab: Windows uses WebView2 and Android uses the platform WebView, with the previous text/source renderer kept as fallback.
- Replaced raw JSON automation editing paths with separate UI dialogs for API output templates, device indexing, global triggers, project schedules, scheduled run history, and custom agent tools.
- Project schedules are edited per project and can select existing triggers, create new triggers, attach files/folders, choose permissions, profile/model, email/API reports, and an output-formatting prompt.
- Added a direct setting for "close without minimizing to tray" and kept the tray bridge lifecycle synchronized with it.
- Compact chat controls now render "Rights" as an icon-only control on narrow windows.
- Added Linux desktop runner sources configured with the `AIAgent` executable name.
- Fixed `llama.cpp` CPU startup arguments: CPU profiles use `--n-gpu-layers 0`, and `--flash-attn` is passed with an explicit value.
- Added local llama lifecycle handling: local profiles start/keep the server, remote profiles stop it, and app shutdown stops it.
- Moved default llama downloads to `tools/downloads`.
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
- `build_windows.bat` with `SKIP_CHECKS=1` - passed, copied `dist/AIAgent_v1.52_windows_x64`.
- `flutter build apk --release` - passed, produced `build/app/outputs/flutter-apk/app-release.apk`.
- `build_android.bat` with `SKIP_CHECKS=1` - passed, copied `dist/AIAgent_v1.52_android_universal.apk`.
- `flutter build linux --release` - blocked on Windows host by Flutter platform rule; build it on Linux.
