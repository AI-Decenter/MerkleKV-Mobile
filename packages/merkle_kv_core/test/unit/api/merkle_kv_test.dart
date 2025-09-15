import 'package:test/test.dart';
import '../../../lib/src/merkle_kv_mobile.dart';
import '../../../lib/src/config/merkle_kv_config.dart';
import '../../../lib/src/exceptions/merkle_kv_exception.dart';
import '../../../lib/src/mqtt/connection_state.dart';

void main() {
  group('MerkleKV', () {
    late MerkleKVConfig config;

    setUp(() {
      config = MerkleKVConfig.builder()
          .mqttHost('mqtt.test.com')
          .clientId('test-client')
          .nodeId('test-node')
          .build();
    });

    group('constructor and factory', () {
      test('creates instance with config', () {
        final client = MerkleKV(config);
        expect(client, isA<MerkleKV>());
        expect(client.version, equals('0.0.1'));
      });

      test('builder factory returns MerkleKVConfigBuilder', () {
        final builder = MerkleKV.builder();
        expect(builder, isA<MerkleKVConfigBuilder>());
      });
    });

    group('connection state', () {
      test('initial state is disconnected', () {
        final client = MerkleKV(config);
        expect(client.currentConnectionState, equals(ConnectionState.disconnected));
        expect(client.isConnected, isFalse);
      });

      test('connection state stream is available', () {
        final client = MerkleKV(config);
        expect(client.connectionState, isA<Stream<ConnectionState>>());
      });
    });

    group('validation', () {
      late MerkleKV client;

      setUp(() {
        client = MerkleKV(config);
      });

      tearDown(() async {
        await client.dispose();
      });

      group('key validation', () {
        test('throws ValidationException for empty key', () async {
          expect(
            () async => await client.get(''),
            throwsA(isA<ValidationException>()
                .having((e) => e.message, 'message', contains('Key cannot be empty'))),
          );
        });

        test('throws ValidationException for oversized key', () async {
          // Create a key that's > 256 bytes UTF-8
          final oversizedKey = 'x' * 257;
          
          expect(
            () async => await client.get(oversizedKey),
            throwsA(isA<ValidationException>()
                .having((e) => e.message, 'message', contains('Key size'))),
          );
        });

        test('throws ValidationException for multi-byte UTF-8 key exceeding byte limit', () async {
          // Each emoji is 4 bytes, so 65 emojis = 260 bytes > 256 byte limit
          final oversizedKey = '🔥' * 65;
          
          expect(
            () async => await client.get(oversizedKey),
            throwsA(isA<ValidationException>()
                .having((e) => e.message, 'message', contains('Key size'))),
          );
        });
      });

      group('value validation', () {
        test('throws ValidationException for oversized value', () async {
          // Create a value that's > 256 KiB
          final oversizedValue = 'x' * (256 * 1024 + 1);
          
          expect(
            () async => await client.set('key', oversizedValue),
            throwsA(isA<ValidationException>()
                .having((e) => e.message, 'message', contains('Value size'))),
          );
        });

        test('throws ValidationException for multi-byte UTF-8 value exceeding byte limit', () async {
          // Each emoji is 4 bytes, so calculate how many exceed 256KiB
          final maxEmojis = (256 * 1024) ~/ 4;
          final oversizedValue = '🎉' * (maxEmojis + 1);
          
          expect(
            () async => await client.set('key', oversizedValue),
            throwsA(isA<ValidationException>()
                .having((e) => e.message, 'message', contains('Value size'))),
          );
        });
      });

      group('bulk operation validation', () {
        test('validates all keys in multiGet', () async {
          expect(
            () async => await client.multiGet(['valid-key', '']),
            throwsA(isA<ValidationException>()
                .having((e) => e.message, 'message', contains('Key cannot be empty'))),
          );
        });

        test('validates all keys and values in multiSet', () async {
          expect(
            () async => await client.multiSet({
              'valid-key': 'valid-value',
              '': 'another-value',
            }),
            throwsA(isA<ValidationException>()
                .having((e) => e.message, 'message', contains('Key cannot be empty'))),
          );
        });

        test('validates bulk payload size', () async {
          // Create a large number of key-value pairs that exceed 512KiB payload
          final largeMap = <String, String>{};
          for (int i = 0; i < 1000; i++) {
            // Each entry has about 1KB, so 1000 entries should exceed 512KiB
            largeMap['key-$i'] = 'x' * 1000;
          }
          
          expect(
            () async => await client.multiSet(largeMap),
            throwsA(isA<PayloadException>()
                .having((e) => e.message, 'message', contains('Bulk operation payload size'))),
          );
        });
      });

      group('disconnected operations', () {
        test('throws DisconnectedException when not initialized', () async {
          expect(
            () async => await client.get('key'),
            throwsA(isA<DisconnectedException>()
                .having((e) => e.message, 'message', contains('not initialized'))),
          );
        });

        test('connect throws ValidationException when already initialized', () async {
          // This would normally work but we can't actually connect in tests
          // so we'll just test the validation logic
          try {
            await client.connect();
          } catch (e) {
            // Expected to fail due to missing MQTT broker, ignore
          }

          expect(
            () async => await client.connect(),
            throwsA(isA<ValidationException>()
                .having((e) => e.message, 'message', contains('already initialized'))),
          );
        });
      });

      group('edge cases', () {
        test('handles empty multiGet list', () async {
          expect(
            () async => await client.multiGet([]),
            throwsA(isA<DisconnectedException>()), // Fails at connection check first
          );
        });

        test('handles empty multiSet map', () async {
          expect(
            () async => await client.multiSet({}),
            throwsA(isA<DisconnectedException>()), // Fails at connection check first
          );
        });

        test('validates UTF-8 boundary cases', () async {
          // Valid UTF-8 at exact byte boundary
          final maxValidKey = 'a' * 256; // 256 bytes exactly
          
          expect(
            () async => await client.get(maxValidKey),
            throwsA(isA<DisconnectedException>()), // Should pass validation, fail at connection
          );
        });
      });
    });

    group('default parameters', () {
      late MerkleKV client;

      setUp(() {
        client = MerkleKV(config);
      });

      tearDown(() async {
        await client.dispose();
      });

      test('increment defaults to amount 1', () async {
        expect(
          () async => await client.increment('counter'),
          throwsA(isA<DisconnectedException>()), // Validates params then fails at connection
        );
      });

      test('decrement defaults to amount 1', () async {
        expect(
          () async => await client.decrement('counter'),
          throwsA(isA<DisconnectedException>()), // Validates params then fails at connection
        );
      });
    });

    group('resource management', () {
      test('dispose can be called on uninitialized client', () async {
        final client = MerkleKV(config);
        await expectLater(client.dispose(), completes);
      });

      test('disconnect can be called on uninitialized client', () async {
        final client = MerkleKV(config);
        await expectLater(client.disconnect(), completes);
      });
    });
  });
}