/// MerkleKV Mobile - A distributed key-value store for mobile devices
///
/// This library provides a lightweight, distributed key-value store designed
/// specifically for mobile edge devices using MQTT-based communication.
library merkle_kv_mobile;

// Public API Surface
export 'src/api/merkle_kv.dart';
export 'src/api/exceptions.dart';
export 'src/api/validation.dart';
export 'src/api/config_builder.dart';

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
export 'src/mqtt/connection_lifecycle.dart';
export 'src/mqtt/connection_logger.dart';
export 'src/mqtt/topic_validator.dart';

// Battery Management
export 'src/battery/battery_state.dart';
export 'src/battery/battery_monitor.dart';
export 'src/battery/battery_aware_reconnect_policy.dart';

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
export 'src/replication/event_publisher.dart';
export 'src/replication/event_applicator.dart';
export 'src/replication/metrics.dart';
export 'src/replication/lww_resolver.dart';

// Anti-Entropy Protocol
export 'src/anti_entropy/sync_protocol.dart';

// Merkle Tree
export 'src/merkle/merkle_tree.dart';

// Utilities
export 'src/utils/uuid_generator.dart';
