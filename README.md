# AI Agent

> Version 1.59.1 separates explicit Stop requests from internal loop protection and always reports a structured task result when execution ends.

AI Agent is a cross-platform Flutter application for local and OpenAI-compatible models, projects, files, console sessions, office documents, and local tools.

## Version

Current version: `1.59.1+66`.

`pubspec.yaml` is the single version source. The release builder uses the semantic version before `+` in artifact names and the numeric suffix as the Android build number.

## Windows build environment

Flutter is expected at:

```text
N:\Codex\Compilers\flutter\bin\flutter.bat
```

The project is intended to be placed at `N:\Codex\AIAgent`.

## Build commands

```powershell
.\build.ps1 -Target All
```

BAT launchers:

- `build_all.bat`
- `build_windows.bat`
- `build_web.bat`
- `build_android.bat`
- `analyze.bat`
- `run_tests.bat`
- `diagnose_build_env.bat`

The complete release is written to:

```text
N:\Codex\AIAgent\dist\AIAgent_v.1.59.1\
  AIAgent_v.1.59.1_win.zip
  AIAgent_v.1.59.1_web.zip
  AIAgent_v.1.59.1_android.apk
```

The Web target uses a separate browser-safe entry point. Desktop modules that depend on `dart:io`, process execution, and Windows WebView are not compiled into the Web application.

## Agent capabilities in v1.59

- Multi-domain intent analysis keeps software, documents, mail, device search, web research, remote administration, and authorized security assessment in one task without replacing the user's prompt.
- The adaptive run budget extends while measurable progress continues. Checkpoints and the attempt journal retain successful steps, failed approaches, commands, and result signals across context compression and later tasks.
- The Console tab uses a real PTY and xterm-compatible renderer. Agent commands are mirrored into the first console; SSH, telnet, REPL, and msfconsole sessions can remain open for user handoff.
- Web extraction uses an HTML5 DOM parser to preserve headings, lists, tables, code, metadata, links, images, and JSON-LD while removing page chrome.
- Office tools parse and verify DOCX styles/tables/media, XLSX cells/formulas/layout, PPTX shape coordinates/notes, and VSDX pages/shapes/connectors. VSDX creation and structure-preserving text replacement are supported.
- Android stores project/config data in the application-support directory and initializes Flutter bindings before platform plugins.

Supported application targets are Windows x64, Android arm64/x64 (according to the Flutter build target), Web, and Linux when the Linux Flutter runner/toolchain is available.


## Reliability in v1.55

Agent runs are checkpointed under `.cppagent/runs` with the prompt, plan, iteration, tool counters, last action, and verification evidence. Interrupted runs can be resumed from the Chat tab. A tool execution circuit breaker stops identical calls without progress and repeated failures with the same arguments. Verified successful file-changing runs can be stored in local memory only after a passing `EXIT_CODE: 0` check.

The Settings dialog exposes checkpointing, loop protection, automatic verified-run learning, the current evidence report, and run history.


Reliability v1.55 resumes the same checkpointed run, restores evidence and loop protection, and redacts secrets from persistent state.

## Build failure handling

Build output is classified before edits are allowed. Source files can be changed only when the compiler names the file and line, and the file must be read first. Tool-provided `--help` diagnostics are run before configuration changes, one edit requires one rebuild, and the original failed build command is retried before switching strategy. See `docs/BUILD_DIAGNOSTICS_V1_56_RU.md`.

## Reliable build diagnostics

Version 1.57.0 separates source-code, CMake configuration, dependency, environment, and missing-artifact failures. Source files can only be edited after a compiler identifies a concrete file and line. A locally available missing header repairs the include path in `CMakeLists.txt`; CMake configuration alone is not treated as a successful build, and every repair requires an immediate rebuild. Trusted memory is created only from grounded verification after the latest failure.

Version 1.57.1 restores the required `lib/agent_core/build` source package that was accidentally omitted from the previous source archive. The build diagnostics controller, CMake resolver, direct C++ command builder, and tests are now shipped together.


### 1.57.2 fix

Fixed captured CMake build-directory replacement: the resolver no longer invokes `RegExpMatch.start/end` as functions and safely preserves commands, including build paths with spaces.

## Disk-space-safe release builds

Before each platform build, `build.ps1` checks free space on the project volume. If space is low, it removes only generated `build`, `.dart_tool/flutter_build`, and local Gradle/CMake caches. Completed artifacts in `dist` are preserved. Re-running the same version skips existing artifacts; use `-ForceRebuild` for a full rebuild. Android receives one cleanup-and-retry attempt when the volume becomes full during compilation.
