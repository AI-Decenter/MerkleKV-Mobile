# MerkleKV Mobile

A distributed key-value store optimized for mobile edge devices with MQTT-based communication and replication.

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  merkle_kv_core: ^0.0.1
```

Then run:

```bash
flutter pub get
```

## Features

- **MQTT-based communication** with connection management and topic routing
- **In-memory storage** with Last-Write-Wins conflict resolution and optional persistence  
- **Command correlation** for request-response patterns over MQTT
- **CBOR serialization** for deterministic replication event encoding with size limits
- **Comprehensive configuration** with validation and security features
