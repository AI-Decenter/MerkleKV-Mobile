# Mobile E2E Testing for MerkleKV

This directory contains comprehensive end-to-end tests for mobile platforms (Android & iOS) that validate mobile-specific lifecycle scenarios, convergence behavior, and platform connectivity changes.

## 📋 Overview

The mobile E2E testing suite focuses on **spec-compliant convergence behavior** rather than hard-coded latency targets, ensuring the distributed key-value system maintains consistency across mobile platform lifecycle events and network state transitions.

## 🧪 Test Categories

### 1. Mobile Lifecycle Tests (`mobile_lifecycle_test.dart`)
- **Background/Foreground Transitions**: App lifecycle state management
- **App Suspension/Resumption**: Operation queuing and recovery
- **Rapid Lifecycle Cycling**: State corruption prevention
- **Network State Transitions**: Airplane mode, WiFi/cellular switching
- **App Termination Recovery**: Persistent operation queue testing

### 2. Mobile Convergence Tests (`mobile_convergence_test.dart`)
- **Anti-Entropy During Lifecycle Events**: Sync across app suspension cycles
- **Network Interruption Recovery**: Convergence after connectivity loss
- **Merkle Tree Synchronization**: Large dataset sync during lifecycle events
- **Multi-Device Convergence**: Mobile-to-mobile and mobile-to-desktop sync
- **Conflict Resolution**: Last-writer-wins during mobile transitions

### 3. Platform-Specific Tests (`platform_specific_test.dart`)
- **Android Tests**:
  - Background execution limits (Doze mode)
  - Network Security Config compliance
  - App standby mode handling
  - Battery optimization impact
- **iOS Tests**:
  - Background App Refresh handling
  - App Transport Security (ATS) compliance
  - Cellular data restrictions
  - App suspension/termination recovery
- **Cross-Platform Security**:
  - Platform-specific certificate validation
  - TLS version compatibility
  - Credential storage security

### 4. Battery & Power Management Tests (`battery_power_management_test.dart`)
- **Battery Optimization Compliance**: Essential operation preservation
- **Power-Efficient Synchronization**: Adaptive sync based on battery state
- **Background Operation Management**: Platform restriction compliance
- **Thermal Throttling Adaptation**: Performance degradation handling

## 🏗️ Test Infrastructure

### Helper Classes
- **`MobileTestHarness`**: Client lifecycle management, connection monitoring
- **`PlatformSimulation`**: App lifecycle, memory pressure, battery state simulation
- **`ConnectivitySimulator`**: Network state changes, latency, intermittent connectivity
- **`ConvergenceValidator`**: Anti-entropy validation, Merkle sync monitoring
- **`MultiDeviceSimulator`**: Device clusters, network partitions, mixed environments

### Configuration
- **`test_config.yaml`**: Platform settings, timeouts, CI integration
- **`run_mobile_e2e_tests.dart`**: Comprehensive test runner with reporting

## 🚀 Running Tests

### Prerequisites

#### Android Testing Setup

For reliable Android testing, use the enhanced emulator setup:

```bash
# Quick setup with defaults
./scripts/setup_android_emulator.sh

# Custom configuration
./scripts/setup_android_emulator.sh \
  --api-level 33 \
  --target google_apis \
  --memory 3072 \
  --ci-mode

# Verify emulator status
./scripts/android_emulator_helper.sh health
```

See [Android Emulator Setup Guide](../../docs/android-emulator-setup.md) for comprehensive configuration options.

#### iOS Testing Setup (macOS only)

```bash
# Start iOS Simulator
open -a Simulator

# List available simulators
xcrun simctl list devices available

# Start specific simulator
xcrun simctl boot "iPhone 15 Pro"
```

#### General Prerequisites

```bash
# Ensure Flutter is installed
flutter --version

# Install dependencies
flutter pub get

# Verify device connectivity
flutter devices
```

### Running All Tests
```bash
# Run all mobile E2E tests
dart test/mobile_e2e/run_mobile_e2e_tests.dart

# With verbose output
dart test/mobile_e2e/run_mobile_e2e_tests.dart --verbose
```

### Running Specific Categories
```bash
# Lifecycle tests only
dart test/mobile_e2e/run_mobile_e2e_tests.dart --category lifecycle

# Convergence tests only
dart test/mobile_e2e/run_mobile_e2e_tests.dart --category convergence

# Platform-specific tests
dart test/mobile_e2e/run_mobile_e2e_tests.dart --category platform-specific

# Battery tests only
dart test/mobile_e2e/run_mobile_e2e_tests.dart --category battery
```

### Platform-Specific Testing
```bash
# Android only
dart test/mobile_e2e/run_mobile_e2e_tests.dart --platform android

# iOS only (macOS required)
dart test/mobile_e2e/run_mobile_e2e_tests.dart --platform ios
```

### Individual Test Files
```bash
# Run specific test file
flutter test test/mobile_e2e/mobile_lifecycle_test.dart

# With integration test tags
flutter test test/mobile_e2e/mobile_lifecycle_test.dart -t mobile-e2e
```

## 📊 Test Reports

Tests generate comprehensive reports in `test_output/reports/`:

- **HTML Report**: `mobile_e2e_report.html` - Visual test results
- **JUnit XML**: `mobile_e2e_junit.xml` - CI/CD integration
- **JSON Report**: `mobile_e2e_report.json` - Programmatic analysis

## 🔧 CI/CD Integration

### Enhanced Android Emulator Support

The testing framework includes enhanced Android emulator setup for reliable CI/CD environments:

```yaml
# Use the custom Android emulator action
- name: Setup Enhanced Android Emulator
  uses: ./.github/actions/setup-android-emulator
  with:
    api-level: '33'
    target: 'google_apis'
    memory: '3072'
    wait-timeout: '600'

- name: Run Android E2E Tests
  run: |
    dart test/mobile_e2e/run_mobile_e2e_tests.dart --platform android --verbose
```

**Key Features**:
- Optimized AVD creation and caching
- Enhanced device readiness checks
- Comprehensive error handling and debugging
- Matrix testing across Android API levels
- Automatic cleanup and resource management

### Firebase Test Lab
```yaml
# .github/workflows/mobile-e2e.yml
- name: Run Firebase Test Lab
  run: |
    gcloud firebase test android run \
      --type instrumentation \
      --app app-debug.apk \
      --test app-debug-androidTest.apk \
      --device model=Pixel2,version=28
```

### AWS Device Farm
```yaml
- name: Run AWS Device Farm Tests
  run: |
    aws devicefarm schedule-run \
      --project-arn ${{ secrets.AWS_DEVICE_FARM_PROJECT }} \
      --app-arn ${{ secrets.AWS_APP_ARN }} \
      --device-pool-arn ${{ secrets.AWS_DEVICE_POOL }}
```

## 🎯 Key Test Scenarios

### Mobile Lifecycle Validation
```dart
testWidgets('Background transition preserves connection state', (tester) async {
  // Given: Active MerkleKV client
  final client = await testHarness.createClient(config);
  await testHarness.waitForConnection(client);
  
  // When: App goes to background
  await platformSim.simulateAppLifecycleState(AppLifecycleState.paused);
  
  // Then: Connection state handled gracefully
  // And: Data accessible after foreground return
});
```

### Convergence Under Mobile Conditions
```dart
test('Anti-entropy works across app suspension cycles', () async {
  var config = MerkleKVConfig(antiEntropyIntervalMs: 60000);
  // Suspend app during sync operation
  // Verify convergence completes within interval after resumption
  // No hard-coded latency expectations
});
```

### Platform-Specific Behavior
```dart
testWidgets('Android Doze mode handled correctly', (tester) async {
  // Simulate Android background execution limits
  // Verify graceful connection suspension/resumption
  // Ensure data integrity maintained
});

testWidgets('iOS Background App Refresh compliance', (tester) async {
  // Simulate iOS background processing limitations
  // Verify sync state preservation
  // Ensure ATS compliance
});
```

## 📝 Test Design Principles

### Spec-Compliant Testing
- **No Hard-Coded Timeouts**: Use configurable intervals from MerkleKVConfig
- **Convergence-Based Validation**: Focus on eventual consistency, not timing
- **Platform-Adaptive Behavior**: Respect platform-specific limitations

### Mobile-First Approach
- **Lifecycle-Aware Testing**: Account for mobile app state transitions
- **Network Resilience**: Test various connectivity scenarios
- **Power Efficiency**: Validate battery optimization compliance
- **Platform Integration**: Test with actual mobile platform APIs

### Comprehensive Coverage
- **Edge Cases**: Rapid state changes, poor connectivity, memory pressure
- **Multi-Device Scenarios**: Mobile-to-mobile and mobile-to-desktop sync
- **Security Validation**: Platform certificate stores, TLS compliance
- **Performance Monitoring**: Memory usage, battery drain, network efficiency

## 🔍 Debugging

### Enable Debug Logging
```bash
export LOG_LEVEL=DEBUG
export ENABLE_DEBUG_LOGGING=true
dart test/mobile_e2e/run_mobile_e2e_tests.dart --verbose
```

### Mock Service Configuration
```dart
// Enable detailed mock service logging
await testHarness.enableDebugMode();
await platformSim.enableDetailedLogging();
await connectivitySim.enableNetworkLogging();
```

### Performance Monitoring
```dart
// Monitor test performance
await testHarness.verifyMemoryUsage(client);
await testHarness.verifyClientHealth(client);
```

## 🚨 Troubleshooting

### Common Issues

1. **Test Timeouts**
   - Increase timeout in `test_config.yaml`
   - Check network connectivity to MQTT broker
   - Verify device/emulator performance

2. **Platform-Specific Failures**
   - Ensure correct SDK versions installed
   - Verify platform permissions configured
   - Check device/simulator availability

3. **Convergence Test Failures**
   - Verify anti-entropy interval configuration
   - Check for network simulation conflicts
   - Ensure mock services are properly started

### Debugging Commands
```bash
# Check available devices
flutter devices

# Verify Flutter installation
flutter doctor

# Android emulator diagnostics
./scripts/android_emulator_helper.sh troubleshoot

# Test individual components
flutter test test/mobile_e2e/helpers/mobile_test_harness.dart

# Validate test configuration
dart test/mobile_e2e/run_mobile_e2e_tests.dart --help
```

### Enhanced Android Debugging

```bash
# Device setup and health check
./scripts/android_emulator_helper.sh setup

# Collect device information
./scripts/android_emulator_helper.sh info

# Perform comprehensive health check
./scripts/android_emulator_helper.sh health

# Clean device state
./scripts/android_emulator_helper.sh cleanup
```

## 📚 Related Documentation

- [Enhanced Android Emulator Setup](../../docs/android-emulator-setup.md)
- [MerkleKV Core API](../../packages/merkle_kv_core/README.md)
- [Architecture Documentation](../../docs/architecture.md)
- [Deployment Guide](../../docs/DEPLOYMENT.md)
- [Contributing Guidelines](../../CONTRIBUTING.md)

## 🏷️ Test Tags

- `mobile-e2e`: All mobile E2E tests
- `lifecycle`: App lifecycle tests
- `convergence`: Anti-entropy and sync tests
- `platform-specific`: Android/iOS specific tests
- `battery`: Power management tests
- `integration`: Integration test marker