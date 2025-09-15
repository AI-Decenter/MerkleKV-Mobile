import 'package:test/test.dart';
import '../../../lib/src/config/merkle_kv_config.dart';
import '../../../lib/src/config/invalid_config_exception.dart';

void main() {
  group('MerkleKVConfigBuilder', () {
    test('creates builder from MerkleKVConfig.builder()', () {
      final builder = MerkleKVConfig.builder();
      expect(builder, isA<MerkleKVConfigBuilder>());
    });

    test('builds basic configuration with required fields', () {
      final config = MerkleKVConfig.builder()
          .mqttHost('mqtt.example.com')
          .clientId('client-123')
          .nodeId('node-456')
          .build();

      expect(config.mqttHost, equals('mqtt.example.com'));
      expect(config.clientId, equals('client-123'));
      expect(config.nodeId, equals('node-456'));
      expect(config.mqttUseTls, isFalse);
      expect(config.topicPrefix, equals(''));
      expect(config.keepAliveSeconds, equals(60));
    });

    test('builds configuration with all options', () {
      final config = MerkleKVConfig.builder()
          .mqttHost('secure.mqtt.example.com')
          .mqttPort(8883)
          .credentials('user123', 'pass456')
          .useTls()
          .clientId('secure-client')
          .nodeId('secure-node')
          .topicPrefix('myapp/prod')
          .keepAlive(120)
          .sessionExpiry(3600)
          .maxFutureSkew(600000)
          .tombstoneRetention(48)
          .connectionTimeout(30)
          .persistence(true, '/data/storage')
          .build();

      expect(config.mqttHost, equals('secure.mqtt.example.com'));
      expect(config.mqttPort, equals(8883));
      expect(config.username, equals('user123'));
      expect(config.password, equals('pass456'));
      expect(config.mqttUseTls, isTrue);
      expect(config.clientId, equals('secure-client'));
      expect(config.nodeId, equals('secure-node'));
      expect(config.topicPrefix, equals('myapp/prod'));
      expect(config.keepAliveSeconds, equals(120));
      expect(config.sessionExpirySeconds, equals(3600));
      expect(config.skewMaxFutureMs, equals(600000));
      expect(config.tombstoneRetentionHours, equals(48));
      expect(config.connectionTimeoutSeconds, equals(30));
      expect(config.persistenceEnabled, isTrue);
      expect(config.storagePath, equals('/data/storage'));
    });

    test('fluent API chain', () {
      final config = MerkleKVConfig.builder()
          .mqttHost('mqtt.test.com')
          .useTls(true)
          .credentials('testuser', 'testpass')
          .clientId('test-client')
          .nodeId('test-node')
          .topicPrefix('test/env')
          .build();

      expect(config.mqttHost, equals('mqtt.test.com'));
      expect(config.mqttUseTls, isTrue);
      expect(config.username, equals('testuser'));
      expect(config.password, equals('testpass'));
      expect(config.topicPrefix, equals('test/env'));
    });

    test('individual credential setters', () {
      final config = MerkleKVConfig.builder()
          .mqttHost('mqtt.example.com')
          .username('individual-user')
          .password('individual-pass')
          .clientId('individual-client')
          .nodeId('individual-node')
          .build();

      expect(config.username, equals('individual-user'));
      expect(config.password, equals('individual-pass'));
    });

    test('useTls with default parameter', () {
      final config1 = MerkleKVConfig.builder()
          .mqttHost('mqtt.example.com')
          .clientId('client1')
          .nodeId('node1')
          .useTls()
          .build();

      final config2 = MerkleKVConfig.builder()
          .mqttHost('mqtt.example.com')
          .clientId('client2')
          .nodeId('node2')
          .useTls(false)
          .build();

      expect(config1.mqttUseTls, isTrue);
      expect(config2.mqttUseTls, isFalse);
    });

    test('persistence with optional storage path', () {
      final config1 = MerkleKVConfig.builder()
          .mqttHost('mqtt.example.com')
          .clientId('client1')
          .nodeId('node1')
          .persistence(true, '/custom/path')
          .build();

      final config2 = MerkleKVConfig.builder()
          .mqttHost('mqtt.example.com')
          .clientId('client2')
          .nodeId('node2')
          .persistence(true)
          .storagePath('/separate/path')
          .build();

      expect(config1.persistenceEnabled, isTrue);
      expect(config1.storagePath, equals('/custom/path'));
      expect(config2.persistenceEnabled, isTrue);
      expect(config2.storagePath, equals('/separate/path'));
    });

    group('validation errors', () {
      test('throws InvalidConfigException when mqttHost is missing', () {
        expect(
          () => MerkleKVConfig.builder()
              .clientId('client-123')
              .nodeId('node-456')
              .build(),
          throwsA(isA<InvalidConfigException>()
              .having((e) => e.parameter, 'parameter', 'mqttHost')),
        );
      });

      test('throws InvalidConfigException when clientId is missing', () {
        expect(
          () => MerkleKVConfig.builder()
              .mqttHost('mqtt.example.com')
              .nodeId('node-456')
              .build(),
          throwsA(isA<InvalidConfigException>()
              .having((e) => e.parameter, 'parameter', 'clientId')),
        );
      });

      test('throws InvalidConfigException when nodeId is missing', () {
        expect(
          () => MerkleKVConfig.builder()
              .mqttHost('mqtt.example.com')
              .clientId('client-123')
              .build(),
          throwsA(isA<InvalidConfigException>()
              .having((e) => e.parameter, 'parameter', 'nodeId')),
        );
      });
    });

    test('builder can be reused after build', () {
      final builder = MerkleKVConfig.builder()
          .mqttHost('mqtt.example.com')
          .clientId('client-base')
          .nodeId('node-base');

      final config1 = builder.topicPrefix('env1').build();
      final config2 = builder.topicPrefix('env2').build();

      expect(config1.topicPrefix, equals('env1'));
      expect(config2.topicPrefix, equals('env2'));
      expect(config1.mqttHost, equals(config2.mqttHost));
    });

    test('defaults are applied correctly', () {
      final config = MerkleKVConfig.builder()
          .mqttHost('mqtt.example.com')
          .clientId('client-123')
          .nodeId('node-456')
          .build();

      expect(config.mqttUseTls, isFalse);
      expect(config.topicPrefix, equals(''));
      expect(config.keepAliveSeconds, equals(60));
      expect(config.sessionExpirySeconds, equals(86400));
      expect(config.skewMaxFutureMs, equals(300000));
      expect(config.tombstoneRetentionHours, equals(24));
      expect(config.connectionTimeoutSeconds, equals(20));
      expect(config.persistenceEnabled, isFalse);
      expect(config.storagePath, isNull);
    });
  });
}