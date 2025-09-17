import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';

import '../helpers/mobile_test_harness.dart';
import '../helpers/platform_simulation.dart';
import '../helpers/convergence_validator.dart';
import '../helpers/multi_device_simulator.dart';

/// Mobile Convergence E2E Tests
/// 
/// Tests anti-entropy synchronization and convergence behavior during mobile
/// state transitions, focusing on spec-compliant behavior rather than 
/// hard-coded latency targets.
@Tags(['mobile-e2e', 'convergence'])
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Mobile Convergence E2E Tests', () {
    late MobileTestHarness testHarness;
    late PlatformSimulation platformSim;
    late ConvergenceValidator convergenceValidator;
    late MultiDeviceSimulator multiDevice;
    late MerkleKVConfig config;

    setUpAll(() async {
      testHarness = MobileTestHarness();
      platformSim = PlatformSimulation();
      convergenceValidator = ConvergenceValidator();
      multiDevice = MultiDeviceSimulator();
      
      // Configure with anti-entropy enabled
      config = MerkleKVConfig(
        mqttHost: 'localhost',
        mqttPort: 1883,
        clientId: 'convergence-mobile-client',
        nodeId: 'mobile-convergence-node',
        topicPrefix: 'mobile-convergence-test',
        antiEntropyIntervalMs: 60000, // 1 minute for spec compliance
        mqttUseTls: false,
      );
    });

    tearDownAll(() async {
      await testHarness.dispose();
      await platformSim.dispose();
      await convergenceValidator.dispose();
      await multiDevice.dispose();
    });

    group('Anti-Entropy During Mobile State Changes', () {
      testWidgets('Anti-entropy works across app suspension cycles', (tester) async {
        // Given: Two clients with different data
        final mobileClient = await testHarness.createClient(config);
        final desktopClient = await multiDevice.createDesktopClient(config.copyWith(
          clientId: 'desktop-client',
          nodeId: 'desktop-node',
        ));
        
        await testHarness.waitForConnection(mobileClient);
        await testHarness.waitForConnection(desktopClient);
        
        // Create divergent state
        await mobileClient.set('mobile-data', 'mobile-value');
        await desktopClient.set('desktop-data', 'desktop-value');
        
        // Verify initial divergence
        expect(await mobileClient.get('desktop-data'), isNull);
        expect(await desktopClient.get('mobile-data'), isNull);
        
        // When: Mobile app gets suspended during sync operation
        await platformSim.simulateAppLifecycleState(AppLifecycleState.paused);
        await tester.pump(const Duration(milliseconds: 500));
        
        // Trigger anti-entropy sync on desktop side
        await convergenceValidator.triggerAntiEntropy(desktopClient);
        
        // When: Mobile app resumes
        await platformSim.simulateAppLifecycleState(AppLifecycleState.resumed);
        await testHarness.waitForConnection(mobileClient);
        
        // Then: Convergence should complete within configured interval
        await convergenceValidator.waitForConvergence(
          [mobileClient, desktopClient],
          timeout: Duration(milliseconds: config.antiEntropyIntervalMs + 10000),
        );
        
        // Verify convergence achieved
        expect(await mobileClient.get('desktop-data'), equals('desktop-value'));
        expect(await desktopClient.get('mobile-data'), equals('mobile-value'));
      });

      testWidgets('Convergence continues after network interruption', (tester) async {
        // Given: Multiple clients with ongoing sync
        final clients = await multiDevice.createClientCluster([
          config.copyWith(clientId: 'mobile-1', nodeId: 'mobile-node-1'),
          config.copyWith(clientId: 'mobile-2', nodeId: 'mobile-node-2'),
          config.copyWith(clientId: 'desktop-1', nodeId: 'desktop-node-1'),
        ]);
        
        await Future.wait(clients.map((c) => testHarness.waitForConnection(c)));
        
        // Create data on different clients
        await clients[0].set('key-from-mobile-1', 'value-1');
        await clients[1].set('key-from-mobile-2', 'value-2');
        await clients[2].set('key-from-desktop', 'value-3');
        
        // When: Network interruption occurs during sync
        await multiDevice.simulateNetworkPartition(
          clients.sublist(0, 2), // Mobile clients
          clients.sublist(2),    // Desktop clients
          duration: const Duration(seconds: 5),
        );
        
        // When: Network is restored
        await multiDevice.restoreNetworkPartition();
        
        // Then: Anti-entropy should restore convergence
        await convergenceValidator.waitForConvergence(
          clients,
          timeout: Duration(milliseconds: config.antiEntropyIntervalMs * 2),
        );
        
        // Verify all data is available on all clients
        for (final client in clients) {
          expect(await client.get('key-from-mobile-1'), equals('value-1'));
          expect(await client.get('key-from-mobile-2'), equals('value-2'));
          expect(await client.get('key-from-desktop'), equals('value-3'));
        }
      });

      testWidgets('Merkle tree synchronization handles mobile lifecycle events', (tester) async {
        // Given: Clients with large datasets requiring merkle sync
        final mobileClient = await testHarness.createClient(config);
        final remoteClient = await multiDevice.createDesktopClient(config.copyWith(
          clientId: 'remote-desktop',
          nodeId: 'remote-node',
        ));
        
        await testHarness.waitForConnection(mobileClient);
        await testHarness.waitForConnection(remoteClient);
        
        // Create substantial dataset to trigger merkle sync
        final largeDataset = await convergenceValidator.createLargeDataset(100);
        
        // Load data on mobile client
        for (final entry in largeDataset.entries) {
          await mobileClient.set(entry.key, entry.value);
        }
        
        // When: Mobile goes to background during merkle sync
        await convergenceValidator.triggerAntiEntropy(mobileClient);
        await platformSim.simulateAppLifecycleState(AppLifecycleState.paused);
        
        // Allow some sync progress
        await tester.pump(const Duration(seconds: 2));
        
        // When: Mobile returns to foreground
        await platformSim.simulateAppLifecycleState(AppLifecycleState.resumed);
        await testHarness.waitForConnection(mobileClient);
        
        // Then: Merkle sync should complete successfully
        await convergenceValidator.waitForMerkleSync(mobileClient, remoteClient);
        
        // Verify all data synchronized correctly
        for (final entry in largeDataset.entries) {
          expect(await remoteClient.get(entry.key), equals(entry.value));
        }
      });
    });

    group('Multi-Device Convergence with Mobile Clients', () {
      testWidgets('Mobile client convergence with other mobile clients', (tester) async {
        // Given: Multiple mobile clients
        final mobileClients = await multiDevice.createMobileClientCluster([
          config.copyWith(clientId: 'mobile-a', nodeId: 'mobile-node-a'),
          config.copyWith(clientId: 'mobile-b', nodeId: 'mobile-node-b'),
          config.copyWith(clientId: 'mobile-c', nodeId: 'mobile-node-c'),
        ]);
        
        await Future.wait(mobileClients.map((c) => testHarness.waitForConnection(c)));
        
        // When: Each mobile client creates unique data
        await mobileClients[0].set('mobile-a-data', 'data-from-a');
        await mobileClients[1].set('mobile-b-data', 'data-from-b');
        await mobileClients[2].set('mobile-c-data', 'data-from-c');
        
        // Simulate various mobile lifecycle events
        await platformSim.simulateAppLifecycleStateForClient(mobileClients[0], AppLifecycleState.paused);
        await platformSim.simulateAppLifecycleStateForClient(mobileClients[1], AppLifecycleState.inactive);
        
        // Allow sync time
        await tester.pump(const Duration(seconds: 3));
        
        // Resume all clients
        await platformSim.simulateAppLifecycleStateForClient(mobileClients[0], AppLifecycleState.resumed);
        await platformSim.simulateAppLifecycleStateForClient(mobileClients[1], AppLifecycleState.resumed);
        
        // Then: All clients should converge
        await convergenceValidator.waitForConvergence(
          mobileClients,
          timeout: Duration(milliseconds: config.antiEntropyIntervalMs * 2),
        );
        
        // Verify convergence
        for (final client in mobileClients) {
          expect(await client.get('mobile-a-data'), equals('data-from-a'));
          expect(await client.get('mobile-b-data'), equals('data-from-b'));
          expect(await client.get('mobile-c-data'), equals('data-from-c'));
        }
      });

      testWidgets('Mixed mobile and desktop client convergence', (tester) async {
        // Given: Mixed client environment
        final mobileClient = await testHarness.createClient(config);
        final desktopClients = await multiDevice.createDesktopClientCluster([
          config.copyWith(clientId: 'desktop-1', nodeId: 'desktop-node-1'),
          config.copyWith(clientId: 'desktop-2', nodeId: 'desktop-node-2'),
        ]);
        
        final allClients = [mobileClient, ...desktopClients];
        await Future.wait(allClients.map((c) => testHarness.waitForConnection(c)));
        
        // When: Mobile client goes offline temporarily
        await platformSim.simulateAppLifecycleState(AppLifecycleState.detached);
        
        // Desktop clients continue working
        await desktopClients[0].set('desktop-work-1', 'offline-work-1');
        await desktopClients[1].set('desktop-work-2', 'offline-work-2');
        
        // Mobile comes back online
        await platformSim.simulateAppLifecycleState(AppLifecycleState.resumed);
        await testHarness.waitForConnection(mobileClient);
        
        // Mobile creates new data
        await mobileClient.set('mobile-return-data', 'returned-online');
        
        // Then: Full convergence should occur
        await convergenceValidator.waitForConvergence(
          allClients,
          timeout: Duration(milliseconds: config.antiEntropyIntervalMs * 2),
        );
        
        // Verify all data present on all clients
        for (final client in allClients) {
          expect(await client.get('desktop-work-1'), equals('offline-work-1'));
          expect(await client.get('desktop-work-2'), equals('offline-work-2'));
          expect(await client.get('mobile-return-data'), equals('returned-online'));
        }
      });
    });

    group('Conflict Resolution During Mobile Events', () {
      testWidgets('Last-writer-wins resolution during lifecycle transitions', (tester) async {
        // Given: Two clients with conflicting updates
        final mobileClient = await testHarness.createClient(config);
        final remoteClient = await multiDevice.createDesktopClient(config.copyWith(
          clientId: 'conflict-remote',
          nodeId: 'conflict-remote-node',
        ));
        
        await testHarness.waitForConnection(mobileClient);
        await testHarness.waitForConnection(remoteClient);
        
        // Both clients set same key with different values
        await mobileClient.set('conflict-key', 'mobile-value');
        await remoteClient.set('conflict-key', 'remote-value');
        
        // When: Mobile goes to background during conflict resolution
        await platformSim.simulateAppLifecycleState(AppLifecycleState.paused);
        
        // Trigger sync from remote
        await convergenceValidator.triggerAntiEntropy(remoteClient);
        await tester.pump(const Duration(seconds: 1));
        
        // Mobile returns
        await platformSim.simulateAppLifecycleState(AppLifecycleState.resumed);
        await testHarness.waitForConnection(mobileClient);
        
        // Then: Conflict should be resolved using last-writer-wins
        await convergenceValidator.waitForConvergence([mobileClient, remoteClient]);
        
        // Both clients should have the same resolved value
        final mobileValue = await mobileClient.get('conflict-key');
        final remoteValue = await remoteClient.get('conflict-key');
        expect(mobileValue, equals(remoteValue));
        expect(mobileValue, isIn(['mobile-value', 'remote-value']));
      });

      testWidgets('Vector clock ordering during network transitions', (tester) async {
        // Given: Clients with ordered operations
        final clients = await multiDevice.createClientCluster([
          config.copyWith(clientId: 'ordered-1', nodeId: 'ordered-node-1'),
          config.copyWith(clientId: 'ordered-2', nodeId: 'ordered-node-2'),
        ]);
        
        await Future.wait(clients.map((c) => testHarness.waitForConnection(c)));
        
        // Create ordered sequence of operations
        await clients[0].set('sequence-key', 'value-1');
        await tester.pump(const Duration(milliseconds: 100));
        
        // Simulate network issues during next operation
        await multiDevice.simulateNetworkLatency(const Duration(milliseconds: 1000));
        await clients[1].set('sequence-key', 'value-2');
        
        // When: Mobile lifecycle event occurs
        await platformSim.simulateAppLifecycleStateForClient(clients[0], AppLifecycleState.paused);
        await tester.pump(const Duration(milliseconds: 500));
        await platformSim.simulateAppLifecycleStateForClient(clients[0], AppLifecycleState.resumed);
        
        // Then: Vector clock ordering should be preserved
        await convergenceValidator.waitForConvergence(clients);
        await convergenceValidator.verifyVectorClockOrdering(clients, 'sequence-key');
        
        // Final state should be consistent
        final finalValue = await clients[0].get('sequence-key');
        expect(await clients[1].get('sequence-key'), equals(finalValue));
      });
    });

    group('Convergence Performance Under Mobile Conditions', () {
      testWidgets('Convergence efficiency with limited mobile bandwidth', (tester) async {
        // Given: Mobile client with bandwidth constraints
        final mobileClient = await testHarness.createClient(config);
        final desktopClient = await multiDevice.createDesktopClient(config.copyWith(
          clientId: 'bandwidth-desktop',
          nodeId: 'bandwidth-desktop-node',
        ));
        
        await testHarness.waitForConnection(mobileClient);
        await testHarness.waitForConnection(desktopClient);
        
        // Simulate limited mobile bandwidth
        await multiDevice.simulateBandwidthConstraints(
          client: mobileClient,
          maxBytesPerSecond: 1024, // 1KB/s
        );
        
        // Create dataset that requires efficient sync
        final dataset = await convergenceValidator.createDataset(50);
        for (final entry in dataset.entries) {
          await desktopClient.set(entry.key, entry.value);
        }
        
        // When: Trigger convergence under bandwidth constraints
        final startTime = DateTime.now();
        await convergenceValidator.triggerAntiEntropy(mobileClient);
        
        // Monitor convergence progress
        await convergenceValidator.waitForConvergence([mobileClient, desktopClient]);
        final convergenceTime = DateTime.now().difference(startTime);
        
        // Then: Convergence should be efficient despite bandwidth limits
        expect(convergenceTime.inMilliseconds, lessThan(config.antiEntropyIntervalMs * 3));
        
        // Verify data integrity
        for (final entry in dataset.entries) {
          expect(await mobileClient.get(entry.key), equals(entry.value));
        }
      });

      testWidgets('Battery optimization does not prevent convergence', (tester) async {
        // Given: Mobile client with battery optimization enabled
        final mobileClient = await testHarness.createClient(config);
        final remoteClient = await multiDevice.createDesktopClient(config.copyWith(
          clientId: 'battery-remote',
          nodeId: 'battery-remote-node',
        ));
        
        await testHarness.waitForConnection(mobileClient);
        await testHarness.waitForConnection(remoteClient);
        
        // Enable battery optimization simulation
        await platformSim.simulateBatteryOptimization(enabled: true);
        
        // Create data to sync
        await remoteClient.set('battery-test-key', 'battery-test-value');
        
        // When: Mobile enters background with battery optimization
        await platformSim.simulateAppLifecycleState(AppLifecycleState.paused);
        await platformSim.simulateBatteryState(BatteryState.low);
        
        // Trigger sync
        await convergenceValidator.triggerAntiEntropy(remoteClient);
        
        // When: Mobile returns to foreground
        await platformSim.simulateAppLifecycleState(AppLifecycleState.resumed);
        await testHarness.waitForConnection(mobileClient);
        
        // Then: Convergence should still occur despite battery optimization
        await convergenceValidator.waitForConvergence([mobileClient, remoteClient]);
        expect(await mobileClient.get('battery-test-key'), equals('battery-test-value'));
      });
    });
  });
}