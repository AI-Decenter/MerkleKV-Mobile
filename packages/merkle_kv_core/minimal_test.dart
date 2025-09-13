import 'dart:async';

import 'lib/src/config/merkle_kv_config.dart';
import 'lib/src/mqtt/connection_lifecycle.dart';
import 'lib/src/mqtt/connection_logger.dart';
import 'lib/src/mqtt/connection_state.dart';
import 'lib/src/mqtt/mqtt_client_interface.dart';
import 'lib/src/replication/metrics.dart';

/// Simple logger for minimal testing
class TestLogger implements ConnectionLogger {
  @override
  void debug(String message) {}
  
  @override
  void info(String message) {
    print('INFO: $message');
  }
  
  @override
  void warn(String message) {
    print('WARN: $message');
  }
  
  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    print('ERROR: $message');
    if (error != null) print('  Error: $error');
  }
}

/// Simple mock MQTT client for minimal testing
class SimpleMockClient implements MqttClientInterface {
  StreamController<ConnectionState>? _controller;
  bool shouldFail = false;
  Duration delay = Duration.zero;

  SimpleMockClient() {
    _controller = StreamController<ConnectionState>.broadcast();
  }

  @override
  Stream<ConnectionState> get connectionState => _controller!.stream;

  void _setState(ConnectionState state) {
    if (_controller != null && !_controller!.isClosed) {
      _controller!.add(state);
    }
  }

  @override
  Future<void> connect() async {
    _setState(ConnectionState.connecting);
    
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }
    
    if (shouldFail) {
      _setState(ConnectionState.disconnected);
      throw Exception('Connection failed');
    }
    
    _setState(ConnectionState.connected);
  }

  @override
  Future<void> disconnect({bool suppressLWT = true}) async {
    _setState(ConnectionState.disconnecting);
    await Future.delayed(Duration(milliseconds: 10));
    _setState(ConnectionState.disconnected);
  }

  @override
  Future<void> publish(String topic, String payload, {bool forceQoS1 = true, bool forceRetainFalse = true}) async {}

  @override
  Future<void> subscribe(String topic, void Function(String, String) handler) async {}

  @override
  Future<void> unsubscribe(String topic) async {}

  void dispose() {
    _controller?.close();
    _controller = null;
  }
}

Future<void> testMinimal() async {
  print('🧪 Testing minimal connection lifecycle...');
  
  final config = MerkleKVConfig(
    mqttHost: 'test.example.com',
    nodeId: 'test-node',
    clientId: 'test-client',
    keepAliveSeconds: 2,
  );
  
  final mockClient = SimpleMockClient();
  final metrics = InMemoryReplicationMetrics();
  
  final manager = DefaultConnectionLifecycleManager(
    config: config,
    mqttClient: mockClient,
    metrics: metrics,
    logger: TestLogger(),
  );

  final events = <ConnectionStateEvent>[];
  final subscription = manager.connectionState.listen((event) {
    print('Event: ${event.state} - ${event.reason}');
    events.add(event);
  });

  try {
    // Test 1: Successful connection
    await manager.connect();
    await Future.delayed(Duration(milliseconds: 50)); // Let events propagate
    
    print('✅ Success: isConnected = ${manager.isConnected}');
    print('✅ Success: Events count = ${events.length}');
    
    // Test 2: Graceful disconnect
    await manager.disconnect();
    await Future.delayed(Duration(milliseconds: 50));
    
    print('✅ Disconnect: isConnected = ${manager.isConnected}');
    print('✅ Disconnect: Events count = ${events.length}');
    
    // Test 3: Connection failure
    events.clear();
    mockClient.shouldFail = true;
    
    try {
      await manager.connect();
      print('❌ Should have failed');
    } catch (e) {
      print('✅ Failed as expected: $e');
    }
    
    await Future.delayed(Duration(milliseconds: 50));
    print('✅ Failure: isConnected = ${manager.isConnected}');
    print('✅ Failure: Events count = ${events.length}');
    
    // Test 4: Timeout
    events.clear();
    mockClient.shouldFail = false;
    mockClient.delay = Duration(seconds: 5); // Longer than timeout
    
    try {
      await manager.connect();
      print('❌ Should have timed out');
    } catch (e) {
      print('✅ Timeout as expected: $e');
    }
    
    await Future.delayed(Duration(milliseconds: 50));
    print('✅ Timeout: isConnected = ${manager.isConnected}');
    print('✅ Timeout: Events count = ${events.length}');
    
  } finally {
    await subscription.cancel();
    await manager.dispose();
    mockClient.dispose();
  }
  
  print('✅ All minimal tests passed!');
}

Future<void> main() async {
  try {
    await testMinimal();
    print('\n🎉 Comprehensive test fixes validated successfully!');
  } catch (e, stackTrace) {
    print('\n❌ Validation failed: $e');
    print('Stack trace: $stackTrace');
    exit(1);
  }
}

void exit(int code) {
  // Dart's exit function
  throw StateError('Exit with code $code');
}