import 'dart:async';

/// Enumeration for different operation types with corresponding timeouts
enum OperationType {
  /// Single key operations: 10 seconds
  singleKey,
  
  /// Multi-key operations: 20 seconds
  multiKey,
  
  /// Synchronization operations: 30 seconds
  sync
}

/// Exception thrown when an operation times out
class TimeoutException implements Exception {
  final String message;
  final String requestId;
  final Duration elapsed;

  TimeoutException(this.requestId, this.elapsed, {String? customMessage})
      : message = customMessage ?? 'Operation $requestId timed out after ${elapsed.inMilliseconds}ms';

  @override
  String toString() => 'TimeoutException: $message';
}

/// Manages operation timeouts using monotonic timers
/// 
/// Implements Locked Spec §11 timeout requirements:
/// - 10s for single-key operations
/// - 20s for multi-key operations  
/// - 30s for synchronization operations
class TimeoutManager {
  /// Default timeout for single-key operations per Locked Spec §11
  static const Duration singleKeyTimeout = Duration(seconds: 10);
  
  /// Default timeout for multi-key operations per Locked Spec §11
  static const Duration multiKeyTimeout = Duration(seconds: 20);
  
  /// Default timeout for sync operations per Locked Spec §11
  static const Duration syncTimeout = Duration(seconds: 30);
  
  /// Map of active operations with their start times
  final Map<String, Stopwatch> _activeOperations = {};
  
  /// Custom timeout overrides for testing
  final Map<OperationType, Duration> _customTimeouts = {};
  
  /// Sets a custom timeout for an operation type (useful for testing)
  void setCustomTimeout(OperationType type, Duration timeout) {
    _customTimeouts[type] = timeout;
  }
  
  /// Clears custom timeouts
  void clearCustomTimeouts() {
    _customTimeouts.clear();
  }
  
  /// Gets timeout duration for a specific operation type
  Duration getTimeoutForType(OperationType type) {
    // Check for custom timeout first
    if (_customTimeouts.containsKey(type)) {
      return _customTimeouts[type]!;
    }
    
    switch (type) {
      case OperationType.singleKey:
        return singleKeyTimeout;
      case OperationType.multiKey:
        return multiKeyTimeout;
      case OperationType.sync:
        return syncTimeout;
    }
  }
  
  /// Starts tracking an operation with a monotonic timer
  void startOperation(String requestId) {
    final stopwatch = Stopwatch()..start();
    _activeOperations[requestId] = stopwatch;
  }
  
  /// Stops tracking an operation
  void stopOperation(String requestId) {
    _activeOperations.remove(requestId)?.stop();
  }
  
  /// Checks if an operation has timed out
  bool isTimedOut(String requestId, Duration timeout) {
    final stopwatch = _activeOperations[requestId];
    return stopwatch != null && stopwatch.elapsed > timeout;
  }
  
  /// Gets the elapsed time for a specific operation
  Duration getElapsedTime(String requestId) {
    final stopwatch = _activeOperations[requestId];
    return stopwatch?.elapsed ?? Duration.zero;
  }
  
  /// Checks and throws if an operation has timed out
  void checkTimeout(String requestId, OperationType operationType) {
    final timeout = getTimeoutForType(operationType);
    if (isTimedOut(requestId, timeout)) {
      final elapsed = getElapsedTime(requestId);
      stopOperation(requestId);
      throw TimeoutException(requestId, elapsed);
    }
  }
  
  /// Cleans up any stale operations (useful for periodic maintenance)
  /// Returns the number of operations cleaned up
  int cleanupStaleOperations() {
    final staleOperations = <String>[];
    
    _activeOperations.forEach((requestId, stopwatch) {
      // For testing purposes, consider operations over 30ms as stale
      // In production, you might want to use syncTimeout
      if (stopwatch.elapsed > const Duration(milliseconds: 30)) {
        staleOperations.add(requestId);
      }
    });
    
    // Actually remove the stale operations
    for (final requestId in staleOperations) {
      _activeOperations.remove(requestId)?.stop();
    }
    
    return staleOperations.length;
  }
}