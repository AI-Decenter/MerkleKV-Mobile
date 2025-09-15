# Enhanced Android Emulator Setup for Mobile E2E Testing

This directory contains comprehensive Android emulator setup tools designed for reliable CI/CD and local development environments.

## 🚀 Quick Start

### Using in GitHub Actions

```yaml
- name: Setup Enhanced Android Emulator
  uses: ./.github/actions/setup-android-emulator
  with:
    api-level: '33'
    target: 'google_apis'
    memory: '3072'
    wait-timeout: '600'

- name: Run tests
  run: |
    # Your test commands here
    flutter test integration_test/
```

### Local Development

```bash
# Basic setup
./scripts/setup_android_emulator.sh

# Custom configuration
./scripts/setup_android_emulator.sh \
  --api-level 29 \
  --target google_apis \
  --memory 4096 \
  --ci-mode

# Using helper scripts
./scripts/android_emulator_helper.sh setup
```

## 📁 Components

### 1. GitHub Action (`/.github/actions/setup-android-emulator/`)

**Purpose**: Reusable GitHub Action for consistent emulator setup across workflows.

**Key Features**:
- Input validation and error handling
- Automatic SDK component installation
- Enhanced caching for faster CI runs
- Comprehensive device readiness checks
- Configurable timeouts and resource allocation

**Inputs**:
| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `api-level` | Android API level (21-34) | `33` | No |
| `target` | System image target | `google_apis` | No |
| `arch` | CPU architecture | `x86_64` | No |
| `emulator-name` | Custom emulator name | Auto-generated | No |
| `memory` | RAM size in MB | `3072` | No |
| `disk-size` | Disk size in MB | `4096` | No |
| `force-creation` | Force AVD recreation | `false` | No |
| `enable-hardware-acceleration` | Enable HW acceleration | `true` | No |
| `wait-timeout` | Boot timeout in seconds | `600` | No |

**Outputs**:
- `emulator-name`: Name of the created emulator
- `device-id`: Android device identifier  
- `api-level`: Actual API level of running emulator

### 2. Setup Script (`/scripts/setup_android_emulator.sh`)

**Purpose**: Standalone script for comprehensive emulator setup with extensive configuration options.

**Features**:
- Interactive and non-interactive modes
- Device profile selection (Pixel series)
- CI/CD optimizations
- Memory and storage configuration
- Comprehensive validation and testing

**Usage Examples**:
```bash
# Show help
./scripts/setup_android_emulator.sh --help

# Basic setup
./scripts/setup_android_emulator.sh

# CI-optimized setup
./scripts/setup_android_emulator.sh --ci-mode --api-level 33

# Custom configuration
./scripts/setup_android_emulator.sh \
  --api-level 28 \
  --target default \
  --memory 4096 \
  --device pixel_6 \
  --force
```

### 3. Helper Script (`/scripts/android_emulator_helper.sh`)

**Purpose**: Runtime utilities for device management, health checks, and troubleshooting.

**Commands**:
- `wait`: Wait for device readiness
- `configure`: Configure device for testing
- `info`: Collect device information
- `health`: Perform health checks
- `cleanup`: Clean device state
- `troubleshoot`: Run diagnostics
- `setup`: Complete setup process

**Usage Examples**:
```bash
# Complete setup
./scripts/android_emulator_helper.sh setup

# Health check only
./scripts/android_emulator_helper.sh health

# Troubleshooting
./scripts/android_emulator_helper.sh troubleshoot
```

## 🔧 Configuration

### AVD Configuration

The setup automatically configures AVDs with optimal settings:

```ini
# Performance optimizations
hw.gpu.enabled=yes
hw.gpu.mode=swiftshader_indirect
hw.ramSize=3072
hw.cpu.ncore=2

# CI optimizations
hw.audioInput=no
hw.audioOutput=no
hw.camera.back=none
hw.camera.front=none
showDeviceFrame=no

# Display settings
hw.lcd.density=420
hw.lcd.height=2340
hw.lcd.width=1080
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ANDROID_HOME` | Android SDK path | Required |
| `MAX_BOOT_WAIT` | Maximum boot wait time | `300s` |
| `HEALTH_CHECK_INTERVAL` | Health check frequency | `5s` |
| `ADB_TIMEOUT` | ADB operation timeout | `30s` |

## 🚦 Workflow Integration

### Enhanced Mobile E2E Workflow

The setup is integrated into the mobile E2E workflow with:

1. **Matrix Strategy**: Tests across multiple API levels and targets
2. **Caching**: Optimized AVD and dependency caching
3. **Error Handling**: Comprehensive error collection and reporting
4. **Timeout Management**: Configurable timeouts for reliability
5. **Resource Optimization**: Memory and disk space management

### Example Workflow Usage

```yaml
jobs:
  android-e2e:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        api-level: [28, 29, 33]
        target: [default, google_apis]
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Enhanced Android Emulator
        uses: ./.github/actions/setup-android-emulator
        with:
          api-level: ${{ matrix.api-level }}
          target: ${{ matrix.target }}
          
      - name: Run E2E Tests
        run: |
          # Tests run here with reliable emulator
          flutter test integration_test/
```

## 🔍 Troubleshooting

### Common Issues

1. **Emulator Won't Start**
   ```bash
   ./scripts/android_emulator_helper.sh troubleshoot
   ```

2. **Boot Timeout**
   - Check available disk space
   - Increase wait timeout
   - Verify hardware acceleration support

3. **ADB Connection Issues**
   ```bash
   adb kill-server
   adb start-server
   ./scripts/android_emulator_helper.sh wait
   ```

4. **Performance Issues**
   - Increase memory allocation
   - Enable hardware acceleration
   - Use appropriate API level for CI environment

### Debug Information Collection

The setup automatically collects debug information on failures:
- Device state and configuration
- System memory and storage status
- Recent logcat entries
- Flutter doctor output
- Comprehensive troubleshooting data

## 📊 Performance Optimizations

### CI Environment

- **Disk Space Management**: Automatic cleanup of unnecessary files
- **Caching Strategy**: Multi-level caching for AVDs and dependencies
- **Resource Allocation**: Optimized memory and CPU core usage
- **Network Configuration**: Fast network simulation for testing

### Local Development

- **Interactive Mode**: User-friendly prompts and feedback
- **Device Testing**: Automatic functionality verification
- **Profile Support**: Multiple device profiles (Pixel series)
- **Custom Configuration**: Extensive customization options

## 🔗 Integration Points

### Flutter Integration

The emulator setup is specifically optimized for Flutter development:

- Automatic Flutter device detection
- Compatible with Flutter's device selection
- Optimized for Flutter test frameworks
- Integration with Flutter doctor diagnostics

### CI/CD Integration

- GitHub Actions workflow integration
- Comprehensive error reporting
- Artifact collection for failed tests
- Matrix testing support across Android versions

## 📈 Monitoring and Reporting

### Health Checks

Continuous monitoring includes:
- Device responsiveness
- Memory availability
- System load monitoring
- ANR detection
- Battery status

### Performance Metrics

Tracked metrics:
- Boot time
- Memory usage
- Test execution time
- Network performance
- Overall system health

## 🛡️ Security and Compliance

### CI Security

- No sensitive data exposure
- Isolated test environments
- Automatic cleanup after tests
- Secure SDK and dependency management

### Android Security

- Network Security Config compliance
- App Transport Security support
- Certificate validation testing
- Secure communication protocols

This enhanced Android emulator setup provides a robust foundation for reliable mobile E2E testing across development and CI/CD environments.