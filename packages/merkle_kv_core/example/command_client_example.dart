// ignore_for_file: avoid_print
import 'dart:async';

import 'package:merkle_kv_core/merkle_kv_core.dart';

/// Example demonstrating CommandCorrelator integration with MQTT client and topic router.
///
/// This example shows how to use the CommandCorrelator to send commands with
/// automatic correlation, timeouts, and deduplication over MQTT.
class MerkleKVCommandClient {
  final MqttClientInterface _mqttClient;
  final TopicRouter _topicRouter;
  final CommandCorrelator _correlator;

  MerkleKVCommandClient._(
    this._mqttClient,
    this._topicRouter,
    this._correlator,
  );

  /// Creates a MerkleKV command client with MQTT transport.
  static Future<MerkleKVCommandClient> create(MerkleKVConfig config) async {
    final mqttClient = MqttClientImpl(config);
    final topicRouter = TopicRouterImpl(config, mqttClient);

    // Create correlator with topic router publish function
    final correlator = CommandCorrelator(
      publishCommand: (jsonPayload) async {
        // Clients may only publish to their own canonical command topic.
        await topicRouter.publishCommand(config.clientId, jsonPayload);
      },
      logger: (entry) {
        print('Command lifecycle: ${entry.toString()}');
      },
    );

    final client = MerkleKVCommandClient._(mqttClient, topicRouter, correlator);

    // Connect and set up response handling
    await client._initialize();

    return client;
  }

  /// Initialize the client and set up response handling.
  Future<void> _initialize() async {
    // Connect to MQTT broker
    await _mqttClient.connect();

    // Subscribe to incoming commands (responses would be handled in a real implementation)
    // In practice, the server side would handle commands and send responses
    await _topicRouter.subscribeToCommands((topic, payload) {
      // This would typically be handled by a server-side component
      // For this example, we're just showing the client-side correlation
      print('Received command: $payload');
    });

    print('MerkleKV Command Client initialized and ready');
  }

  /// Sends a GET command for the specified key.
  Future<Response> get(String key) async {
    final command = Command(
      id: '', // Will be auto-generated
      op: 'GET',
      key: key,
    );

    return await _correlator.send(command);
  }

  /// Sends a SET command for the specified key-value pair.
  Future<Response> set(String key, dynamic value) async {
    final command = Command(
      id: '', // Will be auto-generated
      op: 'SET',
      key: key,
      value: value,
    );

    return await _correlator.send(command);
  }

  /// Sends a DELETE command for the specified key.
  Future<Response> delete(String key) async {
    final command = Command(
      id: '', // Will be auto-generated
      op: 'DEL',
      key: key,
    );

    return await _correlator.send(command);
  }

  /// Sends a multi-GET command for the specified keys.
  Future<Response> multiGet(List<String> keys) async {
    final command = Command(
      id: '', // Will be auto-generated
      op: 'MGET',
      keys: keys,
    );

    return await _correlator.send(command);
  }

  /// Sends an INCREMENT command for the specified key.
  Future<Response> increment(String key, {int amount = 1}) async {
    final command = Command(
      id: '', // Will be auto-generated
      op: 'INCR',
      key: key,
      amount: amount,
    );

    return await _correlator.send(command);
  }

  /// Returns client statistics for monitoring.
  Map<String, dynamic> getStats() {
    return {
      'pending_requests': _correlator.pendingRequestCount,
      'cache_size': _correlator.cacheSize,
      'connection_state': _mqttClient.connectionState.toString(),
    };
  }

  /// Disconnects and cleans up resources.
  Future<void> dispose() async {
    _correlator.dispose();
    await _mqttClient.disconnect();
  }
}

/// Example usage demonstration
Future<void> main() async {
  // Configure MerkleKV
  final config = MerkleKVConfig(
    mqttHost: 'localhost',
    mqttPort: 1883,
    clientId: 'demo-client',
    nodeId: 'demo-node',
    topicPrefix: 'merkle/demo',
  );

  // Create command client
  final client = await MerkleKVCommandClient.create(config);

  try {
    // Example operations with automatic correlation
    print('Setting value...');
    final setResponse = await client.set('user:123', {
      'name': 'Alice',
      'age': 30,
    });
    print('SET result: ${setResponse.status.value}');

    print('Getting value...');
    final getResponse = await client.get('user:123');
    if (getResponse.isSuccess) {
      print('GET result: ${getResponse.value}');
    } else {
      print('GET error: ${getResponse.error}');
    }

    print('Incrementing counter...');
    final incrResponse = await client.increment('counter:visits', amount: 5);
    print('INCR result: ${incrResponse.status.value}');

    // Multi-key operation
    print('Multi-get...');
    final mgetResponse = await client.multiGet(['user:123', 'counter:visits']);
    print('MGET result: ${mgetResponse.value}');

    // Show client statistics
    print('Client stats: ${client.getStats()}');
  } catch (e) {
    print('Error: $e');
  } finally {
    // Clean up
    await client.dispose();
  }
}
