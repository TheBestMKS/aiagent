# Changelog

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
