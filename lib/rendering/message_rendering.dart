import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';

import '../controllers/agent_controller.dart';

Widget buildMessageContent(BuildContext context, AgentController controller,
    String keyPrefix, String text, VoidCallback onChanged) {
  final widgets = <Widget>[];
  final fencePattern = RegExp(r'```([^\r\n`]*)\r?\n([\s\S]*?)```');
  var index = 0;
  var blockIndex = 0;
  for (final match in fencePattern.allMatches(text)) {
    if (match.start > index) {
      final before = text.substring(index, match.start);
      if (before.isNotEmpty)
        widgets
            .add(buildFormattedContentWithTables(context, controller, before));
    }
    final language = (match.group(1) ?? '').trim();
    final code = match.group(2) ?? '';
    final key = '$keyPrefix:code:$blockIndex';
    widgets.add(Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child:
          buildCollapsibleCodeBlock(controller, key, language, code, onChanged),
    ));
    blockIndex++;
    index = match.end;
  }
  if (index < text.length) {
    final tail = text.substring(index);
    if (tail.isNotEmpty)
      widgets.add(buildFormattedContentWithTables(context, controller, tail));
  }
  final imagePreview = buildMessageImagePreviews(context, controller, text);
  if (imagePreview != null)
    widgets.add(
        Padding(padding: const EdgeInsets.only(top: 8), child: imagePreview));
  if (widgets.isEmpty) return const SizedBox.shrink();
  if (widgets.length == 1) return widgets.first;
  return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets);
}

Widget? buildMessageImagePreviews(
    BuildContext context, AgentController controller, String text) {
  final items = <MapEntry<String, String>>[];
  final seen = <String>{};
  void add(String url, String label) {
    final clean = url.trim().replaceAll(RegExp(r'[\)\]\.,;]+$'), '');
    if (clean.isEmpty || !seen.add(clean)) return;
    final lower = clean.toLowerCase();
    if (!RegExp(r'\.(png|jpe?g|webp|gif|bmp)(\?|#|$)', caseSensitive: false)
        .hasMatch(lower)) return;
    items.add(
        MapEntry(clean, label.trim().isEmpty ? 'изображение' : label.trim()));
  }

  for (final m
      in RegExp(r'!\[([^\]]*)\]\((https?://[^\)]+)\)').allMatches(text)) {
    add(m.group(2) ?? '', m.group(1) ?? '');
  }
  for (final m
      in RegExp(r'^\s*-\s*(.*?)\s*=>\s*(https?://\S+)', multiLine: true)
          .allMatches(text)) {
    final label = m.group(1) ?? '';
    final url = m.group(2) ?? '';
    if (label.toLowerCase().contains('изображ') ||
        label.toLowerCase().contains('фото') ||
        RegExp(r'\.(png|jpe?g|webp|gif|bmp)', caseSensitive: false)
            .hasMatch(url)) add(url, label);
  }
  if (items.isEmpty) return null;
  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: items
        .take(8)
        .map((item) => InkWell(
              onTap: () => showLinkActionDialog(context, controller, item.key),
              child: SizedBox(
                width: 160,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(item.key,
                          width: 160,
                          height: 110,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                              width: 160,
                              height: 80,
                              alignment: Alignment.center,
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: const Icon(Icons.broken_image))),
                    ),
                    const SizedBox(height: 4),
                    Text(item.value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ),
            ))
        .toList(),
  );
}

Widget buildCollapsibleCodeBlock(AgentController controller, String key,
    String language, String code, VoidCallback onChanged) {
  final expanded = controller.expandedCodeBlockKey == key;
  final lang = language.isEmpty ? 'code' : language;
  final lineCount = code.isEmpty ? 0 : code.split(RegExp(r'\r?\n')).length;
  return Container(
    width: double.infinity,
    decoration: BoxDecoration(
      border: Border.all(color: Colors.grey.withValues(alpha: 0.45)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () {
            controller.expandedCodeBlockKey = expanded ? null : key;
            onChanged();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18),
                const SizedBox(width: 6),
                const Icon(Icons.code, size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('Блок кода: $lang • $lineCount строк',
                        style: const TextStyle(fontWeight: FontWeight.w700))),
              ],
            ),
          ),
        ),
        if (expanded)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(color: Colors.grey.withValues(alpha: 0.35))),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: SingleChildScrollView(
                child: SelectableText(
                  code,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

Widget buildFormattedContentWithTables(
    BuildContext context, AgentController controller, String text) {
  final lines = text.split(RegExp(r'\r?\n'));
  final widgets = <Widget>[];
  final plain = StringBuffer();
  var i = 0;
  void flushPlain() {
    if (plain.isEmpty) return;
    widgets.add(
        buildFormattedSelectableText(context, controller, plain.toString()));
    plain.clear();
  }

  bool isDividerLine(String line) {
    final t = line.trim();
    if (!t.contains('|')) return false;
    return RegExp(r'^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$')
        .hasMatch(t);
  }

  bool isTableRow(String line) =>
      line.trim().contains('|') && line.trim().split('|').length >= 3;
  while (i < lines.length) {
    if (i + 1 < lines.length &&
        isTableRow(lines[i]) &&
        isDividerLine(lines[i + 1])) {
      flushPlain();
      final tableRows = <String>[lines[i]];
      i += 2;
      while (i < lines.length && isTableRow(lines[i])) {
        tableRows.add(lines[i]);
        i++;
      }
      widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: buildMarkdownTable(context, tableRows)));
      continue;
    }
    plain.writeln(lines[i]);
    i++;
  }
  flushPlain();
  if (widgets.isEmpty) return const SizedBox.shrink();
  if (widgets.length == 1) return widgets.first;
  return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets);
}

List<String> splitMarkdownTableRow(String line) {
  var t = line.trim();
  if (t.startsWith('|')) t = t.substring(1);
  if (t.endsWith('|')) t = t.substring(0, t.length - 1);
  return t.split('|').map((e) => e.trim()).toList();
}

Widget buildMarkdownTable(BuildContext context, List<String> rows) {
  if (rows.isEmpty) return const SizedBox.shrink();
  final header = splitMarkdownTableRow(rows.first);
  final dataRows = rows.skip(1).map(splitMarkdownTableRow).toList();
  final columnCount = math.max(
      header.length, dataRows.fold<int>(0, (m, r) => math.max(m, r.length)));
  String cell(List<String> row, int index) =>
      index < row.length ? row[index] : '';
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(
      headingRowHeight: 36,
      dataRowMinHeight: 34,
      dataRowMaxHeight: 72,
      columns: [
        for (var c = 0; c < columnCount; c++)
          DataColumn(
              label: Text(cell(header, c),
                  style: const TextStyle(fontWeight: FontWeight.w800)))
      ],
      rows: [
        for (final row in dataRows)
          DataRow(cells: [
            for (var c = 0; c < columnCount; c++)
              DataCell(SelectableText(cell(row, c)))
          ])
      ],
    ),
  );
}

Widget buildFormattedSelectableText(
    BuildContext context, AgentController controller, String text) {
  final spans = <TextSpan>[];
  final lines = text
      .splitMapJoin(
        RegExp(r'\r?\n'),
        onMatch: (m) => '\n',
        onNonMatch: (part) => part,
      )
      .split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final heading = RegExp(r'^(#{1,6})\s*(.*)$').firstMatch(line);
    if (heading != null) {
      final level = heading.group(1)!.length;
      var body = heading.group(2) ?? '';
      final style = TextStyle(
        fontSize: switch (level) {
          1 => 24,
          2 => 22,
          3 => 20,
          4 => 18,
          5 => 16,
          _ => 15
        },
        fontWeight: FontWeight.w800,
        height: 1.25,
      );
      appendInlineFormattedSpans(context, controller, spans, body,
          baseStyle: style);
    } else {
      appendInlineFormattedSpans(context, controller, spans, line);
    }
    if (i != lines.length - 1) spans.add(const TextSpan(text: '\n'));
  }
  return SelectableText.rich(TextSpan(children: spans));
}

void appendInlineFormattedSpans(BuildContext context,
    AgentController controller, List<TextSpan> spans, String text,
    {TextStyle? baseStyle}) {
  final pattern =
      RegExp(r'(\*\*[\s\S]*?\*\*|`[^`\r\n]+`|https?://[^\s\)\]\}]+)');
  var index = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > index)
      spans.add(
          TextSpan(text: text.substring(index, match.start), style: baseStyle));
    final token = match.group(0) ?? '';
    if (token.startsWith('**') && token.endsWith('**') && token.length >= 4) {
      spans.add(TextSpan(
          text: token.substring(2, token.length - 2),
          style: (baseStyle ?? const TextStyle())
              .merge(const TextStyle(fontWeight: FontWeight.w800))));
    } else if (token.startsWith('`') &&
        token.endsWith('`') &&
        token.length >= 2) {
      spans.add(TextSpan(
          text: token.substring(1, token.length - 1),
          style: (baseStyle ?? const TextStyle())
              .merge(const TextStyle(fontFamily: 'monospace'))));
    } else if (token.startsWith('http://') || token.startsWith('https://')) {
      spans.add(TextSpan(
        text: token,
        style: (baseStyle ?? const TextStyle()).merge(TextStyle(
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline)),
        recognizer: TapGestureRecognizer()
          ..onTap = () => showLinkActionDialog(context, controller, token),
      ));
    } else {
      spans.add(TextSpan(text: token, style: baseStyle));
    }
    index = match.end;
  }
  if (index < text.length)
    spans.add(TextSpan(text: text.substring(index), style: baseStyle));
}

Future<void> showLinkActionDialog(
    BuildContext context, AgentController controller, String url) async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (_) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
              title: Text(url, maxLines: 2, overflow: TextOverflow.ellipsis)),
          ListTile(
              leading: const Icon(Icons.tab),
              title: const Text('Открыть во вкладке Web'),
              onTap: () {
                Navigator.pop(context);
                controller.openUrlInWebTab?.call(url);
              }),
          ListTile(
              leading: const Icon(Icons.open_in_browser),
              title: const Text('Открыть с помощью внешнего браузера'),
              onTap: () {
                Navigator.pop(context);
                unawaited(controller.openExternalUrl(url));
              }),
          ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Копировать'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: url));
                Navigator.pop(context);
              }),
        ],
      ),
    ),
  );
}
