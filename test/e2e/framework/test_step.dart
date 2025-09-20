/// Base class for all test steps in the E2E framework
/// 
/// This abstract class defines the interface for all test steps that can be
/// executed as part of E2E scenarios. Each step must implement the execute method
/// to perform its specific testing logic.
abstract class TestStep {
  final String description;
  final Duration? timeout;
  
  TestStep({
    required this.description,
    this.timeout,
  });
  
  /// Execute the test step with provided context
  /// 
  /// Parameters:
  /// - appiumDriver: WebDriver instance for app interaction
  /// - lifecycleManager: Platform lifecycle management
  /// - networkManager: Network state management
  Future<void> execute({
    dynamic appiumDriver,
    dynamic lifecycleManager,
    dynamic networkManager,
  });
  
  @override
  String toString() => 'TestStep($description)';
}