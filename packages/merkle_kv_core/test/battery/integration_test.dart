import 'package:test/test.dart';
import 'package:merkle_kv_core/src/battery/battery_state.dart';
import 'package:merkle_kv_core/src/battery/battery_monitor.dart';
import 'package:merkle_kv_core/src/battery/battery_aware_reconnect_policy.dart';
import 'package:merkle_kv_core/src/mqtt/mqtt_client_impl.dart';
import 'package:merkle_kv_core/src/config/merkle_kv_config.dart';

void main() {
  group('Battery-aware MQTT Client Integration', () {
    late MerkleKVConfig config;
    late TestBatteryMonitor batteryMonitor;
    late BatteryAwareReconnectPolicy reconnectPolicy;

    setUp(() {
      config = MerkleKVConfig(
        mqttHost: 'localhost',
        mqttPort: 1883,
        clientId: 'test-battery-client',
        nodeId: 'test-battery-node',
      );
      batteryMonitor = TestBatteryMonitor();
      reconnectPolicy = const BatteryAwareReconnectPolicy();
    });

    tearDown(() async {
      if (batteryMonitor.isMonitoring) {
        await batteryMonitor.stop();
      }
    });

    test('MQTT client integrates with battery monitor', () {
      final mqttClient = MqttClientImpl(
        config,
        batteryMonitor: batteryMonitor,
        reconnectPolicy: reconnectPolicy,
      );

      expect(mqttClient.batteryMonitor, equals(batteryMonitor));
      expect(mqttClient.reconnectPolicy, equals(reconnectPolicy));
    });

    test('MQTT client uses default components when not provided', () {
      final mqttClient = MqttClientImpl(config);

      expect(mqttClient.batteryMonitor, isA<DefaultBatteryMonitor>());
      expect(mqttClient.reconnectPolicy, isA<BatteryAwareReconnectPolicy>());
    });

    test('battery state affects reconnection gating decisions', () {
      final policy = const BatteryAwareReconnectPolicy(
        maxAttemptsInPowerSave: 2,
        maxAttemptsOnCriticalBattery: 1,
      );

      // Normal conditions - allow reconnection
      final normalState = BatteryState.test();
      expect(policy.shouldAttemptReconnection(normalState, 5), isTrue);

      // Power save mode - gate after threshold
      final powerSaveState = BatteryState.test(isPowerSaveMode: true);
      expect(policy.shouldAttemptReconnection(powerSaveState, 2), isTrue);
      expect(policy.shouldAttemptReconnection(powerSaveState, 3), isFalse);

      // Critical battery - gate after threshold
      final criticalState = BatteryState.test(level: 5, isCharging: false);
      expect(policy.shouldAttemptReconnection(criticalState, 1), isTrue);
      expect(policy.shouldAttemptReconnection(criticalState, 2), isFalse);
    });

    test('backoff timing always follows Locked Spec regardless of battery', () {
      final policy = const BatteryAwareReconnectPolicy();

      // Test multiple attempts - timing should be consistent regardless of battery state
      for (int attempt = 0; attempt < 6; attempt++) {
        final backoff = policy.calculateBackoff(attempt);

        // Timing should be within the expected Locked Spec range
        final expectedMin = (1 << attempt) * 0.8; // Base delay minus 20% jitter
        final expectedMax = (attempt < 5 ? (1 << attempt) : 32) * 1.2; // Base delay plus 20% jitter, capped at 32s

        expect(backoff.inSeconds, greaterThanOrEqualTo(expectedMin.round()));
        expect(backoff.inSeconds, lessThanOrEqualTo(expectedMax.round()));
      }
    });

    test('conservative policy gates reconnection more aggressively', () {
      final conservativePolicy = const BatteryAwareReconnectPolicy.conservative();
      final defaultPolicy = const BatteryAwareReconnectPolicy();

      final powerSaveState = BatteryState.test(isPowerSaveMode: true);

      // Conservative policy should gate earlier
      expect(defaultPolicy.shouldAttemptReconnection(powerSaveState, 3), isTrue);
      expect(conservativePolicy.shouldAttemptReconnection(powerSaveState, 3), isFalse);

      // But timing should still be the same
      final conservativeBackoff = conservativePolicy.calculateBackoff(2);
      final defaultBackoff = defaultPolicy.calculateBackoff(2);
      
      // Both should be around 4s ±20%, so within reasonable range of each other
      expect((conservativeBackoff.inSeconds - defaultBackoff.inSeconds).abs(), lessThan(2));
    });

    test('disabled policy never gates reconnection', () {
      final disabledPolicy = const BatteryAwareReconnectPolicy.disabled();
      final worstCaseState = BatteryState.test(
        level: 1,
        isCharging: false,
        isPowerSaveMode: true,
        isBackgrounded: true,
      );

      // Should allow reconnection even under worst conditions
      expect(disabledPolicy.shouldAttemptReconnection(worstCaseState, 100), isTrue);
      expect(disabledPolicy.getGatingReason(worstCaseState, 100), isNull);
    });

    test('battery monitor provides test simulation capabilities', () async {
      await batteryMonitor.start();
      
      // Start with normal state
      expect(batteryMonitor.currentState.level, equals(50));
      expect(batteryMonitor.currentState.isCritical, isFalse);

      // Simulate critical battery
      batteryMonitor.simulateCriticalBattery();
      expect(batteryMonitor.currentState.level, equals(5));
      expect(batteryMonitor.currentState.isCritical, isTrue);
      expect(batteryMonitor.currentState.isPowerSaveMode, isTrue);

      // Simulate charging
      batteryMonitor.simulateLowBattery(charging: true);
      expect(batteryMonitor.currentState.level, equals(15));
      expect(batteryMonitor.currentState.isCharging, isTrue);
      expect(batteryMonitor.currentState.isCritical, isFalse); // Not critical when charging

      // Simulate app backgrounding
      batteryMonitor.simulateAppBackgrounded();
      expect(batteryMonitor.currentState.isBackgrounded, isTrue);
    });

    test('gating reasons provide helpful diagnostics', () {
      final policy = const BatteryAwareReconnectPolicy(
        maxAttemptsInPowerSave: 2,
        maxAttemptsOnCriticalBattery: 1,
        maxAttemptsWhenBackgrounded: 3,
      );

      // Power save gating reason
      final powerSaveState = BatteryState.test(isPowerSaveMode: true);
      final powerSaveReason = policy.getGatingReason(powerSaveState, 3);
      expect(powerSaveReason, contains('Power save mode'));
      expect(powerSaveReason, contains('2'));

      // Critical battery gating reason
      final criticalState = BatteryState.test(level: 8, isCharging: false);
      final criticalReason = policy.getGatingReason(criticalState, 2);
      expect(criticalReason, contains('Critical battery'));
      expect(criticalReason, contains('8%'));
      expect(criticalReason, contains('1'));

      // Background gating reason
      final backgroundState = BatteryState.test(isBackgrounded: true);
      final backgroundReason = policy.getGatingReason(backgroundState, 4);
      expect(backgroundReason, contains('App backgrounded'));
      expect(backgroundReason, contains('3'));

      // No reason when not gated
      final normalState = BatteryState.test();
      expect(policy.getGatingReason(normalState, 5), isNull);
    });
  });
}