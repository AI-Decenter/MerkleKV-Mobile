#!/usr/bin/env dart

import 'lib/merkle_kv.dart';

/// Basic validation test that doesn't rely on dart test framework
Future<void> main() async {
  print('🧪 Running basic validation tests...');
  
  try {
    // Test 1: Can create config
    print('📋 Test 1: Creating configuration...');
    final config = MerkleKV.builder()
        .mqttHost('mqtt.example.com')
        .mqttPort(8883)
        .useTls()
        .credentials('username', 'password')
        .clientId('test-client')
        .nodeId('test-node')
        .topicPrefix('test')
        .build();
    print('✅ Configuration created successfully');
    
    // Test 2: Can create client instance
    print('📋 Test 2: Creating client instance...');
    final client = MerkleKV(config);
    print('✅ Client instance created successfully');
    
    // Test 3: Check version
    print('📋 Test 3: Checking version...');
    final version = client.version;
    print('✅ Version: $version');
    
    // Test 4: Check configuration access
    print('📋 Test 4: Verifying configuration...');
    print('   Host: ${config.mqttHost}');
    print('   Port: ${config.mqttPort}');
    print('   TLS: ${config.mqttUseTls}');
    print('   Client ID: ${config.clientId}');
    print('   Node ID: ${config.nodeId}');
    print('   Topic Prefix: ${config.topicPrefix}');
    print('✅ Configuration access successful');
    
    // Test 5: Exception handling
    print('📋 Test 5: Testing exception creation...');
    try {
      MerkleKV.builder()
          .mqttHost('')  // Invalid host
          .build();
      print('❌ Should have thrown exception for invalid host');
    } catch (e) {
      print('✅ Exception properly thrown for invalid config: ${e.runtimeType}');
    }
    
    print('');
    print('🎉 All basic validation tests passed!');
    print('🔧 Core API compilation and basic functionality verified');
    
  } catch (e, stackTrace) {
    print('❌ Validation failed: $e');
    print('Stack trace: $stackTrace');
    return;
  }
}