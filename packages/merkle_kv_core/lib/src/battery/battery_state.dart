/// Battery state information for mobile power management.
///
/// Provides battery level, charging status, and power saving mode information
/// to support intelligent reconnection policies.
class BatteryState {
  /// Battery level as a percentage (0-100).
  final int level;

  /// Whether the device is currently charging.
  final bool isCharging;

  /// Whether power save mode is enabled.
  final bool isPowerSaveMode;

  /// Whether the app is currently in the background.
  final bool isBackgrounded;

  /// Timestamp when this state was captured.
  final DateTime timestamp;

  /// Creates a new battery state snapshot.
  const BatteryState({
    required this.level,
    required this.isCharging,
    required this.isPowerSaveMode,
    required this.isBackgrounded,
    required this.timestamp,
  });

  /// Creates a battery state for testing purposes.
  BatteryState.test({
    this.level = 50,
    this.isCharging = false,
    this.isPowerSaveMode = false,
    this.isBackgrounded = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Creates a default battery state (unknown conditions, conservative).
  BatteryState.unknown({DateTime? timestamp})
      : level = 50,
        isCharging = false,
        isPowerSaveMode = false,
        isBackgrounded = false,
        timestamp = timestamp ?? DateTime.now();

  /// Whether the battery is in critical condition (low level and not charging).
  bool get isCritical => level < 10 && !isCharging;

  /// Whether the battery is in low condition.
  bool get isLow => level < 20;

  @override
  String toString() => 'BatteryState(level: $level%, charging: $isCharging, '
      'powerSave: $isPowerSaveMode, background: $isBackgrounded)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BatteryState &&
          runtimeType == other.runtimeType &&
          level == other.level &&
          isCharging == other.isCharging &&
          isPowerSaveMode == other.isPowerSaveMode &&
          isBackgrounded == other.isBackgrounded;

  @override
  int get hashCode =>
      level.hashCode ^
      isCharging.hashCode ^
      isPowerSaveMode.hashCode ^
      isBackgrounded.hashCode;
}