import 'dart:convert';

import '../utils/numeric_operations.dart';

/// Represents a command to be sent to MerkleKV.
///
/// Commands follow the Locked Spec §3.1 format with required fields:
/// - id: UUIDv4 identifier for request/response correlation
/// - op: Operation type (GET, SET, DEL, etc.)
/// - key: Target key (for single-key operations)
/// - keys: Target keys (for multi-key operations)
/// - value: Value to store (for SET operations)
/// - amount: Numeric amount (for INCR/DECR operations)
class Command {
  /// Unique identifier for request/response correlation (UUIDv4 format)
  final String id;

  /// Operation type (GET, SET, DEL, MGET, MSET, INCR, DECR, SYNC, SYNC_KEYS)
  final String op;

  /// Target key for single-key operations
  final String? key;

  /// Target keys for multi-key operations
  final List<String>? keys;

  /// Value to store (for SET, MSET operations)
  final dynamic value;

  /// Key-value pairs for MSET operation
  final Map<String, dynamic>? keyValues;

  /// Numeric amount for INCR/DECR operations
  final int? amount;

  /// Additional parameters for sync operations
  final Map<String, dynamic>? params;

  const Command({
    required this.id,
    required this.op,
    this.key,
    this.keys,
    this.value,
    this.keyValues,
    this.amount,
    this.params,
  });

  /// Creates a Command from JSON object.
  ///
  /// Validates required fields and throws [FormatException] for invalid format.
  factory Command.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final op = json['op'];

    if (id == null || id is! String) {
      throw const FormatException('Missing or invalid "id" field');
    }

    if (op == null || op is! String) {
      throw const FormatException('Missing or invalid "op" field');
    }

    // Validate key field type
    final key = json['key'];
    if (key != null && key is! String) {
      throw const FormatException('Invalid "key" field - must be string');
    }

    // Validate keys field type
    final keys = json['keys'];
    if (keys != null && keys is! List) {
      throw const FormatException('Invalid "keys" field - must be array');
    }

    // Validate keyValues field type
    final keyValues = json['keyValues'];
    if (keyValues != null && keyValues is! Map) {
      throw const FormatException('Invalid "keyValues" field - must be object');
    }

    // Validate amount field type
    final amount = json['amount'];
    if (amount != null && amount is! int) {
      throw const FormatException('Invalid "amount" field - must be integer');
    }

    try {
      return Command(
        id: id,
        op: op,
        key: key as String?,
        keys: keys?.cast<String>(),
        value: json['value'],
        keyValues: keyValues?.cast<String, dynamic>(),
        amount: amount as int?,
        params: (json['params'] as Map?)?.cast<String, dynamic>(),
      );
    } catch (e) {
      throw FormatException('Invalid field types: $e');
    }
  }

  /// Converts Command to JSON object for serialization.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'id': id, 'op': op};

    if (key != null) json['key'] = key;
    if (keys != null) json['keys'] = keys;
    if (value != null) json['value'] = value;
    if (keyValues != null) json['keyValues'] = keyValues;
    if (amount != null) json['amount'] = amount;
    if (params != null) json['params'] = params;

    return json;
  }

  /// Serializes Command to JSON string.
  String toJsonString() => jsonEncode(toJson());

  /// Creates Command from JSON string.
  ///
  /// Throws [FormatException] for malformed JSON or invalid structure.
  factory Command.fromJsonString(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      return Command.fromJson(decoded);
    } catch (e) {
      throw FormatException('Invalid JSON format: $e');
    }
  }

  /// Returns true if this is a single-key operation.
  bool get isSingleKeyOp => ['GET', 'SET', 'DEL', 'INCR', 'DECR', 'APPEND', 'PREPEND'].contains(op);

  /// Returns true if this is a multi-key operation.
  bool get isMultiKeyOp => ['MGET', 'MSET'].contains(op);

  /// Returns true if this is a sync operation.
  bool get isSyncOp => ['SYNC', 'SYNC_KEYS'].contains(op);

  /// Returns the expected timeout duration for this command type.
  Duration get expectedTimeout {
    if (isSingleKeyOp) {
      return const Duration(seconds: 10); // 10s for single-key ops
    } else if (isMultiKeyOp) {
      return const Duration(seconds: 20); // 20s for multi-key ops
    } else if (isSyncOp) {
      return const Duration(seconds: 30); // 30s for sync ops
    } else {
      return const Duration(seconds: 10); // Default to single-key timeout
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Command &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          op == other.op &&
          key == other.key &&
          _listEquals(keys, other.keys) &&
          value == other.value &&
          _mapEquals(keyValues, other.keyValues) &&
          amount == other.amount &&
          _mapEquals(params, other.params);

  @override
  int get hashCode =>
      id.hashCode ^
      op.hashCode ^
      key.hashCode ^
      _listHashCode(keys) ^
      value.hashCode ^
      _mapHashCode(keyValues) ^
      amount.hashCode ^
      _mapHashCode(params);

  @override
  String toString() => 'Command(id: $id, op: $op, key: $key)';

  // Helper methods for equality comparison
  bool _listEquals(List? a, List? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _mapEquals(Map? a, Map? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }

  int _listHashCode(List? list) {
    if (list == null) return 0;
    int hash = 0;
    for (final item in list) {
      hash ^= item.hashCode;
    }
    return hash;
  }

  int _mapHashCode(Map? map) {
    if (map == null) return 0;
    int hash = 0;
    for (final entry in map.entries) {
      hash ^= entry.key.hashCode ^ entry.value.hashCode;
    }
    return hash;
  }

  // Convenience factory methods
  /// Creates an INCR command with optional amount (default 1).
  factory Command.incr({
    required String id,
    required String key,
    int amount = 1,
  }) {
    if (!NumericOperations.isValidAmount(amount)) {
      throw ArgumentError(
        'Amount must be in range [-9e15, 9e15], got: $amount',
      );
    }
    return Command(id: id, op: 'INCR', key: key, amount: amount);
  }

  /// Creates a DECR command with optional amount (default 1).
  factory Command.decr({
    required String id,
    required String key,
    int amount = 1,
  }) {
    if (!NumericOperations.isValidAmount(amount)) {
      throw ArgumentError(
        'Amount must be in range [-9e15, 9e15], got: $amount',
      );
    }
    return Command(id: id, op: 'DECR', key: key, amount: amount);
  }

  /// Creates an APPEND command.
  factory Command.append({
    required String id,
    required String key,
    required String value,
  }) {
    return Command(
      id: id,
      op: 'APPEND',
      key: key,
      value: value,
    );
  }

  /// Creates a PREPEND command.
  factory Command.prepend({
    required String id,
    required String key,
    required String value,
  }) {
    return Command(
      id: id,
      op: 'PREPEND',
      key: key,
      value: value,
    );
  }

  /// Creates an MGET command.
  factory Command.mget({
    required String id,
    required List<String> keys,
  }) {
    return Command(
      id: id,
      op: 'MGET',
      keys: keys,
    );
  }

  /// Creates an MSET command.
  factory Command.mset({
    required String id,
    required Map<String, dynamic> keyValues,
  }) {
    return Command(
      id: id,
      op: 'MSET',
      keyValues: keyValues,
    );
  }
}
