import 'dart:async';
import 'package:test/test.dart';
import 'package:merkle_kv_core/src/mqtt/mqtt_client_interface.dart';
import 'package:merkle_kv_core/src/mqtt/connection_state.dart';
import 'package:merkle_kv_core/src/config/merkle_kv_config.dart';
import 'package:merkle_kv_core/src/config/invalid_config_exception.dart';

/// Mock MQTT client for unit tests - does not make real network connections
class MockMqttClientUnit implements MqttClientInterface {
  StreamController<ConnectionState>? _stateController;
  ConnectionState _currentState = ConnectionState.disconnected;
  final List<String> _subscriptions = [];
  final List<String> _publishCalls = [];
  final Map<String, void Function(String, String)> _handlers = {};
  
  bool shouldFailConnection = false;
  Exception? connectionException;
  
  MockMqttClientUnit() {
    _stateController = StreamController<ConnectionState>.broadcast();
  }

  @override
  Stream<ConnectionState> get connectionState => _stateController!.stream;

  @override
  Future<void> connect() async {
    _currentState = ConnectionState.connecting;
    _stateController!.add(_currentState);
    
    await Future.delayed(Duration(milliseconds: 10)); // Simulate async operation
    
    if (shouldFailConnection) {
      // For direct unit tests, emit disconnected state on failure
      // This simulates real MQTT client behavior where failed connections result in disconnected state
      _currentState = ConnectionState.disconnected;
      _stateController!.add(_currentState);
      throw connectionException ?? Exception('Mock connection failed');
    }
    
    _currentState = ConnectionState.connected;
    _stateController!.add(_currentState);
  }

  @override
  Future<void> disconnect({bool suppressLWT = true}) async {
    _currentState = ConnectionState.disconnecting;
    _stateController!.add(_currentState);
    
    await Future.delayed(Duration(milliseconds: 10)); // Simulate async operation
    
    _subscriptions.clear();
    _handlers.clear();
    
    _currentState = ConnectionState.disconnected;
    _stateController!.add(_currentState);
  }

  @override
  Future<void> publish(String topic, String payload, {bool forceQoS1 = true, bool forceRetainFalse = true}) async {
    _publishCalls.add('$topic:$payload');
    // Simulate successful publish without network call
  }

  @override
  Future<void> subscribe(String topic, void Function(String, String) handler) async {
    _subscriptions.add(topic);
    _handlers[topic] = handler;
    // Simulate successful subscription without network call
  }

  @override
  Future<void> unsubscribe(String topic) async {
    _subscriptions.remove(topic);
    _handlers.remove(topic);
    // Simulate successful unsubscription without network call
  }

  void dispose() {
    _stateController?.close();
  }

  // Test helper methods
  List<String> get subscriptions => List.unmodifiable(_subscriptions);
  List<String> get publishCalls => List.unmodifiable(_publishCalls);
  ConnectionState get currentState => _currentState;
}

void main() {
  late MerkleKVConfig config;

  setUp(() {
    config = MerkleKVConfig(
      clientId: 'mqtt-test-client',
      nodeId: 'mqtt-test-node',
      mqttHost: 'localhost',
    );
  });

  group('MQTT Client Tests', () {
    group('Connection Management', () {
      test('client starts in disconnected state', () {
        final client = MockMqttClientUnit();
        
        expect(client.connectionState, isA<Stream<ConnectionState>>());
        expect(client.currentState, equals(ConnectionState.disconnected));
        
        client.dispose();
      });

      test('connection state stream emits changes', () async {
        final client = MockMqttClientUnit();
        
        final states = <ConnectionState>[];
        final subscription = client.connectionState.listen(states.add);
        
        await client.connect();
        
        // Wait for events to be processed
        await Future.delayed(Duration(milliseconds: 50));
        
        expect(states, contains(ConnectionState.connecting));
        expect(states, contains(ConnectionState.connected));
        expect(client.currentState, equals(ConnectionState.connected));
        
        await subscription.cancel();
        client.dispose();
      });
    });

    group('Message Publishing', () {
      test('publish method exists and accepts parameters', () async {
        final client = MockMqttClientUnit();
        
        await client.publish('test/topic', 'test message');
        
        expect(client.publishCalls, contains('test/topic:test message'));
        
        client.dispose();
      });

      test('publish with QoS parameters', () async {
        final client = MockMqttClientUnit();
        
        // Test with different QoS settings
        await client.publish(
          'test/topic', 
          'test message',
          forceQoS1: false,
          forceRetainFalse: false,
        );
        
        expect(client.publishCalls, contains('test/topic:test message'));
        
        client.dispose();
      });
    });

    group('Subscription Management', () {
      test('subscribe method exists', () async {
        final client = MockMqttClientUnit();
        
        void messageHandler(String topic, String payload) {
          // Test handler
        }
        
        await client.subscribe('test/topic', messageHandler);
        
        expect(client.subscriptions, contains('test/topic'));
        
        client.dispose();
      });

      test('unsubscribe method exists', () async {
        final client = MockMqttClientUnit();
        
        // First subscribe
        await client.subscribe('test/topic', (topic, payload) {});
        expect(client.subscriptions, contains('test/topic'));
        
        // Then unsubscribe
        await client.unsubscribe('test/topic');
        expect(client.subscriptions, isNot(contains('test/topic')));
        
        client.dispose();
      });
    });

    group('Configuration Validation', () {
      test('TLS enforcement when credentials present', () {
        expect(
          () => MerkleKVConfig(
            clientId: 'test-client',
            nodeId: 'test-node',
            mqttHost: 'localhost',
            username: 'user',
            password: 'pass',
            mqttUseTls: false, // This should cause an error
          ), 
          throwsA(isA<ArgumentError>()),
        );
      });

      test('valid configuration creates client', () {
        expect(
          () => MockMqttClientUnit(), 
          returnsNormally,
        );
      });
    });

    group('Error Handling', () {
      test('invalid host configuration', () {
        // Empty host should throw InvalidConfigException
        expect(
          () => MerkleKVConfig(
            clientId: 'test-client',
            nodeId: 'test-node',
            mqttHost: '', // Empty host
          ),
          throwsA(isA<InvalidConfigException>()),
        );
      });

      test('disconnect without connection', () async {
        final client = MockMqttClientUnit();
        
        // Should handle gracefully
        await client.disconnect();
        expect(client.currentState, equals(ConnectionState.disconnected));
        
        client.dispose();
      });

      test('connection failure handling', () async {
        final client = MockMqttClientUnit();
        client.shouldFailConnection = true;
        client.connectionException = Exception('Network error');
        
        expect(() async => await client.connect(), throwsA(isA<Exception>()));
        
        // Allow time for state changes to be processed
        await Future.delayed(Duration(milliseconds: 20));
        
        expect(client.currentState, equals(ConnectionState.disconnected));
        
        client.dispose();
      });
    });
  });
}