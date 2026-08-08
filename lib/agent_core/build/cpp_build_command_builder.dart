class CppBuildCommandBuilder {
  const CppBuildCommandBuilder._();

  static String windowsDirect({
    required String compiler,
    required String sourceArgs,
    String executable = r'build\app.exe',
    String compilerFlags = '-std=c++17 -O2',
  }) {
    final prepare =
        '(if not exist build mkdir build) & (if exist $executable del /q $executable)';
    return '$prepare & $compiler $compilerFlags $sourceArgs -o $executable '
        '&& if exist $executable ($executable) else '
        '(echo BUILD_ARTIFACT_MISSING: $executable && exit /b 2)';
  }

  static String windowsMsvc({
    required String compiler,
    required String sourceArgs,
    String executable = r'build\app.exe',
  }) {
    final prepare =
        '(if not exist build mkdir build) & (if exist $executable del /q $executable)';
    return '$prepare & $compiler /nologo /EHsc /std:c++17 $sourceArgs '
        '/Fe:$executable && if exist $executable ($executable) else '
        '(echo BUILD_ARTIFACT_MISSING: $executable && exit /b 2)';
  }
}
