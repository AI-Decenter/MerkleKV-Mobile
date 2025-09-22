import 'package:test/test.dart';
import 'package:merkle_kv_core/src/battery/battery_state.dart';
import 'package:merkle_kv_core/src/battery/battery_monitor.dart';

void main() {
  group('DefaultBatteryMonitor', () {
    late DefaultBatteryMonitor monitor;

    setUp(() {
      monitor = DefaultBatteryMonitor();
    });

    tearDown(() async {
      if (monitor.isMonitoring) {
        await monitor.stop();
      }
    });

    test('initial state is not monitoring', () {
      expect(monitor.isMonitoring, isFalse);
      expect(monitor.currentState.level, equals(50));
      expect(monitor.currentState.isCharging, isFalse);
    });

    test('start begins monitoring and emits initial state', () async {
      final stateStream = monitor.batteryState.take(1).toList();
      
      await monitor.start();
      
      expect(monitor.isMonitoring, isTrue);
      final states = await stateStream;
      expect(states, hasLength(1));
      expect(states.first.level, equals(50));
    });

    test('updateState emits new state when monitoring', () async {
      await monitor.start();
      
      final stateStream = monitor.batteryState.take(1).toList();
      final newState = BatteryState.test(level: 75, isCharging: true);
      
      monitor.updateState(newState);
      
      final states = await stateStream;
      expect(states.first.level, equals(75));
      expect(states.first.isCharging, isTrue);
      expect(monitor.currentState.level, equals(75));
    });

    test('updateState does nothing when not monitoring', () {
      final newState = BatteryState.test(level: 75);
      monitor.updateState(newState);
      
      expect(monitor.currentState.level, equals(50)); // unchanged
    });

    test('stop ends monitoring', () async {
      await monitor.start();
      expect(monitor.isMonitoring, isTrue);
      
      await monitor.stop();
      expect(monitor.isMonitoring, isFalse);
    });
  });

  group('TestBatteryMonitor', () {
    late TestBatteryMonitor monitor;

    setUp(() {
      monitor = TestBatteryMonitor();
    });

    tearDown(() async {
      if (monitor.isMonitoring) {
        await monitor.stop();
      }
    });

    test('starts with test default state', () {
      expect(monitor.currentState.level, equals(50));
      expect(monitor.currentState.isCharging, isFalse);
      expect(monitor.currentState.isPowerSaveMode, isFalse);
    });

    test('can be initialized with custom state', () {
      final customState = BatteryState.test(level: 80, isCharging: true);
      final customMonitor = TestBatteryMonitor(initialState: customState);
      
      expect(customMonitor.currentState.level, equals(80));
      expect(customMonitor.currentState.isCharging, isTrue);
    });

    test('simulateLowBattery sets appropriate state', () async {
      await monitor.start();
      
      final stateStream = monitor.batteryState.take(1).toList();
      monitor.simulateLowBattery();
      
      final states = await stateStream;
      expect(states.first.level, equals(15));
      expect(states.first.isCharging, isFalse);
      expect(monitor.currentState.isLow, isTrue);
    });

    test('simulateLowBattery with charging option', () async {
      await monitor.start();
      
      final stateStream = monitor.batteryState.take(1).toList();
      monitor.simulateLowBattery(charging: true);
      
      final states = await stateStream;
      expect(states.first.level, equals(15));
      expect(states.first.isCharging, isTrue);
      expect(monitor.currentState.isCritical, isFalse); // Not critical because charging
    });

    test('simulateCriticalBattery sets critical state', () async {
      await monitor.start();
      
      final stateStream = monitor.batteryState.take(1).toList();
      monitor.simulateCriticalBattery();
      
      final states = await stateStream;
      expect(states.first.level, equals(5));
      expect(states.first.isCharging, isFalse);
      expect(states.first.isPowerSaveMode, isTrue);
      expect(monitor.currentState.isCritical, isTrue);
    });

    test('simulatePowerSaveMode toggles power save state', () async {
      await monitor.start();
      
      // Enable power save mode
      final stateStream1 = monitor.batteryState.take(1).toList();
      monitor.simulatePowerSaveMode(enabled: true);
      
      final states1 = await stateStream1;
      expect(states1.first.isPowerSaveMode, isTrue);
      
      // Disable power save mode
      final stateStream2 = monitor.batteryState.take(1).toList();
      monitor.simulatePowerSaveMode(enabled: false);
      
      final states2 = await stateStream2;
      expect(states2.first.isPowerSaveMode, isFalse);
    });

    test('simulateAppBackgrounded toggles background state', () async {
      await monitor.start();
      
      // Background the app
      final stateStream1 = monitor.batteryState.take(1).toList();
      monitor.simulateAppBackgrounded(backgrounded: true);
      
      final states1 = await stateStream1;
      expect(states1.first.isBackgrounded, isTrue);
      
      // Foreground the app
      final stateStream2 = monitor.batteryState.take(1).toList();
      monitor.simulateAppBackgrounded(backgrounded: false);
      
      final states2 = await stateStream2;
      expect(states2.first.isBackgrounded, isFalse);
    });

    test('simulation methods preserve other state properties', () async {
      await monitor.start();
      
      // Set initial state
      monitor.updateState(BatteryState.test(
        level: 60,
        isCharging: true,
        isPowerSaveMode: false,
        isBackgrounded: false,
      ));
      
      // Simulate power save mode - should preserve other properties
      final stateStream = monitor.batteryState.take(1).toList();
      monitor.simulatePowerSaveMode(enabled: true);
      
      final states = await stateStream;
      expect(states.first.level, equals(60)); // preserved
      expect(states.first.isCharging, isTrue); // preserved
      expect(states.first.isPowerSaveMode, isTrue); // changed
      expect(states.first.isBackgrounded, isFalse); // preserved
    });

    test('multiple state changes emit multiple events', () async {
      await monitor.start();
      
      final stateStream = monitor.batteryState.take(3).toList();
      
      monitor.simulateLowBattery();
      monitor.simulatePowerSaveMode(enabled: true);
      monitor.simulateAppBackgrounded(backgrounded: true);
      
      final states = await stateStream;
      expect(states, hasLength(3));
      
      // Check final state has all changes
      expect(states.last.level, equals(15));
      expect(states.last.isPowerSaveMode, isTrue);
      expect(states.last.isBackgrounded, isTrue);
    });
  });
}