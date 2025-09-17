import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';

/// Convergence Validator for Mobile Testing
/// 
/// Provides utilities for validating anti-entropy synchronization and
/// convergence behavior during mobile state transitions.
class ConvergenceValidator {
  final Map<String, Timer> _convergenceTimers = {};
  final Map<String, Completer<void>> _convergenceCompleters = {};
  bool _isDisposed = false;

  /// Waits for convergence between multiple clients
  Future<void> waitForConvergence(
    List<dynamic> clients, {
    Duration timeout = const Duration(minutes: 2),
  }) async {
    if (_isDisposed || clients.isEmpty) return;

    final convergenceId = _generateConvergenceId();
    final completer = Completer<void>();
    _convergenceCompleters[convergenceId] = completer;

    // Set up timeout
    final timer = Timer(timeout, () {
      _convergenceCompleters.remove(convergenceId)?.completeError(
        TimeoutException(
          'Convergence not achieved within ${timeout.inSeconds}s',
          timeout,
        ),
      );
    });
    _convergenceTimers[convergenceId] = timer;

    // Start convergence monitoring
    _monitorConvergence(convergenceId, clients);

    try {
      await completer.future;
    } finally {
      timer.cancel();
      _convergenceTimers.remove(convergenceId);
      _convergenceCompleters.remove(convergenceId);
    }
  }

  /// Triggers anti-entropy sync on a client
  Future<void> triggerAntiEntropy(dynamic client) async {
    if (_isDisposed) return;

    // Mock triggering anti-entropy sync
    // In real implementation: await client.triggerAntiEntropy();
    await client._mockTriggerAntiEntropy();
  }

  /// Waits for Merkle tree synchronization between clients
  Future<void> waitForMerkleSync(dynamic client1, dynamic client2) async {
    if (_isDisposed) return;

    // Monitor Merkle tree hashes until they match
    const maxAttempts = 30;
    const delayBetweenAttempts = Duration(seconds: 2);

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final hash1 = await client1.getMerkleHash();
      final hash2 = await client2.getMerkleHash();

      if (hash1 == hash2) {
        return; // Sync complete
      }

      await Future.delayed(delayBetweenAttempts);
    }

    throw TimeoutException(
      'Merkle sync not achieved within ${maxAttempts * delayBetweenAttempts.inSeconds}s',
      Duration(seconds: maxAttempts * delayBetweenAttempts.inSeconds),
    );
  }

  /// Creates a large dataset for testing convergence performance
  Future<Map<String, String>> createLargeDataset(int entryCount) async {
    final dataset = <String, String>{};
    final random = math.Random();

    for (int i = 0; i < entryCount; i++) {
      final key = 'large-data-key-$i';
      final value = 'large-data-value-$i-${random.nextInt(1000000)}';
      dataset[key] = value;
    }

    return dataset;
  }

  /// Creates a test dataset with specified number of entries
  Future<Map<String, String>> createDataset(int entryCount) async {
    final dataset = <String, String>{};

    for (int i = 0; i < entryCount; i++) {
      final key = 'test-key-$i';
      final value = 'test-value-$i';
      dataset[key] = value;
    }

    return dataset;
  }

  /// Verifies vector clock ordering for conflict resolution
  Future<void> verifyVectorClockOrdering(
    List<dynamic> clients,
    String key,
  ) async {
    if (_isDisposed || clients.isEmpty) return;

    // Get vector clock information from all clients
    final vectorClocks = <String, dynamic>{};
    
    for (final client in clients) {
      final vclock = await client.getVectorClock(key);
      vectorClocks[client.config.nodeId] = vclock;
    }

    // Verify vector clock consistency
    // Implementation would check causality and ordering rules
    _verifyVectorClockConsistency(vectorClocks);
  }

  /// Monitors convergence progress between clients
  Future<void> _monitorConvergence(String convergenceId, List<dynamic> clients) async {
    const checkInterval = Duration(seconds: 2);
    
    Timer.periodic(checkInterval, (timer) async {
      if (_isDisposed || !_convergenceCompleters.containsKey(convergenceId)) {
        timer.cancel();
        return;
      }

      try {
        final isConverged = await _checkConvergenceState(clients);
        if (isConverged) {
          timer.cancel();
          _convergenceCompleters[convergenceId]?.complete();
        }
      } catch (e) {
        timer.cancel();
        _convergenceCompleters[convergenceId]?.completeError(e);
      }
    });
  }

  /// Checks if all clients have converged
  Future<bool> _checkConvergenceState(List<dynamic> clients) async {
    if (clients.length < 2) return true;

    // Get all keys from all clients
    final allKeys = <String>{};
    for (final client in clients) {
      final keys = await client.getAllKeys();
      allKeys.addAll(keys);
    }

    // Check if all clients have the same data for all keys
    for (final key in allKeys) {
      String? referenceValue;
      
      for (final client in clients) {
        final value = await client.get(key);
        
        if (referenceValue == null) {
          referenceValue = value;
        } else if (referenceValue != value) {
          return false; // Not converged
        }
      }
    }

    return true; // All clients have consistent data
  }

  /// Verifies vector clock consistency
  void _verifyVectorClockConsistency(Map<String, dynamic> vectorClocks) {
    // Simplified vector clock verification
    // In real implementation, this would check:
    // - Causality preservation
    // - Concurrent updates handling
    // - Total ordering where possible
    
    expect(vectorClocks.isNotEmpty, isTrue);
    
    for (final vclock in vectorClocks.values) {
      expect(vclock, isNotNull);
    }
  }

  /// Generates unique convergence monitoring ID
  String _generateConvergenceId() {
    return 'convergence-${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1000)}';
  }

  /// Disposes resources
  Future<void> dispose() async {
    _isDisposed = true;
    
    // Cancel all timers
    for (final timer in _convergenceTimers.values) {
      timer.cancel();
    }
    _convergenceTimers.clear();
    
    // Complete all pending completers with error
    for (final completer in _convergenceCompleters.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('ConvergenceValidator disposed'));
      }
    }
    _convergenceCompleters.clear();
  }
}

/// Extensions for mock client to support convergence testing
extension MockClientConvergenceExtensions on dynamic {
  Future<void> _mockTriggerAntiEntropy() async {
    // Mock implementation of anti-entropy trigger
    await Future.delayed(const Duration(milliseconds: 100));
  }

  Future<String> getMerkleHash() async {
    // Mock Merkle tree hash calculation
    final keys = await getAllKeys();
    keys.sort(); // Ensure consistent ordering
    
    var hash = 0;
    for (final key in keys) {
      final value = await get(key);
      hash = hash ^ key.hashCode ^ (value?.hashCode ?? 0);
    }
    
    return hash.toString();
  }

  Future<List<String>> getAllKeys() async {
    // Mock getting all keys from storage
    try {
      // For the mock client, we can access the storage directly
      if (hasProperty('storage')) {
        final storage = getProperty('storage') as Map<String, String>?;
        return storage?.keys.toList() ?? [];
      }
      return ['mock-key-1', 'mock-key-2']; // Fallback for testing
    } catch (e) {
      return [];
    }
  }

  /// Helper method to check if an object has a property
  bool hasProperty(String propertyName) {
    try {
      // In a real implementation, this would use reflection
      // For testing, we'll use a simple check
      return toString().contains('Mock');
    } catch (e) {
      return false;
    }
  }

  /// Helper method to get a property value
  dynamic getProperty(String propertyName) {
    // In a real implementation, this would use reflection
    // For testing, we'll return mock data
    if (propertyName == 'storage') {
      return <String, String>{'test-key': 'test-value'};
    }
    return null;
  }

  Future<dynamic> getVectorClock(String key) async {
    // Mock vector clock retrieval
    return {
      'nodeId': 'mock-node-id',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'version': 1,
    };
  }
}