import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'test_session_manager.dart';
import '../scenarios/e2e_scenario.dart';

/// iOS-specific test session manager that handles iOS app lifecycle and XCTest integration
class IOSTestSessionManager extends TestSessionManager {
  String? _deviceUDID;
  String? _appBundleId;
  Map<String, String> _iosSimulators = {};
  
  @override
  Future<TestSession> initializeSession(E2EScenario scenario) async {
    print('🍎 Initializing iOS test session...');
    
    final session = await super.initializeSession(scenario);
    
    // iOS-specific initialization
    await _setupIOSEnvironment();
    if (scenario.requiresAppLaunch) {
      await _launchIOSApp();
    }
    
    return session;
  }

  /// Setup iOS development environment
  Future<void> _setupIOSEnvironment() async {
    print('🔧 Setting up iOS environment...');
    
    // Check Xcode and iOS Simulator availability
    await _checkXcodeAvailability();
    await _setupIOSSimulator();
  }

  /// Check if Xcode and required tools are available
  Future<void> _checkXcodeAvailability() async {
    print('🔍 Checking Xcode availability...');
    
    // Check xcodebuild
    final xcodeCheck = await Process.run('which', ['xcodebuild']);
    if (xcodeCheck.exitCode != 0) {
      throw StateError('Xcode not found. Please install Xcode and command line tools.');
    }

    // Check iOS Simulator
    final simCheck = await Process.run('which', ['xcrun']);
    if (simCheck.exitCode != 0) {
      throw StateError('xcrun not found. Please install Xcode command line tools.');
    }

    // Verify Xcode version
    final versionResult = await Process.run('xcodebuild', ['-version']);
    print('✅ Xcode environment verified: ${versionResult.stdout.toString().split('\n')[0]}');
  }

  /// Setup and start iOS Simulator
  Future<void> _setupIOSSimulator() async {
    print('📱 Setting up iOS Simulator...');

    // List available simulators
    final simListResult = await Process.run(
      'xcrun', 
      ['simctl', 'list', 'devices', 'available', '--json']
    );

    if (simListResult.exitCode != 0) {
      throw StateError('Failed to list iOS simulators: ${simListResult.stderr}');
    }

    // Parse available simulators
    await _parseAvailableSimulators(simListResult.stdout.toString());
    
    // Find or create suitable simulator
    _deviceUDID = await _findBestSimulator();
    
    // Boot the simulator if not already booted
    await _bootSimulator(_deviceUDID!);
    
    print('✅ iOS Simulator ready: $_deviceUDID');
  }

  /// Parse available simulators from JSON
  Future<void> _parseAvailableSimulators(String jsonOutput) async {
    try {
      final data = json.decode(jsonOutput);
      final devices = data['devices'] as Map<String, dynamic>;
      
      _iosSimulators.clear();
      
      for (final runtimeKey in devices.keys) {
        if (runtimeKey.contains('iOS') && !runtimeKey.contains('watchOS')) {
          final deviceList = devices[runtimeKey] as List;
          for (final device in deviceList) {
            if (device['isAvailable'] == true) {
              final name = device['name'] as String;
              final udid = device['udid'] as String;
              _iosSimulators[name] = udid;
            }
          }
        }
      }
      
      print('📋 Found ${_iosSimulators.length} available iOS simulators');
    } catch (e) {
      print('⚠️ Failed to parse simulators, using fallback method: $e');
    }
  }

  /// Find the best available simulator
  Future<String> _findBestSimulator() async {
    // Preferred simulator types in order
    final preferredSimulators = [
      'iPhone 15',
      'iPhone 14',
      'iPhone 13',
      'iPhone 12',
      'iPhone SE (3rd generation)',
    ];

    // Try to find preferred simulator
    for (final preferred in preferredSimulators) {
      for (final simName in _iosSimulators.keys) {
        if (simName.contains(preferred)) {
          print('🎯 Selected simulator: $simName');
          return _iosSimulators[simName]!;
        }
      }
    }

    // If no preferred found, use first available
    if (_iosSimulators.isNotEmpty) {
      final firstSim = _iosSimulators.entries.first;
      print('📱 Using first available simulator: ${firstSim.key}');
      return firstSim.value;
    }

    // Create a new simulator if none available
    return await _createTestSimulator();
  }

  /// Create a new test simulator
  Future<String> _createTestSimulator() async {
    print('🔨 Creating new iOS test simulator...');

    final createResult = await Process.run(
      'xcrun',
      [
        'simctl', 'create',
        'MerkleKV-E2E-Test',
        'iPhone 14',
        'iOS16.4'  // Adjust based on available runtime
      ]
    );

    if (createResult.exitCode != 0) {
      throw StateError('Failed to create iOS simulator: ${createResult.stderr}');
    }

    final udid = createResult.stdout.toString().trim();
    print('✅ Created test simulator: $udid');
    return udid;
  }

  /// Boot the iOS simulator
  Future<void> _bootSimulator(String udid) async {
    print('🚀 Booting iOS Simulator: $udid');

    final bootResult = await Process.run(
      'xcrun',
      ['simctl', 'boot', udid]
    );

    // Simulator might already be booted - that's OK
    if (bootResult.exitCode != 0 && 
        !bootResult.stderr.toString().contains('current state: Booted') &&
        !bootResult.stderr.toString().contains('Unable to boot device in current state: Booted')) {
      throw StateError('Failed to boot simulator: ${bootResult.stderr}');
    }

    // Wait for simulator to be fully booted
    await _waitForSimulatorBoot(udid);
    
    print('✅ iOS Simulator booted successfully');
  }

  /// Wait for simulator to be fully booted
  Future<void> _waitForSimulatorBoot(String udid) async {
    print('⏳ Waiting for simulator to fully boot...');
    
    for (int i = 0; i < 60; i++) {
      final statusResult = await Process.run(
        'xcrun',
        ['simctl', 'list', 'devices', udid]
      );

      if (statusResult.stdout.toString().contains('(Booted)')) {
        // Additional wait for services to be ready
        await Future.delayed(Duration(seconds: 5));
        return;
      }

      await Future.delayed(Duration(seconds: 2));
    }

    throw StateError('Timeout waiting for simulator to boot');
  }

  /// Launch iOS app on simulator
  Future<void> _launchIOSApp() async {
    print('📱 Launching iOS app...');

    // Build and install app if needed
    await _buildAndInstallIOSApp();
    
    // Launch the app
    await _startIOSApp();
    
    print('✅ iOS app launched successfully');
  }

  /// Build and install iOS app on simulator
  Future<void> _buildAndInstallIOSApp() async {
    final appPath = 'apps/flutter_demo/build/ios/iphonesimulator/Runner.app';
    
    if (!await Directory(appPath).exists()) {
      print('🔨 Building iOS app for simulator...');
      await _buildIOSApp();
    }

    print('📦 Installing iOS app on simulator...');
    final installResult = await Process.run(
      'xcrun',
      ['simctl', 'install', _deviceUDID!, appPath]
    );

    if (installResult.exitCode != 0) {
      throw StateError('Failed to install iOS app: ${installResult.stderr}');
    }

    print('✅ iOS app installed');
  }

  /// Build iOS app for simulator
  Future<void> _buildIOSApp() async {
    print('🔨 Building iOS app for simulator...');

    final buildResult = await Process.run(
      'flutter',
      [
        'build', 'ios',
        '--simulator',
        '--debug',
      ],
      workingDirectory: 'apps/flutter_demo'
    );

    if (buildResult.exitCode != 0) {
      throw StateError('Failed to build iOS app: ${buildResult.stderr}');
    }

    print('✅ iOS app built successfully');
  }

  /// Start iOS app on simulator
  Future<void> _startIOSApp() async {
    _appBundleId = 'com.example.merkleKvDemo'; // Adjust based on your app

    final launchResult = await Process.run(
      'xcrun',
      ['simctl', 'launch', _deviceUDID!, _appBundleId!]
    );

    if (launchResult.exitCode != 0) {
      throw StateError('Failed to launch iOS app: ${launchResult.stderr}');
    }

    // Wait for app to be fully launched
    await Future.delayed(Duration(seconds: 5));
  }

  /// iOS-specific MQTT broker start (optimized for macOS)
  @override
  Future<void> startMqttBroker() async {
    // On macOS, prefer native mosquitto for better performance
    if (Platform.isMacOS) {
      await _ensureMosquittoOnMacOS();
    }
    
    await super.startMqttBroker();
  }

  /// Ensure mosquitto is available on macOS
  Future<void> _ensureMosquittoOnMacOS() async {
    final mosquittoCheck = await Process.run('which', ['mosquitto']);
    if (mosquittoCheck.exitCode != 0) {
      print('📦 Installing mosquitto via Homebrew...');
      
      // Check if Homebrew is available
      final brewCheck = await Process.run('which', ['brew']);
      if (brewCheck.exitCode != 0) {
        throw StateError('Homebrew not found. Please install Homebrew to use mosquitto.');
      }

      final installResult = await Process.run('brew', ['install', 'mosquitto']);
      if (installResult.exitCode != 0) {
        throw StateError('Failed to install mosquitto: ${installResult.stderr}');
      }

      print('✅ mosquitto installed via Homebrew');
    }
  }

  /// Simulate iOS app lifecycle events
  Future<void> simulateIOSLifecycleEvent(String event) async {
    if (_deviceUDID == null || _appBundleId == null) {
      throw StateError('iOS app not properly initialized');
    }

    switch (event) {
      case 'background':
        await _moveAppToBackground();
        break;
      case 'foreground':
        await _bringAppToForeground();
        break;
      case 'suspend':
        await _suspendApp();
        break;
      case 'terminate':
        await _terminateApp();
        break;
      default:
        throw StateError('Unsupported lifecycle event: $event');
    }
  }

  /// Move app to background (simulate home button press)
  Future<void> _moveAppToBackground() async {
    print('📱 Moving app to background...');
    
    // Simulate home button press
    final homeResult = await Process.run(
      'xcrun',
      ['simctl', 'keycode', _deviceUDID!, '1'] // Home button keycode
    );

    if (homeResult.exitCode != 0) {
      print('⚠️ Failed to simulate home button: ${homeResult.stderr}');
    }

    await Future.delayed(Duration(seconds: 1));
    print('✅ App moved to background');
  }

  /// Bring app to foreground
  Future<void> _bringAppToForeground() async {
    print('📱 Bringing app to foreground...');
    
    final launchResult = await Process.run(
      'xcrun',
      ['simctl', 'launch', _deviceUDID!, _appBundleId!]
    );

    if (launchResult.exitCode != 0) {
      print('⚠️ Failed to bring app to foreground: ${launchResult.stderr}');
    }

    await Future.delayed(Duration(seconds: 2));
    print('✅ App brought to foreground');
  }

  /// Suspend app (deeper background state)
  Future<void> _suspendApp() async {
    print('📱 Suspending app...');
    
    // Move to background first
    await _moveAppToBackground();
    
    // Wait for suspension to take effect
    await Future.delayed(Duration(seconds: 3));
    print('✅ App suspended');
  }

  /// Terminate app
  Future<void> _terminateApp() async {
    print('📱 Terminating app...');
    
    final terminateResult = await Process.run(
      'xcrun',
      ['simctl', 'terminate', _deviceUDID!, _appBundleId!]
    );

    if (terminateResult.exitCode != 0) {
      print('⚠️ Failed to terminate app: ${terminateResult.stderr}');
    }

    await Future.delayed(Duration(seconds: 1));
    print('✅ App terminated');
  }

  @override
  Future<void> cleanup() async {
    print('🧹 Cleaning up iOS test session...');

    // Terminate iOS app
    if (_appBundleId != null && _deviceUDID != null) {
      try {
        await Process.run(
          'xcrun',
          ['simctl', 'terminate', _deviceUDID!, _appBundleId!]
        );
      } catch (e) {
        print('⚠️ Failed to terminate app during cleanup: $e');
      }
    }

    // Shutdown simulator
    if (_deviceUDID != null) {
      try {
        await Process.run(
          'xcrun',
          ['simctl', 'shutdown', _deviceUDID!]
        );
        print('✅ iOS Simulator shutdown');
      } catch (e) {
        print('⚠️ Failed to shutdown simulator: $e');
      }
    }

    // Cleanup parent resources
    await super.cleanup();
  }

  /// Get iOS device information
  Map<String, String> getDeviceInfo() {
    return {
      'deviceUDID': _deviceUDID ?? 'unknown',
      'appBundleId': _appBundleId ?? 'unknown',
      'platform': 'iOS',
      'simulatorCount': _iosSimulators.length.toString(),
    };
  }
}