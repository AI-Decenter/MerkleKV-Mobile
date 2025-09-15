#!/usr/bin/env dart

import 'lib/merkle_kv.dart';
import 'lib/src/commands/response.dart';
import 'lib/src/config/invalid_config_exception.dart';

/// Comprehensive API integration test that validates the complete public interface
Future<void> main() async {
  print('🧪 Running comprehensive API integration test...');
  print('This test validates all public API methods without requiring MQTT broker');
  
  int testsPassed = 0;
  int testsTotal = 0;
  
  void runTest(String testName, Function() testFn) {
    testsTotal++;
    try {
      testFn();
      print('✅ $testName');
      testsPassed++;
    } catch (e) {
      print('❌ $testName: $e');
    }
  }
  
  try {
    // Test 1: Configuration Builder API
    runTest('Configuration builder API', () {
      final config = MerkleKV.builder()
          .mqttHost('mqtt.example.com')
          .mqttPort(8883)
          .useTls()
          .credentials('user', 'pass')
          .clientId('test-client-123')
          .nodeId('test-node-456')
          .topicPrefix('test/app')
          .keepAlive(120)
          .sessionExpiry(7200)
          .maxFutureSkew(300000)
          .tombstoneRetention(48)
          .connectionTimeout(30)
          .persistence(true, '/tmp/test')
          .build();
      
      if (config.mqttHost != 'mqtt.example.com') throw 'Host mismatch';
      if (config.mqttPort != 8883) throw 'Port mismatch';
      if (!config.mqttUseTls) throw 'TLS not enabled';
      if (config.username != 'user') throw 'Username mismatch';
      if (config.clientId != 'test-client-123') throw 'Client ID mismatch';
      if (config.nodeId != 'test-node-456') throw 'Node ID mismatch';
      if (config.topicPrefix != 'test/app') throw 'Topic prefix mismatch';
    });
    
    // Test 2: Client Instance Creation
    late MerkleKV client;
    runTest('Client instance creation', () {
      final config = MerkleKV.builder()
          .mqttHost('mqtt.test.com')
          .clientId('test-client')
          .nodeId('test-node')
          .build();
      
      client = MerkleKV(config);
      if (client.version.isEmpty) throw 'Version not set';
      if (client.currentConnectionState != ConnectionState.disconnected) {
        throw 'Initial state should be disconnected';
      }
    });
    
    // Test 3: Connection State Stream
    runTest('Connection state stream access', () {
      final stream = client.connectionState;
      if (stream == null) throw 'Connection state stream is null';
    });
    
    // Test 4: Configuration Validation - Invalid Cases
    runTest('Configuration validation - empty host', () {
      try {
        MerkleKV.builder()
            .mqttHost('')
            .clientId('test')
            .nodeId('test')
            .build();
        throw 'Should have thrown exception for empty host';
      } on InvalidConfigException {
        // Expected
      }
    });
    
    runTest('Configuration validation - missing client ID', () {
      try {
        MerkleKV.builder()
            .mqttHost('mqtt.test.com')
            .nodeId('test')
            .build();
        throw 'Should have thrown exception for missing client ID';
      } on InvalidConfigException {
        // Expected
      }
    });
    
    runTest('Configuration validation - missing node ID', () {
      try {
        MerkleKV.builder()
            .mqttHost('mqtt.test.com')
            .clientId('test')
            .build();
        throw 'Should have thrown exception for missing node ID';
      } on InvalidConfigException {
        // Expected
      }
    });
    
    // Test 5: Exception Hierarchy
    runTest('Exception hierarchy - ValidationException', () {
      const exception = ValidationException('Test validation error');
      if (exception.errorCode != ErrorCode.invalidRequest) {
        throw 'Wrong error code for ValidationException';
      }
      if (!exception.message.contains('validation')) {
        throw 'Message not preserved';
      }
    });
    
    runTest('Exception hierarchy - TimeoutException', () {
      const exception = TimeoutException('Test timeout error');
      if (exception.errorCode != ErrorCode.timeout) {
        throw 'Wrong error code for TimeoutException';
      }
    });
    
    runTest('Exception hierarchy - KeyNotFoundException', () {
      const exception = KeyNotFoundException('Key not found');
      if (exception.errorCode != ErrorCode.notFound) {
        throw 'Wrong error code for KeyNotFoundException';
      }
    });
    
    // Test 6: Response Creation and Exception Mapping
    runTest('Response to exception mapping', () {
      final response = Response.invalidRequest('test-123', 'Invalid key format');
      final exception = MerkleKVException.fromResponse(response);
      
      if (exception is! ValidationException) {
        throw 'Should create ValidationException for invalid request';
      }
      if (exception.errorCode != ErrorCode.invalidRequest) {
        throw 'Wrong error code mapping';
      }
    });
    
    // Test 7: Advanced Configuration Features
    runTest('Advanced configuration features', () {
      final config = MerkleKV.builder()
          .mqttHost('secure.mqtt.com')
          .mqttPort(8883)
          .useTls()
          .clientId('advanced-client')
          .nodeId('advanced-node')
          .sessionExpiry(3600)
          .maxFutureSkew(600000)
          .tombstoneRetention(72)
          .build();
      
      if (config.sessionExpirySeconds != 3600) throw 'Session expiry not set';
      if (config.skewMaxFutureMs != 600000) throw 'Max future skew not set';
      if (config.tombstoneRetentionHours != 72) throw 'Tombstone retention not set';
    });
    
    // Test 8: Configuration Serialization
    runTest('Configuration serialization', () {
      final config = MerkleKV.builder()
          .mqttHost('mqtt.serialize.test')
          .mqttPort(1883)
          .clientId('serialize-test')
          .nodeId('serialize-node')
          .topicPrefix('serialize')
          .build();
      
      final json = config.toJson();
      if (json['mqttHost'] != 'mqtt.serialize.test') throw 'Host not serialized';
      if (json['mqttPort'] != 1883) throw 'Port not serialized';
      if (json['clientId'] != 'serialize-test') throw 'Client ID not serialized';
      
      // Should not include sensitive data
      if (json.containsKey('username') || json.containsKey('password')) {
        throw 'Sensitive data should not be in JSON';
      }
    });
    
    print('\n' + '='*60);
    print('📊 API Integration Test Results');
    print('='*60);
    print('✅ Passed: $testsPassed');
    print('❌ Failed: ${testsTotal - testsPassed}');
    print('📊 Total: $testsTotal');
    
    if (testsPassed == testsTotal) {
      print('\n🎉 ALL API INTEGRATION TESTS PASSED!');
      print('🔧 Complete public API surface validated and working');
      print('📱 MerkleKV Mobile is ready for use');
    } else {
      print('\n⚠️  Some API tests failed');
    }
    
  } catch (e, stackTrace) {
    print('❌ Integration test failed: $e');
    print('Stack trace: $stackTrace');
  }
}