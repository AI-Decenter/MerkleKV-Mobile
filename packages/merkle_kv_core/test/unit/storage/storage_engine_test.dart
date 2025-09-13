import 'dart:convert';
import 'dart:math';
import 'package:test/test.dart';
import 'package:merkle_kv_core/src/config/merkle_kv_config.dart';
import 'package:merkle_kv_core/src/storage/in_memory_storage.dart';
import 'package:merkle_kv_core/src/storage/storage_entry.dart';

void main() {
  group('Storage Engine', () {
    late InMemoryStorage storage;
    late MerkleKVConfig config;

    setUp(() {
      config = MerkleKVConfig.create(
        mqttHost: 'test-host',
        clientId: 'test-client',
        nodeId: 'test-node',
        persistenceEnabled: false,
      );
      storage = InMemoryStorage(config);
    });

    tearDown(() async {
      await storage.dispose();
    });

    group('LWW Resolution', () {
      setUp(() async {
        await storage.initialize();
      });

      test('LWW resolution with identical timestamps uses nodeId tiebreaker', () async {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        
        // Create entries with same timestamp but different nodeIds
        final entryA = StorageEntry.value(
          key: 'test-key',
          value: 'value-from-node-a',
          timestampMs: timestamp,
          nodeId: 'node-a',
          seq: 1,
        );
        
        final entryB = StorageEntry.value(
          key: 'test-key',
          value: 'value-from-node-b',
          timestampMs: timestamp,
          nodeId: 'node-b',
          seq: 1,
        );
        
        // Apply in order: A then B
        await storage.put('test-key', entryA);
        await storage.put('test-key', entryB);
        
        final result = await storage.get('test-key');
        
        // With identical timestamps, lexicographically larger nodeId wins
        if ('node-a'.compareTo('node-b') > 0) {
          expect(result?.value, equals('value-from-node-a'));
          expect(result?.nodeId, equals('node-a'));
        } else {
          expect(result?.value, equals('value-from-node-b'));
          expect(result?.nodeId, equals('node-b'));
        }
      });

      test('LWW resolution is consistent regardless of comparison order', () async {
        final random = Random(42); // Fixed seed for reproducibility
        
        for (int i = 0; i < 100; i++) {
          final timestamp1 = random.nextInt(1000000);
          final timestamp2 = random.nextInt(1000000);
          final nodeId1 = 'node-${random.nextInt(1000)}';
          final nodeId2 = 'node-${random.nextInt(1000)}';
          final seq1 = random.nextInt(1000);
          final seq2 = random.nextInt(1000);
          
          final entry1 = StorageEntry.value(
            key: 'lww-test-key',
            value: 'value-1',
            timestampMs: timestamp1,
            nodeId: nodeId1,
            seq: seq1,
          );
          
          final entry2 = StorageEntry.value(
            key: 'lww-test-key',
            value: 'value-2',
            timestampMs: timestamp2,
            nodeId: nodeId2,
            seq: seq2,
          );
          
          // Test order 1: entry1 then entry2
          await storage.put('lww-test-key', entry1);
          await storage.put('lww-test-key', entry2);
          final result1 = await storage.get('lww-test-key');
          
          // Clear and test order 2: entry2 then entry1
          await storage.delete('lww-test-key');
          await storage.put('lww-test-key', entry2);
          await storage.put('lww-test-key', entry1);
          final result2 = await storage.get('lww-test-key');
          
          // Results should be identical regardless of insertion order
          expect(result1?.value, equals(result2?.value),
              reason: 'LWW resolution should be deterministic for timestamps $timestamp1 vs $timestamp2, nodeIds $nodeId1 vs $nodeId2');
          expect(result1?.nodeId, equals(result2?.nodeId));
          expect(result1?.timestampMs, equals(result2?.timestampMs));
        }
      });

      test('sequence number tiebreaker when timestamp and nodeId are identical', () async {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        const nodeId = 'same-node';
        
        final entryLowerSeq = StorageEntry.value(
          key: 'seq-test-key',
          value: 'lower-seq-value',
          timestampMs: timestamp,
          nodeId: nodeId,
          seq: 5,
        );
        
        final entryHigherSeq = StorageEntry.value(
          key: 'seq-test-key',
          value: 'higher-seq-value',
          timestampMs: timestamp,
          nodeId: nodeId,
          seq: 10,
        );
        
        // Apply lower seq first, then higher
        await storage.put('seq-test-key', entryLowerSeq);
        await storage.put('seq-test-key', entryHigherSeq);
        
        final result = await storage.get('seq-test-key');
        expect(result?.value, equals('higher-seq-value'));
        expect(result?.seq, equals(10));
      });
    });

    group('Tombstone Management', () {
      setUp(() async {
        await storage.initialize();
      });

      test('tombstone GC removes entries older than 24h', () async {
        final now = DateTime.now().millisecondsSinceEpoch;
        final oldTimestamp = now - (25 * 60 * 60 * 1000); // 25 hours ago
        final recentTimestamp = now - (1 * 60 * 60 * 1000); // 1 hour ago
        
        // Create old tombstone
        final oldTombstone = StorageEntry.tombstone(
          key: 'old-deleted-key',
          timestampMs: oldTimestamp,
          nodeId: 'test-node',
          seq: 1,
        );
        
        // Create recent tombstone
        final recentTombstone = StorageEntry.tombstone(
          key: 'recent-deleted-key',
          timestampMs: recentTimestamp,
          nodeId: 'test-node',
          seq: 2,
        );
        
        await storage.put('old-deleted-key', oldTombstone);
        await storage.put('recent-deleted-key', recentTombstone);
        
        // Trigger GC
        await storage.garbageCollectTombstones();
        
        // Old tombstone should be removed, recent should remain
        final allEntries = await storage.getAllEntries();
        final hasOldTombstone = allEntries.any((e) => e.key == 'old-deleted-key');
        final hasRecentTombstone = allEntries.any((e) => e.key == 'recent-deleted-key');
        
        expect(hasOldTombstone, isFalse, reason: 'Old tombstone should be garbage collected');
        expect(hasRecentTombstone, isTrue, reason: 'Recent tombstone should be retained');
      });

      test('tombstone prevents resurrection of older entries', () async {
        final now = DateTime.now().millisecondsSinceEpoch;
        
        // Create initial value
        final initialValue = StorageEntry.value(
          key: 'resurrection-test',
          value: 'initial-value',
          timestampMs: now - 2000,
          nodeId: 'test-node',
          seq: 1,
        );
        
        // Create tombstone (newer)
        final tombstone = StorageEntry.tombstone(
          key: 'resurrection-test',
          timestampMs: now - 1000,
          nodeId: 'test-node',
          seq: 2,
        );
        
        // Create attempted resurrection (older than tombstone)
        final resurrectAttempt = StorageEntry.value(
          key: 'resurrection-test',
          value: 'resurrection-value',
          timestampMs: now - 1500, // Older than tombstone
          nodeId: 'test-node',
          seq: 3,
        );
        
        await storage.put('resurrection-test', initialValue);
        await storage.put('resurrection-test', tombstone);
        await storage.put('resurrection-test', resurrectAttempt);
        
        final result = await storage.get('resurrection-test');
        expect(result, isNull, reason: 'Tombstone should prevent resurrection of older entries');
      });
    });

    group('UTF-8 Validation', () {
      setUp(() async {
        await storage.initialize();
      });

      test('UTF-8 validation rejects invalid byte sequences', () async {
        // Create key with invalid UTF-8 by manipulating bytes directly
        final invalidUtf8Bytes = [0xFF, 0xFE]; // Invalid UTF-8 sequence
        final invalidKey = String.fromCharCodes(invalidUtf8Bytes);
        
        final entry = StorageEntry.value(
          key: invalidKey,
          value: 'test-value',
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          nodeId: 'test-node',
          seq: 1,
        );
        
        expect(
          () => storage.put(invalidKey, entry),
          throwsA(isA<ArgumentError>()),
          reason: 'Invalid UTF-8 sequences should be rejected',
        );
      });

      test('rejects overlong UTF-8 encodings', () async {
        // Create overlong encoding of ASCII 'A' (should be 0x41, not 0xC0 0x81)
        final overlongBytes = [0xC0, 0x81]; // Overlong encoding
        
        try {
          final overlongKey = String.fromCharCodes(overlongBytes);
          final entry = StorageEntry.value(
            key: overlongKey,
            value: 'test-value',
            timestampMs: DateTime.now().millisecondsSinceEpoch,
            nodeId: 'test-node',
            seq: 1,
          );
          
          expect(
            () => storage.put(overlongKey, entry),
            throwsA(isA<ArgumentError>()),
            reason: 'Overlong UTF-8 encodings should be rejected',
          );
        } on FormatException {
          // Dart may throw FormatException for invalid sequences
          // This is acceptable behavior
        }
      });

      test('handles surrogate pairs correctly', () async {
        // Test with valid surrogate pair (emoji)
        const validEmoji = '🚀'; // Valid UTF-8 emoji
        final entry = StorageEntry.value(
          key: 'emoji-test',
          value: validEmoji,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          nodeId: 'test-node',
          seq: 1,
        );
        
        await storage.put('emoji-test', entry);
        final result = await storage.get('emoji-test');
        
        expect(result?.value, equals(validEmoji));
      });
    });

    group('Payload Size Limits', () {
      setUp(() async {
        await storage.initialize();
      });

      test('payload cap enforced: values >256KiB rejected', () async {
        // Create value exactly 256KiB + 1 byte
        final oversizedValue = 'a' * (256 * 1024 + 1);
        
        final entry = StorageEntry.value(
          key: 'oversized-test',
          value: oversizedValue,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          nodeId: 'test-node',
          seq: 1,
        );
        
        expect(
          () => storage.put('oversized-test', entry),
          throwsA(isA<ArgumentError>()),
          reason: 'Values exceeding 256KiB should be rejected',
        );
      });

      test('accepts value exactly 256KiB', () async {
        // Create value exactly 256KiB
        final maxSizeValue = 'a' * (256 * 1024);
        
        final entry = StorageEntry.value(
          key: 'max-size-test',
          value: maxSizeValue,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          nodeId: 'test-node',
          seq: 1,
        );
        
        await storage.put('max-size-test', entry);
        final result = await storage.get('max-size-test');
        
        expect(result?.value, equals(maxSizeValue));
      });

      test('key size limit: >256 bytes UTF-8 rejected', () async {
        // Create key exactly 257 bytes UTF-8
        final oversizedKey = 'k' * 257;
        
        final entry = StorageEntry.value(
          key: oversizedKey,
          value: 'test-value',
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          nodeId: 'test-node',
          seq: 1,
        );
        
        expect(
          () => storage.put(oversizedKey, entry),
          throwsA(isA<ArgumentError>()),
          reason: 'Keys exceeding 256 bytes UTF-8 should be rejected',
        );
      });

      test('multi-byte UTF-8 characters count as multiple bytes', () async {
        // Each € character is 3 bytes in UTF-8
        // 85 × 3 = 255 bytes (valid)
        // 86 × 3 = 258 bytes (invalid)
        final validKey = '€' * 85; // 255 bytes
        final invalidKey = '€' * 86; // 258 bytes
        
        final validEntry = StorageEntry.value(
          key: validKey,
          value: 'test-value',
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          nodeId: 'test-node',
          seq: 1,
        );
        
        final invalidEntry = StorageEntry.value(
          key: invalidKey,
          value: 'test-value',
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          nodeId: 'test-node',
          seq: 2,
        );
        
        // Valid key should work
        await storage.put(validKey, validEntry);
        final result = await storage.get(validKey);
        expect(result?.value, equals('test-value'));
        
        // Invalid key should be rejected
        expect(
          () => storage.put(invalidKey, invalidEntry),
          throwsA(isA<ArgumentError>()),
          reason: 'Multi-byte UTF-8 characters should count as multiple bytes',
        );
      });
    });

    group('Deduplication by (node_id, seq)', () {
      setUp(() async {
        await storage.initialize();
      });

      test('deduplication by (node_id, seq) prevents duplicate processing', () async {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        const nodeId = 'test-node';
        const seq = 42;
        
        final entry1 = StorageEntry.value(
          key: 'dedup-test',
          value: 'first-value',
          timestampMs: timestamp,
          nodeId: nodeId,
          seq: seq,
        );
        
        // Same (nodeId, seq) but different value - should be deduplicated
        final entry2 = StorageEntry.value(
          key: 'dedup-test',
          value: 'second-value',
          timestampMs: timestamp + 1000, // Even newer timestamp
          nodeId: nodeId,
          seq: seq, // Same sequence number
        );
        
        await storage.put('dedup-test', entry1);
        await storage.put('dedup-test', entry2); // Should be ignored
        
        final result = await storage.get('dedup-test');
        expect(result?.value, equals('first-value'),
            reason: 'Duplicate (nodeId, seq) should be ignored');
      });

      test('different sequence numbers from same node are processed', () async {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        const nodeId = 'test-node';
        
        final entry1 = StorageEntry.value(
          key: 'seq-diff-test',
          value: 'seq-1-value',
          timestampMs: timestamp,
          nodeId: nodeId,
          seq: 1,
        );
        
        final entry2 = StorageEntry.value(
          key: 'seq-diff-test',
          value: 'seq-2-value',
          timestampMs: timestamp + 1000,
          nodeId: nodeId,
          seq: 2, // Different sequence number
        );
        
        await storage.put('seq-diff-test', entry1);
        await storage.put('seq-diff-test', entry2);
        
        final result = await storage.get('seq-diff-test');
        expect(result?.value, equals('seq-2-value'),
            reason: 'Different sequence numbers should be processed');
      });

      test('same sequence from different nodes are processed', () async {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        const seq = 42;
        
        final entryNode1 = StorageEntry.value(
          key: 'node-diff-test',
          value: 'node-1-value',
          timestampMs: timestamp,
          nodeId: 'node-1',
          seq: seq,
        );
        
        final entryNode2 = StorageEntry.value(
          key: 'node-diff-test',
          value: 'node-2-value',
          timestampMs: timestamp + 1000,
          nodeId: 'node-2', // Different node
          seq: seq, // Same sequence number
        );
        
        await storage.put('node-diff-test', entryNode1);
        await storage.put('node-diff-test', entryNode2);
        
        final result = await storage.get('node-diff-test');
        expect(result?.value, equals('node-2-value'),
            reason: 'Same sequence from different nodes should be processed');
      });
    });

    group('Persistence and Recovery', () {
      test('persistence maintains LWW ordering across restarts', () async {
        final persistentConfig = MerkleKVConfig.create(
          mqttHost: 'test-host',
          clientId: 'test-client',
          nodeId: 'test-node',
          persistenceEnabled: true,
        );
        
        final storage1 = InMemoryStorage(persistentConfig);
        await storage1.initialize();
        
        try {
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          
          final entry1 = StorageEntry.value(
            key: 'persist-test',
            value: 'persistent-value',
            timestampMs: timestamp,
            nodeId: 'test-node',
            seq: 1,
          );
          
          await storage1.put('persist-test', entry1);
          await storage1.dispose();
          
          // Create new storage instance (simulating restart)
          final storage2 = InMemoryStorage(persistentConfig);
          await storage2.initialize();
          
          final result = await storage2.get('persist-test');
          expect(result?.value, equals('persistent-value'));
          expect(result?.timestampMs, equals(timestamp));
          
          await storage2.dispose();
        } finally {
          // Cleanup
          await storage1.dispose();
        }
      });
    });

    group('Concurrent Operations', () {
      setUp(() async {
        await storage.initialize();
      });

      test('concurrent puts maintain consistency', () async {
        final futures = <Future<void>>[];
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        
        // Launch 10 concurrent operations
        for (int i = 0; i < 10; i++) {
          final entry = StorageEntry.value(
            key: 'concurrent-test',
            value: 'value-$i',
            timestampMs: timestamp + i, // Different timestamps
            nodeId: 'test-node',
            seq: i,
          );
          
          futures.add(storage.put('concurrent-test', entry));
        }
        
        await Future.wait(futures);
        
        final result = await storage.get('concurrent-test');
        expect(result, isNotNull);
        // Should have the entry with highest timestamp
        expect(result?.timestampMs, equals(timestamp + 9));
        expect(result?.value, equals('value-9'));
      });
    });
  });
}