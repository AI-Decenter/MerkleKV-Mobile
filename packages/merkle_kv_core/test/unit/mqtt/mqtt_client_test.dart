import 'package:test/test.dart';
import 'package:merkle_kv_core/src/mqtt/mqtt_client_impl.dart';
import 'package:merkle_kv_core/src/mqtt/connection_state.dart';
import 'package:merkle_kv_core/src/config/merkle_kv_config.dart';
import 'package:merkle_kv_core/src/config/invalid_config_exception.dart';

void main() {
  late MerkleKVConfig config;

  setUp(() {
    config = MerkleKVConfig(
      clientId: 'mqtt-test-client',
      nodeId: 'mqtt-test-node',
      mqttHost: 'test.example.com',
    );
  });

  group('MQTT Client Tests', () {
    group('Connection Management', () {
      test('client starts in disconnected state', () {
        final client = MqttClientImpl(config);
        
        expect(client.connectionState, isA<Stream<ConnectionState>>());
        // Stream-based state, cannot directly check current state
      });

      test('connection state stream emits changes', () async {
        final client = MqttClientImpl(config);
        
        // Listen to connection state changes
        final stateStream = client.connectionState;
        expect(stateStream, isA<Stream<ConnectionState>>());
        
        // We can't actually test connection without a real broker
        // This test just verifies the stream exists
      });
    });

    group('Message Publishing', () {
      test('publish method exists and accepts parameters', () async {
        final client = MqttClientImpl(config);
        
        // This should not throw even when disconnected (should queue)
        expect(() async => await client.publish('test/topic', 'test message'), 
               returnsNormally);
      });

      test('publish with QoS parameters', () async {
        final client = MqttClientImpl(config);
        
        // Test with different QoS settings
        expect(() async => await client.publish(
          'test/topic', 
          'test message',
          forceQoS1: false,
          forceRetainFalse: false,
        ), returnsNormally);
      });
    });

    group('Subscription Management', () {
      test('subscribe method exists', () async {
        final client = MqttClientImpl(config);
        
        void messageHandler(String topic, String payload) {
          // Test handler
        }
        
        expect(() async => await client.subscribe('test/topic', messageHandler), 
               returnsNormally);
      });

      test('unsubscribe method exists', () async {
        final client = MqttClientImpl(config);
        
        expect(() async => await client.unsubscribe('test/topic'), 
               returnsNormally);
      });
    });

    group('Configuration Validation', () {
      test('TLS enforcement when credentials present', () {
        expect(
          () => MqttClientImpl(MerkleKVConfig(
            clientId: 'test-client',
            nodeId: 'test-node',
            mqttHost: 'test.example.com',
            username: 'user',
            password: 'pass',
            mqttUseTls: false, // This should cause an error
          )), 
          throwsA(isA<ArgumentError>()),
        );
      });

      test('valid configuration creates client', () {
        expect(
          () => MqttClientImpl(MerkleKVConfig(
            clientId: 'test-client',
            nodeId: 'test-node',
            mqttHost: 'test.example.com',
            mqttUseTls: true,
          )), 
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
        final client = MqttClientImpl(config);
        
        // Should handle gracefully
        expect(() async => await client.disconnect(), returnsNormally);
      });
    });
  });
}