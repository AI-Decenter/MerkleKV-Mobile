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
      // First check if MQTT is already running
      if (await _isMqttBrokerRunning()) {
        print('✅ MQTT broker already accessible on port 1883');
        _brokerStarted = true;
        return;
      }

      // Try Docker first, then fallback to local mosquitto
      bool dockerStarted = await _tryStartDockerBroker();
      
      if (!dockerStarted) {
        await _startLocalMosquitto();
      }
      
      // Verify broker is accessible
      await _verifyBrokerConnectivity();
      
      _brokerStarted = true;
      print('✅ MQTT broker started successfully');
      
    } catch (error) {
      print('❌ Failed to start MQTT broker: $error');
      rethrow;
    }
  }

  /// Check if MQTT broker is already running
  Future<bool> _isMqttBrokerRunning() async {
    try {
      final socket = await Socket.connect('localhost', 1883, timeout: Duration(seconds: 2));
      await socket.close();
      return true;
    } catch (error) {
      return false;
    }
  }

  /// Try to start Docker broker
  Future<bool> _tryStartDockerBroker() async {
    try {
      // Check if Docker is available
      final dockerCheck = await Process.run('docker', ['--version']);
      if (dockerCheck.exitCode != 0) {
        print('⚠️ Docker not available, trying local mosquitto');
        return false;
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
        print('⚠️ Docker start failed: ${dockerRun.stderr}');
        return false;
      }

      // Wait for broker to start (optimized for faster testing)
      await Future.delayed(Duration(seconds: 1));
      return true;

    } catch (error) {
      print('⚠️ Docker error: $error, trying local mosquitto');
      return false;
    }
  }

  /// Start local mosquitto broker
  Future<void> _startLocalMosquitto() async {
    try {
      print('🔄 Starting local mosquitto broker...');
      
      // Check if mosquitto is available
      final mosquittoCheck = await Process.run('which', ['mosquitto']);
      if (mosquittoCheck.exitCode != 0) {
        throw StateError('Neither Docker nor local mosquitto available');
      }

      // Start mosquitto with default config
      final result = await Process.run('mosquitto', ['-v']);
      if (result.exitCode != 0) {
        throw StateError('Failed to start local mosquitto: ${result.stderr}');
      }

      // Wait for broker to start (optimized for faster testing)
      await Future.delayed(Duration(seconds: 1));
      print('✅ Local mosquitto broker started');
      
    } catch (error) {
      throw StateError('Failed to start local mosquitto: $error');
    }
  }

  /// Verify MQTT broker connectivity (fast mode)
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
      // Try to stop Docker container first
      final stopResult = await Process.run(
        'docker',
        ['stop', 'e2e-mqtt-broker'],
      );
      
      if (stopResult.exitCode == 0) {
        print('✅ Docker MQTT broker stopped successfully');
        await Process.run('docker', ['rm', 'e2e-mqtt-broker']);
      } else {
        // If Docker stop failed, try to stop local mosquitto
        final killResult = await Process.run('pkill', ['-f', 'mosquitto']);
        if (killResult.exitCode == 0) {
          print('✅ Local MQTT broker stopped successfully');
        } else {
          print('⚠️ Warning: Failed to stop MQTT broker cleanly');
        }
      }
      
      _brokerStarted = false;
      
    } catch (error) {
      print('❌ Error stopping MQTT broker: $error');
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