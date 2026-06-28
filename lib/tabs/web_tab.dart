import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile_webview;
import 'package:webview_windows/webview_windows.dart' as win_webview;

import '../controllers/agent_controller.dart';
import '../core/app_constants.dart';
import '../core/runtime_types.dart';
import '../utils/html_utils.dart';

class WebSession {
  WebSession({
    required this.name,
    this.address = 'https://example.com',
    this.content = '',
    this.source = '',
    this.rendered = '',
    this.showSource = false,
  }) {
    addressController.text = address;
  }

  String name;
  String address;
  String content;
  String source;
  String rendered;
  bool showSource;
  final TextEditingController addressController = TextEditingController();

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        'content': content,
        'source': source,
        'rendered': rendered,
        'showSource': showSource,
      };

  static WebSession fromJson(Map<String, dynamic> json) => WebSession(
        name: json['name']?.toString() ?? 'Web',
        address: json['address']?.toString() ?? 'https://example.com',
        content: json['content']?.toString() ?? '',
        source: json['source']?.toString() ?? '',
        rendered: json['rendered']?.toString() ?? '',
        showSource: json['showSource'] == true,
      );

  void dispose() => addressController.dispose();
}

class WebTab extends StatefulWidget {
  const WebTab({super.key, required this.controller});

  final AgentController controller;

  @override
  State<WebTab> createState() => _WebTabState();
}

class _WebTabState extends State<WebTab> {
  final List<WebSession> sessions = [WebSession(name: 'Web 1')];
  final List<WebQuickAction> quickActions = [
    WebQuickAction('localhost:1234', 'http://127.0.0.1:1234')
  ];
  final List<StreamSubscription<dynamic>> webviewSubscriptions = [];
  final ScrollController verticalScrollController = ScrollController();
  mobile_webview.WebViewController? mobileWebViewController;
  win_webview.WebviewController? windowsWebViewController;
  int selected = 0;
  bool loading = false;
  bool showQuickPanel = false;
  bool stateLoaded = false;
  bool nativeWebViewReady = false;
  String nativeWebViewError = '';

  WebSession get current =>
      sessions[selected.clamp(0, sessions.length - 1).toInt()];

  @override
  void initState() {
    super.initState();
    widget.controller.webOpener = openFromController;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(initializeNativeWebView().then((_) => loadState()));
      final pending = widget.controller.takePendingWebUrl();
      if (pending != null) unawaited(loadUrl(pending));
    });
  }

  @override
  void didUpdateWidget(covariant WebTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller.webOpener != null)
        oldWidget.controller.webOpener = null;
      widget.controller.webOpener = openFromController;
    }
  }

  @override
  void dispose() {
    if (widget.controller.webOpener != null) widget.controller.webOpener = null;
    unawaited(saveState());
    for (final subscription in webviewSubscriptions) {
      unawaited(subscription.cancel());
    }
    final windowsController = windowsWebViewController;
    if (windowsController != null) unawaited(windowsController.dispose());
    for (final session in sessions) {
      session.dispose();
    }
    verticalScrollController.dispose();
    super.dispose();
  }

  Future<void> initializeNativeWebView() async {
    if (nativeWebViewReady || nativeWebViewError.isNotEmpty) return;
    try {
      if (Platform.isAndroid) {
        final controller = mobile_webview.WebViewController()
          ..setJavaScriptMode(mobile_webview.JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.transparent)
          ..setNavigationDelegate(
            mobile_webview.NavigationDelegate(
              onPageStarted: (url) {
                if (!mounted) return;
                setState(() {
                  loading = true;
                  current.address = url;
                  current.addressController.text = url;
                });
                markStateChanged();
              },
              onPageFinished: (url) {
                if (!mounted) return;
                setState(() {
                  loading = false;
                  current.address = url;
                  current.addressController.text = url;
                });
                markStateChanged();
              },
              onWebResourceError: (error) {
                if (!mounted) return;
                setState(() {
                  loading = false;
                  current.content =
                      'Ошибка WebView: ${error.errorCode} ${error.description}';
                });
              },
            ),
          );
        mobileWebViewController = controller;
        nativeWebViewReady = true;
      } else if (Platform.isWindows) {
        final version = await win_webview.WebviewController.getWebViewVersion();
        if (version == null || version.trim().isEmpty) {
          nativeWebViewError =
              'WebView2 Runtime не установлен. Используется текстовый просмотр HTML.';
          return;
        }
        final controller = win_webview.WebviewController();
        await controller.initialize();
        await controller.setPopupWindowPolicy(
            win_webview.WebviewPopupWindowPolicy.sameWindow);
        webviewSubscriptions.add(controller.url.listen((url) {
          if (!mounted || url.trim().isEmpty) return;
          setState(() {
            current.address = url;
            current.addressController.text = url;
          });
          markStateChanged();
        }));
        webviewSubscriptions.add(controller.loadingState.listen((state) {
          if (!mounted) return;
          setState(() => loading = state == win_webview.LoadingState.loading);
        }));
        windowsWebViewController = controller;
        nativeWebViewReady = true;
      } else {
        nativeWebViewError =
            'На этой платформе встроенный WebView не подключен. Используется текстовый просмотр HTML.';
      }
    } on PlatformException catch (e) {
      nativeWebViewError =
          'WebView недоступен: ${e.message ?? e.code}. Используется текстовый просмотр HTML.';
    } catch (e) {
      nativeWebViewError =
          'WebView недоступен: $e. Используется текстовый просмотр HTML.';
    }
    if (mounted) setState(() {});
  }

  void openFromController(String url) {
    if (!mounted) return;
    if (sessions.isEmpty) addSession();
    setState(() => selected = sessions.length - 1);
    unawaited(loadUrl(url));
  }

  Future<void> loadState() async {
    if (stateLoaded) return;
    stateLoaded = true;
    final data = await widget.controller.loadProjectUiStateSection('web');
    if (!mounted || data.isEmpty) return;
    final loadedSessions = (data['sessions'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((m) => WebSession.fromJson(
            m.map((key, value) => MapEntry(key.toString(), value))))
        .toList(growable: false);
    final loadedQuick = (data['quickActions'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((m) {
          final map = m.map((key, value) => MapEntry(key.toString(), value));
          return WebQuickAction(
              map['name']?.toString() ?? 'URL', map['url']?.toString() ?? '');
        })
        .where((a) => a.url.trim().isNotEmpty)
        .toList(growable: false);
    setState(() {
      for (final session in sessions) {
        session.dispose();
      }
      sessions
        ..clear()
        ..addAll(loadedSessions.isEmpty
            ? [WebSession(name: 'Web 1')]
            : loadedSessions);
      quickActions
        ..clear()
        ..addAll(loadedQuick.isEmpty
            ? [WebQuickAction('localhost:1234', 'http://127.0.0.1:1234')]
            : loadedQuick);
      selected = (int.tryParse(data['selected']?.toString() ?? '') ?? 0)
          .clamp(0, sessions.length - 1)
          .toInt();
      showQuickPanel = data['showQuickPanel'] == true;
    });
    if (nativeWebViewReady && current.address.trim().isNotEmpty) {
      unawaited(loadUrl(current.address));
    }
  }

  Future<void> saveState() async {
    await widget.controller.saveProjectUiStateSection('web', {
      'selected': selected,
      'showQuickPanel': showQuickPanel,
      'sessions': sessions.map((s) => s.toJson()).toList(),
      'quickActions':
          quickActions.map((a) => {'name': a.name, 'url': a.url}).toList(),
    });
  }

  void markStateChanged() => unawaited(saveState());

  void syncGeneratedQuickActions() {
    for (final generated in widget.controller.generatedWebQuickActions) {
      final exists = quickActions.any((a) => a.url == generated.url);
      if (!exists) {
        quickActions.add(WebQuickAction(generated.name, generated.url));
        markStateChanged();
      }
    }
  }

  Future<void> loadUrl(String raw) async {
    var url = raw.trim();
    if (url.isEmpty) return;
    if (!url.contains('://') && !url.startsWith('file:')) url = 'https://$url';
    setState(() {
      loading = true;
      current.address = url;
      current.addressController.text = url;
      current.content = 'Загрузка $url ...';
    });
    markStateChanged();
    if (!current.showSource) {
      if (!nativeWebViewReady && nativeWebViewError.isEmpty) {
        await initializeNativeWebView();
      }
      if (nativeWebViewReady) {
        try {
          if (Platform.isAndroid && mobileWebViewController != null) {
            await mobileWebViewController!.loadRequest(Uri.parse(url));
          } else if (Platform.isWindows && windowsWebViewController != null) {
            await windowsWebViewController!.loadUrl(url);
          }
          widget.controller.ensureWebQuickLaunch(
              Uri.parse(url).host.isEmpty ? url : Uri.parse(url).host, url);
          markStateChanged();
          return;
        } catch (e) {
          setState(() => current.content =
              'WebView не смог открыть $url\n$e\n\nПробую текстовый режим...');
        }
      }
    }
    try {
      final uri = Uri.parse(url);
      String text;
      int status = 200;
      if (uri.scheme == 'file') {
        text = await File(uri.toFilePath()).readAsString(encoding: utf8);
      } else {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 15);
        final request = await client.getUrl(uri);
        request.headers.set(
            HttpHeaders.userAgentHeader, 'Mozilla/5.0 AiAgent/$appVersion');
        request.headers.set(HttpHeaders.acceptHeader,
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
        final response =
            await request.close().timeout(const Duration(seconds: 60));
        status = response.statusCode;
        text = await utf8.decodeStream(response);
        client.close(force: true);
      }
      setState(() {
        current.source = text;
        current.rendered =
            renderHtmlLikeBrowser(text, url: url, status: status);
        current.content =
            current.showSource ? current.source : current.rendered;
      });
      widget.controller.ensureWebQuickLaunch(
          Uri.parse(url).host.isEmpty ? url : Uri.parse(url).host, url);
    } catch (e) {
      setState(() => current.content = 'Ошибка открытия $url\n$e');
    } finally {
      if (mounted) setState(() => loading = false);
      markStateChanged();
    }
  }

  void addSession({WebSession? from}) {
    setState(() {
      final session = WebSession(
        name:
            from == null ? 'Web ${sessions.length + 1}' : '${from.name} копия',
        address: from?.address ?? 'https://example.com',
        content: from?.content ?? '',
        source: from?.source ?? '',
        rendered: from?.rendered ?? '',
        showSource: from?.showSource ?? false,
      );
      sessions.add(session);
      selected = sessions.length - 1;
    });
    markStateChanged();
  }

  Future<void> showSessionMenu(TapDownDetails details, int index) async {
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          details.globalPosition.dx,
          details.globalPosition.dy,
          details.globalPosition.dx,
          details.globalPosition.dy),
      items: const [
        PopupMenuItem(value: 'duplicate', child: Text('Дублировать')),
        PopupMenuItem(value: 'rename', child: Text('Переименовать')),
        PopupMenuItem(value: 'delete', child: Text('Удалить')),
      ],
    );
    if (value == 'duplicate') addSession(from: sessions[index]);
    if (value == 'rename') {
      final name = await askText(context, 'Переименовать вкладку', 'Название',
          initial: sessions[index].name);
      if (name != null && name.trim().isNotEmpty) {
        setState(() => sessions[index].name = name.trim());
        markStateChanged();
      }
    }
    if (value == 'delete' && sessions.length > 1) {
      setState(() {
        sessions[index].dispose();
        sessions.removeAt(index);
        selected = selected.clamp(0, sessions.length - 1).toInt();
      });
      markStateChanged();
    }
  }

  Future<void> showQuickActionMenu(TapDownDetails details, int index) async {
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          details.globalPosition.dx,
          details.globalPosition.dy,
          details.globalPosition.dx,
          details.globalPosition.dy),
      items: const [
        PopupMenuItem(value: 'edit', child: Text('Изменить')),
        PopupMenuItem(
            value: 'open_external', child: Text('Открыть в браузере ОС')),
        PopupMenuItem(value: 'delete', child: Text('Удалить')),
      ],
    );
    if (value == 'edit') {
      final name = await askText(context, 'Название кнопки', 'Название',
          initial: quickActions[index].name);
      if (name == null) return;
      final url = await askText(context, 'Адрес', 'URL',
          initial: quickActions[index].url);
      if (url == null) return;
      setState(() {
        quickActions[index].name = name;
        quickActions[index].url = url;
      });
      markStateChanged();
    }
    if (value == 'open_external') {
      await widget.controller.openExternalUrl(quickActions[index].url);
    }
    if (value == 'delete') {
      setState(() => quickActions.removeAt(index));
      markStateChanged();
    }
  }

  Widget quickPanel() {
    syncGeneratedQuickActions();
    return SizedBox(
      width: 240,
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          Row(children: [
            const Expanded(
                child: Text('Быстрые адреса',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            IconButton(
              tooltip: 'Добавить',
              onPressed: () async {
                final name =
                    await askText(context, 'Название кнопки', 'Название');
                if (name == null) return;
                final url = await askText(context, 'Адрес', 'URL');
                if (url == null) return;
                setState(() => quickActions.add(WebQuickAction(name, url)));
                markStateChanged();
              },
              icon: const Icon(Icons.add),
            ),
          ]),
          for (var i = 0; i < quickActions.length; i++)
            GestureDetector(
              onSecondaryTapDown: (details) => showQuickActionMenu(details, i),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: OutlinedButton(
                  onPressed: () => unawaited(loadUrl(quickActions[i].url)),
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(quickActions[i].name,
                          overflow: TextOverflow.ellipsis)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _browserSurface() {
    if (!current.showSource && nativeWebViewReady) {
      final Widget webview = Platform.isAndroid &&
              mobileWebViewController != null
          ? mobile_webview.WebViewWidget(controller: mobileWebViewController!)
          : Platform.isWindows && windowsWebViewController != null
              ? win_webview.Webview(windowsWebViewController!)
              : _textBrowserSurface();
      return Stack(
        children: [
          Positioned.fill(child: webview),
          if (loading)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      );
    }
    return _textBrowserSurface();
  }

  Widget _textBrowserSurface() {
    final emptyText = nativeWebViewError.isNotEmpty
        ? nativeWebViewError
        : 'Введите адрес и нажмите "Открыть".';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8)),
      child: Scrollbar(
        controller: verticalScrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: verticalScrollController,
          child: SelectableText(
              current.content.isEmpty ? emptyText : current.content),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    syncGeneratedQuickActions();
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 900;
      final main = Expanded(
        child: Column(
          children: [
            Material(
              elevation: 1,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  if (narrow)
                    IconButton(
                      onPressed: () {
                        setState(() => showQuickPanel = !showQuickPanel);
                        markStateChanged();
                      },
                      icon: const Icon(Icons.bookmarks),
                      tooltip: 'Быстрые адреса',
                    ),
                  for (var i = 0; i < sessions.length; i++)
                    GestureDetector(
                      onSecondaryTapDown: (details) =>
                          showSessionMenu(details, i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 6),
                        child: ChoiceChip(
                          label: Text(sessions[i].name),
                          selected: selected == i,
                          onSelected: (_) {
                            setState(() => selected = i);
                            if (nativeWebViewReady &&
                                !current.showSource &&
                                current.address.trim().isNotEmpty) {
                              unawaited(loadUrl(current.address));
                            }
                            markStateChanged();
                          },
                        ),
                      ),
                    ),
                  IconButton(
                      onPressed: () => addSession(),
                      icon: const Icon(Icons.add),
                      tooltip: 'Новая вкладка')
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: current.addressController,
                    decoration: const InputDecoration(
                        labelText: 'Адрес',
                        border: OutlineInputBorder(),
                        isDense: true),
                    onChanged: (_) => markStateChanged(),
                    onSubmitted: loadUrl,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                    tooltip: current.showSource ? 'Страница' : 'HTML',
                    onPressed: () {
                      setState(() {
                        current.showSource = !current.showSource;
                        current.content = current.showSource
                            ? current.source
                            : current.rendered;
                      });
                      markStateChanged();
                      unawaited(loadUrl(current.addressController.text));
                    },
                    icon: Icon(current.showSource ? Icons.web : Icons.code)),
                const SizedBox(width: 8),
                IconButton.outlined(
                    tooltip: 'Открыть в браузере ОС',
                    onPressed: () => unawaited(
                        widget.controller.openExternalUrl(current.address)),
                    icon: const Icon(Icons.open_in_browser)),
                const SizedBox(width: 8),
                FilledButton.icon(
                    onPressed: loading
                        ? null
                        : () =>
                            unawaited(loadUrl(current.addressController.text)),
                    icon: const Icon(Icons.public),
                    label: Text(loading ? 'Загрузка' : 'Открыть')),
              ]),
            ),
            Expanded(child: _browserSurface()),
            if (DateTime.now().microsecondsSinceEpoch < 0)
              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(8)),
                  child: Scrollbar(
                    controller: verticalScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: verticalScrollController,
                      child: SelectableText(current.content.isEmpty
                          ? 'Введите адрес и нажмите “Открыть”. Для сайтов, которым нужен настоящий движок Chromium/WebView2, используйте кнопку открытия в браузере ОС.'
                          : current.content),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
      if (narrow) {
        return Row(children: [
          main,
          if (showQuickPanel) const VerticalDivider(width: 1),
          if (showQuickPanel) quickPanel(),
        ]);
      }
      return Row(
          children: [main, const VerticalDivider(width: 1), quickPanel()]);
    });
  }
}
