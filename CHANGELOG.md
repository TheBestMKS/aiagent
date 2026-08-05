## 1.59.1+66 - 2026-07-19

- Fixed an internal repetition/circuit-breaker stop being reported as "stopped by user" even when the Stop button was never pressed.
- Added distinct typed termination causes for explicit user cancellation and internal safety guards.
- Added the terminal and resumable `stalled` checkpoint status for runs stopped by loop protection.
- Changed the agent loop to return an explicit result status and reason instead of inferring the outcome from a shared cancellation flag.
- Added a mandatory final "Результат выполнения задачи" message for completed, failed, paused, safety-stopped, and user-cancelled runs, including file/command counters and the last captured result.
- Added regression coverage for the repeated-model-response sequence from the application log, safety-stop classification, result formatting, and stalled-run recovery.

## 1.59.0+65 - 2026-07-18

- Replaced single-label task classification with multi-domain intent analysis and a hidden execution frame that never rewrites the user's prompt.
- Replaced the fixed agent loop with an adaptive progress budget and added automatic per-project attempt memory for successful and failed actions.
- Added a shared native PTY/xterm console with persistent project transcripts and agent command mirroring; interactive SSH, telnet, REPL and msfconsole sessions remain available to the user.
- Replaced regex-only page extraction with HTML5 DOM parsing, semantic main-content selection, structured tables/lists/code, metadata, image/link extraction and JSON-LD.
- Added layout-aware parsing for DOCX paragraphs/styles/tables/media, XLSX cells/formulas/columns/merges, PPTX shapes/coordinates/notes, and VSDX pages/shapes/connections.
- Added VSDX document creation and structure-preserving text replacement.
- Added post-write document verification and rejection of placeholder content, missing requested Markdown tables, and unresolved image references.
- Moved Android application data to the persistent application-support directory and initialized Flutter bindings before platform plugins.
- Added regression tests for task routing, attempt memory, adaptive execution, semantic web extraction, terminal history, and rich Office/VSDX structure.
- Fixed `-ForceRebuild` so rebuilding one platform replaces only that artifact and no longer deletes completed artifacts for other platforms in the same version folder.
- Disabled Kotlin incremental compilation for Android builds on cross-drive workspaces, avoiding noisy cache failures when Pub is on `C:` and the project is on `N:`.

## 1.58.1+64 - 2026-07-12

- Добавлена предварительная проверка свободного места перед Windows, Web и Android-сборками.
- При нехватке места сборщик удаляет только генерируемые `build`, `.dart_tool/flutter_build` и локальные Gradle/CMake-кеши; каталог `dist` и пользовательские файлы сохраняются.
- Android-сборка при заполнении диска выполняет одну безопасную очистку и одну повторную попытку.
- Уже созданные артефакты Windows/Web/Android сохраняются после частичного сбоя и пропускаются при повторном запуске той же версии; для принудительной пересборки добавлен `-ForceRebuild`.
- `build.ps1 -Target Clean` больше не удаляет релизные артефакты без явного `-ForceRebuild`.
- Ошибка `No space left on device` / `errno = 112` классифицируется агентом как проблема окружения с запретом редактирования исходников.
- Убраны замечания `unnecessary_non_null_assertion` и `prefer_const_constructors`.
- Добавлена зависимость `cupertino_icons`, чтобы Web-сборка включала используемый шрифт CupertinoIcons.

## 1.57.2+62 - 2026-07-12

- Исправлена ошибка Dart-анализатора в `CMakeCommandResolver`: захваченная группа регулярного выражения больше не обрабатывается как вызов `match.start(2)`/`match.end(2)`.
- Замена каталога после `cmake --build` теперь вычисляет точный диапазон аргумента внутри полного совпадения и сохраняет остальную команду без изменений.
- Добавлен регрессионный тест для найденного каталога сборки с пробелом в имени.

## 1.57.1+61 - 2026-07-12

- Restored the three source modules under `lib/agent_core/build/` that were accidentally omitted from the 1.57.0 distribution because a source directory named `build` was mistaken for generated build output.
- Restored `BuildFailureAnalysis` recovery/dependency fields, `CMakeCommandResolver`, and `CppBuildCommandBuilder` used by the controller and regression tests.
- Synchronized the fallback application version with `pubspec.yaml`.
- Added distribution validation to require the agent-core build diagnostics modules before creating release source archives.

## 1.57.0+60 - 2026-07-12

- Исправлена логика диагностики CMake: `cmake --build .` без `CMakeCache.txt` автоматически переводится на `cmake -S . -B build` и сборку каталога `build`.
- Успешная конфигурация CMake больше не считается тестом или окончательной проверкой; `run_tests` автоматически продолжает реальной сборкой.
- Ошибка локального заголовка (`fatal error: X.h: No such file or directory`) классифицируется как ошибка include-path, если файл найден в проекте. Исходники блокируются от изменений, а существующий `CMakeLists.txt` дополняется `target_include_directories` без смены цели и переписывания проекта.
- Автогенерация CMake учитывает все C/C++ исходники и каталоги заголовков, а не только один файл.
- Заявление модели о якобы успешной проверке больше не может создать доверенный golden path: используются только фактические доказательства из журнала команд после последней ошибки.
- Повторная запись идентичного плана не считается прогрессом.
- Заблокированные circuit breaker вызовы учитываются как отсутствие прогресса; после трёх последовательных блокировок запуск останавливается.
- Состояние диагностики зависимостей и команды восстановления сохраняется в checkpoint.
- Добавлены регрессионные тесты CMake cache, include-path, классификации проверок, аннулирования старой проверки и защиты от циклов.

## 1.56.1+59 - 2026-07-12

- Fixed the Windows direct C++ command regression test: Windows paths are now represented as Dart raw strings, so `\` is preserved instead of being consumed by string escaping.
- Strengthened the test by naming the safe parenthesized command fragment and the unsafe conditional chain separately.
- No runtime build-diagnostics logic changed; the generated command in 1.56.0 was already correct.

## 1.56.0+58 - 2026-07-12

- Added deterministic build-failure classification for source compilation, linker, CMake/configuration, tool usage, dependency, environment and missing-artifact failures.
- Source edits are now blocked after non-source build failures; compiler-reported source failures require reading the implicated file and the exact reported line range before one minimal edit.
- Added automatic execution of safe `--help` diagnostics when build tools explicitly recommend them.
- Added one-edit/one-rebuild enforcement: after an allowed source/configuration edit, the very next tool action must retry the original build command before any status check or alternative action.
- Fixed Windows direct C++ command chaining so `cmd.exe` cannot skip `g++.exe` when a preceding `if` condition is false.
- Fixed successful-exit detection so `PROCESS_EXIT_CODE: 0` cannot hide an effective `EXIT_CODE` failure such as `BUILD_ARTIFACT_MISSING`.
- Limited consecutive `get_task_status` calls to one and excluded passive status output from progress detection.
- Added guarded delete/copy/move operations for source and build-configuration files after build failures.
- Persisted build diagnosis, required retry command, completed diagnostics and file-read evidence in schema-v3 task checkpoints.
- Added regression tests based on the reported CMake/C++ failure sequence.
- Added `docs/BUILD_DIAGNOSTICS_V1_56_RU.md` and `docs/VALIDATION_V1_56_RU.md`.

## 1.55.2+57

- Fixed duplicate `toolResultLooksSuccessful` definition in `AgentController`.
- Fixed missing import for the `AgentRunStatus.label` extension in the reliability status bar.
- Applied `const` constructors in the Web application header.
- Restored a clean `flutter analyze` path after the 1.55 reliability update.

# Changelog

## 1.55.0+55 - 2026-07-12

- Added durable per-project task checkpoints under `.cppagent/runs`, including prompt, plan, iteration, counters, last tool result, error details and verification evidence.
- Added interrupted-run recovery in Chat with explicit Continue and Dismiss actions; terminal runs are archived into a bounded local history.
- Recovery now resumes the same run from the next remaining iteration and restores counters, the last command status, typed evidence and circuit-breaker state instead of restarting the task from zero.
- Upgraded checkpoints to schema v2 with serialized evidence and hashed loop-protection signatures; oversized, malformed or foreign-project checkpoint files are quarantined locally.
- Added a task execution history dialog and compact live reliability status showing iteration, evidence count and circuit-breaker blocks.
- Added a deterministic tool execution circuit breaker that stops identical calls without progress and repeated failures with unchanged arguments.
- Added global stall detection across alternating tool calls; repeated actions with no new result or state change are stopped even when their tool names differ.
- Added a centralized completion gate that reports missing mutation, verification, research or error-resolution evidence before the agent can claim completion.
- Added a typed task evidence ledger for plans, file mutations, commands, tests, research, permissions and failures.
- Added the read-only `get_task_status` tool so the model can inspect its plan, evidence and loop-protection state before choosing a new strategy.
- Added optional automatic learning from verified runs. A run is stored in local typed memory only after a successful file mutation and a real passing check with `EXIT_CODE: 0`.
- Added application settings for checkpointing, loop protection and verified-run learning.
- Added unit tests for checkpoint recovery/history, restored circuit-breaker state, structured secret redaction and evidence-based verification.
- Restricted successful `run_command` verification evidence to real build, test, analysis or compiler commands; a generic successful command such as `echo` no longer proves task completion.
- Applied shared secret redaction to persistent sessions (including synchronous context markers), task plans, text logs, JSONL action logs, command-output logs, complete checkpoint serialization and nested tool arguments.
- Improved interrupted-task and history dialogs for narrow windows and mobile layouts; the live status now includes completion state and evidence confidence.
- Added project-scoped history cleanup without deleting the active checkpoint.
- Fixed stale final-answer quality errors so a corrected later response can complete the task instead of inheriting an earlier rejection forever.
- Fixed persistence of logging, quality-check and maximum-iteration settings; the iteration limit is now validated to the range 1–1000.
- Split the new reliability functionality into focused `agent_core/runs`, `agent_core/safety`, `agent_core/verification` and reusable widget modules instead of expanding the controller with new subsystems.

## 1.54.0+54 - 2026-07-12

- Added a GitHub-backed plugin manager with 11 isolated adapters, per-plugin enable/disable state, SHA-based update checks, selectable startup update prompts and optional unattended background updates.
- Added compact plugin update status in the main window and full plugin controls in application settings; ZIP verification/extraction runs outside the UI isolate.
- Plugin source updates now use staging, ZIP path-traversal and size-limit validation, manifest validation, atomic activation and rollback backups on desktop and Android.
- Added local typed/versioned memory with provenance, confidence, verification metadata, conflict history and secret redaction.
- Added verified golden-path promotion: a reusable procedure requires a passing check and at least one ruled-out failed approach.
- Added offline hybrid retrieval combining exact matching, BM25-style ranking and character similarity, plus section-aware chunking and cached local plugin-document indexes.
- Added deterministic tool-output compaction that keeps full logs while reducing context consumption.
- Added dynamic agent tool definitions for enabled plugins and local memory operations.
- Kept network search, public API/provider catalogs, optional external memory and OSINT behind plugins and existing permission gates.
- Integrated only safe harness lessons from T3MP3ST; offensive-security execution was not included.
- Added a per-repository integration report and made plugin source plus manifest activation rollback-safe as one update transaction.

## 1.53.0+53 - 2026-07-12

- Replaced duplicated release scripts with one PowerShell build engine and small BAT launchers.
- Release version and Android build number are read from `pubspec.yaml`; hard-coded `v1.52` values were removed.
- Added Windows, Web and Android packaging into `dist/AIAgent_v.<version>` with deterministic artifact names.
- Added a Web-safe application entry point so the browser build no longer compiles desktop `dart:io` and Windows WebView modules.
- Added a responsive browser shell for connection configuration and platform capability guidance.
- Added automatic generation and patching of Windows, Web and Android runner files from the Flutter SDK at `N:\Codex\Compilers\flutter`.
- Removed obsolete environment/manifest patch scripts, generated IDE/plugin files and empty directories.
- Removed empty legacy `tools/llama.cpp/cpu`, `cuda` and `vulkan` placeholders; the current OS/architecture backend layout is created on demand.
- Rebuilt the Windows ICO as a valid optimized multi-resolution icon and connected the shared icon source to generated Windows, Web and Android runners.
- Application version shown in the UI and user-agent strings is now supplied by the release builder through `--dart-define`.

## 1.52.0+52 - 2026-06-30

- Fixed local CUDA `llama.cpp` launch profile resolution so CUDA backends cannot silently start from a CPU folder; legacy `cuda` profiles are normalized to an installed CUDA 13 or CUDA 12 backend when available.
- Added backend compatibility checks before local llama startup and clearer logs/status when a selected GPU backend is missing or incompatible.
- Added best-effort NVIDIA VRAM reporting for the running `llama-server` process in the model status line, next to RAM usage.
- Fixed the Android runner package so the manifest resolves `local.ai.agent.MainActivity` correctly instead of closing immediately on startup.

## 1.51.0+51 - 2026-06-28

- Reworked `llama.cpp` backend folders to `tools/llama.cpp/<os_arch>/<backend>` and added the full requested Windows/Linux/Android variant matrix.
- Fixed release-asset selection so Windows x64 cannot accidentally install arm64 archives; installer now falls back to `tools/downloads` when online release lookup/download is unavailable.
- Local model profiles now list only installed `llama-server` backends, keep per-profile auto-restart settings, and support an icon-only restart button in Chat.
- Added draggable heavy-task status overlay for model startup/install and token-limit wait timers.
- Added process-tree shutdown for local llama on Windows, app-shutdown cleanup, periodic process/API health checks, and optional automatic restore.
- Added API style, runtime-only remote limit probing, token-limit pause duration, and profile context actions for check/edit/delete.
- Expanded schedule editor with one-time time selection and structured yearly/monthly/weekly/daily/hourly/minutely parameters; added a lightweight due scheduler for project prompts.
- Improved office document generation: placeholder output is blocked, markdown tables become real DOCX/XLSX tables, XLSX formulas are written as formulas, and DOCX can embed local markdown image references.

## 1.50.0+50 - 2026-06-28

- Added native WebView browsing for Windows WebView2 and Android platform WebView, with text/source fallback preserved.
- Split automation settings into user-friendly dialogs for API output, indexing, global triggers, custom tools, project schedules, and scheduled task run history.
- Reworked project schedule editing around forms, checkboxes, trigger selection/creation, attachments, extra folders, permissions, profile selection, email/API reports, and output formatting prompts.
- Added the explicit "close without minimizing to tray" setting while preserving tray restore/context-menu behavior.
- Fixed compact chat permissions control so it becomes icon-only on narrow windows.
- Kept generated Console/Web quick actions and project-scoped session state compatible with the new UI.
- Added Linux desktop runner sources configured with `AIAgent` as the executable/window name.
- Disabled Kotlin incremental compilation for Android release builds to avoid cross-drive cache path failures.

## 1.49.0+49 - 2026-06-27

- Fixed local `llama.cpp` launch arguments for CPU and current `--flash-attn` syntax.
- Added llama process lifecycle management for local vs remote profiles and app shutdown.
- Added optional separate llama stdout/stderr logs.
- Switched default llama folders from `tooling` to `tools`, with `tools/downloads` and manual backend folders.
- Added llama install from downloaded archive.
- Added Windows tray left-click restore and right-click menu with restore/exit.
- Renamed Windows executable/resource metadata to `AIAgent`.
- Added project-scoped persistent Console/Web sessions and quick actions.
- Added console quick action editing, script commands, program insertion, and faster command execution path reuse.
- Added browser-like Web tab state, quick URL actions, and external browser fallback.
- Removed visible left-panel hide control and compacted chat actions on narrow windows.
- Changed Shift+Enter to send the prompt.
- Reworked Files tab operations into context menus and fixed editor scrolling for long lines.
- Added DOCX/XLSX/PPTX/ODT/ODS/ODP/ODC/RTF parsing/build/edit libraries and view-engine files.
- Added automation settings for API outputs, triggers, schedules, indexing locations, custom tools, OCR hook, and scheduled run records.
- Added agent tools: `rebuild_device_index`, `search_device_index`, `recognize_image_text`, `run_custom_tool`.
- Updated README and build verification notes.
