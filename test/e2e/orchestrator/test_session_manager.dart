import 'dart:async';
import 'dart:io';
import '../scenarios/e2e_scenario.dart';

/// Manages test sessions including setup, cleanup, and resource management
class TestSessionManager {
  final Map<String, TestSession> _activeSessions = {};
  bool _brokerStarted = false;

  /// Initialize a new test session for the given scenario
  Future<TestSession> initializeSession(E2EScenario scenario) async {
    final sessionId = _generateSessionId();
    final session = TestSession(
      id: sessionId,
      scenario: scenario,
      startTime: DateTime.now(),
    );

    _activeSessions[sessionId] = session;
    
    print('📝 Initialized test session: $sessionId for ${scenario.name}');
    
    return session;
  }

  /// Start MQTT broker if not already running
  Future<void> startMqttBroker() async {
    if (_brokerStarted) {
      print('🔄 MQTT broker already running');
      return;
    }

    print('🚀 Starting MQTT broker...');
    
    try {
      // First check if MQTT broker is already running on port 1883
      if (await _isBrokerAlreadyRunning()) {
        print('✅ MQTT broker already running on port 1883');
        _brokerStarted = true;
        return;
      }

      // Check if Docker is available
      final dockerCheck = await Process.run('docker', ['--version']);
      if (dockerCheck.exitCode != 0) {
        print('⚠️ Docker not available in CI environment - skipping MQTT broker startup');
        print('ℹ️ Tests will use external MQTT broker if available');
        _brokerStarted = true; // Mark as started to skip cleanup
        return;
      }

      // Remove existing container if it exists
      await Process.run('docker', ['rm', '-f', 'e2e-mqtt-broker']);

      // Start Mosquitto broker in Docker
      final dockerRun = await Process.run(
        'docker',
        [
          'run',
          '-d',
          '--name', 'e2e-mqtt-broker',
          '-p', '1883:1883',
          'eclipse-mosquitto:1.6'
        ],
      );

      if (dockerRun.exitCode != 0) {
        throw StateError('Failed to start Docker container: ${dockerRun.stderr}');
      }

      // Wait for broker to start
      await Future.delayed(Duration(seconds: 1));
      
      // Verify broker is accessible
      await _verifyBrokerConnectivity();
      
      _brokerStarted = true;
      print('✅ MQTT broker started successfully');
      
    } catch (error) {
      print('❌ Failed to start MQTT broker: $error');
      rethrow;
    }
  }

  /// Check if MQTT broker is already running on port 1883
  Future<bool> _isBrokerAlreadyRunning() async {
    try {
      final socket = await Socket.connect('localhost', 1883, timeout: Duration(seconds: 2));
      await socket.close();
      return true;
    } catch (error) {
      return false;
    }
  }

  /// Verify MQTT broker connectivity
  Future<void> _verifyBrokerConnectivity() async {
    try {
      final socket = await Socket.connect('localhost', 1883, timeout: Duration(seconds: 2));
      await socket.close();
    } catch (error) {
      throw StateError('MQTT broker is not accessible: $error');
    }
  }

  /// Stop MQTT broker
  Future<void> stopMqttBroker() async {
    if (!_brokerStarted) {
      return;
    }

    print('🛑 Stopping MQTT broker...');
    
    try {
      // Check if Docker is available before trying to stop container
      final dockerCheck = await Process.run('docker', ['--version']);
      if (dockerCheck.exitCode != 0) {
        print('ℹ️ Docker not available - skipping container cleanup');
        _brokerStarted = false;
        return;
      }

      // Stop the Docker container
      final stopResult = await Process.run(
        'docker',
        ['stop', 'e2e-mqtt-broker'],
      );
      
      if (stopResult.exitCode == 0) {
        print('✅ MQTT broker stopped successfully');
      } else {
        print('⚠️ Warning: Failed to stop MQTT broker cleanly');
      }

      // Remove the container
      await Process.run('docker', ['rm', 'e2e-mqtt-broker']);
      
      _brokerStarted = false;
      
    } catch (error) {
      print('❌ Error stopping MQTT broker: $error');
      _brokerStarted = false; // Reset state even if cleanup failed
    }
  }

  /// Cleanup a test session
  Future<void> cleanupSession(TestSession session) async {
    print('🧹 Cleaning up test session: ${session.id}');
    
    session.endTime = DateTime.now();
    _activeSessions.remove(session.id);
    
    // Additional cleanup per session can be added here
  }

  /// Cleanup all resources
  Future<void> cleanup() async {
    print('🧹 Cleaning up TestSessionManager...');
    
    // Cleanup all active sessions
    for (final session in _activeSessions.values) {
      await cleanupSession(session);
    }
    
    // Stop MQTT broker
    await stopMqttBroker();
  }

  /// Generate unique session ID
  String _generateSessionId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecond;
    return 'session_${timestamp}_$random';
  }

  /// Get active sessions count
  int get activeSessionsCount => _activeSessions.length;

  /// Check if MQTT broker is running
  bool get isMqttBrokerRunning => _brokerStarted;
}

/// Represents a test session
class TestSession {
  final String id;
  final E2EScenario scenario;
  final DateTime startTime;
  DateTime? endTime;
  final Map<String, dynamic> metadata = {};

  TestSession({
    required this.id,
    required this.scenario,
    required this.startTime,
  });

  /// Get session duration
  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  /// Add metadata to session
  void addMetadata(String key, dynamic value) {
    metadata[key] = value;
  }

  /// Get metadata from session
  T? getMetadata<T>(String key) {
    return metadata[key] as T?;
  }
}