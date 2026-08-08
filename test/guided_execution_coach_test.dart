import 'package:flutter_test/flutter_test.dart';
import 'package:ii_agent/agent_core/build/project_build_recipe.dart';
import 'package:ii_agent/agent_core/planning/guided_execution_coach.dart';
import 'package:ii_agent/agent_core/planning/task_intent_analyzer.dart';

void main() {
  const coach = GuidedExecutionCoach();
  final intent = const TaskIntentAnalyzer().analyze(
    'Создай программу, собери её и проверь тестами',
  );
  const recipe = ProjectBuildRecipe(
    ecosystem: ProjectEcosystem.flutter,
    projectRoot: 'project',
    signals: ['pubspec.yaml'],
    sourceFiles: ['lib/main.dart'],
    verificationCommands: ['flutter analyze'],
    buildCommands: ['flutter build windows --release'],
    runCommands: [],
    requiredExecutables: ['flutter'],
    missingExecutables: [],
  );

  GuidedExecutionInput input({
    int actions = 0,
    int mutations = 0,
    int commands = 0,
    int failures = 0,
    int? exitCode,
    String failureKind = 'none',
    String implicatedFile = '',
    bool implicatedFileRead = false,
    bool retry = false,
    bool passingVerification = false,
    bool completionReady = false,
    String blocker = '',
  }) =>
      GuidedExecutionInput(
        intent: intent,
        taskToolActions: actions,
        fileMutations: mutations,
        commandRuns: commands,
        failedCommands: failures,
        lastExitCode: exitCode,
        lastToolName: '',
        buildFailureKind: failureKind,
        buildFailureSummary: 'compiler diagnostic',
        implicatedFile: implicatedFile,
        implicatedFileRead: implicatedFileRead,
        suggestedDiagnosticCommand: '',
        buildRetryRequired: retry,
        hasPassingVerification: passingVerification,
        completionReady: completionReady,
        completionBlocker: blocker,
        buildRecipe: recipe,
      );

  test('small and unknown local models receive strict guidance', () {
    expect(
      coach.modelNeedsStrictGuidance(
        modelName: 'qwen2.5-coder-7b',
        contextTokens: 32768,
        outputTokens: 8192,
        localModel: true,
      ),
      isTrue,
    );
    expect(
      coach.modelNeedsStrictGuidance(
        modelName: 'large-remote-model',
        contextTokens: 131072,
        outputTokens: 16384,
        localModel: false,
      ),
      isFalse,
    );
  });

  test('software stages expose only the tools needed for the next step', () {
    final inspect = input();
    expect(coach.nextStep(inspect).stage, GuidedExecutionStage.inspect);
    expect(coach.routedTools(inspect), contains('inspect_project_build'));
    expect(coach.routedTools(inspect), isNot(contains('write_file')));

    final implement = input(actions: 1);
    expect(coach.nextStep(implement).stage, GuidedExecutionStage.implement);
    expect(coach.routedTools(implement), contains('write_file'));
    expect(coach.routedTools(implement), isNot(contains('run_tests')));

    final verify = input(actions: 2, mutations: 2);
    expect(coach.nextStep(verify).stage, GuidedExecutionStage.verify);
    expect(coach.routedTools(verify), contains('run_tests'));
  });

  test('compiler failure requires reading implicated source before editing',
      () {
    final failed = input(
      actions: 4,
      mutations: 2,
      commands: 1,
      failures: 1,
      exitCode: 1,
      failureKind: 'sourceCompile',
      implicatedFile: 'lib/main.dart',
    );
    final step = coach.nextStep(failed);

    expect(step.stage, GuidedExecutionStage.diagnose);
    expect(step.preferredTools, ['read_file']);
  });

  test('verification-only software task never enters implementation stage', () {
    final buildIntent = const TaskIntentAnalyzer().analyze(
      'Собери существующий проект',
    );
    final buildOnly = GuidedExecutionInput(
      intent: buildIntent,
      taskToolActions: 1,
      fileMutations: 0,
      commandRuns: 0,
      failedCommands: 0,
      lastExitCode: null,
      lastToolName: 'inspect_project_build',
      buildFailureKind: 'none',
      buildFailureSummary: '',
      implicatedFile: '',
      implicatedFileRead: false,
      suggestedDiagnosticCommand: '',
      buildRetryRequired: false,
      hasPassingVerification: false,
      completionReady: false,
      completionBlocker: '',
      buildRecipe: recipe,
    );

    expect(buildIntent.expectsMutation, isFalse);
    expect(coach.nextStep(buildOnly).stage, GuidedExecutionStage.verify);
    expect(coach.routedTools(buildOnly), contains('run_tests'));
    expect(coach.routedTools(buildOnly), isNot(contains('write_file')));
  });

  test('successful diagnostic output does not replace a passing build', () {
    final afterHelp = input(
      actions: 4,
      mutations: 2,
      commands: 2,
      exitCode: 0,
      passingVerification: false,
      blocker: 'успешная сборка ещё не выполнена',
    );

    expect(coach.nextStep(afterHelp).stage, GuidedExecutionStage.verify);
    expect(coach.routedTools(afterHelp), contains('run_tests'));
  });

  test('completed task routes to delivery instead of repeating tools', () {
    final completed = input(
      actions: 5,
      mutations: 2,
      commands: 1,
      exitCode: 0,
      passingVerification: true,
      completionReady: true,
    );

    expect(coach.nextStep(completed).stage, GuidedExecutionStage.deliver);
    expect(coach.routedTools(completed), isNot(contains('run_tests')));
  });
}
