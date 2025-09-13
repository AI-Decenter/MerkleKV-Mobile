import 'package:test/test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:merkle_kv_core/src/config/merkle_kv_config.dart';
import 'package:merkle_kv_core/src/mqtt/topic_router.dart';
import 'package:merkle_kv_core/src/mqtt/topic_scheme.dart';
import 'package:merkle_kv_core/src/mqtt/topic_validator.dart';
import 'package:merkle_kv_core/src/mqtt/mqtt_client_interface.dart';

// Generate mocks
@GenerateMocks([MqttClientInterface])
import 'topic_router_test.mocks.dart';

void main() {
  group('Topic Router', () {
    late MerkleKVConfig config;
    late MockMqttClientInterface mockMqttClient;
    late TopicRouterImpl topicRouter;
    late TopicValidator topicValidator;

    setUp(() {
      config = MerkleKVConfig.create(
        mqttHost: 'test-broker.local',
        clientId: 'test-client-123',
        nodeId: 'test-node',
        topicPrefix: 'merkle-kv',
      );
      
      mockMqttClient = MockMqttClientInterface();
      topicValidator = TopicValidator();
      topicRouter = TopicRouterImpl(mockMqttClient, config, topicValidator);
    });

    tearDown(() async {
      await topicRouter.dispose();
    });

    group('Canonical Topic Generation', () {
      test('canonical topic generation: {prefix}/{client_id}/cmd|res', () {
        final commandTopic = TopicScheme.commandTopic(config.topicPrefix, 'target-client');
        final responseTopic = TopicScheme.responseTopic(config.topicPrefix, config.clientId);
        
        expect(commandTopic, equals('merkle-kv/target-client/cmd'));
        expect(responseTopic, equals('merkle-kv/test-client-123/res'));
      });

      test('replication topic follows standard pattern', () {
        final replicationTopic = TopicScheme.replicationTopic(config.topicPrefix);
        expect(replicationTopic, equals('merkle-kv/replication/events'));
      });

      test('topic generation with special characters in client ID', () {
        final specialConfig = MerkleKVConfig.create(
          mqttHost: 'test-broker.local',
          clientId: 'client.with-special_chars123',
          nodeId: 'test-node',
          topicPrefix: 'app',
        );
        
        final commandTopic = TopicScheme.commandTopic(specialConfig.topicPrefix, specialConfig.clientId);
        expect(commandTopic, equals('app/client.with-special_chars123/cmd'));
        
        // Verify topic is valid MQTT topic
        expect(topicValidator.isValidTopic(commandTopic), isTrue);
      });

      test('topic hierarchy maintains consistency', () {
        final topics = [
          TopicScheme.commandTopic(config.topicPrefix, 'client1'),
          TopicScheme.commandTopic(config.topicPrefix, 'client2'),
          TopicScheme.responseTopic(config.topicPrefix, 'client1'),
          TopicScheme.responseTopic(config.topicPrefix, 'client2'),
        ];
        
        // All topics should share the same prefix
        for (final topic in topics) {
          expect(topic, startsWith('${config.topicPrefix}/'));
        }
        
        // Command and response topics should be distinguishable
        expect(topics[0], endsWith('/cmd')); // client1 command
        expect(topics[2], endsWith('/res')); // client1 response
      });
    });

    group('Topic Validation', () {
      test('wildcard injection prevented: reject +,# characters', () {
        final maliciousTopics = [
          'merkle-kv/+/cmd',           // Single-level wildcard
          'merkle-kv/#',               // Multi-level wildcard
          'merkle-kv/client+evil/cmd', // Embedded wildcard
          'merkle-kv/client#evil/res', // Embedded wildcard
          'merkle-kv/client/+',        // Wildcard in topic level
          'merkle-kv/client/#/cmd',    // Wildcard in middle
        ];
        
        for (final maliciousTopic in maliciousTopics) {
          expect(
            topicValidator.isValidTopic(maliciousTopic),
            isFalse,
            reason: 'Topic with wildcards should be rejected: $maliciousTopic',
          );
        }
      });

      test('topic length validation: max 100 UTF-8 bytes', () {
        // Valid topic at limit (100 bytes)
        final validTopic = 'a' * 100;
        expect(topicValidator.isValidTopic(validTopic), isTrue);
        
        // Invalid topic over limit (101 bytes)
        final invalidTopic = 'a' * 101;
        expect(topicValidator.isValidTopic(invalidTopic), isFalse,
            reason: 'Topics over 100 UTF-8 bytes should be rejected');
      });

      test('UTF-8 multi-byte characters count correctly in topic length', () {
        // Each € character is 3 bytes in UTF-8
        // 33 × 3 = 99 bytes (valid)
        final validMultiByteTopic = '€' * 33;
        expect(topicValidator.isValidTopic(validMultiByteTopic), isTrue);
        
        // 34 × 3 = 102 bytes (invalid)
        final invalidMultiByteTopic = '€' * 34;
        expect(topicValidator.isValidTopic(invalidMultiByteTopic), isFalse,
            reason: 'Multi-byte UTF-8 characters should count as multiple bytes');
      });

      test('empty topic levels rejected', () {
        final invalidTopics = [
          'merkle-kv//cmd',     // Empty level
          '/merkle-kv/client',  // Leading empty level
          'merkle-kv/client/',  // Trailing empty level
          '///',                // Multiple empty levels
        ];
        
        for (final invalidTopic in invalidTopics) {
          expect(
            topicValidator.isValidTopic(invalidTopic),
            isFalse,
            reason: 'Topic with empty levels should be rejected: $invalidTopic',
          );
        }
      });

      test('control characters in topics rejected', () {
        final controlCharTopics = [
          'merkle-kv/client\u0000/cmd', // Null character
          'merkle-kv/client\u001F/cmd', // Unit separator
          'merkle-kv/client\u007F/cmd', // Delete character
          'merkle-kv/\u0001client/cmd', // Start of heading
        ];
        
        for (final controlTopic in controlCharTopics) {
          expect(
            topicValidator.isValidTopic(controlTopic),
            isFalse,
            reason: 'Topic with control characters should be rejected: ${controlTopic.codeUnits}',
          );
        }
      });
    });

    group('Multi-tenant Isolation', () {
      test('multi-tenant isolation through prefix validation', () {
        final tenant1Config = MerkleKVConfig.create(
          mqttHost: 'test-broker.local',
          clientId: 'client1',
          nodeId: 'node1',
          topicPrefix: 'tenant1',
        );
        
        final tenant2Config = MerkleKVConfig.create(
          mqttHost: 'test-broker.local',
          clientId: 'client1', // Same client ID, different tenant
          nodeId: 'node1',
          topicPrefix: 'tenant2',
        );
        
        final tenant1CommandTopic = TopicScheme.commandTopic(tenant1Config.topicPrefix, 'target');
        final tenant2CommandTopic = TopicScheme.commandTopic(tenant2Config.topicPrefix, 'target');
        
        expect(tenant1CommandTopic, equals('tenant1/target/cmd'));
        expect(tenant2CommandTopic, equals('tenant2/target/cmd'));
        expect(tenant1CommandTopic, isNot(equals(tenant2CommandTopic)),
            reason: 'Different tenants should have isolated topic spaces');
      });

      test('cross-tenant topic access prevention', () {
        final router1 = TopicRouterImpl(mockMqttClient, config, topicValidator);
        
        // Attempt to publish to different tenant's topic
        final maliciousTopic = 'different-tenant/target-client/cmd';
        
        expect(
          () => router1.publishToTopic(maliciousTopic, 'malicious-payload'),
          throwsA(isA<ArgumentError>()),
          reason: 'Should prevent publishing to different tenant topics',
        );
      });

      test('tenant prefix validation strictness', () {
        final validPrefixes = ['tenant1', 'app-v2', 'production.env', 'test_env'];
        final invalidPrefixes = ['', 'tenant with spaces', 'tenant+wildcard', 'tenant#hash'];
        
        for (final validPrefix in validPrefixes) {
          expect(
            topicValidator.isValidPrefix(validPrefix),
            isTrue,
            reason: 'Valid prefix should be accepted: $validPrefix',
          );
        }
        
        for (final invalidPrefix in invalidPrefixes) {
          expect(
            topicValidator.isValidPrefix(invalidPrefix),
            isFalse,
            reason: 'Invalid prefix should be rejected: $invalidPrefix',
          );
        }
      });
    });

    group('Subscription Management', () {
      test('command subscription with proper topic pattern', () async {
        var receivedMessages = <String>[];
        
        await topicRouter.subscribeToCommands((topic, payload) {
          receivedMessages.add(payload);
        });
        
        // Verify subscription was made to correct topic
        final expectedTopic = TopicScheme.commandTopic(config.topicPrefix, config.clientId);
        verify(mockMqttClient.subscribe(expectedTopic, any)).called(1);
      });

      test('replication subscription with wildcard pattern', () async {
        var receivedMessages = <String>[];
        
        await topicRouter.subscribeToReplication((topic, payload) {
          receivedMessages.add(payload);
        });
        
        // Verify subscription to replication topic
        final expectedTopic = TopicScheme.replicationTopic(config.topicPrefix);
        verify(mockMqttClient.subscribe(expectedTopic, any)).called(1);
      });

      test('automatic re-subscription after reconnection', () async {
        await topicRouter.subscribeToCommands((topic, payload) {});
        await topicRouter.subscribeToReplication((topic, payload) {});
        
        // Simulate disconnection and reconnection
        topicRouter.onConnectionStateChanged(ConnectionState.disconnected);
        topicRouter.onConnectionStateChanged(ConnectionState.connected);
        
        await Future.delayed(const Duration(milliseconds: 100));
        
        // Should re-subscribe to both topics
        final commandTopic = TopicScheme.commandTopic(config.topicPrefix, config.clientId);
        final replicationTopic = TopicScheme.replicationTopic(config.topicPrefix);
        
        verify(mockMqttClient.subscribe(commandTopic, any)).called(2); // Initial + re-sub
        verify(mockMqttClient.subscribe(replicationTopic, any)).called(2); // Initial + re-sub
      });

      test('subscription cleanup on disposal', () async {
        await topicRouter.subscribeToCommands((topic, payload) {});
        await topicRouter.subscribeToReplication((topic, payload) {});
        
        await topicRouter.dispose();
        
        // Should unsubscribe from all topics
        verify(mockMqttClient.unsubscribe(any)).called(2);
      });
    });

    group('Message Publishing', () {
      test('command publishing to target client', () async {
        const targetClientId = 'target-client-456';
        const payload = '{"cmd": "GET", "key": "test-key"}';
        
        await topicRouter.publishCommand(targetClientId, payload);
        
        final expectedTopic = TopicScheme.commandTopic(config.topicPrefix, targetClientId);
        verify(mockMqttClient.publish(expectedTopic, payload)).called(1);
      });

      test('response publishing from current client', () async {
        const payload = '{"status": "OK", "value": "test-value"}';
        
        await topicRouter.publishResponse(payload);
        
        final expectedTopic = TopicScheme.responseTopic(config.topicPrefix, config.clientId);
        verify(mockMqttClient.publish(expectedTopic, payload)).called(1);
      });

      test('replication event publishing', () async {
        const payload = '{"type": "PUT", "key": "test-key", "value": "test-value"}';
        
        await topicRouter.publishReplication(payload);
        
        final expectedTopic = TopicScheme.replicationTopic(config.topicPrefix);
        verify(mockMqttClient.publish(expectedTopic, payload)).called(1);
      });

      test('payload size validation before publishing', () async {
        // Create oversized payload (>512KiB)
        final oversizedPayload = 'x' * (512 * 1024 + 1);
        
        expect(
          () => topicRouter.publishCommand('target', oversizedPayload),
          throwsA(isA<ArgumentError>()),
          reason: 'Oversized payloads should be rejected',
        );
      });
    });

    group('Error Handling', () {
      test('invalid topic publishing rejected', () async {
        const invalidTargetClient = 'client+with+wildcards';
        
        expect(
          () => topicRouter.publishCommand(invalidTargetClient, 'payload'),
          throwsA(isA<ArgumentError>()),
          reason: 'Invalid client IDs should be rejected',
        );
      });

      test('empty payload handling', () async {
        // Empty payloads should be allowed for tombstone messages
        await topicRouter.publishCommand('target-client', '');
        
        final expectedTopic = TopicScheme.commandTopic(config.topicPrefix, 'target-client');
        verify(mockMqttClient.publish(expectedTopic, '')).called(1);
      });

      test('null payload rejection', () async {
        expect(
          () => topicRouter.publishCommand('target-client', null),
          throwsA(isA<ArgumentError>()),
          reason: 'Null payloads should be rejected',
        );
      });

      test('malformed client ID handling', () async {
        final malformedClientIds = [
          '',           // Empty
          'client/cmd', // Contains topic separator
          'client res', // Contains space
          'client\u0000', // Contains null character
        ];
        
        for (final malformedId in malformedClientIds) {
          expect(
            () => topicRouter.publishCommand(malformedId, 'payload'),
            throwsA(isA<ArgumentError>()),
            reason: 'Malformed client ID should be rejected: $malformedId',
          );
        }
      });
    });

    group('Topic Scheme Compliance', () {
      test('topic scheme follows MQTT best practices', () {
        final topics = [
          TopicScheme.commandTopic('app', 'client1'),
          TopicScheme.responseTopic('app', 'client1'),
          TopicScheme.replicationTopic('app'),
        ];
        
        for (final topic in topics) {
          // Should not start or end with /
          expect(topic, isNot(startsWith('/')));
          expect(topic, isNot(endsWith('/')));
          
          // Should not contain double slashes
          expect(topic, isNot(contains('//')));
          
          // Should have reasonable depth (not too many levels)
          final levels = topic.split('/');
          expect(levels.length, lessThanOrEqualTo(4),
              reason: 'Topic should not be too deep: $topic');
        }
      });

      test('topic compatibility with MQTT spec', () {
        final topic = TopicScheme.commandTopic(config.topicPrefix, config.clientId);
        
        // MQTT topic name restrictions
        expect(topic.length, lessThanOrEqualTo(65535)); // MQTT spec limit
        expect(topic, isNot(contains('\u0000'))); // Null character not allowed
        expect(topic, isNot(contains('\uFEFF'))); // BOM not allowed
      });
    });
  });
}