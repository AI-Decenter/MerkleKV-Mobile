@Tags(['integration'])
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';

void main() {
  group('ReplicationEventPublisher Integration Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('merkle_kv_integration_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('Event generation from storage operations', () async {
      // Test that we can generate events from storage entries
      final entry = StorageEntry.value(
        key: 'user:123',
        value: 'John Doe',
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        nodeId: 'node-1',
        seq: 1,
      );

      final event = ReplicationEventPublisher.createEventFromEntry(entry);

      expect(event.key, equals('user:123'));
      expect(event.value, equals('John Doe'));
      expect(event.nodeId, equals('node-1'));
      expect(event.seq, equals(1));
      expect(event.tombstone, isFalse);

      // Verify CBOR serialization works
      final cborData = CborSerializer.encode(event);
      expect(cborData.length, greaterThan(0));

      final decodedEvent = CborSerializer.decode(cborData);
      expect(decodedEvent.key, equals(event.key));
      expect(decodedEvent.value, equals(event.value));
    });

    test('Event generation from tombstone operations', () async {
      final entry = StorageEntry.tombstone(
        key: 'deleted:456',
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        nodeId: 'node-1',
        seq: 2,
      );

      final event = ReplicationEventPublisher.createEventFromEntry(entry);

      expect(event.key, equals('deleted:456'));
      expect(event.value, isNull);
      expect(event.nodeId, equals('node-1'));
      expect(event.seq, equals(2));
      expect(event.tombstone, isTrue);

      // Verify CBOR serialization works for tombstones
      final cborData = CborSerializer.encode(event);
      expect(cborData.length, greaterThan(0));

      final decodedEvent = CborSerializer.decode(cborData);
      expect(decodedEvent.key, equals(event.key));
      expect(decodedEvent.value, isNull);
      expect(decodedEvent.tombstone, isTrue);
    });

    test('SequenceManager persistence across restarts', () async {
      final config = MerkleKVConfig(
        mqttHost: 'test.example.com',
        nodeId: 'test-node',
        clientId: 'test-client',
        storagePath: '${tempDir.path}/sequences',
        persistenceEnabled: true,
      );

      // First manager instance
      final manager1 = SequenceManager(config);
      await manager1.initialize();

      expect(manager1.currentSequence, equals(0));

      final seq1 = manager1.getNextSequence();
      final seq2 = manager1.getNextSequence();
      final seq3 = manager1.getNextSequence();

      expect(seq1, equals(1));
      expect(seq2, equals(2));
      expect(seq3, equals(3));

      await manager1.dispose();

      // Second manager instance (simulates restart)
      final manager2 = SequenceManager(config);
      await manager2.initialize();

      expect(manager2.currentSequence, equals(3));

      final seq4 = manager2.getNextSequence();
      expect(seq4, equals(4));

      await manager2.dispose();
    });

    test('OutboxQueue persistence and ordering', () async {
      final config = MerkleKVConfig(
        mqttHost: 'test.example.com',
        nodeId: 'test-node',
        clientId: 'test-client',
        storagePath: '${tempDir.path}/outbox',
        persistenceEnabled: true,
      );

      // First queue instance
      final queue1 = OutboxQueue(config);
      await queue1.initialize();

      // Add events in sequence
      final events = <ReplicationEvent>[];
      for (var i = 1; i <= 5; i++) {
        final event = ReplicationEvent.value(
          key: 'key$i',
          nodeId: 'test-node',
          seq: i,
          timestampMs: DateTime.now().millisecondsSinceEpoch + i,
          value: 'value$i',
        );
        events.add(event);
        await queue1.enqueue(event);
      }

      expect(await queue1.size(), equals(5));
      await queue1.dispose();

      // Second queue instance (simulates restart)
      final queue2 = OutboxQueue(config);
      await queue2.initialize();

      expect(await queue2.size(), equals(5));

      final recoveredEvents = await queue2.drainAll();
      expect(recoveredEvents, hasLength(5));

      // Verify order is preserved
      for (var i = 0; i < 5; i++) {
        expect(recoveredEvents[i].key, equals('key${i + 1}'));
        expect(recoveredEvents[i].seq, equals(i + 1));
      }

      await queue2.dispose();
    });

    test('Topic scheme generates correct replication topic', () {
      final scheme = TopicScheme.create('production/cluster-a', 'device-123');

      expect(scheme.commandTopic, equals('production/cluster-a/device-123/cmd'));
      expect(scheme.responseTopic, equals('production/cluster-a/device-123/res'));
      expect(scheme.replicationTopic, equals('production/cluster-a/replication/events'));
    });

    test('Event size validation prevents oversized events', () {
      // Create an event with large value that would exceed CBOR limits
      final largeValue = 'x' * (400 * 1024); // 400KB value

      final event = ReplicationEvent.value(
        key: 'large-key',
        nodeId: 'test-node',
        seq: 1,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        value: largeValue,
      );

      // Should throw CborPayloadTooLargeException when trying to encode
      expect(
        () => CborSerializer.encode(event),
        throwsA(isA<CborPayloadTooLargeException>()),
      );
    });

    test('Base64 encoding for MQTT payload', () {
      final event = ReplicationEvent.value(
        key: 'test-key',
        nodeId: 'test-node',
        seq: 1,
        timestampMs: 1640995200000,
        value: 'test-value',
      );

      final cborData = CborSerializer.encode(event);
      final base64Payload = base64Encode(cborData);

      // Verify it's valid base64
      expect(base64Payload.length, greaterThan(0));
      expect(() => base64Decode(base64Payload), returnsNormally);

      // Verify roundtrip
      final decodedCbor = base64Decode(base64Payload);
      final decodedEvent = CborSerializer.decode(Uint8List.fromList(decodedCbor));
      
      expect(decodedEvent.key, equals(event.key));
      expect(decodedEvent.value, equals(event.value));
      expect(decodedEvent.nodeId, equals(event.nodeId));
      expect(decodedEvent.seq, equals(event.seq));
    });
  });
}
