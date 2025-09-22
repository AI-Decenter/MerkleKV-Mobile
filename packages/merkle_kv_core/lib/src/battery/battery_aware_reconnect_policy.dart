import 'dart:math' as math;

import 'battery_state.dart';

/// Battery-aware reconnection policy that maintains Locked Spec compliance.
///
/// This policy implements intelligent reconnection gating based on battery
/// conditions while ensuring backoff timing always follows Locked Specification
/// requirements (1s→32s, factor 2, jitter ±20%).
///
/// Key design principles:
/// - Backoff timing NEVER changes from Locked Spec requirements
/// - Battery state affects WHETHER to attempt reconnection (gating)
/// - Power save mode, critical battery, and background state influence gating
class BatteryAwareReconnectPolicy {
  /// Maximum reconnection attempts in power save mode.
  final int maxAttemptsInPowerSave;

  /// Maximum reconnection attempts on critical battery.
  final int maxAttemptsOnCriticalBattery;

  /// Maximum reconnection attempts when backgrounded.
  final int maxAttemptsWhenBackgrounded;

  /// Whether battery-aware gating is enabled.
  final bool enableBatteryGating;

  /// Creates a battery-aware reconnection policy.
  const BatteryAwareReconnectPolicy({
    this.maxAttemptsInPowerSave = 3,
    this.maxAttemptsOnCriticalBattery = 2,
    this.maxAttemptsWhenBackgrounded = 5,
    this.enableBatteryGating = true,
  });

  /// Creates a disabled policy that never gates reconnection attempts.
  const BatteryAwareReconnectPolicy.disabled()
      : maxAttemptsInPowerSave = 999,
        maxAttemptsOnCriticalBattery = 999,
        maxAttemptsWhenBackgrounded = 999,
        enableBatteryGating = false;

  /// Creates a conservative policy for maximum battery preservation.
  const BatteryAwareReconnectPolicy.conservative()
      : maxAttemptsInPowerSave = 1,
        maxAttemptsOnCriticalBattery = 1,
        maxAttemptsWhenBackgrounded = 2,
        enableBatteryGating = true;

  /// Calculates backoff delay per Locked Specification requirements.
  ///
  /// This method ALWAYS follows Locked Spec timing:
  /// - Exponential backoff: 1s → 2s → 4s → ... → 32s (max)
  /// - Factor of 2 progression
  /// - Jitter of ±20%
  ///
  /// Battery state has NO influence on timing, only on gating decisions.
  Duration calculateBackoff(int attempt) {
    // Locked Spec §6: Exponential backoff 1s→32s, factor 2
    final baseDelaySeconds = math.min(math.pow(2, attempt).toInt(), 32);
    
    // Locked Spec §6: Jitter ±20%
    final random = math.Random();
    final jitter = 1.0 + (random.nextDouble() - 0.5) * 0.4; // ±20%
    
    final delaySeconds = (baseDelaySeconds * jitter).round();
    return Duration(seconds: delaySeconds);
  }

  /// Determines whether to attempt reconnection based on battery conditions.
  ///
  /// This method implements the core gating logic:
  /// - Power save mode: limit attempts after threshold
  /// - Critical battery: limit attempts when not charging
  /// - Background operation: limit attempts when backgrounded
  ///
  /// Returns true if reconnection should be attempted, false to skip.
  bool shouldAttemptReconnection(BatteryState batteryState, int attempt) {
    // If battery gating is disabled, always allow reconnection
    if (!enableBatteryGating) {
      return true;
    }

    // Gate attempts in power save mode
    if (batteryState.isPowerSaveMode && attempt > maxAttemptsInPowerSave) {
      return false;
    }

    // Gate attempts on critical battery (low level and not charging)
    if (batteryState.isCritical && attempt > maxAttemptsOnCriticalBattery) {
      return false;
    }

    // Gate attempts when app is backgrounded
    if (batteryState.isBackgrounded && attempt > maxAttemptsWhenBackgrounded) {
      return false;
    }

    // Allow attempt with standard Locked Spec timing
    return true;
  }

  /// Gets a human-readable reason why reconnection was gated.
  ///
  /// Returns null if reconnection should be allowed.
  String? getGatingReason(BatteryState batteryState, int attempt) {
    if (!enableBatteryGating) {
      return null;
    }

    if (batteryState.isPowerSaveMode && attempt > maxAttemptsInPowerSave) {
      return 'Power save mode enabled, max attempts ($maxAttemptsInPowerSave) exceeded';
    }

    if (batteryState.isCritical && attempt > maxAttemptsOnCriticalBattery) {
      return 'Critical battery level (${batteryState.level}%), max attempts ($maxAttemptsOnCriticalBattery) exceeded';
    }

    if (batteryState.isBackgrounded && attempt > maxAttemptsWhenBackgrounded) {
      return 'App backgrounded, max attempts ($maxAttemptsWhenBackgrounded) exceeded';
    }

    return null;
  }

  /// Creates a copy of this policy with modified parameters.
  BatteryAwareReconnectPolicy copyWith({
    int? maxAttemptsInPowerSave,
    int? maxAttemptsOnCriticalBattery,
    int? maxAttemptsWhenBackgrounded,
    bool? enableBatteryGating,
  }) {
    return BatteryAwareReconnectPolicy(
      maxAttemptsInPowerSave:
          maxAttemptsInPowerSave ?? this.maxAttemptsInPowerSave,
      maxAttemptsOnCriticalBattery:
          maxAttemptsOnCriticalBattery ?? this.maxAttemptsOnCriticalBattery,
      maxAttemptsWhenBackgrounded:
          maxAttemptsWhenBackgrounded ?? this.maxAttemptsWhenBackgrounded,
      enableBatteryGating: enableBatteryGating ?? this.enableBatteryGating,
    );
  }

  @override
  String toString() => 'BatteryAwareReconnectPolicy('
      'enabled: $enableBatteryGating, '
      'powerSave: $maxAttemptsInPowerSave, '
      'critical: $maxAttemptsOnCriticalBattery, '
      'background: $maxAttemptsWhenBackgrounded)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BatteryAwareReconnectPolicy &&
          runtimeType == other.runtimeType &&
          maxAttemptsInPowerSave == other.maxAttemptsInPowerSave &&
          maxAttemptsOnCriticalBattery == other.maxAttemptsOnCriticalBattery &&
          maxAttemptsWhenBackgrounded == other.maxAttemptsWhenBackgrounded &&
          enableBatteryGating == other.enableBatteryGating;

  @override
  int get hashCode =>
      maxAttemptsInPowerSave.hashCode ^
      maxAttemptsOnCriticalBattery.hashCode ^
      maxAttemptsWhenBackgrounded.hashCode ^
      enableBatteryGating.hashCode;
}