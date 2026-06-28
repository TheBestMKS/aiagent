class ConsoleQuickAction {
  ConsoleQuickAction(this.name, this.command, {this.cwd = '.'});
  String name;
  String command;
  String cwd;
}

class WebQuickAction {
  WebQuickAction(this.name, this.url);
  String name;
  String url;
}

class ConsoleRunRequest {
  const ConsoleRunRequest(
      {required this.command, this.cwd = '.', this.newTab = true});
  final String command;
  final String cwd;
  final bool newTab;
}

class BuildArtifactInfo {
  const BuildArtifactInfo({required this.path, required this.exists});
  final String path;
  final bool exists;
}

class AgentPermissionRequest {
  const AgentPermissionRequest(
      {required this.toolName,
      required this.details,
      required this.reason,
      required this.critical});
  final String toolName;
  final String details;
  final String reason;
  final bool critical;
}

class RuntimeModelLimits {
  const RuntimeModelLimits(
      {required this.contextTokens,
      required this.outputTokens,
      required this.source});
  final int? contextTokens;
  final int? outputTokens;
  final String source;
}

class HeavyTaskStatus {
  const HeavyTaskStatus(
      {required this.title,
      required this.detail,
      required this.progress,
      this.remainingSeconds = 0,
      this.canContinue = false});
  final String title;
  final String detail;
  final double? progress;
  final int remainingSeconds;
  final bool canContinue;
}

class OffsetLike {
  const OffsetLike(this.dx, this.dy);
  final double dx;
  final double dy;
}

class LlamaBackendVariant {
  const LlamaBackendVariant({
    required this.id,
    required this.platformKey,
    required this.backend,
    required this.label,
    required this.assetMatchers,
    this.extraAssetMatchers = const [],
    this.speedRank = 0,
  });

  final String id;
  final String platformKey;
  final String backend;
  final String label;
  final List<String> assetMatchers;
  final List<String> extraAssetMatchers;
  final int speedRank;
}
