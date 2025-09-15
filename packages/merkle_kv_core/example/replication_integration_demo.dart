// ignore_for_file: avoid_print
import 'dart:async';
import 'package:merkle_kv_core/merkle_kv_core.dart';

/// Demonstrates the replication event applicator functionality
Future<void> main() async {
  print('=== MerkleKV Event Applicator Demo ===\n');

  // Configuration
  final config = MerkleKVConfig(
    mqttHost: 'localhost',
    mqttPort: 1883,
    nodeId: 'demo-node',
    clientId: 'demo-client',
    skewMaxFutureMs: 300000, // 5 minutes
  );

  // Initialize storage and metrics
  final storage = InMemoryStorage(config);
  await storage.initialize();
  
  final metrics = InMemoryReplicationMetrics();

  // Initialize event applicator
  final applicator = ReplicationEventApplicatorImpl(
    config: config,
    storage: storage,
    metrics: metrics,
  );

  try {
    await applicator.initialize();
    
    print('✅ Event applicator initialized');
    print('Node ID: ${config.nodeId}');
    print('Max future skew: ${config.skewMaxFutureMs}ms\n');

    // Simulate receiving events from other nodes
    print('📥 Applying events from remote nodes...\n');
    
    // Event from node-1
    final event1 = ReplicationEvent.value(
      key: 'user:alice',
      nodeId: 'node-1',
      seq: 100,
      timestampMs: DateTime.now().millisecondsSinceEpoch - 1000,
      value: 'Alice Johnson',
    );
    
    await applicator.applyEvent(event1);
    print('Applied: ${event1.key} = ${event1.value} (from ${event1.nodeId}:${event1.seq})');
    
    // Conflicting event from node-2 (older timestamp - should be rejected)
    final event2 = ReplicationEvent.value(
      key: 'user:alice',
      nodeId: 'node-2', 
      seq: 200,
      timestampMs: DateTime.now().millisecondsSinceEpoch - 2000, // Older
      value: 'Alice Smith',
    );
    
    await applicator.applyEvent(event2);
    print('Applied: ${event2.key} = ${event2.value} (from ${event2.nodeId}:${event2.seq}) - LWW conflict');
    
    // Duplicate event (should be ignored)
    await applicator.applyEvent(event1);
    print('Duplicate: ${event1.key} (from ${event1.nodeId}:${event1.seq}) - ignored');
    
    // Tombstone event
    final tombstone = ReplicationEvent.tombstone(
      key: 'user:bob',
      nodeId: 'node-3',
      seq: 150,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
    
    await applicator.applyEvent(tombstone);
    print('Applied: tombstone for ${tombstone.key} (from ${tombstone.nodeId}:${tombstone.seq})');

    // Apply some local entries first for demonstration
    print('\n📤 Creating local storage entries...\n');
    
    final charlieLocal = StorageEntry(
      key: 'user:charlie',
      value: 'Charlie Brown',
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      nodeId: config.nodeId,
      seq: 1,
      isTombstone: false,
    );
    await storage.put('user:charlie', charlieLocal);
    print('Local: put user:charlie = Charlie Brown');
    
    final themeLocal = StorageEntry(
      key: 'config:theme',
      value: 'dark',
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      nodeId: config.nodeId,
      seq: 2,
      isTombstone: false,
    );
    await storage.put('config:theme', themeLocal);
    print('Local: put config:theme = dark');

    // Wait a moment for events to be processed
    await Future.delayed(Duration(milliseconds: 100));

    // Show final state
    print('\n📊 Final Storage State:');
    final aliceEntry = await storage.get('user:alice');
    final charlieEntry = await storage.get('user:charlie');
    final themeEntry = await storage.get('config:theme');
    final bobEntry = await storage.get('user:bob');
    
    print('user:alice = ${aliceEntry?.value ?? 'null'} (ts: ${aliceEntry?.timestampMs})');
    print('user:charlie = ${charlieEntry?.value ?? 'null'} (ts: ${charlieEntry?.timestampMs})');
    print('config:theme = ${themeEntry?.value ?? 'null'} (ts: ${themeEntry?.timestampMs})');
    print('user:bob = ${bobEntry?.value ?? 'null'} (tombstone: ${bobEntry?.isTombstone ?? false})');

    // Show metrics
    print('\n📈 Replication Metrics:');
    print('Events applied: ${metrics.eventsApplied}');
    print('Events rejected: ${metrics.eventsRejected}');
    print('Events duplicate: ${metrics.eventsDuplicate}');
    print('Conflicts resolved: ${metrics.conflictsResolved}');
    
    // Show deduplication stats
    final dedupStats = applicator.getDeduplicationStats();
    print('\n🔍 Deduplication Stats:');
    print('Total checks: ${dedupStats['totalChecks']}');
    print('Duplicate hits: ${dedupStats['duplicateHits']}');
    print('Active nodes: ${dedupStats['activeNodes']}');
    print('Window evictions: ${dedupStats['windowEvictions']}');
    print('TTL evictions: ${dedupStats['ttlEvictions']}');

    print('\n✅ Demo completed successfully!');

  } catch (e, stackTrace) {
    print('❌ Error during demo: $e');
    print('Stack trace: $stackTrace');
  } finally {
    // Clean up
    await applicator.dispose();
    await storage.dispose();
    print('\n🧹 Resources cleaned up');
  }
}
