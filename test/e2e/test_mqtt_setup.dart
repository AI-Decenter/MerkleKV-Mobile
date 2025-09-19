import 'dart:io';
import 'orchestrator/test_session_manager.dart';

/// Fast test to verify MQTT broker setup for E2E tests
void main() async {
  print('🧪 Testing MQTT broker startup (fast mode)...');
  
  final sessionManager = TestSessionManager();
  final stopwatch = Stopwatch()..start();
  
  try {
    // Check if MQTT broker is already running first
    print('1. Checking for existing MQTT broker...');
    if (await _isPortOpen(1883)) {
      print('✅ MQTT broker already running - test passed!');
      stopwatch.stop();
      print('⏱️ Test completed in ${stopwatch.elapsedMilliseconds}ms');
      return;
    }
    
    // Test MQTT broker startup
    print('2. Starting MQTT broker...');
    await sessionManager.startMqttBroker();
    
    if (sessionManager.isMqttBrokerRunning) {
      print('✅ MQTT broker started successfully');
    } else {
      print('❌ MQTT broker failed to start');
      exit(1);
    }
    
    // Quick connectivity test
    print('3. Quick connectivity test...');
    await _quickConnectivityTest();
    print('✅ MQTT broker is accessible');
    
    stopwatch.stop();
    print('🎉 All tests passed! E2E MQTT setup working correctly.');
    print('⏱️ Test completed in ${stopwatch.elapsedMilliseconds}ms');
    
  } catch (error, stackTrace) {
    stopwatch.stop();
    print('❌ Test failed after ${stopwatch.elapsedMilliseconds}ms: $error');
    print('Stack trace: $stackTrace');
    exit(1);
  } finally {
    // Quick cleanup
    print('4. Cleanup...');
    await sessionManager.stopMqttBroker();
    print('✅ Cleanup completed');
  }
}

/// Fast port check without full socket connection
Future<bool> _isPortOpen(int port) async {
  try {
    final socket = await Socket.connect('localhost', port, timeout: Duration(seconds: 1));
    await socket.close();
    return true;
  } catch (error) {
    return false;
  }
}

/// Quick connectivity test with shorter timeout
Future<void> _quickConnectivityTest() async {
  final socket = await Socket.connect('localhost', 1883, timeout: Duration(seconds: 2));
  await socket.close();
}