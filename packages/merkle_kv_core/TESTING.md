# Comprehensive Testing Guide for MerkleKV-Mobile

This document outlines the comprehensive testing strategy for MerkleKV-Mobile, covering unit tests, integration tests, and property-based testing approaches with MQTT timeout fixes and broker configuration.

## Overview

The MerkleKV-Mobile testing suite implements comprehensive unit testing for all critical components with >95% code coverage targets. The testing strategy emphasizes negative testing, edge cases, and property-based validation to ensure robustness in distributed environments.

## 🔧 Test Environment Setup

### MQTT Broker Configuration

The test suite requires a properly configured MQTT broker. We provide two configurations:

#### Production Configuration
- **File**: `broker/mosquitto/config/mosquitto.conf`
- **Features**: TLS, authentication, ACL
- **Use**: Production deployment

#### Test Configuration  
- **File**: `broker/mosquitto/config/mosquitto-test.conf`
- **Features**: Anonymous access, optimized for testing
- **Use**: CI/CD and local testing

#### Running Test Broker

```bash
# Using Docker with test configuration
cd broker/mosquitto
docker run -it --rm \
  -p 1883:1883 \
  -v $(pwd)/config/mosquitto-test.conf:/mosquitto/config/mosquitto.conf:ro \
  eclipse-mosquitto:1.6

# Or using docker-compose with test override
docker-compose -f docker-compose.yml -f docker-compose.test.yml up
```

### MQTT Connection Timeout Configuration

The MQTT client has been configured with appropriate timeouts for reliable testing:

- **Connection Timeout**: 10 seconds (increased from 2s default)
- **Keepalive Period**: 30 seconds for tests
- **Retry Interval**: 2 seconds for faster test cycles

### Health Check

Before running integration tests, validate broker availability:

```bash
# Run comprehensive health check
./scripts/mqtt_health_check.sh

# With custom parameters
MQTT_BROKER_HOST=localhost \
MQTT_BROKER_PORT=1883 \
MQTT_HEALTH_TIMEOUT=30 \
./scripts/mqtt_health_check.sh
```

The health check script validates:
- TCP port availability
- Basic MQTT publish/subscribe functionality  
- QoS 1 message delivery
- Connection timing and reliability

### Dependencies

Ensure you have the following dependencies installed:

```bash
# Dart SDK 3.9.3 or later
dart --version

# Flutter SDK (for Flutter packages)
flutter --version

# Install test dependencies
dart pub get
```

## Testing Architecture

### Test Organization

```
test/
├── unit/                          # Comprehensive unit tests
│   ├── storage/                   # Storage engine tests
│   ├── mqtt/                      # MQTT client and router tests
│   └── processor/                 # Command processor tests
├── utils/                         # Testing utilities
│   ├── generators.dart           # Property-based test generators
│   └── mock_helpers.dart         # Mock implementations and test helpers
└── integration/                   # Integration and system tests
    ├── anti_entropy/             # Anti-entropy protocol tests
    ├── replication/              # Replication system tests
    └── mqtt/                     # MQTT integration tests
```

### Testing Tools and Dependencies

- **Package:test**: Core Dart testing framework
- **Mocktail**: Mock object generation for dependency isolation
- **Property-based testing**: Custom generators for comprehensive edge case validation
- **Coverage analysis**: Code coverage measurement and reporting

## Core Unit Test Suites

### 1. Storage Engine Tests (`test/unit/storage/`)

**Purpose**: Validate storage layer correctness with focus on LWW resolution, data consistency, and edge cases.

**Key Test Areas**:
- **Last-Writer-Wins (LWW) Resolution**: Conflict resolution with node ID tiebreakers
- **Tombstone Garbage Collection**: 24-hour retention policy validation
- **UTF-8 Boundary Testing**: Proper handling of Unicode edge cases
- **Deduplication Logic**: (node_id, seq) tuple uniqueness enforcement
- **Concurrent Access Patterns**: Thread safety validation

**Property-Based Tests**:
- Random timestamp generation for LWW scenarios
- Malformed UTF-8 sequence handling
- Large payload stress testing
- Bulk operation boundary conditions

### 2. MQTT Client Tests (`test/unit/mqtt/`)

**Purpose**: Ensure reliable MQTT communication with proper QoS enforcement and connection management.

**Key Test Areas**:
- **QoS=1 Enforcement**: Guaranteed message delivery validation
- **Exponential Backoff**: Reconnection strategy with jitter testing
- **Connection Lifecycle**: State transition validation
- **Malformed Packet Handling**: Graceful error recovery
- **Message Queueing**: Offline message handling and queue management
- **Authentication**: TLS and credential validation

**Critical Negative Tests**:
- Network disconnection scenarios
- Broker rejection handling
- Payload size limit enforcement (1MB limit)
- Invalid topic pattern rejection

### 3. Topic Router Tests (`test/unit/mqtt/`)

**Purpose**: Validate MQTT topic routing with canonical format compliance and security.

**Key Test Areas**:
- **Canonical Topic Generation**: Consistent format validation
- **Wildcard Injection Prevention**: Security against malicious patterns
- **UTF-8 Topic Validation**: Unicode support with proper escaping
- **Multi-tenant Isolation**: Cross-tenant data protection
- **Topic Normalization**: Case-sensitive routing validation

**Security-Focused Tests**:
- MQTT wildcard injection attempts (`+`, `#`)
- Topic hierarchy validation
- Tenant boundary enforcement
- Malformed topic pattern rejection

### 4. Command Processor Tests (`test/unit/processor/`)

**Purpose**: Ensure command processing reliability with comprehensive JSON validation and payload limits.

**Key Test Areas**:
- **JSON Schema Validation**: Strict command format enforcement
- **Bulk Operation Limits**: MGET ≤256 keys, MSET ≤100 key-value pairs
- **Payload Size Validation**: Per-command size limits
- **Idempotency**: Request ID-based duplicate detection
- **Error Classification**: Retriable vs non-retriable error handling

**Boundary Condition Tests**:
- Maximum payload size enforcement
- Bulk operation limit validation
- Malformed JSON rejection
- Invalid command structure handling

## Property-Based Testing Strategy

### Test Data Generators (`test/utils/generators.dart`)

**Random Data Generation**:
- `randomTimestamp()`: Timestamp generation for LWW testing
- `randomNodeId()`: Node identifier generation
- `invalidUtf8Bytes()`: Malformed UTF-8 sequence generation
- `payloadOfSize()`: Specific size payload creation
- `malformedJson()`: Invalid JSON structure generation
- `bulkCommandNearLimit()`: Boundary condition command generation

**Usage Pattern**:
```dart
// Property-based test example
check(
  () => TestGenerators.randomTimestamp(),
  (timestamp) {
    final entry = TestDataFactory.createEntry(timestampMs: timestamp);
    // Validate LWW behavior with random timestamps
    return storage.put(entry.key, entry).then((_) => true);
  },
);
```

### Mock Implementations (`test/utils/mock_helpers.dart`)

**Mock Classes**:
- `MockStorage`: In-memory storage with configurable LWW resolution
- `MockMqttClient`: MQTT client simulation with state tracking
- `TestDataFactory`: Consistent test object creation
- `TestAssertions`: Specialized assertion helpers

**Mock Capabilities**:
- Configurable failure scenarios
- State transition simulation
- Message delivery tracking
- Error injection for negative testing

## Running Tests

### Prerequisites

```bash
# Install Dart SDK 3.9.3 or later
# Activate coverage package
dart pub global activate coverage
```

### Test Execution

```bash
# Run all tests
dart test

# Run unit tests only
dart test test/unit/

# Run specific test suite
dart test test/unit/storage/storage_engine_unit_test.dart

# Run with coverage
dart test --coverage=coverage/
dart pub global run coverage:format_coverage --lcov --in=coverage/ --out=coverage/lcov.info

# Generate HTML coverage report
genhtml coverage/lcov.info -o coverage/html
```

### Continuous Integration

```yaml
# GitHub Actions example
- name: Run Unit Tests
  run: |
    dart pub get
    dart test test/unit/ --reporter=json > test_results.json
    dart test --coverage=coverage/

- name: Coverage Analysis
  run: |
    dart pub global run coverage:format_coverage --lcov --in=coverage/ --out=coverage/lcov.info
    # Enforce >95% coverage requirement
```

## Test Coverage Requirements

### Coverage Targets
- **Overall Coverage**: >95%
- **Unit Test Coverage**: >98%
- **Critical Path Coverage**: 100%

### Coverage Exclusions
- Generated code files
- Example/demo applications
- Development utilities

### Coverage Validation
```bash
# Verify coverage meets requirements
dart pub global run coverage:format_coverage \
  --lcov --in=coverage/ --out=coverage/lcov.info

# Check coverage percentage
lcov --summary coverage/lcov.info
```

## Testing Best Practices

### Unit Test Design Principles

1. **Isolation**: Each test should be independent and not rely on external state
2. **Determinism**: Tests should produce consistent results across environments
3. **Clarity**: Test names should clearly describe the scenario being validated
4. **Completeness**: Cover both happy path and error conditions
5. **Performance**: Tests should execute quickly for fast feedback

### Negative Testing Guidelines

1. **Input Validation**: Test all input boundaries and invalid formats
2. **Resource Limits**: Validate behavior at memory/storage/network limits
3. **Failure Scenarios**: Test network failures, disk full, permission errors
4. **Malformed Data**: Test with corrupted, truncated, or malicious inputs
5. **Concurrent Access**: Test race conditions and deadlock scenarios

### Property-Based Testing Guidelines

1. **Generator Design**: Create generators that explore edge cases systematically
2. **Invariant Definition**: Define properties that should always hold
3. **Shrinking**: Implement test case minimization for easier debugging
4. **Seed Control**: Use deterministic seeds for reproducible property tests

## Integration with Development Workflow

### Pre-commit Hooks
```bash
#!/bin/sh
# .git/hooks/pre-commit
dart analyze --fatal-infos
dart test test/unit/
echo "All unit tests passed ✓"
```

### IDE Integration
- Configure VS Code/IntelliJ to run tests on save
- Set up test coverage highlighting
- Enable test result notifications

### Code Review Requirements
- All new code must include corresponding unit tests
- Coverage reports must be included in PR descriptions
- Property-based tests required for data processing logic
- Negative test cases required for error handling paths

## Troubleshooting

### Common Issues

**Frontend Server Errors**:
```bash
# If seeing frontend_server.dart.snapshot errors
dart pub cache repair
dart test --no-sound-null-safety
```

**Coverage Collection Issues**:
```bash
# Clear coverage data
rm -rf coverage/
dart test --coverage=coverage/
```

**Mock Setup Problems**:
```dart
// Ensure proper mock setup in setUp()
setUp(() {
  mockClient = MockMqttClient();
  when(() => mockClient.connect()).thenAnswer((_) async {});
});
```

### Performance Optimization

- Use `group()` to organize related tests for better reporting
- Implement `setUpAll()` for expensive initialization
- Use `tearDown()` for proper cleanup to prevent memory leaks
- Consider parallel test execution for large test suites

## Metrics and Reporting

### Test Metrics Tracked
- **Test Execution Time**: Monitor for performance regressions
- **Code Coverage Percentage**: Ensure coverage requirements are met
- **Test Failure Rate**: Track test stability over time
- **Property Test Iteration Count**: Monitor property test thoroughness

### Automated Reporting
- Generate coverage reports on every CI run
- Track coverage trends over time
- Alert on coverage drops below thresholds
- Include test metrics in release notes

---

This comprehensive testing guide ensures robust validation of MerkleKV-Mobile components with emphasis on edge cases, negative testing, and property-based validation for distributed system reliability.