import 'dart:io';
import 'package:merkle_kv_core/merkle_kv_core.dart';

/// Example demonstrating replication event publishing
void main() async {
  // Configuration
  final config = MerkleKVConfig(
    mqttHost: 'broker.example.com',
    nodeId: 'node-1',
    clientId: 'client-1',
    topicPrefix: 'production/cluster-a',
  );

  print('Using configuration for node: ${config.nodeId}');

  // Topic scheme for replication
  final topicScheme = TopicScheme.create('production/cluster-a', 'client-1');
  print('Replication topic: ${topicScheme.replicationTopic}');

  // Example storage entry (would come from successful SET operation)
  final entry = StorageEntry.value(
    key: 'user:123',
    value: 'John Doe',
    timestampMs: DateTime.now().millisecondsSinceEpoch,
    nodeId: 'node-1',
    seq: 1,
  );

  // Generate replication event from storage entry
  final event = ReplicationEventPublisher.createEventFromEntry(entry);
  print('Generated event: ${event.toString()}');

  // Serialize event to CBOR (ready for MQTT)
  final cborData = CborSerializer.encode(event);
  print('CBOR size: ${cborData.length} bytes');

  // Example tombstone entry
  final tombstoneEntry = StorageEntry.tombstone(
    key: 'deleted:456',
    timestampMs: DateTime.now().millisecondsSinceEpoch,
    nodeId: 'node-1',
    seq: 2,
  );

  final tombstoneEvent = ReplicationEventPublisher.createEventFromEntry(tombstoneEntry);
  print('Tombstone event: ${tombstoneEvent.toString()}');

  // Demonstrate sequence management
  print('\n--- Sequence Management ---');
  final tempDir = await Directory.systemTemp.createTemp('example_');
  
  final configWithPersistence = MerkleKVConfig(
    mqttHost: 'broker.example.com',
    nodeId: 'node-1',
    clientId: 'client-1',
    storagePath: '${tempDir.path}/example',
    persistenceEnabled: true,
  );

  final sequenceManager = SequenceManager(configWithPersistence);
  await sequenceManager.initialize();

  print('Initial sequence: ${sequenceManager.currentSequence}');
  
  for (var i = 0; i < 5; i++) {
    final seq = sequenceManager.getNextSequence();
    print('Generated sequence: $seq');
  }

  await sequenceManager.dispose();
  await tempDir.delete(recursive: true);

  print('\nReplication event publishing system ready!');
}
