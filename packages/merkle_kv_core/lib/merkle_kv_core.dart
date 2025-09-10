/// MerkleKV Mobile - A distributed key-value store for mobile devices
///
/// This library provides a lightweight, distributed key-value store designed
/// specifically for mobile edge devices using MQTT-based communication.
library merkle_kv_mobile;

// Configuration
export 'src/config/merkle_kv_config.dart';
export 'src/config/invalid_config_exception.dart';
export 'src/config/default_config.dart';

// MQTT Client
export 'src/mqtt/connection_state.dart';
export 'src/mqtt/mqtt_client_interface.dart';
export 'src/mqtt/mqtt_client_impl.dart';
export 'src/mqtt/topic_scheme.dart';
export 'src/mqtt/topic_router.dart';

// Commands and Correlation
export 'src/commands/command.dart';
export 'src/commands/response.dart';
export 'src/commands/command_correlator.dart';
export 'src/commands/command_processor.dart';

// Storage
export 'src/storage/storage_interface.dart';
export 'src/storage/storage_entry.dart';
export 'src/storage/in_memory_storage.dart';
export 'src/storage/storage_factory.dart';

// Replication
export 'src/replication/cbor_serializer.dart';

// Core exports will be added in future phases
// export 'src/merkle_kv_mobile.dart';
