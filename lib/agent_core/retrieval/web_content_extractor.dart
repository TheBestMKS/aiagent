import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

class WebPageLink {
  const WebPageLink({required this.url, required this.label});

  final String url;
  final String label;
}

class WebPageImage {
  const WebPageImage({required this.url, required this.description});

  final String url;
  final String description;
}

class WebSearchHit {
  const WebSearchHit({
    required this.url,
    required this.title,
    this.snippet = '',
  });

  final String url;
  final String title;
  final String snippet;
}

class ExtractedWebPage {
  const ExtractedWebPage({
    required this.title,
    required this.text,
    required this.links,
    required this.images,
    required this.metadata,
    required this.structuredData,
    required this.wordCount,
    required this.qualityScore,
    required this.warnings,
  });

  final String title;
  final String text;
  final List<WebPageLink> links;
  final List<WebPageImage> images;
  final Map<String, String> metadata;
  final List<Object?> structuredData;
  final int wordCount;
  final double qualityScore;
  final List<String> warnings;
}

/// DOM-based extraction for pages presented to the model.
///
/// It keeps document structure that carries meaning (headings, lists, tables,
/// quotes and code), while dropping navigation and executable page chrome.
class WebContentExtractor {
  const WebContentExtractor();

  ExtractedWebPage extract(String source, Uri baseUri) {
    final document = html_parser.parse(source);
    final metadata = _extractMetadata(document, baseUri);
    final structuredData = _extractStructuredData(document);
    final title = _cleanInline(document.querySelector('title')?.text ??
        metadata['og:title'] ??
        metadata['twitter:title'] ??
        '');

    for (final node in document.querySelectorAll(
        'script, style, noscript, template, svg, canvas, iframe, form, '
        'button, input, select, textarea, dialog')) {
      node.remove();
    }

    final main = _selectMainContent(document);
    final cleanedMain = main.clone(true);
    for (final node in cleanedMain.querySelectorAll(
        'nav, footer, aside, [role="navigation"], [role="complementary"], '
        '[aria-hidden="true"], .cookie, .cookies, .consent, .advertisement, '
        '.advert, .ads, .social-share, .share-buttons, .newsletter, '
        '.breadcrumbs, .breadcrumb, .pagination')) {
      node.remove();
    }
    final links = _extractLinks(cleanedMain, baseUri);
    final images = _extractImages(document, cleanedMain, baseUri);

    var text = _renderElement(cleanedMain);
    if (text.length < 240 && document.body != null && main != document.body) {
      text = _renderElement(document.body!);
    }
    text = _normalizeBlockText(text);

    final words = RegExp(r'[^\s]+').allMatches(text).length;
    final warnings = <String>[];
    if (text.length < 240) {
      warnings.add('На странице извлечено мало основного текста.');
    }
    final lower = text.toLowerCase();
    if (lower.contains('enable javascript') ||
        lower.contains('включите javascript') ||
        lower.contains('checking your browser') ||
        lower.contains('captcha')) {
      warnings.add(
          'Страница может требовать JavaScript, авторизацию или проверку браузера.');
    }
    if (words > 0 && links.length > words ~/ 3) {
      warnings.add('Страница содержит много навигационных ссылок.');
    }

    final paragraphCount = cleanedMain.querySelectorAll('p').length;
    final tableCount = cleanedMain.querySelectorAll('table').length;
    final semanticBonus = paragraphCount * 0.015 + tableCount * 0.08;
    final lengthScore = (text.length / 5000).clamp(0.0, 1.0);
    final quality =
        (lengthScore * 0.72 + semanticBonus).clamp(0.0, 1.0).toDouble();

    return ExtractedWebPage(
      title: title,
      text: text,
      links: links,
      images: images,
      metadata: metadata,
      structuredData: structuredData,
      wordCount: words,
      qualityScore: quality,
      warnings: warnings,
    );
  }

  List<WebSearchHit> extractSearchResults(String source, Uri baseUri,
      {int maxResults = 10}) {
    final document = html_parser.parse(source);
    final hits = <WebSearchHit>[];
    final seen = <String>{};

    void add(Element anchor, {Element? container}) {
      if (hits.length >= maxResults) return;
      final url = _resolveUrl(baseUri, anchor.attributes['href'] ?? '');
      final title = _cleanInline(anchor.text);
      if (url.isEmpty || title.length < 3 || !seen.add(url)) return;
      final scope = container ?? anchor.parent;
      final snippet = _cleanInline(
          scope?.querySelector('.result__snippet, .result-snippet, p')?.text ??
              '');
      hits.add(WebSearchHit(url: url, title: title, snippet: snippet));
    }

    for (final anchor in document.querySelectorAll('a.result__a')) {
      add(anchor, container: anchor.parent?.parent);
    }
    if (hits.isEmpty) {
      for (final anchor in document.querySelectorAll('main a[href], a[href]')) {
        add(anchor);
        if (hits.length >= maxResults) break;
      }
    }
    return hits;
  }

  Element _selectMainContent(Document document) {
    for (final selector in const [
      'article',
      'main',
      '[role="main"]',
      '#content',
      '#main-content',
      '.main-content',
      '.article-content',
      '.post-content',
      '.entry-content'
    ]) {
      final candidates = document.querySelectorAll(selector);
      if (candidates.isEmpty) continue;
      candidates.sort((a, b) => b.text.length.compareTo(a.text.length));
      if (candidates.first.text.trim().length >= 160) return candidates.first;
    }

    final body = document.body ?? document.documentElement!;
    final candidates = body.querySelectorAll('section, div').where((element) {
      final textLength = element.text.trim().length;
      if (textLength < 400) return false;
      final directChildren = element.children.length.clamp(1, 10000);
      return textLength / directChildren > 80;
    }).toList();
    if (candidates.isNotEmpty) {
      candidates.sort((a, b) => _contentScore(b).compareTo(_contentScore(a)));
      return candidates.first;
    }
    return body;
  }

  double _contentScore(Element element) {
    final textLength = element.text.trim().length.toDouble();
    final linkLength = element
        .querySelectorAll('a')
        .fold<int>(0, (sum, anchor) => sum + anchor.text.length);
    final paragraphBonus = element.querySelectorAll('p').length * 80.0;
    final headingBonus = element.querySelectorAll('h1, h2, h3').length * 35.0;
    return textLength - linkLength * 0.65 + paragraphBonus + headingBonus;
  }

  Map<String, String> _extractMetadata(Document document, Uri baseUri) {
    final result = <String, String>{};
    for (final meta in document.querySelectorAll('meta')) {
      final key = (meta.attributes['property'] ??
              meta.attributes['name'] ??
              meta.attributes['itemprop'] ??
              '')
          .trim()
          .toLowerCase();
      final value = _cleanInline(meta.attributes['content'] ?? '');
      if (key.isNotEmpty && value.isNotEmpty && result.length < 80) {
        result.putIfAbsent(key, () => value);
      }
    }
    final canonical = document.querySelector('link[rel="canonical"]');
    final canonicalUrl =
        _resolveUrl(baseUri, canonical?.attributes['href'] ?? '');
    if (canonicalUrl.isNotEmpty) result['canonical'] = canonicalUrl;
    final language = document.documentElement?.attributes['lang']?.trim() ?? '';
    if (language.isNotEmpty) result['language'] = language;
    return result;
  }

  List<Object?> _extractStructuredData(Document document) {
    final result = <Object?>[];
    for (final script
        in document.querySelectorAll('script[type="application/ld+json"]')) {
      final raw = script.text.trim();
      if (raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          result.addAll(decoded.take(20));
        } else {
          result.add(decoded);
        }
      } catch (_) {
        // Invalid publisher JSON-LD must not make the whole page unreadable.
      }
      if (result.length >= 20) break;
    }
    return result;
  }

  List<WebPageLink> _extractLinks(Element root, Uri baseUri) {
    final result = <WebPageLink>[];
    final seen = <String>{};
    for (final anchor in root.querySelectorAll('a[href]')) {
      if (result.length >= 160) break;
      final url = _resolveUrl(baseUri, anchor.attributes['href'] ?? '');
      final label = _cleanInline(anchor.text.isNotEmpty
          ? anchor.text
          : (anchor.attributes['aria-label'] ??
              anchor.attributes['title'] ??
              ''));
      if (url.isEmpty || label.isEmpty || !seen.add(url)) continue;
      result.add(WebPageLink(url: url, label: label));
    }
    return result;
  }

  List<WebPageImage> _extractImages(
      Document document, Element contentRoot, Uri baseUri) {
    final result = <WebPageImage>[];
    final seen = <String>{};

    void add(String rawUrl, String description) {
      if (result.length >= 60) return;
      final url = _resolveUrl(baseUri, rawUrl);
      if (url.isEmpty || !seen.add(url)) return;
      result.add(WebPageImage(
        url: url,
        description: _cleanInline(description),
      ));
    }

    for (final meta in document.querySelectorAll(
        'meta[property="og:image"], meta[name="twitter:image"]')) {
      add(meta.attributes['content'] ?? '',
          meta.attributes['property'] ?? meta.attributes['name'] ?? 'image');
    }
    for (final image in contentRoot.querySelectorAll('img')) {
      final source = image.attributes['src'] ??
          image.attributes['data-src'] ??
          image.attributes['data-original'] ??
          _firstSrcSetUrl(image.attributes['srcset'] ?? '');
      final description = [
        image.attributes['alt'],
        image.attributes['title'],
        image.attributes['aria-label']
      ]
          .whereType<String>()
          .where((value) => value.trim().isNotEmpty)
          .join(' / ');
      add(source, description);
    }
    return result;
  }

  String _renderElement(Element element) {
    final buffer = StringBuffer();
    for (final node in element.nodes) {
      _renderNode(node, buffer);
    }
    return buffer.toString();
  }

  void _renderNode(Node node, StringBuffer buffer) {
    if (node is Text) {
      final value = node.data.replaceAll(RegExp(r'\s+'), ' ');
      if (value.trim().isNotEmpty) buffer.write(value);
      return;
    }
    if (node is! Element) return;
    final tag = node.localName ?? '';
    if (tag == 'table') {
      _renderTable(node, buffer);
      return;
    }
    if (tag == 'ul' || tag == 'ol') {
      _renderList(node, buffer, ordered: tag == 'ol');
      return;
    }
    if (tag == 'pre') {
      buffer
        ..writeln()
        ..writeln('```')
        ..writeln(node.text.trimRight())
        ..writeln('```')
        ..writeln();
      return;
    }
    if (tag == 'br') {
      buffer.writeln();
      return;
    }

    final isHeading = RegExp(r'^h[1-6]$').hasMatch(tag);
    final isBlock = isHeading ||
        const {
          'p',
          'div',
          'section',
          'article',
          'header',
          'blockquote',
          'figure',
          'figcaption',
          'address',
          'details',
          'summary',
          'dl',
          'dt',
          'dd'
        }.contains(tag);
    if (isBlock) buffer.writeln();
    if (isHeading) {
      final level = int.tryParse(tag.substring(1)) ?? 2;
      buffer.write('${'#' * level} ');
    } else if (tag == 'blockquote') {
      buffer.write('> ');
    }
    for (final child in node.nodes) {
      _renderNode(child, buffer);
    }
    if (isBlock) buffer.writeln();
  }

  void _renderList(Element list, StringBuffer buffer, {required bool ordered}) {
    buffer.writeln();
    var index = 1;
    for (final item
        in list.children.where((child) => child.localName == 'li')) {
      final text = _normalizeBlockText(_renderElement(item))
          .replaceAll('\n', ' ')
          .trim();
      if (text.isEmpty) continue;
      buffer.writeln('${ordered ? '${index++}.' : '-'} $text');
    }
    buffer.writeln();
  }

  void _renderTable(Element table, StringBuffer buffer) {
    final rows = table.querySelectorAll('tr');
    if (rows.isEmpty) return;
    buffer.writeln();
    for (final row in rows.take(200)) {
      final cells = row
          .querySelectorAll('th, td')
          .map((cell) => _cleanInline(cell.text).replaceAll('|', r'\|'))
          .toList();
      if (cells.isEmpty) continue;
      buffer.writeln('| ${cells.join(' | ')} |');
    }
    buffer.writeln();
  }

  String _resolveUrl(Uri baseUri, String raw) {
    var value = raw.trim();
    if (value.startsWith('//')) value = '${baseUri.scheme}:$value';
    final parsed = Uri.tryParse(value);
    if (parsed == null) return '';
    final resolved = parsed.hasScheme ? parsed : baseUri.resolveUri(parsed);
    if (resolved.scheme != 'http' && resolved.scheme != 'https') return '';
    if (resolved.host.endsWith('duckduckgo.com') &&
        resolved.queryParameters['uddg']?.isNotEmpty == true) {
      return Uri.decodeComponent(resolved.queryParameters['uddg']!);
    }
    return resolved.toString();
  }

  String _firstSrcSetUrl(String srcSet) {
    final first = srcSet.split(',').first.trim();
    return first.split(RegExp(r'\s+')).firstOrNull ?? '';
  }

  String _cleanInline(String value) => value
      .replaceAll(RegExp(r'[\r\n\t ]+'), ' ')
      .replaceAll('\u00a0', ' ')
      .trim();

  String _normalizeBlockText(String value) => value
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n[ \t]+'), '\n')
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
