import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../helpers/mobile_test_harness.dart';
import '../helpers/platform_simulation.dart';
import '../helpers/connectivity_simulator.dart';

/// Mobile Lifecycle E2E Tests
/// 
/// Tests mobile-specific lifecycle scenarios including background/foreground
/// transitions, airplane mode toggling, and platform connectivity changes.
/// 
/// Focus: Spec-compliant convergence behavior rather than hard-coded latency targets.
@Tags(['mobile-e2e', 'lifecycle'])
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Mobile Lifecycle E2E Tests', () {
    late MobileTestHarness testHarness;
    late PlatformSimulation platformSim;
    late ConnectivitySimulator connectivitySim;
    late MerkleKVConfig config;

    setUpAll(() async {
      // Initialize test infrastructure
      testHarness = MobileTestHarness();
      platformSim = PlatformSimulation();
      connectivitySim = ConnectivitySimulator();
      
      // Configure for mobile testing with anti-entropy interval
      config = MerkleKVConfig(
        mqttHost: 'localhost',
        mqttPort: 1883,
        clientId: 'mobile-e2e-client',
        nodeId: 'test-mobile-node',
        topicPrefix: 'mobile-e2e-test',
        antiEntropyIntervalMs: 60000, // Spec-compliant interval
        mqttUseTls: false,
      );
    });

    tearDownAll(() async {
      await testHarness.dispose();
      await platformSim.dispose();
      await connectivitySim.dispose();
    });

    group('Background/Foreground Transitions', () {
      testWidgets('Background transition preserves connection state', (tester) async {
        // Given: Active MerkleKV client with established connection
        final client = await testHarness.createClient(config);
        await testHarness.waitForConnection(client);
        
        // Set a test value before background transition
        await client.set('test-key-bg', 'background-test-value');
        
        // When: App goes to background
        await platformSim.simulateAppLifecycleState(AppLifecycleState.paused);
        await tester.pump(const Duration(seconds: 1));
        
        // Then: Connection state should be gracefully handled
        final connectionState = await testHarness.getConnectionState(client);
        expect(connectionState, isIn([ConnectionState.connected, ConnectionState.reconnecting]));
        
        // When: App returns to foreground
        await platformSim.simulateAppLifecycleState(AppLifecycleState.resumed);
        await tester.pump(const Duration(seconds: 2));
        
        // Then: Connection should be restored and data accessible
        await testHarness.waitForConnection(client);
        final retrievedValue = await client.get('test-key-bg');
        expect(retrievedValue, equals('background-test-value'));
      });

      testWidgets('App suspension preserves pending operations', (tester) async {
        // Given: MerkleKV client with pending operations
        final client = await testHarness.createClient(config);
        await testHarness.waitForConnection(client);
        
        // Queue multiple operations
        final futures = <Future<void>>[
          client.set('key1', 'value1'),
          client.set('key2', 'value2'),
          client.set('key3', 'value3'),
        ];
        
        // When: App gets suspended while operations are pending
        await platformSim.simulateAppLifecycleState(AppLifecycleState.paused);
        
        // Wait for operations to potentially complete or queue
        await Future.wait(futures);
        
        // When: App resumes
        await platformSim.simulateAppLifecycleState(AppLifecycleState.resumed);
        await testHarness.waitForConnection(client);
        
        // Then: All operations should have completed successfully
        expect(await client.get('key1'), equals('value1'));
        expect(await client.get('key2'), equals('value2'));
        expect(await client.get('key3'), equals('value3'));
      });

      testWidgets('Rapid background/foreground cycling does not corrupt state', (tester) async {
        // Given: Active MerkleKV client
        final client = await testHarness.createClient(config);
        await testHarness.waitForConnection(client);
        
        // Set initial state
        await client.set('cycle-test', 'initial-value');
        
        // When: Rapid cycling between background and foreground
        for (int i = 0; i < 5; i++) {
          await platformSim.simulateAppLifecycleState(AppLifecycleState.paused);
          await tester.pump(const Duration(milliseconds: 100));
          
          await platformSim.simulateAppLifecycleState(AppLifecycleState.resumed);
          await tester.pump(const Duration(milliseconds: 100));
        }
        
        // Then: Connection state should remain stable and data intact
        await testHarness.waitForConnection(client);
        final value = await client.get('cycle-test');
        expect(value, equals('initial-value'));
        
        // Verify no memory leaks or state corruption
        await testHarness.verifyClientHealth(client);
      });
    });

    group('Network State Transitions', () {
      testWidgets('Airplane mode toggle triggers proper reconnection', (tester) async {
        // Given: Connected MerkleKV client
        final client = await testHarness.createClient(config);
        await testHarness.waitForConnection(client);
        
        // Set data before network interruption
        await client.set('airplane-test', 'before-disconnect');
        
        // When: Airplane mode enabled (network disconnected)
        await connectivitySim.simulateConnectivityChange(ConnectivityResult.none);
        await tester.pump(const Duration(seconds: 1));
        
        // Connection should detect the network loss
        await testHarness.waitForConnectionState(client, ConnectionState.disconnected);
        
        // When: Airplane mode disabled (network restored)
        await connectivitySim.simulateConnectivityChange(ConnectivityResult.wifi);
        
        // Then: Automatic reconnection should occur
        await testHarness.waitForConnection(client, timeout: const Duration(seconds: 10));
        
        // Data should still be accessible
        final value = await client.get('airplane-test');
        expect(value, equals('before-disconnect'));
        
        // Operations should work normally after reconnection
        await client.set('airplane-test-after', 'after-reconnect');
        expect(await client.get('airplane-test-after'), equals('after-reconnect'));
      });

      testWidgets('WiFi to cellular network transition maintains connectivity', (tester) async {
        // Given: Client connected via WiFi
        final client = await testHarness.createClient(config);
        await connectivitySim.simulateConnectivityChange(ConnectivityResult.wifi);
        await testHarness.waitForConnection(client);
        
        // Store test data
        await client.set('network-transition', 'wifi-data');
        
        // When: Network switches from WiFi to cellular
        await connectivitySim.simulateConnectivityChange(ConnectivityResult.mobile);
        await tester.pump(const Duration(seconds: 1));
        
        // Then: Connection should adapt without data loss
        await testHarness.waitForConnection(client);
        final value = await client.get('network-transition');
        expect(value, equals('wifi-data'));
        
        // New operations should work on cellular
        await client.set('cellular-data', 'mobile-network-value');
        expect(await client.get('cellular-data'), equals('mobile-network-value'));
      });

      testWidgets('Poor connectivity simulation maintains operation queue', (tester) async {
        // Given: Client with poor network conditions
        final client = await testHarness.createClient(config);
        await connectivitySim.simulateLatency(const Duration(milliseconds: 2000));
        await testHarness.waitForConnection(client);
        
        // When: Multiple operations are queued during poor connectivity
        final futures = <Future<void>>[
          client.set('slow-key-1', 'value1'),
          client.set('slow-key-2', 'value2'),
          client.set('slow-key-3', 'value3'),
        ];
        
        // Simulate intermittent connectivity
        await connectivitySim.simulateIntermittentConnectivity(
          disconnectDuration: const Duration(milliseconds: 500),
          intervals: 3,
        );
        
        // Wait for operations to complete
        await Future.wait(futures);
        
        // Then: All operations should eventually succeed
        expect(await client.get('slow-key-1'), equals('value1'));
        expect(await client.get('slow-key-2'), equals('value2'));
        expect(await client.get('slow-key-3'), equals('value3'));
      });
    });

    group('App Termination and Recovery', () {
      testWidgets('App termination during pending operations enables recovery on restart', (tester) async {
        // Given: Client with persistent storage enabled
        final persistentConfig = config.copyWith(
          // Enable persistent storage for operation recovery
          storage: StorageFactory.createPersistent('test-db'),
        );
        
        final client = await testHarness.createClient(persistentConfig);
        await testHarness.waitForConnection(client);
        
        // Queue operations
        await client.set('persistent-key-1', 'persistent-value-1');
        final pendingOperation = client.set('persistent-key-2', 'persistent-value-2');
        
        // When: Simulate app termination (force close)
        await testHarness.simulateAppTermination(client);
        
        // When: App restarts and creates new client instance
        final newClient = await testHarness.createClient(persistentConfig);
        await testHarness.waitForConnection(newClient);
        
        // Then: Previously persisted data should be available
        expect(await newClient.get('persistent-key-1'), equals('persistent-value-1'));
        
        // Pending operations should be recoverable from persistent queue
        // (Note: This depends on implementation of persistent operation queue)
        await testHarness.waitForOperationRecovery(newClient);
        
        // Verify system health after recovery
        await testHarness.verifyClientHealth(newClient);
      });
    });

    group('System Memory Pressure', () {
      testWidgets('Low memory conditions do not corrupt sync state', (tester) async {
        // Given: Client with active synchronization
        final client = await testHarness.createClient(config);
        await testHarness.waitForConnection(client);
        
        // Set up data for sync
        await client.set('memory-test-1', 'value-before-pressure');
        await client.set('memory-test-2', 'value-before-pressure-2');
        
        // When: System experiences memory pressure
        await platformSim.simulateMemoryPressure(MemoryPressureLevel.critical);
        await tester.pump(const Duration(seconds: 1));
        
        // Then: Sync state should remain consistent
        expect(await client.get('memory-test-1'), equals('value-before-pressure'));
        expect(await client.get('memory-test-2'), equals('value-before-pressure-2'));
        
        // New operations should continue to work
        await client.set('memory-test-after', 'value-after-pressure');
        expect(await client.get('memory-test-after'), equals('value-after-pressure'));
        
        // Verify no memory leaks
        await testHarness.verifyMemoryUsage(client);
      });
    });
  });
}