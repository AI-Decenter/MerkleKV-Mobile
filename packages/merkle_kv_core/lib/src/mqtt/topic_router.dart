import 'dart:async';
import 'dart:developer' as developer;

import '../config/merkle_kv_config.dart';
import 'connection_state.dart';
import 'mqtt_client_interface.dart';
import 'topic_scheme.dart';
import 'topic_validator.dart';
import 'topic_authorization.dart';

/// Abstract interface for topic-based message routing.
///
/// Manages subscribe/publish operations for command, response, and replication
/// topics with automatic re-subscription after reconnect.
abstract class TopicRouter {
  /// Subscribe to command messages for this client.
  ///
  /// [handler] - Callback function (topic, payload) => void
  Future<void> subscribeToCommands(void Function(String, String) handler);

  /// Subscribe to replication messages for all devices.
  ///
  /// [handler] - Callback function (topic, payload) => void
  Future<void> subscribeToReplication(void Function(String, String) handler);

  /// Publish a command message to target client.
  ///
  /// [targetClientId] - Target client identifier
  /// [payload] - Message payload
  Future<void> publishCommand(String targetClientId, String payload);

  /// Publish a response message from this client.
  ///
  /// [payload] - Response payload
  Future<void> publishResponse(String payload);

  /// Publish a replication event for all devices.
  ///
  /// [payload] - Replication event payload
  Future<void> publishReplication(String payload);

  /// Dispose resources and clean up subscriptions.
  Future<void> dispose();
}

/// Default implementation of [TopicRouter] using MQTT client.
///
/// Provides topic management with validation, QoS enforcement, and automatic
/// re-subscription after reconnection events.
class TopicRouterImpl implements TopicRouter {
  final MerkleKVConfig _config;
  final MqttClientInterface _mqttClient;
  final TopicScheme _topicScheme;

  // Active subscription handlers
  void Function(String, String)? _commandHandler;
  void Function(String, String)? _replicationHandler;

  // Connection state monitoring
  StreamSubscription<ConnectionState>? _connectionSubscription;

  /// Creates a TopicRouter with the provided configuration and MQTT client.
  TopicRouterImpl(MerkleKVConfig config, this._mqttClient)
    : _config = config,
      _topicScheme = TopicScheme.create(config.topicPrefix, config.clientId) {
    _initializeConnectionMonitoring();
  }

  /// Initialize connection state monitoring for auto re-subscription.
  void _initializeConnectionMonitoring() {
    _connectionSubscription = _mqttClient.connectionState.listen((state) {
      if (state == ConnectionState.connected) {
        _restoreSubscriptions();
      }
    });
  }

  /// Restore active subscriptions after reconnection.
  Future<void> _restoreSubscriptions() async {
    developer.log(
      'Restoring subscriptions after reconnection',
      name: 'TopicRouter',
      level: 800, // INFO
    );

    // Re-subscribe to commands if handler is active
    if (_commandHandler != null) {
      TopicAuthorization.checkSubscribe(
        _config,
        _topicScheme.commandTopic,
      );
      await _mqttClient.subscribe(_topicScheme.commandTopic, _commandHandler!);
      developer.log(
        'Restored command subscription: ${_topicScheme.commandTopic}',
        name: 'TopicRouter',
        level: 800, // INFO
      );
    }

    // Re-subscribe to replication if handler is active
    if (_replicationHandler != null) {
      TopicAuthorization.checkSubscribe(
        _config,
        _topicScheme.replicationTopic,
      );
      await _mqttClient.subscribe(
        _topicScheme.replicationTopic,
        _replicationHandler!,
      );
      developer.log(
        'Restored replication subscription: ${_topicScheme.replicationTopic}',
        name: 'TopicRouter',
        level: 800, // INFO
      );
    }
  }

  @override
  Future<void> subscribeToCommands(
    void Function(String, String) handler,
  ) async {
    _commandHandler = handler;
    TopicAuthorization.checkSubscribe(
      _config,
      _topicScheme.commandTopic,
    );
    await _mqttClient.subscribe(_topicScheme.commandTopic, handler);

    developer.log(
      'Subscribed to commands: ${_topicScheme.commandTopic}',
      name: 'TopicRouter',
      level: 800, // INFO
    );
  }

  @override
  Future<void> subscribeToReplication(
    void Function(String, String) handler,
  ) async {
    _replicationHandler = handler;
    TopicAuthorization.checkSubscribe(
      _config,
      _topicScheme.replicationTopic,
    );
    await _mqttClient.subscribe(_topicScheme.replicationTopic, handler);

    developer.log(
      'Subscribed to replication: ${_topicScheme.replicationTopic}',
      name: 'TopicRouter',
      level: 800, // INFO
    );
  }

  @override
  Future<void> publishCommand(String targetClientId, String payload) async {
    // Use TopicValidator for enhanced validation and consistent topic building
    final targetTopic = TopicValidator.buildCommandTopic(
      _topicScheme.prefix, 
      targetClientId,
    );

    TopicAuthorization.checkPublish(
      _config,
      targetTopic,
    );
    await _mqttClient.publish(targetTopic, payload, forceQoS1: true, forceRetainFalse: true);

    developer.log(
      'Published command to $targetTopic (${payload.length} bytes)',
      name: 'TopicRouter',
      level: 800, // INFO
    );
  }

  @override
  Future<void> publishResponse(String payload) async {
    TopicAuthorization.checkPublish(
      _config,
      _topicScheme.responseTopic,
    );
    await _mqttClient.publish(_topicScheme.responseTopic, payload, forceQoS1: true, forceRetainFalse: true);

    developer.log(
      'Published response to ${_topicScheme.responseTopic} (${payload.length} bytes)',
      name: 'TopicRouter',
      level: 800, // INFO
    );
  }

  @override
  Future<void> publishReplication(String payload) async {
    TopicAuthorization.checkPublish(
      _config,
      _topicScheme.replicationTopic,
    );
    await _mqttClient.publish(_topicScheme.replicationTopic, payload, forceQoS1: true, forceRetainFalse: true);

    developer.log(
      'Published replication to ${_topicScheme.replicationTopic} (${payload.length} bytes)',
      name: 'TopicRouter',
      level: 800, // INFO
    );
  }

  @override
  Future<void> dispose() async {
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _commandHandler = null;
    _replicationHandler = null;

    developer.log(
      'TopicRouter disposed',
      name: 'TopicRouter',
      level: 800, // INFO
    );
  }
}
