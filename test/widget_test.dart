import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_agent/app/ai_agent_app.dart';
import 'package:ii_agent/utils/path_utils.dart';

void main() {
  testWidgets('App starts', (WidgetTester tester) async {
    await tester.pumpWidget(const AiAgentApp(disableStartupTasks: true));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  test('sanitize file names', () {
    expect(sanitizeFileName('test'), 'test');
    expect(sanitizeFileName('a/b:c'), 'a_b_c');
  });

  test('truncateMiddle keeps short text', () {
    expect(truncateMiddle('abc', 10), 'abc');
  });
}
