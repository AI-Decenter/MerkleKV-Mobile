import 'dart:io';
import 'package:merkle_kv_core/merkle_kv_core.dart';

/// Mock MQTT client for demonstration
class MockMqttClient implements MqttClientInterface {
  final List<String> _publishedMessages = [];
  ConnectionState _state = ConnectionState.disconnected;

  @override
  Stream<ConnectionState> get connectionState => Stream.value(_state);

  @override
  Future<void> connect() async {
    _state = ConnectionState.connected;
    print('MQTT: Connected');
  }

  @override
  Future<void> disconnect({bool suppressLWT = true}) async {
    _state = ConnectionState.disconnected;
    print('MQTT: Disconnected');
  }

  @override
  Future<void> publish(String topic, String payload, {bool forceQoS1 = true, bool forceRetainFalse = true}) async {
    if (_state != ConnectionState.connected) {
      throw Exception('Not connected');
    }
    _publishedMessages.add('$topic: $payload');
    print('MQTT: Published to $topic (${payload.length} bytes)');
  }

  @override
  Future<void> subscribe(String topic, void Function(String, String) handler) async {
    print('MQTT: Subscribed to $topic');
  }

  @override
  Future<void> unsubscribe(String topic) async {
    print('MQTT: Unsubscribed from $topic');
  }

  List<String> get publishedMessages => List.unmodifiable(_publishedMessages);

  void simulateDisconnection() {
    _state = ConnectionState.disconnected;
    print('MQTT: Connection lost');
  }

  void simulateReconnection() {
    _state = ConnectionState.connected;
    print('MQTT: Reconnected');
  }
}

/// Enhanced command processor that publishes replication events
class ReplicatingCommandProcessor {
  final CommandProcessor _processor;
  final ReplicationEventPublisher _eventPublisher;
  final MerkleKVConfig _config;
  final StorageInterface _storage;
  int _sequenceNumber = 0;

  ReplicatingCommandProcessor({
    required CommandProcessor processor,
    required ReplicationEventPublisher eventPublisher,
    required MerkleKVConfig config,
    required StorageInterface storage,
  }) : _processor = processor, 
       _eventPublisher = eventPublisher,
       _config = config,
       _storage = storage;

  Future<Response> set(String key, String value, String id) async {
    final response = await _processor.set(key, value, id);
    
    // Publish replication event on successful SET
    if (response.isSuccess) {
      try {
        final entry = await _storage.get(key);
        if (entry != null) {
          await _eventPublisher.publishStorageEvent(entry);
        }
      } catch (e) {
        print('Warning: Failed to publish replication event for SET: $e');
      }
    }
    
    return response;
  }

  Future<Response> delete(String key, String id) async {
    final response = await _processor.delete(key, id);
    
    // Publish replication event on successful DELETE
    if (response.isSuccess) {
      try {
        // Create a tombstone entry for replication
        final timestampMs = DateTime.now().millisecondsSinceEpoch;
        final seq = ++_sequenceNumber;
        
        final tombstoneEntry = StorageEntry.tombstone(
          key: key,
          timestampMs: timestampMs,
          nodeId: _config.nodeId,
          seq: seq,
        );
        
        await _eventPublisher.publishStorageEvent(tombstoneEntry);
      } catch (e) {
        print('Warning: Failed to publish replication event for DELETE: $e');
      }
    }
    
    return response;
  }

  // Delegate other methods
  Future<Response> get(String key, String id) async {
    return await _processor.get(key, id);
  }
}

/// Demonstrates complete replication event publishing workflow
void main() async {
  print('=== MerkleKV Mobile Replication Event Publishing Demo ===\n');

  // Setup temporary directory
  final tempDir = await Directory.systemTemp.createTemp('replication_demo_');
  print('Using temp directory: ${tempDir.path}');

  try {
    // Configuration
    final config = MerkleKVConfig(
      mqttHost: 'broker.example.com',
      nodeId: 'demo-node-1',
      clientId: 'demo-client-1',
      topicPrefix: 'demo/cluster',
      storagePath: '${tempDir.path}/storage',
      persistenceEnabled: true,
    );

    // Initialize components
    final mockMqtt = MockMqttClient();
    final topicScheme = TopicScheme.create(config.topicPrefix, config.clientId);
    final metrics = InMemoryReplicationMetrics();
    
    final storage = StorageFactory.create(config);
    await storage.initialize();

    final eventPublisher = ReplicationEventPublisherImpl(
      config: config,
      mqttClient: mockMqtt,
      topicScheme: topicScheme,
      metrics: metrics,
    );
    await eventPublisher.initialize();

    final baseCommandProcessor = CommandProcessorImpl(config, storage);
    
    final commandProcessor = ReplicatingCommandProcessor(
      processor: baseCommandProcessor,
      eventPublisher: eventPublisher,
      config: config,
      storage: storage,
    );

    print('Topic scheme:');
    print('  Command: ${topicScheme.commandTopic}');
    print('  Response: ${topicScheme.responseTopic}');
    print('  Replication: ${topicScheme.replicationTopic}');
    print('');

    // Connect MQTT
    await mockMqtt.connect();

    // Demonstrate operations with replication
    print('--- Performing Operations ---');
    
    // SET operation
    print('1. SET user:123 "John Doe"');
    final setResponse = await commandProcessor.set('user:123', 'John Doe', 'req-1');
    print('   Response: ${setResponse.status}');
    print('   Metrics: ${metrics}');
    print('');

    // SET another key
    print('2. SET user:456 "Jane Smith"');
    final setResponse2 = await commandProcessor.set('user:456', 'Jane Smith', 'req-2');
    print('   Response: ${setResponse2.status}');
    print('   Metrics: ${metrics}');
    print('');

    // DELETE operation
    print('3. DELETE user:123');
    final deleteResponse = await commandProcessor.delete('user:123', 'req-3');
    print('   Response: ${deleteResponse.status}');
    print('   Metrics: ${metrics}');
    print('');

    // Demonstrate offline queuing
    print('--- Testing Offline Behavior ---');
    mockMqtt.simulateDisconnection();

    print('4. SET user:789 "Bob Wilson" (while offline)');
    final offlineResponse = await commandProcessor.set('user:789', 'Bob Wilson', 'req-4');
    print('   Response: ${offlineResponse.status}');
    print('   Metrics: ${metrics}');
    print('');

    // Check outbox status
    final status = await eventPublisher.outboxStatus.first;
    print('   Outbox status: ${status.pendingEvents} pending events');
    print('');

    // Reconnect and flush
    print('5. Reconnecting and flushing outbox...');
    mockMqtt.simulateReconnection();
    await eventPublisher.flushOutbox();
    print('   Metrics after flush: ${metrics}');
    print('');

    // Show published messages
    print('--- Published MQTT Messages ---');
    for (var i = 0; i < mockMqtt.publishedMessages.length; i++) {
      print('${i + 1}. ${mockMqtt.publishedMessages[i]}');
    }
    print('');

    // Demonstrate sequence persistence
    print('--- Testing Sequence Persistence ---');
    print('Current sequence: ${eventPublisher.currentSequence}');
    
    // Dispose and recreate to test recovery
    await eventPublisher.dispose();
    
    final newEventPublisher = ReplicationEventPublisherImpl(
      config: config,
      mqttClient: mockMqtt,
      topicScheme: topicScheme,
      metrics: metrics,
    );
    await newEventPublisher.initialize();
    
    print('Recovered sequence: ${newEventPublisher.currentSequence}');
    print('Next sequence would be: ${newEventPublisher.currentSequence + 1}');

    await newEventPublisher.dispose();
    await storage.dispose();

    print('\n=== Demo Complete ===');
    print('Total events published: ${metrics.eventsPublished}');
    print('Total publish errors: ${metrics.publishErrors}');
    print('Average publish latency: ${metrics.publishLatencies.isEmpty ? 0 : metrics.publishLatencies.reduce((a, b) => a + b) / metrics.publishLatencies.length}ms');

  } finally {
    await tempDir.delete(recursive: true);
  }
}
