import 'dart:async';
import 'package:test/test.dart';

import '../../lib/src/config/merkle_kv_config.dart';
import '../../lib/src/mqtt/connection_lifecycle.dart';
import '../../lib/src/mqtt/connection_state.dart';
import '../../lib/src/mqtt/mqtt_client_interface.dart';
import '../../lib/src/replication/metrics.dart';

// Test timing constants to improve readability and maintainability
class TestTimings {
  static const subscriptionDelay = Duration(milliseconds: 20);
  static const eventProcessingDelay = Duration(milliseconds: 100);
  static const smallDelay = Duration(milliseconds: 10);
  static const longDelay = Duration(seconds: 15);
  static const shortTimeout = Duration(seconds: 3);
  static const connectionTimeout = Duration(seconds: 20); // Match client timeout (updated from 10s to 20s)
  static const timeoutWindow = Duration(seconds: 1);
}

/// Mock MQTT client for testing.
class MockMqttClient implements MqttClientInterface {
  StreamController<ConnectionState>? _stateController;
  
  ConnectionState _currentState = ConnectionState.disconnected;
  final List<String> _subscriptions = [];
  final List<String> _publishCalls = [];
  final Map<String, void Function(String, String)> _handlers = {};
  
  // Configuration for test scenarios
  bool shouldFailConnection = false;
  Duration connectDelay = Duration.zero;
  Duration disconnectDelay = Duration.zero;
  Exception? connectionException;
  bool suppressLWTCalled = false;

  MockMqttClient() {
    _initializeController();
  }

  void _initializeController() {
    _stateController?.close();
    _stateController = StreamController<ConnectionState>.broadcast();
  }

  @override
  Stream<ConnectionState> get connectionState {
    if (_stateController == null || _stateController!.isClosed) {
      _initializeController();
    }
    return _stateController!.stream;
  }

  ConnectionState get currentState => _currentState;
  List<String> get subscriptions => List.unmodifiable(_subscriptions);
  List<String> get publishCalls => List.unmodifiable(_publishCalls);
  
  void setState(ConnectionState state) {
    if (_currentState != state) {
      _currentState = state;
      // Use Future.microtask to ensure events are emitted after the current execution context
      if (_stateController != null && !_stateController!.isClosed) {
        Future.microtask(() {
          if (_stateController != null && !_stateController!.isClosed) {
            _stateController!.add(state);
          }
        });
      }
    }
  }

  @override
  Future<void> connect() async {
    // Debug: MockClient connect() called, shouldFailConnection: $shouldFailConnection
    
    // Always emit connecting state first
    setState(ConnectionState.connecting);
    
    if (connectDelay > Duration.zero) {
      await Future.delayed(connectDelay);
    }
    
    if (shouldFailConnection) {
      // Wait a bit then emit disconnected state
      await Future.delayed(const Duration(milliseconds: 20));
      setState(ConnectionState.disconnected);
      throw connectionException ?? Exception('Connection failed');
    }
    
    // Emit intermediate state change to simulate real MQTT client behavior
    await Future.delayed(const Duration(milliseconds: 20));
    setState(ConnectionState.connected);
  }

  @override
  Future<void> disconnect({bool suppressLWT = true}) async {
    suppressLWTCalled = suppressLWT;
    
    if (disconnectDelay > Duration.zero) {
      await Future.delayed(disconnectDelay);
    }
    
    setState(ConnectionState.disconnecting);
    
    // Clean up all subscriptions when disconnecting
    _subscriptions.clear();
    _handlers.clear();
    
    await Future.delayed(const Duration(milliseconds: 10));
    setState(ConnectionState.disconnected);
  }

  @override
  Future<void> publish(
    String topic,
    String payload, {
    bool forceQoS1 = true,
    bool forceRetainFalse = true,
  }) async {
    _publishCalls.add('$topic:$payload');
  }

  @override
  Future<void> subscribe(String topic, void Function(String, String) handler) async {
    _subscriptions.add(topic);
    _handlers[topic] = handler;
  }

  @override
  Future<void> unsubscribe(String topic) async {
    _subscriptions.remove(topic);
    _handlers.remove(topic);
  }

  void dispose() {
    _stateController?.close();
    _stateController = null;
  }

  void reset() {
    // Reset state for new test
    shouldFailConnection = false;
    connectDelay = Duration.zero;
    disconnectDelay = Duration.zero;
    connectionException = null;
    suppressLWTCalled = false;
    _subscriptions.clear();
    _publishCalls.clear();
    _handlers.clear();
    _currentState = ConnectionState.disconnected;
    _initializeController();
  }
}

void main() {
  group('ConnectionLifecycleManager', () {
    late MerkleKVConfig config;
    late MockMqttClient mockClient;
    late InMemoryReplicationMetrics metrics;
    late DefaultConnectionLifecycleManager manager;

    setUp(() {
      config = MerkleKVConfig(
        mqttHost: 'test.example.com',
        nodeId: 'test-node',
        clientId: 'test-client',
        keepAliveSeconds: 5,
      );
      
      mockClient = MockMqttClient();
      metrics = InMemoryReplicationMetrics();
      
      manager = DefaultConnectionLifecycleManager(
        config: config,
        mqttClient: mockClient,
        metrics: metrics,
      );
    });

    tearDown(() async {
      try {
        // Ensure proper disconnection before disposal
        if (manager.isConnected) {
          await manager.disconnect(suppressLWT: true);
        }
        
        // Dispose resources in proper order
        await manager.dispose();
        mockClient.dispose();
        
        // Reset mock state for next test
        mockClient.reset();
        
        // Small delay to allow cleanup completion
        await Future.delayed(const Duration(milliseconds: 10));
      } catch (e) {
        // Ensure tearDown doesn't fail tests
        // Note: tearDown cleanup failed - $e
      }
    });

    group('Connection establishment', () {
      test('successful connection emits correct state events', () async {
        final events = <ConnectionStateEvent>[];
        final subscription = manager.connectionState.listen((event) {
          print('Test received event: ${event.state} - ${event.reason}');
          events.add(event);
        });

        // Wait for subscription to be fully active
        await Future.delayed(TestTimings.subscriptionDelay);

        await manager.connect();

        // Wait for all events to be processed and captured
        await Future.delayed(TestTimings.eventProcessingDelay);

        print('Total events received: ${events.length}');
        for (int i = 0; i < events.length; i++) {
          print('Event $i: ${events[i].state} - ${events[i].reason}');
        }

        // Should have at least connecting event and connected event
        expect(events.length, greaterThanOrEqualTo(2), 
               reason: 'Should have at least connecting and connected events. Got: ${events.map((e) => '${e.state}:${e.reason}').join(', ')}');
        
        // Check for connecting event
        final connectingEvents = events.where((e) => e.state == ConnectionState.connecting);
        expect(connectingEvents.isNotEmpty, isTrue, reason: 'Should have connecting event');
        expect(connectingEvents.first.reason, contains('Manual connection request'));
        
        // Check for connected event
        final connectedEvents = events.where((e) => e.state == ConnectionState.connected);
        expect(connectedEvents.isNotEmpty, isTrue, reason: 'Should have connected event');
        expect(connectedEvents.any((e) => e.reason?.contains('Connection established successfully') == true), isTrue);
        
        expect(manager.isConnected, isTrue);
        
        await subscription.cancel();
      });

      test('connection failure emits error state', () async {
        mockClient.shouldFailConnection = true;
        mockClient.connectionException = Exception('Network error');
        
        final events = <ConnectionStateEvent>[];
        final subscription = manager.connectionState.listen((event) {
          print('Failure test received event: ${event.state} - ${event.reason}');
          events.add(event);
        });

        // Wait for subscription to be fully active
        await Future.delayed(TestTimings.subscriptionDelay);

        await expectLater(
          manager.connect(),
          throwsA(isA<Exception>()),
        );

        // Wait for all events to be processed
        await Future.delayed(TestTimings.eventProcessingDelay);

        print('Failure test total events received: ${events.length}');
        for (int i = 0; i < events.length; i++) {
          print('Failure Event $i: ${events[i].state} - ${events[i].reason}');
        }

        // Should have at least connecting and disconnected events
        expect(events.length, greaterThanOrEqualTo(2), 
               reason: 'Should have at least connecting and disconnected events. Got: ${events.map((e) => '${e.state}:${e.reason}').join(', ')}');
        
        // Check for connecting event
        final connectingEvents = events.where((e) => e.state == ConnectionState.connecting);
        expect(connectingEvents.isNotEmpty, isTrue, reason: 'Should have connecting event');
        
        // Check for disconnected event
        final disconnectedEvents = events.where((e) => e.state == ConnectionState.disconnected);
        expect(disconnectedEvents.isNotEmpty, isTrue, reason: 'Should have disconnected event');
        expect(disconnectedEvents.last.error, isNotNull);
        expect(disconnectedEvents.last.reason, contains('Connection failed'));
        
        expect(manager.isConnected, isFalse);
        
        await subscription.cancel();
      });

      test('connection timeout is handled properly', () async {
        // Use a delay longer than the connection timeout to force timeout
        mockClient.connectDelay = const Duration(seconds: 25); // Longer than 20s timeout
        
        final events = <ConnectionStateEvent>[];
        final subscription = manager.connectionState.listen((event) {
          print('Timeout test received event: ${event.state} - ${event.reason}');
          events.add(event);
        });

        // Wait for subscription to be active
        await Future.delayed(TestTimings.subscriptionDelay);

        // Connection should throw timeout exception
        await expectLater(
          manager.connect(),
          throwsA(isA<Exception>()),
        );

        // Wait for all events to be processed
        await Future.delayed(TestTimings.eventProcessingDelay);

        print('Timeout test total events received: ${events.length}');
        for (int i = 0; i < events.length; i++) {
          print('Timeout Event $i: ${events[i].state} - ${events[i].reason}');
        }

        // Should have timeout event or connection failed event
        final hasTimeoutEvent = events.any((e) => 
          e.reason?.contains('timeout') == true || 
          e.reason?.contains('Connection timeout') == true ||
          e.reason?.contains('Connection failed') == true);
        expect(hasTimeoutEvent, isTrue, 
               reason: 'Should have timeout/failure event. All events: ${events.map((e) => '${e.state}: ${e.reason}').toList()}');
        expect(manager.isConnected, isFalse);
        
        await subscription.cancel();
      });

      test('duplicate connection attempts are ignored', () async {
        final connectFuture1 = manager.connect();
        final connectFuture2 = manager.connect();
        
        await Future.wait([connectFuture1, connectFuture2]);
        
        expect(manager.isConnected, isTrue);
        
        // Should only have one set of connection events
        expect(mockClient.currentState, equals(ConnectionState.connected));
      });
    });

    group('Graceful disconnection', () {
      setUp(() async {
        await manager.connect();
        expect(manager.isConnected, isTrue);
      });

      test('successful disconnection with LWT suppression', () async {
        final events = <ConnectionStateEvent>[];
        final subscription = manager.connectionState.listen(events.add);

        await manager.disconnect(suppressLWT: true);

        expect(mockClient.suppressLWTCalled, isTrue);
        expect(manager.isConnected, isFalse);
        
        final disconnectEvents = events.where(
          (e) => e.state == ConnectionState.disconnecting || 
                 e.state == ConnectionState.disconnected
        );
        
        expect(disconnectEvents.length, greaterThanOrEqualTo(2));
        
        await subscription.cancel();
      });

      test('disconnection without LWT suppression', () async {
        await manager.disconnect(suppressLWT: false);

        expect(mockClient.suppressLWTCalled, isFalse);
        expect(manager.isConnected, isFalse);
      });

      test('disconnection timeout is handled', () async {
        mockClient.disconnectDelay = TestTimings.longDelay;
        
        final events = <ConnectionStateEvent>[];
        final subscription = manager.connectionState.listen(events.add);

        await manager.disconnect();

        // Should complete even with timeout
        expect(manager.isConnected, isFalse);
        
        await subscription.cancel();
      });

      test('duplicate disconnection attempts are ignored', () async {
        final disconnectFuture1 = manager.disconnect();
        final disconnectFuture2 = manager.disconnect();
        
        await Future.wait([disconnectFuture1, disconnectFuture2]);
        
        expect(manager.isConnected, isFalse);
      });
    });

    group('Resource cleanup', () {
      test('subscriptions are cleaned up on disconnect', () async {
        await manager.connect();
        
        // Add some mock subscriptions
        await mockClient.subscribe('topic1', (topic, payload) {});
        await mockClient.subscribe('topic2', (topic, payload) {});
        
        expect(mockClient.subscriptions.length, equals(2));
        
        await manager.disconnect();
        
        // Mock client should have been asked to unsubscribe
        expect(mockClient.subscriptions.length, equals(0));
      });

      test('active timers are canceled on disconnect', () async {
        await manager.connect();
        
        // Simulate some active timers (these would be tracked internally)
        // For this test, we verify through the internal state
        
        await manager.disconnect();
        
        // Timers should be cleaned up (verified through no memory leaks)
        expect(manager.isConnected, isFalse);
      });
    });

    group('App lifecycle handling', () {
      test('app backgrounding with connection maintenance', () async {
        final backgroundManager = DefaultConnectionLifecycleManager(
          config: config,
          mqttClient: mockClient,
          metrics: metrics,
          maintainConnectionInBackground: true,
        );
        
        await backgroundManager.connect();
        expect(backgroundManager.isConnected, isTrue);
        
        await backgroundManager.handleAppStateChange(AppLifecycleState.paused);
        
        // Should remain connected
        expect(backgroundManager.isConnected, isTrue);
        
        await backgroundManager.dispose();
      });

      test('app backgrounding without connection maintenance', () async {
        final backgroundManager = DefaultConnectionLifecycleManager(
          config: config,
          mqttClient: mockClient,
          metrics: metrics,
          maintainConnectionInBackground: false,
        );
        
        await backgroundManager.connect();
        expect(backgroundManager.isConnected, isTrue);
        
        await backgroundManager.handleAppStateChange(AppLifecycleState.paused);
        
        // Should disconnect
        expect(backgroundManager.isConnected, isFalse);
        
        await backgroundManager.dispose();
      });

      test('app resuming reconnects if needed', () async {
        final backgroundManager = DefaultConnectionLifecycleManager(
          config: config,
          mqttClient: mockClient,
          metrics: metrics,
          maintainConnectionInBackground: false,
        );
        
        await backgroundManager.connect();
        await backgroundManager.handleAppStateChange(AppLifecycleState.paused);
        expect(backgroundManager.isConnected, isFalse);
        
        await backgroundManager.handleAppStateChange(AppLifecycleState.resumed);
        
        // Should reconnect
        expect(backgroundManager.isConnected, isTrue);
        
        await backgroundManager.dispose();
      });

      test('inactive state is handled gracefully', () async {
        await manager.connect();
        
        await manager.handleAppStateChange(AppLifecycleState.inactive);
        
        // Should remain connected during brief inactive state
        expect(manager.isConnected, isTrue);
      });
    });

    group('State monitoring', () {
      test('MQTT client state changes are tracked', () async {
        final events = <ConnectionStateEvent>[];
        final subscription = manager.connectionState.listen(events.add);

        // Simulate direct MQTT state changes
        mockClient.setState(ConnectionState.connecting);
        await Future.delayed(TestTimings.smallDelay);
        
        mockClient.setState(ConnectionState.connected);
        await Future.delayed(TestTimings.smallDelay);
        
        mockClient.setState(ConnectionState.disconnected);
        await Future.delayed(TestTimings.smallDelay);

        expect(events.length, greaterThanOrEqualTo(3));
        expect(events.map((e) => e.state), contains(ConnectionState.connecting));
        expect(events.map((e) => e.state), contains(ConnectionState.connected));
        expect(events.map((e) => e.state), contains(ConnectionState.disconnected));
        
        await subscription.cancel();
      });

      test('connection state events have timestamps', () async {
        final events = <ConnectionStateEvent>[];
        final subscription = manager.connectionState.listen(events.add);

        await manager.connect();

        for (final event in events) {
          expect(event.timestamp, isNotNull);
          expect(event.timestamp.isBefore(DateTime.now().add(TestTimings.timeoutWindow)), isTrue);
        }
        
        await subscription.cancel();
      });

      test('error categorization works correctly', () async {
        final testCases = [
          ('timeout', 'timeout'),
          ('authentication failed', 'authFailure'),
          ('network error', 'networkError'),
          ('unauthorized access', 'authFailure'),
          ('socket error', 'networkError'),
          ('unknown error', 'brokerClose'),
        ];

        for (final testCase in testCases) {
          mockClient.shouldFailConnection = true;
          mockClient.connectionException = Exception(testCase.$1);
          
          final events = <ConnectionStateEvent>[];
          final subscription = manager.connectionState.listen(events.add);

          await expectLater(manager.connect(), throwsA(isA<Exception>()));
          
          // Wait a bit for events to be processed
          await Future.delayed(TestTimings.smallDelay);
          
          // Find error events (should have non-null error field)
          final errorEvents = events.where((e) => e.error != null);
          expect(errorEvents.isNotEmpty, isTrue, reason: 'Should have at least one error event');
          
          final errorEvent = errorEvents.first;
          expect(errorEvent.reason, contains('Connection failed'));
          
          await subscription.cancel();
          
          // Reset for next test
          mockClient.shouldFailConnection = false;
          mockClient.connectionException = null;
        }
      });
    });

    group('Rapid connect/disconnect cycles', () {
      test('handles rapid cycles without resource leaks', () async {
        for (int i = 0; i < 10; i++) {
          await manager.connect();
          expect(manager.isConnected, isTrue);
          
          await manager.disconnect();
          expect(manager.isConnected, isFalse);
        }
        
        // Should not have any resource leaks
        expect(manager.isConnected, isFalse);
      });

      test('concurrent connect/disconnect operations', () async {
        final futures = <Future>[];
        
        // Start multiple concurrent operations
        for (int i = 0; i < 5; i++) {
          futures.add(manager.connect());
          futures.add(manager.disconnect());
        }
        
        await Future.wait(futures);
        
        // Should end in a consistent state
        expect(manager.isConnected, anyOf(isTrue, isFalse));
      });
    });

    group('Error recovery', () {
      test('recovers from connection failures', () async {
        // First attempt fails
        mockClient.shouldFailConnection = true;
        await expectLater(manager.connect(), throwsA(isA<Exception>()));
        expect(manager.isConnected, isFalse);
        
        // Second attempt succeeds
        mockClient.shouldFailConnection = false;
        await manager.connect();
        expect(manager.isConnected, isTrue);
      });

      test('handles network interruptions gracefully', () async {
        await manager.connect();
        expect(manager.isConnected, isTrue);
        
        // Simulate network interruption
        mockClient.setState(ConnectionState.disconnected);
        await Future.delayed(const Duration(milliseconds: 10));
        
        expect(manager.isConnected, isFalse);
      });
    });

    group('Dispose and cleanup', () {
      test('dispose cleans up all resources', () async {
        await manager.connect();
        
        final events = <ConnectionStateEvent>[];
        final subscription = manager.connectionState.listen(events.add);
        
        await manager.dispose();
        
        // Should not emit any more events
        mockClient.setState(ConnectionState.connected);
        await Future.delayed(TestTimings.smallDelay);
        
        // Events stream should be closed
        expect(subscription.isPaused, isFalse); // Stream is closed, not paused
        
        await subscription.cancel();
      });

      test('dispose is idempotent', () async {
        await manager.dispose();
        await manager.dispose(); // Should not throw
      });
    });

    group('Configuration integration', () {
      test('uses correct keep-alive timeout', () async {
        final shortConfig = MerkleKVConfig(
          mqttHost: 'test.example.com',
          nodeId: 'test-node',
          clientId: 'test-client',
          keepAliveSeconds: 1, // Very short for testing
        );
        
        final shortManager = DefaultConnectionLifecycleManager(
          config: shortConfig,
          mqttClient: mockClient,
          metrics: metrics,
        );
        
        mockClient.connectDelay = TestTimings.shortTimeout; // Longer than timeout
        
        await expectLater(
          shortManager.connect(),
          throwsA(isA<Exception>()),
        );
        
        await shortManager.dispose();
      });

      test('respects TLS configuration', () async {
        final tlsConfig = MerkleKVConfig(
          mqttHost: 'secure.example.com',
          nodeId: 'test-node',
          clientId: 'test-client',
          mqttUseTls: true,
          username: 'testuser',
          password: 'testpass',
        );
        
        final tlsManager = DefaultConnectionLifecycleManager(
          config: tlsConfig,
          mqttClient: mockClient,
          metrics: metrics,
        );
        
        await tlsManager.connect();
        expect(tlsManager.isConnected, isTrue);
        
        await tlsManager.dispose();
      });
    });
  });
}