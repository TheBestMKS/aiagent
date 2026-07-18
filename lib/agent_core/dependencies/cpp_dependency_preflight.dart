import 'dart:io';

class CppDependencyAvailability {
  const CppDependencyAvailability({
    required this.openCvConfirmed,
    required this.libTorchConfirmed,
    required this.onnxRuntimeConfirmed,
    required this.inspectedEntries,
  });

  final bool openCvConfirmed;
  final bool libTorchConfirmed;
  final bool onnxRuntimeConfirmed;
  final int inspectedEntries;

  bool isConfirmed(String dependency) {
    final lower = dependency.toLowerCase();
    if (lower == 'opencv') return openCvConfirmed;
    if (lower == 'libtorch' || lower == 'torch') return libTorchConfirmed;
    if (lower == 'onnxruntime' || lower == 'onnx runtime') {
      return onnxRuntimeConfirmed;
    }
    return false;
  }

  String toPromptBlock() => '''[CPP_DEPENDENCY_PREFLIGHT]
OpenCV confirmed in portable tools: $openCvConfirmed
LibTorch confirmed in portable tools: $libTorchConfirmed
ONNX Runtime confirmed in portable tools: $onnxRuntimeConfirmed
Inspected entries: $inspectedEntries
Rules:
- A dependency marked false is NOT proven to be installed. Do not invent C:/msys64, OpenCV_DIR, CMAKE_PREFIX_PATH or another absolute path.
- Before committing the project to an unconfirmed heavy dependency, locate it in tools, download it to tools, or choose a dependency-free implementation that can actually be compiled now.
- OpenCV DNN is primarily an inference API. Do not describe cv::dnn as a complete forward/backward training framework.
- The user requested a release build, so prefer an implementable and verifiable architecture over a hypothetical framework design.
[/CPP_DEPENDENCY_PREFLIGHT]''';
}

class CppDependencyPreflight {
  const CppDependencyPreflight._();

  static bool taskLooksLikeImageMl(String text) {
    final lower = text.toLowerCase();
    final image = const <String>[
      'image',
      'picture',
      'opencv',
      'картин',
      'изображен',
      'объект',
      'computer vision',
      'компьютерн',
    ].any(lower.contains);
    final ml = const <String>[
      'model',
      'train',
      'inference',
      'нейрон',
      'модел',
      'обучен',
      'инференс',
      'классифик',
    ].any(lower.contains);
    return image && ml;
  }

  static CppDependencyAvailability probe(
    Directory toolsRoot, {
    int maxEntries = 20000,
  }) {
    var inspected = 0;
    var openCv = false;
    var libTorch = false;
    var onnx = false;
    if (!toolsRoot.existsSync()) {
      return const CppDependencyAvailability(
        openCvConfirmed: false,
        libTorchConfirmed: false,
        onnxRuntimeConfirmed: false,
        inspectedEntries: 0,
      );
    }
    final pending = <Directory>[toolsRoot];
    while (pending.isNotEmpty && inspected < maxEntries) {
      final directory = pending.removeLast();
      List<FileSystemEntity> entries;
      try {
        entries = directory.listSync(recursive: false, followLinks: false);
      } catch (_) {
        continue;
      }
      for (final entity in entries) {
        inspected++;
        if (inspected > maxEntries) break;
        if (entity is Directory) pending.add(entity);
        final lower = entity.path.replaceAll('\\', '/').toLowerCase();
        if (!openCv &&
            (lower.endsWith('/opencvconfig.cmake') ||
                lower.contains('/include/opencv2/') ||
                lower.contains('/libopencv'))) {
          openCv = true;
        }
        if (!libTorch &&
            (lower.endsWith('/torchconfig.cmake') ||
                lower.contains('/include/torch/torch.h') ||
                lower.contains('/libtorch'))) {
          libTorch = true;
        }
        if (!onnx &&
            (lower.endsWith('/onnxruntime_cxx_api.h') ||
                lower.contains('/onnxruntime/'))) {
          onnx = true;
        }
        if (openCv && libTorch && onnx) break;
      }
      if (openCv && libTorch && onnx) break;
    }
    return CppDependencyAvailability(
      openCvConfirmed: openCv,
      libTorchConfirmed: libTorch,
      onnxRuntimeConfirmed: onnx,
      inspectedEntries: inspected,
    );
  }

  static String? planBlockReason(
    String plan,
    CppDependencyAvailability availability,
  ) {
    final lower = plan.toLowerCase();
    final mentionsOpenCv = lower.contains('opencv');
    final mentionsLibTorch = lower.contains('libtorch') || lower.contains('pytorch c++');
    final mentionsOnnx = lower.contains('onnxruntime') || lower.contains('onnx runtime');

    if (mentionsOpenCv && lower.contains('dnn') && _mentionsTraining(lower)) {
      return 'DEPENDENCY_CAPABILITY_MISMATCH: план предлагает OpenCV DNN как '
          'движок полноценного обучения с forward/backward pass. cv::dnn '
          'предназначен главным образом для загрузки и инференса готовых сетей. '
          'Выбери реально обучаемую архитектуру либо реализуй небольшой '
          'самостоятельный классификатор, который можно собрать и проверить.';
    }

    final unconfirmed = <String>[];
    if (mentionsOpenCv && !availability.openCvConfirmed) unconfirmed.add('OpenCV');
    if (mentionsLibTorch && !availability.libTorchConfirmed) unconfirmed.add('LibTorch');
    if (mentionsOnnx && !availability.onnxRuntimeConfirmed) unconfirmed.add('ONNX Runtime');
    if (unconfirmed.isEmpty) return null;

    if (_containsExplicitPreflight(lower)) return null;
    return 'DEPENDENCY_PREFLIGHT_REQUIRED: план сразу выбирает '
        '${unconfirmed.join(', ')}, но зависимость не подтверждена в переносимой '
        'папке tools. Сначала добавь отдельный шаг проверки/поиска или загрузки '
        'зависимости. Если релиз нужно собрать без скачивания, выбери '
        'dependency-free вариант. Нельзя сначала написать весь проект, а затем '
        'угадывать абсолютный путь к библиотеке.';
  }

  static String? mutationPathBlockReason(String text) {
    final activeLines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .where((line) {
          final lower = line.toLowerCase();
          return lower.contains('cmake_prefix_path') ||
              lower.contains('opencv') ||
              lower.contains('torch') ||
              lower.contains('onnx');
        });
    final absolute = RegExp(r'''["']([A-Za-z]:[/\\][^"'\r\n;]+)["']''');
    for (final line in activeLines) {
      for (final match in absolute.allMatches(line)) {
        final raw = match.group(1)?.trim() ?? '';
        if (raw.isEmpty || raw.contains(r'${')) continue;
        final normalized = raw.replaceAll('/', Platform.pathSeparator);
        if (!File(normalized).existsSync() &&
            !Directory(normalized).existsSync()) {
          return 'UNVERIFIED_DEPENDENCY_PATH_BLOCKED: путь `$raw` не существует '
              'в текущей системе. Изменение CMake не выполнено. Найди реальный '
              'OpenCVConfig.cmake/TorchConfig.cmake в tools, скачай зависимость '
              'в tools или убери неподтверждённую зависимость. Не угадывай путь.';
        }
      }
    }
    return null;
  }

  static bool _mentionsTraining(String lower) => const <String>[
        'train',
        'training',
        'обуч',
        'backward',
        'градиент',
      ].any(lower.contains);

  static bool _containsExplicitPreflight(String lower) {
    final markers = const <String>[
      'проверить наличие',
      'проверка наличия',
      'list_local_tools',
      'filesystem_search',
      'download_to_tools',
      'скачать зависимость',
      'найти opencvconfig',
      'найти torchconfig',
      'найти onnxruntime',
    ];
    var preflightIndex = -1;
    for (final marker in markers) {
      final index = lower.indexOf(marker);
      if (index >= 0 && (preflightIndex < 0 || index < preflightIndex)) {
        preflightIndex = index;
      }
    }
    if (preflightIndex < 0) return false;
    final implementationMarkers = const <String>[
      'реализация кода',
      'написать main',
      'создать main',
      'подключить opencv',
      'написать основные файлы',
      'implementation',
    ];
    var implementationIndex = -1;
    for (final marker in implementationMarkers) {
      final index = lower.indexOf(marker);
      if (index >= 0 &&
          (implementationIndex < 0 || index < implementationIndex)) {
        implementationIndex = index;
      }
    }
    return implementationIndex < 0 || preflightIndex < implementationIndex;
  }
}
