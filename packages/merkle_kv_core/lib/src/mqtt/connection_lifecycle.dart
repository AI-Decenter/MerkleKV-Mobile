import 'dart:async';

import 'package:meta/meta.dart';

import '../config/merkle_kv_config.dart';
import '../replication/metrics.dart';
import 'connection_logger.dart';
import 'connection_state.dart';
import 'mqtt_client_interface.dart';

/// Application lifecycle states for platform integration.
enum AppLifecycleState {
  /// The application is resumed and has input focus.
  resumed,
  
  /// The application is in an inactive state and is not receiving user input.
  inactive,
  
  /// The application is not currently visible to the user, 
  /// not responding to user input, and running in the background.
  paused,
  
  /// The application is still hosted on a flutter engine but
  /// is detached from any host views.
  detached,
  
  /// The application is hidden and cannot be seen by the user.
  hidden,
}

/// Detailed connection state with additional event information.
class ConnectionStateEvent {
  final ConnectionState state;
  final DateTime timestamp;
  final String? reason;
  final Exception? error;

  const ConnectionStateEvent({
    required this.state,
    required this.timestamp,
    this.reason,
    this.error,
  });

  @override
  String toString() => 
      'ConnectionStateEvent(state: $state, timestamp: $timestamp, reason: $reason, error: $error)';
}

/// Disconnection reasons for observability.
enum DisconnectionReason {
  manual,
  timeout,
  brokerClose,
  networkError,
  authFailure,
  configChange,
  appLifecycle,
}

/// Abstract interface for MQTT connection lifecycle management.
///
/// Provides comprehensive connection management including graceful connection
/// establishment, clean disconnection with Last Will and Testament (LWT) 
/// suppression, connection state monitoring, and proper resource cleanup.
abstract class ConnectionLifecycleManager {
  /// Connect to the MQTT broker with proper handshake.
  ///
  /// Establishes connection with configured parameters (clientId, cleanStart,
  /// keepAlive, LWT, TLS if available). Emits Connecting → Connected states.
  /// 
  /// Throws [Exception] if connection fails after configured retries.
  Future<void> connect();

  /// Gracefully disconnect from the MQTT broker.
  ///
  /// [suppressLWT] - If true, clears Last Will and Testament before 
  /// disconnecting to prevent false offline signals. Defaults to true.
  /// 
  /// Performs clean MQTT DISCONNECT and emits Disconnecting → Disconnected.
  Future<void> disconnect({bool suppressLWT = true});

  /// Handle application lifecycle state changes.
  ///
  /// [state] - Current application lifecycle state (resumed, paused, etc.)
  /// 
  /// On backgrounding: maintains or gracefully suspends connection (configurable).
  /// On resume: reconnects if needed.
  Future<void> handleAppStateChange(AppLifecycleState state);

  /// Stream of detailed connection state events.
  ///
  /// Emits [ConnectionStateEvent] with state, timestamp, reason, and error
  /// information for: connected, disconnected, error, reconnecting states.
  Stream<ConnectionStateEvent> get connectionState;

  /// Current connection status.
  ///
  /// Returns true if currently connected to the MQTT broker.
  bool get isConnected;

  /// Dispose resources and cleanup.
  ///
  /// Should be called when the lifecycle manager is no longer needed.
  Future<void> dispose();
}

/// Default implementation of [ConnectionLifecycleManager].
///
/// Provides comprehensive MQTT connection lifecycle management with proper
/// resource cleanup, state monitoring, and platform integration.
class DefaultConnectionLifecycleManager implements ConnectionLifecycleManager {
  final MerkleKVConfig _config;
  final MqttClientInterface _mqttClient;
  final ReplicationMetrics? _metrics;
  final ConnectionLogger _logger;
  final Duration _disconnectionTimeout;

  final StreamController<ConnectionStateEvent> _stateController =
      StreamController<ConnectionStateEvent>.broadcast();

  ConnectionState _currentState = ConnectionState.disconnected;
  DateTime? _connectionStartTime;
  Timer? _disconnectionTimeoutTimer;
  final List<StreamSubscription> _subscriptions = [];
  final Set<String> _activeSubscriptions = {};
  final List<Timer> _activeTimers = [];

  // Configuration for background behavior
  bool _maintainConnectionInBackground = true;
  ConnectionState? _stateBeforeBackground;

  /// Creates a connection lifecycle manager.
  ///
  /// [config] - MerkleKV configuration
  /// [mqttClient] - MQTT client implementation
  /// [metrics] - Optional metrics collector
  /// [logger] - Optional logger for connection events (defaults to console output)
  /// [disconnectionTimeout] - Timeout for disconnection operations (defaults to 10 seconds)
  DefaultConnectionLifecycleManager({
    required MerkleKVConfig config,
    required MqttClientInterface mqttClient,
    ReplicationMetrics? metrics,
    bool maintainConnectionInBackground = true,
    ConnectionLogger? logger,
    Duration? disconnectionTimeout,
  })  : _config = config,
        _mqttClient = mqttClient,
        _metrics = metrics,
        _logger = logger ?? const DefaultConnectionLogger(),
        _disconnectionTimeout = disconnectionTimeout ?? const Duration(seconds: 10),
        _maintainConnectionInBackground = maintainConnectionInBackground {
    _initializeStateMonitoring();
  }

  @override
  Stream<ConnectionStateEvent> get connectionState => _stateController.stream;

  @override
  bool get isConnected => _currentState == ConnectionState.connected;

  /// Get the configuration for subclass access.
  @protected
  MerkleKVConfig get config => _config;

  /// Get the MQTT client for subclass access.
  @protected
  MqttClientInterface get mqttClient => _mqttClient;

  /// Initialize connection state monitoring.
  void _initializeStateMonitoring() {
    // Monitor MQTT client state changes
    final subscription = _mqttClient.connectionState.listen((state) {
      _handleMqttStateChange(state);
    });
    _subscriptions.add(subscription);
  }

  @override
  Future<void> connect() async {
    if (_currentState == ConnectionState.connected ||
        _currentState == ConnectionState.connecting) {
      return;
    }

    _logger.info('Starting connection to ${_config.mqttHost}:${_config.mqttPort}');
    _connectionStartTime = DateTime.now();
    
    _updateState(
      ConnectionState.connecting,
      reason: 'Manual connection request',
    );

    try {
      // Use Future.timeout to properly handle connection timeouts
      await _mqttClient.connect().timeout(
        Duration(seconds: _config.keepAliveSeconds * 2),
        onTimeout: () {
          _handleConnectionTimeout();
          throw Exception('Connection timeout after ${_config.keepAliveSeconds * 2} seconds');
        },
      );
      
      final duration = DateTime.now().difference(_connectionStartTime!);
      _logger.info('Connected successfully in ${duration.inMilliseconds}ms');
      
      _metrics?.recordConnectionLifecycleEvent('connection_established');
      _metrics?.recordConnectionDurationMetric(duration.inSeconds.toDouble());
      
      _updateState(
        ConnectionState.connected,
        reason: 'Connection established successfully',
      );
    } catch (e) {
      final reason = _categorizeConnectionError(e);
      _logger.error('Connection failed: $reason', e);
      
      _metrics?.recordConnectionLifecycleEvent('connection_failed');
      _metrics?.recordDisconnectionReasonMetric(reason);
      
      _updateState(
        ConnectionState.disconnected,
        reason: 'Connection failed: $reason',
        error: e is Exception ? e : Exception(e.toString()),
      );
      
      rethrow;
    }
  }

  @override
  Future<void> disconnect({bool suppressLWT = true}) async {
    if (_currentState == ConnectionState.disconnected ||
        _currentState == ConnectionState.disconnecting) {
      return;
    }

    _logger.info('Starting graceful disconnection (suppressLWT: $suppressLWT)');
    
    _updateState(
      ConnectionState.disconnecting,
      reason: 'Manual disconnection request',
    );

    // Set disconnection timeout
    _disconnectionTimeoutTimer = Timer(
      _disconnectionTimeout,
      () => _handleDisconnectionTimeout(),
    );

    try {
      // Perform resource cleanup before disconnecting
      await _performResourceCleanup();
      
      if (suppressLWT) {
        _logger.debug('Suppressing Last Will and Testament');
        _metrics?.recordConnectionLifecycleEvent('lwt_suppressed');
      }

      await _mqttClient.disconnect(suppressLWT: suppressLWT);
      _disconnectionTimeoutTimer?.cancel();
      
      _logger.info('Disconnected successfully');
      _metrics?.recordConnectionLifecycleEvent('disconnection_completed');
      _metrics?.recordDisconnectionReasonMetric(DisconnectionReason.manual);
      
      _updateState(
        ConnectionState.disconnected,
        reason: 'Graceful disconnection completed',
      );
    } catch (e) {
      _disconnectionTimeoutTimer?.cancel();
      
      _logger.error('Disconnection error', e);
      _metrics?.recordConnectionLifecycleEvent('disconnection_failed');
      
      // Force state to disconnected even on error
      _updateState(
        ConnectionState.disconnected,
        reason: 'Disconnection completed with errors',
        error: e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  @override
  Future<void> handleAppStateChange(AppLifecycleState state) async {
    _logger.debug('App lifecycle state changed to: $state');
    
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        await _handleAppBackgrounding();
        break;
      case AppLifecycleState.resumed:
        await _handleAppResuming();
        break;
      case AppLifecycleState.inactive:
        // Handle brief inactive states (e.g., incoming call)
        break;
      case AppLifecycleState.hidden:
        // Handle hidden state (iOS specific)
        await _handleAppBackgrounding();
        break;
    }
  }

  /// Handle MQTT client state changes.
  void _handleMqttStateChange(ConnectionState state) {
    if (state != _currentState) {
      _logger.debug('MQTT client state changed: $_currentState → $state');
      
      switch (state) {
        case ConnectionState.connected:
          _updateState(state, reason: 'MQTT client connected');
          break;
        case ConnectionState.disconnected:
          _updateState(state, reason: 'MQTT client disconnected');
          break;
        case ConnectionState.connecting:
          _updateState(state, reason: 'MQTT client connecting');
          break;
        case ConnectionState.disconnecting:
          _updateState(state, reason: 'MQTT client disconnecting');
          break;
      }
    }
  }

  /// Handle app going to background.
  Future<void> _handleAppBackgrounding() async {
    _stateBeforeBackground = _currentState;
    
    _logger.debug('App backgrounding, maintain connection: $_maintainConnectionInBackground');
    _metrics?.recordConnectionLifecycleEvent('app_backgrounded');
    
    if (!_maintainConnectionInBackground && isConnected) {
      await disconnect(suppressLWT: true);
    }
  }

  /// Handle app resuming from background.
  Future<void> _handleAppResuming() async {
    _logger.debug('App resuming from background');
    _metrics?.recordConnectionLifecycleEvent('app_resumed');
    
    // Reconnect if we were connected before backgrounding
    if (_stateBeforeBackground == ConnectionState.connected && 
        !isConnected && 
        !_maintainConnectionInBackground) {
      try {
        await connect();
      } catch (e) {
        _logger.warn('Failed to reconnect on app resume: $e');
      }
    }
    
    _stateBeforeBackground = null;
  }

  /// Handle connection timeout.
  void _handleConnectionTimeout() {
    _logger.warn('Connection timeout reached');
    _metrics?.recordConnectionLifecycleEvent('connection_timeout');
    _metrics?.recordDisconnectionReasonMetric(DisconnectionReason.timeout);
    
    _updateState(
      ConnectionState.disconnected,
      reason: 'Connection timeout',
      error: Exception('Connection timeout after ${_config.keepAliveSeconds * 2} seconds'),
    );
  }

  /// Handle disconnection timeout.
  void _handleDisconnectionTimeout() {
    _logger.warn('Disconnection timeout reached');
    _metrics?.recordConnectionLifecycleEvent('disconnection_timeout');
    
    // Force disconnected state
    _updateState(
      ConnectionState.disconnected,
      reason: 'Disconnection timeout - forced',
      error: Exception('Disconnection timeout after 10 seconds'),
    );
  }

  /// Perform comprehensive resource cleanup.
  Future<void> _performResourceCleanup() async {
    _logger.debug('Performing resource cleanup');
    
    try {
      // Clean up active subscriptions
      final subscriptionCount = _activeSubscriptions.length;
      for (final topic in List.from(_activeSubscriptions)) {
        try {
          await _mqttClient.unsubscribe(topic);
          _activeSubscriptions.remove(topic);
        } catch (e) {
          _logger.warn('Failed to unsubscribe from $topic: $e');
        }
      }
      
      _metrics?.recordCleanupOperationMetric('subscriptions_cleaned', subscriptionCount);
      
      // Cancel active timers
      final timerCount = _activeTimers.length;
      for (final timer in _activeTimers) {
        timer.cancel();
      }
      _activeTimers.clear();
      
      _metrics?.recordCleanupOperationMetric('timers_canceled', timerCount);
      
      // Clear any authentication material from memory
      // (This would be handled by the MQTT client implementation)
      
      _logger.debug('Resource cleanup completed');
    } catch (e) {
      _logger.error('Error during resource cleanup', e);
      throw Exception('Resource cleanup failed: $e');
    }
  }

  /// Update connection state and emit event.
  void _updateState(
    ConnectionState newState, {
    String? reason,
    Exception? error,
  }) {
    _currentState = newState;
    
    final event = ConnectionStateEvent(
      state: newState,
      timestamp: DateTime.now(),
      reason: reason,
      error: error,
    );
    
    _stateController.add(event);
    _metrics?.recordConnectionStateChangeMetric(newState.toString());
    
    _logger.debug('State updated: ${event.state} - ${event.reason}');
  }

  /// Categorize connection errors for observability.
  DisconnectionReason _categorizeConnectionError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    if (errorString.contains('timeout')) {
      return DisconnectionReason.timeout;
    } else if (errorString.contains('authentication') || 
               errorString.contains('unauthorized')) {
      return DisconnectionReason.authFailure;
    } else if (errorString.contains('network') || 
               errorString.contains('socket')) {
      return DisconnectionReason.networkError;
    } else {
      return DisconnectionReason.brokerClose;
    }
  }

  @override
  Future<void> dispose() async {
    _logger.info('Disposing connection lifecycle manager');
    
    // Update state to disconnected if currently connected
    if (_currentState != ConnectionState.disconnected) {
      _updateState(
        ConnectionState.disconnected,
        reason: 'Manager disposed',
      );
    }
    
    // Cancel all timers
    _disconnectionTimeoutTimer?.cancel();
    for (final timer in _activeTimers) {
      timer.cancel();
    }
    
    // Cancel all subscriptions
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    
    // Close state controller
    await _stateController.close();
    
    _logger.info('Connection lifecycle manager disposed');
  }
}

/// Extension for metrics integration.
extension on ReplicationMetrics {
  /// Record connection lifecycle events for observability.
  void recordConnectionLifecycleEvent(String event) {
    // Record connection events - using existing application metrics for now
    // In a production implementation, you might add specific connection metrics
    switch (event) {
      case 'connection_established':
      case 'connection_failed':
      case 'disconnection_completed':
      case 'disconnection_failed':
      case 'connection_timeout':
      case 'disconnection_timeout':
      case 'lwt_suppressed':
      case 'app_backgrounded':
      case 'app_resumed':
        // These could be recorded as specific metrics if needed
        break;
    }
  }
  
  void recordConnectionDurationMetric(double seconds) {
    // Record connection establishment duration
    recordApplicationLatency((seconds * 1000).round());
  }
  
  void recordDisconnectionReasonMetric(DisconnectionReason reason) {
    // Record disconnection reasons for analysis
    switch (reason) {
      case DisconnectionReason.manual:
      case DisconnectionReason.timeout:
      case DisconnectionReason.brokerClose:
      case DisconnectionReason.networkError:
      case DisconnectionReason.authFailure:
      case DisconnectionReason.configChange:
      case DisconnectionReason.appLifecycle:
        // Could be tracked as specific disconnect reason metrics
        break;
    }
  }
  
  void recordConnectionStateChangeMetric(String state) {
    // Record state transitions
    recordApplicationLatency(1); // Simple counter for state changes
  }
  
  void recordCleanupOperationMetric(String operation, int count) {
    // Record resource cleanup operations
    recordApplicationLatency(count);
  }
}