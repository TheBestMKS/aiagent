class AdaptiveAgentBudget {
  AdaptiveAgentBudget({
    required int configuredWindow,
    this.extensionSize = 40,
    this.maximumIterations = 2000,
    this.maximumRuntime = const Duration(hours: 12),
  })  : configuredWindow = configuredWindow.clamp(8, 500).toInt(),
        currentLimit = configuredWindow.clamp(8, 500).toInt(),
        startedAt = DateTime.now();

  final int configuredWindow;
  final int extensionSize;
  final int maximumIterations;
  final Duration maximumRuntime;
  final DateTime startedAt;
  int currentLimit;
  int _lastProgressRevision = 0;
  int _lastProgressIteration = 0;

  void observe({required int iteration, required int progressRevision}) {
    if (progressRevision > _lastProgressRevision) {
      _lastProgressRevision = progressRevision;
      _lastProgressIteration = iteration;
    }
  }

  bool get runtimeExpired =>
      DateTime.now().difference(startedAt) >= maximumRuntime;

  bool canRunIteration(int iteration) =>
      iteration <= currentLimit &&
      iteration <= maximumIterations &&
      !runtimeExpired;

  bool extendIfProgressing({
    required int iteration,
    required int progressRevision,
    required bool taskComplete,
  }) {
    observe(iteration: iteration, progressRevision: progressRevision);
    if (taskComplete || runtimeExpired || currentLimit >= maximumIterations) {
      return false;
    }
    final recentProgress = progressRevision > 0 &&
        iteration - _lastProgressIteration <= configuredWindow.clamp(8, 40);
    if (!recentProgress) return false;
    currentLimit = (currentLimit + extensionSize)
        .clamp(configuredWindow, maximumIterations)
        .toInt();
    return true;
  }

  String statusSummary(
      {required int iteration, required int progressRevision}) {
    final elapsed = DateTime.now().difference(startedAt);
    return 'ADAPTIVE_BUDGET: iteration=$iteration; current_limit=$currentLimit; '
        'hard_limit=$maximumIterations; progress_revision=$progressRevision; '
        'last_progress_iteration=$_lastProgressIteration; '
        'elapsed_seconds=${elapsed.inSeconds}; '
        'runtime_expired=$runtimeExpired';
  }
}
