import 'dart:async';
import 'dart:convert';
import 'package:mocktail/mocktail.dart';
import '../../lib/src/storage/storage_interface.dart';
import '../../lib/src/storage/storage_entry.dart';
import '../../lib/src/mqtt/mqtt_client_interface.dart';
import '../../lib/src/mqtt/connection_state.dart';

/// Mock storage implementation for unit testing
class MockStorage extends Mock implements StorageInterface {
  final Map<String, StorageEntry> _entries = {};
  bool _initialized = false;

  // Override get method to return entries from memory
  @override
  Future<StorageEntry?> get(String key) async {
    _ensureInitialized();
    return _entries[key];
  }

  // Override put method to store entries in memory with LWW resolution
  @override
  Future<void> put(String key, StorageEntry entry) async {
    _ensureInitialized();
    
    final existing = _entries[key];
    if (existing != null) {
      if (existing.winsOver(entry)) {
        return; // Existing wins, ignore put
      }
      if (existing.isEquivalentTo(entry)) {
        return; // Identical, ignore put
      }
    }
    
    _entries[key] = entry;
  }

  @override
  Future<void> putWithReconciliation(String key, StorageEntry entry) async {
    await put(key, entry);
  }

  @override
  Future<void> delete(String key, int timestampMs, String nodeId, int seq) async {
    _ensureInitialized();
    
    final tombstone = StorageEntry.tombstone(
      key: key,
      timestampMs: timestampMs,
      nodeId: nodeId,
      seq: seq,
    );
    
    await put(key, tombstone);
  }

  @override
  Future<List<StorageEntry>> getAllEntries() async {
    _ensureInitialized();
    return List<StorageEntry>.from(_entries.values);
  }

  @override
  Future<int> garbageCollectTombstones() async {
    _ensureInitialized();
    
    final keysToRemove = <String>[];
    for (final entry in _entries.values) {
      if (entry.isExpiredTombstone()) {
        keysToRemove.add(entry.key);
      }
    }
    
    for (final key in keysToRemove) {
      _entries.remove(key);
    }
    
    return keysToRemove.length;
  }

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<void> dispose() async {
    _entries.clear();
    _initialized = false;
  }

  // Test helper methods
  void setEntry(String key, StorageEntry entry) {
    _entries[key] = entry;
  }

  StorageEntry? getEntry(String key) {
    return _entries[key];
  }

  void clear() {
    _entries.clear();
  }

  int get entryCount => _entries.length;

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('MockStorage not initialized');
    }
  }
}

/// Mock MQTT client for testing topic router and connection behavior  
class MockMqttClient extends Mock implements MqttClientInterface {
  final StreamController<ConnectionState> _connectionStateController = 
      StreamController<ConnectionState>.broadcast();
  
  final Map<String, void Function(String, String)> _subscriptions = {};
  final List<PublishCall> _publishCalls = [];
  ConnectionState _currentState = ConnectionState.disconnected;

  @override
  Stream<ConnectionState> get connectionState => _connectionStateController.stream;

  ConnectionState get currentConnectionState => _currentState;

  @override
  Future<void> connect() async {
    _updateConnectionState(ConnectionState.connecting);
    await Future.delayed(const Duration(milliseconds: 10));
    _updateConnectionState(ConnectionState.connected);
  }

  @override
  Future<void> disconnect({bool suppressLWT = true}) async {
    _updateConnectionState(ConnectionState.disconnecting);
    await Future.delayed(const Duration(milliseconds: 10));
    _updateConnectionState(ConnectionState.disconnected);
  }

  @override
  Future<void> subscribe(String topic, void Function(String, String) handler) async {
    _subscriptions[topic] = handler;
  }

  @override
  Future<void> unsubscribe(String topic) async {
    _subscriptions.remove(topic);
  }

  @override
  Future<void> publish(
    String topic,
    String payload, {
    bool forceQoS1 = true,
    bool forceRetainFalse = true,
  }) async {
    _publishCalls.add(PublishCall(
      topic: topic,
      payload: payload,
      qos1: forceQoS1,
      retainFalse: forceRetainFalse,
    ));
  }

  // Test helper methods
  void simulateConnectionState(ConnectionState state) {
    _updateConnectionState(state);
  }

  void simulateMessage(String topic, String payload) {
    final handler = _subscriptions[topic];
    if (handler != null) {
      handler(topic, payload);
    }
  }

  void simulateQoSDowngrade() {
    // Simulate broker downgrading QoS to 0
    // This would typically be detected during subscription
  }

  void simulateMalformedPacket() {
    // Simulate receiving malformed MQTT packet
    _updateConnectionState(ConnectionState.disconnected);
  }

  void reset() {
    _publishCalls.clear();
    _subscriptions.clear();
  }

  List<PublishCall> get publishCalls => List.unmodifiable(_publishCalls);
  Set<String> get subscribedTopics => _subscriptions.keys.toSet();
  Map<String, void Function(String, String)> get subscriptionHandlers => 
      Map.unmodifiable(_subscriptions);

  void _updateConnectionState(ConnectionState state) {
    _currentState = state;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(state);
    }
  }

  Future<void> dispose() async {
    reset(); // Clear internal state to prevent memory leaks
    await _connectionStateController.close();
  }
}

/// Represents a publish call for testing
class PublishCall {
  final String topic;
  final String payload;
  final bool qos1;
  final bool retainFalse;

  const PublishCall({
    required this.topic,
    required this.payload,
    required this.qos1,
    required this.retainFalse,
  });

  @override
  String toString() => 'PublishCall(topic: $topic, payload: ${payload.length} bytes, qos1: $qos1, retain: ${!retainFalse})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PublishCall &&
        other.topic == topic &&
        other.payload == payload &&
        other.qos1 == qos1 &&
        other.retainFalse == retainFalse;
  }

  @override
  int get hashCode => Object.hash(topic, payload, qos1, retainFalse);
}

/// Test configuration builder for various test scenarios
class TestConfigBuilder {
  String _mqttHost = 'localhost';
  int _mqttPort = 1883;
  String _clientId = 'test-client';
  String _nodeId = 'test-node';
  String _topicPrefix = 'test/prefix';
  String? _username;
  String? _password;
  bool _enableTls = false;

  TestConfigBuilder mqttHost(String host) {
    _mqttHost = host;
    return this;
  }

  TestConfigBuilder mqttPort(int port) {
    _mqttPort = port;
    return this;
  }

  TestConfigBuilder clientId(String id) {
    _clientId = id;
    return this;
  }

  TestConfigBuilder nodeId(String id) {
    _nodeId = id;
    return this;
  }

  TestConfigBuilder topicPrefix(String prefix) {
    _topicPrefix = prefix;
    return this;
  }

  TestConfigBuilder credentials(String username, String password) {
    _username = username;
    _password = password;
    return this;
  }

  TestConfigBuilder enableTls() {
    _enableTls = true;
    return this;
  }

  Map<String, dynamic> build() {
    final config = {
      'mqttHost': _mqttHost,
      'mqttPort': _mqttPort,
      'clientId': _clientId,
      'nodeId': _nodeId,
      'topicPrefix': _topicPrefix,
      'enableTls': _enableTls,
    };

    if (_username != null) config['username'] = _username!;
    if (_password != null) config['password'] = _password!;

    return config;
  }
}

/// Test data factory for creating consistent test objects
class TestDataFactory {
  static StorageEntry createEntry({
    required String key,
    String? value,
    int? timestampMs,
    String nodeId = 'test-node',
    int seq = 1,
    bool isTombstone = false,
  }) {
    final timestamp = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
    
    if (isTombstone) {
      return StorageEntry.tombstone(
        key: key,
        timestampMs: timestamp,
        nodeId: nodeId,
        seq: seq,
      );
    } else {
      return StorageEntry.value(
        key: key,
        value: value ?? 'test-value',
        timestampMs: timestamp,
        nodeId: nodeId,
        seq: seq,
      );
    }
  }

  static Map<String, dynamic> createCommand({
    String id = 'test-request',
    String op = 'GET',
    String? key,
    dynamic value,
    List<String>? keys,
    Map<String, dynamic>? keyValues,
  }) {
    final command = {'id': id, 'op': op};
    
    if (key != null) command['key'] = key;
    if (value != null) command['value'] = value;
    if (keys != null) command['keys'] = keys.join(',');
    if (keyValues != null) command['keyValues'] = keyValues.entries.map((e) => '${e.key}=${e.value}').join(',');
    
    return command;
  }

  static String createMalformedJson(String type) {
    switch (type) {
      case 'truncated':
        return '{"id": "test", "op": "GET"';
      case 'missing_quote':
        return '{id": "test", "op": "GET"}';
      case 'invalid_escape':
        return '{"id": "test", "op": "\\q"}';
      case 'trailing_comma':
        return '{"id": "test", "op": "GET",}';
      case 'control_char':
        return '{"id": "test\x00", "op": "GET"}';
      default:
        return '{"invalid": json}';
    }
  }
}

/// Assertion helpers for common test patterns
class TestAssertions {
  /// Asserts that a storage entry has expected LWW properties
  static void assertLwwWinner(StorageEntry winner, StorageEntry loser) {
    if (winner.timestampMs != loser.timestampMs) {
      if (winner.timestampMs <= loser.timestampMs) {
        throw AssertionError(
          'LWW winner should have newer timestamp: '
          'winner=${winner.timestampMs}, loser=${loser.timestampMs}'
        );
      }
    } else {
      // Same timestamp, check nodeId tiebreaker
      if (winner.nodeId.compareTo(loser.nodeId) <= 0) {
        throw AssertionError(
          'LWW winner should have lexically greater nodeId: '
          'winner="${winner.nodeId}", loser="${loser.nodeId}"'
        );
      }
    }
  }

  /// Asserts that a topic follows canonical format
  static void assertCanonicalTopic(String topic, String expectedPrefix, String expectedClientId, String expectedSuffix) {
    final expected = '$expectedPrefix/$expectedClientId/$expectedSuffix';
    if (topic != expected) {
      throw AssertionError(
        'Topic does not match canonical format: '
        'actual="$topic", expected="$expected"'
      );
    }
  }

  /// Asserts that UTF-8 byte length is within limit
  static void assertUtf8ByteLength(String text, int maxBytes) {
    final bytes = utf8.encode(text);
    if (bytes.length > maxBytes) {
      throw AssertionError(
        'UTF-8 byte length exceeds limit: '
        'actual=${bytes.length}, max=$maxBytes, text="$text"'
      );
    }
  }

  /// Asserts that payload size is within limit
  static void assertPayloadSize(String jsonPayload, int maxBytes) {
    final bytes = utf8.encode(jsonPayload);
    if (bytes.length > maxBytes) {
      throw AssertionError(
        'Payload size exceeds limit: '
        'actual=${bytes.length}, max=$maxBytes'
      );
    }
  }
}