import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';

import 'lib/src/config/merkle_kv_config.dart';
import 'lib/src/mqtt/connection_lifecycle.dart';
import 'lib/src/mqtt/connection_state.dart';
import 'lib/src/mqtt/mqtt_client_interface.dart';
import 'lib/src/replication/metrics.dart';

final _logger = Logger('TestRunner');

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
    _logger.info('MockClient connect() called, shouldFailConnection: $shouldFailConnection');
    
    // Always emit connecting state first
    setState(ConnectionState.connecting);
    
    if (connectDelay > Duration.zero) {
      await Future.delayed(connectDelay);
    }
    
    if (shouldFailConnection) {
      setState(ConnectionState.disconnected);
      throw connectionException ?? Exception('Connection failed');
    }
    
    // Emit intermediate state change to simulate real MQTT client behavior
    await Future.delayed(Duration(milliseconds: 10));
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

Future<void> testBasicConnection() async {
  _logger.info('🧪 Testing basic connection...');
  
  final config = MerkleKVConfig(
    mqttHost: 'test.example.com',
    nodeId: 'test-node',
    clientId: 'test-client',
    keepAliveSeconds: 5,
  );
  
  final mockClient = MockMqttClient();
  final metrics = InMemoryReplicationMetrics();
  
  final manager = DefaultConnectionLifecycleManager(
    config: config,
    mqttClient: mockClient,
    metrics: metrics,
  );

  final events = <ConnectionStateEvent>[];
  final subscription = manager.connectionState.listen(events.add);

  try {
    await manager.connect();
    
    _logger.info('✅ Connection successful');
    _logger.info('✅ isConnected: ${manager.isConnected}');
    _logger.info('✅ Events received: ${events.length}');
    
    for (int i = 0; i < events.length; i++) {
      _logger.info('   Event $i: ${events[i].state} - ${events[i].reason}');
    }
    
    assert(manager.isConnected, 'Should be connected');
    assert(events.length >= 2, 'Should have connecting and connected events');
    assert(events.any((e) => e.state == ConnectionState.connecting), 'Should have connecting event');
    assert(events.any((e) => e.state == ConnectionState.connected), 'Should have connected event');
    
  } finally {
    await subscription.cancel();
    await manager.dispose();
    mockClient.dispose();
  }
}

Future<void> testConnectionTimeout() async {
  _logger.info('\n🧪 Testing connection timeout...');
  
  final config = MerkleKVConfig(
    mqttHost: 'test.example.com',
    nodeId: 'test-node',
    clientId: 'test-client',
    keepAliveSeconds: 1, // Very short for testing
  );
  
  final mockClient = MockMqttClient();
  mockClient.connectDelay = const Duration(seconds: 5); // Longer than timeout
  final metrics = InMemoryReplicationMetrics();
  
  final manager = DefaultConnectionLifecycleManager(
    config: config,
    mqttClient: mockClient,
    metrics: metrics,
  );

  final events = <ConnectionStateEvent>[];
  final subscription = manager.connectionState.listen((event) {
    _logger.info('Timeout test event: ${event.state} - ${event.reason}');
    events.add(event);
  });

  try {
    bool threwException = false;
    try {
      await manager.connect();
    } catch (e) {
      threwException = true;
      _logger.info('✅ Connect threw exception as expected: $e');
    }
    
    assert(threwException, 'Connection should have thrown timeout exception');
    assert(!manager.isConnected, 'Should not be connected');
    
    _logger.info('✅ Connection timeout handled properly');
    _logger.info('✅ Events received: ${events.length}');
    
    for (int i = 0; i < events.length; i++) {
      _logger.info('   Event $i: ${events[i].state} - ${events[i].reason}');
    }
    
  } finally {
    await subscription.cancel();
    await manager.dispose();
    mockClient.dispose();
  }
}

Future<void> testConnectionFailure() async {
  _logger.info('\n🧪 Testing connection failure...');
  
  final config = MerkleKVConfig(
    mqttHost: 'test.example.com',
    nodeId: 'test-node',
    clientId: 'test-client',
    keepAliveSeconds: 5,
  );
  
  final mockClient = MockMqttClient();
  mockClient.shouldFailConnection = true;
  mockClient.connectionException = Exception('Network error');
  final metrics = InMemoryReplicationMetrics();
  
  final manager = DefaultConnectionLifecycleManager(
    config: config,
    mqttClient: mockClient,
    metrics: metrics,
  );

  final events = <ConnectionStateEvent>[];
  final subscription = manager.connectionState.listen((event) {
    _logger.info('Failure test event: ${event.state} - ${event.reason}');
    events.add(event);
  });

  try {
    bool threwException = false;
    try {
      await manager.connect();
    } catch (e) {
      threwException = true;
      _logger.info('✅ Connect threw exception as expected: $e');
    }
    
    assert(threwException, 'Connection should have thrown exception');
    assert(!manager.isConnected, 'Should not be connected');
    
    _logger.info('✅ Connection failure handled properly');
    _logger.info('✅ Events received: ${events.length}');
    
    for (int i = 0; i < events.length; i++) {
      _logger.info('   Event $i: ${events[i].state} - ${events[i].reason}');
    }
    
    // Check for error indicators
    final errorEvents = events.where((e) => e.error != null);
    final failureEvents = events.where((e) => 
      e.reason?.contains('failed') == true || 
      e.reason?.contains('error') == true);
    
    _logger.info('✅ Error events: ${errorEvents.length}');
    _logger.info('✅ Failure events: ${failureEvents.length}');
    
  } finally {
    await subscription.cancel();
    await manager.dispose();
    mockClient.dispose();
  }
}

Future<void> main() async {
  // Configure logging
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    // Use print here for output, but only in the logging handler
    // ignore: avoid_print
    print('${record.level.name}: ${record.time}: ${record.message}');
  });

  _logger.info('🚀 Starting Connection Lifecycle Tests\n');
  
  try {
    await testBasicConnection();
    await testConnectionTimeout();
    await testConnectionFailure();
    
    _logger.info('\n✅ All tests passed! MockMqttClient fixes are working correctly.');
  } catch (e, stackTrace) {
    _logger.severe('\n❌ Test failed: $e');
    _logger.severe('Stack trace: $stackTrace');
    exit(1);
  }
}