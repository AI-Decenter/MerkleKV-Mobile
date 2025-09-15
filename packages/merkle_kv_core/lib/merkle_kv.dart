/// Public API surface for MerkleKV Mobile
///
/// Provides clean abstractions for core operations (GET, SET, DEL, INCR/DECR, 
/// APPEND/PREPEND), bulk operations (MGET/MSET), and configuration management.
library merkle_kv;

// Core API
export 'src/merkle_kv_mobile.dart';

// Configuration with builder pattern
export 'src/config/merkle_kv_config.dart';

// Exception hierarchy
export 'src/exceptions/merkle_kv_exception.dart';

// Connection state
export 'src/mqtt/connection_state.dart';

// Key-value result for bulk operations
export 'src/models/key_value_result.dart';