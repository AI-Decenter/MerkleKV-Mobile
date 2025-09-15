import 'dart:convert';
import 'package:test/test.dart';
import '../../../lib/src/mqtt/topic_router.dart';
import '../../../lib/src/mqtt/topic_validator.dart';
import '../../../lib/src/mqtt/connection_state.dart';
import '../../../lib/src/config/merkle_kv_config.dart';
import '../../../lib/src/config/invalid_config_exception.dart';
import '../../utils/generators.dart';
import '../../utils/mock_helpers.dart';

void main() {
  group('Topic Router Unit Tests', () {
    late MerkleKVConfig config;
    late MockMqttClient mockClient;
    late TopicRouterImpl router;

    setUp(() {
      config = MerkleKVConfig.create(
        mqttHost: 'localhost',
        clientId: 'test-client',
        nodeId: 'test-node',
        topicPrefix: 'test/prefix',
      );
      mockClient = MockMqttClient();
      router = TopicRouterImpl(config, mockClient);
    });

    tearDown(() async {
      try {
        await mockClient.disconnect();
        await router.dispose();
        await mockClient.dispose();
        await Future.delayed(const Duration(milliseconds: 5));
      } catch (e) {
        // Ensure tearDown doesn't fail tests
      }
    });

    group('Basic Functionality', () {
      test('can create router with valid config', () {
        expect(router, isNotNull);
      });

      test('can publish command messages', () async {
        await router.publishCommand('target-device', 'test-command');
        expect(mockClient.publishCalls, hasLength(1));
        final call = mockClient.publishCalls.first;
        expect(call.topic, contains('test/prefix'));
        expect(call.payload, equals('test-command'));
      });

      test('can publish response messages', () async {
        await router.publishResponse('test-response');
        expect(mockClient.publishCalls, hasLength(1));
        final call = mockClient.publishCalls.first;
        expect(call.topic, contains('test/prefix'));
        expect(call.payload, equals('test-response'));
      });

      test('can publish replication messages', () async {
        await router.publishReplication('test-replication');
        expect(mockClient.publishCalls, hasLength(1));
        final call = mockClient.publishCalls.first;
        expect(call.topic, contains('test/prefix'));
        expect(call.payload, equals('test-replication'));
      });

      test('can subscribe to commands', () async {
        await router.subscribeToCommands((topic, payload) {});
        expect(mockClient.subscribedTopics, hasLength(1));
        expect(mockClient.subscribedTopics.first, contains('test/prefix'));
        expect(mockClient.subscribedTopics.first, contains('cmd'));
      });

      test('can subscribe to replication', () async {
        await router.subscribeToReplication((topic, payload) {});
        expect(mockClient.subscribedTopics, hasLength(1));
        expect(mockClient.subscribedTopics.first, contains('test/prefix'));
        expect(mockClient.subscribedTopics.first, contains('replication'));
      });

      test('handlers receive messages correctly', () async {
        String? receivedTopic;
        String? receivedPayload;
        
        await router.subscribeToCommands((topic, payload) {
          receivedTopic = topic;
          receivedPayload = payload;
        });
        
        mockClient.simulateMessage('test/prefix/test-client/cmd', 'test-command');
        
        await Future.delayed(const Duration(milliseconds: 10));
        
        expect(receivedTopic, equals('test/prefix/test-client/cmd'));
        expect(receivedPayload, equals('test-command'));
      });

      test('disposal works correctly', () async {
        await router.dispose();
        
        // Operations after disposal should still work (disposal only cleans up subscriptions)
        expect(
          () => router.publishCommand('target', 'payload'),
          returnsNormally,
        );
      });
    });
  });
}