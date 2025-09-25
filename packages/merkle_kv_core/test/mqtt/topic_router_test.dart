import 'dart:async';
import 'package:test/test.dart';
import 'package:merkle_kv_core/src/config/merkle_kv_config.dart';
import 'package:merkle_kv_core/src/config/invalid_config_exception.dart';
import 'package:merkle_kv_core/src/mqtt/connection_state.dart';
import 'package:merkle_kv_core/src/mqtt/mqtt_client_interface.dart';
import 'package:merkle_kv_core/src/mqtt/topic_router.dart';
import 'package:merkle_kv_core/src/mqtt/topic_authorization.dart';

/// Mock MQTT client for testing
class MockMqttClient implements MqttClientInterface {
  final StreamController<ConnectionState> _connectionStateController =
      StreamController<ConnectionState>.broadcast();

  final List<String> subscribedTopics = [];
  final Map<String, void Function(String, String)> subscriptionHandlers = {};
  final List<PublishCall> publishCalls = [];

  @override
  Stream<ConnectionState> get connectionState =>
      _connectionStateController.stream;

  @override
  ConnectionState get currentConnectionState => ConnectionState.connected;

  /// Simulate connection state change
  void simulateConnectionState(ConnectionState state) {
    _connectionStateController.add(state);
  }

  @override
  Future<void> connect() async {
    simulateConnectionState(ConnectionState.connecting);
    await Future.delayed(const Duration(milliseconds: 1));
    simulateConnectionState(ConnectionState.connected);
  }

  @override
  Future<void> disconnect({bool suppressLWT = true}) async {
    simulateConnectionState(ConnectionState.disconnecting);
    await Future.delayed(const Duration(milliseconds: 1));
    simulateConnectionState(ConnectionState.disconnected);
  }

  @override
  Future<void> subscribe(
    String topic,
    void Function(String, String) handler,
  ) async {
    subscribedTopics.add(topic);
    subscriptionHandlers[topic] = handler;
  }

  @override
  Future<void> unsubscribe(String topic) async {
    subscribedTopics.remove(topic);
    subscriptionHandlers.remove(topic);
  }

  @override
  Future<void> publish(
    String topic,
    String payload, {
    bool forceQoS1 = true,
    bool forceRetainFalse = true,
  }) async {
    publishCalls.add(
      PublishCall(
        topic: topic,
        payload: payload,
        qos1: forceQoS1,
        retainFalse: forceRetainFalse,
      ),
    );
  }

  /// Simulate receiving a message
  void simulateMessage(String topic, String payload) {
    final handler = subscriptionHandlers[topic];
    if (handler != null) {
      handler(topic, payload);
    }
  }

  /// Reset mock state
  void reset() {
    subscribedTopics.clear();
    subscriptionHandlers.clear();
    publishCalls.clear();
  }

  /// Dispose mock resources
  Future<void> dispose() async {
    await _connectionStateController.close();
  }
}

/// Represents a publish call made to the mock client
class PublishCall {
  final String topic;
  final String payload;
  final bool qos1;
  final bool retainFalse;

  const PublishCall({
    required this.topic,
    required this.payload,
    required this.qos1,
    required this.retainFalse,
  });

  @override
  String toString() =>
      'PublishCall(topic: $topic, payload: $payload, qos1: $qos1, retainFalse: $retainFalse)';
}

void main() {
  group('TopicRouterImpl', () {
    late MerkleKVConfig config;
    late MockMqttClient mockClient;
    late TopicRouterImpl router;

    setUp(() {
      config = MerkleKVConfig(
        mqttHost: 'localhost',
        clientId: 'test-client',
        nodeId: 'test-node',
        topicPrefix: 'test/prefix',
      );
      mockClient = MockMqttClient();
      router = TopicRouterImpl(config, mockClient);
    });

    tearDown(() async {
      await router.dispose();
      await mockClient.dispose();
    });

    group('subscription management', () {
      test('subscribeToCommands subscribes to correct topic', () async {
        String? receivedTopic;
        String? receivedPayload;

        await router.subscribeToCommands((topic, payload) {
          receivedTopic = topic;
          receivedPayload = payload;
        });

        expect(
          mockClient.subscribedTopics,
          contains('test/prefix/test-client/cmd'),
        );

        // Simulate receiving a command
        mockClient.simulateMessage(
          'test/prefix/test-client/cmd',
          'test-command',
        );

        expect(receivedTopic, equals('test/prefix/test-client/cmd'));
        expect(receivedPayload, equals('test-command'));
      });

      test('subscribeToReplication subscribes to correct topic', () async {
        String? receivedTopic;
        String? receivedPayload;

        await router.subscribeToReplication((topic, payload) {
          receivedTopic = topic;
          receivedPayload = payload;
        });

        expect(
          mockClient.subscribedTopics,
          contains('test/prefix/replication/events'),
        );

        // Simulate receiving a replication event
        mockClient.simulateMessage(
          'test/prefix/replication/events',
          'replication-event',
        );

        expect(receivedTopic, equals('test/prefix/replication/events'));
        expect(receivedPayload, equals('replication-event'));
      });

      test('multiple devices can receive replication events', () async {
        final receivedMessages = <String, List<String>>{};

        // Simulate multiple devices subscribing to replication
        await router.subscribeToReplication((topic, payload) {
          receivedMessages.putIfAbsent('device1', () => []).add(payload);
        });

        // Create second router for different device
        final config2 = MerkleKVConfig(
          mqttHost: 'localhost',
          clientId: 'device-2',
          nodeId: 'node-2',
          topicPrefix: 'test/prefix',
        );
        final mockClient2 = MockMqttClient();
        final router2 = TopicRouterImpl(config2, mockClient2);

        await router2.subscribeToReplication((topic, payload) {
          receivedMessages.putIfAbsent('device2', () => []).add(payload);
        });

        // Both should subscribe to same replication topic
        expect(
          mockClient.subscribedTopics,
          contains('test/prefix/replication/events'),
        );
        expect(
          mockClient2.subscribedTopics,
          contains('test/prefix/replication/events'),
        );

        // Simulate replication message to both
        mockClient.simulateMessage('test/prefix/replication/events', 'event1');
        mockClient2.simulateMessage('test/prefix/replication/events', 'event1');

        expect(receivedMessages['device1'], equals(['event1']));
        expect(receivedMessages['device2'], equals(['event1']));

        await router2.dispose();
        await mockClient2.dispose();
      });
    });

    group('publishing with QoS enforcement', () {
      test(
        'publishCommand publishes to own canonical topic with QoS=1, retain=false',
        () async {
          await router.publishCommand('test-client', 'command-payload');

          expect(mockClient.publishCalls, hasLength(1));
          final call = mockClient.publishCalls.first;

          expect(call.topic, equals('test/prefix/test-client/cmd'));
          expect(call.payload, equals('command-payload'));
          expect(call.qos1, isTrue);
          expect(call.retainFalse, isTrue);
        },
      );

      test(
        'publishCommand denies cross-client target even with QoS enforcement',
        () async {
          expect(
            () => router.publishCommand('target-device', 'command-payload'),
            throwsA(isA<AuthorizationException>()),
          );
          expect(mockClient.publishCalls, isEmpty);
        },
      );

      test(
        'publishResponse publishes to own response topic with QoS=1, retain=false',
        () async {
          await router.publishResponse('response-payload');

          expect(mockClient.publishCalls, hasLength(1));
          final call = mockClient.publishCalls.first;

          expect(call.topic, equals('test/prefix/test-client/res'));
          expect(call.payload, equals('response-payload'));
          expect(call.qos1, isTrue);
          expect(call.retainFalse, isTrue);
        },
      );

      test(
        'publishReplication publishes to replication topic with QoS=1, retain=false',
        () async {
          await router.publishReplication('replication-payload');

          expect(mockClient.publishCalls, hasLength(1));
          final call = mockClient.publishCalls.first;

          expect(call.topic, equals('test/prefix/replication/events'));
          expect(call.payload, equals('replication-payload'));
          expect(call.qos1, isTrue);
          expect(call.retainFalse, isTrue);
        },
      );
    });

    group('target clientId validation', () {
      test('publishCommand validates target clientId', () async {
        // Test invalid target clientId
        expect(
          () => router.publishCommand('invalid/client', 'payload'),
          throwsA(isA<ArgumentError>()),
        );

        expect(
          () => router.publishCommand('client+wildcard', 'payload'),
          throwsA(isA<ArgumentError>()),
        );

        expect(
          () => router.publishCommand('client#wildcard', 'payload'),
          throwsA(isA<ArgumentError>()),
        );

        // Test empty target clientId
        expect(
          () => router.publishCommand('', 'payload'),
          throwsA(isA<ArgumentError>()),
        );

        // Test too long target clientId
        final longClientId = 'a' * 129;
        expect(
          () => router.publishCommand(longClientId, 'payload'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('publishCommand accepts own clientId as valid target', () async {
        await router.publishCommand('test-client', 'payload');
        expect(mockClient.publishCalls, hasLength(1));
      });

      test('publishCommand denies different clientId despite valid format', () async {
        expect(
          () => router.publishCommand('valid-client-123', 'payload'),
          throwsA(isA<AuthorizationException>()),
        );
        expect(mockClient.publishCalls, isEmpty);
      });
    });

    group('reconnection and auto re-subscribe', () {
      test('restores subscriptions after reconnection', () async {
        // Set up subscriptions
        await router.subscribeToCommands((topic, payload) {});
        await router.subscribeToReplication((topic, payload) {});

        expect(mockClient.subscribedTopics, hasLength(2));
        mockClient.reset(); // Clear subscription history

        // Simulate disconnection and reconnection
        mockClient.simulateConnectionState(ConnectionState.disconnected);
        await Future.delayed(const Duration(milliseconds: 5));

        mockClient.simulateConnectionState(ConnectionState.connecting);
        await Future.delayed(const Duration(milliseconds: 5));

        mockClient.simulateConnectionState(ConnectionState.connected);
        await Future.delayed(const Duration(milliseconds: 5));

        // Verify subscriptions were restored
        expect(
          mockClient.subscribedTopics,
          contains('test/prefix/test-client/cmd'),
        );
        expect(
          mockClient.subscribedTopics,
          contains('test/prefix/replication/events'),
        );
      });

      test('only restores active subscriptions', () async {
        // Only subscribe to commands, not replication
        await router.subscribeToCommands((topic, payload) {});

        expect(mockClient.subscribedTopics, hasLength(1));
        mockClient.reset();

        // Simulate reconnection
        mockClient.simulateConnectionState(ConnectionState.connected);
        await Future.delayed(const Duration(milliseconds: 5));

        // Only command subscription should be restored
        expect(
          mockClient.subscribedTopics,
          contains('test/prefix/test-client/cmd'),
        );
        expect(
          mockClient.subscribedTopics,
          isNot(contains('test/prefix/replication/events')),
        );
      });

      test('handles multiple reconnection cycles', () async {
        await router.subscribeToCommands((topic, payload) {});

        // Simulate multiple disconnection/reconnection cycles
        for (int i = 0; i < 3; i++) {
          mockClient.reset();

          mockClient.simulateConnectionState(ConnectionState.disconnected);
          await Future.delayed(const Duration(milliseconds: 1));

          mockClient.simulateConnectionState(ConnectionState.connected);
          await Future.delayed(const Duration(milliseconds: 1));

          expect(
            mockClient.subscribedTopics,
            contains('test/prefix/test-client/cmd'),
          );
        }
      });
    });

    group('edge cases and error handling', () {
      test('handles dispose without active subscriptions', () async {
        // Should not throw when disposing without subscriptions
        await router.dispose();
      });

      test('handles dispose with active subscriptions', () async {
        await router.subscribeToCommands((topic, payload) {});
        await router.subscribeToReplication((topic, payload) {});

        // Should not throw when disposing with subscriptions
        await router.dispose();
      });

      test('handles large payloads correctly', () async {
        final largePayload = 'x' * 10000; // 10KB payload

        await router.publishResponse(largePayload);

        expect(mockClient.publishCalls, hasLength(1));
        expect(mockClient.publishCalls.first.payload, equals(largePayload));
      });

      test('maintains handler references across reconnections', () async {
        final receivedMessages = <String>[];

        await router.subscribeToCommands((topic, payload) {
          receivedMessages.add(payload);
        });

        // Test initial message
        mockClient.simulateMessage('test/prefix/test-client/cmd', 'message1');
        expect(receivedMessages, equals(['message1']));

        // Simulate reconnection
        mockClient.simulateConnectionState(ConnectionState.disconnected);
        mockClient.simulateConnectionState(ConnectionState.connected);
        await Future.delayed(const Duration(milliseconds: 5));

        // Test message after reconnection
        mockClient.simulateMessage('test/prefix/test-client/cmd', 'message2');
        expect(receivedMessages, equals(['message1', 'message2']));
      });
    });

    group('topic scheme integration', () {
      test('uses normalized topic prefix from config', () async {
        final configWithUnnormalizedPrefix = MerkleKVConfig(
          mqttHost: 'localhost',
          clientId: 'client-1',
          nodeId: 'node-1',
          topicPrefix: '  //test/prefix//  ', // Unnormalized
        );

        final routerWithNormalizedPrefix = TopicRouterImpl(
          configWithUnnormalizedPrefix,
          mockClient,
        );

        await routerWithNormalizedPrefix.subscribeToCommands(
          (topic, payload) {},
        );

        // Should normalize to 'test/prefix'
        expect(
          mockClient.subscribedTopics,
          contains('test/prefix/client-1/cmd'),
        );

        await routerWithNormalizedPrefix.dispose();
      });

      test('handles different topic prefix configurations', () async {
        final configs = [
          ('simple', 'simple/client-1/cmd'),
          ('complex/multi/level', 'complex/multi/level/client-1/cmd'),
          ('under_scores-and-dashes', 'under_scores-and-dashes/client-1/cmd'),
        ];

        for (final (prefix, expectedTopic) in configs) {
          final testConfig = MerkleKVConfig(
            mqttHost: 'localhost',
            clientId: 'client-1',
            nodeId: 'node-1',
            topicPrefix: prefix,
          );

          final testClient = MockMqttClient();
          final testRouter = TopicRouterImpl(testConfig, testClient);

          await testRouter.subscribeToCommands((topic, payload) {});

          expect(testClient.subscribedTopics, contains(expectedTopic));

          await testRouter.dispose();
          await testClient.dispose();
        }
      });
    });
  });
}
