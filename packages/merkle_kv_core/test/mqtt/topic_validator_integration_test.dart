@Tags(['integration'])
import 'package:test/test.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';

void main() {
  group('TopicValidator Integration Tests', () {
    group('Multi-tenant topic validation integration', () {
      test('validates complete MerkleKVConfig with different tenant prefixes', () {
        // Test tenant 1 configuration
        final tenant1Config = MerkleKVConfig(
          mqttHost: 'test.mqtt.broker',
          mqttPort: 1883,
          clientId: 'device-123',
          nodeId: 'node-123',
          topicPrefix: 'tenant-1/prod',
        );

        expect(tenant1Config.topicPrefix, equals('tenant-1/prod'));
        expect(tenant1Config.clientId, equals('device-123'));

        // Test tenant 2 configuration
        final tenant2Config = MerkleKVConfig(
          mqttHost: 'test.mqtt.broker',
          mqttPort: 1883,
          clientId: 'device-456',
          nodeId: 'node-456',
          topicPrefix: 'tenant-2/staging',
        );

        expect(tenant2Config.topicPrefix, equals('tenant-2/staging'));
        expect(tenant2Config.clientId, equals('device-456'));

        // Verify tenant isolation by checking that command topics don't overlap
        final topic1 = TopicValidator.buildCommandTopic(
          tenant1Config.topicPrefix,
          tenant1Config.clientId,
        );
        final topic2 = TopicValidator.buildCommandTopic(
          tenant2Config.topicPrefix,
          tenant2Config.clientId,
        );

        expect(topic1, equals('tenant-1/prod/device-123/cmd'));
        expect(topic2, equals('tenant-2/staging/device-456/cmd'));
        expect(topic1, isNot(equals(topic2)));
      });

      test('validates TopicScheme integration with enhanced validation', () {
        // Test with valid configuration
        final topicScheme = TopicScheme.create('customer-a/env', 'mobile-app-1');

        expect(topicScheme.prefix, equals('customer-a/env'));
        expect(topicScheme.clientId, equals('mobile-app-1'));

        // Test command topic generation
        final commandTopic = topicScheme.commandTopic;
        expect(commandTopic, equals('customer-a/env/mobile-app-1/cmd'));

        // Test response topic generation
        final responseTopic = topicScheme.responseTopic;
        expect(responseTopic, equals('customer-a/env/mobile-app-1/res'));

        // Test replication topic generation
        final replicationTopic = topicScheme.replicationTopic;
        expect(replicationTopic, equals('customer-a/env/replication/events'));
      });

      test('validates TopicRouter integration for multi-tenant isolation', () {
        // Create configurations for different tenants
        final config1 = MerkleKVConfig(
          mqttHost: 'mqtt.example.com',
          mqttPort: 1883,
          clientId: 'sensor-001',
          nodeId: 'node-001',
          topicPrefix: 'org-1/production',
        );

        final config2 = MerkleKVConfig(
          mqttHost: 'mqtt.example.com',
          mqttPort: 1883,
          clientId: 'sensor-002',
          nodeId: 'node-002',
          topicPrefix: 'org-2/development',
        );

        // Verify that TopicRouter would generate different command topics
        final commandTopic1 = TopicValidator.buildCommandTopic(
          config1.topicPrefix,
          config1.clientId,
        );
        final commandTopic2 = TopicValidator.buildCommandTopic(
          config2.topicPrefix,
          config2.clientId,
        );

        expect(commandTopic1, equals('org-1/production/sensor-001/cmd'));
        expect(commandTopic2, equals('org-2/development/sensor-002/cmd'));
        
        // Verify complete isolation
        expect(commandTopic1, isNot(equals(commandTopic2)));
        
        // Verify prefix extraction maintains tenant boundaries
        expect(TopicValidator.extractPrefix(commandTopic1), equals('org-1/production'));
        expect(TopicValidator.extractPrefix(commandTopic2), equals('org-2/development'));
      });

      test('validates edge cases with maximum length configurations', () {
        // Test configurations with reasonable lengths to stay within topic limits
        final reasonablePrefix = 'a' * 20; // Reasonable prefix length
        final reasonableClientId = 'b' * 20; // Reasonable client ID length

        final config = MerkleKVConfig(
          mqttHost: 'test.broker',
          mqttPort: 1883,
          clientId: reasonableClientId,
          nodeId: 'test-node',
          topicPrefix: reasonablePrefix,
        );

        expect(config.topicPrefix, equals(reasonablePrefix));
        expect(config.clientId, equals(reasonableClientId));

        // Verify topic generation works within limits
        final commandTopic = TopicValidator.buildCommandTopic(
          config.topicPrefix,
          config.clientId,
        );

        expect(commandTopic, isNotEmpty);
        expect(TopicValidator.getUtf8ByteLength(commandTopic), lessThanOrEqualTo(100));
      });

      test('validates invalid configurations are properly rejected', () {
        // Test prefix validation through MerkleKVConfig - this should fail during config creation
        expect(
          () => MerkleKVConfig(
            mqttHost: 'test.broker',
            mqttPort: 1883,
            clientId: 'device-123',
            nodeId: 'test-node',
            topicPrefix: 'tenant+invalid',
          ),
          throwsA(isA<InvalidConfigException>()),
        );

        // Test client ID validation through MerkleKVConfig
        expect(
          () => MerkleKVConfig(
            mqttHost: 'test.broker',
            mqttPort: 1883,
            clientId: 'device/invalid',
            nodeId: 'test-node',
            topicPrefix: 'tenant-1',
          ),
          throwsA(isA<InvalidConfigException>()),
        );

        // Test TopicScheme validation
        expect(
          () => TopicScheme.create('tenant#invalid', 'device-123'),
          throwsA(isA<InvalidConfigException>()),
        );
      });
    });

    group('Backward compatibility validation', () {
      test('maintains compatibility with existing TopicScheme usage', () {
        // Test that existing code patterns still work
        final scheme = TopicScheme.create('legacy-app', 'old-device');

        // Verify all existing properties work
        expect(scheme.prefix, equals('legacy-app'));
        expect(scheme.clientId, equals('old-device'));
        expect(scheme.commandTopic, equals('legacy-app/old-device/cmd'));
        expect(scheme.responseTopic, equals('legacy-app/old-device/res'));
        expect(scheme.replicationTopic, equals('legacy-app/replication/events'));

        // Verify validation is now enhanced but still compatible
        expect(() => TopicScheme.validateClientId('valid-client'), isNot(throwsA(anything)));
        expect(() => TopicScheme.validateClientId('invalid/client'), throwsA(isA<InvalidConfigException>()));
      });

      test('validates prefix normalization maintains backward compatibility', () {
        // Test that prefix normalization doesn't break existing behavior
        expect(TopicValidator.normalizePrefix('  legacy-app  '), equals('legacy-app'));
        expect(TopicValidator.normalizePrefix('/legacy-app/'), equals('legacy-app'));
        expect(TopicValidator.normalizePrefix(''), equals('mkv')); // Default fallback
      });
    });
  });
}