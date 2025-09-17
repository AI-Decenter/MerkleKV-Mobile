import 'dart:async';
import 'dart:math' as math;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

/// Connectivity Simulator for Mobile Testing
/// 
/// Simulates various network connectivity scenarios including airplane mode,
/// network transitions, poor connectivity, and intermittent connections.
class ConnectivitySimulator {
  final StreamController<ConnectivityResult> _connectivityController = 
      StreamController<ConnectivityResult>.broadcast();
  
  ConnectivityResult _currentConnectivity = ConnectivityResult.wifi;
  Duration _latencyDelay = Duration.zero;
  bool _isDisposed = false;
  Timer? _intermittentTimer;

  /// Current connectivity stream
  Stream<ConnectivityResult> get onConnectivityChanged => 
      _connectivityController.stream;

  /// Current connectivity result
  ConnectivityResult get connectivity => _currentConnectivity;

  /// Simulates connectivity change (e.g., airplane mode, WiFi to cellular)
  Future<void> simulateConnectivityChange(ConnectivityResult newConnectivity) async {
    if (_isDisposed) return;

    _currentConnectivity = newConnectivity;
    _connectivityController.add(newConnectivity);
    
    // Add realistic delay for connectivity changes
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// Simulates network latency
  Future<void> simulateLatency(Duration latency) async {
    if (_isDisposed) return;

    _latencyDelay = latency;
    
    // In real network operations, this delay would be applied
    await Future.delayed(const Duration(milliseconds: 100));
  }

  /// Simulates intermittent connectivity
  Future<void> simulateIntermittentConnectivity({
    required Duration disconnectDuration,
    required int intervals,
  }) async {
    if (_isDisposed) return;

    final originalConnectivity = _currentConnectivity;
    
    for (int i = 0; i < intervals; i++) {
      // Disconnect
      await simulateConnectivityChange(ConnectivityResult.none);
      await Future.delayed(disconnectDuration);
      
      // Reconnect
      await simulateConnectivityChange(originalConnectivity);
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Simulates poor network conditions with packet loss
  Future<void> simulatePoorConnectivity({
    Duration latency = const Duration(milliseconds: 1000),
    double packetLossRate = 0.1, // 10% packet loss
  }) async {
    if (_isDisposed) return;

    _latencyDelay = latency;
    
    // Simulate packet loss by randomly failing operations
    final random = math.Random();
    if (random.nextDouble() < packetLossRate) {
      // Simulate temporary disconnection for packet loss
      await simulateConnectivityChange(ConnectivityResult.none);
      await Future.delayed(const Duration(milliseconds: 100));
      await simulateConnectivityChange(_currentConnectivity);
    }
  }

  /// Applies current latency delay to operations
  Future<void> applyLatencyDelay() async {
    if (_latencyDelay > Duration.zero) {
      await Future.delayed(_latencyDelay);
    }
  }

  /// Checks if currently connected
  bool get isConnected => _currentConnectivity != ConnectivityResult.none;

  /// Gets connection type string
  String get connectionType {
    switch (_currentConnectivity) {
      case ConnectivityResult.wifi:
        return 'WiFi';
      case ConnectivityResult.mobile:
        return 'Cellular';
      case ConnectivityResult.ethernet:
        return 'Ethernet';
      case ConnectivityResult.bluetooth:
        return 'Bluetooth';
      case ConnectivityResult.vpn:
        return 'VPN';
      case ConnectivityResult.other:
        return 'Other';
      case ConnectivityResult.none:
        return 'None';
    }
  }

  /// Disposes resources
  Future<void> dispose() async {
    _isDisposed = true;
    _intermittentTimer?.cancel();
    await _connectivityController.close();
  }
}