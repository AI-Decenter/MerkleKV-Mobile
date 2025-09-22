import 'package:test/test.dart';
import 'package:merkle_kv_core/src/battery/battery_state.dart';

void main() {
  group('BatteryState', () {
    test('creates battery state with all properties', () {
      final timestamp = DateTime.now();
      final state = BatteryState(
        level: 75,
        isCharging: true,
        isPowerSaveMode: false,
        isBackgrounded: false,
        timestamp: timestamp,
      );

      expect(state.level, equals(75));
      expect(state.isCharging, isTrue);
      expect(state.isPowerSaveMode, isFalse);
      expect(state.isBackgrounded, isFalse);
      expect(state.timestamp, equals(timestamp));
    });

    test('test constructor provides reasonable defaults', () {
      final state = BatteryState.test();

      expect(state.level, equals(50));
      expect(state.isCharging, isFalse);
      expect(state.isPowerSaveMode, isFalse);
      expect(state.isBackgrounded, isFalse);
      expect(state.timestamp, isNotNull);
    });

    test('unknown constructor provides conservative defaults', () {
      final state = BatteryState.unknown();

      expect(state.level, equals(50));
      expect(state.isCharging, isFalse);
      expect(state.isPowerSaveMode, isFalse);
      expect(state.isBackgrounded, isFalse);
      expect(state.timestamp, isNotNull);
    });

    test('isCritical returns true for low battery not charging', () {
      final criticalState = BatteryState.test(level: 5, isCharging: false);
      final criticalButCharging = BatteryState.test(level: 5, isCharging: true);
      final lowButNotCritical = BatteryState.test(level: 15, isCharging: false);

      expect(criticalState.isCritical, isTrue);
      expect(criticalButCharging.isCritical, isFalse);
      expect(lowButNotCritical.isCritical, isFalse);
    });

    test('isLow returns true for battery level below 20%', () {
      final lowState = BatteryState.test(level: 15);
      final normalState = BatteryState.test(level: 50);
      final highState = BatteryState.test(level: 80);

      expect(lowState.isLow, isTrue);
      expect(normalState.isLow, isFalse);
      expect(highState.isLow, isFalse);
    });

    test('toString provides readable representation', () {
      final state = BatteryState.test(
        level: 85,
        isCharging: true,
        isPowerSaveMode: false,
        isBackgrounded: true,
      );

      final str = state.toString();
      expect(str, contains('85%'));
      expect(str, contains('charging: true'));
      expect(str, contains('powerSave: false'));
      expect(str, contains('background: true'));
    });

    test('equality works correctly', () {
      final timestamp = DateTime.now();
      final state1 = BatteryState(
        level: 50,
        isCharging: false,
        isPowerSaveMode: false,
        isBackgrounded: false,
        timestamp: timestamp,
      );
      final state2 = BatteryState(
        level: 50,
        isCharging: false,
        isPowerSaveMode: false,
        isBackgrounded: false,
        timestamp: timestamp,
      );
      final state3 = BatteryState(
        level: 75,
        isCharging: false,
        isPowerSaveMode: false,
        isBackgrounded: false,
        timestamp: timestamp,
      );

      expect(state1, equals(state2));
      expect(state1, isNot(equals(state3)));
      expect(state1.hashCode, equals(state2.hashCode));
    });
  });
}