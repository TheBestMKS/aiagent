import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_agent/agent_core/runs/agent_run_checkpoint.dart';
import 'package:ii_agent/agent_core/runs/agent_run_checkpoint_store.dart';
import 'package:ii_agent/agent_core/runs/agent_termination.dart';
import 'package:ii_agent/agent_core/terminal/interactive_terminal_service.dart';

void main() {
  test('Windows project path is converted to a WSL mount path', () {
    expect(
      InteractiveTerminalService.windowsPathToWsl(r'N:\Projects\Demo App'),
      '/mnt/n/Projects/Demo App',
    );
    expect(
      InteractiveTerminalService.windowsPathToWsl('/home/user/project'),
      '/home/user/project',
    );
  });

  test('WSL verbose output is parsed even when it contains UTF-16 nulls', () {
    const output = ' \u0000 \u0000N\u0000A\u0000M\u0000E\u0000      '
        'S\u0000T\u0000A\u0000T\u0000E\u0000      '
        'V\u0000E\u0000R\u0000S\u0000I\u0000O\u0000N\u0000\r\u0000\n\u0000'
        '*\u0000 \u0000D\u0000e\u0000b\u0000i\u0000a\u0000n\u0000  '
        'S\u0000t\u0000o\u0000p\u0000p\u0000e\u0000d\u0000  2\u0000';
    final distributions =
        InteractiveTerminalService.parseWslDistributionList(output);

    expect(distributions, hasLength(1));
    expect(distributions.single.name, 'Debian');
    expect(distributions.single.state, 'Stopped');
    expect(distributions.single.version, 2);
    expect(distributions.single.isDefault, isTrue);
  });

  test('guidance request is distinct from user cancellation', () {
    final termination = AgentTerminationState()
      ..requestUserGuidance('Неизвестен адрес сервера');

    expect(termination.shouldStop, isTrue);
    expect(termination.awaitingUser, isTrue);
    expect(termination.userRequested, isFalse);
    expect(termination.safetyStopped, isFalse);
    expect(
      AgentLoopResult.awaitingUser(termination.reason).status,
      AgentRunStatus.awaitingUser,
    );
  });

  test('awaiting-user checkpoint remains active and resumable', () async {
    final root = await Directory.systemTemp.createTemp('aia_awaiting_');
    addTearDown(() => root.delete(recursive: true));
    final store = AgentRunCheckpointStore(projectRoot: root);
    final checkpoint = await store.begin(
      prompt: 'Настрой сервер',
      maxIterations: 100,
    );
    await store.save(checkpoint.copyWith(
      status: AgentRunStatus.awaitingUser,
      iteration: 9,
      toolActions: 6,
      lastError: 'Нужен адрес сервера',
    ));

    final restored = await store.loadInterrupted();
    expect(restored, isNotNull);
    expect(restored!.status, AgentRunStatus.awaitingUser);
    expect(restored.canResume, isTrue);
    expect(restored.lastError, 'Нужен адрес сервера');
  });
}
