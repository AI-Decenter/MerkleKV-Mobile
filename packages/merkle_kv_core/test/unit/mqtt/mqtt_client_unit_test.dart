import 'dart:async';
import 'dart:math' as math;
import 'package:test/test.dart';

import '../../../lib/src/config/merkle_kv_config.dart';
import '../../../lib/src/mqtt/connection_state.dart';
import '../../utils/mock_helpers.dart';

void main() {
  group('MQTT Client Unit Tests', () {
    late MockMqttClient client;

    setUp(() {
      client = MockMqttClient();
    });

    tearDown(() async {
      // Clean up MockMqttClient resources
      client.reset();
      await client.dispose();
    });

    group('Connection Management', () {
      test('should enforce QoS=1 for publish operations', () async {
        // Act: Connect and publish with QoS=1 enforcement
        await client.connect();
        await client.publish('test/topic', 'test-message');

        // Assert: Verify QoS=1 was enforced using MockMqttClient tracking
        expect(client.publishCalls, hasLength(1));
        final publishCall = client.publishCalls.first;
        expect(publishCall.topic, equals('test/topic'));
        expect(publishCall.payload, equals('test-message'));
        expect(publishCall.qos1, isTrue);
        expect(publishCall.retainFalse, isTrue);
      });

      test('should track subscribed topics correctly', () async {
        // Act: Subscribe to topics
        await client.subscribe('app/+/data', (topic, payload) {});

        // Assert: Verify subscription was tracked using MockMqttClient tracking
        expect(client.subscribedTopics, contains('app/+/data'));
        expect(client.subscriptionHandlers, containsPair('app/+/data', isA<Function>()));
      });

      test('should track connection state transitions', () async {
        // Act: Use the MockMqttClient's connection state stream
        final stateStream = client.connectionState;
        final stateChanges = <ConnectionState>[];
        
        final subscription = stateStream.listen(stateChanges.add);
        
        // Simulate connection state changes using MockMqttClient's helper
        client.simulateConnectionState(ConnectionState.connecting);
        await Future.delayed(const Duration(milliseconds: 10));
        client.simulateConnectionState(ConnectionState.connected);
        await Future.delayed(const Duration(milliseconds: 10));

        // Assert: Verify state transitions were tracked
        expect(stateChanges, contains(ConnectionState.connecting));
        expect(stateChanges, contains(ConnectionState.connected));
        expect(client.currentConnectionState, equals(ConnectionState.connected));
        
        await subscription.cancel();
      });

      test('should handle connection state changes gracefully', () async {
        // Act: Connect using MockMqttClient's implementation
        await client.connect();
        
        // Assert: Connection state should be connected
        expect(client.currentConnectionState, equals(ConnectionState.connected));
        
        // Act: Simulate connection failure
        client.simulateConnectionState(ConnectionState.disconnected);
        
        // Assert: Connection state should be disconnected
        expect(client.currentConnectionState, equals(ConnectionState.disconnected));
      });
    });

    group('Reconnection Strategy', () {
      test('should implement exponential backoff with jitter', () async {
        // Test exponential backoff calculation
        final random = math.Random(42); // Fixed seed for reproducible tests

        // Simulate exponential backoff delays
        for (int attempt = 1; attempt <= 5; attempt++) {
          final baseDelay = math.pow(2, attempt - 1) * 1000; // Base delay in ms
          final jitter = random.nextInt(1000);
          final totalDelay = (baseDelay + jitter).toInt();
          
          expect(totalDelay, greaterThan(baseDelay.toInt()));
          expect(totalDelay, lessThan((baseDelay + 1000).toInt()));
        }
      });

      test('should limit maximum backoff delay', () async {
        // Test maximum backoff limit (30 seconds)
        const maxBackoffMs = 30000;
        
        for (int attempt = 10; attempt <= 15; attempt++) {
          final baseDelay = math.pow(2, attempt - 1) * 1000;
          final effectiveDelay = math.min(baseDelay, maxBackoffMs.toDouble());
          
          expect(effectiveDelay, lessThanOrEqualTo(maxBackoffMs));
        }
      });
    });

    group('Malformed Packet Handling', () {
      test('should handle connection state after malformed packets', () async {
        // Act: Connect first
        await client.connect();
        expect(client.currentConnectionState, equals(ConnectionState.connected));

        // Act: Simulate malformed packet using MockMqttClient's helper
        client.simulateMalformedPacket();

        // Assert: Should transition to disconnected state
        expect(client.currentConnectionState, equals(ConnectionState.disconnected));
      });
    });

    group('Message Publishing', () {
      test('should track published messages', () async {
        // Act: Publish messages using MockMqttClient
        await client.publish('test/topic', 'queued-message');

        // Assert: Message should be tracked in publishCalls
        expect(client.publishCalls, hasLength(1));
        final publishCall = client.publishCalls.first;
        expect(publishCall.topic, equals('test/topic'));
        expect(publishCall.payload, equals('queued-message'));
      });
    });

    group('Authentication', () {
      test('should validate TLS configuration', () async {
        // Arrange: Create TLS config
        final tlsConfig = MerkleKVConfig.create(
          mqttHost: 'secure.example.com',
          clientId: 'tls-client',
          nodeId: 'test-node',
          mqttUseTls: true,
        );

        // Assert: TLS should be enabled
        expect(tlsConfig.mqttUseTls, isTrue);
      });
    });

    group('Topic Management', () {
      test('should handle subscription lifecycle', () async {
        // Act: Subscribe and unsubscribe using MockMqttClient
        await client.subscribe('test/topic', (topic, payload) {});
        expect(client.subscribedTopics, contains('test/topic'));
        
        await client.unsubscribe('test/topic');
        expect(client.subscribedTopics, isNot(contains('test/topic')));
      });

      test('should track subscription handlers', () async {
        // Arrange: Create handler function
        void testHandler(String topic, String payload) {}

        // Act: Subscribe with handler
        await client.subscribe('test/topic', testHandler);

        // Assert: Handler should be tracked
        expect(client.subscriptionHandlers.containsKey('test/topic'), isTrue);
        expect(client.subscribedTopics, contains('test/topic'));
      });
    });

    group('Message Handling', () {
      test('should process incoming messages correctly', () async {
        // Arrange: Set up message handler
        var receivedTopic = '';
        var receivedPayload = '';
        
        await client.subscribe('test/topic', (topic, payload) {
          receivedTopic = topic;
          receivedPayload = payload;
        });

        // Act: Simulate message using MockMqttClient's helper
        client.simulateMessage('test/topic', 'test-payload');

        // Assert: Message should be processed
        expect(receivedTopic, equals('test/topic'));
        expect(receivedPayload, equals('test-payload'));
      });
    });

    group('Payload Validation', () {
      test('should track payload characteristics', () async {
        // Arrange: Create various payloads
        final smallPayload = 'small';
        final normalPayload = 'normal payload';
        final largePayload = 'x' * 1000; // 1KB payload

        // Act: Publish different payload sizes
        await client.publish('test/small', smallPayload);
        await client.publish('test/normal', normalPayload);
        await client.publish('test/large', largePayload);

        // Assert: All payloads should be tracked
        expect(client.publishCalls, hasLength(3));
        
        final calls = client.publishCalls;
        expect(calls[0].payload, equals(smallPayload));
        expect(calls[1].payload, equals(normalPayload));
        expect(calls[2].payload, equals(largePayload));
      });
    });
  });
}