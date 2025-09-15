import 'dart:async';
import 'dart:convert';

import 'commands/command.dart';
import 'commands/command_correlator.dart';
import 'commands/command_processor.dart';
import 'commands/response.dart';
import 'config/merkle_kv_config.dart';
import 'exceptions/merkle_kv_exception.dart';
import 'models/key_value_result.dart';
import 'mqtt/connection_state.dart';
import 'mqtt/mqtt_client_interface.dart';
import 'mqtt/mqtt_client_impl.dart';
import 'storage/storage_factory.dart';
import 'utils/string_operations.dart';

/// Main client interface for MerkleKV Mobile
///
/// Provides clean abstractions for core operations (GET, SET, DEL, INCR/DECR, 
/// APPEND/PREPEND), bulk operations (MGET/MSET), and configuration management.
/// 
/// The API enforces UTF-8 byte-size caps per Locked Spec §11, provides fail-fast 
/// behavior for disconnected operations unless offline queue is enabled, ensures 
/// idempotent DEL operations always return OK regardless of key existence, and 
/// maintains thread-safety for concurrent mobile usage.
class MerkleKV {
  static const int _maxKeyBytes = 256;
  static const int _maxValueBytes = 256 * 1024; // 256 KiB
  static const int _maxBulkPayloadBytes = 512 * 1024; // 512 KiB

  final MerkleKVConfig _config;
  late final MqttClientInterface _mqttClient;
  late final CommandProcessor _commandProcessor;
  late final CommandCorrelator _commandCorrelator;
  late final StreamController<ConnectionState> _connectionStateController;

  bool _isInitialized = false;
  bool _isConnected = false;
  ConnectionState _currentState = ConnectionState.disconnected;

  /// Creates a new MerkleKV client instance with the provided configuration.
  ///
  /// The client must be initialized with [connect] before operations can be performed.
  MerkleKV(this._config) {
    _connectionStateController = StreamController<ConnectionState>.broadcast();
  }

  /// Factory constructor that builds configuration using the builder pattern.
  ///
  /// Example:
  /// ```dart
  /// final client = MerkleKV.builder()
  ///   .mqttHost('mqtt.example.com')
  ///   .clientId('mobile-app-1')
  ///   .nodeId('device-123')
  ///   .useTls()
  ///   .build();
  /// ```
  static MerkleKVConfigBuilder builder() => MerkleKVConfig.builder();

  /// Current connection state stream.
  ///
  /// Emits connection state changes for monitoring connectivity.
  Stream<ConnectionState> get connectionState => _connectionStateController.stream;

  /// Current connection state.
  ConnectionState get currentConnectionState => _currentState;

  /// Whether the client is currently connected and ready for operations.
  bool get isConnected => _isConnected && _currentState == ConnectionState.connected;

  /// Get the version of the library
  String get version => '0.0.1';

  /// Initializes and connects the client to the MQTT broker.
  ///
  /// Must be called before any operations can be performed.
  /// Throws [ConnectionException] if connection fails.
  Future<void> connect() async {
    if (_isInitialized) {
      throw const ValidationException('Client is already initialized');
    }

    // Mark as initialized immediately to prevent multiple concurrent connect attempts
    _isInitialized = true;

    try {
      _updateConnectionState(ConnectionState.connecting);

      // Initialize storage
      final storage = StorageFactory.create(_config);

      // Initialize command processor
      _commandProcessor = CommandProcessorImpl(_config, storage);

      // Initialize MQTT client
      _mqttClient = MqttClientImpl(_config);

      // Initialize command correlator
      _commandCorrelator = CommandCorrelator(
        publishCommand: (jsonPayload) => _mqttClient.publish(
          '${_config.topicPrefix}/${_config.clientId}/cmd',
          jsonPayload,
        ),
      );

      // Connect to MQTT broker
      await _mqttClient.connect();

      _isConnected = true;
      _updateConnectionState(ConnectionState.connected);
    } catch (e) {
      // Keep _isInitialized as true to prevent retry attempts
      // Client must be disposed and recreated for a new connection attempt
      _isConnected = false;
      _updateConnectionState(ConnectionState.disconnected);
      if (e is MerkleKVException) {
        rethrow;
      }
      throw ConnectionException('Failed to connect: $e', e);
    }
  }

  /// Disconnects the client from the MQTT broker.
  ///
  /// After calling this method, the client must be reconnected with [connect]
  /// before operations can be performed again.
  Future<void> disconnect() async {
    if (!_isInitialized) {
      return;
    }

    try {
      _updateConnectionState(ConnectionState.disconnecting);
      await _mqttClient.disconnect();
    } finally {
      _isInitialized = false;
      _isConnected = false;
      _updateConnectionState(ConnectionState.disconnected);
    }
  }

  /// Retrieves the value associated with the given key.
  ///
  /// Returns the value if the key exists, null if the key doesn't exist.
  /// Throws [ValidationException] if key validation fails.
  /// Throws [TimeoutException] if the operation times out.
  /// Throws [DisconnectedException] if client is disconnected and offline queue is disabled.
  Future<String?> get(String key, [String? requestId]) async {
    _validateKey(key);
    _ensureConnected();

    final id = requestId ?? UuidGenerator.generate();
    final response = await _commandProcessor.get(key, id);

    if (response.isSuccess) {
      return response.value as String?;
    } else if (response.errorCode == ErrorCode.notFound) {
      return null;
    } else {
      throw MerkleKVException.fromResponse(response);
    }
  }

  /// Sets the value for the given key.
  ///
  /// Throws [ValidationException] if key or value validation fails.
  /// Throws [PayloadException] if value exceeds size limits.
  /// Throws [TimeoutException] if the operation times out.
  /// Throws [DisconnectedException] if client is disconnected and offline queue is disabled.
  Future<void> set(String key, String value, [String? requestId]) async {
    _validateKey(key);
    _validateValue(value);
    _ensureConnected();

    final id = requestId ?? UuidGenerator.generate();
    final response = await _commandProcessor.set(key, value, id);

    if (!response.isSuccess) {
      throw MerkleKVException.fromResponse(response);
    }
  }

  /// Deletes the key and its associated value.
  ///
  /// This operation is idempotent and always succeeds regardless of whether 
  /// the key exists, per Locked Spec requirements.
  /// 
  /// Throws [ValidationException] if key validation fails.
  /// Throws [TimeoutException] if the operation times out.
  /// Throws [DisconnectedException] if client is disconnected and offline queue is disabled.
  Future<void> delete(String key, [String? requestId]) async {
    _validateKey(key);
    _ensureConnected();

    final id = requestId ?? UuidGenerator.generate();
    final response = await _commandProcessor.delete(key, id);

    if (!response.isSuccess) {
      throw MerkleKVException.fromResponse(response);
    }
  }

  /// Increments the numeric value of the key by the specified amount.
  ///
  /// If the key doesn't exist, it's treated as 0 before incrementing.
  /// The default increment amount is 1.
  /// 
  /// Throws [ValidationException] if key validation fails or if the existing value is not numeric.
  /// Throws [TimeoutException] if the operation times out.
  /// Throws [DisconnectedException] if client is disconnected and offline queue is disabled.
  Future<int> increment(String key, [int amount = 1, String? requestId]) async {
    _validateKey(key);
    _ensureConnected();

    final id = requestId ?? UuidGenerator.generate();
    final response = await _commandProcessor.increment(key, amount, id);

    if (response.isSuccess) {
      return response.value as int;
    } else {
      throw MerkleKVException.fromResponse(response);
    }
  }

  /// Decrements the numeric value of the key by the specified amount.
  ///
  /// If the key doesn't exist, it's treated as 0 before decrementing.
  /// The default decrement amount is 1.
  /// 
  /// Throws [ValidationException] if key validation fails or if the existing value is not numeric.
  /// Throws [TimeoutException] if the operation times out.
  /// Throws [DisconnectedException] if client is disconnected and offline queue is disabled.
  Future<int> decrement(String key, [int amount = 1, String? requestId]) async {
    _validateKey(key);
    _ensureConnected();

    final id = requestId ?? UuidGenerator.generate();
    final response = await _commandProcessor.decrement(key, amount, id);

    if (response.isSuccess) {
      return response.value as int;
    } else {
      throw MerkleKVException.fromResponse(response);
    }
  }

  /// Appends the value to the end of the existing value for the given key.
  ///
  /// If the key doesn't exist, the operation is equivalent to a SET operation.
  /// 
  /// Throws [ValidationException] if key or value validation fails.
  /// Throws [PayloadException] if the resulting value would exceed size limits.
  /// Throws [TimeoutException] if the operation times out.
  /// Throws [DisconnectedException] if client is disconnected and offline queue is disabled.
  Future<void> append(String key, String value, [String? requestId]) async {
    _validateKey(key);
    _validateValue(value);
    _ensureConnected();

    final id = requestId ?? UuidGenerator.generate();
    final response = await _commandProcessor.append(key, value, id);

    if (!response.isSuccess) {
      throw MerkleKVException.fromResponse(response);
    }
  }

  /// Prepends the value to the beginning of the existing value for the given key.
  ///
  /// If the key doesn't exist, the operation is equivalent to a SET operation.
  /// 
  /// Throws [ValidationException] if key or value validation fails.
  /// Throws [PayloadException] if the resulting value would exceed size limits.
  /// Throws [TimeoutException] if the operation times out.
  /// Throws [DisconnectedException] if client is disconnected and offline queue is disabled.
  Future<void> prepend(String key, String value, [String? requestId]) async {
    _validateKey(key);
    _validateValue(value);
    _ensureConnected();

    final id = requestId ?? UuidGenerator.generate();
    final response = await _commandProcessor.prepend(key, value, id);

    if (!response.isSuccess) {
      throw MerkleKVException.fromResponse(response);
    }
  }

  /// Retrieves multiple keys in a single operation.
  ///
  /// Returns a map where keys that exist are mapped to their values,
  /// and keys that don't exist are not included in the result.
  /// 
  /// Throws [ValidationException] if any key validation fails.
  /// Throws [PayloadException] if the bulk operation exceeds payload size limits.
  /// Throws [TimeoutException] if the operation times out.
  /// Throws [DisconnectedException] if client is disconnected and offline queue is disabled.
  Future<Map<String, String>> multiGet(List<String> keys, [String? requestId]) async {
    if (keys.isEmpty) {
      return {};
    }

    for (final key in keys) {
      _validateKey(key);
    }
    _validateBulkPayload(keys, null);
    _ensureConnected();

    final id = requestId ?? UuidGenerator.generate();
    final response = await _commandProcessor.mget(keys, id);

    if (response.isSuccess && response.results != null) {
      final result = <String, String>{};
      for (final keyResult in response.results!) {
        if (keyResult.isSuccess && keyResult.value != null) {
          result[keyResult.key] = keyResult.value!;
        }
      }
      return result;
    } else {
      throw MerkleKVException.fromResponse(response);
    }
  }

  /// Sets multiple key-value pairs in a single operation.
  ///
  /// All operations are atomic - either all succeed or all fail.
  /// 
  /// Throws [ValidationException] if any key or value validation fails.
  /// Throws [PayloadException] if the bulk operation exceeds payload size limits.
  /// Throws [TimeoutException] if the operation times out.
  /// Throws [DisconnectedException] if client is disconnected and offline queue is disabled.
  Future<void> multiSet(Map<String, String> keyValues, [String? requestId]) async {
    if (keyValues.isEmpty) {
      return;
    }

    for (final entry in keyValues.entries) {
      _validateKey(entry.key);
      _validateValue(entry.value);
    }
    _validateBulkPayload(keyValues.keys.toList(), keyValues);
    _ensureConnected();

    final id = requestId ?? UuidGenerator.generate();
    final response = await _commandProcessor.mset(keyValues, id);

    if (!response.isSuccess) {
      throw MerkleKVException.fromResponse(response);
    }
  }

  /// Validates a key according to Locked Spec §11 requirements.
  void _validateKey(String key) {
    if (key.isEmpty) {
      throw const ValidationException('Key cannot be empty');
    }

    if (!StringOperations.isValidUtf8String(key)) {
      throw const ValidationException('Key must be valid UTF-8');
    }

    final keyBytes = StringOperations.getUtf8ByteSize(key);
    if (keyBytes > _maxKeyBytes) {
      throw ValidationException('Key size ($keyBytes bytes) exceeds maximum allowed ($_maxKeyBytes bytes)');
    }
  }

  /// Validates a value according to Locked Spec §11 requirements.
  void _validateValue(String value) {
    if (!StringOperations.isValidUtf8String(value)) {
      throw const ValidationException('Value must be valid UTF-8');
    }

    if (!StringOperations.isWithinSizeLimit(value)) {
      final valueBytes = StringOperations.getUtf8ByteSize(value);
      throw ValidationException('Value size ($valueBytes bytes) exceeds maximum allowed ($_maxValueBytes bytes)');
    }
  }

  /// Validates bulk operation payload size according to Locked Spec §11 requirements.
  void _validateBulkPayload(List<String> keys, Map<String, String>? keyValues) {
    // Create a mock command to check payload size
    final command = keyValues != null
        ? Command.mset(id: 'test', keyValues: keyValues)
        : Command.mget(id: 'test', keys: keys);

    final payload = command.toJsonString();
    final payloadBytes = utf8.encode(payload).length;

    if (payloadBytes > _maxBulkPayloadBytes) {
      throw PayloadException('Bulk operation payload size ($payloadBytes bytes) exceeds maximum allowed ($_maxBulkPayloadBytes bytes)');
    }
  }

  /// Ensures the client is connected before performing operations.
  void _ensureConnected() {
    if (!_isInitialized) {
      throw const DisconnectedException('Client is not initialized. Call connect() first.');
    }
    if (!_isConnected) {
      throw const DisconnectedException('Client is disconnected. Offline queue is not enabled.');
    }
  }

  /// Updates the connection state and notifies listeners.
  void _updateConnectionState(ConnectionState newState) {
    _currentState = newState;
    _connectionStateController.add(newState);
  }

  /// Disposes resources and closes streams.
  Future<void> dispose() async {
    await disconnect();
    await _connectionStateController.close();
  }
}
