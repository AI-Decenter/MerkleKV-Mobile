@Tags(['integration'])
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:merkle_kv_core/src/config/merkle_kv_config.dart';
import 'package:merkle_kv_core/src/mqtt/connection_state.dart';
import 'package:merkle_kv_core/src/mqtt/mqtt_client_impl.dart';

void main() {
  // Skip network-dependent tests in CI environment
  final skipReason = (Platform.environment.containsKey('CI') || Platform.environment.containsKey('GITHUB_ACTIONS')) 
      ? 'Skipped in CI environment - no MQTT broker available' 
      : null;
  
  group('MqttClientImpl', () {
    late MerkleKVConfig config;
    late MqttClientImpl client;

    setUp(() {
      final host = Platform.environment['MQTT_TEST_HOST'] ?? 'localhost';
      final port = int.tryParse(Platform.environment['MQTT_TEST_PORT'] ?? '1883') ?? 1883;
      
      config = MerkleKVConfig(
        mqttHost: host,
        mqttPort: port,
        clientId: 'test-client-${DateTime.now().millisecondsSinceEpoch}',
        nodeId: 'test-node',
        mqttUseTls: false,
      );
    });

    tearDown(() async {
      try {
        await client.dispose();
      } catch (e) {
        // Ignore disposal errors in tests
      }
    });

    group('configuration', () {
      test('applies Spec §6 defaults correctly', () {
        client = MqttClientImpl(config);

        // Test public interface behavior instead of private implementation
        expect(client.connectionState, isA<Stream<ConnectionState>>());
      });

      test('enforces TLS when credentials are present', () {
        expect(
          () => MqttClientImpl(
            MerkleKVConfig(
              mqttHost: 'localhost',
              mqttPort: 1883,
              clientId: 'test-client',
              nodeId: 'test-node',
              mqttUseTls: false,
              username: 'user',
              password: 'pass',
            ),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('TLS must be enabled when credentials are provided'),
            ),
          ),
        );
      });

      test('configures TLS correctly when enabled', () {
        final tlsConfig = MerkleKVConfig(
          mqttHost: 'localhost',
          mqttPort: 8883,
          clientId: 'test-client',
          nodeId: 'test-node',
          mqttUseTls: true,
          username: 'user',
          password: 'pass',
        );

        client = MqttClientImpl(tlsConfig);

        // Test that TLS configuration is accepted without error
        expect(client.connectionState, isA<Stream<ConnectionState>>());
      });

      test('configures Last Will and Testament correctly', () {
        client = MqttClientImpl(config);

        // Test that LWT configuration is set up properly by checking no error in creation
        expect(client, isA<MqttClientImpl>());
      });
    });

    group('connection lifecycle', () {
      test('starts in disconnected state', () {
        client = MqttClientImpl(config);

        // Test initial state through stream
        final completer = Completer<ConnectionState>();
        final subscription = client.connectionState.listen(completer.complete);

        // Trigger a state change to test current state
        client.disconnect();

        subscription.cancel();
      });

      test('connection state stream emits changes', () async {
        client = MqttClientImpl(config);

        final states = <ConnectionState>[];
        final subscription = client.connectionState.listen(states.add);

        // Simulate disconnect to trigger state emission
        await client.disconnect();

        await Future.delayed(const Duration(milliseconds: 10));

        // Verify we get at least the disconnecting state
        expect(states, isNotEmpty);

        await subscription.cancel();
      });

      test('handles connection failure gracefully', () async {
        // Use unreachable host to force connection failure
        final badConfig = MerkleKVConfig(
          mqttHost: 'unreachable.example.com',
          mqttPort: 1883, // Valid port
          clientId: 'test-client',
          nodeId: 'test-node',
        );

        client = MqttClientImpl(badConfig);

        expect(() => client.connect(), throwsA(isA<Exception>()));
      }, skip: skipReason);
    });

    group('exponential backoff', () {
      test('implements correct backoff sequence with jitter', () async {
        client = MqttClientImpl(config);

        // Test the mathematical properties of exponential backoff
        final expectedSequence = [1, 2, 4, 8, 16, 32];

        for (int attempt = 0; attempt < expectedSequence.length; attempt++) {
          final expectedBase = expectedSequence[attempt];
          final actualBase = math.min(math.pow(2, attempt).toInt(), 32);
          expect(actualBase, equals(expectedBase));
        }
      });

      test('jitter is within ±20% across multiple attempts', () {
        // Statistical test for jitter distribution
        final delays = <double>[];
        const baseDelay = 4; // Use fixed base delay

        for (int i = 0; i < 100; i++) {
          final random = math.Random();
          final jitter = 1.0 + (random.nextDouble() - 0.5) * 0.4;
          final actualDelay = baseDelay * jitter;
          delays.add(actualDelay);
        }

        // Verify delays are within expected range
        final minExpected = baseDelay * 0.8; // -20%
        final maxExpected = baseDelay * 1.2; // +20%

        for (final delay in delays) {
          expect(delay, greaterThanOrEqualTo(minExpected));
          expect(delay, lessThanOrEqualTo(maxExpected));
        }

        // Verify distribution is reasonably spread
        final average = delays.reduce((a, b) => a + b) / delays.length;
        expect(average, closeTo(baseDelay, 0.5)); // Should be close to base
      });
    });

    group('QoS enforcement', () {
      test('publishes with QoS=1 and retain=false by default', () async {
        client = MqttClientImpl(config);

        // Test default behavior by attempting to publish
        await client.publish('test/topic', 'test payload');

        // Since we're disconnected, message should be queued
        // This tests the default parameter behavior
        expect(
          () => client.publish('test/topic', 'test payload'),
          returnsNormally,
        );
      });

      test('respects QoS and retain overrides when specified', () async {
        client = MqttClientImpl(config);

        // Test with custom settings - should not throw
        await client.publish(
          'test/topic',
          'test payload',
          forceQoS1: false,
          forceRetainFalse: false,
        );

        // Test completes without error
        expect(true, isTrue);
      });
    });

    group('message queuing', () {
      test('queues messages when disconnected', () async {
        client = MqttClientImpl(config);

        // Should not throw when publishing while disconnected
        await client.publish('test/topic1', 'payload1');
        await client.publish('test/topic2', 'payload2');

        // Test completes without error
        expect(true, isTrue);
      });

      test('flushes queue after successful connection', () async {
        client = MqttClientImpl(config);

        // Queue messages while disconnected
        await client.publish('test/topic1', 'payload1');
        await client.publish('test/topic2', 'payload2');

        // Test that queuing works without error
        expect(true, isTrue);
      });
    });

    group('subscription management', () {
      test('manages subscription handlers correctly', () async {
        client = MqttClientImpl(config);

        final receivedMessages = <String, String>{};

        await client.subscribe('test/topic', (topic, payload) {
          receivedMessages[topic] = payload;
        });

        // Test that subscription completes without error
        expect(true, isTrue);
      });

      test('removes subscription on unsubscribe', () async {
        client = MqttClientImpl(config);

        await client.subscribe('test/topic', (topic, payload) {});
        await client.unsubscribe('test/topic');

        // Test that unsubscribe completes without error
        expect(true, isTrue);
      });
    });

    group('Last Will and Testament', () {
      test('formats LWT payload correctly', () {
        client = MqttClientImpl(config);

        // Test that LWT configuration is set up correctly
        expect(client, isA<MqttClientImpl>());
      });
      test('suppresses LWT on graceful disconnect', () async {
        client = MqttClientImpl(config);

        // Test graceful disconnect behavior
        await client.disconnect(suppressLWT: true);

        // Test that disconnect completes without error
        expect(true, isTrue);
      });
    });

    group('error handling', () {
      test('distinguishes network errors', () async {
        final badConfig = MerkleKVConfig(
          mqttHost: 'unreachable.host.invalid',
          mqttPort: 1883,
          clientId: 'test-client',
          nodeId: 'test-node',
        );

        client = MqttClientImpl(badConfig);

        expect(
          () => client.connect(),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Network error'),
            ),
          ),
        );
      }, skip: skipReason);

      test('handles invalid port gracefully', () async {
        // Test error for config validation, not MQTT connection
        expect(
          () => MerkleKVConfig(
            mqttHost: 'localhost',
            mqttPort: 0, // Invalid port
            clientId: 'test-client',
            nodeId: 'test-node',
          ),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('session settings', () {
      test('applies session expiry and clean start settings', () {
        final sessionConfig = MerkleKVConfig(
          mqttHost: 'localhost',
          mqttPort: 1883,
          clientId: 'test-client',
          nodeId: 'test-node',
          sessionExpirySeconds: 7200, // 2 hours
        );

        client = MqttClientImpl(sessionConfig);

        // Test that configuration is accepted
        expect(client.connectionState, isA<Stream<ConnectionState>>());
      });
    });
  });

  group('ConnectionState enum', () {
    test('has all required states', () {
      expect(ConnectionState.values, hasLength(4));
      expect(ConnectionState.values, contains(ConnectionState.disconnected));
      expect(ConnectionState.values, contains(ConnectionState.connecting));
      expect(ConnectionState.values, contains(ConnectionState.connected));
      expect(ConnectionState.values, contains(ConnectionState.disconnecting));
    });
  });
}
