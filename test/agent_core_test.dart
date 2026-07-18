import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_agent/agent_core/context/tool_output_compactor.dart';
import 'package:ii_agent/agent_core/dependencies/cpp_dependency_preflight.dart';
import 'package:ii_agent/agent_core/build/build_failure_analyzer.dart';
import 'package:ii_agent/agent_core/build/build_working_directory_resolver.dart';
import 'package:ii_agent/agent_core/build/cpp_build_command_builder.dart';
import 'package:ii_agent/agent_core/build/cmake_command_resolver.dart';
import 'package:ii_agent/agent_core/memory/local_memory_service.dart';
import 'package:ii_agent/agent_core/retrieval/hybrid_retrieval.dart';
import 'package:ii_agent/agent_core/runs/adaptive_agent_budget.dart';
import 'package:ii_agent/agent_core/runs/agent_run_checkpoint.dart';
import 'package:ii_agent/agent_core/runs/agent_run_checkpoint_store.dart';
import 'package:ii_agent/agent_core/safety/tool_call_contract.dart';
import 'package:ii_agent/agent_core/safety/tool_call_json_repair.dart';
import 'package:ii_agent/agent_core/safety/tool_execution_guard.dart';
import 'package:ii_agent/agent_core/safety/unsupported_success_claim_guard.dart';
import 'package:ii_agent/agent_core/security/secret_redactor.dart';
import 'package:ii_agent/agent_core/terminal/interactive_terminal_service.dart';
import 'package:ii_agent/agent_core/verification/task_completion_gate.dart';
import 'package:ii_agent/agent_core/verification/task_evidence_ledger.dart';
import 'package:ii_agent/agent_core/verification/verification_command_classifier.dart';
import 'package:ii_agent/plugins/plugin_catalog.dart';
import 'package:ii_agent/plugins/plugin_manager.dart';
import 'package:ii_agent/controllers/agent_controller.dart';
import 'package:ii_agent/core/models.dart';
import 'package:ii_agent/utils/path_utils.dart';

void main() {
  test(
      'build failure analyzer distinguishes CMake configuration from source code',
      () {
    const analyzer = BuildFailureAnalyzer();
    final analysis = analyzer.analyze(
      command: 'cmake -B build && cmake --build build --config Release',
      output: '''EXIT_CODE: 1
PROCESS_EXIT_CODE: 1
[STDERR]
CMake Error: The source directory "N:/Project" does not appear to contain CMakeLists.txt.
Specify --help for usage, or press the help button on the CMake GUI.
[/STDERR]''',
    );
    expect(analysis.kind, BuildFailureKind.buildConfiguration);
    expect(analysis.sourceMutationAllowed, isFalse);
    expect(analysis.suggestedDiagnosticCommand, 'cmake --help');
  });

  test('build failure analyzer allows source edit only for an implicated file',
      () {
    const analyzer = BuildFailureAnalyzer();
    final analysis = analyzer.analyze(
      command: 'g++ src/main.cpp -o build/app.exe',
      output: '''EXIT_CODE: 1
src/main.cpp:42:7: error: expected semicolon before return
''',
    );
    expect(analysis.kind, BuildFailureKind.sourceCompile);
    expect(analysis.implicatedFiles, contains('src/main.cpp'));
    expect(analysis.implicatedLines['src/main.cpp'], 42);
    expect(analysis.sourceMutationAllowed, isTrue);
  });

  test('artifact failure is not mistaken for success from process exit code',
      () {
    const analyzer = BuildFailureAnalyzer();
    final analysis = analyzer.analyze(
      command: 'g++ src/main.cpp -o build/app.exe',
      output: '''EXIT_CODE: 2
PROCESS_EXIT_CODE: 0
BUILD_ARTIFACT_MISSING: build/app.exe
''',
    );
    expect(analysis.kind, BuildFailureKind.artifact);
  });

  test('disk exhaustion is an environment failure and blocks source edits', () {
    const analyzer = BuildFailureAnalyzer();
    final analysis = analyzer.analyze(
      command: 'flutter build apk --release',
      output:
          '''FileSystemException: writeFrom failed, path = 'N:/Project/.dart_tool/flutter_build/app.dill'
OS Error: Недостаточно места на диске, errno = 112
EXIT_CODE: 1''',
    );
    expect(analysis.kind, BuildFailureKind.environment);
    expect(analysis.sourceMutationAllowed, isFalse);
    expect(analysis.recommendedAction, contains('Не изменяй исходники'));
    expect(analysis.recommendedAction, contains('повтори ту же команду'));
  });

  test('release builder preserves partial artifacts and checks disk space', () {
    final script = File('build.ps1').readAsStringSync();
    expect(script, contains('Ensure-BuildDiskSpace'));
    expect(script, contains('Remove-GeneratedBuildData'));
    expect(script, contains('Completed artifacts were preserved'));
    expect(script, contains('Use -ForceRebuild'));
    expect(script, contains('MinimumAndroidFreeSpaceGB'));
    expect(script, contains(r'$ResetRelease = $false'));
    expect(script, contains('replace only their own artifact'));
    expect(script, contains('Release artifacts were preserved'));
  });

  test('Windows direct C++ command isolates conditional preparation', () {
    final command = CppBuildCommandBuilder.windowsDirect(
      compiler: 'g++.exe',
      sourceArgs: r'src\main.cpp',
    );
    const safeDeleteAndCompile =
        r'(if exist build\app.exe del /q build\app.exe) & g++.exe';
    const unsafeConditionalChain =
        r'if exist build\app.exe del /q build\app.exe & g++.exe';

    expect(command, startsWith('(if not exist build mkdir build) & '));
    expect(command, contains(safeDeleteAndCompile));
    expect(command, isNot(contains(unsafeConditionalChain)));
  });

  test('controller does not treat PROCESS_EXIT_CODE as successful build', () {
    final controller = AgentController();
    expect(
      controller.commandOutputHasSuccessfulExit(
        'EXIT_CODE: 2\nPROCESS_EXIT_CODE: 0\nBUILD_ARTIFACT_MISSING',
      ),
      isFalse,
    );
    expect(
      controller.commandOutputHasSuccessfulExit(
        'EXIT_CODE: 0\nPROCESS_EXIT_CODE: 0',
      ),
      isTrue,
    );
  });

  test('configuration failure blocks unrelated source edits', () {
    final controller = AgentController()
      ..lastBuildFailureAnalysis = const BuildFailureAnalysis(
        kind: BuildFailureKind.buildConfiguration,
        summary: 'missing CMakeLists.txt',
        suggestedDiagnosticCommand: 'cmake --help',
      )
      ..buildRetryRequired = true
      ..buildFailureRevision = 1;
    final reason = controller.buildFailureMutationBlockReason(
      'src/main.cpp',
      fileExists: true,
    );
    expect(reason, contains('SOURCE_EDIT_BLOCKED_AFTER_BUILD_FAILURE'));
  });

  test('source failure requires reading the implicated file before edit', () {
    final controller = AgentController()
      ..lastBuildFailureAnalysis = const BuildFailureAnalysis(
        kind: BuildFailureKind.sourceCompile,
        summary: 'compiler error',
        implicatedFiles: <String>['src/main.cpp'],
        implicatedLines: <String, int>{'src/main.cpp': 42},
      )
      ..buildRetryRequired = true
      ..buildFailureRevision = 3;
    expect(
      controller.buildFailureMutationBlockReason(
        'src/main.cpp',
        fileExists: true,
      ),
      contains('SOURCE_EDIT_REQUIRES_ERROR_RANGE'),
    );
    controller.fileReadAtBuildFailureRevision['src/main.cpp'] = 3;
    controller.fileReadRangesAtBuildFailureRevision['src/main.cpp'] = '1:20';
    expect(
      controller.buildFailureMutationBlockReason(
        'src/main.cpp',
        fileExists: true,
      ),
      contains('SOURCE_EDIT_REQUIRES_ERROR_RANGE'),
    );
    controller.fileReadRangesAtBuildFailureRevision['src/main.cpp'] = '22:62';
    expect(
      controller.buildFailureMutationBlockReason(
        'src/main.cpp',
        fileExists: true,
      ),
      isNull,
    );
  });

  test('automatic CMake repair is limited to a missing CMakeLists file', () {
    final controller = AgentController();
    expect(
      controller.shouldAutoRepairMissingCMakeLists(
        'CMake Error: source directory does not appear to contain CMakeLists.txt',
      ),
      isTrue,
    );
    expect(
      controller.shouldAutoRepairMissingCMakeLists(
        'CMake Error: Could not create named generator Ninja',
      ),
      isFalse,
    );
  });

  test('build configuration edit follows explicit help diagnostic', () {
    final controller = AgentController()
      ..lastBuildFailureAnalysis = const BuildFailureAnalysis(
        kind: BuildFailureKind.buildConfiguration,
        summary: 'bad command or missing configuration',
        suggestedDiagnosticCommand: 'cmake --help',
      )
      ..buildRetryRequired = true
      ..buildFailureRevision = 2;
    expect(
      controller.buildFailureMutationBlockReason(
        'CMakeLists.txt',
        fileExists: false,
      ),
      contains('BUILD_DIAGNOSTIC_REQUIRED'),
    );
    controller.buildDiagnosticsRun.add('cmake --help');
    expect(
      controller.buildFailureMutationBlockReason(
        'CMakeLists.txt',
        fileExists: false,
      ),
      isNull,
    );
  });

  test('after a build-related edit the original build command is required', () {
    final controller = AgentController()
      ..requiredBuildRetryCommand =
          'cmake -B build && cmake --build build --config Release';
    expect(
      controller.isRequiredBuildRetryCommand(
        'cmake -B build && cmake --build build --config Release',
      ),
      isTrue,
    );
    expect(
      controller.isRequiredBuildRetryCommand('g++ src/main.cpp -o app.exe'),
      isFalse,
    );
  });

  test('after a source edit the next tool must retry the build', () {
    final controller = AgentController()
      ..buildRetryRequired = true
      ..buildMutationAwaitingRetry = true
      ..requiredBuildRetryCommand =
          'cmake -B build && cmake --build build --config Release';
    expect(
      controller.isRequiredBuildRetryToolCall(
        const ToolCall(name: 'get_task_status', args: <String, dynamic>{}),
      ),
      isFalse,
    );
    expect(
      controller.isRequiredBuildRetryToolCall(
        const ToolCall(name: 'run_tests', args: <String, dynamic>{}),
      ),
      isTrue,
    );
    expect(
      controller.isRequiredBuildRetryToolCall(
        const ToolCall(
          name: 'run_command',
          args: <String, dynamic>{
            'command': 'cmake -B build && cmake --build build --config Release',
          },
        ),
      ),
      isTrue,
    );
  });

  test('hybrid retrieval ranks exact and related Russian text', () {
    const engine = HybridRetrievalEngine();
    const docs = [
      HybridDocument(
          id: 'a',
          title: 'Сборка Flutter',
          text: 'Команда flutter build windows'),
      HybridDocument(
          id: 'b',
          title: 'Память',
          text: 'Локальная типизированная память агента'),
    ];
    final results = engine.search('как собрать Flutter под Windows', docs);
    expect(results, isNotEmpty);
    expect(results.first.document.id, 'a');
  });

  test('golden path requires verification and a ruled-out approach', () async {
    final dir = await Directory.systemTemp.createTemp('aia_memory_test_');
    addTearDown(() => dir.delete(recursive: true));
    final memory = LocalMemoryService(configRoot: dir);
    await memory.initialize();

    await expectLater(
      memory.promoteGoldenPath(
        problem: 'build failed',
        solution: 'use the local Flutter SDK',
        verification: '',
        failedApproaches: const ['system flutter was missing'],
      ),
      throwsA(isA<StateError>()),
    );

    final record = await memory.promoteGoldenPath(
      problem: 'build failed',
      solution: 'use the local Flutter SDK',
      verification: 'EXIT_CODE: 0',
      failedApproaches: const ['system flutter was missing'],
    );
    expect(record.verified, isTrue);
    expect(record.type, AgentMemoryType.procedure);
  });

  test('memory redacts common secret forms', () async {
    final dir = await Directory.systemTemp.createTemp('aia_secret_test_');
    addTearDown(() => dir.delete(recursive: true));
    final memory = LocalMemoryService(configRoot: dir);
    final record = await memory.remember(
      type: AgentMemoryType.fact,
      title: 'Credentials',
      content: 'api_key=super-secret-value',
    );
    expect(record.content, isNot(contains('super-secret-value')));
    expect(record.content, contains('REDACTED'));
  });

  test('shared secret redactor masks tokens and URL credentials', () {
    final fakeGithubToken = [
      'ghp',
      'abcdefghijklmnopqrstuvwxyz123456',
    ].join('_');
    final redacted = SecretRedactor.redact(
      'Authorization=Bearer abcdefghijklmnop '
      'https://user:super-password@example.com $fakeGithubToken',
    );
    expect(redacted, isNot(contains('abcdefghijklmnop')));
    expect(redacted, isNot(contains('super-password')));
    expect(redacted, isNot(contains(fakeGithubToken)));
    expect(redacted, contains('REDACTED'));
  });

  test('structured secret redaction handles nested JSON-like values', () {
    final redacted = SecretRedactor.redactObject({
      'headers': {
        'Authorization': 'Bearer abcdefghijklmnopqrstuvwxyz',
      },
      'config': {
        'client_secret': 'nested-secret-value',
        'safe': 'visible',
      },
    });
    final text = redacted.toString();
    expect(text, isNot(contains('nested-secret-value')));
    expect(text, isNot(contains('abcdefghijklmnopqrstuvwxyz')));
    expect(text, contains('visible'));
  });

  test('only real build, test, or analysis commands count as verification', () {
    expect(
      VerificationCommandClassifier.isVerificationCommand('flutter analyze'),
      isTrue,
    );
    expect(
      VerificationCommandClassifier.isVerificationCommand('python -m pytest'),
      isTrue,
    );
    expect(
      VerificationCommandClassifier.isVerificationCommand('echo done'),
      isFalse,
    );

    final ledger = TaskEvidenceLedger();
    ledger.recordTool(
      toolName: 'run_command',
      args: const {'command': 'echo done'},
      result: 'EXIT_CODE: 0',
      successful: true,
    );
    expect(ledger.hasPassingVerification, isFalse);
    ledger.recordTool(
      toolName: 'run_command',
      args: const {'command': 'flutter analyze'},
      result: 'EXIT_CODE: 0',
      successful: true,
    );
    expect(ledger.hasPassingVerification, isTrue);
  });

  test('tool output compactor preserves signals and boundaries', () {
    final output =
        'BEGIN\n${List.filled(5000, 'normal line').join('\n')}\nERROR: failed\nEND';
    const compactor = ToolOutputCompactor(maxChars: 1200);
    final compacted = compactor.compact('run_command', output);
    expect(compacted, contains('TOOL_OUTPUT_COMPACTED'));
    expect(compacted, contains('ERROR: failed'));
    expect(compacted, contains('BEGIN'));
    expect(compacted, contains('END'));
  });

  test('memory serializes concurrent mutations without losing records',
      () async {
    final dir = await Directory.systemTemp.createTemp('aia_concurrent_memory_');
    addTearDown(() => dir.delete(recursive: true));
    final memory = LocalMemoryService(configRoot: dir);
    await Future.wait(List.generate(
      20,
      (index) => memory.remember(
        type: AgentMemoryType.observation,
        title: 'Observation $index',
        content: 'Value $index',
      ),
    ));
    final records = await memory.readActiveRecords();
    expect(records.length, 20);
  });

  test('memory preserves contradictory versions for review', () async {
    final dir = await Directory.systemTemp.createTemp('aia_conflict_test_');
    addTearDown(() => dir.delete(recursive: true));
    final memory = LocalMemoryService(configRoot: dir);
    await memory.remember(
      type: AgentMemoryType.decision,
      title: 'Build backend',
      content: 'Use Vulkan',
    );
    await memory.remember(
      type: AgentMemoryType.decision,
      title: 'Build backend',
      content: 'Use CUDA',
    );
    final conflicts = await memory.formatConflicts();
    expect(conflicts, contains('Use Vulkan'));
    expect(conflicts, contains('Use CUDA'));
  });

  test('reference plugin searches synchronized documentation by chunks',
      () async {
    final dir = await Directory.systemTemp.createTemp('aia_plugin_test_');
    addTearDown(() => dir.delete(recursive: true));
    final manager = PluginManager(
      pluginsRoot: dir,
      networkAllowed: () => false,
      onStatus: (_) {},
      onChanged: () {},
    );
    await manager.initialize();
    const id = 'production_agentic_rag_reference';
    final source = manager.pluginSourceDirectory(id);
    await source.create(recursive: true);
    await File('${source.path}${Platform.pathSeparator}README.md')
        .writeAsString(
      '${List.filled(1500, 'ordinary retrieval text').join('\n')}\n'
      '## Rare section\nreciprocal rank fusion preserves the rare needle',
    );
    manager.plugins = manager.plugins
        .map((plugin) => plugin.id == id
            ? plugin.copyWith(
                sourceInstalled: true,
                installedCommit: 'test-commit',
              )
            : plugin)
        .toList(growable: false);
    final result = await manager.searchDocumentation(id, 'rare needle');
    expect(result, contains('reciprocal rank fusion'));
  });

  test('task checkpoint survives interruption and archives terminal state',
      () async {
    final dir = await Directory.systemTemp.createTemp('aia_checkpoint_test_');
    addTearDown(() => dir.delete(recursive: true));
    final store = AgentRunCheckpointStore(projectRoot: dir);
    final started =
        await store.begin(prompt: 'Fix the project', maxIterations: 20);
    await store.save(started.copyWith(
      status: AgentRunStatus.executingTool,
      iteration: 4,
      lastTool: 'run_tests',
      toolActions: 7,
      commandRuns: 2,
      internetActions: 1,
      progressRevision: 5,
      lastCommand: 'flutter test',
      lastCommandResultPreview: 'EXIT_CODE: 0',
      lastCommandExitCode: 0,
      evidenceItems: [
        TaskEvidenceItem(
          time: DateTime.now(),
          type: TaskEvidenceType.test,
          title: 'run_tests',
          detail: 'EXIT_CODE: 0',
          successful: true,
        ).toJson(),
      ],
      toolGuardState: const {
        'callCounts': {'read_file:12345678': 2},
        'blockedCalls': 1,
      },
      buildFailureKind: BuildFailureKind.buildConfiguration.name,
      buildFailureSummary: 'CMakeLists.txt is missing',
      buildFailureImplicatedLines: const <String, int>{
        'src/main.cpp': 42,
      },
      buildSuggestedDiagnostic: 'cmake --help',
      buildRetryRequired: true,
      requiredBuildRetryCommand:
          'cmake -B build && cmake --build build --config Release',
      buildFailureRevision: 2,
      buildDiagnosticsRun: const <String>['cmake --help'],
      fileReadAtBuildFailureRevision: const <String, int>{
        'CMakeLists.txt': 2,
      },
      fileReadRangesAtBuildFailureRevision: const <String, String>{
        'src/main.cpp': '22:62',
      },
    ));

    final recovered = await store.loadInterrupted();
    expect(recovered, isNotNull);
    final checkpoint = recovered!;
    expect(checkpoint.status, AgentRunStatus.interrupted);
    expect(checkpoint.iteration, 4);
    expect(checkpoint.lastTool, 'run_tests');
    expect(checkpoint.commandRuns, 2);
    expect(checkpoint.internetActions, 1);
    expect(checkpoint.progressRevision, 5);
    expect(checkpoint.lastCommandExitCode, 0);
    expect(checkpoint.evidenceItems, hasLength(1));
    expect(checkpoint.toolGuardState['blockedCalls'], 1);
    expect(
        checkpoint.buildFailureKind, BuildFailureKind.buildConfiguration.name);
    expect(checkpoint.buildRetryRequired, isTrue);
    expect(checkpoint.buildSuggestedDiagnostic, 'cmake --help');
    expect(checkpoint.buildFailureImplicatedLines['src/main.cpp'], 42);
    expect(checkpoint.buildDiagnosticsRun, contains('cmake --help'));
    expect(checkpoint.fileReadAtBuildFailureRevision['CMakeLists.txt'], 2);
    expect(
      checkpoint.fileReadRangesAtBuildFailureRevision['src/main.cpp'],
      '22:62',
    );

    final completed = checkpoint.copyWith(status: AgentRunStatus.completed);
    await store.archiveAndClear(completed);
    expect(await store.activeFile.exists(), isFalse);
    final history = store.historyRoot
        .listSync(followLinks: false)
        .whereType<File>()
        .toList();
    expect(history, hasLength(1));
  });

  test('malformed checkpoint is quarantined instead of resumed', () async {
    final dir = await Directory.systemTemp.createTemp('aia_bad_checkpoint_');
    addTearDown(() => dir.delete(recursive: true));
    final store = AgentRunCheckpointStore(projectRoot: dir);
    await store.initialize();
    await store.activeFile.writeAsString('{broken json');
    expect(await store.loadInterrupted(), isNull);
    final quarantined = store.corruptRoot
        .listSync(followLinks: false)
        .whereType<File>()
        .toList();
    expect(quarantined, hasLength(1));
  });

  test('tool execution guard stops identical calls without progress', () {
    final guard = ToolExecutionGuard(maxIdenticalCallsWithoutProgress: 3);
    const args = <String, dynamic>{'path': 'lib/main.dart'};
    for (var index = 0; index < 3; index++) {
      expect(
        guard
            .evaluate(
              toolName: 'read_file',
              args: args,
              progressRevision: 0,
            )
            .allowed,
        isTrue,
      );
      guard.record(
        toolName: 'read_file',
        args: args,
        result: 'same result',
        progressRevision: 0,
        successful: true,
      );
    }
    final blocked = guard.evaluate(
      toolName: 'read_file',
      args: args,
      progressRevision: 0,
    );
    expect(blocked.allowed, isFalse);
    expect(blocked.message, contains('TOOL_CIRCUIT_BREAKER'));
  });

  test('global stall guard blocks alternating actions without progress', () {
    final guard = ToolExecutionGuard(
      maxIdenticalCallsWithoutProgress: 20,
      maxFailuresPerSignature: 20,
      maxCallsWithoutGlobalProgress: 4,
    );
    for (var index = 0; index < 4; index++) {
      final name = index.isEven ? 'read_file' : 'list_files';
      final args = <String, dynamic>{'path': index.isEven ? 'a' : 'b'};
      expect(
        guard
            .evaluate(
              toolName: name,
              args: args,
              progressRevision: 0,
            )
            .allowed,
        isTrue,
      );
      guard.record(
        toolName: name,
        args: args,
        result: 'unchanged',
        progressRevision: 0,
        successful: true,
      );
    }
    final blocked = guard.evaluate(
      toolName: 'project_map',
      args: const {'path': '.'},
      progressRevision: 0,
    );
    expect(blocked.allowed, isFalse);
    expect(blocked.message, contains('TOOL_GLOBAL_STALL'));
  });

  test('tool execution guard snapshot restores loop protection', () {
    final original = ToolExecutionGuard(maxIdenticalCallsWithoutProgress: 2);
    const args = <String, dynamic>{'command': 'echo hello'};
    for (var index = 0; index < 2; index++) {
      original.record(
        toolName: 'run_command',
        args: args,
        result: 'same result',
        progressRevision: 0,
        successful: true,
      );
    }
    final restored = ToolExecutionGuard(maxIdenticalCallsWithoutProgress: 2)
      ..restore(original.snapshot());
    final decision = restored.evaluate(
      toolName: 'run_command',
      args: args,
      progressRevision: 0,
    );
    expect(decision.allowed, isFalse);
    expect(
        original.signatureFor('run_command', args), isNot(contains('hello')));
  });

  test('evidence ledger recognizes a verified file-changing run', () {
    final ledger = TaskEvidenceLedger();
    ledger.recordTool(
      toolName: 'write_file',
      args: const {'path': 'lib/main.dart'},
      result: 'WRITE_OK',
      successful: true,
    );
    ledger.recordTool(
      toolName: 'run_tests',
      args: const {},
      result: 'EXIT_CODE: 0',
      successful: true,
    );
    expect(ledger.hasSuccessfulMutation, isTrue);
    expect(ledger.hasPassingVerification, isTrue);
    expect(
      ledger.confidence(
        expectsMutation: true,
        expectsVerification: true,
        expectsResearch: false,
      ),
      greaterThanOrEqualTo(0.8),
    );
  });

  test('attempt memory exposes outcomes and prevents blind retries', () {
    final ledger = TaskEvidenceLedger();
    ledger.recordTool(
      toolName: 'run_command',
      args: const {'command': 'cmake --build build'},
      result: 'EXIT_CODE: 1\nERROR: generator is unavailable',
      successful: false,
    );
    ledger.recordTool(
      toolName: 'run_command',
      args: const {'command': 'flutter test'},
      result: 'EXIT_CODE: 0\nAll tests passed',
      successful: true,
    );

    final context = ledger.decisionContext();
    expect(context, contains('DO_NOT_REPEAT_WITHOUT_NEW_EVIDENCE'));
    expect(context, contains('generator is unavailable'));
    expect(context, contains('REUSE_CONFIRMED_RESULTS'));
    expect(context, contains('EXIT_CODE: 0'));
  });

  test('adaptive budget extends only while measurable progress is recent', () {
    final budget = AdaptiveAgentBudget(
      configuredWindow: 8,
      extensionSize: 4,
      maximumIterations: 20,
    );
    budget.observe(iteration: 7, progressRevision: 2);
    expect(
      budget.extendIfProgressing(
          iteration: 8, progressRevision: 2, taskComplete: false),
      isTrue,
    );
    expect(budget.currentLimit, 12);
    expect(
      budget.extendIfProgressing(
          iteration: 20, progressRevision: 2, taskComplete: false),
      isFalse,
    );
  });

  test('interactive terminal keeps shell state and exposes it to the UI',
      () async {
    final dir = await Directory.systemTemp.createTemp('aia_terminal_test_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/nested').create();
    final service = InteractiveTerminalService();
    addTearDown(service.dispose);
    await service.configureProject(dir.path);
    await service.open(sessionId: 'shared', cwd: '.');

    await service.writeAndCollect('shared', 'cd nested',
        quietPeriod: const Duration(milliseconds: 150),
        timeout: const Duration(seconds: 5));
    final result = await service.writeAndCollect(
        'shared', Platform.isWindows ? 'cd' : 'pwd',
        quietPeriod: const Duration(milliseconds: 150),
        timeout: const Duration(seconds: 5));

    expect(service.snapshot('shared')?.running, isTrue);
    expect(result.toLowerCase(), contains('nested'));
    await service.close('shared');
  },
      timeout: const Timeout(Duration(seconds: 20)),
      skip: Platform.isWindows &&
              Platform.environment['AIA_TEST_NATIVE_PTY'] != '1'
          ? 'flutter test does not bundle flutter_pty.dll; covered by the Windows application smoke test'
          : false);

  test('shared agent console transcript survives project reload', () async {
    final dir = await Directory.systemTemp.createTemp('aia_terminal_log_test_');
    addTearDown(() => dir.delete(recursive: true));
    final first = InteractiveTerminalService();
    await first.configureProject(dir.path);
    await first.recordCommandTranscript(
      command: 'echo persisted',
      cwd: dir.path,
      output: 'persisted output',
    );
    expect(
        first.snapshot('agent-main')?.transcript, contains('persisted output'));
    await first.dispose();

    final second = InteractiveTerminalService();
    addTearDown(second.dispose);
    await second.configureProject(dir.path);
    expect(second.snapshot('agent-main')?.transcript,
        contains('persisted output'));
  });

  test('completion gate refuses a file task without a passing check', () {
    final ledger = TaskEvidenceLedger();
    ledger.recordTool(
      toolName: 'write_file',
      args: const {'path': 'lib/main.dart'},
      result: 'WRITE_OK',
      successful: true,
    );
    final incomplete = TaskCompletionGate.assess(
      evidence: ledger,
      expectsMutation: true,
      expectsVerification: true,
      expectsResearch: false,
      lastCommandExitCode: null,
      circuitBreakerBlocks: 0,
    );
    expect(incomplete.ready, isFalse);
    expect(incomplete.state, TaskCompletionState.needsEvidence);

    ledger.recordTool(
      toolName: 'run_tests',
      args: const {},
      result: 'EXIT_CODE: 0',
      successful: true,
    );
    final complete = TaskCompletionGate.assess(
      evidence: ledger,
      expectsMutation: true,
      expectsVerification: true,
      expectsResearch: false,
      lastCommandExitCode: 0,
      circuitBreakerBlocks: 0,
    );
    expect(complete.ready, isTrue);
    expect(complete.confidence, greaterThanOrEqualTo(0.8));
  });

  test('bundled plugin catalog contains isolated adapters', () {
    expect(bundledPluginCatalog.length, 11);
    expect(bundledPluginCatalog.map((item) => item.id).toSet().length, 11);
    expect(
      bundledPluginCatalog
          .firstWhere((item) => item.id == 'tempest_harness_reference')
          .enabled,
      isFalse,
    );
  });
  test('missing CMake cache is a configuration error', () {
    const analyzer = BuildFailureAnalyzer();
    final analysis = analyzer.analyze(
      command: 'cmake --build . --config Release',
      output: 'Error: not a CMake build directory (missing CMakeCache.txt)',
    );
    expect(analysis.kind, BuildFailureKind.buildConfiguration);
    expect(analysis.sourceMutationAllowed, isFalse);
    expect(analysis.suggestedRecoveryCommand, contains('cmake -S . -B build'));
  });

  test('local missing header is repaired through CMake, not cpp source',
      () async {
    final dir = await Directory.systemTemp.createTemp('aia_header_logic_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/include').create(recursive: true);
    await Directory('${dir.path}/src').create(recursive: true);
    await File('${dir.path}/include/ImageClassifier.h').writeAsString('// h');
    const analyzer = BuildFailureAnalyzer();
    final analysis = analyzer.analyze(
      command: 'cmake --build build --config Release',
      projectRoot: dir.path,
      output: '${dir.path.replaceAll('\\', '/')}/src/ImageClassifier.cpp:1:10: '
          'fatal error: ImageClassifier.h: No such file or directory',
    );
    expect(analysis.kind, BuildFailureKind.buildConfiguration);
    expect(analysis.implicatedFiles, contains('CMakeLists.txt'));
    expect(analysis.locatedDependencyPath, 'include/ImageClassifier.h');
    expect(analysis.sourceMutationAllowed, isFalse);
  });

  test('CMake resolver configures build directory before cmake build dot',
      () async {
    final dir = await Directory.systemTemp.createTemp('aia_cmake_resolver_');
    addTearDown(() => dir.delete(recursive: true));
    await File('${dir.path}/CMakeLists.txt')
        .writeAsString('cmake_minimum_required(VERSION 3.16)');
    final resolved = CMakeCommandResolver.resolve(
      command: 'cmake --build . --config Release',
      workingDirectory: dir.path,
    );
    expect(resolved.changed, isTrue);
    expect(resolved.effectiveCommand, contains('cmake -S . -B build'));
    expect(resolved.effectiveCommand, contains('cmake --build build'));
  });

  test('CMake resolver replaces captured build directory safely', () async {
    final dir = await Directory.systemTemp.createTemp('aia_cmake_existing_');
    addTearDown(() => dir.delete(recursive: true));
    final existing = Directory('${dir.path}/existing build');
    await existing.create(recursive: true);
    await File('${existing.path}/CMakeCache.txt').writeAsString('# cache');

    final resolved = CMakeCommandResolver.resolve(
      command: 'cmake --build . --config Release',
      workingDirectory: dir.path,
    );

    expect(resolved.changed, isTrue);
    expect(
      resolved.effectiveCommand,
      'cmake --build "existing build" --config Release',
    );
  });

  test('CMake configure-only command is not passing verification', () {
    final ledger = TaskEvidenceLedger();
    ledger.recordTool(
      toolName: 'run_tests',
      args: const {'command': 'cmake -S . -B build'},
      result: 'EXIT_CODE: 0',
      successful: true,
    );
    expect(ledger.hasPassingVerification, isFalse);
    expect(
      VerificationCommandClassifier.isVerificationCommand(
        'cmake -S . -B build',
      ),
      isFalse,
    );
  });

  test('later failure invalidates an earlier passing verification', () {
    final ledger = TaskEvidenceLedger();
    ledger.recordTool(
      toolName: 'run_tests',
      args: const {'command': 'cmake --build build'},
      result: 'EXIT_CODE: 0',
      successful: true,
    );
    expect(ledger.hasPassingVerification, isTrue);
    ledger.recordTool(
      toolName: 'run_tests',
      args: const {'command': 'cmake --build build'},
      result: 'EXIT_CODE: 1',
      successful: false,
    );
    expect(ledger.hasPassingVerification, isFalse);
  });

  test('blocked attempts contribute to global stall detection', () {
    final guard = ToolExecutionGuard(maxCallsWithoutGlobalProgress: 2);
    guard.recordBlockedAttempt(progressRevision: 0);
    guard.recordBlockedAttempt(progressRevision: 0);
    final decision = guard.evaluate(
      toolName: 'get_task_status',
      args: const {},
      progressRevision: 0,
    );
    expect(decision.allowed, isFalse);
    expect(decision.message, contains('TOOL_GLOBAL_STALL'));
  });

  test('CMake include repair preserves existing target and source code',
      () async {
    final dir = await Directory.systemTemp.createTemp('aia_cmake_patch_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/src').create(recursive: true);
    await Directory('${dir.path}/include').create(recursive: true);
    await File('${dir.path}/src/main.cpp')
        .writeAsString('int main(){return 0;}');
    await File('${dir.path}/src/ImageClassifier.cpp')
        .writeAsString('#include "ImageClassifier.h"');
    await File('${dir.path}/include/ImageClassifier.h').writeAsString('// h');
    await File('${dir.path}/CMakeLists.txt').writeAsString('''
cmake_minimum_required(VERSION 3.16)
project(UserProject)
add_executable(user_target src/main.cpp src/ImageClassifier.cpp)
''');
    final controller = AgentController()
      ..currentProject = ProjectInfo(name: 'test', path: dir.path);
    final note = controller.ensureCMakeListsForCppSource(
      'src/main.cpp',
      forceRepair: true,
    );
    final cmake = await File('${dir.path}/CMakeLists.txt').readAsString();
    expect(note, contains('without rewriting'));
    expect(cmake, contains('add_executable(user_target'));
    expect(cmake, contains('target_include_directories(user_target PRIVATE'));
    expect(cmake, contains(r'${CMAKE_CURRENT_SOURCE_DIR}/include'));
    expect(await File('${dir.path}/src/main.cpp').readAsString(),
        'int main(){return 0;}');
  });

  test('tool call parser repairs a trailing comma without changing arguments',
      () {
    final controller = AgentController();
    final calls = controller.parseToolCalls(
      '<tool_call>{"name":"run_command","args":{"command":"cmake -B build -S .","cwd":".",}}</tool_call>',
    );
    expect(calls, hasLength(1));
    expect(calls.single.name, 'run_command');
    expect(calls.single.args['command'], 'cmake -B build -S .');
    expect(calls.single.args['cwd'], '.');
  });

  test('replace_text contract infers CMakeLists path only when unambiguous',
      () {
    final resolution = ToolCallContract.resolve(
      const ToolCall(
        name: 'replace_text',
        args: {
          'old_text': 'find_package(OpenCV REQUIRED)',
          'new_text': 'find_package(OpenCV QUIET)',
        },
      ),
      buildFailureAnalysis: const BuildFailureAnalysis(
        kind: BuildFailureKind.buildConfiguration,
        summary: 'CMake configuration error',
        implicatedFiles: <String>['CMakeLists.txt'],
      ),
    );
    expect(resolution.valid, isTrue);
    expect(resolution.repaired, isTrue);
    expect(resolution.call.args['path'], 'CMakeLists.txt');
  });

  test(
      'tool contract rejects replace_text without required path when ambiguous',
      () {
    final resolution = ToolCallContract.resolve(
      const ToolCall(
        name: 'replace_text',
        args: {'old_text': 'alpha', 'new_text': 'beta'},
      ),
    );
    expect(resolution.valid, isFalse);
    expect(resolution.message, contains('`path`'));
  });

  test('image ML preflight blocks OpenCV DNN as a training framework', () {
    const availability = CppDependencyAvailability(
      openCvConfirmed: false,
      libTorchConfirmed: false,
      onnxRuntimeConfirmed: false,
      inspectedEntries: 0,
    );
    final reason = CppDependencyPreflight.planBlockReason(
      'Использовать OpenCV DNN, выполнить forward/backward training и собрать приложение.',
      availability,
    );
    expect(reason, contains('DEPENDENCY_CAPABILITY_MISMATCH'));
  });

  test('unverified absolute dependency path is blocked before CMake mutation',
      () {
    final reason = CppDependencyPreflight.mutationPathBlockReason(
      r'set(OpenCV_DIR "C:/definitely_missing_aia_opencv/build")',
    );
    expect(reason, contains('UNVERIFIED_DEPENDENCY_PATH_BLOCKED'));
  });

  test('plain success claim is rejected without a real action or evidence', () {
    final reason = UnsupportedSuccessClaimGuard.blockReason(
      text: 'Я успешно заменил блок в CMakeLists.txt и сборка завершена.',
      completionReady: false,
      hasActionsInResponse: false,
    );
    expect(reason, contains('UNSUPPORTED_SUCCESS_CLAIM'));
  });

  test('continuation wording is recognized without matching unrelated prompts',
      () {
    final controller = AgentController();
    expect(controller.isContinuationIntent('Продолжай'), isTrue);
    expect(controller.isContinuationIntent('продолжи работу'), isTrue);
    expect(controller.isContinuationIntent('Напиши продолжение рассказа'),
        isFalse);
  });

  test('latest cancelled checkpoint with progress can be resumed from history',
      () async {
    final dir = await Directory.systemTemp.createTemp('aia_resume_history_');
    addTearDown(() => dir.delete(recursive: true));
    final store = AgentRunCheckpointStore(projectRoot: dir);
    final checkpoint = await store.begin(
      prompt: 'Собери проект',
      maxIterations: 120,
    );
    await store.archiveAndClear(
      checkpoint.copyWith(
        status: AgentRunStatus.cancelled,
        iteration: 7,
        toolActions: 4,
        commandRuns: 2,
        lastError: 'cancelled by user',
      ),
    );
    final restored = await store.loadLatestResumableHistory();
    expect(restored, isNotNull);
    expect(restored!.prompt, 'Собери проект');
    expect(restored.iteration, 7);
    expect(restored.status, AgentRunStatus.cancelled);
  });

  test('missing CMake working directory is normalized to project root',
      () async {
    final dir = await Directory.systemTemp.createTemp('aia_cmake_cwd_');
    addTearDown(() => dir.delete(recursive: true));
    final resolution = BuildWorkingDirectoryResolver.resolve(
      command: 'cmake --build . --config Release',
      projectRoot: dir.path,
      requestedRelativeDirectory: 'build',
    );
    expect(resolution.changed, isTrue);
    expect(resolution.effectiveRelativeDirectory, isEmpty);
    expect(resolution.reason, contains('CMake'));
  });

  test('trailing comma repair never changes comma-brace text inside strings',
      () {
    const source =
        '{"name":"write_file","args":{"path":"x.txt","content":"keep ,} and ,]",},}';
    final repaired = ToolCallJsonRepair.removeTrailingCommas(source);
    expect(repaired, contains('keep ,} and ,]'));
    expect(repaired, endsWith('"}}'));
  });

  test('a fallback sentence does not replace dependency preflight', () {
    const availability = CppDependencyAvailability(
      openCvConfirmed: false,
      libTorchConfirmed: false,
      onnxRuntimeConfirmed: false,
      inspectedEntries: 0,
    );
    final reason = CppDependencyPreflight.planBlockReason(
      'Выберу LibTorch и напишу основные файлы. Если библиотека будет недоступна, потом сделаю упрощённый вариант.',
      availability,
    );
    expect(reason, contains('DEPENDENCY_PREFLIGHT_REQUIRED'));
  });

  test('explicit dependency check before implementation is accepted', () {
    const availability = CppDependencyAvailability(
      openCvConfirmed: false,
      libTorchConfirmed: false,
      onnxRuntimeConfirmed: false,
      inspectedEntries: 0,
    );
    final reason = CppDependencyPreflight.planBlockReason(
      'Сначала проверить наличие LibTorch через list_local_tools, затем написать основные файлы или выбрать вариант без зависимости.',
      availability,
    );
    expect(reason, isNull);
  });
}
