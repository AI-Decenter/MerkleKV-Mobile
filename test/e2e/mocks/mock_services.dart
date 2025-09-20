import 'dart:async';
import 'dart:convert';
import 'dart:math';

/// Mock MQTT service for iOS E2E testing
/// Simulates actual MQTT broker behavior for testing purposes
class MockMQTTService {
  static final MockMQTTService _instance = MockMQTTService._internal();
  factory MockMQTTService() => _instance;
  MockMQTTService._internal();

  bool _isConnected = false;
  bool _isOnline = true;
  final Map<String, String> _data = {};
  final List<String> _operationQueue = [];
  final StreamController<Map<String, dynamic>> _statusController = StreamController.broadcast();
  
  // Connection state
  bool get isConnected => _isConnected && _isOnline;
  bool get isOnline => _isOnline;
  Map<String, String> get data => Map.from(_data);
  List<String> get operationQueue => List.from(_operationQueue);
  
  Stream<Map<String, dynamic>> get statusStream => _statusController.stream;

  /// Initialize MQTT service
  Future<void> initialize() async {
    await Future.delayed(Duration(milliseconds: 100));
    print('[MQTT] Service initialized');
  }

  /// Connect to MQTT broker
  Future<bool> connect() async {
    if (!_isOnline) {
      print('[MQTT] Cannot connect - network offline');
      return false;
    }
    
    await Future.delayed(Duration(milliseconds: 500));
    _isConnected = true;
    print('[MQTT] Connected to broker');
    
    _statusController.add({
      'event': 'connected',
      'timestamp': DateTime.now().toIso8601String(),
    });
    
    return true;
  }

  /// Disconnect from MQTT broker
  Future<void> disconnect() async {
    await Future.delayed(Duration(milliseconds: 200));
    _isConnected = false;
    print('[MQTT] Disconnected from broker');
    
    _statusController.add({
      'event': 'disconnected',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Set network state
  void setNetworkState(bool online) {
    final wasConnected = _isConnected;
    _isOnline = online;
    
    if (!online && _isConnected) {
      _isConnected = false;
      print('[MQTT] Network offline - connection lost');
      _statusController.add({
        'event': 'network_offline',
        'timestamp': DateTime.now().toIso8601String(),
      });
    } else if (online && !_isConnected && wasConnected) {
      // Auto-reconnect when network comes back
      Timer(Duration(milliseconds: 500), () {
        connect();
      });
    }
  }

  /// Execute SET operation
  Future<bool> set(String key, String value) async {
    if (!isConnected) {
      _operationQueue.add('SET $key $value');
      print('[MQTT] Operation queued (offline): SET $key $value');
      return false;
    }
    
    await Future.delayed(Duration(milliseconds: 100));
    _data[key] = value;
    print('[MQTT] SET operation completed: $key = $value');
    return true;
  }

  /// Execute GET operation
  Future<String?> get(String key) async {
    if (!isConnected) {
      print('[MQTT] Cannot GET $key - not connected');
      return null;
    }
    
    await Future.delayed(Duration(milliseconds: 50));
    final value = _data[key];
    print('[MQTT] GET operation completed: $key = $value');
    return value;
  }

  /// Process queued operations
  Future<int> processQueue() async {
    if (!isConnected) {
      print('[MQTT] Cannot process queue - not connected');
      return 0;
    }
    
    final queueSize = _operationQueue.length;
    print('[MQTT] Processing ${queueSize} queued operations');
    
    for (final operation in List.from(_operationQueue)) {
      final parts = operation.split(' ');
      if (parts.length >= 3 && parts[0] == 'SET') {
        final key = parts[1];
        final value = parts.sublist(2).join(' ');
        await set(key, value);
      }
    }
    
    _operationQueue.clear();
    print('[MQTT] Queue processing completed');
    return queueSize;
  }

  /// Verify convergence state
  Future<bool> verifyConvergence({Duration maxWait = const Duration(seconds: 30)}) async {
    if (!isConnected) {
      print('[MQTT] Cannot verify convergence - not connected');
      return false;
    }
    
    print('[MQTT] Verifying convergence (max wait: ${maxWait.inSeconds}s)');
    await Future.delayed(Duration(milliseconds: 500));
    
    // Simulate convergence check
    final convergenceTime = Duration(milliseconds: Random().nextInt(2000) + 500);
    await Future.delayed(convergenceTime);
    
    print('[MQTT] Convergence verified in ${convergenceTime.inMilliseconds}ms');
    return true;
  }

  /// Get service statistics
  Map<String, dynamic> getStats() {
    return {
      'connected': _isConnected,
      'online': _isOnline,
      'dataCount': _data.length,
      'queueSize': _operationQueue.length,
      'keys': _data.keys.toList(),
    };
  }

  /// Reset service state
  void reset() {
    _isConnected = false;
    _isOnline = true;
    _data.clear();
    _operationQueue.clear();
    print('[MQTT] Service reset');
  }

  /// Cleanup resources
  void dispose() {
    _statusController.close();
  }
}

/// Mock iOS Simulator Controller for testing
class MockiOSSimulatorController {
  static final MockiOSSimulatorController _instance = MockiOSSimulatorController._internal();
  factory MockiOSSimulatorController() => _instance;
  MockiOSSimulatorController._internal();

  // Simulator state
  bool _backgroundAppRefreshEnabled = true;
  bool _lowPowerModeEnabled = false;
  bool _wifiEnabled = true;
  bool _cellularEnabled = true;
  bool _vpnEnabled = false;
  String _networkType = 'wifi';
  bool _notificationsEnabled = true;
  int _memoryUsage = 50; // Percentage

  // Getters
  bool get backgroundAppRefreshEnabled => _backgroundAppRefreshEnabled;
  bool get lowPowerModeEnabled => _lowPowerModeEnabled;
  bool get wifiEnabled => _wifiEnabled;
  bool get cellularEnabled => _cellularEnabled;
  bool get vpnEnabled => _vpnEnabled;
  String get networkType => _networkType;
  bool get notificationsEnabled => _notificationsEnabled;
  int get memoryUsage => _memoryUsage;
  
  /// Get current network state
  Map<String, bool> get networkState => {
    'wifi': _wifiEnabled,
    'cellular': _cellularEnabled,
  };
  
  /// Get cellular data restriction status
  bool get cellularDataRestricted => !_cellularEnabled;
  
  /// Get VPN configuration
  Map<String, dynamic> get vpnConfiguration => {
    'enabled': _vpnEnabled,
    'type': _vpnEnabled ? 'vpn' : 'none',
  };

  /// Set Background App Refresh state
  Future<void> setBackgroundAppRefresh(bool enabled) async {
    await Future.delayed(Duration(milliseconds: 200));
    _backgroundAppRefreshEnabled = enabled;
    print('[iOS] Background App Refresh ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Set Low Power Mode state
  Future<void> setLowPowerMode(bool enabled) async {
    await Future.delayed(Duration(milliseconds: 300));
    _lowPowerModeEnabled = enabled;
    if (enabled) {
      // Low Power Mode typically disables background refresh
      _backgroundAppRefreshEnabled = false;
    }
    print('[iOS] Low Power Mode ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Set network state
  Future<void> setNetworkState({bool? wifi, bool? cellular, String? type}) async {
    await Future.delayed(Duration(milliseconds: 400));
    
    if (wifi != null) {
      _wifiEnabled = wifi;
      print('[iOS] WiFi ${wifi ? 'enabled' : 'disabled'}');
    }
    
    if (cellular != null) {
      _cellularEnabled = cellular;
      print('[iOS] Cellular ${cellular ? 'enabled' : 'disabled'}');
    }
    
    if (type != null) {
      _networkType = type;
      print('[iOS] Network type changed to: $type');
    }

    // Update MQTT service network state
    final networkOnline = (_wifiEnabled || _cellularEnabled) && !_vpnTransitioning;
    MockMQTTService().setNetworkState(networkOnline);
  }

  bool _vpnTransitioning = false;

  /// Enable/disable VPN
  Future<void> setVPNState(bool enabled) async {
    _vpnTransitioning = true;
    await Future.delayed(Duration(milliseconds: 800)); // VPN takes longer
    
    _vpnEnabled = enabled;
    _vpnTransitioning = false;
    
    if (enabled) {
      _networkType = 'vpn';
    } else {
      _networkType = _wifiEnabled ? 'wifi' : 'cellular';
    }
    
    print('[iOS] VPN ${enabled ? 'connected' : 'disconnected'}');
    
    // VPN changes can briefly interrupt connectivity
    MockMQTTService().setNetworkState(false);
    await Future.delayed(Duration(milliseconds: 300));
    MockMQTTService().setNetworkState(true);
  }
  
  /// Set cellular data restriction
  Future<void> setCellularDataRestriction(bool restricted) async {
    await Future.delayed(Duration(milliseconds: 200));
    if (restricted) {
      _cellularEnabled = false;
      print('[iOS] Cellular data restricted');
    } else {
      _cellularEnabled = true;
      print('[iOS] Cellular data unrestricted');
    }
    
    // Update network state
    final networkOnline = (_wifiEnabled || _cellularEnabled) && !_vpnTransitioning;
    MockMQTTService().setNetworkState(networkOnline);
  }
  
  /// Configure VPN settings
  Future<void> setVPNConfiguration({bool? enabled, String? type}) async {
    if (enabled != null) {
      await setVPNState(enabled);
    }
    print('[iOS] VPN configuration updated');
  }

  /// Simulate memory warning
  Future<void> simulateMemoryWarning({String severity = 'moderate'}) async {
    await Future.delayed(Duration(milliseconds: 100));
    
    switch (severity) {
      case 'low':
        _memoryUsage = 75;
        break;
      case 'moderate':
        _memoryUsage = 85;
        break;
      case 'high':
        _memoryUsage = 95;
        break;
    }
    
    print('[iOS] Memory warning simulated (${severity}, usage: ${_memoryUsage}%)');
  }

  /// Trigger notification
  Future<void> triggerNotification({
    String title = 'Test Notification',
    String body = 'Test notification body',
  }) async {
    if (!_notificationsEnabled) {
      print('[iOS] Notification blocked - notifications disabled');
      return;
    }
    
    await Future.delayed(Duration(milliseconds: 150));
    print('[iOS] Notification triggered: $title - $body');
  }

  /// Simulate app backgrounding
  Future<void> moveAppToBackground({Duration duration = const Duration(minutes: 1)}) async {
    print('[iOS] Moving app to background for ${duration.inSeconds}s');
    await Future.delayed(Duration(milliseconds: 200));
    
    // If BAR is disabled, disconnect MQTT
    if (!_backgroundAppRefreshEnabled) {
      MockMQTTService().setNetworkState(false);
      print('[iOS] App suspended due to disabled Background App Refresh');
    }
    
    // Simulate background duration
    await Future.delayed(duration);
  }

  /// Simulate app foregrounding
  Future<void> moveAppToForeground() async {
    print('[iOS] Moving app to foreground');
    await Future.delayed(Duration(milliseconds: 300));
    
    // Restore network connectivity
    final networkOnline = _wifiEnabled || _cellularEnabled;
    MockMQTTService().setNetworkState(networkOnline);
    
    print('[iOS] App returned to foreground');
  }

  /// Get simulator state
  Map<String, dynamic> getState() {
    return {
      'backgroundAppRefresh': _backgroundAppRefreshEnabled,
      'lowPowerMode': _lowPowerModeEnabled,
      'wifi': _wifiEnabled,
      'cellular': _cellularEnabled,
      'vpn': _vpnEnabled,
      'networkType': _networkType,
      'notifications': _notificationsEnabled,
      'memoryUsage': _memoryUsage,
    };
  }

  /// Reset simulator to default state
  void reset() {
    _backgroundAppRefreshEnabled = true;
    _lowPowerModeEnabled = false;
    _wifiEnabled = true;
    _cellularEnabled = true;
    _vpnEnabled = false;
    _networkType = 'wifi';
    _notificationsEnabled = true;
    _memoryUsage = 50;
    print('[iOS] Simulator reset to default state');
  }
}