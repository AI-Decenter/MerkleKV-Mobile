import 'dart:convert';

import '../config/merkle_kv_config.dart';
import '../storage/storage_interface.dart';
import '../storage/storage_entry.dart';
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
  Future<Response> get(String key);

  /// Stores a key-value pair.
  Future<Response> set(String key, String value);

  /// Deletes a key (always returns OK - idempotent).
  Future<Response> delete(String key);
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
                command.id, 'Missing key for GET operation');
          } else {
            response = await get(command.key!);
          }
          break;
        case 'SET':
          if (command.key == null) {
            response = Response.invalidRequest(
                command.id, 'Missing key for SET operation');
          } else if (command.value == null) {
            response = Response.invalidRequest(
                command.id, 'Missing value for SET operation');
          } else {
            response = await set(command.key!, command.value.toString());
          }
          break;
        case 'DEL':
        case 'DELETE':
          if (command.key == null) {
            response = Response.invalidRequest(
                command.id, 'Missing key for DELETE operation');
          } else {
            response = await delete(command.key!);
          }
          break;
        default:
          response = Response.invalidRequest(
              command.id, 'Unsupported operation: ${command.op}');
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
  Future<Response> get(String key) async {
    // Validate key size
    final keyBytes = utf8.encode(key);
    if (keyBytes.length > _maxKeyBytes) {
      return Response.payloadTooLarge('');
    }

    try {
      final entry = await _storage.get(key);
      if (entry == null || entry.isTombstone) {
        return Response.notFound('');
      }
      return Response.ok(id: '', value: entry.value);
    } catch (e) {
      return Response.internalError('', 'Storage error: $e');
    }
  }

  @override
  Future<Response> set(String key, String value) async {
    // Validate key size
    final keyBytes = utf8.encode(key);
    if (keyBytes.length > _maxKeyBytes) {
      return Response.payloadTooLarge('');
    }

    // Validate value size
    final valueBytes = utf8.encode(value);
    if (valueBytes.length > _maxValueBytes) {
      return Response.payloadTooLarge('');
    }

    try {
      // Generate version vector
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
      return Response.ok(id: '');
    } catch (e) {
      return Response.internalError('', 'Storage error: $e');
    }
  }

  @override
  Future<Response> delete(String key) async {
    // Validate key size
    final keyBytes = utf8.encode(key);
    if (keyBytes.length > _maxKeyBytes) {
      return Response.payloadTooLarge('');
    }

    try {
      // Generate version vector for tombstone
      final timestampMs = DateTime.now().millisecondsSinceEpoch;
      final seq = _nextSequenceNumber();

      await _storage.delete(key, timestampMs, _config.nodeId, seq);
      return Response.ok(id: '');
    } catch (e) {
      return Response.internalError('', 'Storage error: $e');
    }
  }

  /// Gets next sequence number in a thread-safe manner.
  int _nextSequenceNumber() {
    return ++_sequenceNumber;
  }

  /// Retrieves cached response if available and not expired.
  Response? _getCachedResponse(String requestId) {
    _cleanupExpiredEntries();

    final entry = _idempotencyCache[requestId];
    if (entry != null && !entry.isExpired) {
      // Move to end of access order (LRU)
      _cacheAccessOrder.remove(requestId);
      _cacheAccessOrder.add(requestId);
      return entry.response;
    }

    // Remove expired entry
    if (entry != null) {
      _idempotencyCache.remove(requestId);
      _cacheAccessOrder.remove(requestId);
    }

    return null;
  }

  /// Caches a response with TTL and LRU eviction.
  void _cacheResponse(String requestId, Response response) {
    final expiry = DateTime.now().add(_cacheTimeout);
    _idempotencyCache[requestId] = _CacheEntry(response, expiry);

    // Update access order
    _cacheAccessOrder.remove(requestId);
    _cacheAccessOrder.add(requestId);

    // Enforce cache size limit with LRU eviction
    while (_idempotencyCache.length > _maxCacheSize) {
      final oldestKey = _cacheAccessOrder.removeAt(0);
      _idempotencyCache.remove(oldestKey);
    }
  }

  /// Removes expired cache entries.
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
