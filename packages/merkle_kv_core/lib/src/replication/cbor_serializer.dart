// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:typed_data';

import 'package:cbor/cbor.dart';

/// Maximum CBOR payload size (300 KiB) as per Locked Spec §11
const int _maxCborPayloadSize = 300 * 1024; // 300 KiB

/// Error code for payload too large, matching existing codebase pattern
const int _payloadTooLargeErrorCode = 103;

/// Exception thrown when CBOR serialization/deserialization fails
class CborValidationException implements Exception {
  const CborValidationException(this.message);

  final String message;

  @override
  String toString() => 'CborValidationException: $message';
}

/// Exception thrown when payload exceeds size limits
class CborPayloadTooLargeException implements Exception {
  const CborPayloadTooLargeException(this.message,
      [this.errorCode = _payloadTooLargeErrorCode]);

  final String message;
  final int errorCode;

  @override
  String toString() => 'CborPayloadTooLargeException: $message (code: $errorCode)';
}

/// Replication event model as per Locked Spec §3.3
///
/// Schema:
/// {
///   "key":           <string>,           // required, UTF-8
///   "node_id":       <string>,           // required
///   "seq":           <int>,              // required (int64 range)
///   "timestamp_ms":  <int>,              // required (int64 UTC ms)
///   "tombstone":     <bool>,             // required
///   "value":         <string>            // present ONLY if tombstone=false; omit otherwise
/// }
class ReplicationEvent {
  const ReplicationEvent({
    required this.key,
    required this.nodeId,
    required this.seq,
    required this.timestampMs,
    required this.tombstone,
    this.value,
  });

  /// Creates a value-bearing replication event
  const ReplicationEvent.value({
    required this.key,
    required this.nodeId,
    required this.seq,
    required this.timestampMs,
    required this.value,
  }) : tombstone = false;

  /// Creates a tombstone (delete) replication event
  const ReplicationEvent.tombstone({
    required this.key,
    required this.nodeId,
    required this.seq,
    required this.timestampMs,
  })  : value = null,
        tombstone = true;

  final String key;
  final String nodeId;
  final int seq;
  final int timestampMs;
  final bool tombstone;
  final String? value;

  /// Create from JSON map
  factory ReplicationEvent.fromJson(Map<String, dynamic> json) {
    // Validate required fields
    final key = json['key'];
    final nodeId = json['node_id'];
    final seq = json['seq'];
    final timestampMs = json['timestamp_ms'];
    final tombstone = json['tombstone'];

    if (key == null) {
      throw const CborValidationException('Missing required field: key');
    }
    if (nodeId == null) {
      throw const CborValidationException('Missing required field: node_id');
    }
    if (seq == null) {
      throw const CborValidationException('Missing required field: seq');
    }
    if (timestampMs == null) {
      throw const CborValidationException(
          'Missing required field: timestamp_ms');
    }
    if (tombstone == null) {
      throw const CborValidationException('Missing required field: tombstone');
    }

    // Type validation
    if (key is! String) {
      throw const CborValidationException('Field "key" must be a string');
    }
    if (nodeId is! String) {
      throw const CborValidationException('Field "node_id" must be a string');
    }
    if (seq is! int) {
      throw const CborValidationException('Field "seq" must be an integer');
    }
    if (timestampMs is! int) {
      throw const CborValidationException(
          'Field "timestamp_ms" must be an integer');
    }
    if (tombstone is! bool) {
      throw const CborValidationException(
          'Field "tombstone" must be a boolean');
    }

    // Validate tombstone/value consistency
    final value = json['value'];
    if (tombstone == true && value != null) {
      throw const CborValidationException(
          'Value field must be omitted when tombstone=true');
    }
    if (tombstone == false && value != null && value is! String) {
      throw const CborValidationException(
          'Field "value" must be a string when present');
    }

    return ReplicationEvent(
      key: key,
      nodeId: nodeId,
      seq: seq,
      timestampMs: timestampMs,
      tombstone: tombstone,
      value: value as String?,
    );
  }

  /// Convert to JSON map with deterministic key ordering
  Map<String, dynamic> toJson() {
    // Use LinkedHashMap to maintain insertion order for deterministic encoding
    final map = <String, dynamic>{
      'key': key,
      'node_id': nodeId,
      'seq': seq,
      'timestamp_ms': timestampMs,
      'tombstone': tombstone,
    };

    // Only include value if not a tombstone
    if (!tombstone && value != null) {
      map['value'] = value;
    }

    return map;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReplicationEvent &&
        other.key == key &&
        other.nodeId == nodeId &&
        other.seq == seq &&
        other.timestampMs == timestampMs &&
        other.tombstone == tombstone &&
        other.value == value;
  }

  @override
  int get hashCode {
    return Object.hash(key, nodeId, seq, timestampMs, tombstone, value);
  }

  @override
  String toString() {
    return 'ReplicationEvent(key: $key, nodeId: $nodeId, seq: $seq, '
        'timestampMs: $timestampMs, tombstone: $tombstone, value: $value)';
  }
}

/// CBOR serializer for replication events with deterministic encoding
class CborSerializer {
  const CborSerializer._();

  /// Encode a replication event to CBOR bytes with deterministic ordering
  ///
  /// Throws [CborPayloadTooLargeException] if encoded size exceeds 300 KiB
  static Uint8List encode(ReplicationEvent event) {
    // Create deterministic map with stable key order
    final map = _createDeterministicMap(event);

    // Encode to CBOR
    final encoded = cbor.encode(CborMap(map));

    // Check size limit and return as Uint8List
    if (encoded.length > _maxCborPayloadSize) {
      throw CborPayloadTooLargeException(
        'CBOR payload size ${encoded.length} exceeds limit of $_maxCborPayloadSize bytes',
      );
    }

    return Uint8List.fromList(encoded);
  }

  /// Decode CBOR bytes to a replication event
  ///
  /// Throws [CborValidationException] for invalid CBOR or schema violations
  /// Throws [CborPayloadTooLargeException] if payload exceeds size limits
  static ReplicationEvent decode(Uint8List bytes) {
    // Check size limit
    if (bytes.length > _maxCborPayloadSize) {
      throw CborPayloadTooLargeException(
        'CBOR payload size ${bytes.length} exceeds limit of $_maxCborPayloadSize bytes',
      );
    }

    try {
      final decoded = cbor.decode(bytes);

      if (decoded is! CborMap) {
        throw const CborValidationException('CBOR payload must be a map');
      }

      // Convert CBOR map to Dart map
      final map = <String, dynamic>{};
      for (final entry in decoded.entries) {
        if (entry.key is! CborString) {
          throw const CborValidationException('All map keys must be strings');
        }
        final key = (entry.key as CborString).toString();
        final value = _convertCborValue(entry.value);
        map[key] = value;
      }

      return ReplicationEvent.fromJson(map);
    } on FormatException catch (e) {
      throw CborValidationException('Invalid CBOR data: ${e.toString()}');
    } catch (e) {
      if (e is CborValidationException || e is CborPayloadTooLargeException) {
        rethrow;
      }
      throw CborValidationException('Failed to decode CBOR: $e');
    }
  }

  /// Create a deterministic map with stable key ordering
  static Map<CborString, CborValue> _createDeterministicMap(
      ReplicationEvent event) {
    final map = <CborString, CborValue>{};

    // Add fields in canonical order: key, node_id, seq, timestamp_ms, tombstone, value
    map[CborString('key')] = CborString(event.key);
    map[CborString('node_id')] = CborString(event.nodeId);
    map[CborString('seq')] = CborInt(BigInt.from(event.seq));
    map[CborString('timestamp_ms')] = CborInt(BigInt.from(event.timestampMs));
    map[CborString('tombstone')] = CborBool(event.tombstone);

    // Only include value if not a tombstone
    if (!event.tombstone && event.value != null) {
      map[CborString('value')] = CborString(event.value!);
    }

    return map;
  }

  /// Convert CBOR value to Dart value
  static dynamic _convertCborValue(CborValue cborValue) {
    if (cborValue is CborString) {
      return cborValue.toString();
    } else if (cborValue is CborInt) {
      return cborValue.toInt();
    } else if (cborValue is CborBool) {
      return cborValue.value;
    } else if (cborValue is CborNull) {
      return null;
    } else {
      throw CborValidationException(
          'Unsupported CBOR value type: ${cborValue.runtimeType}');
    }
  }
}
