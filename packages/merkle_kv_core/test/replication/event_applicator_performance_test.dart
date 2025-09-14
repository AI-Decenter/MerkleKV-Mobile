import 'dart:math';
import 'package:test/test.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';

void main() {
  group('ReplicationEventApplicator Performance Tests', () {
    late InMemoryStorage storage;
    late InMemoryReplicationMetrics metrics;
    late ReplicationEventApplicatorImpl applicator;
    late MerkleKVConfig config;

    setUp(() async {
      config = MerkleKVConfig(
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

    group('Throughput Tests', () {
      test('processes high volume of events efficiently', () async {
        const eventCount = 10000;
        final stopwatch = Stopwatch()..start();
        
        for (int i = 0; i < eventCount; i++) {
          final event = ReplicationEvent.value(
            key: 'key-${i % 1000}', // Reuse keys to test conflicts
            nodeId: 'node-${i % 10}', // Multiple nodes
            seq: i,
            timestampMs: 1000 + i,
            value: 'value-$i',
          );
          
          await applicator.applyEvent(event);
        }
        
        stopwatch.stop();
        final throughput = eventCount / (stopwatch.elapsedMilliseconds / 1000);
        
        print('Applied $eventCount events in ${stopwatch.elapsedMilliseconds}ms');
        print('Throughput: ${throughput.toStringAsFixed(1)} events/second');
        
        // Verify reasonable throughput (should be > 1000 events/second)
        expect(throughput, greaterThan(1000));
        
        // Verify all events were processed
        final totalProcessed = metrics.eventsApplied + 
                              metrics.eventsRejected + 
                              metrics.eventsDuplicate;
        expect(totalProcessed, equals(eventCount));
      });

      test('maintains O(1) deduplication performance', () async {
        const warmupEvents = 1000;
        const testEvents = 1000;
        
        // Warmup phase
        for (int i = 0; i < warmupEvents; i++) {
          final event = ReplicationEvent.value(
            key: 'warmup-$i',
            nodeId: 'node-1',
            seq: i,
            timestampMs: 1000 + i,
            value: 'value-$i',
          );
          await applicator.applyEvent(event);
        }
        
        // Test phase - measure time for duplicate checks
        final stopwatch = Stopwatch()..start();
        
        for (int i = 0; i < testEvents; i++) {
          // Submit duplicates to test deduplication performance
          final event = ReplicationEvent.value(
            key: 'warmup-${i % warmupEvents}',
            nodeId: 'node-1',
            seq: i % warmupEvents,
            timestampMs: 1000 + (i % warmupEvents),
            value: 'value-${i % warmupEvents}',
          );
          await applicator.applyEvent(event);
        }
        
        stopwatch.stop();
        final duplicateCheckThroughput = testEvents / (stopwatch.elapsedMilliseconds / 1000);
        
        print('Duplicate check throughput: ${duplicateCheckThroughput.toStringAsFixed(1)} checks/second');
        
        // Should be very fast for duplicates (O(1) lookups)
        expect(duplicateCheckThroughput, greaterThan(5000));
        expect(metrics.eventsDuplicate, equals(testEvents));
      });
    });

    group('Memory Usage Tests', () {
      test('bounds memory usage under sustained load', () async {
        final tracker = DeduplicationTracker(
          windowSize: 1000,
          ttl: Duration(milliseconds: 100),
          maxNodes: 50,
        );
        
        final testApplicator = ReplicationEventApplicatorImpl(
          config: config,
          storage: storage,
          metrics: metrics,
          deduplicationTracker: tracker,
        );
        await testApplicator.initialize();
        
        const cycleCount = 10;
        const eventsPerCycle = 5000;
        
        for (int cycle = 0; cycle < cycleCount; cycle++) {
          // Generate events for many different nodes
          for (int i = 0; i < eventsPerCycle; i++) {
            final event = ReplicationEvent.value(
              key: 'key-$i',
              nodeId: 'node-${i % 100}', // 100 different nodes
              seq: cycle * eventsPerCycle + i,
              timestampMs: 1000 + cycle * eventsPerCycle + i,
              value: 'value-$i',
            );
            await testApplicator.applyEvent(event);
          }
          
          // Check memory bounds
          final stats = tracker.stats;
          expect(stats['activeNodes'], lessThanOrEqualTo(50)); // Max nodes enforced
          
          // Wait for some TTL cleanup
          if (cycle % 3 == 0) {
            await Future.delayed(Duration(milliseconds: 150));
          }
        }
        
        final finalStats = tracker.stats;
        print('Final deduplication stats: $finalStats');
        
        // Memory should be bounded
        expect(finalStats['activeNodes'], lessThanOrEqualTo(50));
        expect(finalStats['ttlEvictions'], greaterThan(0));
        
        await testApplicator.dispose();
      });

      test('handles large CBOR payloads efficiently', () async {
        const payloadCount = 1000;
        final stopwatch = Stopwatch()..start();
        
        for (int i = 0; i < payloadCount; i++) {
          final event = ReplicationEvent.value(
            key: 'large-key-$i',
            nodeId: 'node-1',
            seq: i,
            timestampMs: 1000 + i,
            value: 'x' * (50 * 1024), // 50KB value (large but under limit)
          );
          
          final cborData = CborSerializer.encode(event);
          await applicator.applyCborEvent(cborData);
        }
        
        stopwatch.stop();
        final throughput = payloadCount / (stopwatch.elapsedMilliseconds / 1000);
        
        print('Large CBOR throughput: ${throughput.toStringAsFixed(1)} payloads/second');
        
        // Should handle large payloads reasonably well
        expect(throughput, greaterThan(100));
        expect(metrics.eventsApplied, equals(payloadCount));
      });
    });

    group('Latency Tests', () {
      test('maintains low latency under concurrent load', () async {
        const eventCount = 1000;
        final latencies = <Duration>[];
        
        for (int i = 0; i < eventCount; i++) {
          final start = DateTime.now();
          
          final event = ReplicationEvent.value(
            key: 'latency-test-$i',
            nodeId: 'node-1',
            seq: i,
            timestampMs: 1000 + i,
            value: 'value-$i',
          );
          
          await applicator.applyEvent(event);
          
          final latency = DateTime.now().difference(start);
          latencies.add(latency);
        }
        
        // Calculate latency statistics
        latencies.sort((a, b) => a.compareTo(b));
        final p50 = latencies[eventCount ~/ 2];
        final p95 = latencies[(eventCount * 0.95).round()];
        final p99 = latencies[(eventCount * 0.99).round()];
        
        print('Latency P50: ${p50.inMicroseconds}μs');
        print('Latency P95: ${p95.inMicroseconds}μs');
        print('Latency P99: ${p99.inMicroseconds}μs');
        
        // Latency requirements (these are aggressive but achievable for in-memory)
        expect(p50.inMicroseconds, lessThan(1000)); // < 1ms for P50
        expect(p95.inMicroseconds, lessThan(5000)); // < 5ms for P95
        expect(p99.inMicroseconds, lessThan(10000)); // < 10ms for P99
      });
    });

    group('Conflict Resolution Performance', () {
      test('handles high conflict scenarios efficiently', () async {
        const conflictingKey = 'hotspot-key';
        const eventCount = 5000;
        final random = Random(42);
        
        final stopwatch = Stopwatch()..start();
        
        // Generate many events for the same key from different nodes/timestamps
        for (int i = 0; i < eventCount; i++) {
          final event = ReplicationEvent.value(
            key: conflictingKey,
            nodeId: 'node-${random.nextInt(10)}',
            seq: i,
            timestampMs: 1000 + random.nextInt(1000), // Random timestamps for conflicts
            value: 'value-$i',
          );
          
          await applicator.applyEvent(event);
        }
        
        stopwatch.stop();
        final throughput = eventCount / (stopwatch.elapsedMilliseconds / 1000);
        
        print('Conflict resolution throughput: ${throughput.toStringAsFixed(1)} events/second');
        print('Applied: ${metrics.eventsApplied}, Rejected: ${metrics.eventsRejected}');
        print('Duplicates: ${metrics.eventsDuplicate}, Conflicts: ${metrics.conflictsResolved}');
        
        // Should handle conflicts efficiently
        expect(throughput, greaterThan(2000));
        
        // Verify final state is consistent (only one value for the key)
        final finalEntry = await storage.get(conflictingKey);
        expect(finalEntry, isNotNull);
        
        // Total events should be accounted for
        final totalProcessed = metrics.eventsApplied + 
                              metrics.eventsRejected + 
                              metrics.eventsDuplicate + 
                              metrics.conflictsResolved;
        expect(totalProcessed, equals(eventCount));
      });
    });

    group('Sliding Window Performance', () {
      test('maintains performance as window slides', () async {
        final tracker = DeduplicationTracker(
          windowSize: 100, // Small window to force sliding
          maxNodes: 10,
        );
        
        final testApplicator = ReplicationEventApplicatorImpl(
          config: config,
          storage: storage,
          metrics: metrics,
          deduplicationTracker: tracker,
        );
        await testApplicator.initialize();
        
        const slidingEvents = 1000;
        final stopwatch = Stopwatch()..start();
        
        // Generate events that will cause window sliding
        for (int i = 0; i < slidingEvents; i++) {
          final event = ReplicationEvent.value(
            key: 'sliding-$i',
            nodeId: 'node-1',
            seq: i,
            timestampMs: 1000 + i,
            value: 'value-$i',
          );
          
          await testApplicator.applyEvent(event);
        }
        
        stopwatch.stop();
        final throughput = slidingEvents / (stopwatch.elapsedMilliseconds / 1000);
        
        print('Sliding window throughput: ${throughput.toStringAsFixed(1)} events/second');
        
        final stats = tracker.stats;
        print('Window evictions: ${stats['windowEvictions']}');
        
        // Should maintain good performance even with sliding
        expect(throughput, greaterThan(3000));
        expect(stats['windowEvictions'], greaterThan(0)); // Window should have slid
        
        await testApplicator.dispose();
      });
    });

    group('Stress Tests', () {
      test('survives sustained high-rate mixed workload', () async {
        const duration = Duration(seconds: 5);
        const batchSize = 100;
        final random = Random(42);
        
        final stopwatch = Stopwatch()..start();
        int totalEvents = 0;
        
        while (stopwatch.elapsed < duration) {
          final batch = <Future<void>>[];
          
          for (int i = 0; i < batchSize; i++) {
            final eventType = random.nextInt(3);
            final nodeId = 'node-${random.nextInt(5)}';
            final seq = totalEvents + i;
            final timestamp = 1000 + totalEvents + i;
            
            Future<void> eventFuture;
            
            switch (eventType) {
              case 0: // Value event
                final event = ReplicationEvent.value(
                  key: 'stress-key-${random.nextInt(100)}',
                  nodeId: nodeId,
                  seq: seq,
                  timestampMs: timestamp,
                  value: 'value-$seq',
                );
                eventFuture = applicator.applyEvent(event);
                break;
                
              case 1: // Tombstone event
                final event = ReplicationEvent.tombstone(
                  key: 'stress-key-${random.nextInt(100)}',
                  nodeId: nodeId,
                  seq: seq,
                  timestampMs: timestamp,
                );
                eventFuture = applicator.applyEvent(event);
                break;
                
              case 2: // CBOR event
                final event = ReplicationEvent.value(
                  key: 'cbor-key-${random.nextInt(100)}',
                  nodeId: nodeId,
                  seq: seq,
                  timestampMs: timestamp,
                  value: 'cbor-value-$seq',
                );
                final cborData = CborSerializer.encode(event);
                eventFuture = applicator.applyCborEvent(cborData);
                break;
                
              default:
                throw StateError('Unexpected event type');
            }
            
            batch.add(eventFuture);
          }
          
          // Wait for batch to complete
          await Future.wait(batch);
          totalEvents += batchSize;
        }
        
        stopwatch.stop();
        final throughput = totalEvents / (stopwatch.elapsedMilliseconds / 1000.0);
        
        print('Stress test completed:');
        print('  Duration: ${stopwatch.elapsedMilliseconds}ms');
        print('  Total events: $totalEvents');
        print('  Throughput: ${throughput.toStringAsFixed(1)} events/second');
        print('  Applied: ${metrics.eventsApplied}');
        print('  Rejected: ${metrics.eventsRejected}');
        print('  Duplicates: ${metrics.eventsDuplicate}');
        
        // Should maintain reasonable throughput under stress
        expect(throughput, greaterThan(1000));
        
        // System should remain functional
        final totalProcessed = metrics.eventsApplied + 
                              metrics.eventsRejected + 
                              metrics.eventsDuplicate + 
                              metrics.conflictsResolved;
        expect(totalProcessed, equals(totalEvents));
      });
    });
  });
}
