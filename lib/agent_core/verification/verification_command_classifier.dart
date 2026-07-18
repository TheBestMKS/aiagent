class VerificationCommandClassifier {
  const VerificationCommandClassifier._();

  static bool isVerificationCommand(String command) {
    final normalized = _normalize(command);
    if (normalized.isEmpty) return false;
    if (isConfigurationOnlyCommand(normalized)) return false;

    final patterns = <RegExp>[
      RegExp(r'(^|[\s\\/])flutter(?:\.bat|\.exe)?\s+(analyze|test|build)\b'),
      RegExp(r'(^|[\s\\/])dart(?:\.exe)?\s+(analyze|test|compile)\b'),
      RegExp(r'(^|[\s\\/])(pytest(?:\.exe)?|python(?:\.exe)?\s+-m\s+pytest)\b'),
      RegExp(r'(^|[\s\\/])(npm|pnpm|yarn|bun)(?:\.cmd)?\s+(run\s+)?(test|check|lint|build)\b'),
      RegExp(r'(^|[\s\\/])cargo(?:\.exe)?\s+(test|check|build|clippy)\b'),
      RegExp(r'(^|[\s\\/])go(?:\.exe)?\s+(test|vet|build)\b'),
      RegExp(r'(^|[\s\\/])dotnet(?:\.exe)?\s+(test|build|publish)\b'),
      RegExp(r'(^|[\s\\/])(mvn|mvnw|gradle|gradlew)(?:\.bat|\.cmd)?\b.*\b(test|check|build|package|verify)\b'),
      RegExp(r'(^|[\s\\/])cmake(?:\.exe)?\s+--build\b'),
      RegExp(r'(^|[\s\\/])(make|ninja|msbuild)(?:\.exe)?\b'),
      RegExp(r'(^|[\s\\/])(clang\+\+|g\+\+|cl(?:\.exe)?|rustc|gcc)(?:\.exe)?\b'),
      RegExp(r'(^|[\s\\/])(ctest|xcodebuild)(?:\.exe)?\b'),
      RegExp(r'(^|[\s\\/])swift\s+test\b'),
      RegExp(r'(^|[\s\\/])(ruff|eslint|pylint|mypy|tsc)(?:\.exe|\.cmd)?\b'),
      RegExp(r'(^|[\s\\/])(build_all|build_windows|build_web|build_android|analyze|run_tests)\.(bat|cmd)\b'),
      RegExp(r'(^|[\s\\/])build\.ps1\b'),
    ];
    return patterns.any((pattern) => pattern.hasMatch(normalized));
  }

  static bool isConfigurationOnlyCommand(String command) {
    final normalized = _normalize(command);
    if (!RegExp(r'(^|[\s"/\\])cmake(?:\.exe)?\b').hasMatch(normalized)) {
      return false;
    }
    if (normalized.contains('--build')) return false;
    return RegExp(r'(^|\s)-(?:s|b)(?:\s|$)', caseSensitive: false)
            .hasMatch(normalized) ||
        normalized.contains('cmakelists.txt');
  }

  static bool isSafeDiagnosticCommand(String command) {
    final normalized = _normalize(command);
    return RegExp(
      r'^(?:"[^"]+"|[^\s]+)\s+(?:--help|--version|-version|/\?)$',
      caseSensitive: false,
    ).hasMatch(normalized);
  }

  static String _normalize(String command) => command
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
