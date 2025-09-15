# MerkleKV Mobile Development Guide

A distributed key-value store optimized for mobile edge devices with MQTT-based communication and replication. This monorepo contains Dart packages for core functionality and Flutter applications for mobile deployment.

**Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.**

## Working Effectively

### Bootstrap Development Environment (Required First Steps)

**CRITICAL: Always run these steps in order before making any changes:**

```bash
# 1. Install Dart SDK (if not available)
cd /tmp
wget https://storage.googleapis.com/dart-archive/channels/stable/release/3.5.4/sdk/dartsdk-linux-x64-release.zip
unzip -q dartsdk-linux-x64-release.zip
sudo mv dart-sdk /usr/local/
export PATH="/usr/local/dart-sdk/bin:$PATH"
echo 'export PATH="/usr/local/dart-sdk/bin:$PATH"' >> ~/.bashrc

# 2. Install Melos (monorepo manager)
dart pub global activate melos
export PATH="$PATH:$HOME/.pub-cache/bin"
echo 'export PATH="$PATH:$HOME/.pub-cache/bin"' >> ~/.bashrc

# 3. Install dependencies for core package (REQUIRED)
cd packages/merkle_kv_core
dart pub get  # Takes ~1 second

# 4. Install Node.js dependencies (for development tools)
cd ../../
npm install  # Takes ~10-15 seconds
```

### Build and Analysis (NEVER CANCEL)

```bash
# Static analysis (REQUIRED before committing)
cd packages/merkle_kv_core
dart analyze .
# Takes 2-3 seconds. NEVER CANCEL - very fast analysis.
# EXPECTED: 413 analysis issues (warnings/info) - this is normal for this codebase.
# Critical errors in OptimizedMqttClient and ErrorClassifier are known issues.

# Lint JavaScript/TypeScript (if working on npm scripts)
cd ../../
npm run lint
# Takes ~0.3 seconds. NEVER CANCEL.
```

### Testing Strategy (IMPORTANT LIMITATIONS)

**CRITICAL NOTE**: The test suite has frontend_server snapshot issues with the current Dart SDK setup. Do NOT attempt to run `dart test` as it will fail. This is a known limitation in the current environment.

**Instead, use these validation approaches:**

1. **Static Analysis Only**: Use `dart analyze .` to validate code structure
2. **MQTT Integration Testing**: Use manual MQTT broker testing
3. **Manual Code Review**: Inspect changes carefully before committing

### MQTT Broker Setup and Testing

**REQUIRED for integration testing:**

```bash
# Start MQTT broker (REQUIRED for MQTT-related development)
docker run -d --name test-mosquitto -p 1883:1883 eclipse-mosquitto:1.6
# Takes ~2-5 seconds. NEVER CANCEL.

# Test MQTT connectivity (always run after starting broker)
./scripts/mqtt_health_check.sh
# Takes ~2-3 seconds. NEVER CANCEL.

# Manual MQTT testing
mosquitto_pub -h localhost -p 1883 -t test/topic -m "test message"
mosquitto_sub -h localhost -p 1883 -t test/topic -C 1
```

### Flutter Development (LIMITATIONS)

**WARNING**: Flutter SDK installation has network issues in this environment. The Flutter app (`apps/flutter_demo`) cannot be built or tested due to corrupted Flutter SDK downloads. Focus development on the core Dart package (`packages/merkle_kv_core`).

## Validation Requirements

### Manual Testing Scenarios (ALWAYS PERFORM)

After making any changes to MQTT or replication code:

1. **MQTT Connectivity Test**:
   ```bash
   # Start broker if not running
   docker ps | grep mosquitto || docker run -d --name test-mosquitto -p 1883:1883 eclipse-mosquitto:1.6
   
   # Test pub/sub workflow
   mosquitto_sub -h localhost -p 1883 -t "merkle_kv/test" -C 1 &
   sleep 1
   mosquitto_pub -h localhost -p 1883 -t "merkle_kv/test" -m "validation_test"
   wait
   ```

2. **Code Analysis Validation**:
   ```bash
   cd packages/merkle_kv_core
   dart analyze . | grep -E "error •" | head -20
   # EXPECTED: ~15 known errors in OptimizedMqttClient and ErrorClassifier
   # Any NEW errors indicate issues with your changes
   ```

3. **Dependency Resolution Test**:
   ```bash
   cd packages/merkle_kv_core
   dart pub get --dry-run
   dart pub deps
   # Should complete without errors
   ```

### Pre-Commit Checklist (MANDATORY)

```bash
# 1. Run static analysis
cd packages/merkle_kv_core
dart analyze .

# 2. Check dependencies
dart pub get

# 3. Verify MQTT broker if touching MQTT code
docker ps | grep mosquitto && ./scripts/mqtt_health_check.sh

# 4. Run npm lint for any JavaScript/configuration changes
cd ../../
npm run lint
```

## Common Development Tasks

### Working with the Core Package

**Primary development location**: `packages/merkle_kv_core/`

```bash
# Navigate to core package
cd packages/merkle_kv_core

# Check package health
dart pub get && dart analyze .

# Key directories:
ls lib/src/
# commands/     - Command processing and timeout management
# storage/      - In-memory storage with LWW conflict resolution
# mqtt/         - MQTT client implementation
# replication/  - CBOR serialization and event publishing
# config/       - Configuration management
# anti_entropy/ - Synchronization protocol
```

### Understanding Timeouts and Timing

From `packages/merkle_kv_core/lib/src/commands/timeout_manager.dart`:
- Single-key operations: 10 seconds
- Multi-key operations: 20 seconds  
- Sync operations: 30 seconds

**Development operation timings (measured):**
- `dart pub get`: ~1 second
- `dart analyze`: ~2-3 seconds
- MQTT broker startup: ~2-5 seconds
- MQTT health check: ~2-3 seconds
- `npm install`: ~10-15 seconds
- `npm run lint`: ~0.3 seconds

### MQTT Integration Development

**IMPORTANT**: All MQTT operations use QoS=1 and retain=false per the Locked Spec.

Key configuration files:
- `packages/merkle_kv_core/lib/src/config/default_config.dart` - Environment configs
- `packages/merkle_kv_core/lib/src/mqtt/topic_scheme.dart` - Topic structure

Example topic structure:
```
{topicPrefix}/commands/{clientId}      # Command requests
{topicPrefix}/responses/{clientId}     # Command responses  
{topicPrefix}/replication/events       # Replication events
```

### Replication System

**Core components:**
- **CBOR Serialization**: `lib/src/replication/cbor_serializer.dart`
- **Event Publishing**: `lib/src/replication/event_publisher.dart`
- **Anti-Entropy Protocol**: `lib/src/anti_entropy/sync_protocol.dart`

**Payload limits (per Locked Spec §11)**:
- Key size: ≤256 bytes
- Value size: ≤256 KiB  
- Command payload: ≤512 KiB
- CBOR replication payload: ≤300 KiB

## Project Structure Quick Reference

```
.
├── packages/
│   └── merkle_kv_core/          # Main Dart package
│       ├── lib/src/             # Source code
│       ├── test/                # Test suites (NOT RUNNABLE)
│       └── pubspec.yaml         # Package dependencies
├── apps/
│   └── flutter_demo/            # Flutter app (NOT BUILDABLE)
├── broker/mosquitto/            # MQTT broker configuration
├── docs/                        # Documentation
├── scripts/                     # Development scripts
│   ├── mqtt_health_check.sh     # MQTT testing utility
│   └── dev/setup.sh             # Environment setup
├── melos.yaml                   # Monorepo configuration
├── package.json                 # Node.js workspace
└── README.md                    # Project overview
```

## Debugging and Troubleshooting

### Common Issues and Solutions

1. **Dart SDK Issues**:
   ```bash
   # Reinstall Dart SDK
   sudo rm -rf /usr/local/dart-sdk
   # Follow bootstrap steps above
   ```

2. **MQTT Connection Failures**:
   ```bash
   # Check broker status
   docker ps | grep mosquitto
   
   # Restart broker
   docker stop test-mosquitto && docker rm test-mosquitto
   docker run -d --name test-mosquitto -p 1883:1883 eclipse-mosquitto:1.6
   
   # Test connectivity
   ./scripts/mqtt_health_check.sh
   ```

3. **Package Dependency Issues**:
   ```bash
   cd packages/merkle_kv_core
   dart pub deps  # Show dependency tree
   dart pub outdated  # Check for updates
   rm -rf .dart_tool/ && dart pub get  # Clean rebuild
   ```

4. **Analysis Errors**:
   - Expected errors in `OptimizedMqttClient` and `ErrorClassifier` are known issues
   - New errors indicate problems with your changes
   - Focus on fixing new errors you introduce

### Development Environment Status Check

```bash
# Quick environment validation
cd /home/runner/work/MerkleKV-Mobile/MerkleKV-Mobile

# Check tools
echo "Dart: $(dart --version 2>&1 | head -1)"
echo "Node: $(node --version)"
echo "Docker: $(docker --version)"

# Check broker
docker ps | grep mosquitto || echo "❌ MQTT broker not running"

# Check core package
cd packages/merkle_kv_core
dart pub get > /dev/null && echo "✅ Core package dependencies OK" || echo "❌ Package issues"
```

## Architecture and Specification Compliance

**This codebase implements the Locked Specification v1.0:**

- **MQTT Transport Only**: No fallback protocols
- **QoS=1, retain=false**: All MQTT operations  
- **Size Limits**: Enforced per specification
- **Timeout Handling**: 10s/20s/30s for single/multi/sync operations
- **LWW Conflict Resolution**: With vector timestamps
- **Exponential Backoff**: For reconnection with jitter
- **Deterministic Behavior**: CBOR serialization
- **Operation Idempotency**: Required for all operations

**Key Files for Spec Compliance:**
- `lib/src/commands/timeout_manager.dart` - Timeout enforcement
- `lib/src/replication/cbor_serializer.dart` - Deterministic serialization
- `lib/src/mqtt/topic_validator.dart` - Topic structure validation
- `lib/src/config/merkle_kv_config.dart` - Configuration validation

## Final Notes

- **DO NOT attempt to run `dart test`** - the test framework is broken in this environment
- **DO NOT attempt to build Flutter apps** - Flutter SDK has download issues
- **ALWAYS start with static analysis** - `dart analyze .` is your primary validation tool
- **ALWAYS test MQTT integration manually** when working with MQTT code
- **NEVER CANCEL fast operations** - analysis and builds complete in seconds
- **Focus on the core Dart package** - `packages/merkle_kv_core/` is the main development target

The codebase has known analysis issues that should not be "fixed" as they represent incomplete implementations that are outside the scope of typical development tasks.