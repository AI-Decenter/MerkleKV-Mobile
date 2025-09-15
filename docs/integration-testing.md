# Integration Testing with Real MQTT Brokers

## Overview

This document describes the comprehensive integration test suite for MerkleKV Mobile that uses real MQTT brokers (Mosquitto and HiveMQ) to validate end-to-end system behavior under realistic network conditions.

## Features

### Multi-Broker Testing
- **Mosquitto 2.0**: Open-source MQTT broker for standard scenarios
- **HiveMQ CE**: Commercial-grade broker for advanced feature testing
- **Toxiproxy**: Network proxy for partition simulation and fault injection

### Specification Compliance Testing
- **Payload Limits**: 256KiB individual values, 512KiB bulk operations (Locked Spec §11)
- **Anti-Entropy**: Convergence within configured intervals ± 20% variance
- **Security**: TLS 1.2+ enforcement, ACL validation, client certificates
- **MQTT Compatibility**: Support for MQTT v3.1.1 and v5.0

### Comprehensive Test Coverage
- End-to-end operations (GET/SET/DEL) through real brokers
- TLS connection establishment and certificate validation
- ACL enforcement preventing cross-tenant access
- Network partition tolerance with message queuing
- Concurrent operations with Last-Writer-Wins conflict resolution
- Broker restart scenarios and connection recovery

## Quick Start

### 1. Start Test Environment
```bash
# From project root
./scripts/setup-integration-tests.sh
```

This script:
- Generates TLS certificates for testing
- Configures ACL files for multi-tenant scenarios
- Starts Docker containers with health checks
- Validates broker connectivity

### 2. Run Integration Tests
```bash
cd packages/merkle_kv_core

# Run all integration tests
dart test test/integration/ --reporter=expanded

# Run specific test categories
dart test -t broker-integration    # Core broker tests
dart test -t convergence           # Anti-entropy timing tests

# Exclude integration tests (unit tests only)
dart test -x integration
```

### 3. Stop Test Environment
```bash
docker-compose -f docker-compose.test.yml down
```

## Test Categories

### End-to-End Operations
Validates basic MQTT operations through real brokers:
```dart
test('Mosquitto: Basic GET/SET/DEL operations work correctly', () async {
  // Connects to real Mosquitto broker
  // Publishes SET command via MQTT
  // Validates message processing
});
```

### Payload Limit Validation
Tests Locked Specification payload limits:
```dart
test('256KiB individual values are accepted', () async {
  final value256kb = generatePayload(256 * 1024);
  // Verify broker accepts 256KiB values
});

test('512KiB bulk operations are processed correctly', () async {
  final bulkData = createBulkPayload(50, 10 * 1024); // ~500KiB
  // Verify broker processes bulk operations within limits
});
```

### TLS and Security Testing
Validates security configurations:
```dart
test('TLS 1.2+ connection establishment', () async {
  final config = createTestConfig(broker, useTLS: true);
  // Establishes real TLS connection to broker
});

test('ACL enforcement prevents cross-tenant access', () async {
  // Tests that tenant_a_user1 cannot access tenant_b topics
});
```

### Anti-Entropy Convergence
Tests specification-compliant convergence timing:
```dart
test('Convergence occurs within configured interval ± 20% variance', () async {
  // Creates divergent state between two nodes
  // Measures actual convergence time
  // Validates timing against specification
});
```

## Configuration

### Broker Endpoints
- **Mosquitto**: localhost:1883 (MQTT), localhost:8883 (TLS)
- **HiveMQ**: localhost:1884 (MQTT), localhost:8884 (TLS)
- **Toxiproxy**: localhost:1885-1886 (proxied connections)

### Test Users and ACL
The test environment includes pre-configured users for ACL testing:

| User | Password | Access |
|------|----------|--------|
| admin | password123 | Full access to all topics |
| tenant_a_user1 | password123 | merkle_kv_mobile_a/* only |
| tenant_b_user1 | password123 | merkle_kv_mobile_b/* only |
| readonly_user | password123 | Read-only access |
| device_001 | password123 | Device-specific topics |

### Environment Variables
```bash
# Override default broker settings
MQTT_TEST_HOST=localhost
MQTT_TEST_PORT=1883
MQTT_TEST_USERNAME=tenant_a_user1
MQTT_TEST_PASSWORD=password123
MQTT_TEST_USE_TLS=true
```

## Architecture

### Test Structure
```
docker-compose.test.yml              # Multi-broker test environment
test/
├── mosquitto.conf                   # Mosquitto configuration
├── mosquitto-acl.conf              # ACL rules for multi-tenant testing
├── mosquitto-passwd                # Test user credentials
├── mosquitto-tls/                  # TLS certificates
└── hivemq-config/                  # HiveMQ configuration

packages/merkle_kv_core/test/integration/
├── broker_integration_test.dart    # Main integration test suite
├── convergence_test.dart           # Anti-entropy convergence tests
└── README.md                       # Integration test documentation

scripts/
└── setup-integration-tests.sh      # Test environment setup script
```

### Key Components

#### BrokerTestConfig
Defines broker endpoints and capabilities:
```dart
static const mosquitto = BrokerTestConfig(
  name: 'Mosquitto',
  host: 'localhost',
  port: 1883,
  tlsPort: 8883,
  supportsTLS: true,
  credentials: {'admin': 'password123', ...},
);
```

#### IntegrationTestHelpers
Utility functions for broker operations:
```dart
static Future<bool> isBrokerAvailable(BrokerTestConfig config);
static MerkleKVConfig createTestConfig(BrokerTestConfig broker);
static String generatePayload(int sizeBytes);
```

#### Test Timing Constants
Specification-aligned timeouts:
```dart
class IntegrationTestTiming {
  static const Duration brokerConnectTimeout = Duration(seconds: 10);
  static const Duration operationTimeout = Duration(seconds: 15);
  static const Duration convergenceTimeout = Duration(seconds: 45);
}
```

## Graceful Degradation

The integration tests are designed to work in various environments:

### With Brokers Available
- Full test suite runs against real MQTT brokers
- Validates actual network behavior and timing
- Tests TLS, ACL, and broker-specific features

### Without Brokers Available
- Tests automatically detect unavailable brokers
- All integration tests are gracefully skipped
- Clear guidance provided for starting test environment
- Unit tests continue to run normally

Example output when brokers are unavailable:
```
✗ Mosquitto broker not available at localhost:1883
✗ HiveMQ broker not available at localhost:1884

❌ No MQTT brokers available for integration testing.
Please start brokers using: docker-compose -f docker-compose.test.yml up -d
Skipping all integration tests.

00:00 +1 ~14: All tests passed!
```

## CI Integration

### GitHub Actions Example
```yaml
name: Integration Tests
on: [push, pull_request]

jobs:
  integration-tests:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup Dart SDK
      uses: dart-lang/setup-dart@v1
      
    - name: Start Integration Test Environment
      run: ./scripts/setup-integration-tests.sh
      
    - name: Install Dependencies
      run: |
        cd packages/merkle_kv_core
        dart pub get
        
    - name: Run Integration Tests
      run: |
        cd packages/merkle_kv_core
        dart test test/integration/ --reporter=expanded --timeout=10m
        
    - name: Stop Test Environment
      if: always()
      run: docker-compose -f docker-compose.test.yml down
```

### Local Development
```bash
# Start environment once
./scripts/setup-integration-tests.sh

# Run tests during development
cd packages/merkle_kv_core
dart test test/integration/broker_integration_test.dart -t broker-integration

# Keep environment running for iterative testing
# Stop when done: docker-compose -f docker-compose.test.yml down
```

## Troubleshooting

### Common Issues

**Broker Connection Failures**
```bash
# Check broker status
docker-compose -f docker-compose.test.yml ps

# View broker logs
docker-compose -f docker-compose.test.yml logs mosquitto

# Test manual connection
mosquitto_sub -h localhost -p 1883 -t '$SYS/broker/uptime' -C 1
```

**TLS Certificate Issues**
```bash
# Regenerate certificates
rm -rf test/mosquitto-tls/*
./scripts/setup-integration-tests.sh

# Test TLS connection
mosquitto_sub -h localhost -p 8883 -t '$SYS/broker/uptime' -C 1 \
  --cafile test/mosquitto-tls/ca.crt --insecure
```

**Test Timeouts**
- Use appropriate test tags for faster feedback
- Increase timeouts for convergence tests
- Check broker health and connectivity

## Specification Compliance

The integration tests validate compliance with the Locked Specification:

- **§4.7**: MGET operation limits (256 keys maximum)
- **§4.8**: MSET operation limits (100 key-value pairs maximum)  
- **§6**: MQTT connection lifecycle and Last Will Testament
- **§11**: Message payload limits (256KiB values, 512KiB bulk operations)
- **Security**: TLS 1.2+ enforcement when credentials are present
- **Anti-entropy**: Convergence within configured intervals with 20% variance tolerance

This comprehensive test suite ensures that MerkleKV Mobile functions correctly in production-like environments with real MQTT broker implementations.