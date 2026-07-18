import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_constants.dart';

Widget buildAiAgentApp() => const AiAgentWebApp();

class AiAgentWebApp extends StatelessWidget {
  const AiAgentWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '$appName $appVersion',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const _WebHomeScreen(),
    );
  }
}

class _WebHomeScreen extends StatefulWidget {
  const _WebHomeScreen();

  @override
  State<_WebHomeScreen> createState() => _WebHomeScreenState();
}

class _WebHomeScreenState extends State<_WebHomeScreen> {
  final endpointController =
      TextEditingController(text: 'http://127.0.0.1:1234/v1');
  final modelController = TextEditingController();
  final projectController = TextEditingController();
  int selectedPage = 0;

  @override
  void dispose() {
    endpointController.dispose();
    modelController.dispose();
    projectController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 840;
    final body = IndexedStack(
      index: selectedPage,
      children: [
        _OverviewPage(onOpenConnection: () => setState(() => selectedPage = 1)),
        _ConnectionPage(
          endpointController: endpointController,
          modelController: modelController,
          projectController: projectController,
        ),
        const _LimitationsPage(),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(appName),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(child: Text('v$appVersion')),
          ),
        ],
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: selectedPage,
                  onDestinationSelected: (value) =>
                      setState(() => selectedPage = value),
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard),
                      label: Text('Обзор'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.hub_outlined),
                      selectedIcon: Icon(Icons.hub),
                      label: Text('Подключение'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.info_outline),
                      selectedIcon: Icon(Icons.info),
                      label: Text('Возможности'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: selectedPage,
              onDestinationSelected: (value) =>
                  setState(() => selectedPage = value),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: 'Обзор',
                ),
                NavigationDestination(
                  icon: Icon(Icons.hub_outlined),
                  selectedIcon: Icon(Icons.hub),
                  label: 'Подключение',
                ),
                NavigationDestination(
                  icon: Icon(Icons.info_outline),
                  selectedIcon: Icon(Icons.info),
                  label: 'Возможности',
                ),
              ],
            ),
    );
  }
}

class _PageFrame extends StatelessWidget {
  const _PageFrame({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 20),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewPage extends StatelessWidget {
  const _OverviewPage({required this.onOpenConnection});

  final VoidCallback onOpenConnection;

  @override
  Widget build(BuildContext context) {
    return _PageFrame(
      title: 'AI Agent для браузера',
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Web-сборка готова для размещения на локальном или обычном веб-сервере.',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Она предоставляет безопасную браузерную оболочку и параметры подключения к OpenAI-совместимому серверу. Полный доступ к файлам, процессам, локальным инструментам и llama.cpp остаётся в Windows-версии.',
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onOpenConnection,
                  icon: const Icon(Icons.settings_ethernet),
                  label: const Text('Настроить подключение'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _FeatureCard(
              icon: Icons.web,
              title: 'Адаптивный интерфейс',
              text: 'Работает на широких и мобильных экранах браузера.',
            ),
            _FeatureCard(
              icon: Icons.security,
              title: 'Безопасный режим',
              text: 'Не запрашивает прямой доступ к системным процессам.',
            ),
            _FeatureCard(
              icon: Icons.api,
              title: 'Совместимый endpoint',
              text: 'Подготовка параметров для локального API и LM Studio.',
            ),
          ],
        ),
      ],
    );
  }
}

class _ConnectionPage extends StatelessWidget {
  const _ConnectionPage({
    required this.endpointController,
    required this.modelController,
    required this.projectController,
  });

  final TextEditingController endpointController;
  final TextEditingController modelController;
  final TextEditingController projectController;

  String get configuration => '''{
  "endpoint": "${endpointController.text.trim()}",
  "model": "${modelController.text.trim()}",
  "project": "${projectController.text.trim()}",
  "appVersion": "$appVersion"
}''';

  @override
  Widget build(BuildContext context) {
    return _PageFrame(
      title: 'Параметры подключения',
      children: [
        TextField(
          controller: endpointController,
          decoration: const InputDecoration(
            labelText: 'OpenAI-совместимый endpoint',
            hintText: 'http://127.0.0.1:1234/v1',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: modelController,
          decoration: const InputDecoration(
            labelText: 'Модель',
            hintText: 'Имя модели на сервере',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: projectController,
          decoration: const InputDecoration(
            labelText: 'Название проекта',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: configuration));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Конфигурация скопирована в буфер обмена'),
                ),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('Копировать конфигурацию'),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Для прямых запросов из браузера сервер должен разрешать CORS для адреса, с которого открыта Web-версия.',
        ),
      ],
    );
  }
}

class _LimitationsPage extends StatelessWidget {
  const _LimitationsPage();

  @override
  Widget build(BuildContext context) {
    return const _PageFrame(
      title: 'Распределение возможностей',
      children: [
        _CapabilityRow(
          icon: Icons.desktop_windows,
          title: 'Windows',
          text: 'Полный режим: проекты, файлы, консоль, процессы, документы, локальные модели и инструменты.',
        ),
        SizedBox(height: 12),
        _CapabilityRow(
          icon: Icons.android,
          title: 'Android',
          text: 'Мобильный интерфейс, доступные каталоги устройства, WebView и сетевые профили.',
        ),
        SizedBox(height: 12),
        _CapabilityRow(
          icon: Icons.language,
          title: 'Web',
          text: 'Безопасная браузерная оболочка без прямого запуска системных команд и произвольного чтения файлов.',
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 30),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(text),
            ],
          ),
        ),
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(text),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      ),
    );
  }
}
