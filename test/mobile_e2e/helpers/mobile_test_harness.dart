import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter_test/flutter_test.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';

/// Mobile Test Harness
/// 
/// Provides testing utilities for mobile-specific scenarios including
/// client lifecycle management, connection state monitoring, and
/// health verification.
class MobileTestHarness {
  final List<dynamic> _activeClients = [];
  final Map<dynamic, StreamSubscription> _connectionSubscriptions = {};
  final Map<String, Timer> _timeoutTimers = {};

  /// Creates a MerkleKV client configured for mobile testing
  Future<dynamic> createClient(MerkleKVConfig config) async {
    // Note: This creates a mock client for testing purposes
    // In real implementation, this would be: MerkleKVMobile(config)
    final client = _MockMerkleKVClient(config);
    _activeClients.add(client);
    
    // Start connection monitoring
    _connectionSubscriptions[client] = client.connectionState.listen((state) {
      developer.log('Client ${config.clientId} connection state: $state');
    });
    
    await client.start();
    return client;
  }

  /// Waits for a client to establish connection
  Future<void> waitForConnection(
    dynamic client, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final completer = Completer<void>();
    late StreamSubscription subscription;
    late Timer timeoutTimer;

    subscription = client.connectionState.listen((state) {
      if (state == ConnectionState.connected) {
        subscription.cancel();
        timeoutTimer.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });

    timeoutTimer = Timer(timeout, () {
      subscription.cancel();
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException(
            'Client failed to connect within ${timeout.inSeconds}s',
            timeout,
          ),
        );
      }
    });

    return completer.future;
  }

  /// Waits for a specific connection state
  Future<void> waitForConnectionState(
    dynamic client,
    ConnectionState expectedState, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final completer = Completer<void>();
    late StreamSubscription subscription;
    late Timer timeoutTimer;

    subscription = client.connectionState.listen((state) {
      if (state == expectedState) {
        subscription.cancel();
        timeoutTimer.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });

    timeoutTimer = Timer(timeout, () {
      subscription.cancel();
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException(
            'Client did not reach state $expectedState within ${timeout.inSeconds}s',
            timeout,
          ),
        );
      }
    });

    return completer.future;
  }

  /// Gets the current connection state of a client
  Future<ConnectionState> getConnectionState(dynamic client) async {
    // Return the current state from the stream
    return client.currentConnectionState;
  }

  /// Simulates app termination for a client
  Future<void> simulateAppTermination(dynamic client) async {
    // Forcefully disconnect without proper cleanup
    await client.forceDisconnect();
    _activeClients.remove(client);
    _connectionSubscriptions[client]?.cancel();
    _connectionSubscriptions.remove(client);
  }

  /// Waits for operation recovery after client restart
  Future<void> waitForOperationRecovery(
    dynamic client, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    // Wait for pending operations to be recovered from persistent storage
    await client.recoverPendingOperations();
    
    // Allow some time for operations to complete
    await Future.delayed(const Duration(seconds: 2));
  }

  /// Verifies client health and state integrity
  Future<void> verifyClientHealth(dynamic client) async {
    // Check connection state is valid
    final connectionState = await getConnectionState(client);
    expect(connectionState, isIn([
      ConnectionState.connected,
      ConnectionState.connecting,
      ConnectionState.reconnecting,
    ]));

    // Verify basic operations work
    final testKey = 'health-check-${DateTime.now().millisecondsSinceEpoch}';
    final testValue = 'health-check-value';
    
    await client.set(testKey, testValue);
    final retrievedValue = await client.get(testKey);
    expect(retrievedValue, equals(testValue));
    
    // Clean up test data
    await client.delete(testKey);
  }

  /// Verifies memory usage is within acceptable bounds
  Future<void> verifyMemoryUsage(dynamic client) async {
    // Get memory metrics from client
    final memoryUsage = await client.getMemoryUsage();
    
    // Verify memory usage is reasonable (specific thresholds depend on app)
    expect(memoryUsage.heapUsage, lessThan(100 * 1024 * 1024)); // 100MB
    expect(memoryUsage.leakCount, equals(0));
    
    developer.log('Memory usage: ${memoryUsage.heapUsage} bytes');
  }

  /// Dispose all resources
  Future<void> dispose() async {
    // Cancel all timers
    for (final timer in _timeoutTimers.values) {
      timer.cancel();
    }
    _timeoutTimers.clear();

    // Cancel all subscriptions
    for (final subscription in _connectionSubscriptions.values) {
      await subscription.cancel();
    }
    _connectionSubscriptions.clear();

    // Dispose all clients
    for (final client in _activeClients) {
      try {
        await client.dispose();
      } catch (e) {
        developer.log('Error disposing client: $e');
      }
    }
    _activeClients.clear();
  }
}

/// Memory usage metrics for testing
class MemoryUsage {
  final int heapUsage;
  final int leakCount;

  const MemoryUsage({
    required this.heapUsage,
    required this.leakCount,
  });
}

/// Mock MerkleKV client for testing purposes
class _MockMerkleKVClient {
  final MerkleKVConfig config;
  final StreamController<ConnectionState> _connectionStateController = 
      StreamController<ConnectionState>.broadcast();
  final Map<String, String> _storage = {};
  
  ConnectionState _currentState = ConnectionState.disconnected;
  bool _isDisposed = false;

  _MockMerkleKVClient(this.config);

  Stream<ConnectionState> get connectionState => _connectionStateController.stream;
  
  ConnectionState get currentConnectionState => _currentState;

  /// Expose storage for testing
  Map<String, String> get storage => Map.unmodifiable(_storage);

  Future<void> start() async {
    if (_isDisposed) return;
    
    _updateConnectionState(ConnectionState.connecting);
    
    // Simulate connection delay
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (!_isDisposed) {
      _updateConnectionState(ConnectionState.connected);
    }
  }

  Future<void> set(String key, String value) async {
    if (_currentState != ConnectionState.connected) {
      throw StateError('Client not connected');
    }
    _storage[key] = value;
  }

  Future<String?> get(String key) async {
    if (_currentState != ConnectionState.connected) {
      throw StateError('Client not connected');
    }
    return _storage[key];
  }

  Future<void> delete(String key) async {
    if (_currentState != ConnectionState.connected) {
      throw StateError('Client not connected');
    }
    _storage.remove(key);
  }

  Future<void> forceDisconnect() async {
    _updateConnectionState(ConnectionState.disconnected);
  }

  Future<void> recoverPendingOperations() async {
    // Mock operation recovery
    await Future.delayed(const Duration(milliseconds: 200));
  }

  Future<MemoryUsage> getMemoryUsage() async {
    return const MemoryUsage(
      heapUsage: 1024 * 1024, // 1MB
      leakCount: 0,
    );
  }

  Future<void> dispose() async {
    _isDisposed = true;
    _updateConnectionState(ConnectionState.disconnected);
    await _connectionStateController.close();
  }

  void _updateConnectionState(ConnectionState newState) {
    if (_isDisposed) return;
    
    _currentState = newState;
    _connectionStateController.add(newState);
  }
}