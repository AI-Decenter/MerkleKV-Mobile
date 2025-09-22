# Battery-Aware Reconnection Policy

The MerkleKV Mobile library includes intelligent battery-aware reconnection policies that adapt to mobile device power constraints while maintaining strict compliance with Locked Specification timing requirements.

## Overview

The battery-aware reconnection system consists of three main components:

1. **BatteryState** - Captures current battery level, charging status, power save mode, and app background state
2. **BatteryMonitor** - Monitors battery state changes and provides real-time updates
3. **BatteryAwareReconnectPolicy** - Makes intelligent gating decisions based on battery conditions

## Key Design Principles

### Locked Specification Compliance
- **Backoff timing NEVER changes** from Locked Spec requirements (1s→32s, factor 2, jitter ±20%)
- Battery state affects **WHETHER** to attempt reconnection (gating), not **WHEN**
- All timing constraints remain exactly as specified

### Intelligent Gating Strategy
- **Power Save Mode**: Limits reconnection attempts when device is in power save mode
- **Critical Battery**: Restricts attempts when battery is low (<10%) and not charging  
- **Background Operation**: Reduces attempts when app is backgrounded
- **Configurable Thresholds**: All limits are customizable per application needs

## Quick Start

### Basic Usage
```dart
import 'package:merkle_kv_core/merkle_kv.dart';

// MQTT client with default battery awareness
final config = MerkleKVConfig(
  mqttHost: 'mqtt.example.com',
  clientId: 'mobile-device-1',
  nodeId: 'device-uuid-123',
);

final mqttClient = MqttClientImpl(config);
// Battery awareness is enabled by default with sensible settings
```

### Custom Battery Policy
```dart
// Create a conservative battery policy for maximum power savings
final conservativePolicy = BatteryAwareReconnectPolicy.conservative();

// Or create a custom policy
final customPolicy = BatteryAwareReconnectPolicy(
  maxAttemptsInPowerSave: 2,      // Default: 3
  maxAttemptsOnCriticalBattery: 1, // Default: 2  
  maxAttemptsWhenBackgrounded: 3,  // Default: 5
  enableBatteryGating: true,       // Default: true
);

final mqttClient = MqttClientImpl(config, reconnectPolicy: customPolicy);
```

### Testing with Battery Simulation
```dart
// Create a test battery monitor for simulation
final batteryMonitor = TestBatteryMonitor();
final mqttClient = MqttClientImpl(config, batteryMonitor: batteryMonitor);

await batteryMonitor.start();

// Simulate different battery conditions
batteryMonitor.simulateCriticalBattery();    // 5% battery, not charging, power save on
batteryMonitor.simulateLowBattery();         // 15% battery, not charging
batteryMonitor.simulateLowBattery(charging: true); // 15% battery, charging
batteryMonitor.simulatePowerSaveMode();      // Enable power save mode
batteryMonitor.simulateAppBackgrounded();    // App goes to background
```

## Policy Presets

### Default Policy
Balanced battery awareness suitable for most mobile applications:
- Power save mode: 3 attempts max
- Critical battery: 2 attempts max  
- Background operation: 5 attempts max

### Conservative Policy
Aggressive battery preservation for battery-sensitive applications:
- Power save mode: 1 attempt max
- Critical battery: 1 attempt max
- Background operation: 2 attempts max

### Disabled Policy
No battery gating - equivalent to non-battery-aware behavior:
- All conditions: 999 attempts max
- Use when battery awareness is not desired

## Battery State Reference

### BatteryState Properties
```dart
class BatteryState {
  final int level;              // Battery percentage (0-100)
  final bool isCharging;        // Whether device is charging
  final bool isPowerSaveMode;   // Whether power save mode is active
  final bool isBackgrounded;    // Whether app is in background
  final DateTime timestamp;     // When state was captured
  
  // Helper properties
  bool get isCritical;          // level < 10 && !isCharging
  bool get isLow;               // level < 20
}
```

### Gating Logic
Reconnection attempts are gated (blocked) when:

1. **Power Save Mode**: `isPowerSaveMode == true` AND `attempt > maxAttemptsInPowerSave`
2. **Critical Battery**: `isCritical == true` AND `attempt > maxAttemptsOnCriticalBattery`  
3. **Background App**: `isBackgrounded == true` AND `attempt > maxAttemptsWhenBackgrounded`

The first matching condition takes precedence.

## Integration Examples

### Monitoring Battery State
```dart
final mqttClient = MqttClientImpl(config);

// Access current battery state
final currentState = mqttClient.batteryMonitor.currentState;
print('Battery level: ${currentState.level}%');
print('Charging: ${currentState.isCharging}');

// Listen to battery state changes
mqttClient.batteryMonitor.batteryState.listen((state) {
  print('Battery state changed: $state');
});
```

### Checking Reconnection Policy
```dart
final policy = mqttClient.reconnectPolicy;
final batteryState = mqttClient.batteryMonitor.currentState;

// Check if reconnection would be allowed
final shouldAttempt = policy.shouldAttemptReconnection(batteryState, attemptNumber);

// Get reason if gated
final reason = policy.getGatingReason(batteryState, attemptNumber);
if (reason != null) {
  print('Reconnection gated: $reason');
}

// Check timing (always Locked Spec compliant)
final backoffDelay = policy.calculateBackoff(attemptNumber);
print('Next attempt in: ${backoffDelay.inSeconds}s');
```

### Custom Battery Monitor Implementation
```dart
class MyBatteryMonitor implements BatteryMonitor {
  // Implement platform-specific battery monitoring
  // e.g., using platform channels for iOS/Android
  
  @override
  Future<void> start() async {
    // Initialize platform battery monitoring
  }
  
  @override
  BatteryState get currentState => _currentState;
  
  // ... implement other methods
}

final customMonitor = MyBatteryMonitor();
final mqttClient = MqttClientImpl(config, batteryMonitor: customMonitor);
```

## Best Practices

### Mobile Applications
- Use default or conservative policies for battery-sensitive apps
- Monitor battery state changes for reactive UI updates
- Consider user preferences for battery optimization level

### Testing
- Use `TestBatteryMonitor` for unit and integration testing
- Test all battery scenarios: normal, low, critical, charging, power save, background
- Verify timing remains Locked Spec compliant under all conditions

### Production Deployment
- Implement platform-specific battery monitoring (iOS/Android)
- Log battery gating events for analytics and debugging
- Consider exposing battery policy as user configuration

## Locked Specification Compliance

The battery-aware system maintains strict compliance with Locked Specification requirements:

- **Timing**: Backoff delays always follow 1s→2s→4s→8s→16s→32s progression with ±20% jitter
- **Maximum Delay**: Never exceeds 32 seconds regardless of battery state
- **Jitter**: Always includes ±20% randomization for avoiding thundering herd
- **Factor**: Always uses factor of 2 exponential progression
- **Gating Only**: Battery state only affects gating decisions, never timing calculations

## Troubleshooting

### Common Issues

**Reconnection attempts being gated unexpectedly:**
- Check current battery state with `mqttClient.batteryMonitor.currentState`
- Verify policy configuration with `mqttClient.reconnectPolicy`
- Use `policy.getGatingReason()` to understand why attempts are blocked

**Battery monitoring not working:**
- Ensure `batteryMonitor.start()` was called
- Check `batteryMonitor.isMonitoring` status
- Verify platform-specific battery monitoring is implemented correctly

**Timing not following expected pattern:**
- Battery state should NOT affect timing - this would be a bug
- All timing should follow Locked Spec exactly regardless of battery conditions
- Use `policy.calculateBackoff()` to verify timing calculation

### Debugging

Enable detailed logging to understand battery-aware behavior:
```dart
// Monitor battery state changes
mqttClient.batteryMonitor.batteryState.listen((state) {
  print('Battery: ${state.level}% charging:${state.isCharging} powerSave:${state.isPowerSaveMode}');
});

// Check gating decisions during reconnection attempts
for (int attempt = 1; attempt <= 10; attempt++) {
  final shouldAttempt = policy.shouldAttemptReconnection(batteryState, attempt);
  final reason = policy.getGatingReason(batteryState, attempt);
  print('Attempt $attempt: ${shouldAttempt ? "ALLOW" : "GATE"} ${reason ?? ""}');
}
```