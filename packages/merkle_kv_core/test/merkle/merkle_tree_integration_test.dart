@Tags(['integration'])
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';

void main() {
  group('Merkle Tree Storage Integration', () {
    late InMemoryStorage storage;
    late InMemoryReplicationMetrics metrics;
    late MerkleTreeImpl merkleTree;
    
    setUp(() async {
      final config = MerkleKVConfig.defaultConfig(
        host: 'localhost',
        clientId: 'test-client',
        nodeId: 'test-node',
      );
      storage = InMemoryStorage(config);
      await storage.initialize();
      metrics = InMemoryReplicationMetrics();
      merkleTree = MerkleTreeImpl(storage, metrics);
    });
    
    tearDown(() {
      merkleTree.dispose();
    });
    
    test('integration with storage notifications', () async {
      final rootHashChanges = <Uint8List>[];
      merkleTree.rootHashChanges.listen((hash) => rootHashChanges.add(hash));
      
      // Initial empty state - no change notification yet
      await merkleTree.getRootHash();
      expect(rootHashChanges.length, equals(0)); // No changes yet
      
      // Add first entry
      await storage.put('user:123', StorageEntry.value(
        key: 'user:123',
        value: '{"name": "Alice", "age": 30}',
        timestampMs: 1000,
        nodeId: 'node1',
        seq: 1,
      ));
      
      await merkleTree.rebuildFromStorage();
      expect(rootHashChanges.length, equals(1)); // First change from empty to non-empty
      
      // Add second entry
      await storage.put('user:456', StorageEntry.value(
        key: 'user:456',
        value: '{"name": "Bob", "age": 25}',
        timestampMs: 2000,
        nodeId: 'node2',
        seq: 1,
      ));
      
      await merkleTree.rebuildFromStorage();
      expect(rootHashChanges.length, equals(2)); // Two changes: empty->1 entry, 1->2 entries
      expect(merkleTree.leafCount, equals(2));
    });
    
    test('LWW conflict resolution integration', () async {
      // Add initial entry
      await storage.put('config:theme', StorageEntry.value(
        key: 'config:theme',
        value: 'dark',
        timestampMs: 1000,
        nodeId: 'node1',
        seq: 1,
      ));
      
      await merkleTree.rebuildFromStorage();
      final hash1 = await merkleTree.getRootHash();
      
      // Add conflicting entry with later timestamp (should win)
      await storage.put('config:theme', StorageEntry.value(
        key: 'config:theme',
        value: 'light',
        timestampMs: 2000,
        nodeId: 'node2',
        seq: 1,
      ));
      
      await merkleTree.rebuildFromStorage();
      final hash2 = await merkleTree.getRootHash();
      
      expect(hash2, isNot(equals(hash1)));
      expect(merkleTree.leafCount, equals(1)); // Still one entry, but updated
      
      // Verify the winning value is reflected in the hash
      final entry = await storage.get('config:theme');
      expect(entry!.value, equals('light'));
      expect(entry.timestampMs, equals(2000));
    });
    
    test('tombstone handling in tree construction', () async {
      // Add regular entries
      await storage.put('file:1', StorageEntry.value(
        key: 'file:1', value: 'content1', timestampMs: 1000, nodeId: 'node1', seq: 1,
      ));
      await storage.put('file:2', StorageEntry.value(
        key: 'file:2', value: 'content2', timestampMs: 1000, nodeId: 'node1', seq: 2,
      ));
      await storage.put('file:3', StorageEntry.value(
        key: 'file:3', value: 'content3', timestampMs: 1000, nodeId: 'node1', seq: 3,
      ));
      
      await merkleTree.rebuildFromStorage();
      final hashWithAllFiles = await merkleTree.getRootHash();
      expect(merkleTree.leafCount, equals(3));
      
      // Delete one file (create tombstone)
      await storage.delete('file:2', 2000, 'node1', 4);
      
      await merkleTree.rebuildFromStorage();
      final hashWithTombstone = await merkleTree.getRootHash();
      
      // Tree should still have 3 entries (including tombstone)
      expect(merkleTree.leafCount, equals(3));
      expect(hashWithTombstone, isNot(equals(hashWithAllFiles)));
      
      // Verify tombstone is included in tree construction
      final allEntries = await storage.getAllEntries();
      expect(allEntries.length, equals(3));
      expect(allEntries.where((e) => e.isTombstone).length, equals(1));
    });
    
    test('consistency across storage implementations', () async {
      // Test data that should produce identical hashes across different storage implementations
      final testData = [
        ('cache:user:123:profile', '{"id":123,"name":"John Doe","email":"john@example.com"}'),
        ('session:abc123', '{"userId":123,"expires":1699999999,"isAdmin":false}'),
        ('metrics:2023-11-15:pageviews', '{"count":1547,"unique":892}'),
        ('config:app:version', '2.1.0'),
        ('temp:upload:xyz789', 'binary_data_placeholder'),
      ];
      
      // Add data to first storage
      for (int i = 0; i < testData.length; i++) {
        final (key, value) = testData[i];
        await storage.put(key, StorageEntry.value(
          key: key,
          value: value,
          timestampMs: 1700000000 + i * 1000, // Predictable timestamps
          nodeId: 'integration-test-node',
          seq: i + 1,
        ));
      }
      
      await merkleTree.rebuildFromStorage();
      final hash1 = await merkleTree.getRootHash();
      
      // Create second storage with same data in different order
      final config2 = MerkleKVConfig.defaultConfig(
        host: 'localhost',
        clientId: 'test-client-2',
        nodeId: 'test-node-2',
      );
      final storage2 = InMemoryStorage(config2);
      await storage2.initialize();
      final merkleTree2 = MerkleTreeImpl(storage2, metrics);
      
      for (int i = testData.length - 1; i >= 0; i--) {
        final (key, value) = testData[i];
        await storage2.put(key, StorageEntry.value(
          key: key,
          value: value,
          timestampMs: 1700000000 + i * 1000,
          nodeId: 'integration-test-node',
          seq: i + 1,
        ));
      }
      
      await merkleTree2.rebuildFromStorage();
      final hash2 = await merkleTree2.getRootHash();
      
      expect(hash1, equals(hash2));
      expect(merkleTree.leafCount, equals(merkleTree2.leafCount));
      
      merkleTree2.dispose();
    });
    
    test('real-world data patterns', () async {
      // Simulate real-world MerkleKV usage patterns
      
      // User profiles
      await storage.put('user:alice', StorageEntry.value(
        key: 'user:alice',
        value: '{"name":"Alice Smith","email":"alice@example.com","role":"admin"}',
        timestampMs: 1700000000,
        nodeId: 'server1',
        seq: 1,
      ));
      
      // Configuration settings
      await storage.put('config:api_endpoint', StorageEntry.value(
        key: 'config:api_endpoint',
        value: 'https://api.example.com/v2',
        timestampMs: 1700000100,
        nodeId: 'server1',
        seq: 2,
      ));
      
      // Session data
      await storage.put('session:abc123', StorageEntry.value(
        key: 'session:abc123',
        value: '{"userId":"alice","expires":1700086400,"permissions":["read","write"]}',
        timestampMs: 1700000200,
        nodeId: 'server2',
        seq: 1,
      ));
      
      // Cache entries
      await storage.put('cache:weather:nyc', StorageEntry.value(
        key: 'cache:weather:nyc',
        value: '{"temp":22,"humidity":65,"conditions":"partly_cloudy"}',
        timestampMs: 1700000300,
        nodeId: 'server3',
        seq: 1,
      ));
      
      // Feature flags
      await storage.put('feature:new_ui', StorageEntry.value(
        key: 'feature:new_ui',
        value: 'true',
        timestampMs: 1700000400,
        nodeId: 'server1',
        seq: 3,
      ));
      
      await merkleTree.rebuildFromStorage();
      final initialHash = await merkleTree.getRootHash();
      expect(merkleTree.leafCount, equals(5));
      
      // Simulate user logout (delete session)
      await storage.delete('session:abc123', 1700001000, 'server2', 2);
      
      await merkleTree.rebuildFromStorage();
      final hashAfterLogout = await merkleTree.getRootHash();
      expect(hashAfterLogout, isNot(equals(initialHash)));
      expect(merkleTree.leafCount, equals(5)); // Still 5 entries (including tombstone)
      
      // Update configuration
      await storage.put('config:api_endpoint', StorageEntry.value(
        key: 'config:api_endpoint',
        value: 'https://api.example.com/v3',
        timestampMs: 1700002000,
        nodeId: 'server1',
        seq: 4,
      ));
      
      await merkleTree.rebuildFromStorage();
      final hashAfterConfigUpdate = await merkleTree.getRootHash();
      expect(hashAfterConfigUpdate, isNot(equals(hashAfterLogout)));
      
      // Verify final state
      expect(merkleTree.leafCount, equals(5));
      expect(merkleTree.depth, greaterThan(1));
    });
    
    test('anti-entropy synchronization scenario', () async {
      // Simulate two nodes with different data that need to sync
      
      // Node 1 data
      final config1 = MerkleKVConfig.defaultConfig(
        host: 'localhost',
        clientId: 'node1-client',
        nodeId: 'node1',
      );
      final node1Storage = InMemoryStorage(config1);
      await node1Storage.initialize();
      final node1Tree = MerkleTreeImpl(node1Storage, metrics);
      
      await node1Storage.put('shared:doc1', StorageEntry.value(
        key: 'shared:doc1', value: 'content_from_node1', timestampMs: 1000, nodeId: 'node1', seq: 1,
      ));
      await node1Storage.put('node1:private', StorageEntry.value(
        key: 'node1:private', value: 'private_data', timestampMs: 1100, nodeId: 'node1', seq: 2,
      ));
      
      await node1Tree.rebuildFromStorage();
      final node1Hash = await node1Tree.getRootHash();
      
      // Node 2 data
      final config2 = MerkleKVConfig.defaultConfig(
        host: 'localhost',
        clientId: 'node2-client',
        nodeId: 'node2',
      );
      final node2Storage = InMemoryStorage(config2);
      await node2Storage.initialize();
      final node2Tree = MerkleTreeImpl(node2Storage, metrics);
      
      await node2Storage.put('shared:doc1', StorageEntry.value(
        key: 'shared:doc1', value: 'content_from_node2', timestampMs: 2000, nodeId: 'node2', seq: 1,
      ));
      await node2Storage.put('node2:private', StorageEntry.value(
        key: 'node2:private', value: 'other_private_data', timestampMs: 1200, nodeId: 'node2', seq: 2,
      ));
      
      await node2Tree.rebuildFromStorage();
      final node2Hash = await node2Tree.getRootHash();
      
      // Hashes should be different due to different content
      expect(node1Hash, isNot(equals(node2Hash)));
      
      // Simulate sync: apply node2's updates to node1
      final node2Entries = await node2Storage.getAllEntries();
      for (final entry in node2Entries) {
        await node1Storage.put(entry.key, entry);
      }
      
      await node1Tree.rebuildFromStorage();
      final node1SyncedHash = await node1Tree.getRootHash();
      
      // After sync, apply node1's data to node2
      final node1Entries = await node1Storage.getAllEntries();
      for (final entry in node1Entries) {
        await node2Storage.put(entry.key, entry);
      }
      
      await node2Tree.rebuildFromStorage();
      final node2SyncedHash = await node2Tree.getRootHash();
      
      // Both nodes should have identical hashes after sync
      expect(node1SyncedHash, equals(node2SyncedHash));
      
      // Verify both nodes have all data
      expect(node1Tree.leafCount, equals(node2Tree.leafCount));
      expect(node1Tree.leafCount, equals(3)); // shared:doc1, node1:private, node2:private
      
      node1Tree.dispose();
      node2Tree.dispose();
    });
    
    test('metrics integration with real operations', () async {
      metrics.reset();
      
      // Perform series of operations
      await storage.put('test1', StorageEntry.value(
        key: 'test1', value: 'value1', timestampMs: 1000, nodeId: 'node1', seq: 1,
      ));
      await merkleTree.rebuildFromStorage();
      
      await storage.put('test2', StorageEntry.value(
        key: 'test2', value: 'value2', timestampMs: 2000, nodeId: 'node1', seq: 2,
      ));
      await merkleTree.rebuildFromStorage();
      
      await storage.delete('test1', 3000, 'node1', 3);
      await merkleTree.rebuildFromStorage();
      
      // Verify metrics were tracked
      expect(metrics.merkleTreeLeafCount, equals(2)); // 1 regular + 1 tombstone
      expect(metrics.merkleTreeDepth, greaterThan(0));
      expect(metrics.merkleRootHashChanges, greaterThanOrEqualTo(3));
      expect(metrics.merkleHashComputations, greaterThan(0));
      expect(metrics.merkleTreeBuildDurations.isNotEmpty, isTrue);
      
      // All build durations should be at least 1µs (clamped)
      for (final duration in metrics.merkleTreeBuildDurations) {
        expect(duration, greaterThanOrEqualTo(1));
      }
      
      print('Integration test metrics:');
      print('  Leaf count: ${metrics.merkleTreeLeafCount}');
      print('  Tree depth: ${metrics.merkleTreeDepth}');
      print('  Root hash changes: ${metrics.merkleRootHashChanges}');
      print('  Hash computations: ${metrics.merkleHashComputations}');
      print('  Build durations: ${metrics.merkleTreeBuildDurations}');
    });
  });
}
