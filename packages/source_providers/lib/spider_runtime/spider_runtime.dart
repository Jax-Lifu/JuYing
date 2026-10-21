/// QuickJS Isolated Spider Sandbox Environment (Section 6.1 source_providers/spider_runtime).
abstract interface class ISpiderRuntime {
  Future<void> initialize();
  Future<String> evaluateScript(String script,
      {Duration timeout = const Duration(seconds: 6)});
  Future<void> dispose();
}
