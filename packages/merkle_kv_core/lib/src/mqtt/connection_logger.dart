/// Simple logging interface for the connection lifecycle manager.
/// 
/// This provides a lightweight abstraction over logging that can be 
/// configured or replaced as needed without changing the core implementation.
abstract class ConnectionLogger {
  /// Log a debug message.
  void debug(String message);
  
  /// Log an informational message.
  void info(String message);
  
  /// Log a warning message.
  void warn(String message);
  
  /// Log an error message.
  void error(String message, [Object? error, StackTrace? stackTrace]);
}

/// Default implementation that outputs to console with timestamps.
/// 
/// In production, this could be replaced with package:logging or
/// another logging framework integration.
class DefaultConnectionLogger implements ConnectionLogger {
  final String prefix;
  final bool enableDebug;
  
  const DefaultConnectionLogger({
    this.prefix = 'ConnectionLifecycle',
    this.enableDebug = true,
  });
  
  @override
  void debug(String message) {
    if (enableDebug) {
      _log('DEBUG', message);
    }
  }
  
  @override
  void info(String message) {
    _log('INFO', message);
  }
  
  @override
  void warn(String message) {
    _log('WARN', message);
  }
  
  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    _log('ERROR', message);
    if (error != null) {
      _log('ERROR', 'Error details: $error');
    }
    if (stackTrace != null) {
      _log('ERROR', 'Stack trace: $stackTrace');
    }
  }
  
  void _log(String level, String message) {
    // ignore: avoid_print
    print('[${DateTime.now().toIso8601String()}] $level $prefix: $message');
  }
}

/// Silent logger implementation for testing or when logging is disabled.
class SilentConnectionLogger implements ConnectionLogger {
  const SilentConnectionLogger();
  
  @override
  void debug(String message) {}
  
  @override
  void info(String message) {}
  
  @override
  void warn(String message) {}
  
  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {}
}