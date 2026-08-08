import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ii_agent/agent_core/build/project_build_recipe.dart';

void main() {
  test('detects Node scripts and uses project-native checks', () async {
    final root = await Directory.systemTemp.createTemp('aia_node_recipe_');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}${Platform.pathSeparator}package.json')
        .writeAsString('''
{"scripts":{"lint":"eslint .","test":"node --test","build":"vite build"}}
''');

    final recipe = const ProjectBuildRecipeDetector().detect(
      root,
      executables: const {'npm': 'npm.cmd'},
      isExecutableAvailable: (_) => true,
      windows: true,
    );

    expect(recipe.ecosystem, ProjectEcosystem.node);
    expect(recipe.verificationCommands, contains('npm.cmd run lint'));
    expect(recipe.verificationCommands, contains('npm.cmd test'));
    expect(recipe.buildCommands, contains('npm.cmd run build'));
    expect(recipe.missingExecutables, isEmpty);
  });

  test('plain C recipe creates build directory before compiling', () async {
    final root = await Directory.systemTemp.createTemp('aia_c_recipe_');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}${Platform.pathSeparator}main.c')
        .writeAsString('int main(void) { return 0; }');

    final recipe = const ProjectBuildRecipeDetector().detect(
      root,
      executables: const {'gcc': 'gcc.exe'},
      isExecutableAvailable: (_) => true,
      windows: true,
    );

    expect(recipe.ecosystem, ProjectEcosystem.c);
    expect(recipe.preferredVerificationCommand,
        startsWith('if not exist build mkdir build && gcc.exe'));
    expect(recipe.preferredVerificationCommand, contains('-std=c11'));
  });
}
