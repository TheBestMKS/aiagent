import 'package:flutter_test/flutter_test.dart';
import 'package:ii_agent/agent_core/retrieval/web_content_extractor.dart';

void main() {
  const extractor = WebContentExtractor();

  test('extracts semantic article content and drops page chrome', () {
    const source = '''<!doctype html>
<html lang="ru"><head>
  <title>Rundll32 reference</title>
  <meta name="description" content="Technical reference">
  <link rel="canonical" href="/reference/rundll32">
  <script type="application/ld+json">{"@type":"TechArticle","name":"Rundll32"}</script>
</head><body>
  <nav><a href="/home">Home navigation</a></nav>
  <main><article>
    <h1>Rundll32</h1>
    <p>Rundll32 loads and runs exported functions from dynamic-link libraries.</p>
    <h2>Syntax</h2>
    <pre>rundll32.exe module,entry</pre>
    <ul><li>Inspect the full command line.</li><li>Verify the referenced DLL.</li></ul>
    <table><tr><th>Field</th><th>Meaning</th></tr><tr><td>Module</td><td>DLL path</td></tr></table>
    <a href="details">Detailed reference</a>
    <img src="/images/example.png" alt="Command example">
  </article></main>
  <footer>Cookie policy and unrelated footer text</footer>
</body></html>''';

    final page = extractor.extract(
        source, Uri.parse('https://example.test/docs/index.html'));

    expect(page.title, 'Rundll32 reference');
    expect(page.text, contains('# Rundll32'));
    expect(page.text, contains('```'));
    expect(page.text, contains('| Field | Meaning |'));
    expect(page.text, isNot(contains('Cookie policy')));
    expect(page.text, isNot(contains('Home navigation')));
    expect(
        page.metadata['canonical'], 'https://example.test/reference/rundll32');
    expect(page.structuredData, isNotEmpty);
    expect(page.links.single.url, 'https://example.test/docs/details');
    expect(page.images.single.url, 'https://example.test/images/example.png');
    expect(page.qualityScore, greaterThan(0));
  });

  test('parses search result links and snippets using the DOM', () {
    const source = '''
<div class="result">
  <h2><a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.test%2Fone">First result</a></h2>
  <div class="result__snippet">Useful first snippet.</div>
</div>
<div class="result">
  <h2><a class="result__a" href="https://example.test/two">Second result</a></h2>
  <div class="result__snippet">Useful second snippet.</div>
</div>''';
    final hits = extractor.extractSearchResults(
        source, Uri.parse('https://duckduckgo.com/html/'));

    expect(hits, hasLength(2));
    expect(hits.first.url, 'https://example.test/one');
    expect(hits.first.snippet, contains('Useful first snippet'));
  });
}
