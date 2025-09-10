import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:cbor/cbor.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';

void main() {
  group('ReplicationEvent', () {
    test('creates value event correctly', () {
      final event = ReplicationEvent.setValue(
        key: 'test:key',
        value: 'test value',
        timestamp_ms: 1234567890,
        node_id: 'node-1',
        seq: 42,
      );

      expect(event.key, equals('test:key'));
      expect(event.value, equals('test value'));
      expect(event.timestamp_ms, equals(1234567890));
      expect(event.node_id, equals('node-1'));
      expect(event.seq, equals(42));
      expect(event.tombstone, isFalse);
    });

    test('creates tombstone event correctly', () {
      final event = ReplicationEvent.setTombstone(
        key: 'test:key',
        timestamp_ms: 1234567890,
        node_id: 'node-1',
        seq: 43,
      );

      expect(event.key, equals('test:key'));
      expect(event.value, isNull);
      expect(event.timestamp_ms, equals(1234567890));
      expect(event.node_id, equals('node-1'));
      expect(event.seq, equals(43));
      expect(event.tombstone, isTrue);
    });

    test('equality works correctly', () {
      final event1 = ReplicationEvent.setValue(
        key: 'key1',
        value: 'value1',
        timestamp_ms: 123,
        node_id: 'node1',
        seq: 1,
      );
      final event2 = ReplicationEvent.setValue(
        key: 'key1',
        value: 'value1',
        timestamp_ms: 123,
        node_id: 'node1',
        seq: 1,
      );
      final event3 = ReplicationEvent.setValue(
        key: 'key2',
        value: 'value1',
        timestamp_ms: 123,
        node_id: 'node1',
        seq: 1,
      );

      expect(event1, equals(event2));
      expect(event1, isNot(equals(event3)));
    });
  });

  group('ReplicationCbor.encode', () {
    test('encodes value event deterministically', () {
      final event = ReplicationEvent.setValue(
        key: 'user:123',
        value: 'john_doe',
        timestamp_ms: 1637142400000,
        node_id: 'device-xyz',
        seq: 42,
      );

      final encoded1 = ReplicationCbor.encode(event);
      final encoded2 = ReplicationCbor.encode(event);

      expect(encoded1, equals(encoded2));
      expect(encoded1, isA<Uint8List>());
    });

    test('encodes tombstone event deterministically', () {
      final event = ReplicationEvent.setTombstone(
        key: 'user:456',
        timestamp_ms: 1637142400000,
        node_id: 'device-abc',
        seq: 43,
      );

      final encoded1 = ReplicationCbor.encode(event);
      final encoded2 = ReplicationCbor.encode(event);

      expect(encoded1, equals(encoded2));
      expect(encoded1, isA<Uint8List>());
    });

    test('produces identical bytes for identical events', () {
      final event1 = ReplicationEvent.setValue(
        key: 'test:key',
        value: 'test value',
        timestamp_ms: 1234567890,
        node_id: 'node-1',
        seq: 1,
      );
      final event2 = ReplicationEvent.setValue(
        key: 'test:key',
        value: 'test value',
        timestamp_ms: 1234567890,
        node_id: 'node-1',
        seq: 1,
      );

      final encoded1 = ReplicationCbor.encode(event1);
      final encoded2 = ReplicationCbor.encode(event2);

      // Compare as hex strings for clarity
      final hex1 =
          encoded1.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final hex2 =
          encoded2.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      expect(hex1, equals(hex2));
    });

    test('throws for payload exceeding size limit', () {
      // Create a value that will exceed 300 KiB when encoded
      final largeValue =
          'x' * (300 * 1024); // Approximately 300 KiB of 'x' characters
      final event = ReplicationEvent.setValue(
        key: 'large:key',
        value: largeValue,
        timestamp_ms: 1234567890,
        node_id: 'node-1',
        seq: 1,
      );

      expect(
        () => ReplicationCbor.encode(event),
        throwsA(isA<ReplicationSerializationError>().having((e) => e.code,
            'code', ReplicationSerializationErrorCode.payloadTooLarge)),
      );
    });
  });

  group('ReplicationCbor.decode', () {
    test('round-trip encode/decode preserves value event', () {
      final original = ReplicationEvent.setValue(
        key: 'user:789',
        value: 'jane_doe',
        timestamp_ms: 1637142500000,
        node_id: 'device-123',
        seq: 100,
      );

      final encoded = ReplicationCbor.encode(original);
      final decoded = ReplicationCbor.decode(encoded);

      expect(decoded, equals(original));
    });

    test('round-trip encode/decode preserves tombstone event', () {
      final original = ReplicationEvent.setTombstone(
        key: 'user:999',
        timestamp_ms: 1637142600000,
        node_id: 'device-456',
        seq: 200,
      );

      final encoded = ReplicationCbor.encode(original);
      final decoded = ReplicationCbor.decode(encoded);

      expect(decoded, equals(original));
      expect(decoded.value, isNull);
      expect(decoded.tombstone, isTrue);
    });

    test('throws for payload exceeding size limit', () {
      final oversizedPayload = Uint8List(300 * 1024 + 1); // 300 KiB + 1 byte

      expect(
        () => ReplicationCbor.decode(oversizedPayload),
        throwsA(isA<ReplicationSerializationError>().having((e) => e.code,
            'code', ReplicationSerializationErrorCode.payloadTooLarge)),
      );
    });

    test('throws for malformed CBOR', () {
      final malformedData =
          Uint8List.fromList([0xFF, 0xFF, 0xFF]); // Invalid CBOR

      expect(
        () => ReplicationCbor.decode(malformedData),
        throwsA(isA<ReplicationSerializationError>().having((e) => e.code,
            'code', ReplicationSerializationErrorCode.malformedCbor)),
      );
    });

    test('throws for missing required fields', () {
      // Manually create CBOR with missing field
      final incompleteMap = <String, dynamic>{
        'key': 'test',
        'node_id': 'node1',
        // Missing: seq, timestamp_ms, tombstone
      };
      final incompleteCbor = cbor.encode(CborMap(incompleteMap));

      expect(
        () => ReplicationCbor.decode(incompleteCbor),
        throwsA(isA<ReplicationSerializationError>()
            .having((e) => e.code, 'code',
                ReplicationSerializationErrorCode.schemaViolation)
            .having((e) => e.message, 'message',
                contains('Missing required field'))),
      );
    });

    test('throws for wrong field types', () {
      final invalidMap = <String, dynamic>{
        'key': 123, // Should be string
        'node_id': 'node1',
        'seq': 1,
        'timestamp_ms': 123,
        'tombstone': false,
        'value': 'test',
      };
      final invalidCbor = cbor.encode(CborMap(invalidMap));

      expect(
        () => ReplicationCbor.decode(invalidCbor),
        throwsA(isA<ReplicationSerializationError>()
            .having((e) => e.code, 'code',
                ReplicationSerializationErrorCode.schemaViolation)
            .having((e) => e.message, 'message', contains('must be a string'))),
      );
    });

    test('throws for tombstone with value field', () {
      final invalidMap = <String, dynamic>{
        'key': 'test',
        'node_id': 'node1',
        'seq': 1,
        'timestamp_ms': 123,
        'tombstone': true,
        'value': 'should not be here', // Invalid for tombstone
      };
      final invalidCbor = cbor.encode(CborMap(invalidMap));

      expect(
        () => ReplicationCbor.decode(invalidCbor),
        throwsA(isA<ReplicationSerializationError>()
            .having((e) => e.code, 'code',
                ReplicationSerializationErrorCode.schemaViolation)
            .having((e) => e.message, 'message',
                contains('Tombstone events must not contain a "value" field'))),
      );
    });

    test('throws for non-tombstone without value field', () {
      final invalidMap = <String, dynamic>{
        'key': 'test',
        'node_id': 'node1',
        'seq': 1,
        'timestamp_ms': 123,
        'tombstone': false,
        // Missing value field
      };
      final invalidCbor = cbor.encode(CborMap(invalidMap));

      expect(
        () => ReplicationCbor.decode(invalidCbor),
        throwsA(isA<ReplicationSerializationError>()
            .having((e) => e.code, 'code',
                ReplicationSerializationErrorCode.schemaViolation)
            .having((e) => e.message, 'message',
                contains('Non-tombstone events must contain a "value" field'))),
      );
    });
  });

  group('ReplicationCbor.validateEvent', () {
    test('accepts valid value event', () {
      final event = ReplicationEvent.setValue(
        key: 'valid:key',
        value: 'valid value',
        timestamp_ms: 1234567890,
        node_id: 'node-1',
        seq: 1,
      );

      expect(() => ReplicationCbor.validateEvent(event), returnsNormally);
    });

    test('accepts valid tombstone event', () {
      final event = ReplicationEvent.setTombstone(
        key: 'valid:key',
        timestamp_ms: 1234567890,
        node_id: 'node-1',
        seq: 1,
      );

      expect(() => ReplicationCbor.validateEvent(event), returnsNormally);
    });

    test('throws for empty key', () {
      final event = ReplicationEvent.setValue(
        key: '',
        value: 'value',
        timestamp_ms: 123,
        node_id: 'node1',
        seq: 1,
      );

      expect(
        () => ReplicationCbor.validateEvent(event),
        throwsA(isA<ReplicationSerializationError>()
            .having((e) => e.code, 'code',
                ReplicationSerializationErrorCode.schemaViolation)
            .having(
                (e) => e.message, 'message', contains('Key cannot be empty'))),
      );
    });

    test('throws for key exceeding size limit', () {
      final longKey = 'x' * 257; // Exceeds 256 byte limit
      final event = ReplicationEvent.setValue(
        key: longKey,
        value: 'value',
        timestamp_ms: 123,
        node_id: 'node1',
        seq: 1,
      );

      expect(
        () => ReplicationCbor.validateEvent(event),
        throwsA(isA<ReplicationSerializationError>()
            .having((e) => e.code, 'code',
                ReplicationSerializationErrorCode.schemaViolation)
            .having((e) => e.message, 'message', contains('Key UTF-8 size'))),
      );
    });

    test('throws for empty node_id', () {
      final event = ReplicationEvent.setValue(
        key: 'key',
        value: 'value',
        timestamp_ms: 123,
        node_id: '',
        seq: 1,
      );

      expect(
        () => ReplicationCbor.validateEvent(event),
        throwsA(isA<ReplicationSerializationError>()
            .having((e) => e.code, 'code',
                ReplicationSerializationErrorCode.schemaViolation)
            .having((e) => e.message, 'message',
                contains('Node ID cannot be empty'))),
      );
    });

    test('throws for node_id exceeding length limit', () {
      final longNodeId = 'x' * 129; // Exceeds 128 character limit
      final event = ReplicationEvent.setValue(
        key: 'key',
        value: 'value',
        timestamp_ms: 123,
        node_id: longNodeId,
        seq: 1,
      );

      expect(
        () => ReplicationCbor.validateEvent(event),
        throwsA(isA<ReplicationSerializationError>()
            .having((e) => e.code, 'code',
                ReplicationSerializationErrorCode.schemaViolation)
            .having((e) => e.message, 'message', contains('Node ID length'))),
      );
    });

    test('throws for negative sequence number', () {
      final event = ReplicationEvent.setValue(
        key: 'key',
        value: 'value',
        timestamp_ms: 123,
        node_id: 'node1',
        seq: -1,
      );

      expect(
        () => ReplicationCbor.validateEvent(event),
        throwsA(isA<ReplicationSerializationError>()
            .having((e) => e.code, 'code',
                ReplicationSerializationErrorCode.schemaViolation)
            .having((e) => e.message, 'message',
                contains('Sequence number must be non-negative'))),
      );
    });

    test('throws for negative timestamp', () {
      final event = ReplicationEvent.setValue(
        key: 'key',
        value: 'value',
        timestamp_ms: -1,
        node_id: 'node1',
        seq: 1,
      );

      expect(
        () => ReplicationCbor.validateEvent(event),
        throwsA(isA<ReplicationSerializationError>()
            .having((e) => e.code, 'code',
                ReplicationSerializationErrorCode.schemaViolation)
            .having((e) => e.message, 'message',
                contains('Timestamp must be non-negative'))),
      );
    });

    test('throws for value exceeding size limit', () {
      final largeValue = 'x' * (256 * 1024 + 1); // Exceeds 256 KiB limit
      final event = ReplicationEvent.setValue(
        key: 'key',
        value: largeValue,
        timestamp_ms: 123,
        node_id: 'node1',
        seq: 1,
      );

      expect(
        () => ReplicationCbor.validateEvent(event),
        throwsA(isA<ReplicationSerializationError>()
            .having((e) => e.code, 'code',
                ReplicationSerializationErrorCode.schemaViolation)
            .having((e) => e.message, 'message', contains('Value UTF-8 size'))),
      );
    });

    test('throws for tombstone with non-null value', () {
      final event = ReplicationEvent(
        key: 'key',
        value: 'should be null',
        timestamp_ms: 123,
        node_id: 'node1',
        seq: 1,
        tombstone: true,
      );

      expect(
        () => ReplicationCbor.validateEvent(event),
        throwsA(isA<ReplicationSerializationError>()
            .having((e) => e.code, 'code',
                ReplicationSerializationErrorCode.schemaViolation)
            .having((e) => e.message, 'message',
                contains('Tombstone events must have null value'))),
      );
    });

    test('throws for non-tombstone with null value', () {
      final event = ReplicationEvent(
        key: 'key',
        value: null,
        timestamp_ms: 123,
        node_id: 'node1',
        seq: 1,
        tombstone: false,
      );

      expect(
        () => ReplicationCbor.validateEvent(event),
        throwsA(isA<ReplicationSerializationError>()
            .having((e) => e.code, 'code',
                ReplicationSerializationErrorCode.schemaViolation)
            .having((e) => e.message, 'message',
                contains('Non-tombstone events must have non-null value'))),
      );
    });
  });

  group('Size limit boundary tests', () {
    test('payload exactly at 300 KiB limit passes', () {
      // Create a value that when encoded will be exactly at or just under 300 KiB
      // We need to account for CBOR overhead (map structure, keys, other fields)
      // Approximate overhead: ~50-100 bytes for structure + field names
      final targetValueSize = (300 * 1024) - 200; // Leave room for overhead
      final largeValue = 'x' * targetValueSize;

      final event = ReplicationEvent.setValue(
        key: 'k',
        value: largeValue,
        timestamp_ms: 1,
        node_id: 'n',
        seq: 1,
      );

      final encoded = ReplicationCbor.encode(event);
      expect(encoded.length, lessThanOrEqualTo(300 * 1024));

      // Should decode successfully
      final decoded = ReplicationCbor.decode(encoded);
      expect(decoded, equals(event));
    });

    test('value at 256 KiB UTF-8 limit encodes under 300 KiB', () {
      final maxValue = 'x' * (256 * 1024); // Exactly 256 KiB
      final event = ReplicationEvent.setValue(
        key: 'key',
        value: maxValue,
        timestamp_ms: 1234567890,
        node_id: 'node',
        seq: 1,
      );

      // Should validate without throwing
      expect(() => ReplicationCbor.validateEvent(event), returnsNormally);

      // Should encode successfully and stay under 300 KiB
      final encoded = ReplicationCbor.encode(event);
      expect(encoded.length, lessThan(300 * 1024));

      // Should round-trip correctly
      final decoded = ReplicationCbor.decode(encoded);
      expect(decoded.value?.length, equals(256 * 1024));
    });

    test('UTF-8 multi-byte characters handled correctly in size limits', () {
      // Use Unicode characters that are 3 bytes each in UTF-8
      final unicodeChar = '€'; // Euro symbol is 3 bytes in UTF-8
      final utf8Bytes = utf8.encode(unicodeChar);
      expect(utf8Bytes.length, equals(3));

      // Create a key that's exactly at the 256 byte limit
      final keyChars = 256 ~/ 3; // 85 characters * 3 bytes = 255 bytes
      final key = unicodeChar * keyChars;
      expect(utf8.encode(key).length, lessThanOrEqualTo(256));

      final event = ReplicationEvent.setValue(
        key: key,
        value: 'test',
        timestamp_ms: 123,
        node_id: 'node',
        seq: 1,
      );

      expect(() => ReplicationCbor.validateEvent(event), returnsNormally);
    });
  });

  group('Deterministic encoding verification', () {
    test('identical events from different instances produce identical CBOR',
        () {
      // Create events separately to ensure they're different instances
      final event1 = ReplicationEvent.setValue(
        key: 'deterministic:test',
        value: 'same value',
        timestamp_ms: 1637142400000,
        node_id: 'device-1',
        seq: 999,
      );

      final event2 = ReplicationEvent.setValue(
        key: 'deterministic:test',
        value: 'same value',
        timestamp_ms: 1637142400000,
        node_id: 'device-1',
        seq: 999,
      );

      final encoded1 = ReplicationCbor.encode(event1);
      final encoded2 = ReplicationCbor.encode(event2);

      // Verify they're different instances but equal
      expect(identical(event1, event2), isFalse);
      expect(event1, equals(event2));

      // Verify encoded bytes are identical
      expect(encoded1, equals(encoded2));

      // Verify as hex strings for visual verification
      final hex1 =
          encoded1.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final hex2 =
          encoded2.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(hex1, equals(hex2));
    });

    test('field order is deterministic (insertion order preserved)', () {
      final event = ReplicationEvent.setValue(
        key: 'order:test',
        value: 'test value',
        timestamp_ms: 1234567890,
        node_id: 'node-order',
        seq: 42,
      );

      // Encode multiple times to ensure consistent ordering
      final encoded1 = ReplicationCbor.encode(event);
      final encoded2 = ReplicationCbor.encode(event);
      final encoded3 = ReplicationCbor.encode(event);

      expect(encoded1, equals(encoded2));
      expect(encoded2, equals(encoded3));

      // Decode and verify field order is preserved in round-trip
      final decoded = ReplicationCbor.decode(encoded1);
      expect(decoded, equals(event));
    });
  });
}
