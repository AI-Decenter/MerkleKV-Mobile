import 'dart:math';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';

void main() {
  group('ReplicationEventApplicator', () {
    late InMemoryStorage storage;
    late InMemoryReplicationMetrics metrics;
    late ReplicationEventApplicatorImpl applicator;
    late MerkleKVConfig config;

    setUp(() async {
      config = MerkleKVConfig(
        mqttHost: 'localhost',
        nodeId: 'test-node',
        clientId: 'test-client',
        skewMaxFutureMs: 300000, // 5 minutes
      );
      
      storage = InMemoryStorage(config);
      await storage.initialize();
      
      metrics = InMemoryReplicationMetrics();
      
      applicator = ReplicationEventApplicatorImpl(
        config: config,
        storage: storage,
        metrics: metrics,
      );
      
      await applicator.initialize();
    });

    tearDown(() async {
      await applicator.dispose();
      await storage.dispose();
    });

    group('Basic Event Application', () {
      test('applies valid SET event to empty storage', () async {
        final event = ReplicationEvent.value(
          key: 'test-key',
          nodeId: 'node-1',
          seq: 1,
          timestampMs: 1000,
          value: 'test-value',
        );

        await applicator.applyEvent(event);

        final stored = await storage.get('test-key');
        expect(stored, isNotNull);
        expect(stored!.value, equals('test-value'));
        expect(stored.nodeId, equals('node-1'));
        expect(stored.seq, equals(1));
        expect(metrics.eventsApplied, equals(1));
      });

      test('applies valid DELETE event (tombstone)', () async {
        // First set a value
        await storage.put('test-key', StorageEntry.value(
          key: 'test-key',
          value: 'initial',
          timestampMs: 500,
          nodeId: 'node-0',
          seq: 1,
        ));

        final deleteEvent = ReplicationEvent.tombstone(
          key: 'test-key',
          nodeId: 'node-1',
          seq: 2,
          timestampMs: 1000,
        );

        await applicator.applyEvent(deleteEvent);

        final stored = await storage.get('test-key');
        expect(stored, isNull); // Tombstone should hide the entry
        expect(metrics.eventsApplied, equals(1));
      });

      test('emits application status for successful events', () async {
        final statusStream = applicator.applicationStatus;
        final statusFuture = statusStream.first;

        final event = ReplicationEvent.value(
          key: 'test-key',
          nodeId: 'node-1',
          seq: 1,
          timestampMs: 1000,
          value: 'test-value',
        );

        await applicator.applyEvent(event);

        final status = await statusFuture;
        expect(status.result, equals(ApplicationResult.applied));
        expect(status.event.key, equals('test-key'));
        expect(status.processingTime, isA<Duration>());
      });
    });

    group('Deduplication', () {
      test('detects and ignores duplicate events', () async {
        final event = ReplicationEvent.value(
          key: 'test-key',
          nodeId: 'node-1',
          seq: 1,
          timestampMs: 1000,
          value: 'test-value',
        );

        // Apply first time
        await applicator.applyEvent(event);
        expect(metrics.eventsApplied, equals(1));

        // Apply second time - should be duplicate
        await applicator.applyEvent(event);
        expect(metrics.eventsApplied, equals(1)); // No change
        expect(metrics.eventsDuplicate, equals(1));
      });

      test('tracks different sequences per node independently', () async {
        final event1 = ReplicationEvent.value(
          key: 'key1',
          nodeId: 'node-1',
          seq: 1,
          timestampMs: 1000,
          value: 'value1',
        );

        final event2 = ReplicationEvent.value(
          key: 'key2',
          nodeId: 'node-2',
          seq: 1, // Same seq but different node
          timestampMs: 1001,
          value: 'value2',
        );

        await applicator.applyEvent(event1);
        await applicator.applyEvent(event2);

        expect(metrics.eventsApplied, equals(2));
        expect(metrics.eventsDuplicate, equals(0));

        final stored1 = await storage.get('key1');
        final stored2 = await storage.get('key2');
        expect(stored1!.value, equals('value1'));
        expect(stored2!.value, equals('value2'));
      });

      test('handles out-of-window sequence numbers correctly', () async {
        // Create applicator with small window for testing
        final smallTracker = DeduplicationTracker(windowSize: 5);
        final smallApplicator = ReplicationEventApplicatorImpl(
          config: config,
          storage: storage,
          metrics: metrics,
          deduplicationTracker: smallTracker,
        );
        await smallApplicator.initialize();

        // Apply events with sequences 1-10
        for (int i = 1; i <= 10; i++) {
          final event = ReplicationEvent.value(
            key: 'key$i',
            nodeId: 'node-1',
            seq: i,
            timestampMs: 1000 + i,
            value: 'value$i',
          );
          await smallApplicator.applyEvent(event);
        }

        expect(metrics.eventsApplied, equals(10));

        // Now try to apply event with seq=1 again - should not be duplicate
        // because it's outside the window
        final oldEvent = ReplicationEvent.value(
          key: 'old-key',
          nodeId: 'node-1',
          seq: 1,
          timestampMs: 2000, // Newer timestamp
          value: 'old-value',
        );

        await smallApplicator.applyEvent(oldEvent);
        expect(metrics.eventsApplied, equals(11)); // Should be applied

        await smallApplicator.dispose();
      });
    });

    group('Last-Write-Wins Conflict Resolution', () {
      test('newer event wins over older event', () async {
        // Store older event
        final olderEvent = ReplicationEvent.value(
          key: 'test-key',
          nodeId: 'node-1',
          seq: 1,
          timestampMs: 1000,
          value: 'older-value',
        );
        await applicator.applyEvent(olderEvent);

        // Apply newer event
        final newerEvent = ReplicationEvent.value(
          key: 'test-key',
          nodeId: 'node-2',
          seq: 1,
          timestampMs: 2000,
          value: 'newer-value',
        );
        await applicator.applyEvent(newerEvent);

        final stored = await storage.get('test-key');
        expect(stored!.value, equals('newer-value'));
        expect(metrics.eventsApplied, equals(2));
      });

      test('older event is rejected', () async {
        // Store newer event first
        final newerEvent = ReplicationEvent.value(
          key: 'test-key',
          nodeId: 'node-1',
          seq: 1,
          timestampMs: 2000,
          value: 'newer-value',
        );
        await applicator.applyEvent(newerEvent);

        // Try to apply older event
        final olderEvent = ReplicationEvent.value(
          key: 'test-key',
          nodeId: 'node-2',
          seq: 1,
          timestampMs: 1000,
          value: 'older-value',
        );
        await applicator.applyEvent(olderEvent);

        final stored = await storage.get('test-key');
        expect(stored!.value, equals('newer-value')); // Unchanged
        expect(metrics.eventsApplied, equals(1));
        expect(metrics.eventsRejected, equals(1));
      });

      test('uses nodeId as tiebreaker for same timestamp', () async {
        final timestamp = 1000;

        // Apply event from node-b first
        final eventB = ReplicationEvent.value(
          key: 'test-key',
          nodeId: 'node-b',
          seq: 1,
          timestampMs: timestamp,
          value: 'value-b',
        );
        await applicator.applyEvent(eventB);

        // Apply event from node-a (should win due to lexicographic ordering)
        final eventA = ReplicationEvent.value(
          key: 'test-key',
          nodeId: 'node-a',
          seq: 1,
          timestampMs: timestamp,
          value: 'value-a',
        );
        await applicator.applyEvent(eventA);

        final stored = await storage.get('test-key');
        expect(stored!.value, equals('value-b')); // node-b wins (higher in sort order)
        expect(metrics.eventsApplied, equals(1));
        expect(metrics.eventsRejected, equals(1));
      });

      test('detects content duplicates with identical timestamps', () async {
        final event = ReplicationEvent.value(
          key: 'test-key',
          nodeId: 'node-1',
          seq: 1,
          timestampMs: 1000,
          value: 'test-value',
        );

        // Apply first time
        await applicator.applyEvent(event);

        // Apply identical event with different sequence (but same content)
        final duplicateEvent = ReplicationEvent.value(
          key: 'test-key',
          nodeId: 'node-1',
          seq: 2, // Different seq but same content
          timestampMs: 1000,
          value: 'test-value',
        );
        await applicator.applyEvent(duplicateEvent);

        expect(metrics.eventsApplied, equals(1));
        expect(metrics.eventsDuplicate, equals(1));
      });

      test('detects timestamp anomalies (same timestamp, different content)', () async {
        final event1 = ReplicationEvent.value(
          key: 'test-key',
          nodeId: 'node-1',
          seq: 1,
          timestampMs: 1000,
          value: 'value1',
        );
        await applicator.applyEvent(event1);

        // Same timestamp and nodeId but different content - anomaly
        final event2 = ReplicationEvent.value(
          key: 'test-key',
          nodeId: 'node-1',
          seq: 2,
          timestampMs: 1000,
          value: 'value2', // Different content
        );
        await applicator.applyEvent(event2);

        final stored = await storage.get('test-key');
        expect(stored!.value, equals('value1')); // Original value kept
        expect(metrics.eventsApplied, equals(1));
        expect(metrics.conflictsResolved, equals(1));
      });
    });

    group('Validation', () {
      test('rejects event with oversized key', () async {
        final longKey = 'k' * 257; // Exceeds 256 byte limit
        final event = ReplicationEvent.value(
          key: longKey,
          nodeId: 'node-1',
          seq: 1,
          timestampMs: 1000,
          value: 'value',
        );

        await applicator.applyEvent(event);

        expect(metrics.eventsApplied, equals(0));
        expect(metrics.eventsRejected, equals(1));
      });

      test('rejects event with oversized value', () async {
        final longValue = 'v' * (256 * 1024 + 1); // Exceeds 256 KiB limit
        final event = ReplicationEvent.value(
          key: 'key',
          nodeId: 'node-1',
          seq: 1,
          timestampMs: 1000,
          value: longValue,
        );

        await applicator.applyEvent(event);

        expect(metrics.eventsApplied, equals(0));
        expect(metrics.eventsRejected, equals(1));
      });

      test('rejects tombstone event with value', () async {
        // Create malformed event manually
        final malformedEvent = ReplicationEvent(
          key: 'key',
          nodeId: 'node-1',
          seq: 1,
          timestampMs: 1000,
          tombstone: true,
          value: 'should-not-have-value',
        );

        await applicator.applyEvent(malformedEvent);

        expect(metrics.eventsApplied, equals(0));
        expect(metrics.eventsRejected, equals(1));
      });

      test('rejects non-tombstone event without value', () async {
        // Create malformed event manually
        final malformedEvent = ReplicationEvent(
          key: 'key',
          nodeId: 'node-1',
          seq: 1,
          timestampMs: 1000,
          tombstone: false,
          value: null,
        );

        await applicator.applyEvent(malformedEvent);

        expect(metrics.eventsApplied, equals(0));
        expect(metrics.eventsRejected, equals(1));
      });

      test('rejects event with negative sequence', () async {
        final event = ReplicationEvent.value(
          key: 'key',
          nodeId: 'node-1',
          seq: -1,
          timestampMs: 1000,
          value: 'value',
        );

        await applicator.applyEvent(event);

        expect(metrics.eventsApplied, equals(0));
        expect(metrics.eventsRejected, equals(1));
      });

      test('rejects event with invalid timestamp', () async {
        final event = ReplicationEvent.value(
          key: 'key',
          nodeId: 'node-1',
          seq: 1,
          timestampMs: 0,
          value: 'value',
        );

        await applicator.applyEvent(event);

        expect(metrics.eventsApplied, equals(0));
        expect(metrics.eventsRejected, equals(1));
      });
    });

    group('Timestamp Clamping', () {
      test('clamps future timestamps beyond skew tolerance', () async {
        final futureTime = DateTime.now().millisecondsSinceEpoch + 
                          config.skewMaxFutureMs + 1000; // 1 second beyond limit

        final event = ReplicationEvent.value(
          key: 'test-key',
          nodeId: 'node-1',
          seq: 1,
          timestampMs: futureTime,
          value: 'test-value',
        );

        await applicator.applyEvent(event);

        final stored = await storage.get('test-key');
        expect(stored, isNotNull);
        expect(stored!.timestampMs, lessThan(futureTime));
        expect(metrics.eventsApplied, equals(1));
        expect(metrics.eventsClamped, equals(1));
      });

      test('does not clamp timestamps within skew tolerance', () async {
        final acceptableTime = DateTime.now().millisecondsSinceEpoch + 
                               config.skewMaxFutureMs - 1000; // 1 second before limit

        final event = ReplicationEvent.value(
          key: 'test-key',
          nodeId: 'node-1',
          seq: 1,
          timestampMs: acceptableTime,
          value: 'test-value',
        );

        await applicator.applyEvent(event);

        final stored = await storage.get('test-key');
        expect(stored, isNotNull);
        expect(stored!.timestampMs, equals(acceptableTime));
        expect(metrics.eventsApplied, equals(1));
        expect(metrics.eventsClamped, equals(0));
      });
    });

    group('CBOR Event Processing', () {
      test('applies valid CBOR event', () async {
        final event = ReplicationEvent.value(
          key: 'test-key',
          nodeId: 'node-1',
          seq: 1,
          timestampMs: 1000,
          value: 'test-value',
        );

        final cborData = CborSerializer.encode(event);
        await applicator.applyCborEvent(cborData);

        final stored = await storage.get('test-key');
        expect(stored, isNotNull);
        expect(stored!.value, equals('test-value'));
        expect(metrics.eventsApplied, equals(1));
      });

      test('rejects oversized CBOR payload', () async {
        final largeCbor = Uint8List(300 * 1024 + 1); // Exceeds 300 KiB limit
        await applicator.applyCborEvent(largeCbor);

        expect(metrics.eventsApplied, equals(0));
        expect(metrics.eventsRejected, equals(1));
      });

      test('handles malformed CBOR gracefully', () async {
        final malformedCbor = Uint8List.fromList([0xFF, 0xFE, 0xFD]); // Invalid CBOR
        await applicator.applyCborEvent(malformedCbor);

        expect(metrics.eventsApplied, equals(0));
        expect(metrics.eventsRejected, equals(1));
      });
    });

    group('Statistics and Observability', () {
      test('provides deduplication statistics', () async {
        final event1 = ReplicationEvent.value(
          key: 'key1',
          nodeId: 'node-1',
          seq: 1,
          timestampMs: 1000,
          value: 'value1',
        );

        final event2 = ReplicationEvent.value(
          key: 'key2',
          nodeId: 'node-2',
          seq: 1,
          timestampMs: 1001,
          value: 'value2',
        );

        await applicator.applyEvent(event1);
        await applicator.applyEvent(event2);
        await applicator.applyEvent(event1); // Duplicate

        final stats = applicator.getDeduplicationStats();
        expect(stats['events']['applied'], equals(2));
        expect(stats['events']['duplicate'], equals(1));
        expect(stats['tracker']['activeNodes'], equals(2));
        expect(stats['tracker']['totalChecks'], greaterThan(0));
      });

      test('records application latency metrics', () async {
        final event = ReplicationEvent.value(
          key: 'test-key',
          nodeId: 'node-1',
          seq: 1,
          timestampMs: 1000,
          value: 'test-value',
        );

        await applicator.applyEvent(event);

        expect(metrics.applicationLatencies, hasLength(1));
        expect(metrics.applicationLatencies.first, greaterThan(0));
      });
    });

    group('Error Isolation', () {
      test('continues processing after malformed event', () async {
        final malformedEvent = ReplicationEvent.value(
          key: 'k' * 300, // Invalid key
          nodeId: 'node-1',
          seq: 1,
          timestampMs: 1000,
          value: 'value',
        );

        final validEvent = ReplicationEvent.value(
          key: 'valid-key',
          nodeId: 'node-1',
          seq: 2,
          timestampMs: 1001,
          value: 'valid-value',
        );

        // Apply malformed event first
        await applicator.applyEvent(malformedEvent);
        
        // Valid event should still be processed
        await applicator.applyEvent(validEvent);

        final stored = await storage.get('valid-key');
        expect(stored, isNotNull);
        expect(stored!.value, equals('valid-value'));
        expect(metrics.eventsApplied, equals(1));
        expect(metrics.eventsRejected, equals(1));
      });
    });
  });

  group('DeduplicationTracker', () {
    late DeduplicationTracker tracker;

    setUp(() {
      tracker = DeduplicationTracker(
        windowSize: 10,
        ttl: Duration(milliseconds: 100),
        maxNodes: 3,
      );
    });

    tearDown(() {
      tracker.dispose();
    });

    group('Basic Functionality', () {
      test('marks and detects duplicates correctly', () {
        expect(tracker.isDuplicate('node-1', 1), isFalse);
        
        tracker.markSeen('node-1', 1);
        expect(tracker.isDuplicate('node-1', 1), isTrue);
      });

      test('handles different nodes independently', () {
        tracker.markSeen('node-1', 1);
        tracker.markSeen('node-2', 1);
        
        expect(tracker.isDuplicate('node-1', 1), isTrue);
        expect(tracker.isDuplicate('node-2', 1), isTrue);
        expect(tracker.isDuplicate('node-1', 2), isFalse);
        expect(tracker.isDuplicate('node-2', 2), isFalse);
      });
    });

    group('Window Management', () {
      test('slides window when sequence exceeds window size', () {
        for (int i = 1; i <= 15; i++) {
          tracker.markSeen('node-1', i);
        }
        
        // Early sequences should be evicted
        expect(tracker.isDuplicate('node-1', 1), isFalse);
        expect(tracker.isDuplicate('node-1', 2), isFalse);
        
        // Recent sequences should still be tracked
        expect(tracker.isDuplicate('node-1', 15), isTrue);
        expect(tracker.isDuplicate('node-1', 14), isTrue);
      });

      test('ignores sequences that are too old', () {
        tracker.markSeen('node-1', 10);
        tracker.markSeen('node-1', 1); // Too old, should be ignored
        
        expect(tracker.isDuplicate('node-1', 1), isFalse);
        expect(tracker.isDuplicate('node-1', 10), isTrue);
      });
    });

    group('LRU Eviction', () {
      test('evicts oldest node when max nodes exceeded', () {
        // Fill up to max nodes
        tracker.markSeen('node-1', 1);
        tracker.markSeen('node-2', 1);
        tracker.markSeen('node-3', 1);
        
        // Access node-1 to make it more recent
        tracker.isDuplicate('node-1', 1);
        
        // Add fourth node - should evict oldest (node-2 or node-3)
        tracker.markSeen('node-4', 1);
        
        final stats = tracker.stats;
        expect(stats['activeNodes'], equals(3));
        expect(stats['windowEvictions'], equals(1));
      });
    });

    group('TTL Cleanup', () {
      test('evicts expired entries', () async {
        tracker.markSeen('node-1', 1);
        
        // Wait for TTL to expire
        await Future.delayed(Duration(milliseconds: 150));
        
        // Trigger cleanup manually
        tracker.performCleanupForTesting();
        
        final stats = tracker.stats;
        expect(stats['activeNodes'], equals(0));
        expect(stats['ttlEvictions'], equals(1));
      });
    });

    group('Statistics', () {
      test('tracks hit rate correctly', () {
        tracker.markSeen('node-1', 1);
        
        tracker.isDuplicate('node-1', 1); // Hit
        tracker.isDuplicate('node-1', 2); // Miss
        tracker.isDuplicate('node-1', 1); // Hit
        
        final stats = tracker.stats;
        expect(stats['totalChecks'], equals(3));
        expect(stats['duplicateHits'], equals(2));
        expect(stats['hitRate'], closeTo(2/3, 0.01));
      });
    });
  });

  group('Chaos Testing', () {
    late InMemoryStorage storage;
    late InMemoryReplicationMetrics metrics;
    late ReplicationEventApplicatorImpl applicator;

    setUp(() async {
      final config = MerkleKVConfig(
        mqttHost: 'localhost',
        nodeId: 'test-node',
        clientId: 'test-client',
      );
      
      storage = InMemoryStorage(config);
      await storage.initialize();
      
      metrics = InMemoryReplicationMetrics();
      
      applicator = ReplicationEventApplicatorImpl(
        config: config,
        storage: storage,
        metrics: metrics,
      );
      
      await applicator.initialize();
    });

    tearDown(() async {
      await applicator.dispose();
      await storage.dispose();
    });

    test('handles random event ordering without corruption', () async {
      final random = Random(42); // Fixed seed for reproducibility
      final events = <ReplicationEvent>[];
      
      // Generate mix of events
      for (int i = 0; i < 100; i++) {
        final nodeId = 'node-${random.nextInt(5)}';
        final seq = random.nextInt(1000);
        final timestamp = 1000 + random.nextInt(5000);
        
        if (random.nextBool()) {
          events.add(ReplicationEvent.value(
            key: 'key-${random.nextInt(20)}',
            nodeId: nodeId,
            seq: seq,
            timestampMs: timestamp,
            value: 'value-$i',
          ));
        } else {
          events.add(ReplicationEvent.tombstone(
            key: 'key-${random.nextInt(20)}',
            nodeId: nodeId,
            seq: seq,
            timestampMs: timestamp,
          ));
        }
      }
      
      // Shuffle events
      events.shuffle(random);
      
      // Apply all events
      for (final event in events) {
        await applicator.applyEvent(event);
      }
      
      // Verify system integrity
      final totalProcessed = metrics.eventsApplied + 
                            metrics.eventsRejected + 
                            metrics.eventsDuplicate + 
                            metrics.conflictsResolved;
      expect(totalProcessed, equals(events.length));
      
      // Storage should be in valid state
      final allEntries = await storage.getAllEntries();
      expect(allEntries, isNotNull);
    });

    test('handles malformed events mixed with valid events', () async {
      final validEvents = [
        ReplicationEvent.value(
          key: 'valid1',
          nodeId: 'node-1',
          seq: 1,
          timestampMs: 1000,
          value: 'value1',
        ),
        ReplicationEvent.value(
          key: 'valid2',
          nodeId: 'node-1',
          seq: 2,
          timestampMs: 1001,
          value: 'value2',
        ),
      ];
      
      final malformedEvents = [
        ReplicationEvent(
          key: 'k' * 300, // Too long
          nodeId: 'node-1',
          seq: 3,
          timestampMs: 1002,
          tombstone: false,
          value: 'value',
        ),
        ReplicationEvent(
          key: 'key',
          nodeId: 'node-1',
          seq: 4,
          timestampMs: 0, // Invalid timestamp
          tombstone: false,
          value: 'value',
        ),
      ];
      
      // Mix valid and malformed events
      final allEvents = [...validEvents, ...malformedEvents];
      allEvents.shuffle();
      
      for (final event in allEvents) {
        await applicator.applyEvent(event);
      }
      
      // Valid events should be applied
      expect(metrics.eventsApplied, equals(2));
      expect(metrics.eventsRejected, equals(2));
      
      final stored1 = await storage.get('valid1');
      final stored2 = await storage.get('valid2');
      expect(stored1!.value, equals('value1'));
      expect(stored2!.value, equals('value2'));
    });
  });
}
