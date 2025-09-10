import 'package:test/test.dart';
import 'package:merkle_kv_core/src/commands/command_processor.dart';
import 'package:merkle_kv_core/src/commands/command.dart';
import 'package:merkle_kv_core/src/commands/response.dart';
import 'package:merkle_kv_core/src/config/merkle_kv_config.dart';
import 'package:merkle_kv_core/src/storage/storage_interface.dart';
import 'package:merkle_kv_core/src/storage/storage_entry.dart';

/// Mock storage implementation for testing.
class MockStorage implements StorageInterface {
  final Map<String, StorageEntry> _entries = {};

  @override
  Future<StorageEntry?> get(String key) async {
    final entry = _entries[key];
    if (entry == null || entry.isTombstone) {
      return null;
    }
    return entry;
  }

  @override
  Future<void> put(String key, StorageEntry entry) async {
    _entries[key] = entry;
  }

  @override
  Future<void> delete(
      String key, int timestampMs, String nodeId, int seq) async {
    final tombstone = StorageEntry.tombstone(
      key: key,
      timestampMs: timestampMs,
      nodeId: nodeId,
      seq: seq,
    );
    _entries[key] = tombstone;
  }

  @override
  Future<List<StorageEntry>> getAllEntries() async {
    return _entries.values.toList();
  }

  @override
  Future<int> garbageCollectTombstones() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final retentionMs = 24 * 60 * 60 * 1000; // 24 hours

    final expiredKeys = <String>[];
    for (final entry in _entries.entries) {
      if (entry.value.isTombstone &&
          now - entry.value.timestampMs > retentionMs) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      _entries.remove(key);
    }

    return expiredKeys.length;
  }

  @override
  Future<void> initialize() async {
    // No-op for mock
  }

  @override
  Future<void> dispose() async {
    _entries.clear();
  }

  // Helper methods for testing
  void setEntry(String key, StorageEntry entry) {
    _entries[key] = entry;
  }

  StorageEntry? getEntry(String key) {
    return _entries[key];
  }

  void clear() {
    _entries.clear();
  }
}

void main() {
  group('CommandProcessor', () {
    late MerkleKVConfig config;
    late MockStorage storage;
    late CommandProcessorImpl processor;

    setUp(() {
      config = MerkleKVConfig.create(
        mqttHost: 'test-host',
        clientId: 'test-client',
        nodeId: 'test-node',
      );
      storage = MockStorage();
      processor = CommandProcessorImpl(config, storage);
    });

    tearDown(() async {
      await storage.dispose();
    });

    group('GET operation', () {
      test('returns value for existing key', () async {
        // Setup: Store an entry
        final entry = StorageEntry.value(
          key: 'test-key',
          value: 'test-value',
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          nodeId: 'node1',
          seq: 1,
        );
        storage.setEntry('test-key', entry);

        final response = await processor.get('test-key');

        expect(response.status, equals(ResponseStatus.ok));
        expect(response.value, equals('test-value'));
        expect(response.errorCode, isNull);
      });

      test('returns NOT_FOUND for missing key', () async {
        final response = await processor.get('missing-key');

        expect(response.status, equals(ResponseStatus.error));
        expect(response.errorCode, equals(ErrorCode.notFound));
        expect(response.value, isNull);
      });

      test('returns NOT_FOUND for tombstone', () async {
        // Setup: Store a tombstone
        final tombstone = StorageEntry.tombstone(
          key: 'deleted-key',
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          nodeId: 'node1',
          seq: 1,
        );
        storage.setEntry('deleted-key', tombstone);

        final response = await processor.get('deleted-key');

        expect(response.status, equals(ResponseStatus.error));
        expect(response.errorCode, equals(ErrorCode.notFound));
      });

      test('returns PAYLOAD_TOO_LARGE for oversized key', () async {
        // Create key > 256 bytes
        final oversizedKey = 'a' * 257;

        final response = await processor.get(oversizedKey);

        expect(response.status, equals(ResponseStatus.error));
        expect(response.errorCode, equals(ErrorCode.payloadTooLarge));
      });

      test('validates key at UTF-8 byte boundary', () async {
        // Create key exactly 256 bytes in UTF-8
        final exactKey = 'a' * 256;

        final response = await processor.get(exactKey);

        expect(response.status, equals(ResponseStatus.error));
        expect(response.errorCode,
            equals(ErrorCode.notFound)); // Key doesn't exist, but size is valid
      });
    });

    group('SET operation', () {
      test('stores value successfully', () async {
        final response = await processor.set('test-key', 'test-value');

        expect(response.status, equals(ResponseStatus.ok));
        expect(response.errorCode, isNull);

        // Verify storage
        final stored = storage.getEntry('test-key');
        expect(stored, isNotNull);
        expect(stored!.key, equals('test-key'));
        expect(stored.value, equals('test-value'));
        expect(stored.nodeId, equals('test-node'));
        expect(stored.seq, equals(1));
        expect(stored.isTombstone, isFalse);
      });

      test('generates correct version vector', () async {
        final beforeTime = DateTime.now().millisecondsSinceEpoch;

        await processor.set('key1', 'value1');
        await processor.set('key2', 'value2');

        final entry1 = storage.getEntry('key1')!;
        final entry2 = storage.getEntry('key2')!;

        // Check timestamps
        expect(entry1.timestampMs, greaterThanOrEqualTo(beforeTime));
        expect(entry2.timestampMs, greaterThanOrEqualTo(entry1.timestampMs));

        // Check node IDs
        expect(entry1.nodeId, equals('test-node'));
        expect(entry2.nodeId, equals('test-node'));

        // Check sequence numbers increment
        expect(entry1.seq, equals(1));
        expect(entry2.seq, equals(2));
      });

      test('returns PAYLOAD_TOO_LARGE for oversized key', () async {
        final oversizedKey = 'a' * 257;

        final response = await processor.set(oversizedKey, 'value');

        expect(response.status, equals(ResponseStatus.error));
        expect(response.errorCode, equals(ErrorCode.payloadTooLarge));
      });

      test('returns PAYLOAD_TOO_LARGE for oversized value', () async {
        // Create value > 256 KiB
        final oversizedValue = 'a' * (256 * 1024 + 1);

        final response = await processor.set('key', oversizedValue);

        expect(response.status, equals(ResponseStatus.error));
        expect(response.errorCode, equals(ErrorCode.payloadTooLarge));
      });

      test('accepts value at size boundary', () async {
        // Create value exactly 256 KiB
        final maxValue = 'a' * (256 * 1024);

        final response = await processor.set('key', maxValue);

        expect(response.status, equals(ResponseStatus.ok));

        final stored = storage.getEntry('key')!;
        expect(stored.value, equals(maxValue));
      });

      test('handles UTF-8 characters correctly', () async {
        const unicodeValue = '🚀✨🌟'; // Multi-byte UTF-8 characters

        final response = await processor.set('unicode-key', unicodeValue);

        expect(response.status, equals(ResponseStatus.ok));

        final stored = storage.getEntry('unicode-key')!;
        expect(stored.value, equals(unicodeValue));
      });
    });

    group('DELETE operation', () {
      test('creates tombstone for existing key', () async {
        // Setup: Store an entry first
        await processor.set('test-key', 'test-value');

        final response = await processor.delete('test-key');

        expect(response.status, equals(ResponseStatus.ok));
        expect(response.errorCode, isNull);

        // Verify tombstone was created
        final tombstone = storage.getEntry('test-key')!;
        expect(tombstone.key, equals('test-key'));
        expect(tombstone.value, isNull);
        expect(tombstone.isTombstone, isTrue);
        expect(tombstone.nodeId, equals('test-node'));
        expect(tombstone.seq, equals(2)); // First seq was for SET
      });

      test('returns OK for non-existing key (idempotent)', () async {
        final response = await processor.delete('missing-key');

        expect(response.status, equals(ResponseStatus.ok));
        expect(response.errorCode, isNull);

        // Verify tombstone was created even for missing key
        final tombstone = storage.getEntry('missing-key')!;
        expect(tombstone.isTombstone, isTrue);
      });

      test('returns PAYLOAD_TOO_LARGE for oversized key', () async {
        final oversizedKey = 'a' * 257;

        final response = await processor.delete(oversizedKey);

        expect(response.status, equals(ResponseStatus.error));
        expect(response.errorCode, equals(ErrorCode.payloadTooLarge));
      });

      test('generates correct sequence number', () async {
        await processor.set('key1', 'value1'); // seq 1
        await processor.set('key2', 'value2'); // seq 2
        await processor.delete('key1'); // seq 3

        final tombstone = storage.getEntry('key1')!;
        expect(tombstone.seq, equals(3));
      });
    });

    group('processCommand', () {
      test('handles GET command', () async {
        // Setup
        storage.setEntry(
            'test-key',
            StorageEntry.value(
              key: 'test-key',
              value: 'test-value',
              timestampMs: DateTime.now().millisecondsSinceEpoch,
              nodeId: 'node1',
              seq: 1,
            ));

        final command = const Command(
          id: 'req-123',
          op: 'GET',
          key: 'test-key',
        );

        final response = await processor.processCommand(command);

        expect(response.id, equals('req-123'));
        expect(response.status, equals(ResponseStatus.ok));
        expect(response.value, equals('test-value'));
      });

      test('handles SET command', () async {
        final command = const Command(
          id: 'req-456',
          op: 'SET',
          key: 'new-key',
          value: 'new-value',
        );

        final response = await processor.processCommand(command);

        expect(response.id, equals('req-456'));
        expect(response.status, equals(ResponseStatus.ok));

        final stored = storage.getEntry('new-key')!;
        expect(stored.value, equals('new-value'));
      });

      test('handles DELETE command', () async {
        final command = const Command(
          id: 'req-789',
          op: 'DEL',
          key: 'delete-key',
        );

        final response = await processor.processCommand(command);

        expect(response.id, equals('req-789'));
        expect(response.status, equals(ResponseStatus.ok));

        final tombstone = storage.getEntry('delete-key')!;
        expect(tombstone.isTombstone, isTrue);
      });

      test('handles DELETE alias', () async {
        final command = const Command(
          id: 'req-000',
          op: 'DELETE',
          key: 'delete-key',
        );

        final response = await processor.processCommand(command);

        expect(response.status, equals(ResponseStatus.ok));
      });

      test('returns INVALID_REQUEST for unsupported operation', () async {
        final command = const Command(
          id: 'req-invalid',
          op: 'UNSUPPORTED',
          key: 'test-key',
        );

        final response = await processor.processCommand(command);

        expect(response.id, equals('req-invalid'));
        expect(response.status, equals(ResponseStatus.error));
        expect(response.errorCode, equals(ErrorCode.invalidRequest));
        expect(response.error, contains('Unsupported operation'));
      });

      test('returns INVALID_REQUEST for missing key in GET', () async {
        final command = const Command(
          id: 'req-nokey',
          op: 'GET',
        );

        final response = await processor.processCommand(command);

        expect(response.status, equals(ResponseStatus.error));
        expect(response.errorCode, equals(ErrorCode.invalidRequest));
        expect(response.error, contains('Missing key'));
      });

      test('returns INVALID_REQUEST for missing value in SET', () async {
        final command = const Command(
          id: 'req-novalue',
          op: 'SET',
          key: 'test-key',
        );

        final response = await processor.processCommand(command);

        expect(response.status, equals(ResponseStatus.error));
        expect(response.errorCode, equals(ErrorCode.invalidRequest));
        expect(response.error, contains('Missing value'));
      });
    });

    group('Idempotency', () {
      test('returns cached response for repeated request', () async {
        final command = const Command(
          id: 'idempotent-123',
          op: 'SET',
          key: 'test-key',
          value: 'test-value',
        );

        // First request
        final response1 = await processor.processCommand(command);
        expect(response1.status, equals(ResponseStatus.ok));

        // Modify storage to verify cache is used
        storage.clear();

        // Second request with same ID
        final response2 = await processor.processCommand(command);
        expect(response2.status, equals(ResponseStatus.ok));
        expect(response2.id, equals(response1.id));

        // Storage should still be empty (cache was used)
        expect(storage.getEntry('test-key'), isNull);
      });

      test('does not cache error responses', () async {
        final command = const Command(
          id: 'error-request',
          op: 'GET',
          key: 'missing-key',
        );

        // First request (error)
        final response1 = await processor.processCommand(command);
        expect(response1.status, equals(ResponseStatus.error));

        // Add the key to storage
        storage.setEntry(
            'missing-key',
            StorageEntry.value(
              key: 'missing-key',
              value: 'now-exists',
              timestampMs: DateTime.now().millisecondsSinceEpoch,
              nodeId: 'node1',
              seq: 1,
            ));

        // Second request should return success (not cached error)
        final response2 = await processor.processCommand(command);
        expect(response2.status, equals(ResponseStatus.ok));
        expect(response2.value, equals('now-exists'));
      });

      test('ignores cache for empty request ID', () async {
        final command1 = const Command(
          id: '',
          op: 'SET',
          key: 'test-key',
          value: 'value1',
        );

        final command2 = const Command(
          id: '',
          op: 'SET',
          key: 'test-key',
          value: 'value2',
        );

        await processor.processCommand(command1);
        await processor.processCommand(command2);

        // Both should have executed (no caching)
        final stored = storage.getEntry('test-key')!;
        expect(stored.value, equals('value2')); // Last write wins
      });
    });

    group('Sequence number management', () {
      test('increments sequence for each mutation', () async {
        await processor.set('key1', 'value1');
        await processor.set('key2', 'value2');
        await processor.delete('key1');
        await processor.set('key3', 'value3');

        final entry2 = storage.getEntry('key2')!;
        final tombstone1 = storage.getEntry('key1')!;
        final entry3 = storage.getEntry('key3')!;

        expect(entry2.seq, equals(2));
        expect(tombstone1.seq, equals(3));
        expect(entry3.seq, equals(4));
      });

      test('does not increment sequence for GET operations', () async {
        await processor.set('key1', 'value1');
        await processor.get('key1');
        await processor.get('missing-key');
        await processor.set('key2', 'value2');

        final entry1 = storage.getEntry('key1')!;
        final entry2 = storage.getEntry('key2')!;

        expect(entry1.seq, equals(1));
        expect(entry2.seq, equals(2)); // GET didn't increment
      });
    });

    group('UTF-8 validation', () {
      test('validates multi-byte UTF-8 key length correctly', () async {
        // Create a string with multi-byte UTF-8 characters
        // Each emoji is 4 bytes in UTF-8
        final multiByteKey = '🚀' * 64; // 64 * 4 = 256 bytes exactly

        final response = await processor.set(multiByteKey, 'value');
        expect(response.status, equals(ResponseStatus.ok));

        // One more byte should fail
        final oversizedKey = multiByteKey + 'a'; // 257 bytes
        final errorResponse = await processor.set(oversizedKey, 'value');
        expect(errorResponse.errorCode, equals(ErrorCode.payloadTooLarge));
      });

      test('validates multi-byte UTF-8 value length correctly', () async {
        // Create value that's exactly 256 KiB in UTF-8
        final charCount = (256 * 1024) ~/ 4; // 4 bytes per emoji
        final maxValue = '🚀' * charCount;

        final response = await processor.set('key', maxValue);
        expect(response.status, equals(ResponseStatus.ok));

        // One more character should fail
        final oversizedValue = maxValue + '🚀';
        final errorResponse = await processor.set('key2', oversizedValue);
        expect(errorResponse.errorCode, equals(ErrorCode.payloadTooLarge));
      });
    });
  });
}
