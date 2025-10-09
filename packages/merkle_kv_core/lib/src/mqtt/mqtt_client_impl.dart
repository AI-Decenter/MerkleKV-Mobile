import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../config/merkle_kv_config.dart';
import '../config/mqtt_security_config.dart';
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
  // Support multiple handlers per topic filter to avoid overwriting
  final Map<String, List<void Function(String, String)>> _subscriptions = {};
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>?
    _updatesSubscription;

  ConnectionState _currentState = ConnectionState.disconnected;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  String? _lastTlsError;

  /// Creates an MQTT client implementation with the provided configuration.
  MqttClientImpl(this._config) {
    _initializeClient();
  }

  @override
  Stream<ConnectionState> get connectionState =>
      _connectionStateController.stream;

  @override
  ConnectionState get currentConnectionState => _currentState;

  /// Initialize the MQTT client with configuration settings.
  void _initializeClient() {
    _client = MqttServerClient(_config.mqttHost, _config.clientId);

    // Configure connection settings per Locked Spec §6
    _client.keepAlivePeriod = _config.keepAliveSeconds;
    _client.autoReconnect = false; // We handle reconnection manually
    _client.logging(on: false); // Prevent credential logging

    // Note: Credentials without TLS are allowed. Security warnings are
    // emitted at configuration build time via MerkleKVConfig.

    // Apply TLS/security configuration
    final sec = _config.mqttSecurity;
    if (_config.mqttUseTls || (sec?.enableTLS ?? false)) {
      _client.secure = true;
      _client.port = _config.mqttPort;

      // Configure SecurityContext if CA and/or client certs are provided
      final context = SecurityContext.defaultContext;
      try {
        if (sec?.caCertPath != null && sec!.caCertPath!.isNotEmpty) {
          context.setTrustedCertificates(sec.caCertPath!);
        }
        if (sec?.authMethod == AuthenticationMethod.clientCertificate) {
          if ((sec?.clientCertPath?.isNotEmpty ?? false) &&
              (sec?.clientKeyPath?.isNotEmpty ?? false)) {
            context.useCertificateChain(sec!.clientCertPath!);
            if (sec.clientKeyPassword != null) {
              context.usePrivateKey(sec.clientKeyPath!,
                  password: sec.clientKeyPassword);
            } else {
              context.usePrivateKey(sec.clientKeyPath!);
            }
          }
        }
      } catch (e) {
        // TLS SecurityContext setup failed; classification will occur later.
        // Intentionally avoid printing secrets to stdout in library code.
      }

      // Enforce strict certificate validation by default
      _client.onBadCertificate = (Object certificate) {
        // Basic expiry check for better error specificity
        if (certificate is X509Certificate) {
          final now = DateTime.now().toUtc();
          final notAfter = certificate.endValidity;
          if (notAfter.isBefore(now)) {
            _lastTlsError = 'certificate expired';
          }
          // We cannot reliably parse SAN in Dart's X509Certificate;
          // rely on platform validation for hostname/SAN. If the subject CN
          // is clearly mismatched to the host, set a hint (best-effort).
          final subj = certificate.subject;
          if (subj.isNotEmpty && _config.mqttHost.isNotEmpty) {
            final cnMatch = RegExp(r'CN=([^,]+)').firstMatch(subj);
            if (cnMatch != null) {
              final cn = cnMatch.group(1) ?? '';
              if (!_hostMatchesPattern(_config.mqttHost, cn)) {
                _lastTlsError ??= 'hostname validation failed';
              }
            }
          }
        }
        // Reject by default; never bypass validation here.
        return false;
      };
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

    // Message handler will be attached on successful connection in _onConnected.
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
      timeoutTimer =
          Timer(Duration(seconds: _config.connectionTimeoutSeconds), () {
        if (!connectionCompleter.isCompleted) {
          connectionCompleter.completeError(Exception(
              'Connection timeout after ${_config.connectionTimeoutSeconds} seconds'));
        }
      });

      // Handle authentication
      if (_config.username != null || _config.password != null) {
        // Support username-only or password-only scenarios. The mqtt_client
        // package accepts optional username/password; passing null for the
        // missing field allows brokers that accept single-credential auth
        // (e.g., token-only in password).
        _client
            .connect(_config.username, _config.password)
            .then((status) {
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
        if (_lastTlsError != null) {
          final err = _lastTlsError!;
          _lastTlsError = null;
          throw Exception(err);
        }
        throw Exception('Connection failed: ${status?.state}');
      }
    } on SocketException catch (e) {
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      final msg = e.toString();
      // Map last TLS error first if set (e may be a generic handshake failure)
      if (_lastTlsError != null) {
        final err = _lastTlsError!;
        _lastTlsError = null;
        throw Exception(err);
      }
      if (msg.contains('authentication') || msg.contains('unauthorized')) {
        throw Exception('Authentication failed');
      }
      if (msg.contains('certificate') && msg.contains('expired')) {
        throw Exception('certificate expired');
      }
      if (msg.contains('CERTIFICATE_VERIFY_FAILED') ||
          msg.contains('CERTIFICATE_VERIFY_FAILED: certificate has expired')) {
        throw Exception('certificate chain validation failed');
      }
      if (msg.contains('wrong version number') ||
          msg.contains('protocol version') ||
          msg.contains('TLSV1_ALERT_PROTOCOL_VERSION')) {
        throw Exception('TLS version too old');
      }
      if (msg.contains('hostname') ||
          msg.contains('Host name verification') ||
          msg.contains('certificate verify failed: Hostname mismatch')) {
        throw Exception('hostname validation failed');
      }
      if (msg.contains('SAN') || msg.contains('Subject Alternative Name')) {
        throw Exception('SAN validation failed');
      }
      if (msg.contains('timeout')) {
        // Treat connection timeouts as network errors and reflect configured timeout
        throw Exception(
            'Network error: Connection timeout after ${_config.connectionTimeoutSeconds} seconds');
      }
      throw Exception('MQTT error: $msg');
    }
  }

  // Best-effort hostname wildcard matching (supports "*.example.com").
  bool _hostMatchesPattern(String host, String pattern) {
    if (pattern == host) return true;
    if (pattern.startsWith('*.')) {
      // '*.example.com' should match 'api.example.com' and 'a.b.example.com',
      // but not 'example.com'. Ensure suffix match at label boundary and at
      // least one additional label before the suffix.
      final suffix = pattern.substring(1); // '.example.com'
      if (!host.endsWith(suffix)) return false;

      final hostSegments = host.split('.');
      final patternTail = pattern.substring(2); // 'example.com'
      final patternSegments = patternTail.split('.');
      // Host must have at least one segment before the suffix
      return hostSegments.length >= patternSegments.length + 1;
    }
    return false;
  }

  /// Classify low-level TLS/handshake errors into stable, user-facing messages.
  static String classifyTlsError(String raw) {
    final msg = raw;
    if (msg.contains('certificate') && msg.contains('expired')) {
      return 'certificate expired';
    }
    if (msg.contains('CERTIFICATE_VERIFY_FAILED')) {
      return 'certificate chain validation failed';
    }
    if (msg.contains('wrong version number') ||
        msg.contains('protocol version') ||
        msg.contains('TLSV1_ALERT_PROTOCOL_VERSION') ||
        msg.contains('unsupported protocol')) {
      return 'TLS version too old';
    }
    if (msg.contains('Hostname mismatch') ||
        msg.contains('Host name verification') ||
        msg.contains('certificate verify failed: Hostname mismatch')) {
      return 'hostname validation failed';
    }
    if (msg.contains('SAN') || msg.contains('Subject Alternative Name')) {
      return 'SAN validation failed';
    }
    return 'MQTT error: $msg';
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
    final handlers =
        _subscriptions.putIfAbsent(topic, () => <void Function(String, String)>[]);
    handlers.add(handler);

    if (_currentState == ConnectionState.connected) {
      // Only subscribe at broker level the first time this topic filter is added
      if (handlers.length == 1) {
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
  }

  @override
  Future<void> unsubscribe(String topic) async {
    final removed = _subscriptions.remove(topic);

    if (_currentState == ConnectionState.connected && removed != null) {
      _client.unsubscribe(topic);
    }
  }

  /// Handle successful connection.
  void _onConnected() {
    _updateConnectionState(ConnectionState.connected);
    // Attach updates listener once connected (updates may be null before connect)
    _updatesSubscription ??= _client.updates?.listen(_onMessageReceived);
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

      // Dispatch to all handlers whose subscription filter matches this topic
      // Supports MQTT wildcards: '+' (single level) and '#' (multi-level at end)
      _subscriptions.forEach((filter, handlers) {
        if (_topicMatches(filter, topic)) {
          // Copy to avoid concurrent modification if a handler unsubscribes
          for (final handler in List.from(handlers)) {
            handler(topic, payload);
          }
        }
      });
    }
  }

  /// Determines whether a topic filter matches a concrete topic name per MQTT rules.
  /// - '+' matches exactly one level
  /// - '#' matches any number of levels and must be the last level
  bool _topicMatches(String filter, String topic) {
    if (filter == topic) return true;

    final fParts = filter.split('/');
    final tParts = topic.split('/');

    int fi = 0;
    int ti = 0;

    while (fi < fParts.length && ti < tParts.length) {
      final f = fParts[fi];
      if (f == '#') {
        // '#' must be last in filter; it matches the rest of the topic
        return fi == fParts.length - 1;
      }
      if (f == '+') {
        // '+' matches exactly one level
        fi++;
        ti++;
        continue;
      }
      if (f != tParts[ti]) {
        return false;
      }
      fi++;
      ti++;
    }

    // If filter has remaining parts
    if (fi < fParts.length) {
      // Only valid remaining part can be a terminal '#'
      return fi == fParts.length - 1 && fParts[fi] == '#';
    }

    // If topic has remaining parts, filter must have ended with '#'
    return ti == tParts.length;
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
    await _updatesSubscription?.cancel();
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
