import 'dart:async';
import 'battery_state.dart';

/// Interface for monitoring battery state across different platforms.
///
/// Provides battery level, charging status, and power management information
/// to support intelligent connection policies on mobile devices.
abstract class BatteryMonitor {
  /// Stream of battery state changes.
  ///
  /// Emits new [BatteryState] whenever battery level, charging status,
  /// or power save mode changes significantly.
  Stream<BatteryState> get batteryState;

  /// Current battery state.
  ///
  /// Returns the most recent battery state information, or a default
  /// unknown state if not available.
  BatteryState get currentState;

  /// Starts monitoring battery state changes.
  ///
  /// Should be called once to begin receiving battery state updates.
  Future<void> start();

  /// Stops monitoring battery state changes.
  ///
  /// Cleans up resources and stops battery state monitoring.
  Future<void> stop();

  /// Whether battery monitoring is currently active.
  bool get isMonitoring;
}

/// Default battery monitor implementation that provides mock data.
///
/// This implementation is used when no platform-specific battery monitor
/// is available. It provides conservative default values to ensure
/// battery-aware policies don't interfere with normal operation.
class DefaultBatteryMonitor implements BatteryMonitor {
  final StreamController<BatteryState> _stateController =
      StreamController<BatteryState>.broadcast();

  BatteryState _currentState = BatteryState.unknown();
  bool _isMonitoring = false;

  @override
  Stream<BatteryState> get batteryState => _stateController.stream;

  @override
  BatteryState get currentState => _currentState;

  @override
  bool get isMonitoring => _isMonitoring;

  @override
  Future<void> start() async {
    if (_isMonitoring) return;

    _isMonitoring = true;
    _currentState = BatteryState.unknown();
    _stateController.add(_currentState);
  }

  @override
  Future<void> stop() async {
    if (!_isMonitoring) return;

    _isMonitoring = false;
    await _stateController.close();
  }

  /// Updates the battery state (for testing or manual updates).
  void updateState(BatteryState newState) {
    if (_isMonitoring && !_stateController.isClosed) {
      _currentState = newState;
      _stateController.add(newState);
    }
  }
}

/// Battery monitor for testing purposes.
///
/// Allows manual control over battery state for testing battery-aware
/// reconnection policies.
class TestBatteryMonitor implements BatteryMonitor {
  final StreamController<BatteryState> _stateController =
      StreamController<BatteryState>.broadcast();

  BatteryState _currentState;
  bool _isMonitoring = false;

  /// Creates a test battery monitor with initial state.
  TestBatteryMonitor({BatteryState? initialState})
      : _currentState = initialState ?? BatteryState.test();

  @override
  Stream<BatteryState> get batteryState => _stateController.stream;

  @override
  BatteryState get currentState => _currentState;

  @override
  bool get isMonitoring => _isMonitoring;

  @override
  Future<void> start() async {
    if (_isMonitoring) return;

    _isMonitoring = true;
    _stateController.add(_currentState);
  }

  @override
  Future<void> stop() async {
    if (!_isMonitoring) return;

    _isMonitoring = false;
    await _stateController.close();
  }

  /// Updates the battery state for testing.
  void updateState(BatteryState newState) {
    if (_isMonitoring && !_stateController.isClosed) {
      _currentState = newState;
      _stateController.add(newState);
    }
  }

  /// Simulates low battery condition.
  void simulateLowBattery({bool charging = false}) {
    updateState(BatteryState(
      level: 15,
      isCharging: charging,
      isPowerSaveMode: false,
      isBackgrounded: _currentState.isBackgrounded,
      timestamp: DateTime.now(),
    ));
  }

  /// Simulates critical battery condition.
  void simulateCriticalBattery() {
    updateState(BatteryState(
      level: 5,
      isCharging: false,
      isPowerSaveMode: true,
      isBackgrounded: _currentState.isBackgrounded,
      timestamp: DateTime.now(),
    ));
  }

  /// Simulates power save mode.
  void simulatePowerSaveMode({bool enabled = true}) {
    updateState(BatteryState(
      level: _currentState.level,
      isCharging: _currentState.isCharging,
      isPowerSaveMode: enabled,
      isBackgrounded: _currentState.isBackgrounded,
      timestamp: DateTime.now(),
    ));
  }

  /// Simulates app backgrounding.
  void simulateAppBackgrounded({bool backgrounded = true}) {
    updateState(BatteryState(
      level: _currentState.level,
      isCharging: _currentState.isCharging,
      isPowerSaveMode: _currentState.isPowerSaveMode,
      isBackgrounded: backgrounded,
      timestamp: DateTime.now(),
    ));
  }
}