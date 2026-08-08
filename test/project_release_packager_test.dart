import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ii_agent/agent_core/release/project_release_packager.dart';

void main() {
  test('release package contains metadata source artifact and valid checksums',
      () async {
    final root = await Directory.systemTemp.createTemp('aia_release_');
    addTearDown(() => root.delete(recursive: true));
    await Directory('${root.path}${Platform.pathSeparator}src')
        .create(recursive: true);
    await File('${root.path}${Platform.pathSeparator}src'
            '${Platform.pathSeparator}main.dart')
        .writeAsString('void main() => print("ok");', encoding: utf8);
    await Directory('${root.path}${Platform.pathSeparator}build')
        .create(recursive: true);
    final artifact = File('${root.path}${Platform.pathSeparator}build'
        '${Platform.pathSeparator}Demo.exe');
    await artifact.writeAsBytes([1, 2, 3, 4, 5]);

    const packager = ProjectReleasePackager();
    final result = await packager.package(
      projectRoot: root,
      request: const ProjectReleaseRequest(
        programName: 'Demo',
        version: '1.2.3',
        platform: 'win',
        architecture: 'x64',
        artifactPaths: ['build/Demo.exe'],
        changeEnglish:
            '# Changes\n\nVersion 1.2.3 adds the tested application release.',
        changeRussian:
            '# Изменения\n\nВерсия 1.2.3 добавляет проверенный выпуск приложения.',
        readmeEnglish:
            '# Demo\n\nA tested demo application. Run Demo.exe on Windows x64.',
        readmeRussian:
            '# Demo\n\nПроверенное демонстрационное приложение. Запустите Demo.exe в Windows x64.',
      ),
    );

    expect(result.directory.path, endsWith('Demo_1.2.3'));
    expect(
        result.files,
        containsAll(<String>[
          'SHA256SUMS.txt',
          'CHANGE_en.md',
          'CHANGE_ru.md',
          'README_en.md',
          'README_ru.md',
          'source_1.2.3.zip',
          'Demo_1.2.3_win_x64.exe',
        ]));
    final sourceBytes = await File(
      '${result.directory.path}${Platform.pathSeparator}source_1.2.3.zip',
    ).readAsBytes();
    final source = ZipDecoder().decodeBytes(sourceBytes);
    final names = source.files.map((file) => file.name).toList();
    expect(names, contains('src/main.dart'));
    expect(names.any((name) => name.startsWith('release/')), isFalse);
    expect(names.any((name) => name.startsWith('.cppagent/')), isFalse);

    final checksumFile = File(
      '${result.directory.path}${Platform.pathSeparator}SHA256SUMS.txt',
    );
    final checksumText = await checksumFile.readAsString(encoding: utf8);
    final copiedArtifact = File(
      '${result.directory.path}${Platform.pathSeparator}'
      'Demo_1.2.3_win_x64.exe',
    );
    final digest =
        (await sha256.bind(copiedArtifact.openRead()).first).toString();
    expect(checksumText, contains('$digest  Demo_1.2.3_win_x64.exe'));
  });
}
