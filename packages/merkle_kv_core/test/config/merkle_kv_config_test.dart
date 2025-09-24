import 'package:test/test.dart';
import 'package:merkle_kv_core/src/config/merkle_kv_config.dart';
import 'package:merkle_kv_core/src/config/mqtt_security_config.dart';
import 'package:merkle_kv_core/src/config/invalid_config_exception.dart';
import 'package:merkle_kv_core/src/config/resource_limits.dart';

void main() {
  group('MerkleKVConfig', () {
    group('defaults', () {
      test('applies exact Spec §11 default values', () {
        final config = MerkleKVConfig(
          mqttHost: 'localhost',
          clientId: 'test-client',
          nodeId: 'test-node',
        );

        expect(config.keepAliveSeconds, equals(60));
        expect(config.sessionExpirySeconds, equals(86400));
        expect(config.skewMaxFutureMs, equals(300000));
        expect(config.tombstoneRetentionHours, equals(24));
      });

      test('infers correct port based on TLS setting', () {
        final configNoTls = MerkleKVConfig(
          mqttHost: 'localhost',
          clientId: 'test-client',
          nodeId: 'test-node',
          mqttUseTls: false,
        );
        expect(configNoTls.mqttPort, equals(1883));

        final configWithTls = MerkleKVConfig(
          mqttHost: 'localhost',
          clientId: 'test-client',
          nodeId: 'test-node',
          mqttUseTls: true,
        );
        expect(configWithTls.mqttPort, equals(8883));
      });

      test('uses provided port when specified', () {
        final config = MerkleKVConfig(
          mqttHost: 'localhost',
          mqttPort: 9999,
          clientId: 'test-client',
          nodeId: 'test-node',
        );
        expect(config.mqttPort, equals(9999));
      });

      test('normalizes topic prefix correctly', () {
        final config1 = MerkleKVConfig(
          mqttHost: 'localhost',
          clientId: 'test-client',
          nodeId: 'test-node',
          topicPrefix: '/my-topic/',
        );
        expect(config1.topicPrefix, equals('my-topic'));

        final config2 = MerkleKVConfig(
          mqttHost: 'localhost',
          clientId: 'test-client',
          nodeId: 'test-node',
          topicPrefix: '   ',
        );
        expect(config2.topicPrefix, equals('mkv'));

        final config3 = MerkleKVConfig(
          mqttHost: 'localhost',
          clientId: 'test-client',
          nodeId: 'test-node',
          topicPrefix: '',
        );
        expect(config3.topicPrefix, equals('mkv'));
      });
    });

    group('validation', () {
      test('throws InvalidConfigException for empty mqttHost', () {
        expect(
          () => MerkleKVConfig(
            mqttHost: '',
            clientId: 'test-client',
            nodeId: 'test-node',
          ),
          throwsA(
            isA<InvalidConfigException>().having(
              (e) => e.parameter,
              'parameter',
              equals('mqttHost'),
            ),
          ),
        );

        expect(
          () => MerkleKVConfig(
            mqttHost: '   ',
            clientId: 'test-client',
            nodeId: 'test-node',
          ),
          throwsA(
            isA<InvalidConfigException>().having(
              (e) => e.parameter,
              'parameter',
              equals('mqttHost'),
            ),
          ),
        );
      });

      test('validates port boundaries', () {
        // Test invalid ports
        expect(
          () => MerkleKVConfig(
            mqttHost: 'localhost',
            mqttPort: 0,
            clientId: 'test-client',
            nodeId: 'test-node',
          ),
          throwsA(
            isA<InvalidConfigException>().having(
              (e) => e.parameter,
              'parameter',
              equals('mqttPort'),
            ),
          ),
        );

        expect(
          () => MerkleKVConfig(
            mqttHost: 'localhost',
            mqttPort: 65536,
            clientId: 'test-client',
            nodeId: 'test-node',
          ),
          throwsA(
            isA<InvalidConfigException>().having(
              (e) => e.parameter,
              'parameter',
              equals('mqttPort'),
            ),
          ),
        );

        // Test valid edge cases
        final config1 = MerkleKVConfig(
          mqttHost: 'localhost',
          mqttPort: 1,
          clientId: 'test-client',
          nodeId: 'test-node',
        );
        expect(config1.mqttPort, equals(1));

        final config2 = MerkleKVConfig(
          mqttHost: 'localhost',
          mqttPort: 65535,
          clientId: 'test-client',
          nodeId: 'test-node',
        );
        expect(config2.mqttPort, equals(65535));
      });

      test('validates clientId length', () {
        // Empty clientId
        expect(
          () => MerkleKVConfig(
            mqttHost: 'localhost',
            clientId: '',
            nodeId: 'test-node',
          ),
          throwsA(
            isA<InvalidConfigException>().having(
              (e) => e.parameter,
              'parameter',
              equals('clientId'),
            ),
          ),
        );

        // Too long clientId (129 characters)
        final longClientId = 'a' * 129;
        expect(
          () => MerkleKVConfig(
            mqttHost: 'localhost',
            clientId: longClientId,
            nodeId: 'test-node',
          ),
          throwsA(
            isA<InvalidConfigException>().having(
              (e) => e.parameter,
              'parameter',
              equals('clientId'),
            ),
          ),
        );

        // Valid edge case: exactly 128 characters
        final maxClientId = 'a' * 128;
        final config = MerkleKVConfig(
          mqttHost: 'localhost',
          clientId: maxClientId,
          nodeId: 'test-node',
        );
        expect(config.clientId, equals(maxClientId));
      });

      test('validates nodeId length', () {
        // Empty nodeId
        expect(
          () => MerkleKVConfig(
            mqttHost: 'localhost',
            clientId: 'test-client',
            nodeId: '',
          ),
          throwsA(
            isA<InvalidConfigException>().having(
              (e) => e.parameter,
              'parameter',
              equals('nodeId'),
            ),
          ),
        );

        // Too long nodeId (129 characters)
        final longNodeId = 'b' * 129;
        expect(
          () => MerkleKVConfig(
            mqttHost: 'localhost',
            clientId: 'test-client',
            nodeId: longNodeId,
          ),
          throwsA(
            isA<InvalidConfigException>().having(
              (e) => e.parameter,
              'parameter',
              equals('nodeId'),
            ),
          ),
        );

        // Valid edge case: exactly 128 characters
        final maxNodeId = 'b' * 128;
        final config = MerkleKVConfig(
          mqttHost: 'localhost',
          clientId: 'test-client',
          nodeId: maxNodeId,
        );
        expect(config.nodeId, equals(maxNodeId));
      });

      test('validates timeout parameters', () {
        // keepAliveSeconds must be positive
        expect(
          () => MerkleKVConfig(
            mqttHost: 'localhost',
            clientId: 'test-client',
            nodeId: 'test-node',
            keepAliveSeconds: 0,
          ),
          throwsA(
            isA<InvalidConfigException>().having(
              (e) => e.parameter,
              'parameter',
              equals('keepAliveSeconds'),
            ),
          ),
        );

        expect(
          () => MerkleKVConfig(
            mqttHost: 'localhost',
            clientId: 'test-client',
            nodeId: 'test-node',
            keepAliveSeconds: -1,
          ),
          throwsA(
            isA<InvalidConfigException>().having(
              (e) => e.parameter,
              'parameter',
              equals('keepAliveSeconds'),
            ),
          ),
        );

        // sessionExpirySeconds must be positive
        expect(
          () => MerkleKVConfig(
            mqttHost: 'localhost',
            clientId: 'test-client',
            nodeId: 'test-node',
            sessionExpirySeconds: 0,
          ),
          throwsA(
            isA<InvalidConfigException>().having(
              (e) => e.parameter,
              'parameter',
              equals('sessionExpirySeconds'),
            ),
          ),
        );

        // tombstoneRetentionHours must be positive
        expect(
          () => MerkleKVConfig(
            mqttHost: 'localhost',
            clientId: 'test-client',
            nodeId: 'test-node',
            tombstoneRetentionHours: 0,
          ),
          throwsA(
            isA<InvalidConfigException>().having(
              (e) => e.parameter,
              'parameter',
              equals('tombstoneRetentionHours'),
            ),
          ),
        );

        // skewMaxFutureMs can be zero but not negative
        expect(
          () => MerkleKVConfig(
            mqttHost: 'localhost',
            clientId: 'test-client',
            nodeId: 'test-node',
            skewMaxFutureMs: -1,
          ),
          throwsA(
            isA<InvalidConfigException>().having(
              (e) => e.parameter,
              'parameter',
              equals('skewMaxFutureMs'),
            ),
          ),
        );

        // Valid edge cases
        final config = MerkleKVConfig(
          mqttHost: 'localhost',
          clientId: 'test-client',
          nodeId: 'test-node',
          keepAliveSeconds: 1,
          sessionExpirySeconds: 1,
          tombstoneRetentionHours: 1,
          skewMaxFutureMs: 0,
        );
        expect(config.keepAliveSeconds, equals(1));
        expect(config.sessionExpirySeconds, equals(1));
        expect(config.tombstoneRetentionHours, equals(1));
        expect(config.skewMaxFutureMs, equals(0));
      });

      test('validates persistence requirements', () {
        // persistenceEnabled=true requires storagePath
        expect(
          () => MerkleKVConfig(
            mqttHost: 'localhost',
            clientId: 'test-client',
            nodeId: 'test-node',
            persistenceEnabled: true,
          ),
          throwsA(
            isA<InvalidConfigException>().having(
              (e) => e.parameter,
              'parameter',
              equals('storagePath'),
            ),
          ),
        );

        expect(
          () => MerkleKVConfig(
            mqttHost: 'localhost',
            clientId: 'test-client',
            nodeId: 'test-node',
            persistenceEnabled: true,
            storagePath: '',
          ),
          throwsA(
            isA<InvalidConfigException>().having(
              (e) => e.parameter,
              'parameter',
              equals('storagePath'),
            ),
          ),
        );

        expect(
          () => MerkleKVConfig(
            mqttHost: 'localhost',
            clientId: 'test-client',
            nodeId: 'test-node',
            persistenceEnabled: true,
            storagePath: '   ',
          ),
          throwsA(
            isA<InvalidConfigException>().having(
              (e) => e.parameter,
              'parameter',
              equals('storagePath'),
            ),
          ),
        );

        // Valid persistence configuration
        final config = MerkleKVConfig(
          mqttHost: 'localhost',
          clientId: 'test-client',
          nodeId: 'test-node',
          persistenceEnabled: true,
          storagePath: '/tmp/test',
        );
        expect(config.persistenceEnabled, isTrue);
        expect(config.storagePath, equals('/tmp/test'));
      });

      test('rejects topic prefix with spaces', () {
        expect(
          () => MerkleKVConfig(
            mqttHost: 'localhost',
            clientId: 'test-client',
            nodeId: 'test-node',
            topicPrefix: 'my topic',
          ),
          throwsA(
            isA<InvalidConfigException>().having(
              (e) => e.parameter,
              'parameter',
              equals('topicPrefix'),
            ),
          ),
        );
      });
    });

    group('security warnings', () {
      late List<String> warnings;

      setUp(() {
        warnings = [];
        MerkleKVConfig.setSecurityWarningHandler((msg) => warnings.add(msg));
      });

      tearDown(() {
        MerkleKVConfig.setSecurityWarningHandler(null);
      });

      test('triggers warning when credentials provided without TLS', () {
        MerkleKVConfig(
          mqttHost: 'localhost',
          clientId: 'test-client',
          nodeId: 'test-node',
          mqttUseTls: false,
          username: 'user',
          password: 'pass',
        );

        expect(warnings, hasLength(1));
        expect(warnings.first, contains('plain text'));
      });

      test('triggers warning when only username provided without TLS', () {
        MerkleKVConfig(
          mqttHost: 'localhost',
          clientId: 'test-client',
          nodeId: 'test-node',
          mqttUseTls: false,
          username: 'user',
        );

        expect(warnings, hasLength(1));
      });

      test('triggers warning when only password provided without TLS', () {
        MerkleKVConfig(
          mqttHost: 'localhost',
          clientId: 'test-client',
          nodeId: 'test-node',
          mqttUseTls: false,
          password: 'pass',
        );

        expect(warnings, hasLength(1));
      });

      test('no warning when credentials provided with TLS', () {
        MerkleKVConfig(
          mqttHost: 'localhost',
          clientId: 'test-client',
          nodeId: 'test-node',
          mqttUseTls: true,
          username: 'user',
          password: 'pass',
        );

        expect(warnings, isEmpty);
      });

      test('no warning when no credentials provided', () {
        MerkleKVConfig(
          mqttHost: 'localhost',
          clientId: 'test-client',
          nodeId: 'test-node',
          mqttUseTls: false,
        );

        expect(warnings, isEmpty);
      });
    });

    group('JSON serialization', () {
      test('toJson excludes sensitive data', () {
        final config = MerkleKVConfig(
          mqttHost: 'example.com',
          mqttPort: 8883,
          username: 'secret-user',
          password: 'secret-pass',
          mqttUseTls: true,
          clientId: 'test-client',
          nodeId: 'test-node',
          topicPrefix: 'test',
          persistenceEnabled: true,
          storagePath: '/tmp/test',
        );

        final json = config.toJson();

        expect(json, isNot(contains('username')));
        expect(json, isNot(contains('password')));
        expect(json, isNot(contains('secret-user')));
        expect(json, isNot(contains('secret-pass')));

        expect(json['mqttHost'], equals('example.com'));
        expect(json['mqttPort'], equals(8883));
        expect(json['mqttUseTls'], isTrue);
        expect(json['clientId'], equals('test-client'));
        expect(json['nodeId'], equals('test-node'));
        expect(json['topicPrefix'], equals('test'));
        expect(json['persistenceEnabled'], isTrue);
        expect(json['storagePath'], equals('/tmp/test'));
      });

      test('fromJson restores non-sensitive values correctly', () {
        final originalConfig = MerkleKVConfig(
          mqttHost: 'example.com',
          mqttPort: 9999,
          mqttUseTls: true,
          clientId: 'test-client',
          nodeId: 'test-node',
          topicPrefix: 'custom',
          keepAliveSeconds: 120,
          sessionExpirySeconds: 7200,
          skewMaxFutureMs: 600000,
          tombstoneRetentionHours: 48,
          persistenceEnabled: true,
          storagePath: '/custom/path',
        );

        final json = originalConfig.toJson();
        final restoredConfig = MerkleKVConfig.fromJson(
          json,
          username: 'new-user',
          password: 'new-pass',
        );

        expect(restoredConfig.mqttHost, equals('example.com'));
        expect(restoredConfig.mqttPort, equals(9999));
        expect(restoredConfig.mqttUseTls, isTrue);
        expect(restoredConfig.clientId, equals('test-client'));
        expect(restoredConfig.nodeId, equals('test-node'));
        expect(restoredConfig.topicPrefix, equals('custom'));
        expect(restoredConfig.keepAliveSeconds, equals(120));
        expect(restoredConfig.sessionExpirySeconds, equals(7200));
        expect(restoredConfig.skewMaxFutureMs, equals(600000));
        expect(restoredConfig.tombstoneRetentionHours, equals(48));
        expect(restoredConfig.persistenceEnabled, isTrue);
        expect(restoredConfig.storagePath, equals('/custom/path'));

        // Credentials should be the new ones
        expect(restoredConfig.username, equals('new-user'));
        expect(restoredConfig.password, equals('new-pass'));
      });

      test('fromJson applies defaults for missing optional fields', () {
        final minimalJson = {
          'mqttHost': 'localhost',
          'mqttPort': 1883,
          'mqttUseTls': false,
          'clientId': 'test-client',
          'nodeId': 'test-node',
        };

        final config = MerkleKVConfig.fromJson(minimalJson);

        expect(config.keepAliveSeconds, equals(60));
        expect(config.sessionExpirySeconds, equals(86400));
        expect(config.skewMaxFutureMs, equals(300000));
        expect(config.tombstoneRetentionHours, equals(24));
        expect(config.persistenceEnabled, isFalse);
        expect(config.topicPrefix, equals('mkv'));
      });

      test('resourceLimits round-trips via JSON and copyWith', () {
        final cfg = MerkleKVConfig(
          mqttHost: 'localhost',
          clientId: 'c1',
          nodeId: 'n1',
          // Provide some limits; these are advisory and not enforced.
          resourceLimits: ResourceLimits(
            memoryLimitBytes: 1024,
            storageLimitBytes: 2048,
            networkUploadKbps: 512,
            networkDownloadKbps: 1024,
            cpuLimitPercent: 50,
            ioReadIops: 100,
            ioWriteIops: 200,
            maxConcurrentOperations: 8,
            mqttMaxMessagesPerSecond: 20,
            outboxMaxBytes: 4096,
            inMemoryCacheMaxBytes: 8192,
          ),
        );

        final json = cfg.toJson();
        expect(json['resourceLimits'], isA<Map<String, dynamic>?>());

        final restored = MerkleKVConfig.fromJson(json);
        expect(restored.resourceLimits?.memoryLimitBytes, 1024);
        expect(restored.resourceLimits?.cpuLimitPercent, 50);

        final updated = restored.copyWith(
          resourceLimits: restored.resourceLimits?.copyWith(
            cpuLimitPercent: 60,
          ),
        );
        expect(updated.resourceLimits?.cpuLimitPercent, 60);
      });

      test('resourceLimits validation rejects invalid values', () {
        expect(
          () => MerkleKVConfig(
            mqttHost: 'localhost',
            clientId: 'c1',
            nodeId: 'n1',
            resourceLimits: const ResourceLimits(cpuLimitPercent: 0),
          ),
          throwsA(isA<InvalidConfigException>()
              .having((e) => e.parameter, 'parameter', 'resourceLimits')),
        );
        expect(
          () => MerkleKVConfig(
            mqttHost: 'localhost',
            clientId: 'c1',
            nodeId: 'n1',
            resourceLimits: const ResourceLimits(memoryLimitBytes: -1),
          ),
          throwsA(isA<InvalidConfigException>()),
        );
      });
    });

    group('copyWith', () {
      test('creates copy with updated values', () {
        final original = MerkleKVConfig(
          mqttHost: 'localhost',
          clientId: 'original-client',
          nodeId: 'original-node',
        );

        final updated = original.copyWith(
          mqttHost: 'example.com',
          mqttUseTls: true,
          username: 'user',
        );

        expect(updated.mqttHost, equals('example.com'));
        expect(updated.mqttUseTls, isTrue);
        expect(updated.username, equals('user'));
        expect(updated.mqttPort, equals(8883)); // Should be inferred for TLS

        // Unchanged values should remain
        expect(updated.clientId, equals('original-client'));
        expect(updated.nodeId, equals('original-node'));
        expect(updated.keepAliveSeconds, equals(60));
      });

      test('preserves original when no changes specified', () {
        final original = MerkleKVConfig(
          mqttHost: 'localhost',
          clientId: 'test-client',
          nodeId: 'test-node',
          username: 'user',
          password: 'pass',
        );

        final copy = original.copyWith();

        expect(copy.mqttHost, equals(original.mqttHost));
        expect(copy.clientId, equals(original.clientId));
        expect(copy.nodeId, equals(original.nodeId));
        expect(copy.username, equals(original.username));
        expect(copy.password, equals(original.password));
      });
    });

    group('toString', () {
      test('masks sensitive data in string representation', () {
        final config = MerkleKVConfig(
          mqttHost: 'example.com',
          clientId: 'test-client',
          nodeId: 'test-node',
          username: 'secret-user',
          password: 'secret-pass',
        );

        final str = config.toString();

        expect(str, contains('username: ***'));
        expect(str, contains('password: ***'));
        expect(str, isNot(contains('secret-user')));
        expect(str, isNot(contains('secret-pass')));
        expect(str, contains('mqttHost: example.com'));
      });

      test('shows null for missing credentials', () {
        final config = MerkleKVConfig(
          mqttHost: 'example.com',
          clientId: 'test-client',
          nodeId: 'test-node',
        );

        final str = config.toString();

        expect(str, contains('username: null'));
        expect(str, contains('password: null'));
      });
    });

    group('defaultConfig factory', () {
      test('creates configuration with minimal parameters', () {
        final config = MerkleKVConfig.defaultConfig(
          host: 'example.com',
          clientId: 'test-client',
          nodeId: 'test-node',
        );

        expect(config.mqttHost, equals('example.com'));
        expect(config.clientId, equals('test-client'));
        expect(config.nodeId, equals('test-node'));
        expect(config.mqttUseTls, isFalse);
        expect(config.mqttPort, equals(1883));
      });

      test('respects TLS setting', () {
        final config = MerkleKVConfig.defaultConfig(
          host: 'example.com',
          clientId: 'test-client',
          nodeId: 'test-node',
          tls: true,
        );

        expect(config.mqttUseTls, isTrue);
        expect(config.mqttPort, equals(8883));
      });

      test('mqttSecurity serializes when present', () {
        final config = MerkleKVConfig(
          mqttHost: 'example.com',
          clientId: 'test-client',
          nodeId: 'test-node',
          mqttUseTls: true,
          mqttSecurity: const MqttSecurityConfig(enableTLS: true),
        );
        final json = config.toJson();
        expect(json['mqttSecurity'], isNotNull);
        final decoded = MerkleKVConfig.fromJson(
          {
            ...json,
            'username': null,
            'password': null,
          },
        );
        expect(decoded.mqttSecurity?.enableTLS, isTrue);
      });
    });
  });

  group('InvalidConfigException', () {
    test('formats message correctly with parameter', () {
      const exception = InvalidConfigException('Value is invalid', 'testParam');
      expect(
        exception.toString(),
        equals(
          'InvalidConfigException: Value is invalid (parameter: testParam)',
        ),
      );
    });

    test('formats message correctly without parameter', () {
      const exception = InvalidConfigException('General error');
      expect(
        exception.toString(),
        equals('InvalidConfigException: General error'),
      );
    });

    test('implements FormatException interface', () {
      const exception = InvalidConfigException('Test message');
      expect(exception, isA<FormatException>());
      expect(exception.message, equals('Test message'));
      expect(exception.offset, isNull);
      expect(exception.source, isNull);
    });
  });
}
