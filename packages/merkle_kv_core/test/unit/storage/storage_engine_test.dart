import 'package:test/test.dart';
import 'package:merkle_kv_core/src/storage/in_memory_storage.dart';
import 'package:merkle_kv_core/src/storage/storage_entry.dart';
import 'package:merkle_kv_core/src/config/merkle_kv_config.dart';

void main() {
  late InMemoryStorage storage;
  late MerkleKVConfig config;

  setUp(() async {
    config = MerkleKVConfig(
      clientId: 'test-client',
      nodeId: 'test-node',
      mqttHost: 'test.example.com',
    );
    storage = InMemoryStorage(config);
    await storage.initialize();
  });

  group('Storage Engine Tests', () {
    group('LWW Resolution', () {
      test('last write wins with timestamp comparison', () async {
        final entry1 = StorageEntry(
          key: 'lww-test-key',
          value: 'first-value',
          timestampMs: 1000,
          nodeId: 'node-1',
          seq: 1,
          isTombstone: false,
        );

        final entry2 = StorageEntry(
          key: 'lww-test-key',
          value: 'second-value',
          timestampMs: 2000,
          nodeId: 'node-2',
          seq: 2,
          isTombstone: false,
        );

        await storage.put('lww-test-key', entry1);
        await storage.put('lww-test-key', entry2);

        final result = await storage.get('lww-test-key');
        expect(result?.value, equals('second-value'));
        expect(result?.timestampMs, equals(2000));
      });

      test('tiebreaker uses node ID when timestamps equal', () async {
        final entry1 = StorageEntry(
          key: 'lww-test-key',
          value: 'value-a',
          timestampMs: 1000,
          nodeId: 'node-a',
          seq: 1,
          isTombstone: false,
        );

        final entry2 = StorageEntry(
          key: 'lww-test-key',
          value: 'value-b',
          timestampMs: 1000,
          nodeId: 'node-b',
          seq: 2,
          isTombstone: false,
        );

        await storage.put('lww-test-key', entry1);
        await storage.put('lww-test-key', entry2);

        final result = await storage.get('lww-test-key');
        expect(result, isNotNull);
        // Result should be deterministic (node-b > node-a)
        expect(result!.value, equals('value-b'));
      });
    });

    group('Tombstone Handling', () {
      test('tombstone overwrites regular entry', () async {
        final regularEntry = StorageEntry(
          key: 'tombstone-key',
          value: 'regular-value',
          timestampMs: 1000,
          nodeId: 'node-1',
          seq: 1,
          isTombstone: false,
        );

        final tombstoneEntry = StorageEntry(
          key: 'tombstone-key',
          value: null,
          timestampMs: 2000,
          nodeId: 'node-2',
          seq: 2,
          isTombstone: true,
        );

        await storage.put('tombstone-key', regularEntry);
        await storage.put('tombstone-key', tombstoneEntry);

        final result = await storage.get('tombstone-key');
        expect(result, isNull); // Tombstones return null
      });

      test('later regular entry overwrites tombstone', () async {
        final tombstoneEntry = StorageEntry(
          key: 'revival-key',
          value: null,
          timestampMs: 1000,
          nodeId: 'node-1',
          seq: 1,
          isTombstone: true,
        );

        final regularEntry = StorageEntry(
          key: 'revival-key',
          value: 'revived-value',
          timestampMs: 2000,
          nodeId: 'node-2',
          seq: 2,
          isTombstone: false,
        );

        await storage.put('revival-key', tombstoneEntry);
        await storage.put('revival-key', regularEntry);

        final result = await storage.get('revival-key');
        expect(result?.value, equals('revived-value'));
      });
    });

    group('Deduplication', () {
      test('duplicate (node_id, seq) pairs are deduplicated', () async {
        final entry1 = StorageEntry(
          key: 'dedup-key',
          value: 'first-attempt',
          timestampMs: 1000,
          nodeId: 'node-1',
          seq: 5,
          isTombstone: false,
        );

        final entry2 = StorageEntry(
          key: 'dedup-key',
          value: 'duplicate-attempt',
          timestampMs: 1100,
          nodeId: 'node-1',
          seq: 5, // Same seq from same node
          isTombstone: false,
        );

        await storage.put('dedup-key', entry1);
        await storage.put('dedup-key', entry2);

        final result = await storage.get('dedup-key');
        expect(result?.value, equals('first-attempt')); // First one wins
      });
    });

    group('UTF-8 Validation', () {
      test('valid UTF-8 strings are stored correctly', () async {
        final unicodeEntry = StorageEntry(
          key: '🔑',
          value: '🚀 Valid UTF-8: 测试',
          timestampMs: 1000,
          nodeId: 'unicode-node',
          seq: 1,
          isTombstone: false,
        );

        await storage.put('🔑', unicodeEntry);
        final result = await storage.get('🔑');

        expect(result?.value, equals('🚀 Valid UTF-8: 测试'));
      });

      test('empty strings are handled correctly', () async {
        final emptyEntry = StorageEntry(
          key: 'empty-test',
          value: '',
          timestampMs: 1000,
          nodeId: 'empty-node',
          seq: 1,
          isTombstone: false,
        );

        await storage.put('empty-test', emptyEntry);
        final result = await storage.get('empty-test');

        expect(result?.value, equals(''));
      });
    });
  });
}