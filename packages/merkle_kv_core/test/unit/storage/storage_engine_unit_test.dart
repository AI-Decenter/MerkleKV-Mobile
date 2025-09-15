import 'dart:convert';
import 'package:test/test.dart';
import '../../../lib/src/storage/in_memory_storage.dart';
import '../../../lib/src/config/merkle_kv_config.dart';
import '../../utils/generators.dart';
import '../../utils/mock_helpers.dart';

void main() {
  group('Storage Engine Unit Tests', () {
    late InMemoryStorage storage;
    late MerkleKVConfig config;

    setUp(() {
      config = MerkleKVConfig.create(
        mqttHost: 'localhost',
        clientId: 'test-client',
        nodeId: 'test-node',
        persistenceEnabled: false,
      );
      storage = InMemoryStorage(config);
      storage.initialize();
    });

    tearDown(() {
      storage.dispose();
    });

    group('Last-Write-Wins Resolution', () {
      test('newer timestamp wins', () async {
        final older = TestDataFactory.createEntry(
          key: 'lww-key',
          value: 'old-value',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        final newer = TestDataFactory.createEntry(
          key: 'lww-key',
          value: 'new-value',
          timestampMs: 2000,
          nodeId: 'node1',
          seq: 2,
        );

        storage.put('lww-key', older);
        storage.put('lww-key', newer);

        final result = await storage.get('lww-key');
        expect(result?.value, equals('new-value'));
        expect(result?.timestampMs, equals(2000));
      });

      test('node ID tiebreaker works correctly', () async {
        final entryA = TestDataFactory.createEntry(
          key: 'tiebreaker-key',
          value: 'value-from-nodeA',
          timestampMs: 1000,
          nodeId: 'nodeA',
          seq: 1,
        );

        final entryZ = TestDataFactory.createEntry(
          key: 'tiebreaker-key',
          value: 'value-from-nodeZ',
          timestampMs: 1000, // Same timestamp
          nodeId: 'nodeZ', // Higher lexicographically
          seq: 2,
        );

        storage.put('tiebreaker-key', entryA);
        storage.put('tiebreaker-key', entryZ);

        final result = await storage.get('tiebreaker-key');
        expect(result?.value, equals('value-from-nodeZ'));
        expect(result?.nodeId, equals('nodeZ'));
      });

      test('older entry is ignored when newer exists', () async {
        final newer = TestDataFactory.createEntry(
          key: 'lww-key',
          value: 'new-value',
          timestampMs: 2000,
          nodeId: 'node1',
          seq: 2,
        );

        final older = TestDataFactory.createEntry(
          key: 'lww-key',
          value: 'old-value',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        storage.put('lww-key', newer);
        storage.put('lww-key', older); // Should be ignored

        final result = await storage.get('lww-key');
        expect(result?.value, equals('new-value'));
        expect(result?.timestampMs, equals(2000));
      });

      test('duplicate version vector is ignored', () async {
        final entry1 = TestDataFactory.createEntry(
          key: 'duplicate-key',
          value: 'first-value',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        final entry2 = TestDataFactory.createEntry(
          key: 'duplicate-key',
          value: 'second-value', // Different value
          timestampMs: 1000, // Same version vector
          nodeId: 'node1',
          seq: 1,
        );

        storage.put('duplicate-key', entry1);
        storage.put('duplicate-key', entry2); // Should be ignored

        final result = await storage.get('duplicate-key');
        expect(result?.value, equals('first-value')); // First entry wins
      });
    });

    group('Tombstone Garbage Collection', () {
      test('removes expired tombstones older than 24 hours', () async {
        final now = DateTime.now().millisecondsSinceEpoch;
        const twentyFiveHours = 25 * 60 * 60 * 1000;

        // Create an expired tombstone
        final expiredTombstone = TestDataFactory.createEntry(
          key: 'expired-key',
          timestampMs: now - twentyFiveHours,
          nodeId: 'node1',
          seq: 1,
          isTombstone: true,
        );

        // Create a fresh tombstone
        final freshTombstone = TestDataFactory.createEntry(
          key: 'fresh-key',
          timestampMs: now,
          nodeId: 'node1',
          seq: 2,
          isTombstone: true,
        );

        storage.put('expired-key', expiredTombstone);
        storage.put('fresh-key', freshTombstone);

        // Verify both exist before GC
        final entriesBeforeGC = await storage.getAllEntries();
        expect(entriesBeforeGC.length, equals(2));

        // Run garbage collection
        final removedCount = await storage.garbageCollectTombstones();

        // Should have removed 1 expired tombstone
        expect(removedCount, equals(1));

        // Verify only fresh tombstone remains
        final entriesAfterGC = await storage.getAllEntries();
        expect(entriesAfterGC.length, equals(1));
        expect(entriesAfterGC[0].key, equals('fresh-key'));
      });

      test('preserves fresh tombstones within 24 hour window', () async {
        final now = DateTime.now().millisecondsSinceEpoch;

        // Create tombstones at different ages within 24 hours
        final recentTombstone = TestDataFactory.createEntry(
          key: 'recent-key',
          timestampMs: now - (2 * 60 * 60 * 1000), // 2 hours ago
          nodeId: 'node1',
          seq: 1,
          isTombstone: true,
        );

        final olderTombstone = TestDataFactory.createEntry(
          key: 'older-key',
          timestampMs: now - (12 * 60 * 60 * 1000), // 12 hours ago
          nodeId: 'node1',
          seq: 2,
          isTombstone: true,
        );

        storage.put('recent-key', recentTombstone);
        storage.put('older-key', olderTombstone);

        // Run garbage collection
        final removedCount = await storage.garbageCollectTombstones();

        // No tombstones should be removed (both are recent)
        expect(removedCount, equals(0));

        final entriesAfterGC = await storage.getAllEntries();
        expect(entriesAfterGC.length, equals(2));
      });

      test('does not remove regular entries during GC', () async {
        final now = DateTime.now().millisecondsSinceEpoch;
        const twentyFiveHours = 25 * 60 * 60 * 1000;

        // Create an old regular entry (not a tombstone)
        final oldEntry = TestDataFactory.createEntry(
          key: 'old-regular-key',
          value: 'old-value',
          timestampMs: now - twentyFiveHours,
          nodeId: 'node1',
          seq: 1,
          isTombstone: false,
        );

        storage.put('old-regular-key', oldEntry);

        // Run garbage collection
        final removedCount = await storage.garbageCollectTombstones();

        // No entries should be removed
        expect(removedCount, equals(0));

        final result = await storage.get('old-regular-key');
        expect(result?.value, equals('old-value'));
      });

      test('returns zero when no tombstones to collect', () async {
        // Add only regular entries
        final entry = TestDataFactory.createEntry(
          key: 'regular-key',
          value: 'value',
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          nodeId: 'node1',
          seq: 1,
          isTombstone: false,
        );

        storage.put('regular-key', entry);

        final removedCount = await storage.garbageCollectTombstones();
        expect(removedCount, equals(0));
      });
    });

    group('UTF-8 Validation', () {
      test('accepts valid UTF-8 strings', () async {
        final validEntry = TestDataFactory.createEntry(
          key: 'test-key',
          value: 'valid-utf8-value',
          isTombstone: false,
        );
        
        // Valid UTF-8 should succeed
        storage.put('test-key', validEntry);
        expect(await storage.get('test-key'), isNotNull);
        
        // Test multi-byte UTF-8 characters
        final emojiEntry = TestDataFactory.createEntry(
          key: '🚀test🌟key🔥',
          value: '💫value✨with🎉emojis💯',
          isTombstone: false,
        );
        
        storage.put('🚀test🌟key🔥', emojiEntry);
        expect(await storage.get('🚀test🌟key🔥'), isNotNull);
      });

      test('UTF-8 byte length validation for keys and values', () async {
        // Test key size validation with multi-byte characters
        final maxKeyUtf8 = '🚀' * 64; // Each emoji is 4 bytes = 256 bytes total
        TestAssertions.assertUtf8ByteLength(maxKeyUtf8, 256);
        
        final maxKeyEntry = TestDataFactory.createEntry(
          key: maxKeyUtf8,
          value: 'test-value',
          isTombstone: false,
        );
        
        // Should succeed at boundary
        storage.put(maxKeyUtf8, maxKeyEntry);
        expect(await storage.get(maxKeyUtf8), isNotNull);

        // Test value size validation with multi-byte characters
        final maxValueUtf8 = '⚡' * (64 * 1024); // Each emoji is 4 bytes = 256KiB total
        TestAssertions.assertUtf8ByteLength(maxValueUtf8, 256 * 1024);
        
        final maxValueEntry = TestDataFactory.createEntry(
          key: 'test-key',
          value: maxValueUtf8,
          isTombstone: false,
        );
        
        // Should succeed at boundary
        storage.put('test-key', maxValueEntry);
        expect(await storage.get('test-key'), isNotNull);
      });
    });

    group('Deduplication by (node_id, seq)', () {
      test('allows same (node_id, seq) for different keys', () async {
        // Same (node_id, seq) is allowed for different keys since 
        // sequence numbers are operation counters, not global unique identifiers
        final entry1 = TestDataFactory.createEntry(
          key: 'key1',
          value: 'value1',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        final entry2 = TestDataFactory.createEntry(
          key: 'key2', // Different key
          value: 'value2',
          timestampMs: 2000,
          nodeId: 'node1', // Same node_id
          seq: 1, // Same seq - this is allowed for different keys
        );

        storage.put('key1', entry1);
        storage.put('key2', entry2);

        // Both entries should exist since they have different keys
        expect(await storage.get('key1'), isNotNull);
        expect(await storage.get('key2'), isNotNull);
      });

      test('allows different node_id with same seq', () async {
        final entry1 = TestDataFactory.createEntry(
          key: 'key1',
          value: 'value1',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        final entry2 = TestDataFactory.createEntry(
          key: 'key2',
          value: 'value2',
          timestampMs: 2000,
          nodeId: 'node2', // Different node_id
          seq: 1, // Same seq
        );

        storage.put('key1', entry1);
        storage.put('key2', entry2);

        expect(await storage.get('key1'), isNotNull);
        expect(await storage.get('key2'), isNotNull); // Should both exist
      });

      test('allows same node_id with different seq', () async {
        final entry1 = TestDataFactory.createEntry(
          key: 'key1',
          value: 'value1',
          timestampMs: 1000,
          nodeId: 'node1',
          seq: 1,
        );

        final entry2 = TestDataFactory.createEntry(
          key: 'key2',
          value: 'value2',
          timestampMs: 2000,
          nodeId: 'node1', // Same node_id
          seq: 2, // Different seq
        );

        storage.put('key1', entry1);
        storage.put('key2', entry2);

        expect(await storage.get('key1'), isNotNull);
        expect(await storage.get('key2'), isNotNull); // Should both exist
      });
    });

    group('Property-Based Tests', () {
      test('property: LWW resolution is consistent and deterministic', () async {
        final baseTimestamp = TestGenerators.randomTimestamp();
        
        final entry1 = TestDataFactory.createEntry(
          key: 'prop-key',
          value: 'value1',
          timestampMs: baseTimestamp,
          nodeId: 'nodeA',
          seq: 1,
        );

        final entry2 = TestDataFactory.createEntry(
          key: 'prop-key',
          value: 'value2',
          timestampMs: baseTimestamp + 1000, // Always newer
          nodeId: 'nodeB',
          seq: 2,
        );

        // Test that newer timestamp always wins regardless of order
        storage.put('prop-key', entry1);
        storage.put('prop-key', entry2);
        
        final result = await storage.get('prop-key');
        expect(result?.value, equals('value2'));
        expect(result?.timestampMs, equals(entry2.timestampMs));
      });

      test('property: tombstone GC preserves entries within 24h window', () async {
        final recentTimestamp = DateTime.now().millisecondsSinceEpoch - (20 * 60 * 60 * 1000); // 20 hours ago
        
        final tombstone = TestDataFactory.createEntry(
          key: 'recent-tombstone',
          timestampMs: recentTimestamp,
          nodeId: 'node1',
          seq: 1,
          isTombstone: true,
        );

        storage.put('recent-tombstone', tombstone);
        final removedCount = await storage.garbageCollectTombstones();

        // Should not remove recent tombstones
        expect(removedCount, equals(0));
      });

      test('property: UTF-8 validation correctly measures byte length', () {
        final testString = TestGenerators.randomUtf8String(
          minLength: 1,
          maxLength: 100,
          includeMultibyte: true,
          includeEmoji: true,
        );
        
        final bytes = utf8.encode(testString);
        final entry = TestDataFactory.createEntry(
          key: 'utf8-test',
          value: testString,
              isTombstone: false,
        );

        // Storage should respect UTF-8 byte length, not character count
        if (bytes.length <= 256 * 1024) { // Within value limit
          expect(() => storage.put('utf8-test', entry), returnsNormally);
        } else {
          // Should reject oversized values
          expect(() => storage.put('utf8-test', entry), throwsA(isA<Exception>()));
        }
      });
    });
  });
}