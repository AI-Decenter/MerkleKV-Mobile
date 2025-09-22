import 'package:test/test.dart';
import 'package:merkle_kv_core/src/battery/battery_state.dart';
import 'package:merkle_kv_core/src/battery/battery_aware_reconnect_policy.dart';

void main() {
  group('BatteryAwareReconnectPolicy', () {
    late BatteryAwareReconnectPolicy policy;

    setUp(() {
      policy = const BatteryAwareReconnectPolicy();
    });

    group('calculateBackoff', () {
      test('follows Locked Spec exponential backoff timing', () {
        // Test the exponential progression: 1s → 2s → 4s → 8s → 16s → 32s
        final delays = <int>[];
        for (int attempt = 0; attempt < 10; attempt++) {
          final backoff = policy.calculateBackoff(attempt);
          delays.add(backoff.inSeconds);
        }

        // Verify exponential progression with max cap at 32 seconds
        expect(delays[0], inInclusiveRange(1, 2)); // ~1s ±20%
        expect(delays[1], inInclusiveRange(1, 3)); // ~2s ±20%
        expect(delays[2], inInclusiveRange(3, 5)); // ~4s ±20%
        expect(delays[3], inInclusiveRange(6, 10)); // ~8s ±20%
        expect(delays[4], inInclusiveRange(12, 20)); // ~16s ±20%
        expect(delays[5], inInclusiveRange(25, 39)); // ~32s ±20%
        expect(delays[6], inInclusiveRange(25, 39)); // Still ~32s (capped)
      });

      test('includes jitter within ±20% range', () {
        final backoffs = <Duration>[];
        for (int i = 0; i < 50; i++) {
          backoffs.add(policy.calculateBackoff(3)); // 8s base delay
        }

        // Check that we get variation (jitter is working)
        final uniqueDelays = backoffs.map((d) => d.inSeconds).toSet();
        expect(uniqueDelays.length, greaterThan(1));

        // All delays should be within ±20% of 8 seconds
        for (final backoff in backoffs) {
          expect(backoff.inSeconds, inInclusiveRange(6, 10)); // 8s ±20%
        }
      });
    });

    group('shouldAttemptReconnection - default policy', () {
      test('allows reconnection under normal conditions', () {
        final normalState = BatteryState.test(
          level: 50,
          isCharging: false,
          isPowerSaveMode: false,
          isBackgrounded: false,
        );

        expect(policy.shouldAttemptReconnection(normalState, 0), isTrue);
        expect(policy.shouldAttemptReconnection(normalState, 2), isTrue);
        expect(policy.shouldAttemptReconnection(normalState, 5), isTrue);
      });

      test('gates reconnection after max attempts in power save mode', () {
        final powerSaveState = BatteryState.test(
          level: 50,
          isPowerSaveMode: true,
        );

        expect(policy.shouldAttemptReconnection(powerSaveState, 1), isTrue);
        expect(policy.shouldAttemptReconnection(powerSaveState, 3), isTrue);
        expect(policy.shouldAttemptReconnection(powerSaveState, 4), isFalse);
        expect(policy.shouldAttemptReconnection(powerSaveState, 10), isFalse);
      });

      test('gates reconnection after max attempts on critical battery', () {
        final criticalState = BatteryState.test(
          level: 5,
          isCharging: false, // Critical = low level + not charging
        );

        expect(policy.shouldAttemptReconnection(criticalState, 1), isTrue);
        expect(policy.shouldAttemptReconnection(criticalState, 2), isTrue);
        expect(policy.shouldAttemptReconnection(criticalState, 3), isFalse);
        expect(policy.shouldAttemptReconnection(criticalState, 10), isFalse);
      });

      test('allows reconnection on low battery if charging', () {
        final lowButChargingState = BatteryState.test(
          level: 5,
          isCharging: true, // Not critical because charging
        );

        expect(policy.shouldAttemptReconnection(lowButChargingState, 5), isTrue);
        expect(policy.shouldAttemptReconnection(lowButChargingState, 10), isTrue);
      });

      test('gates reconnection after max attempts when backgrounded', () {
        final backgroundedState = BatteryState.test(
          level: 80,
          isBackgrounded: true,
        );

        expect(policy.shouldAttemptReconnection(backgroundedState, 3), isTrue);
        expect(policy.shouldAttemptReconnection(backgroundedState, 5), isTrue);
        expect(policy.shouldAttemptReconnection(backgroundedState, 6), isFalse);
        expect(policy.shouldAttemptReconnection(backgroundedState, 10), isFalse);
      });
    });

    group('disabled policy', () {
      test('never gates reconnection attempts', () {
        final disabledPolicy = const BatteryAwareReconnectPolicy.disabled();
        final worstCaseState = BatteryState.test(
          level: 1,
          isCharging: false,
          isPowerSaveMode: true,
          isBackgrounded: true,
        );

        expect(disabledPolicy.shouldAttemptReconnection(worstCaseState, 0), isTrue);
        expect(disabledPolicy.shouldAttemptReconnection(worstCaseState, 100), isTrue);
        expect(disabledPolicy.shouldAttemptReconnection(worstCaseState, 999), isTrue);
      });
    });

    group('conservative policy', () {
      test('gates reconnection very aggressively', () {
        final conservativePolicy = const BatteryAwareReconnectPolicy.conservative();
        
        final powerSaveState = BatteryState.test(isPowerSaveMode: true);
        expect(conservativePolicy.shouldAttemptReconnection(powerSaveState, 1), isTrue);
        expect(conservativePolicy.shouldAttemptReconnection(powerSaveState, 2), isFalse);

        final criticalState = BatteryState.test(level: 5, isCharging: false);
        expect(conservativePolicy.shouldAttemptReconnection(criticalState, 1), isTrue);
        expect(conservativePolicy.shouldAttemptReconnection(criticalState, 2), isFalse);

        final backgroundedState = BatteryState.test(isBackgrounded: true);
        expect(conservativePolicy.shouldAttemptReconnection(backgroundedState, 2), isTrue);
        expect(conservativePolicy.shouldAttemptReconnection(backgroundedState, 3), isFalse);
      });
    });

    group('getGatingReason', () {
      test('returns null when reconnection should be allowed', () {
        final normalState = BatteryState.test();
        expect(policy.getGatingReason(normalState, 1), isNull);
      });

      test('returns descriptive reason for power save gating', () {
        final powerSaveState = BatteryState.test(isPowerSaveMode: true);
        final reason = policy.getGatingReason(powerSaveState, 4);
        
        expect(reason, isNotNull);
        expect(reason, contains('Power save mode'));
        expect(reason, contains('3'));
      });

      test('returns descriptive reason for critical battery gating', () {
        final criticalState = BatteryState.test(level: 5, isCharging: false);
        final reason = policy.getGatingReason(criticalState, 3);
        
        expect(reason, isNotNull);
        expect(reason, contains('Critical battery'));
        expect(reason, contains('5%'));
        expect(reason, contains('2'));
      });

      test('returns descriptive reason for background gating', () {
        final backgroundedState = BatteryState.test(isBackgrounded: true);
        final reason = policy.getGatingReason(backgroundedState, 6);
        
        expect(reason, isNotNull);
        expect(reason, contains('App backgrounded'));
        expect(reason, contains('5'));
      });
    });

    group('copyWith', () {
      test('creates copy with modified parameters', () {
        final original = const BatteryAwareReconnectPolicy(
          maxAttemptsInPowerSave: 3,
          maxAttemptsOnCriticalBattery: 2,
          enableBatteryGating: true,
        );

        final modified = original.copyWith(
          maxAttemptsInPowerSave: 5,
          enableBatteryGating: false,
        );

        expect(modified.maxAttemptsInPowerSave, equals(5));
        expect(modified.maxAttemptsOnCriticalBattery, equals(2)); // unchanged
        expect(modified.enableBatteryGating, isFalse);
      });
    });

    group('toString and equality', () {
      test('toString provides readable representation', () {
        final str = policy.toString();
        expect(str, contains('BatteryAwareReconnectPolicy'));
        expect(str, contains('enabled: true'));
        expect(str, contains('powerSave: 3'));
      });

      test('equality works correctly', () {
        final policy1 = const BatteryAwareReconnectPolicy(maxAttemptsInPowerSave: 5);
        final policy2 = const BatteryAwareReconnectPolicy(maxAttemptsInPowerSave: 5);
        final policy3 = const BatteryAwareReconnectPolicy(maxAttemptsInPowerSave: 3);

        expect(policy1, equals(policy2));
        expect(policy1, isNot(equals(policy3)));
        expect(policy1.hashCode, equals(policy2.hashCode));
      });
    });
  });
}