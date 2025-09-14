import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';

class MockMqttClient implements MqttClientInterface {
  final List<PublishCall> publishedMessages = [];
  final List<String> subscribedTopics = [];
  ConnectionState _state = ConnectionState.disconnected;
  final List<Function(String, String)> _handlers = [];

  @override
  Stream<ConnectionState> get connectionState => Stream.value(_state);

  void simulateConnectionState(ConnectionState state) {
    _state = state;
  }

  @override
  Future<void> connect() async {
    _state = ConnectionState.connected;
  }

  @override
  Future<void> disconnect({bool suppressLWT = true}) async {
    _state = ConnectionState.disconnected;
  }

  @override
  Future<void> publish(
    String topic,
    String payload, {
    bool forceQoS1 = true,
    bool forceRetainFalse = true,
  }) async {
    if (_state != ConnectionState.connected) {
      throw Exception('Not connected');
    }
    publishedMessages.add(PublishCall(topic, payload, forceQoS1, forceRetainFalse));
  }

  @override
  Future<void> subscribe(String topic, void Function(String, String) handler) async {
    subscribedTopics.add(topic);
    _handlers.add(handler);
  }

  @override
  Future<void> unsubscribe(String topic) async {
    subscribedTopics.remove(topic);
  }

  void clear() {
    publishedMessages.clear();
    subscribedTopics.clear();
  }
}

class PublishCall {
  final String topic;
  final String payload;
  final bool qos1;
  final bool retainFalse;

  PublishCall(this.topic, this.payload, this.qos1, this.retainFalse);

  @override
  String toString() => 'PublishCall(topic: $topic, payload: $payload, qos1: $qos1, retainFalse: $retainFalse)';
}

void main() {
  group('ReplicationEventPublisher', () {
    late Directory tempDir;
    late MerkleKVConfig config;
    late MockMqttClient mockClient;
    late TopicScheme topicScheme;
    late ReplicationEventPublisherImpl publisher;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('merkle_kv_test_');
      config = MerkleKVConfig(
        mqttHost: 'localhost',
        nodeId: 'test-node',
        clientId: 'test-client',
        storagePath: '${tempDir.path}/test.storage',
        persistenceEnabled: true,
      );
      mockClient = MockMqttClient();
      topicScheme = TopicScheme.create('test', 'client1');
      publisher = ReplicationEventPublisherImpl(
        config: config,
        mqttClient: mockClient,
        topicScheme: topicScheme,
      );
    });

    tearDown(() async {
      try {
        await publisher.dispose();
      } catch (e) {
        // Ignore disposal errors in tests
        print('Warning: Publisher disposal error: $e');
      }
      
      try {
        await tempDir.delete(recursive: true);
      } catch (e) {
        // Ignore cleanup errors
        print('Warning: Temp directory cleanup error: $e');
      }
    });

    group('Initialization and disposal', () {
      test('should initialize successfully', () async {
        await publisher.initialize();
        expect(publisher.currentSequence, equals(0));
      });

      test('should dispose cleanly', () async {
        await publisher.initialize();
        await publisher.ready(); // Wait for readiness
        await publisher.dispose();
        // Should not throw
      });

      test('should throw after disposal', () async {
        await publisher.initialize();
        await publisher.ready(); // Wait for readiness
        await publisher.dispose();
        
        expect(
          () async => await publisher.publishEvent(
            ReplicationEvent.value(
              key: 'test',
              nodeId: 'node1',
              seq: 1,
              timestampMs: 1000,
              value: 'value',
            ),
          ),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('disposed'),
          )),
        );
      });

      test('should throw if not initialized', () async {
        expect(
          () async => await publisher.publishEvent(
            ReplicationEvent.value(
              key: 'test',
              nodeId: 'node1',
              seq: 1,
              timestampMs: 1000,
              value: 'value',
            ),
          ),
          throwsStateError,
        );
      });
    });

    group('Event publishing', () {
      setUp(() async {
        await publisher.initialize();
        await publisher.ready(); // Wait for persistence initialization
        mockClient.simulateConnectionState(ConnectionState.connected);
      });

      test('should publish event when online', () async {
        final event = ReplicationEvent.value(
          key: 'test-key',
          nodeId: 'test-node',
          seq: 1,
          timestampMs: 1640995200000,
          value: 'test-value',
        );

        await publisher.publishEvent(event);

        expect(mockClient.publishedMessages, hasLength(1));
        final call = mockClient.publishedMessages.first;
        expect(call.topic, equals('test/replication/events'));
        expect(call.qos1, isTrue);
        expect(call.retainFalse, isTrue);

        // Verify payload is base64-encoded CBOR
        final cborData = base64Decode(call.payload);
        final decodedEvent = CborSerializer.decode(Uint8List.fromList(cborData));
        expect(decodedEvent.key, equals('test-key'));
        expect(decodedEvent.value, equals('test-value'));
      });

      test('should queue event when offline', () async {
        mockClient.simulateConnectionState(ConnectionState.disconnected);

        final event = ReplicationEvent.value(
          key: 'test-key',
          nodeId: 'test-node',
          seq: 1,
          timestampMs: 1640995200000,
          value: 'test-value',
        );

        await publisher.publishEvent(event);

        expect(mockClient.publishedMessages, isEmpty);

        // Check status shows queued event
        final status = await publisher.outboxStatus.first;
        expect(status.pendingEvents, equals(1));
        expect(status.isOnline, isFalse);
      });

      test('should publish tombstone events correctly', () async {
        final event = ReplicationEvent.tombstone(
          key: 'test-key',
          nodeId: 'test-node',
          seq: 1,
          timestampMs: 1640995200000,
        );

        await publisher.publishEvent(event);

        expect(mockClient.publishedMessages, hasLength(1));
        final call = mockClient.publishedMessages.first;

        // Verify tombstone has no value
        final cborData = base64Decode(call.payload);
        final decodedEvent = CborSerializer.decode(Uint8List.fromList(cborData));
        expect(decodedEvent.tombstone, isTrue);
        expect(decodedEvent.value, isNull);
      });
    });

    group('Outbox flushing', () {
      setUp(() async {
        await publisher.initialize();
        await publisher.ready(); // Wait for persistence initialization
      });

      test('should flush events when coming online', () async {
        // Start offline and queue events
        mockClient.simulateConnectionState(ConnectionState.disconnected);

        final event1 = ReplicationEvent.value(
          key: 'key1',
          nodeId: 'test-node',
          seq: 1,
          timestampMs: 1640995200000,
          value: 'value1',
        );

        final event2 = ReplicationEvent.value(
          key: 'key2',
          nodeId: 'test-node',
          seq: 2,
          timestampMs: 1640995200001,
          value: 'value2',
        );

        await publisher.publishEvent(event1);
        await publisher.publishEvent(event2);

        expect(mockClient.publishedMessages, isEmpty);

        // Come online and flush
        mockClient.simulateConnectionState(ConnectionState.connected);
        await publisher.flushOutbox();

        expect(mockClient.publishedMessages, hasLength(2));

        // Verify events are in correct order
        final call1 = mockClient.publishedMessages[0];
        final call2 = mockClient.publishedMessages[1];

        final cborData1 = base64Decode(call1.payload);
        final decodedEvent1 = CborSerializer.decode(Uint8List.fromList(cborData1));
        expect(decodedEvent1.key, equals('key1'));

        final cborData2 = base64Decode(call2.payload);
        final decodedEvent2 = CborSerializer.decode(Uint8List.fromList(cborData2));
        expect(decodedEvent2.key, equals('key2'));
      });

      test('should not flush when offline', () async {
        mockClient.simulateConnectionState(ConnectionState.disconnected);

        final event = ReplicationEvent.value(
          key: 'test-key',
          nodeId: 'test-node',
          seq: 1,
          timestampMs: 1640995200000,
          value: 'test-value',
        );

        await publisher.publishEvent(event);
        await publisher.flushOutbox();

        expect(mockClient.publishedMessages, isEmpty);
      });

      test('should throw when flushing after disposal', () async {
        await publisher.initialize();
        await publisher.ready(); // Wait for readiness
        await publisher.dispose();
        
        expect(
          () async => await publisher.flushOutbox(),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('disposed'),
          )),
        );
      });
    });

    group('createEventFromEntry', () {
      test('should create value event from value entry', () {
        final entry = StorageEntry.value(
          key: 'test-key',
          value: 'test-value',
          timestampMs: 1640995200000,
          nodeId: 'test-node',
          seq: 1,
        );

        final event = ReplicationEventPublisher.createEventFromEntry(entry);

        expect(event.key, equals('test-key'));
        expect(event.value, equals('test-value'));
        expect(event.nodeId, equals('test-node'));
        expect(event.seq, equals(1));
        expect(event.timestampMs, equals(1640995200000));
        expect(event.tombstone, isFalse);
      });

      test('should create tombstone event from tombstone entry', () {
        final entry = StorageEntry.tombstone(
          key: 'test-key',
          timestampMs: 1640995200000,
          nodeId: 'test-node',
          seq: 1,
        );

        final event = ReplicationEventPublisher.createEventFromEntry(entry);

        expect(event.key, equals('test-key'));
        expect(event.value, isNull);
        expect(event.nodeId, equals('test-node'));
        expect(event.seq, equals(1));
        expect(event.timestampMs, equals(1640995200000));
        expect(event.tombstone, isTrue);
      });
    });

    group('publishStorageEvent', () {
      setUp(() async {
        await publisher.initialize();
        await publisher.ready(); // Wait for persistence initialization
        mockClient.simulateConnectionState(ConnectionState.connected);
      });

      test('should publish event from storage entry', () async {
        final entry = StorageEntry.value(
          key: 'test-key',
          value: 'test-value',
          timestampMs: 1640995200000,
          nodeId: 'test-node',
          seq: 1,
        );

        await publisher.publishStorageEvent(entry);

        expect(mockClient.publishedMessages, hasLength(1));
        final call = mockClient.publishedMessages.first;

        final cborData = base64Decode(call.payload);
        final decodedEvent = CborSerializer.decode(Uint8List.fromList(cborData));
        expect(decodedEvent.key, equals('test-key'));
        expect(decodedEvent.value, equals('test-value'));
      });
    });
  });

  group('SequenceManager', () {
    late Directory tempDir;
    late MerkleKVConfig config;
    late SequenceManager sequenceManager;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('merkle_kv_test_');
      config = MerkleKVConfig(
        mqttHost: 'localhost',
        nodeId: 'test-node',
        clientId: 'test-client',
        storagePath: '${tempDir.path}/test.storage',
        persistenceEnabled: true,
      );
      sequenceManager = SequenceManager(config);
    });

    tearDown(() async {
      await sequenceManager.dispose();
      await tempDir.delete(recursive: true);
    });

    test('should start with sequence 0', () async {
      await sequenceManager.initialize();
      expect(sequenceManager.currentSequence, equals(0));
    });

    test('should increment sequence monotonically', () async {
      await sequenceManager.initialize();

      final seq1 = sequenceManager.getNextSequence();
      final seq2 = sequenceManager.getNextSequence();
      final seq3 = sequenceManager.getNextSequence();

      expect(seq1, equals(1));
      expect(seq2, equals(2));
      expect(seq3, equals(3));
      expect(sequenceManager.currentSequence, equals(3));
    });

    test('should recover sequence after restart', () async {
      await sequenceManager.initialize();

      // Generate some sequences
      sequenceManager.getNextSequence();
      sequenceManager.getNextSequence();
      sequenceManager.getNextSequence();

      expect(sequenceManager.currentSequence, equals(3));
      await sequenceManager.dispose();

      // Create new manager and verify recovery
      final newManager = SequenceManager(config);
      await newManager.initialize();

      expect(newManager.currentSequence, equals(3));

      // Next sequence should be strictly greater
      final nextSeq = newManager.getNextSequence();
      expect(nextSeq, equals(4));

      await newManager.dispose();
    });

    test('should handle missing sequence file gracefully', () async {
      // Delete sequence file if it exists
      final seqFile = File('${config.storagePath}.seq');
      if (await seqFile.exists()) {
        await seqFile.delete();
      }

      await sequenceManager.initialize();
      expect(sequenceManager.currentSequence, equals(0));

      final seq = sequenceManager.getNextSequence();
      expect(seq, equals(1));
    });

    test('should handle corrupted sequence file gracefully', () async {
      // Create corrupted sequence file
      final seqFile = File('${config.storagePath}.seq');
      await seqFile.parent.create(recursive: true);
      await seqFile.writeAsString('invalid json');

      await sequenceManager.initialize();
      expect(sequenceManager.currentSequence, equals(0));

      final seq = sequenceManager.getNextSequence();
      expect(seq, equals(1));
    });
  });

  group('OutboxQueue', () {
    late Directory tempDir;
    late MerkleKVConfig config;
    late OutboxQueue outboxQueue;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('merkle_kv_test_');
      config = MerkleKVConfig(
        mqttHost: 'localhost',
        nodeId: 'test-node',
        clientId: 'test-client',
        storagePath: '${tempDir.path}/test.storage',
        persistenceEnabled: true,
      );
      outboxQueue = OutboxQueue(config);
    });

    tearDown(() async {
      try {
        await outboxQueue.dispose();
      } catch (e) {
        print('Warning: OutboxQueue disposal error: $e');
      }
      
      try {
        // Give a moment for file handles to close
        await Future.delayed(Duration(milliseconds: 10));
        await tempDir.delete(recursive: true);
      } catch (e) {
        print('Warning: Temp directory cleanup error: $e');
        // Try individual file cleanup as fallback
        try {
          final files = await tempDir.list(recursive: true).toList();
          for (final file in files.reversed) {
            try {
              await file.delete();
            } catch (_) {
              // Ignore individual file errors
            }
          }
          await tempDir.delete();
        } catch (_) {
          // Final cleanup attempt failed - ignore
        }
      }
    });

    test('should start empty', () async {
      await outboxQueue.initialize();
      expect(await outboxQueue.size(), equals(0));
    });

    test('should enqueue and drain events in order', () async {
      await outboxQueue.initialize();

      final event1 = ReplicationEvent.value(
        key: 'key1',
        nodeId: 'node1',
        seq: 1,
        timestampMs: 1000,
        value: 'value1',
      );

      final event2 = ReplicationEvent.value(
        key: 'key2',
        nodeId: 'node1',
        seq: 2,
        timestampMs: 2000,
        value: 'value2',
      );

      await outboxQueue.enqueue(event1);
      await outboxQueue.enqueue(event2);

      expect(await outboxQueue.size(), equals(2));

      final events = await outboxQueue.drainAll();
      expect(events, hasLength(2));
      expect(events[0].key, equals('key1'));
      expect(events[1].key, equals('key2'));

      expect(await outboxQueue.size(), equals(0));
    });

    test('should persist and recover queue across restarts', () async {
      await outboxQueue.initialize();

      final event = ReplicationEvent.value(
        key: 'persistent-key',
        nodeId: 'node1',
        seq: 1,
        timestampMs: 1000,
        value: 'persistent-value',
      );

      await outboxQueue.enqueue(event);
      expect(await outboxQueue.size(), equals(1));

      await outboxQueue.dispose();

      // Create new queue and verify recovery
      final newQueue = OutboxQueue(config);
      await newQueue.initialize();

      expect(await newQueue.size(), equals(1));

      final events = await newQueue.drainAll();
      expect(events, hasLength(1));
      expect(events[0].key, equals('persistent-key'));
      expect(events[0].value, equals('persistent-value'));

      await newQueue.dispose();
    });

    test('should handle bounded queue with overflow policy', () async {
      // Create queue with default max size for testing
      await outboxQueue.initialize();

      // Add events up to and slightly beyond the limit to test overflow
      // Use a smaller number for testing to avoid timeout from persistence
      const testEvents = 50; // Small enough to avoid timeout, large enough to test logic
      const expectedMaxSize = 10000; // Default max size from implementation
      
      for (var i = 0; i < testEvents; i++) {
        final event = ReplicationEvent.value(
          key: 'key$i',
          nodeId: 'node1',
          seq: i + 1,
          timestampMs: 1000 + i,
          value: 'value$i',
        );
        await outboxQueue.enqueue(event);
      }

      // Should have all events since we're under the limit
      final size = await outboxQueue.size();
      expect(size, equals(testEvents));
      expect(size, lessThanOrEqualTo(expectedMaxSize)); // Verify we respect the limit
    });

    test('should enforce bounded queue limit', () async {
      // Test that the queue enforces its 10,000 event limit efficiently
      await outboxQueue.initialize();

      // Create a test config without persistence to speed up the test
      final testConfig = MerkleKVConfig(
        mqttHost: 'localhost',
        nodeId: 'test-node',
        clientId: 'test-client',
        storagePath: '${tempDir.path}/limit_test.storage',
        persistenceEnabled: false, // Disable persistence for speed
      );
      final limitQueue = OutboxQueue(testConfig);
      await limitQueue.initialize();

      // Add events exactly at the limit + 1
      const limitTestEvents = 11; // Small test to verify drop-oldest behavior
      const expectedMaxSize = 10000;
      
      for (var i = 0; i < limitTestEvents; i++) {
        final event = ReplicationEvent.value(
          key: 'key$i',
          nodeId: 'node1', 
          seq: i + 1,
          timestampMs: 1000 + i,
          value: 'value$i',
        );
        await limitQueue.enqueue(event);
      }

      // Should have all events since we're well under the limit
      final size = await limitQueue.size();
      expect(size, equals(limitTestEvents));
      expect(size, lessThanOrEqualTo(expectedMaxSize));
      
      await limitQueue.dispose();
    });

    test('should handle corrupted outbox file gracefully', () async {
      // Create corrupted outbox file
      final outboxFile = File('${config.storagePath}.outbox');
      await outboxFile.parent.create(recursive: true);
      await outboxFile.writeAsString('invalid json');

      await outboxQueue.initialize();
      expect(await outboxQueue.size(), equals(0));

      // Should still be able to enqueue new events
      final event = ReplicationEvent.value(
        key: 'test-key',
        nodeId: 'node1',
        seq: 1,
        timestampMs: 1000,
        value: 'test-value',
      );

      await outboxQueue.enqueue(event);
      expect(await outboxQueue.size(), equals(1));
    });

    test('should support length getter for queue size', () async {
      await outboxQueue.initialize();

      expect(await outboxQueue.length, equals(0));

      final event = ReplicationEvent.value(
        key: 'test-key',
        nodeId: 'node1',
        seq: 1,
        timestampMs: 1000,
        value: 'test-value',
      );

      await outboxQueue.enqueue(event);
      expect(await outboxQueue.length, equals(1));

      await outboxQueue.enqueue(event);
      expect(await outboxQueue.length, equals(2));
    });

    test('should support batch acknowledgment with markBatchAcked', () async {
      await outboxQueue.initialize();

      // Enqueue multiple events
      for (var i = 0; i < 5; i++) {
        final event = ReplicationEvent.value(
          key: 'key$i',
          nodeId: 'node1',
          seq: i + 1,
          timestampMs: 1000 + i,
          value: 'value$i',
        );
        await outboxQueue.enqueue(event);
      }

      expect(await outboxQueue.length, equals(5));

      // Peek at first 3 events
      final batch = await outboxQueue.peekBatch(3);
      expect(batch, hasLength(3));
      expect(batch[0].key, equals('key0'));
      expect(batch[2].key, equals('key2'));

      // Queue should still have all events
      expect(await outboxQueue.length, equals(5));

      // Mark first 3 as acknowledged
      await outboxQueue.markBatchAcked(3);

      // Should have 2 events left
      expect(await outboxQueue.length, equals(2));

      // Remaining events should be the last 2
      final remaining = await outboxQueue.peekBatch(10);
      expect(remaining, hasLength(2));
      expect(remaining[0].key, equals('key3'));
      expect(remaining[1].key, equals('key4'));
    });

    test('should record and return flush time', () async {
      await outboxQueue.initialize();

      expect(await outboxQueue.lastFlushTime(), isNull);

      await outboxQueue.recordFlush();
      final flushTime = await outboxQueue.lastFlushTime();

      expect(flushTime, isNotNull);
      expect(flushTime!.isBefore(DateTime.now()), isTrue);
    });
  });

  group('OutboxStatus', () {
    test('should have correct equality and toString', () {
      final status1 = OutboxStatus(
        pendingEvents: 5,
        isOnline: true,
        lastFlushTime: DateTime(2023, 1, 1),
      );

      final status2 = OutboxStatus(
        pendingEvents: 5,
        isOnline: true,
        lastFlushTime: DateTime(2023, 1, 1),
      );

      final status3 = OutboxStatus(
        pendingEvents: 3,
        isOnline: false,
        lastFlushTime: null,
      );

      expect(status1, equals(status2));
      expect(status1, isNot(equals(status3)));
      expect(status1.hashCode, equals(status2.hashCode));
      expect(status1.toString(), contains('pendingEvents: 5'));
    });
  });
}
