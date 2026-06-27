import 'dart:async';

import 'package:flutter/material.dart';

String renderHtmlLikeBrowser(String html,
    {required String url, required int status}) {
  var text = html;
  text = text.replaceAll(RegExp(r'(?is)<script[^>]*>.*?</script>'), '');
  text = text.replaceAll(RegExp(r'(?is)<style[^>]*>.*?</style>'), '');
  final titleMatch = RegExp(r'(?is)<title[^>]*>(.*?)</title>').firstMatch(text);
  final title = titleMatch == null
      ? url
      : htmlDecodeBasic(titleMatch.group(1) ?? url).trim();
  text = text.replaceAll(RegExp(r'(?i)<br\s*/?>'), '\n');
  text = text.replaceAll(RegExp(r'(?i)</p\s*>'), '\n\n');
  text = text.replaceAll(RegExp(r'(?i)</h[1-6]\s*>'), '\n\n');
  text = text.replaceAll(RegExp(r'(?i)<li[^>]*>'), '• ');
  text = text.replaceAll(RegExp(r'(?i)</li\s*>'), '\n');
  text = text.replaceAll(RegExp(r'(?is)<[^>]+>'), ' ');
  text = htmlDecodeBasic(text);
  text = text.replaceAll(RegExp(r'[ \t\x0B\f\r]+'), ' ');
  text = text.replaceAll(RegExp(r'\n\s+'), '\n');
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  if (text.isEmpty)
    text = '(страница не содержит видимого текста или требует JavaScript)';
  return 'HTTP $status\n$title\nURL: $url\n\n$text';
}

String htmlDecodeBasic(String value) {
  return value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}

Future<String?> askText(BuildContext context, String title, String label,
    {String initial = ''}) async {
  final controller = TextEditingController(text: initial);
  try {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
            controller: controller,
            decoration: InputDecoration(
                labelText: label, border: const OutlineInputBorder()),
            autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('ОК')),
        ],
      ),
    );
    return result;
  } finally {
    controller.dispose();
  }
}
