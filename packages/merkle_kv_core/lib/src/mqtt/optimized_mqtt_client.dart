import 'dart:async';
import 'dart:convert';

import '../config/merkle_kv_config.dart';
import '../replication/metrics.dart';
import '../utils/payload_optimizer.dart';
import 'connection_state.dart';
import 'mqtt_client_interface.dart';
import 'mqtt_client_impl.dart';

/// MQTT client decorator that applies transparent payload optimization
/// to published messages while maintaining full wire format compatibility.
class OptimizedMqttClient implements MqttClientInterface {
  /// The underlying MQTT client
  final MqttClientInterface _client;
  
  /// The payload optimizer for message size reduction
  final PayloadOptimizer _optimizer;
  
  /// The size estimator for pre-flight validation
  final SizeEstimator _sizeEstimator = SizeEstimator();
  
  /// Metrics collection
  final ReplicationMetrics? _metrics;

  /// Creates an optimized MQTT client that transparently applies
  /// payload optimization to published messages.
  OptimizedMqttClient(
    MqttClientInterface client, {
    ReplicationMetrics? metrics,
  }) : _client = client,
       _metrics = metrics,
       _optimizer = PayloadOptimizer(metrics: metrics);

  @override
  Stream<ConnectionState> get connectionState => _client.connectionState;

  @override
  Future<void> connect() => _client.connect();

  @override
  Future<void> disconnect({bool suppressLWT = true}) => _client.disconnect(suppressLWT: suppressLWT);

  @override
  Future<void> publish(String topic, String payload, {bool forceQoS1 = true, bool forceRetainFalse = true}) async {
    try {
      // Try to optimize JSON payload if it's valid JSON
      String optimizedPayload;
      try {
        final dynamic jsonData = jsonDecode(payload);
        if (jsonData is Map<String, dynamic>) {
          // Valid JSON object, apply optimization
          final String encoded = jsonEncode(
            _reorderJsonFields(jsonData as Map<String, dynamic>)
          );
          optimizedPayload = encoded;
        } else {
          // Not a JSON object (array or primitive), use as-is
          optimizedPayload = payload;
        }
      } catch (_) {
        // Not valid JSON, use as-is
        optimizedPayload = payload;
      }
      
      // Validate size before publishing
      if (utf8.encode(optimizedPayload).length > SizeEstimator.maxPayloadSize) {
        _metrics?.incrementSizeLimitExceeded();
        throw Exception('Payload exceeds maximum size limit');
      }
      
      // Publish optimized payload
      await _client.publish(topic, optimizedPayload, forceQoS1: forceQoS1, forceRetainFalse: forceRetainFalse);
    } catch (e) {
      // Re-throw any exceptions
      rethrow;
    }
  }

  @override
  Future<void> subscribe(
    String topic,
    void Function(String, String) handler,
  ) {
    // Pass-through subscriptions (no optimization needed for incoming messages)
    return _client.subscribe(topic, handler);
  }

  @override
  Future<void> unsubscribe(String topic) {
    // Pass-through unsubscribe
    return _client.unsubscribe(topic);
  }
  
  /// Reorders JSON fields for consistent minimal representation
  Map<String, dynamic> _reorderJsonFields(Map<String, dynamic> json) {
    final Map<String, dynamic> ordered = <String, dynamic>{};
    
    // Add fields in a consistent order based on common schema patterns
    
    // IDs and operation types first (almost always present)
    if (json.containsKey('id')) ordered['id'] = json['id'];
    if (json.containsKey('op')) ordered['op'] = json['op'];
    if (json.containsKey('type')) ordered['type'] = json['type'];
    if (json.containsKey('status')) ordered['status'] = json['status'];
    
    // Keys and values (very common)
    if (json.containsKey('key')) ordered['key'] = json['key'];
    if (json.containsKey('value')) ordered['value'] = json['value'];
    
    // Other fields in alphabetical order
    final List<String> remaining = json.keys
        .where((k) => !ordered.containsKey(k))
        .toList()
      ..sort();
    
    for (final String key in remaining) {
      final dynamic value = json[key];
      if (value is Map<String, dynamic>) {
        // Recursively reorder nested objects
        ordered[key] = _reorderJsonFields(value);
      } else if (value is List) {
        // Process list items if they are objects
        ordered[key] = _processListItems(value);
      } else {
        // Use value as-is for primitives
        ordered[key] = value;
      }
    }
    
    return ordered;
  }
  
  /// Process list items for nested JSON objects
  List _processListItems(List items) {
    return items.map((dynamic item) {
      if (item is Map<String, dynamic>) {
        return _reorderJsonFields(item);
      } else if (item is List) {
        return _processListItems(item);
      }
      return item;
    }).toList();
  }
}

/// Factory extension to create optimized MQTT clients
extension OptimizedMqttClientFactory on MqttClientInterface {
  /// Creates an optimized MQTT client that transparently applies
  /// payload optimization while maintaining wire format compatibility.
  static MqttClientInterface create(
    MerkleKVConfig config, {
    ReplicationMetrics? metrics,
  }) {
    // Create the base MQTT client
    final MqttClientInterface baseClient = MqttClientImpl(config);
    
    // Wrap with optimized client
    return OptimizedMqttClient(baseClient, metrics: metrics);
  }
}