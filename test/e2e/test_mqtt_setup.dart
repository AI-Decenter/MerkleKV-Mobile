import 'dart:io';
import 'orchestrator/test_session_manager.dart';

/// Simple test to verify MQTT broker startup for E2E tests
void main() async {
  print('🧪 Testing MQTT broker startup for E2E tests...');
  
  final sessionManager = TestSessionManager();
  
  try {
    // Test MQTT broker startup
    print('1. Testing MQTT broker startup...');
    await sessionManager.startMqttBroker();
    
    if (sessionManager.isMqttBrokerRunning) {
      print('✅ MQTT broker started successfully');
    } else {
      print('❌ MQTT broker failed to start');
      exit(1);
    }
    
    // Test basic connectivity
    print('2. Testing basic connectivity...');
    final socket = await Socket.connect('localhost', 1883, timeout: Duration(seconds: 5));
    await socket.close();
    print('✅ MQTT broker is accessible on port 1883');
    
    print('🎉 All tests passed! E2E MQTT setup is working correctly.');
    
  } catch (error, stackTrace) {
    print('❌ Test failed: $error');
    print('Stack trace: $stackTrace');
    exit(1);
  } finally {
    // Test cleanup
    print('3. Testing cleanup...');
    await sessionManager.stopMqttBroker();
    print('✅ Cleanup completed');
  }
}