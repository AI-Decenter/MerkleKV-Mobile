/// MerkleKV Mobile Public API
///
/// This is the main entry point for the MerkleKV Mobile library.
/// Import this file to access the complete public API surface.
///
/// Example usage:
/// ```dart
/// import 'package:merkle_kv_core/merkle_kv.dart';
///
/// final config = MerkleKVConfig.builder()
///   .host('mqtt.example.com')
///   .clientId('mobile-device-1')  
///   .nodeId('device-uuid-123')
///   .enableTls()
///   .build();
///
/// final merkleKV = await MerkleKV.create(config);
/// await merkleKV.connect();
///
/// await merkleKV.set('key', 'value');
/// final value = await merkleKV.get('key');
/// ```
library merkle_kv;

// Export the public API surface
export 'src/api/merkle_kv.dart';
export 'src/api/exceptions.dart';
export 'src/api/validation.dart';
export 'src/api/config_builder.dart';

// Export essential configuration classes
export 'src/config/merkle_kv_config.dart';
export 'src/config/invalid_config_exception.dart';
export 'src/config/default_config.dart';

// Export connection state for reactive monitoring
export 'src/mqtt/connection_state.dart';

// Export battery management for mobile power optimization
export 'src/battery/battery_state.dart';
export 'src/battery/battery_monitor.dart';
export 'src/battery/battery_aware_reconnect_policy.dart';