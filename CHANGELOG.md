# Changelog

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
