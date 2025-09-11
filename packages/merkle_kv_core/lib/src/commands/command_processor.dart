import 'dart:convert';

import '../config/merkle_kv_config.dart';
import '../storage/storage_interface.dart';
import '../storage/storage_entry.dart';
import '../utils/numeric_operations.dart';
import '../utils/string_operations.dart';
import 'command.dart';
import 'response.dart';

/// Abstract command processor interface per Locked Spec §4.1–§4.4.
///
/// Handles core command processing with validation, version vectors,
/// and idempotency management.
abstract class CommandProcessor {
  /// Processes a command and returns a response.
  Future<Response> processCommand(Command command);

  /// Retrieves a value by key.
  Future<Response> get(String key, String id);

  /// Stores a key-value pair.
  Future<Response> set(String key, String value, String id);

  /// Deletes a key (always returns OK - idempotent).
  Future<Response> delete(String key, String id);

  /// Increments a numeric value by the specified amount.
  Future<Response> increment(String key, int amount, String id);

  /// Decrements a numeric value by the specified amount.
  Future<Response> decrement(String key, int amount, String id);

  /// Appends a value to the end of existing string.   
  Future<Response> append(String key, String value, String id);

  /// Prepends a value to the beginning of existing string. 
  Future<Response> prepend(String key, String value, String id);
}

/// Cache entry for idempotent request handling.
class _CacheEntry {
  final Response response;
  final DateTime expiry;

  _CacheEntry(this.response, this.expiry);

  bool get isExpired => DateTime.now().isAfter(expiry);
}

/// Command processor implementation following Locked Spec §4.1–§4.4.
///
/// Features:
/// - UTF-8 size validation per §11 (keys ≤256B, values ≤256KiB)
/// - Version vector generation with node-local sequence numbers
/// - Last-Write-Wins conflict resolution in storage layer
/// - Idempotency cache with TTL and LRU eviction
/// - Thread-safe sequence number management
class CommandProcessorImpl implements CommandProcessor {
  static const int _maxKeyBytes = 256;
  static const int _maxValueBytes = 256 * 1024; // 256 KiB
  static const Duration _cacheTimeout = Duration(minutes: 10);
  static const int _maxCacheSize = 1000;

  final MerkleKVConfig _config;
  final StorageInterface _storage;
  final Map<String, _CacheEntry> _idempotencyCache = {};
  final List<String> _cacheAccessOrder = [];
  int _sequenceNumber = 0;

  CommandProcessorImpl(this._config, this._storage);

  @override
  Future<Response> processCommand(Command command) async {
    // Check idempotency cache first
    if (command.id.isNotEmpty) {
      final cachedResponse = _getCachedResponse(command.id);
      if (cachedResponse != null) {
        return cachedResponse;
      }
    }

    Response response;
    try {
      switch (command.op.toUpperCase()) {
        case 'GET':
          if (command.key == null) {
            response = Response.invalidRequest(
              command.id,
              'Missing key for GET operation',
            );
          } else {
            response = await get(command.key!, command.id);
          }
          break;
        case 'SET':
          if (command.key == null) {
            response = Response.invalidRequest(
              command.id,
              'Missing key for SET operation',
            );
          } else if (command.value == null) {
            response = Response.invalidRequest(
              command.id,
              'Missing value for SET operation',
            );
          } else {
            response = await set(command.key!, command.value.toString(), command.id);
          }
          break;
        case 'DEL':
        case 'DELETE':
          if (command.key == null) {
            response = Response.invalidRequest(
              command.id,
              'Missing key for DELETE operation',
            );
          } else {
            response = await delete(command.key!, command.id);
          }
          break;
        case 'INCR':
          if (command.key == null) {
            response = Response.invalidRequest(
              command.id,
              'Missing key for INCR operation',
            );
          } else {
            final amount = command.amount ?? 1;
            if (!NumericOperations.isValidAmount(amount)) {
              response = Response.invalidRequest(
                command.id,
                'Amount must be in range [-9e15, 9e15], got: $amount',
              );
            } else {
              response = await increment(command.key!, amount, command.id);
            }
          }
          break;
        case 'DECR':
          if (command.key == null) {
            response = Response.invalidRequest(
              command.id,
              'Missing key for DECR operation',
            );
          } else {
            final amount = command.amount ?? 1;
            if (!NumericOperations.isValidAmount(amount)) {
              response = Response.invalidRequest(
                command.id,
                'Amount must be in range [-9e15, 9e15], got: $amount',
              );
            } else {
              response = await decrement(command.key!, amount, command.id);
            }
          }
          break;
        case 'APPEND':  
          if (command.key == null) {
            response = Response.invalidRequest(
                command.id, 'Missing key for APPEND operation');
          } else if (command.value == null) {
            response = Response.invalidRequest(
                command.id, 'Missing value for APPEND operation');
          } else {
            response = await append(command.key!, command.value.toString(), command.id);
          }
          break;
        case 'PREPEND':  
          if (command.key == null) {
            response = Response.invalidRequest(
                command.id, 'Missing key for PREPEND operation');
          } else if (command.value == null) {
            response = Response.invalidRequest(
                command.id, 'Missing value for PREPEND operation');
          } else {
            response = await prepend(command.key!, command.value.toString(), command.id);
          }
          break;
        default:
          response = Response.invalidRequest(
            command.id,
            'Unsupported operation: ${command.op}',
          );
      }
    } catch (e) {
      response = Response.internalError(command.id, 'Internal error: $e');
    }

    // Update response ID to match command ID
    response = Response(
      id: command.id,
      status: response.status,
      value: response.value,
      error: response.error,
      errorCode: response.errorCode,
      metadata: response.metadata,
    );

    // Cache successful responses
    if (command.id.isNotEmpty && response.isSuccess) {
      _cacheResponse(command.id, response);
    }

    return response;
  }

  @override
  Future<Response> get(String key, String id) async {
    final keyBytes = utf8.encode(key);
    if (keyBytes.length > _maxKeyBytes) {
      return Response.payloadTooLarge(id);
    }

    try {
      final entry = await _storage.get(key);
      if (entry == null || entry.isTombstone) {
        return Response.notFound(id);
      }
      return Response.ok(id: id, value: entry.value);
    } catch (e) {
      return Response.internalError(id, 'Storage error: $e');
    }
  }

  @override
  Future<Response> set(String key, String value, String id) async {
    final keyBytes = utf8.encode(key);
    if (keyBytes.length > _maxKeyBytes) {
      return Response.payloadTooLarge(id);
    }

    final valueBytes = utf8.encode(value);
    if (valueBytes.length > _maxValueBytes) {
      return Response.payloadTooLarge(id);
    }

    try {
      final timestampMs = DateTime.now().millisecondsSinceEpoch;
      final seq = _nextSequenceNumber();

      final entry = StorageEntry.value(
        key: key,
        value: value,
        timestampMs: timestampMs,
        nodeId: _config.nodeId,
        seq: seq,
      );

      await _storage.put(key, entry);
      return Response.ok(id: id);
    } catch (e) {
      return Response.internalError(id, 'Storage error: $e');
    }
  }

  @override
  Future<Response> delete(String key, String id) async {
    final keyBytes = utf8.encode(key);
    if (keyBytes.length > _maxKeyBytes) {
      return Response.payloadTooLarge(id);
    }

    try {
      final timestampMs = DateTime.now().millisecondsSinceEpoch;
      final seq = _nextSequenceNumber();

      await _storage.delete(key, timestampMs, _config.nodeId, seq);
      return Response.ok(id: id);
    } catch (e) {
      return Response.internalError(id, 'Storage error: $e');
    }
  }

  @override
  Future<Response> increment(String key, int amount, String id) async {
    return await _performNumericOperation(key, amount, true, id);
  }

  @override
  Future<Response> decrement(String key, int amount, String id) async {
    return await _performNumericOperation(key, amount, false, id);
  }

  @override
  Future<Response> append(String key, String value, String id) async {
    return await _performStringOperation(key, value, true, id);
  }

  @override
  Future<Response> prepend(String key, String value, String id) async {
    return await _performStringOperation(key, value, false, id);
  }

  Future<Response> _performNumericOperation(
    String key,
    int amount,
    bool isIncrement,
    String id,
  ) async {
    try {
      final keyBytes = utf8.encode(key);
      if (keyBytes.length > _maxKeyBytes) {
        return Response.payloadTooLarge(id);
      }

      final current = await _storage.get(key);
      int currentInt = 0;

      if (current != null && !current.isTombstone) {
        final parsed = NumericOperations.parseInteger(current.value);
        if (parsed == null) {
          return Response.invalidType(
            id,
            'Value is not a valid integer: ${current.value}',
          );
        }
        currentInt = parsed;
      }

      final int newValue;
      try {
        if (isIncrement) {
          newValue = NumericOperations.safeIncrement(currentInt, amount);
        } else {
          newValue = NumericOperations.safeDecrement(currentInt, amount);
        }
      } on NumericOverflowException catch (e) {
        return Response.rangeOverflow(id, e.message);
      }

      final canonicalValue = NumericOperations.formatCanonical(newValue);

      final entry = StorageEntry.value(
        key: key,
        value: canonicalValue,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        nodeId: _config.nodeId,
        seq: _nextSequenceNumber(),
      );

      await _storage.put(key, entry);

      return Response.ok(id: id, value: canonicalValue);
    } catch (e) {
      return Response.internalError(id, 'Numeric operation failed: $e');
    }
  }

  Future<Response> _performStringOperation(
    String key,
    String value,
    bool isAppend,
    String requestId,
  ) async {
    try {
      // Validate key size
      final keyBytes = utf8.encode(key);
      if (keyBytes.length > _maxKeyBytes) {
        return Response.payloadTooLarge(requestId);
      }

      // Validate input value is valid UTF-8
      if (!StringOperations.isValidUtf8String(value)) {
        return Response.invalidRequest(requestId, 'Invalid UTF-8 in value parameter');
      }

      // Get current value
      final current = await _storage.get(key);
      String? existingValue;

      if (current != null && !current.isTombstone) {
        existingValue = current.value;
      }
      // If key doesn't exist or is tombstone, treat as empty string (per §4.6)

      // Perform safe concatenation
      final String? result;
      if (isAppend) {
        result = StringOperations.safeAppend(existingValue, value);
      } else {
        result = StringOperations.safePrepend(value, existingValue);
      }

      if (result == null) {
        // Would exceed size limit
        return Response.payloadTooLarge(requestId);
      }

      // Create new storage entry with version vector
      final entry = StorageEntry.value(
        key: key,
        value: result,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        nodeId: _config.nodeId,
        seq: _nextSequenceNumber(),
      );

      // Store the new value
      await _storage.put(key, entry);

      return Response.ok(id: requestId, value: result);
    } catch (e) {
      return Response.internalError(requestId, 'String operation failed: $e');
    }
  }


  int _nextSequenceNumber() {
    return ++_sequenceNumber;
  }

  Response? _getCachedResponse(String requestId) {
    _cleanupExpiredEntries();

    final entry = _idempotencyCache[requestId];
    if (entry != null && !entry.isExpired) {
      _cacheAccessOrder.remove(requestId);
      _cacheAccessOrder.add(requestId);
      return entry.response;
    }

    if (entry != null) {
      _idempotencyCache.remove(requestId);
      _cacheAccessOrder.remove(requestId);
    }

    return null;
  }

  void _cacheResponse(String requestId, Response response) {
    final expiry = DateTime.now().add(_cacheTimeout);
    _idempotencyCache[requestId] = _CacheEntry(response, expiry);

    _cacheAccessOrder.remove(requestId);
    _cacheAccessOrder.add(requestId);

    while (_idempotencyCache.length > _maxCacheSize) {
      final oldestKey = _cacheAccessOrder.removeAt(0);
      _idempotencyCache.remove(oldestKey);
    }
  }

  void _cleanupExpiredEntries() {
    final now = DateTime.now();
    final expiredKeys = <String>[];

    for (final entry in _idempotencyCache.entries) {
      if (entry.value.expiry.isBefore(now)) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      _idempotencyCache.remove(key);
      _cacheAccessOrder.remove(key);
    }
  }
}
