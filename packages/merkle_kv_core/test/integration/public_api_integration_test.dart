import 'package:test/test.dart';
import '../../lib/merkle_kv.dart';
import '../../lib/src/commands/response.dart';

/// Integration test demonstrating the public API usage.
/// 
/// Note: These tests demonstrate API usage patterns but will fail at 
/// connection time since no MQTT broker is available in test environment.
void main() {
  group('MerkleKV Public API Integration', () {
    test('builder pattern configuration', () {
      // Demonstrate the fluent builder API
      final config = MerkleKVConfig.builder()
          .mqttHost('mqtt.example.com')
          .mqttPort(8883)
          .useTls()
          .credentials('username', 'password')
          .clientId('mobile-app-123')
          .nodeId('device-456')
          .topicPrefix('myapp/prod')
          .keepAlive(120)
          .persistence(true, '/data/merkle_kv')
          .build();

      expect(config.mqttHost, equals('mqtt.example.com'));
      expect(config.mqttPort, equals(8883));
      expect(config.mqttUseTls, isTrue);
      expect(config.clientId, equals('mobile-app-123'));
      expect(config.topicPrefix, equals('myapp/prod'));
    });

    test('basic client initialization and configuration', () {
      final client = MerkleKV(
        MerkleKVConfig.builder()
            .mqttHost('mqtt.test.com')
            .clientId('test-client')
            .nodeId('test-node')
            .build(),
      );

      expect(client.version, equals('0.0.1'));
      expect(client.isConnected, isFalse);
      expect(client.currentConnectionState, equals(ConnectionState.disconnected));
    });

    test('API surface completeness', () async {
      final client = MerkleKV(
        MerkleKVConfig.builder()
            .mqttHost('mqtt.test.com')
            .clientId('test-client')
            .nodeId('test-node')
            .build(),
      );

      // Verify all core operations are available and properly typed
      expect(() => client.get('key'), throwsA(isA<DisconnectedException>()));
      expect(() => client.set('key', 'value'), throwsA(isA<DisconnectedException>()));
      expect(() => client.delete('key'), throwsA(isA<DisconnectedException>()));
      expect(() => client.increment('counter'), throwsA(isA<DisconnectedException>()));
      expect(() => client.decrement('counter'), throwsA(isA<DisconnectedException>()));
      expect(() => client.append('key', 'suffix'), throwsA(isA<DisconnectedException>()));
      expect(() => client.prepend('key', 'prefix'), throwsA(isA<DisconnectedException>()));
      
      // Verify bulk operations
      expect(() => client.multiGet(['key1', 'key2']), throwsA(isA<DisconnectedException>()));
      expect(() => client.multiSet({'key1': 'value1', 'key2': 'value2'}), throwsA(isA<DisconnectedException>()));

      await client.dispose();
    });

    test('exception hierarchy mapping', () {
      // Test that exceptions are properly mapped from error codes
      final validationError = MerkleKVException.fromResponse(
        Response.invalidRequest('test', 'Invalid key'),
      );
      expect(validationError, isA<ValidationException>());

      final timeoutError = MerkleKVException.fromResponse(
        Response.timeout('test'),
      );
      expect(timeoutError, isA<TimeoutException>());

      final notFoundError = MerkleKVException.fromResponse(
        Response.notFound('test'),
      );
      expect(notFoundError, isA<KeyNotFoundException>());

      final payloadError = MerkleKVException.fromResponse(
        Response.payloadTooLarge('test'),
      );
      expect(payloadError, isA<PayloadException>());
    });

    test('UTF-8 validation compliance', () async {
      final client = MerkleKV(
        MerkleKVConfig.builder()
            .mqttHost('mqtt.test.com')
            .clientId('test-client')
            .nodeId('test-node')
            .build(),
      );

      // Test UTF-8 byte size limits
      final maxKey = 'a' * 256; // Exactly 256 bytes
      final oversizeKey = 'a' * 257; // 257 bytes - too large

      // Should pass validation (but fail at connection)
      expect(
        () async => await client.get(maxKey),
        throwsA(isA<DisconnectedException>()),
      );

      // Should fail validation
      expect(
        () async => await client.get(oversizeKey),
        throwsA(isA<ValidationException>()),
      );

      // Test multi-byte UTF-8 characters
      final emojiKey = '🔥' * 64; // 64 * 4 = 256 bytes exactly
      final oversizeEmojiKey = '🔥' * 65; // 65 * 4 = 260 bytes - too large

      expect(
        () async => await client.get(emojiKey),
        throwsA(isA<DisconnectedException>()),
      );

      expect(
        () async => await client.get(oversizeEmojiKey),
        throwsA(isA<ValidationException>()),
      );

      await client.dispose();
    });

    test('idempotent operations with request IDs', () async {
      final client = MerkleKV(
        MerkleKVConfig.builder()
            .mqttHost('mqtt.test.com')
            .clientId('test-client')
            .nodeId('test-node')
            .build(),
      );

      // All operations support optional request IDs for idempotency
      const requestId = 'custom-request-123';

      expect(() => client.get('key', requestId), throwsA(isA<DisconnectedException>()));
      expect(() => client.set('key', 'value', requestId), throwsA(isA<DisconnectedException>()));
      expect(() => client.delete('key', requestId), throwsA(isA<DisconnectedException>()));
      expect(() => client.increment('counter', 5, requestId), throwsA(isA<DisconnectedException>()));
      expect(() => client.decrement('counter', 3, requestId), throwsA(isA<DisconnectedException>()));
      expect(() => client.append('key', 'suffix', requestId), throwsA(isA<DisconnectedException>()));
      expect(() => client.prepend('key', 'prefix', requestId), throwsA(isA<DisconnectedException>()));
      expect(() => client.multiGet(['key1', 'key2'], requestId), throwsA(isA<DisconnectedException>()));
      expect(() => client.multiSet({'key': 'value'}, requestId), throwsA(isA<DisconnectedException>()));

      await client.dispose();
    });

    test('connection state monitoring', () async {
      final client = MerkleKV(
        MerkleKVConfig.builder()
            .mqttHost('mqtt.test.com')
            .clientId('test-client')
            .nodeId('test-node')
            .build(),
      );

      // Connection state should be observable
      expect(client.connectionState, isA<Stream<ConnectionState>>());
      expect(client.currentConnectionState, equals(ConnectionState.disconnected));
      expect(client.isConnected, isFalse);

      // Test connection state changes (would normally happen during connect/disconnect)
      final stateChanges = <ConnectionState>[];
      final subscription = client.connectionState.listen(stateChanges.add);

      // Connection would change state during connect() but we can't test that here
      // since we don't have a real MQTT broker

      await subscription.cancel();
      await client.dispose();
    });

    test('comprehensive example usage pattern', () async {
      // This demonstrates how a developer would use the API
      final config = MerkleKV.builder()
          .mqttHost('mqtt.mycompany.com')
          .mqttPort(8883)
          .useTls()
          .credentials('mobile-user', 'secure-password')
          .clientId('mobile-app-${DateTime.now().millisecondsSinceEpoch}')
          .nodeId('device-uuid-123')
          .topicPrefix('myapp/production')
          .keepAlive(60)
          .persistence(true)
          .build();

      final client = MerkleKV(config);

      expect(client, isA<MerkleKV>());

      // In a real app, this would connect to the broker:
      // await client.connect();
      
      // Example operations (would work after connection):
      // await client.set('user:123:name', 'Alice');
      // final name = await client.get('user:123:name');
      // await client.increment('global:counter');
      // final users = await client.multiGet(['user:123:name', 'user:456:name']);
      // await client.multiSet({'user:789:name': 'Bob', 'user:789:email': 'bob@example.com'});
      
      await client.dispose();
    });
  });
}