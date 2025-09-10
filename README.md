# MerkleKV Mobile

A distributed key-value store optimized for mobile edge devices with MQTT-based communication and replication.

## 📋 Table of Contents

- [📱 Overview](#-overview)
- [🚀 Getting Started](#-getting-started)
- [🏗️ Architecture](#️-architecture)
- [📚 API Reference](#-api-reference)
- [🔄 Replication System](#-replication-system)
- [💻 Implementation Details](#-implementation-details)
- [🛠️ Configuration](#️-configuration)
- [📋 Usage Example](#-usage-example)
- [🏭 Implementation Steps](#-implementation-steps)
- [🧪 Testing Strategy](#-testing-strategy)
- [📊 Performance Considerations](#-performance-considerations)
- [📱 Platform Support](#-platform-support)
- [🔒 Security Considerations](#-security-considerations)
- [⚡ Next Steps](#-next-steps)

## 📱 Overview

MerkleKV Mobile is a lightweight, distributed key-value store designed specifically for mobile edge
devices. Unlike the original MerkleKV that uses a TCP server for client-server communication,
MerkleKV Mobile uses MQTT for all communications, making it ideal for mobile environments where
opening TCP ports is not feasible.

The system provides:

- In-memory key-value storage
- Real-time data synchronization between devices
- MQTT-based request-response communication pattern
- Efficient Merkle tree-based anti-entropy synchronization
- Device-specific message routing using client IDs

## What's New (Phase 1 — Core)

- **MerkleKVConfig** (Locked Spec §11): Centralized, immutable configuration with strict validation, secure credential handling, JSON (sans secrets), `copyWith`, and defaults:
  - `keepAliveSeconds=60`, `sessionExpirySeconds=86400`, `skewMaxFutureMs=300000`, `tombstoneRetentionHours=24`.
- **MQTT Client Layer** (Locked Spec §6): Connection lifecycle, exponential backoff (1s→32s, jitter ±20%), session persistence (Clean Start=false, Session Expiry=24h), LWT, QoS=1 & retain=false enforcement, TLS when credentials present.
- **Command Correlation Layer** (Locked Spec §3.1-3.2): Request/response correlation with UUIDv4 generation, operation-specific timeouts (10s/20s/30s), deduplication cache (10min TTL, LRU eviction), payload size validation (512 KiB limit), structured logging, and async/await API over MQTT.
- **Command Processor** (Locked Spec §4.1-§4.4): Core command processing with GET/SET/DEL operations, UTF-8 size validation (keys ≤256B, values ≤256KiB), version vector generation with sequence numbers, idempotency cache with TTL and LRU eviction, comprehensive error handling with standardized error codes.
- **Storage Engine** (Locked Spec §5.1, §5.6, §8): In-memory key-value store with UTF-8 support, Last-Write-Wins conflict resolution using `(timestampMs, nodeId)` ordering, tombstone management with 24-hour retention and garbage collection, optional persistence with SHA-256 checksums and corruption recovery, size constraints (keys ≤256B, values ≤256KiB UTF-8).
- **CBOR Serializer** (Locked Spec §3.3): Deterministic CBOR encoding/decoding for replication events with `timestamp_ms` standardization, fixed field ordering (`key`, `node_id`, `seq`, `timestamp_ms`, `tombstone`, `value`), 300 KiB payload limits, UTF-8 aware validation, and comprehensive error handling (`MALFORMED_CBOR`, `SCHEMA_VIOLATION`, `PAYLOAD_TOO_LARGE`).

### Storage Engine Features

The core storage engine provides:

- **In-memory key-value operations** with concurrent-safe access
- **Last-Write-Wins conflict resolution** per Locked Spec §5.1:
  - Primary ordering by `timestampMs` (wall clock)
  - Tiebreaker by `nodeId` (lexicographic)
  - Duplicate detection for identical version vectors
- **Tombstone lifecycle management** per Locked Spec §5.6:
  - Delete operations create tombstones (24-hour retention)
  - Automatic garbage collection of expired tombstones
  - Read-your-writes consistency (tombstones return null)
- **Optional persistence** with integrity guarantees:
  - Append-only JSON Lines format with SHA-256 checksums
  - Corruption recovery (skip bad records, continue loading)
  - Atomic file operations prevent data loss
- **UTF-8 size validation** per Locked Spec §11:
  - Keys: ≤256 bytes UTF-8 encoded
  - Values: ≤256 KiB bytes UTF-8 encoded
  - Multi-byte character boundary handling

### Quick Storage Example

```dart
import 'package:merkle_kv_core/merkle_kv_core.dart';

// Configuration with persistence disabled (in-memory only)
final config = MerkleKVConfig(
  mqttHost: 'broker.example.com',
  clientId: 'mobile-device-1',
  nodeId: 'device-uuid-123',
  persistenceEnabled: false,
);

// Create storage instance
final storage = StorageFactory.create(config);
await storage.initialize();

// Store data with version vector
final entry = StorageEntry.value(
  key: 'user:123',
  value: 'John Doe',
  timestampMs: DateTime.now().millisecondsSinceEpoch,
  nodeId: config.nodeId,
  seq: 1,
);

await storage.put('user:123', entry);

// Retrieve data
final retrieved = await storage.get('user:123');
print(retrieved?.value); // "John Doe"

// Clean up
await storage.dispose();
```

For persistence-enabled storage:

```dart
// Configuration with persistence enabled
final persistentConfig = MerkleKVConfig(
  mqttHost: 'broker.example.com',
  clientId: 'mobile-device-1',
  nodeId: 'device-uuid-123',
  persistenceEnabled: true,
  storagePath: '/app/storage', // Platform-appropriate path
);

// Storage survives app restarts
final persistentStorage = StorageFactory.create(persistentConfig);
await persistentStorage.initialize(); // Loads existing data

// Data persists across sessions with integrity checks
```

## 🏗️ Architecture

### Communication Model

MerkleKV Mobile uses a pure MQTT communication model:

1. **Command Channel**: Each device subscribes to its own command topic based on its client ID:

   ```text
   merkle_kv_mobile/{client_id}/cmd
   ```

2. **Response Channel**: Responses are published to a client-specific response topic:

   ```text
   merkle_kv_mobile/{client_id}/res
   ```

3. **Replication Channel**: Data changes are published to a shared replication topic:

   ```text
   merkle_kv_mobile/replication/events
   ```

### Topic Scheme (Canonical)

The canonical topic scheme follows Locked Spec §2 with strict validation:

```dart
import 'package:merkle_kv_core/merkle_kv_core.dart';

final scheme = TopicScheme.create('prod/cluster-a', 'device-123');

print(scheme.commandTopic);    // prod/cluster-a/device-123/cmd
print(scheme.responseTopic);   // prod/cluster-a/device-123/res  
print(scheme.replicationTopic); // prod/cluster-a/replication/events

// Topic router manages subscribe/publish with auto re-subscribe
final router = TopicRouterImpl(config, mqttClient);
await router.subscribeToCommands((topic, payload) => handleCommand(payload));
```

### Data Flow

#### Command Execution Flow

```text
Mobile App                  MerkleKV Mobile Library               MQTT Broker
    |                               |                                  |
    |-- Command (SET user:1 value) ->|                                  |
    |                               |-- Publish to {client_id}/cmd --->|
    |                               |                                  |
    |                               |<- Subscribe to {client_id}/res --|
    |                               |                                  |
    |                               |-- Process command locally ------>|
    |                               |                                  |
    |                               |-- Publish result to {client_id}/res ->|
    |<- Response (OK) --------------|                                  |
    |                               |                                  |
```

#### Replication Flow

```text
Device 1                     MQTT Broker                    Device 2
   |                             |                             |
   |-- SET operation ----------->|                             |
   |                             |                             |
   |-- Publish change event ---->|                             |
   |                             |                             |
   |                             |-- Forward change event ---->|
   |                             |                             |
   |                             |<- Subscribe to replication -|
   |                             |                             |
   |                             |                             |-- Apply change locally
   |                             |                             |
```

## 📚 API Reference

### Command Format

Commands are sent as JSON objects to the command topic:

```json
{
  "id": "req-12345",        // Request ID for correlation
  "op": "SET",              // Operation: GET, SET, DEL, etc.
  "key": "user:123",        // Key to operate on
  "value": "john_doe",      // Value (for SET, APPEND, etc.)
  "amount": 5               // Amount (for INCR, DECR operations)
}
```

### Response Format

Responses are published as JSON objects to the response topic:

```json
{
  "id": "req-12345",        // Original request ID
  "status": "OK",           // Status: OK, NOT_FOUND, ERROR
  "value": "john_doe",      // Value (for GET operations)
  "error": "error message"  // Error description (if status is ERROR)
}
```

### Supported Operations

#### Basic Operations

- `GET`: Retrieve a value by key
- `SET`: Store a key-value pair
- `DEL`: Delete a key and its value

#### Numeric Operations

- `INCR`: Increment a numeric value (with optional amount)
- `DECR`: Decrement a numeric value (with optional amount)

#### String Operations

- `APPEND`: Append a value to an existing string
- `PREPEND`: Prepend a value to an existing string

#### Bulk Operations

- `MGET`: Get multiple keys in a single operation
- `MSET`: Set multiple key-value pairs in a single operation
- `KEYS`: List all keys matching a pattern (for debugging)

## 🔄 Replication System

### Change Event Format

Change events are serialized using CBOR for efficiency and published to the replication topic with deterministic field ordering:

```cbor
{
  "key": "user:123",         // Key modified
  "node_id": "device-xyz",   // Source device ID  
  "seq": 42,                 // Sequence number for ordering
  "timestamp_ms": 1637142400000, // Operation timestamp (UTC milliseconds)
  "tombstone": false,        // Whether this is a deletion
  "value": "john_doe"        // New value (omitted if tombstone=true)
}
```

**CBOR Schema Features:**
- **Deterministic encoding**: Fixed field insertion order ensures identical binary output across devices
- **Size limits**: Total CBOR payload ≤ 300 KiB; keys ≤ 256B UTF-8; values ≤ 256 KiB UTF-8
- **Tombstone handling**: Value field omitted for deletions (tombstone=true)
- **Error handling**: `MALFORMED_CBOR`, `SCHEMA_VIOLATION`, `PAYLOAD_TOO_LARGE` error codes

### Conflict Resolution

- **Last-Write-Wins (LWW)**: Conflicts are resolved using timestamp ordering
- **Source Tracking**: Events include source node ID to prevent loops
- **Idempotency**: Duplicate events with the same sequence number are ignored

## 💻 Implementation Details

### Core Components

1. **Storage Engine**: In-memory key-value store with optional persistence
2. **MQTT Client**: Manages subscriptions, publications, and reconnection logic
3. **Command Processor**: Handles incoming commands and generates responses
4. **Replication Manager**: Publishes and applies change events
5. **Merkle Tree**: Efficient data structure for anti-entropy synchronization

### Message Processing Pipeline

```text
MQTT Message → JSON Parsing → Command Validation → Command Execution → 
Response Generation → Response Publishing → (Optional) Replication
```

## Configuration (MerkleKVConfig)

Locked Spec §11 defaults are applied automatically. Secrets are never serialized.

```dart
import 'package:merkle_kv_core/merkle_kv_core.dart';

final cfg = MerkleKVConfig(
  mqttHost: 'broker.example.com',
  clientId: 'android-123',
  nodeId: 'node-01',
  mqttUseTls: true,           // TLS recommended especially with credentials
  username: 'user',           // sensitive: excluded from toJson()
  password: 'pass',           // sensitive: excluded from toJson()
  persistenceEnabled: true,
  storagePath: '/data/merklekv',
);

// JSON does not include secrets
final json = cfg.toJson();
final restored = MerkleKVConfig.fromJson(json, username: 'user', password: 'pass');
```

**Defaults (per §11):** keepAlive=60, sessionExpiry=86400, skewMaxFutureMs=300000, tombstoneRetentionHours=24.

**Validation:** clientId/nodeId length ∈ [1,128]; mqttPort ∈ [1,65535]; timeouts > 0; storagePath required when persistence is enabled.

**Security:** If credentials are provided and mqttUseTls=false, a security warning is emitted.

## MQTT Client Usage

The client enforces QoS=1 and retain=false for application messages. LWT is configured automatically and suppressed on graceful disconnect.

```dart
import 'package:merkle_kv_core/merkle_kv_core.dart';

final client = MqttClientImpl(cfg); // uses MerkleKVConfig

// Observe connection state
final sub = client.connectionState.listen((s) {
  // disconnected, connecting, connected, disconnecting
});

// Connect (<=10s typical)
await client.connect();

// Subscribe
await client.subscribe('${cfg.topicPrefix}/${cfg.clientId}/cmd', (topic, payload) {
  // handle command
});

// Publish (QoS=1, retain=false enforced)
await client.publish('${cfg.topicPrefix}/${cfg.clientId}/res', '{"status":"ok"}');

// Graceful disconnect (suppresses LWT)
await client.disconnect();

// Cleanup
await sub.cancel();
```

**Reconnect:** Exponential backoff 1s→2s→4s→…→32s with ±20% jitter. Messages published during disconnect are queued (bounded) and flushed after reconnect.

**Sessions:** Clean Start=false; Session Expiry=24h.

**TLS:** Automatically enforced when credentials are present; server cert validation required.

## Command Correlation Usage

The CommandCorrelator provides async/await API over MQTT with automatic ID generation, timeouts, and deduplication.

```dart
import 'package:merkle_kv_core/merkle_kv_core.dart';

// Create correlator with MQTT publish function
final correlator = CommandCorrelator(
  publishCommand: (jsonPayload) async {
    await mqttClient.publish('${config.topicPrefix}/${targetClientId}/cmd', jsonPayload);
  },
  logger: (entry) => print('Request lifecycle: ${entry.toString()}'),
);

// Send commands with automatic correlation
final command = Command(
  id: '', // Empty ID will generate UUIDv4 automatically
  op: 'GET',
  key: 'user:123',
);

try {
  final response = await correlator.send(command);
  if (response.isSuccess) {
    print('Result: ${response.value}');
  } else {
    print('Error: ${response.error} (${response.errorCode})');
  }
} catch (e) {
  print('Request failed: $e');
}

// Handle incoming responses
mqttClient.subscribe('${config.topicPrefix}/${config.clientId}/res', (topic, payload) {
  correlator.onResponse(payload);
});

// Cleanup
correlator.dispose();
```

**Features:**
- **Automatic UUIDv4 generation** when command ID is empty
- **Operation-specific timeouts**: 10s (single-key), 20s (multi-key), 30s (sync)
- **Deduplication cache**: 10-minute TTL with LRU eviction for idempotent replies
- **Payload validation**: Rejects commands > 512 KiB
- **Structured logging**: Request lifecycle with timing and error codes
- **Late response handling**: Caches responses that arrive after timeout

## Command Processor Usage

The CommandProcessor handles core GET/SET/DEL operations with validation and idempotency.

```dart
import 'package:merkle_kv_core/merkle_kv_core.dart';

// Create processor with config and storage
final config = MerkleKVConfig.create(
  mqttHost: 'broker.example.com',
  clientId: 'device-123',
  nodeId: 'node-uuid',
);
final storage = StorageFactory.create(config);
await storage.initialize();

final processor = CommandProcessorImpl(config, storage);

// Process commands directly
final getCmd = Command(id: 'req-1', op: 'GET', key: 'user:123');
final getResponse = await processor.processCommand(getCmd);

final setCmd = Command(id: 'req-2', op: 'SET', key: 'user:123', value: 'John Doe');
final setResponse = await processor.processCommand(setCmd);

final delCmd = Command(id: 'req-3', op: 'DEL', key: 'user:123');
final delResponse = await processor.processCommand(delCmd);

// Or use individual methods
final directGet = await processor.get('user:456');
final directSet = await processor.set('user:456', 'Jane Doe');
final directDel = await processor.delete('user:456');

print('Response: ${directGet.status} - ${directGet.value}');
```

**Features:**
- **UTF-8 validation**: Keys ≤256B, values ≤256KiB with proper multi-byte handling
- **Version vectors**: Automatic generation with timestamps and sequence numbers
- **Idempotency**: 10-minute TTL cache with LRU eviction for duplicate requests
- **Error handling**: Standardized codes (INVALID_REQUEST=100, NOT_FOUND=102, PAYLOAD_TOO_LARGE=103)
- **Thread safety**: Atomic sequence number generation for concurrent operations

## CBOR Replication Usage

The CBOR serializer provides deterministic encoding for replication events:

```dart
import 'package:merkle_kv_core/merkle_kv_core.dart';

// Create a replication event
final event = ReplicationEvent.setValue(
  key: 'user:123',
  value: 'john_doe',
  timestamp_ms: DateTime.now().millisecondsSinceEpoch,
  node_id: 'device-xyz',
  seq: 42,
);

// Encode to CBOR for MQTT transmission (deterministic)
final cborBytes = ReplicationCbor.encode(event);

// Decode from CBOR (preserves exact structure)
final decodedEvent = ReplicationCbor.decode(cborBytes);
assert(event == decodedEvent);

// Create tombstone event for deletions
final tombstone = ReplicationEvent.setTombstone(
  key: 'user:456',
  timestamp_ms: DateTime.now().millisecondsSinceEpoch,
  node_id: 'device-xyz',
  seq: 43,
);

// Tombstones omit the value field in CBOR
final tombstoneBytes = ReplicationCbor.encode(tombstone);
```

### High-Level Store Usage

For a complete MerkleKV Mobile store with automatic MQTT connection and replication:

```dart
import 'package:merkle_kv_mobile/merkle_kv_mobile.dart';

void main() async {
  // Initialize the store
  final store = MerkleKVMobile(
    MerkleKVConfig(
      mqttHost: 'broker.example.com',
      mqttPort: 1883,
      clientId: 'mobile-${DateTime.now().millisecondsSinceEpoch}',
      nodeId: 'demo-device',
    ),
  );
  
  // Connect to MQTT broker
  await store.connect();
  
  // Use the store (operations will be replicated)
  await store.set('user:123', 'john_doe');
  final result = await store.get('user:123');
  print('Retrieved: ${result.value}');
  
  // Clean up
  await store.disconnect();
}
```

## 📋 Usage Example

```dart
import 'package:merkle_kv_mobile/merkle_kv_mobile.dart';

void main() async {
  // Initialize the store
  final store = MerkleKVMobile(
    MerkleKVConfig(
      mqttBroker: 'test.mosquitto.org',
      mqttPort: 1883,
      clientId: 'mobile-${DateTime.now().millisecondsSinceEpoch}',
      nodeId: 'demo-device',
    ),
  );
  
  // Connect to MQTT broker
  await store.connect();
  
  // Set a value
  final setResult = await store.set('user:123', 'john_doe');
  print('SET result: ${setResult.status}');
  
  // Get a value
  final getResult = await store.get('user:123');
  print('GET result: ${getResult.value}');
  
  // Increment a counter
  await store.set('counter', '10');
  final incrResult = await store.incr('counter', 5);
  print('INCR result: ${incrResult.value}'); // Should be 15
  
  // Delete a value
  final delResult = await store.delete('user:123');
  print('DEL result: ${delResult.status}');
  
  // Close the connection
  await store.disconnect();
}
```

## 🏭 Implementation Steps

### Phase 1: Core Functionality

1. Implement basic MQTT client with reconnection handling
2. Create in-memory storage engine
3. Implement command processing pipeline
4. Add request-response pattern over MQTT
5. Basic GET/SET/DEL operations

### Phase 2: Advanced Operations

1. Add numeric operations (INCR/DECR)
2. Add string operations (APPEND/PREPEND)
3. Add bulk operations (MGET/MSET)
4. Implement operation timeout handling
5. Add persistent storage option

### Phase 3: Replication System

1. ✅ Implement change event serialization (CBOR) - **COMPLETED**
2. Add replication event publishing
3. Implement replication event handling
4. Add Last-Write-Wins conflict resolution
5. Implement loop prevention mechanism

### Phase 4: Anti-Entropy & Optimization

1. Implement Merkle tree for efficient synchronization
2. Add anti-entropy protocol
3. Optimize message sizes
4. Add compression for large values
5. Implement efficient binary protocol

## 🧪 Testing Strategy

1. **Unit Tests**: Test individual components in isolation
2. Unit tests for core components
3. Mock-based tests for MQTT communication
4. Integration tests with real MQTT brokers
5. Flutter-specific integration tests
6. End-to-end tests in a real mobile environment

## 📊 Performance Considerations

- **Message Size**: Use CBOR encoding for compact messages
- **Battery Impact**: Implement intelligent reconnection strategy
- **Bandwidth Usage**: Batch operations when possible
- **Storage Efficiency**: Use incremental updates for large values
- **CPU Usage**: Optimize Merkle tree calculations for mobile CPUs

## 📱 Platform Support

- Android (API level 21+)
- iOS (iOS 10+)
- Flutter compatibility
- React Native compatibility (through native bridge)

## 🔒 Security Considerations

- **Authentication**: Support for MQTT username/password and client certificates
- **Authorization**: Topic-level access control using client ID
- **Encryption**: TLS for transport security
- **Data Privacy**: Optional value encryption at rest

## 🚀 Getting Started

### Quick Setup

The MerkleKV Mobile project structure has been created and includes:

✅ **Complete Monorepo Structure**

- Core Dart package with essential interfaces
- Flutter demo application template
- MQTT broker with security configuration
- Comprehensive documentation and CI/CD pipelines

✅ **Production-Ready MQTT Broker**

- TLS encryption support
- User authentication and ACL
- Docker containerization
- Health monitoring

### Prerequisites

- **Flutter SDK** 3.10.0 or higher
- **Dart SDK** 3.0.0 or higher
- **Docker** (for MQTT broker)
- **Git** for version control

## Quick Start (Dev)

```bash
# 1) Bootstrap monorepo
melos bootstrap

# 2) Static analysis & format checks
dart analyze
dart format --output=none --set-exit-if-changed .

# 3) Run tests (pure Dart + Flutter where applicable)
dart test -p vm packages/merkle_kv_core
flutter test
```

### Development Setup

1. **Clone and Bootstrap the Project**:

   ```bash
   git clone https://github.com/mico220706/MerkleKV-Mobile.git
   cd MerkleKV-Mobile
   
   # Install Melos for monorepo management
   dart pub global activate melos
   
   # Bootstrap all packages
   melos bootstrap
   ```

2. **Start the MQTT Broker**:

   ```bash
   # Navigate to broker directory
   cd broker/mosquitto
   
   # Start the broker with Docker Compose
   docker-compose up -d
   
   # Verify broker is running
   docker-compose ps
   ```

3. **Run the Flutter Demo**:

   ```bash
   cd apps/flutter_demo
   flutter run
   ```

### Quick Usage Example

1. **Add the package to your pubspec.yaml**:

   ```yaml
   dependencies:
     merkle_kv_core:
       path: ../../packages/merkle_kv_core
   ```

2. **Import and use the package**:

   ```dart
   import 'package:merkle_kv_core/merkle_kv_core.dart';
   
   void main() async {
     // Initialize with your MQTT broker
     final store = MerkleKVMobile(
       MerkleKVConfig(
         mqttBroker: 'localhost',  // Use your broker address
         mqttPort: 1883,
         clientId: 'device-${DateTime.now().millisecondsSinceEpoch}',
         nodeId: 'demo-device',
       ),
     );
     
     // Connect to the broker
     await store.connect();
     
     // Use the store
     await store.set('profile:name', 'John Doe');
     final result = await store.get('profile:name');
     print('Retrieved: ${result.value}');
     
     // Clean up
     await store.disconnect();
   }
   ```

### Project Structure

```text
MerkleKV-Mobile/
├── packages/
│   └── merkle_kv_core/          # Core Dart implementation
├── apps/
│   └── flutter_demo/            # Flutter demonstration app
├── broker/
│   └── mosquitto/               # MQTT broker configuration
├── scripts/
│   └── dev/                     # Development automation
├── docs/                        # Technical documentation
└── .github/workflows/           # CI/CD automation
```

### Development Commands

```bash
# Analyze code across all packages
melos run analyze

# Format code across all packages
melos run format

# Run tests across all packages
melos run test

# Start development broker
./scripts/dev/start_broker.sh

# Setup development environment
./scripts/dev/setup.sh
```

### Code Formatting

This project enforces strict Dart formatting in CI.  
Before committing or opening a PR, always run:

```bash
dart format .
```

If formatting is not applied, CI will fail.

## ⚡ Next Steps

- Implement offline queue for operation persistence
- Add client-side caching strategy
- Create administration dashboard for monitoring
- Add support for complex data types
- Implement cross-platform plugins

## Code Style and CI Policy

This repository enforces strict Dart formatting in CI. All `.dart` files must pass `dart format --set-exit-if-changed`.

Developers must run the formatter locally before committing:

```bash
dart format .
```

CI will fail if formatting is not compliant.

## Release Workflow Guide

The GitHub Actions job **"Release Management & Distribution"** is **intentionally skipped** on normal
branches and pull requests. It only runs when a **semantic version tag** is pushed (e.g., `v1.0.0`,
`v1.1.0-beta.1`, `v2.0.0-rc.1`).

**When should I push a release tag?**

- After a milestone is complete and CI is green (Static Analysis, Tests, Documentation all passing).
- When publishing a versioned package or a public snapshot for users/contributors.
- Not for every small change (to avoid release spam).

**Tag types (SemVer):**

- Stable: `vX.Y.Z` (e.g., `v1.0.0`)
- Pre-release: `vX.Y.Z-alpha.N`, `vX.Y.Z-beta.N`
- Release Candidate: `vX.Y.Z-rc.N`

**How to create and push a release tag:**

```bash
# Ensure you're on main and CI is green
git checkout main
git pull origin main

# Create a semantic version tag
git tag v0.1.0

# Push the tag to trigger the Release job
git push origin v0.1.0
```

**What happens after pushing the tag?**

The Release job runs and:

- Validates code quality (pre-release gates)
- Builds source distribution & checksums
- Generates detailed release notes
- Publishes a GitHub Release with artifacts

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details on:

- Code of conduct
- Development workflow
- Pull request process
- Issue reporting guidelines

### Development Status

| Component | Status | Description |
|-----------|---------|-------------|
| **Core Package** | 🟡 In Progress | Basic interfaces and configuration |
| **Flutter Demo** | 🟡 In Progress | Template application structure |
| **MQTT Broker** | ✅ Complete | Production-ready with TLS/ACL |
| **CI/CD Pipeline** | ✅ Complete | Enterprise-grade automation |
| **Documentation** | 🟡 In Progress | Architecture and API docs |
| **Testing** | 🔴 Planned | Unit and integration tests |

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙋‍♂️ Support

- 📖 **Documentation**: [docs/](docs/)
- 🐛 **Bug Reports**: [GitHub Issues](https://github.com/mico220706/MerkleKV-Mobile/issues)
- 💡 **Feature Requests**: [GitHub Discussions](https://github.com/mico220706/MerkleKV-Mobile/discussions)
- 🔒 **Security Issues**: See [SECURITY.md](SECURITY.md)

---

## Made with ❤️ for mobile distributed systems
