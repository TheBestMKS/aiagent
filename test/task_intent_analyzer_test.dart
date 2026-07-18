import 'package:flutter_test/flutter_test.dart';
import 'package:ii_agent/agent_core/planning/task_intent_analyzer.dart';

void main() {
  const analyzer = TaskIntentAnalyzer();

  test('keeps several domains instead of forcing a software workflow', () {
    final intent = analyzer.analyze(
        'Подключись по SSH к серверу, найди там DOCX и исправь таблицу в документе');

    expect(intent.domains, contains(TaskDomain.remoteAccess));
    expect(intent.domains, contains(TaskDomain.documents));
    expect(intent.domains, contains(TaskDomain.spreadsheets));
    expect(intent.actions, contains(TaskAction.connect));
    expect(intent.actions, contains(TaskAction.edit));
    expect(intent.requiresProjectAudit, isFalse);
    expect(intent.recommendedInitialTools, contains('terminal_open'));
    expect(intent.recommendedInitialTools, contains('read_document_structure'));
  });

  test('routes device document search without inserting project audit rules',
      () {
    final intent = analyzer.analyze(
        'Поищи информацию о rundll32 на компьютере, найди документы содержащие её');
    final frame = intent.toPromptBlock(
        projectPath: r'N:\Projects\Default',
        projectEntries: const ['README.md']);

    expect(intent.domains, contains(TaskDomain.deviceSearch));
    expect(intent.domains, contains(TaskDomain.documents));
    expect(intent.requiresProjectAudit, isFalse);
    expect(intent.recommendedInitialTools, contains('search_device_documents'));
    expect(frame, contains('original request is authoritative'));
    expect(frame, isNot(contains('document_work')));
    expect(frame, isNot(contains('reserved_before_task')));
  });

  test('recognizes security work as an interactive remote task', () {
    final intent = analyzer.analyze(
        'Используя nmap и metasploit проведи разрешенный пентест списка IP');

    expect(intent.domains, contains(TaskDomain.securityAssessment));
    expect(intent.capabilities, contains('persistent-terminal'));
    expect(intent.capabilities, contains('scope-and-authorization'));
    expect(intent.recommendedInitialTools, contains('terminal_open'));
  });
}
