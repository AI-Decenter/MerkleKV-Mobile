// ignore_for_file: avoid_print
import 'dart:async';

import '../lib/src/config/merkle_kv_config.dart';
import '../lib/src/mqtt/connection_lifecycle.dart';
import '../lib/src/mqtt/connection_logger.dart';
import '../lib/src/mqtt/mqtt_client_impl.dart';
import '../lib/src/replication/metrics.dart';

/// Simple console logger for demo purposes
class DemoLogger {
  static void info(String message) {

    print(message);
  }
  
  static void error(String message) {
  
    print(message);
  }
}

/// Example demonstrating the Connection Lifecycle Manager
/// 
/// This example shows how to use the ConnectionLifecycleManager for proper
/// MQTT connection management with graceful disconnection, state monitoring,
/// and platform lifecycle integration.
void main() async {
  DemoLogger.info('🔄 Connection Lifecycle Manager Demo');
  DemoLogger.info('====================================');

  // Create configuration
  final config = MerkleKVConfig(
    mqttHost: 'localhost',  // Change to your MQTT broker
    mqttPort: 1883,
    nodeId: 'demo-node',
    clientId: 'lifecycle-demo-client',
    keepAliveSeconds: 30,
  );

  // Create MQTT client
  final mqttClient = MqttClientImpl(config);
  
  // Create metrics for observability
  final metrics = InMemoryReplicationMetrics();
  
  // Create connection lifecycle manager with custom logger
  final manager = DefaultConnectionLifecycleManager(
    config: config,
    mqttClient: mqttClient,
    metrics: metrics,
    maintainConnectionInBackground: true,
    logger: const DefaultConnectionLogger(enableDebug: false), // Less verbose for demo
  );

  // Monitor connection state changes
  final subscription = manager.connectionState.listen((event) {
    DemoLogger.info('📡 Connection State: ${event.state} - ${event.reason}');
    if (event.error != null) {
      DemoLogger.error('   ❌ Error: ${event.error}');
    }
  });

  try {
    DemoLogger.info('\n🚀 Connecting to MQTT broker...');
    
    // Attempt connection
    try {
      await manager.connect();
      DemoLogger.info('✅ Connected successfully!');
      DemoLogger.info('   Connection status: ${manager.isConnected}');
    } catch (e) {
      DemoLogger.error('❌ Connection failed: $e');
      DemoLogger.info('   (This is expected if no MQTT broker is running)');
      return;
    }

    // Simulate app lifecycle changes

    print('\n📱 Simulating app lifecycle changes...');
    
    // Simulate app going to background

    print('   ⏸️  App pausing (backgrounding)...');
    await manager.handleAppStateChange(AppLifecycleState.paused);

    print('   Connection status after pause: ${manager.isConnected}');
    
    // Wait a moment
    await Future.delayed(const Duration(seconds: 1));
    
    // Simulate app resuming

    print('   ▶️  App resuming (foregrounding)...');
    await manager.handleAppStateChange(AppLifecycleState.resumed);

    print('   Connection status after resume: ${manager.isConnected}');

    // Wait a moment to see connection activity
    await Future.delayed(const Duration(seconds: 2));

    // Demonstrate graceful disconnection

    print('\n🔌 Performing graceful disconnection...');

    print('   Suppressing LWT message for clean shutdown...');
    
    await manager.disconnect(suppressLWT: true);

    print('✅ Disconnected successfully!');

    print('   Connection status: ${manager.isConnected}');

  } catch (e) {

    print('❌ Demo error: $e');
  } finally {
    // Clean up resources

    print('\n🧹 Cleaning up resources...');
    
    await subscription.cancel();
    await manager.dispose();
    

    print('✅ Cleanup completed');
  }


  print('\n📊 Demo completed successfully!');

  print('   Features demonstrated:');

  print('   ✓ Connection establishment with proper handshake');

  print('   ✓ Connection state monitoring and events');

  print('   ✓ Platform lifecycle integration (background/foreground)');

  print('   ✓ Graceful disconnection with LWT suppression');

  print('   ✓ Resource cleanup and disposal');

  print('   ✓ Error handling and recovery');
}

/// Example showing different configuration options
void demonstrateConfigurationOptions() {

  print('\n🔧 Connection Lifecycle Configuration Options');

  print('===========================================');

  // Basic configuration
  final basicConfig = MerkleKVConfig(
    mqttHost: 'localhost',
    nodeId: 'basic-node',
    clientId: 'basic-client',
  );

  // Secure configuration with TLS
  final secureConfig = MerkleKVConfig(
    mqttHost: 'secure-broker.example.com',
    mqttPort: 8883,
    mqttUseTls: true,
    username: 'secure-user',
    password: 'secure-password',
    nodeId: 'secure-node',
    clientId: 'secure-client',
    keepAliveSeconds: 60,
  );

  // Configuration for mobile environments
  final mobileConfig = MerkleKVConfig(
    mqttHost: 'mobile-broker.example.com',
    nodeId: 'mobile-node',
    clientId: 'mobile-client',
    keepAliveSeconds: 120,  // Longer keep-alive for mobile networks
  );


  print('✓ Basic configuration: ${basicConfig.mqttHost}:${basicConfig.mqttPort}');

  print('✓ Secure configuration: ${secureConfig.mqttHost}:${secureConfig.mqttPort} (TLS)');

  print('✓ Mobile configuration: ${mobileConfig.mqttHost}:${mobileConfig.mqttPort}');
  

  print('\n🔒 Security features:');

  print('   ✓ TLS encryption when credentials are provided');

  print('   ✓ Certificate validation (reject bad certificates)');

  print('   ✓ Credential cleanup on disconnection');
  

  print('\n📱 Mobile optimizations:');

  print('   ✓ Configurable background connection maintenance');

  print('   ✓ Platform lifecycle event integration');

  print('   ✓ Automatic reconnection on foreground resume');

  print('   ✓ Proper resource cleanup for memory efficiency');
}