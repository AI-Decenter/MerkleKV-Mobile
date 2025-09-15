import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';

import 'mobile_test_harness.dart';
import 'connectivity_simulator.dart';

/// Multi-Device Simulator for Mobile Testing
/// 
/// Simulates complex multi-device scenarios including device clusters,
/// network partitions, and mixed mobile/desktop environments.
class MultiDeviceSimulator {
  final MobileTestHarness _testHarness = MobileTestHarness();
  final List<dynamic> _managedClients = [];
  final Map<dynamic, ConnectivitySimulator> _clientConnectivity = {};
  final List<NetworkPartition> _activePartitions = [];
  
  bool _isDisposed = false;

  /// Creates a desktop client (simulated non-mobile device)
  Future<dynamic> createDesktopClient(MerkleKVConfig config) async {
    if (_isDisposed) return null;

    final client = await _testHarness.createClient(config);
    _managedClients.add(client);
    
    // Desktop clients have stable connectivity by default
    final connectivity = ConnectivitySimulator();
    await connectivity.simulateConnectivityChange(ConnectivityResult.ethernet);
    _clientConnectivity[client] = connectivity;
    
    return client;
  }

  /// Creates multiple desktop clients
  Future<List<dynamic>> createDesktopClientCluster(List<MerkleKVConfig> configs) async {
    final clients = <dynamic>[];
    
    for (final config in configs) {
      final client = await createDesktopClient(config);
      if (client != null) {
        clients.add(client);
      }
    }
    
    return clients;
  }

  /// Creates a mobile client with mobile-specific connectivity simulation
  Future<dynamic> createMobileClient(MerkleKVConfig config) async {
    if (_isDisposed) return null;

    final client = await _testHarness.createClient(config);
    _managedClients.add(client);
    
    // Mobile clients start with WiFi but can switch to cellular
    final connectivity = ConnectivitySimulator();
    await connectivity.simulateConnectivityChange(ConnectivityResult.wifi);
    _clientConnectivity[client] = connectivity;
    
    return client;
  }

  /// Creates multiple mobile clients
  Future<List<dynamic>> createMobileClientCluster(List<MerkleKVConfig> configs) async {
    final clients = <dynamic>[];
    
    for (final config in configs) {
      final client = await createMobileClient(config);
      if (client != null) {
        clients.add(client);
      }
    }
    
    return clients;
  }

  /// Creates a mixed cluster of mobile and desktop clients
  Future<List<dynamic>> createClientCluster(List<MerkleKVConfig> configs) async {
    final clients = <dynamic>[];
    
    for (int i = 0; i < configs.length; i++) {
      final config = configs[i];
      
      // Alternate between mobile and desktop for variety
      final client = i % 2 == 0 
          ? await createMobileClient(config)
          : await createDesktopClient(config);
      
      if (client != null) {
        clients.add(client);
      }
    }
    
    return clients;
  }

  /// Simulates network partition between client groups
  Future<void> simulateNetworkPartition(
    List<dynamic> group1,
    List<dynamic> group2, {
    Duration duration = const Duration(seconds: 10),
  }) async {
    if (_isDisposed) return;

    final partition = NetworkPartition(group1, group2, duration);
    _activePartitions.add(partition);
    
    // Disconnect groups from each other
    for (final client in group1) {
      final connectivity = _clientConnectivity[client];
      if (connectivity != null) {
        await connectivity.simulateConnectivityChange(ConnectivityResult.none);
      }
    }
    
    // Allow partition to persist
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// Restores network connectivity after partition
  Future<void> restoreNetworkPartition() async {
    if (_isDisposed || _activePartitions.isEmpty) return;

    // Restore connectivity for all partitioned clients
    for (final partition in _activePartitions) {
      for (final client in [...partition.group1, ...partition.group2]) {
        final connectivity = _clientConnectivity[client];
        if (connectivity != null) {
          await connectivity.simulateConnectivityChange(ConnectivityResult.wifi);
        }
      }
    }
    
    _activePartitions.clear();
    
    // Allow time for reconnection
    await Future.delayed(const Duration(seconds: 2));
  }

  /// Simulates bandwidth constraints for a specific client
  Future<void> simulateBandwidthConstraints({
    required dynamic client,
    required int maxBytesPerSecond,
  }) async {
    if (_isDisposed) return;

    // Mock bandwidth limitation
    // In real implementation, this would throttle actual network operations
    final connectivity = _clientConnectivity[client];
    if (connectivity != null) {
      // Simulate higher latency to represent bandwidth constraints
      final latencyMs = math.max(100, (1000 / maxBytesPerSecond * 1024).round());
      await connectivity.simulateLatency(Duration(milliseconds: latencyMs));
    }
  }

  /// Simulates network latency for all managed clients
  Future<void> simulateNetworkLatency(Duration latency) async {
    if (_isDisposed) return;

    for (final connectivity in _clientConnectivity.values) {
      await connectivity.simulateLatency(latency);
    }
  }

  /// Simulates intermittent connectivity across all clients
  Future<void> simulateGlobalIntermittentConnectivity({
    required Duration disconnectDuration,
    required int intervals,
  }) async {
    if (_isDisposed) return;

    for (final connectivity in _clientConnectivity.values) {
      // Add randomization to avoid synchronized disconnections
      final randomDelay = math.Random().nextInt(1000);
      
      Timer(Duration(milliseconds: randomDelay), () async {
        await connectivity.simulateIntermittentConnectivity(
          disconnectDuration: disconnectDuration,
          intervals: intervals,
        );
      });
    }
    
    // Wait for all intermittent connectivity simulation to complete
    final totalDuration = Duration(
      milliseconds: (disconnectDuration.inMilliseconds * intervals * 2) + 1000,
    );
    await Future.delayed(totalDuration);
  }

  /// Simulates mobile client switching from WiFi to cellular
  Future<void> simulateMobileNetworkSwitch(dynamic mobileClient) async {
    if (_isDisposed) return;

    final connectivity = _clientConnectivity[mobileClient];
    if (connectivity != null) {
      // Switch from WiFi to cellular
      await connectivity.simulateConnectivityChange(ConnectivityResult.mobile);
      
      // Add typical cellular latency
      await connectivity.simulateLatency(const Duration(milliseconds: 200));
    }
  }

  /// Gets connectivity status for a client
  ConnectivityResult? getClientConnectivity(dynamic client) {
    return _clientConnectivity[client]?.connectivity;
  }

  /// Gets connection status for all managed clients
  Map<dynamic, ConnectivityResult> getAllClientConnectivity() {
    final result = <dynamic, ConnectivityResult>{};
    
    for (final entry in _clientConnectivity.entries) {
      result[entry.key] = entry.value.connectivity;
    }
    
    return result;
  }

  /// Verifies all clients are properly connected
  Future<void> verifyAllClientsConnected() async {
    if (_isDisposed) return;

    for (final client in _managedClients) {
      await _testHarness.waitForConnection(client);
    }
  }

  /// Gets health status of all managed clients
  Future<Map<dynamic, bool>> getClientHealthStatus() async {
    final healthStatus = <dynamic, bool>{};
    
    for (final client in _managedClients) {
      try {
        await _testHarness.verifyClientHealth(client);
        healthStatus[client] = true;
      } catch (e) {
        healthStatus[client] = false;
      }
    }
    
    return healthStatus;
  }

  /// Disposes all resources
  Future<void> dispose() async {
    _isDisposed = true;
    
    // Clear active partitions
    _activePartitions.clear();
    
    // Dispose connectivity simulators
    for (final connectivity in _clientConnectivity.values) {
      await connectivity.dispose();
    }
    _clientConnectivity.clear();
    
    // Clear managed clients
    _managedClients.clear();
    
    // Dispose test harness
    await _testHarness.dispose();
  }
}

/// Represents a network partition between client groups
class NetworkPartition {
  final List<dynamic> group1;
  final List<dynamic> group2;
  final Duration duration;
  final DateTime startTime;

  NetworkPartition(this.group1, this.group2, this.duration)
      : startTime = DateTime.now();

  bool get isExpired => 
      DateTime.now().difference(startTime) > duration;

  List<dynamic> get allClients => [...group1, ...group2];
}