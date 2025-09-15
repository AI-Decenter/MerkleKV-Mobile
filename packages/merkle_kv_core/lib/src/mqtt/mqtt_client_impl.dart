import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../config/merkle_kv_config.dart';
import 'connection_state.dart';
import 'mqtt_client_interface.dart';

/// Default implementation of [MqttClientInterface] using mqtt_client package.
///
/// Provides connection management with exponential backoff, session handling,
/// Last Will and Testament, and QoS enforcement per Locked Spec §6.
class MqttClientImpl implements MqttClientInterface {
  final MerkleKVConfig _config;
  late final MqttServerClient _client;
  final StreamController<ConnectionState> _connectionStateController =
      StreamController<ConnectionState>.broadcast();
  final List<_QueuedMessage> _messageQueue = [];
  final Map<String, void Function(String, String)> _subscriptions = {};

  ConnectionState _currentState = ConnectionState.disconnected;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  /// Creates an MQTT client implementation with the provided configuration.
  MqttClientImpl(this._config) {
    _initializeClient();
  }

  @override
  Stream<ConnectionState> get connectionState =>
      _connectionStateController.stream;

  /// Initialize the MQTT client with configuration settings.
  void _initializeClient() {
    _client = MqttServerClient(_config.mqttHost, _config.clientId);

    // Configure connection settings per Locked Spec §6
    _client.keepAlivePeriod = _config.keepAliveSeconds;
    _client.autoReconnect = false; // We handle reconnection manually
    _client.logging(on: false); // Prevent credential logging

    // TLS enforcement when credentials are present
    if ((_config.username != null || _config.password != null) &&
        !_config.mqttUseTls) {
      throw ArgumentError('TLS must be enabled when credentials are provided');
    }

    if (_config.mqttUseTls) {
      _client.secure = true;
      _client.port = _config.mqttPort;
      // Validate server certificate by default (reject bad certificates)
      _client.onBadCertificate = (Object certificate) => false;
    } else {
      _client.port = _config.mqttPort;
    }

    // Last Will and Testament (LWT) configuration
    _configureLWT();

    // Set up connection event handlers
    _client.onConnected = _onConnected;
    _client.onDisconnected = _onDisconnected;
    _client.onSubscribed = _onSubscribed;
    _client.onUnsubscribed = _onUnsubscribed;

    // Message handler
    _client.updates?.listen(_onMessageReceived);
  }

  /// Configure Last Will and Testament per Locked Spec §6.
  void _configureLWT() {
    final lwtTopic = '${_config.topicPrefix}/${_config.clientId}/res';
    final lwtPayload = json.encode({
      'status': 'offline',
      'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
    });

    final connectionMessage = MqttConnectMessage()
        .withWillTopic(lwtTopic)
        .withWillMessage(lwtPayload)
        .withWillQos(MqttQos.atLeastOnce) // QoS=1
        .withClientIdentifier(_config.clientId);

    _client.connectionMessage = connectionMessage;
  }

  @override
  Future<void> connect() async {
    if (_currentState == ConnectionState.connected ||
        _currentState == ConnectionState.connecting) {
      return;
    }

    _updateConnectionState(ConnectionState.connecting);

    try {
      await _attemptConnection();
      _reconnectAttempts = 0; // Reset on successful connection
    } catch (e) {
      _updateConnectionState(ConnectionState.disconnected);
      _scheduleReconnect();
      rethrow;
    }
  }

  /// Attempt connection with current settings and timeout.
  Future<void> _attemptConnection() async {
    try {
      var status;

      // Create a timeout completer for configurable connection timeout
      final connectionCompleter = Completer<MqttClientConnectionStatus?>();
      Timer? timeoutTimer;

      // Set up timeout from configuration
      timeoutTimer = Timer(Duration(seconds: _config.connectionTimeoutSeconds), () {
        if (!connectionCompleter.isCompleted) {
          connectionCompleter.completeError(Exception('Connection timeout after ${_config.connectionTimeoutSeconds} seconds'));
        }
      });

      // Handle authentication
      if (_config.username != null && _config.password != null) {
        _client.connect(_config.username!, _config.password!).then((status) {
          timeoutTimer?.cancel();
          if (!connectionCompleter.isCompleted) {
            connectionCompleter.complete(status);
          }
        }).catchError((error) {
          timeoutTimer?.cancel();
          if (!connectionCompleter.isCompleted) {
            connectionCompleter.completeError(error);
          }
        });
      } else {
        _client.connect().then((status) {
          timeoutTimer?.cancel();
          if (!connectionCompleter.isCompleted) {
            connectionCompleter.complete(status);
          }
        }).catchError((error) {
          timeoutTimer?.cancel();
          if (!connectionCompleter.isCompleted) {
            connectionCompleter.completeError(error);
          }
        });
      }

      // Wait for connection or timeout
      status = await connectionCompleter.future;

      if (status?.state != MqttConnectionState.connected) {
        throw Exception('Connection failed: ${status?.state}');
      }
    } on SocketException catch (e) {
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      if (e.toString().contains('authentication') ||
          e.toString().contains('unauthorized')) {
        throw Exception('Authentication failed');
      }
      if (e.toString().contains('timeout')) {
        throw Exception('Connection timeout after 20 seconds');
      }
      throw Exception('MQTT error: ${e.toString()}');
    }
  }

  /// Schedule reconnection with exponential backoff and jitter.
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();

    // Exponential backoff: 1s → 2s → 4s → ... → 32s (max)
    final baseDelay = math.min(math.pow(2, _reconnectAttempts).toInt(), 32);

    // Add jitter ±20%
    final random = math.Random();
    final jitter = 1.0 + (random.nextDouble() - 0.5) * 0.4; // ±20%
    final delaySeconds = (baseDelay * jitter).round();

    _reconnectAttempts++;

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      if (_currentState == ConnectionState.disconnected) {
        try {
          await connect();
        } catch (e) {
          // Error already handled in connect(), will schedule next attempt
        }
      }
    });
  }

  @override
  Future<void> disconnect({bool suppressLWT = true}) async {
    _reconnectTimer?.cancel();
    _updateConnectionState(ConnectionState.disconnecting);

    if (suppressLWT) {
      // Clear LWT before disconnecting for graceful shutdown
      _client.connectionMessage = MqttConnectMessage().startClean();
    }

    _client.disconnect();
    _updateConnectionState(ConnectionState.disconnected);
  }

  @override
  Future<void> publish(
    String topic,
    String payload, {
    bool forceQoS1 = true,
    bool forceRetainFalse = true,
  }) async {
    final message = _QueuedMessage(
      topic: topic,
      payload: payload,
      qos: forceQoS1 ? MqttQos.atLeastOnce : MqttQos.atMostOnce,
      retain: forceRetainFalse ? false : true,
    );

    if (_currentState != ConnectionState.connected) {
      // Queue message for later delivery
      _messageQueue.add(message);
      return;
    }

    _publishMessage(message);
  }

  /// Publish a single message immediately.
  void _publishMessage(_QueuedMessage message) {
    final builder = MqttClientPayloadBuilder();
    builder.addString(message.payload);

    _client.publishMessage(
      message.topic,
      message.qos,
      builder.payload!,
      retain: message.retain,
    );
  }

  /// Flush queued messages after reconnection.
  void _flushMessageQueue() {
    final messages = List<_QueuedMessage>.from(_messageQueue);
    _messageQueue.clear();

    for (final message in messages) {
      _publishMessage(message);
    }
  }

  @override
  Future<void> subscribe(
    String topic,
    void Function(String, String) handler,
  ) async {
    _subscriptions[topic] = handler;

    if (_currentState == ConnectionState.connected) {
      final subscription = _client.subscribe(topic, MqttQos.atLeastOnce);

      // Log warning if broker downgrades to QoS 0
      if (subscription?.qos == MqttQos.atMostOnce) {
        // Use a proper logging framework in production
        // ignore: avoid_print
        print(
          'Warning: Broker downgraded subscription to QoS 0 for topic: $topic',
        );
      }
    }
  }

  @override
  Future<void> unsubscribe(String topic) async {
    _subscriptions.remove(topic);

    if (_currentState == ConnectionState.connected) {
      _client.unsubscribe(topic);
    }
  }

  /// Handle successful connection.
  void _onConnected() {
    _updateConnectionState(ConnectionState.connected);
    _reestablishSubscriptions();
    _flushMessageQueue();
  }

  /// Handle disconnection.
  void _onDisconnected() {
    if (_currentState != ConnectionState.disconnecting) {
      // Unexpected disconnection - schedule reconnect
      _updateConnectionState(ConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  /// Re-establish subscriptions after reconnection.
  void _reestablishSubscriptions() {
    for (final topic in _subscriptions.keys) {
      _client.subscribe(topic, MqttQos.atLeastOnce);
    }
  }

  /// Handle subscription confirmation.
  void _onSubscribed(String topic) {
    // Subscription confirmed
  }

  /// Handle unsubscription confirmation.
  void _onUnsubscribed(String? topic) {
    // Unsubscription confirmed
  }

  /// Handle incoming messages.
  void _onMessageReceived(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final receivedMessage in messages) {
      final topic = receivedMessage.topic;
      final message = receivedMessage.payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(
        message.payload.message,
      );

      final handler = _subscriptions[topic];
      if (handler != null) {
        handler(topic, payload);
      }
    }
  }

  /// Update connection state and notify listeners.
  void _updateConnectionState(ConnectionState newState) {
    if (_currentState != newState) {
      _currentState = newState;
      _connectionStateController.add(newState);
    }
  }

  /// Dispose resources.
  Future<void> dispose() async {
    _reconnectTimer?.cancel();
    if (!_connectionStateController.isClosed) {
      await _connectionStateController.close();
    }
    _client.disconnect();
  }
}

/// Internal class for queuing messages during disconnection.
class _QueuedMessage {
  final String topic;
  final String payload;
  final MqttQos qos;
  final bool retain;

  const _QueuedMessage({
    required this.topic,
    required this.payload,
    required this.qos,
    required this.retain,
  });
}
