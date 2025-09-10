import 'dart:convert';
import 'dart:typed_data';
import 'package:cbor/cbor.dart';

/// Replication event representing a change in the distributed key-value store
class ReplicationEvent {
  final String key;
  final String? value; // null for tombstones
  final int timestamp_ms; // standardized field name
  final String node_id;
  final int seq;
  final bool tombstone;

  const ReplicationEvent({
    required this.key,
    this.value,
    required this.timestamp_ms,
    required this.node_id,
    required this.seq,
    required this.tombstone,
  });

  /// Creates a replication event for a value change
  ReplicationEvent.setValue({
    required String key,
    required String value,
    required int timestamp_ms,
    required String node_id,
    required int seq,
  }) : this(
          key: key,
          value: value,
          timestamp_ms: timestamp_ms,
          node_id: node_id,
          seq: seq,
          tombstone: false,
        );

  /// Creates a replication event for a tombstone (deletion)
  ReplicationEvent.setTombstone({
    required String key,
    required int timestamp_ms,
    required String node_id,
    required int seq,
  }) : this(
          key: key,
          value: null,
          timestamp_ms: timestamp_ms,
          node_id: node_id,
          seq: seq,
          tombstone: true,
        );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplicationEvent &&
          runtimeType == other.runtimeType &&
          key == other.key &&
          value == other.value &&
          timestamp_ms == other.timestamp_ms &&
          node_id == other.node_id &&
          seq == other.seq &&
          tombstone == other.tombstone;

  @override
  int get hashCode =>
      key.hashCode ^
      value.hashCode ^
      timestamp_ms.hashCode ^
      node_id.hashCode ^
      seq.hashCode ^
      tombstone.hashCode;

  @override
  String toString() {
    return 'ReplicationEvent{'
        'key: $key, '
        'value: $value, '
        'timestamp_ms: $timestamp_ms, '
        'node_id: $node_id, '
        'seq: $seq, '
        'tombstone: $tombstone'
        '}';
  }
}

/// CBOR serializer for replication events with deterministic encoding
class ReplicationCbor {
  static const int maxPayloadBytes = 300 * 1024; // 300 KiB
  static const int maxKeyBytes = 256; // UTF-8 bytes
  static const int maxValueBytes = 256 * 1024; // 256 KiB UTF-8 bytes
  static const int maxNodeIdLength = 128; // characters

  /// Encodes a replication event to CBOR with deterministic field ordering
  static Uint8List encode(ReplicationEvent event) {
    validateEvent(event);

    // Build map with deterministic insertion order:
    // "key", "node_id", "seq", "timestamp_ms", "tombstone", "value" (if not tombstone)
    final map = <String, dynamic>{};
    map['key'] = event.key;
    map['node_id'] = event.node_id;
    map['seq'] = event.seq;
    map['timestamp_ms'] = event.timestamp_ms;
    map['tombstone'] = event.tombstone;
    
    // Only include value field if not a tombstone
    if (!event.tombstone) {
      map['value'] = event.value;
    }

    final encoded = cbor.encode(CborMap(map));
    
    // Enforce final payload size limit
    if (encoded.length > maxPayloadBytes) {
      throw ReplicationSerializationError(
        ReplicationSerializationErrorCode.payloadTooLarge,
        'CBOR payload size ${encoded.length} exceeds limit of $maxPayloadBytes bytes',
      );
    }
    
    return encoded;
  }

  /// Decodes CBOR bytes to a replication event
  static ReplicationEvent decode(Uint8List bytes) {
    if (bytes.length > maxPayloadBytes) {
      throw ReplicationSerializationError(
        ReplicationSerializationErrorCode.payloadTooLarge,
        'CBOR payload size ${bytes.length} exceeds limit of $maxPayloadBytes bytes',
      );
    }

    late final CborValue decoded;
    try {
      decoded = cbor.decode(bytes);
    } catch (e) {
      throw ReplicationSerializationError(
        ReplicationSerializationErrorCode.malformedCbor,
        'Failed to decode CBOR: $e',
      );
    }

    if (decoded is! CborMap) {
      throw ReplicationSerializationError(
        ReplicationSerializationErrorCode.schemaViolation,
        'Expected CBOR map, got ${decoded.runtimeType}',
      );
    }

    final map = decoded.toObject() as Map<String, dynamic>;

    // Validate required fields
    final requiredFields = ['key', 'node_id', 'seq', 'timestamp_ms', 'tombstone'];
    for (final field in requiredFields) {
      if (!map.containsKey(field)) {
        throw ReplicationSerializationError(
          ReplicationSerializationErrorCode.schemaViolation,
          'Missing required field: $field',
        );
      }
    }

    // Validate field types
    if (map['key'] is! String) {
      throw ReplicationSerializationError(
        ReplicationSerializationErrorCode.schemaViolation,
        'Field "key" must be a string, got ${map['key'].runtimeType}',
      );
    }
    if (map['node_id'] is! String) {
      throw ReplicationSerializationError(
        ReplicationSerializationErrorCode.schemaViolation,
        'Field "node_id" must be a string, got ${map['node_id'].runtimeType}',
      );
    }
    if (map['seq'] is! int) {
      throw ReplicationSerializationError(
        ReplicationSerializationErrorCode.schemaViolation,
        'Field "seq" must be an integer, got ${map['seq'].runtimeType}',
      );
    }
    if (map['timestamp_ms'] is! int) {
      throw ReplicationSerializationError(
        ReplicationSerializationErrorCode.schemaViolation,
        'Field "timestamp_ms" must be an integer, got ${map['timestamp_ms'].runtimeType}',
      );
    }
    if (map['tombstone'] is! bool) {
      throw ReplicationSerializationError(
        ReplicationSerializationErrorCode.schemaViolation,
        'Field "tombstone" must be a boolean, got ${map['tombstone'].runtimeType}',
      );
    }

    final tombstone = map['tombstone'] as bool;
    String? value;

    // Validate value field based on tombstone status
    if (tombstone) {
      if (map.containsKey('value')) {
        throw ReplicationSerializationError(
          ReplicationSerializationErrorCode.schemaViolation,
          'Tombstone events must not contain a "value" field',
        );
      }
      value = null;
    } else {
      if (!map.containsKey('value')) {
        throw ReplicationSerializationError(
          ReplicationSerializationErrorCode.schemaViolation,
          'Non-tombstone events must contain a "value" field',
        );
      }
      if (map['value'] is! String) {
        throw ReplicationSerializationError(
          ReplicationSerializationErrorCode.schemaViolation,
          'Field "value" must be a string, got ${map['value'].runtimeType}',
        );
      }
      value = map['value'] as String;
    }

    final event = ReplicationEvent(
      key: map['key'] as String,
      value: value,
      timestamp_ms: map['timestamp_ms'] as int,
      node_id: map['node_id'] as String,
      seq: map['seq'] as int,
      tombstone: tombstone,
    );

    // Validate the reconstructed event
    validateEvent(event);

    return event;
  }

  /// Validates a replication event according to schema rules
  static void validateEvent(ReplicationEvent event) {
    // Key validation
    if (event.key.isEmpty) {
      throw ReplicationSerializationError(
        ReplicationSerializationErrorCode.schemaViolation,
        'Key cannot be empty',
      );
    }
    
    final keyBytes = utf8.encode(event.key);
    if (keyBytes.length > maxKeyBytes) {
      throw ReplicationSerializationError(
        ReplicationSerializationErrorCode.schemaViolation,
        'Key UTF-8 size ${keyBytes.length} exceeds limit of $maxKeyBytes bytes',
      );
    }

    // Node ID validation
    if (event.node_id.isEmpty) {
      throw ReplicationSerializationError(
        ReplicationSerializationErrorCode.schemaViolation,
        'Node ID cannot be empty',
      );
    }
    if (event.node_id.length > maxNodeIdLength) {
      throw ReplicationSerializationError(
        ReplicationSerializationErrorCode.schemaViolation,
        'Node ID length ${event.node_id.length} exceeds limit of $maxNodeIdLength characters',
      );
    }

    // Sequence and timestamp validation
    if (event.seq < 0) {
      throw ReplicationSerializationError(
        ReplicationSerializationErrorCode.schemaViolation,
        'Sequence number must be non-negative, got ${event.seq}',
      );
    }
    if (event.timestamp_ms < 0) {
      throw ReplicationSerializationError(
        ReplicationSerializationErrorCode.schemaViolation,
        'Timestamp must be non-negative, got ${event.timestamp_ms}',
      );
    }

    // Value validation based on tombstone status
    if (event.tombstone) {
      if (event.value != null) {
        throw ReplicationSerializationError(
          ReplicationSerializationErrorCode.schemaViolation,
          'Tombstone events must have null value',
        );
      }
    } else {
      if (event.value == null) {
        throw ReplicationSerializationError(
          ReplicationSerializationErrorCode.schemaViolation,
          'Non-tombstone events must have non-null value',
        );
      }
      
      final valueBytes = utf8.encode(event.value!);
      if (valueBytes.length > maxValueBytes) {
        throw ReplicationSerializationError(
          ReplicationSerializationErrorCode.schemaViolation,
          'Value UTF-8 size ${valueBytes.length} exceeds limit of $maxValueBytes bytes',
        );
      }
    }
  }
}

/// Error thrown during replication event serialization
class ReplicationSerializationError implements Exception {
  final ReplicationSerializationErrorCode code;
  final String message;

  const ReplicationSerializationError(this.code, this.message);

  @override
  String toString() => 'ReplicationSerializationError: $message (code: $code)';
}

/// Error codes for replication serialization failures
enum ReplicationSerializationErrorCode {
  /// CBOR data is malformed or cannot be parsed
  malformedCbor,
  
  /// Event violates the expected schema or validation rules
  schemaViolation,
  
  /// Payload size exceeds the maximum allowed limit
  payloadTooLarge,
}
