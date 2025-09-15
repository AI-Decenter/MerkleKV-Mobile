# MerkleKV Mobile Integration Testing

This directory contains comprehensive integration tests for the MerkleKV Mobile system using real MQTT brokers. These tests validate end-to-end functionality, security configurations, payload limits, and convergence behavior per the Locked Specification.

## Test Environment

The integration tests use a Docker Compose environment with multiple MQTT brokers:

- **Mosquitto 2.0**: Open-source MQTT broker (ports 1883, 8883)
- **HiveMQ CE**: Commercial-grade MQTT broker (ports 1884, 8884)
- **Toxiproxy**: Network proxy for partition testing (ports 1885, 8885, 1886, 8886)

## Quick Start

1. **Start the test environment:**
   ```bash
   # From project root
   ./scripts/setup-integration-tests.sh
   ```

2. **Run integration tests:**
   ```bash
   cd packages/merkle_kv_core
   dart test test/integration/ --reporter=expanded
   ```

3. **Stop the test environment:**
   ```bash
   docker-compose -f docker-compose.test.yml down
   ```

## Test Categories

### End-to-End Operations
- Basic GET/SET/DEL operations through real brokers
- Message publishing and subscription validation
- Error handling and timeout behavior

### Payload Limit Validation
- 256KiB individual value acceptance (per Locked Spec §11)
- 512KiB bulk operation processing
- Broker enforcement of message size limits
- Edge case testing at exact payload boundaries

### TLS and Security Testing
- TLS 1.2+ connection establishment
- Client certificate authentication
- ACL enforcement and cross-tenant access prevention
- Username/password authentication scenarios

### Anti-Entropy and Convergence
- Multi-client convergence within configured intervals
- Last-Writer-Wins conflict resolution
- Network partition tolerance
- Message queuing during disconnections

### Broker Compatibility Matrix
- MQTT version compatibility (3.1.1, 5.0)
- Cross-broker behavior validation
- Feature parity testing

### Concurrent Operations
- Multiple client scenarios
- Conflict resolution under realistic timing
- Race condition handling

## Test Configuration

### Environment Variables

The tests can be configured using environment variables:

```bash
# Broker endpoints
MQTT_TEST_HOST=localhost
MQTT_TEST_PORT=1883
MQTT_TEST_TLS_PORT=8883

# Authentication (optional)
MQTT_TEST_USERNAME=tenant_a_user1
MQTT_TEST_PASSWORD=password123

# TLS settings
MQTT_TEST_USE_TLS=true
```

### Test Tags

Tests are organized with tags for selective execution:

- `@Tags(['broker-integration'])`: Tests requiring real brokers
- `@Tags(['convergence'])`: Anti-entropy timing tests (extended timeout)
- `@Tags(['integration'])`: General integration tests

Run specific test categories:
```bash
# Run only broker integration tests
dart test -t broker-integration

# Run convergence tests with extended timeouts
dart test -t convergence

# Exclude integration tests (unit tests only)
dart test -x integration
```

## Architecture

### Test Structure

```
test/integration/
├── broker_integration_test.dart    # Main integration test suite
├── convergence_test.dart           # Anti-entropy convergence tests
└── README.md                       # This file
```

### Key Classes

- **BrokerTestConfig**: Multi-broker test configuration
- **IntegrationTestHelpers**: Utility functions for broker testing
- **IntegrationTestTiming**: Timeout and timing constants
- **ConvergenceTestConfig**: Anti-entropy timing validation

## Test Data and Cleanup

### Isolation
- Each test uses unique client IDs and node IDs
- Temporary storage paths prevent data conflicts
- Tests clean up resources in `finally` blocks

### Test Users
The following test users are configured for ACL testing:

```
admin:password123                    # Full access
tenant_a_user1:password123          # merkle_kv_mobile_a/* topics only
tenant_a_user2:password123          # merkle_kv_mobile_a/* topics only  
tenant_b_user1:password123          # merkle_kv_mobile_b/* topics only
tenant_b_user2:password123          # merkle_kv_mobile_b/* topics only
readonly_user:password123           # Read-only access
device_001:password123              # Device-specific topics
device_002:password123              # Device-specific topics
```

## Troubleshooting

### Common Issues

1. **Broker not available**
   ```
   ✗ Mosquitto broker not available at localhost:1883
   ```
   **Solution**: Start brokers with `./scripts/setup-integration-tests.sh`

2. **TLS connection failures**
   ```
   ⚠️ Mosquitto TLS (port 8883) may not be reachable
   ```
   **Solution**: Check certificate generation and broker TLS configuration

3. **Permission denied**
   ```
   Error: Failed to connect: Not authorized
   ```
   **Solution**: Verify ACL configuration and user credentials

4. **Tests timeout**
   ```
   Test timed out after 30s
   ```
   **Solution**: Use appropriate test tags or increase timeouts

### Debugging

View broker logs:
```bash
# All services
docker-compose -f docker-compose.test.yml logs -f

# Specific broker
docker-compose -f docker-compose.test.yml logs -f mosquitto
docker-compose -f docker-compose.test.yml logs -f hivemq
```

Check broker health:
```bash
# Test connectivity
mosquitto_sub -h localhost -p 1883 -t '$SYS/broker/uptime' -C 1

# Test TLS
mosquitto_sub -h localhost -p 8883 -t '$SYS/broker/uptime' -C 1 \
  --cafile test/mosquitto-tls/ca.crt --insecure
```

### Performance Considerations

- Integration tests are slower than unit tests (real network I/O)
- Convergence tests may take up to 10 minutes (anti-entropy intervals)
- Use selective test execution during development
- CI pipeline should run full suite with proper timeouts

## Specification Compliance

These tests validate compliance with the Locked Specification:

- **§4.7-4.8**: Bulk operation limits (256 keys, 100 pairs)
- **§6**: Last Will and Testament configuration
- **§11**: Payload size limits (256KiB values, 512KiB bulk)
- **Security**: TLS 1.2+ enforcement, ACL validation
- **Anti-entropy**: Convergence within configured intervals ± 20% variance

## CI Integration

For CI pipelines:

```yaml
# GitHub Actions example
- name: Start Integration Test Environment
  run: ./scripts/setup-integration-tests.sh

- name: Run Integration Tests
  run: |
    cd packages/merkle_kv_core
    dart test test/integration/ --reporter=expanded --timeout=10m

- name: Stop Test Environment
  if: always()
  run: docker-compose -f docker-compose.test.yml down
```

The tests automatically skip when brokers are unavailable, making them safe for environments where Docker isn't available.