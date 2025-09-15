import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';

import '../storage/storage_interface.dart';
import '../storage/storage_entry.dart';
import '../merkle/merkle_tree.dart';
import '../replication/metrics.dart';
import '../mqtt/mqtt_client_interface.dart';

/// Anti-entropy synchronization error codes per Locked Spec §9
enum SyncErrorCode {
  payloadTooLarge,
  rateLimited,
  timeout,
  invalidRequest,
  unauthorized,
  networkError,
  merkleTreeError,
}

/// Exception thrown during anti-entropy operations
class SyncException implements Exception {
  final SyncErrorCode code;
  final String message;
  final dynamic cause;

  const SyncException(this.code, this.message, [this.cause]);

  @override
  String toString() => 'SyncException(${code.name}): $message${cause != null ? ' (caused by: $cause)' : ''}';
}

/// Result of a synchronization operation
class SyncResult {
  final bool success;
  final String? remoteNodeId;
  final int keysExamined;
  final int keysSynced;
  final int rounds;
  final Duration duration;
  final SyncErrorCode? errorCode;
  final String? errorMessage;

  const SyncResult({
    required this.success,
    this.remoteNodeId,
    required this.keysExamined,
    required this.keysSynced,
    required this.rounds,
    required this.duration,
    this.errorCode,
    this.errorMessage,
  });

  factory SyncResult.success({
    String? remoteNodeId,
    required int keysExamined,
    required int keysSynced,
    required int rounds,
    required Duration duration,
  }) {
    return SyncResult(
      success: true,
      remoteNodeId: remoteNodeId,
      keysExamined: keysExamined,
      keysSynced: keysSynced,
      rounds: rounds,
      duration: duration,
    );
  }

  factory SyncResult.failure({
    String? remoteNodeId,
    required SyncErrorCode errorCode,
    required String errorMessage,
    required Duration duration,
    int keysExamined = 0,
    int keysSynced = 0,
    int rounds = 0,
  }) {
    return SyncResult(
      success: false,
      remoteNodeId: remoteNodeId,
      keysExamined: keysExamined,
      keysSynced: keysSynced,
      rounds: rounds,
      duration: duration,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  @override
  String toString() => 'SyncResult(success: $success, remoteNode: $remoteNodeId, '
      'keysExamined: $keysExamined, keysSynced: $keysSynced, rounds: $rounds, '
      'duration: ${duration.inMilliseconds}ms${!success ? ', error: $errorCode - $errorMessage' : ''})';
}

/// SYNC request for Merkle root hash exchange
class SyncRequest {
  final String requestId;
  final String sourceNodeId;
  final Uint8List rootHash;
  final DateTime timestamp;
  final int timeoutMs;

  const SyncRequest({
    required this.requestId,
    required this.sourceNodeId,
    required this.rootHash,
    required this.timestamp,
    this.timeoutMs = 30000, // 30 second default timeout
  });

  Map<String, dynamic> toMap() {
    return {
      'requestId': requestId,
      'sourceNodeId': sourceNodeId,
      'rootHash': base64.encode(rootHash),
      'timestamp': timestamp.millisecondsSinceEpoch,
      'timeoutMs': timeoutMs,
    };
  }

  factory SyncRequest.fromMap(Map<String, dynamic> map) {
    return SyncRequest(
      requestId: map['requestId'],
      sourceNodeId: map['sourceNodeId'],
      rootHash: base64.decode(map['rootHash']),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      timeoutMs: map['timeoutMs'] ?? 30000,
    );
  }
}

/// SYNC response with comparison result
class SyncResponse {
  final String requestId;
  final String responseNodeId;
  final Uint8List rootHash;
  final bool hashesMatch;
  final List<String>? divergentPaths; // Paths that need SYNC_KEYS
  final DateTime timestamp;

  const SyncResponse({
    required this.requestId,
    required this.responseNodeId,
    required this.rootHash,
    required this.hashesMatch,
    this.divergentPaths,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'requestId': requestId,
      'responseNodeId': responseNodeId,
      'rootHash': base64.encode(rootHash),
      'hashesMatch': hashesMatch,
      'divergentPaths': divergentPaths,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory SyncResponse.fromMap(Map<String, dynamic> map) {
    return SyncResponse(
      requestId: map['requestId'],
      responseNodeId: map['responseNodeId'],
      rootHash: base64.decode(map['rootHash']),
      hashesMatch: map['hashesMatch'],
      divergentPaths: map['divergentPaths']?.cast<String>(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
    );
  }
}

/// SYNC_KEYS request for targeted key-value exchange
class SyncKeysRequest {
  final String requestId;
  final String sourceNodeId;
  final List<String> keys;
  final Map<String, StorageEntry> entries; // Local entries for comparison
  final DateTime timestamp;
  final int timeoutMs;

  const SyncKeysRequest({
    required this.requestId,
    required this.sourceNodeId,
    required this.keys,
    required this.entries,
    required this.timestamp,
    this.timeoutMs = 30000,
  });

  Map<String, dynamic> toMap() {
    return {
      'requestId': requestId,
      'sourceNodeId': sourceNodeId,
      'keys': keys,
      'entries': entries.map((key, entry) => MapEntry(key, entry.toJson())),
      'timestamp': timestamp.millisecondsSinceEpoch,
      'timeoutMs': timeoutMs,
    };
  }

  factory SyncKeysRequest.fromMap(Map<String, dynamic> map) {
    final entriesMap = (map['entries'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, StorageEntry.fromJson(value)),
    );
    
    return SyncKeysRequest(
      requestId: map['requestId'],
      sourceNodeId: map['sourceNodeId'],
      keys: (map['keys'] as List).cast<String>(),
      entries: entriesMap,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      timeoutMs: map['timeoutMs'] ?? 30000,
    );
  }
}

/// SYNC_KEYS response with reconciliation data
class SyncKeysResponse {
  final String requestId;
  final String responseNodeId;
  final Map<String, StorageEntry> entries; // Remote entries for reconciliation
  final List<String> notFoundKeys; // Keys not present on remote node
  final DateTime timestamp;

  const SyncKeysResponse({
    required this.requestId,
    required this.responseNodeId,
    required this.entries,
    required this.notFoundKeys,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'requestId': requestId,
      'responseNodeId': responseNodeId,
      'entries': entries.map((key, entry) => MapEntry(key, entry.toJson())),
      'notFoundKeys': notFoundKeys,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory SyncKeysResponse.fromMap(Map<String, dynamic> map) {
    final entriesMap = (map['entries'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, StorageEntry.fromJson(value)),
    );
    
    return SyncKeysResponse(
      requestId: map['requestId'],
      responseNodeId: map['responseNodeId'],
      entries: entriesMap,
      notFoundKeys: (map['notFoundKeys'] as List).cast<String>(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
    );
  }
}

/// Payload size validator per Locked Spec §9
class PayloadValidator {
  /// Maximum payload size: 512 KiB per Locked Spec §9
  static const int maxPayloadSize = 512 * 1024;

  /// Validate SYNC_KEYS payload size
  static bool validateSyncKeysPayload(List<String> keys, Map<String, StorageEntry> entries) {
    final totalSize = calculateTotalSize(keys, entries);
    return totalSize <= maxPayloadSize;
  }

  /// Calculate total payload size in bytes
  static int calculateTotalSize(List<String> keys, Map<String, StorageEntry> entries) {
    var totalSize = 0;
    
    // Size of keys list
    for (final key in keys) {
      totalSize += utf8.encode(key).length;
    }
    
    // Size of entries map
    for (final entry in entries.values) {
      totalSize += utf8.encode(entry.key).length;
      if (entry.value != null) {
        totalSize += utf8.encode(entry.value!).length;
      }
      totalSize += utf8.encode(entry.nodeId).length;
      totalSize += 8; // timestampMs (int64)
      totalSize += 8; // seq (int64)
      totalSize += 1; // isTombstone flag
    }
    
    // Add JSON/CBOR overhead (estimated 20% overhead)
    totalSize = (totalSize * 1.2).round();
    
    return totalSize;
  }

  /// Validate individual request/response payload
  static void validatePayload(Map<String, dynamic> payload, String operationType) {
    final jsonString = jsonEncode(payload);
    final payloadSize = utf8.encode(jsonString).length;
    
    if (payloadSize > maxPayloadSize) {
      throw SyncException(
        SyncErrorCode.payloadTooLarge,
        '$operationType payload size ($payloadSize bytes) exceeds limit ($maxPayloadSize bytes)',
      );
    }
  }
}

/// Token bucket rate limiter for anti-entropy operations
class RateLimiter {
  final double requestsPerSecond;
  final int bucketCapacity;
  
  double _tokens;
  DateTime _lastRefill;

  RateLimiter({
    this.requestsPerSecond = 5.0, // Default 5 requests/second per issue spec
    int? bucketCapacity,
  }) : bucketCapacity = bucketCapacity ?? (requestsPerSecond * 2).round(),
       _tokens = (bucketCapacity ?? (requestsPerSecond * 2).round()).toDouble(),
       _lastRefill = DateTime.now();

  /// Attempt to consume a token for rate limiting
  bool tryConsume() {
    _refillTokens();
    
    if (_tokens >= 1.0) {
      _tokens -= 1.0;
      return true;
    }
    
    return false;
  }

  /// Get current tokens available
  double get availableTokens {
    _refillTokens();
    return _tokens;
  }

  void _refillTokens() {
    final now = DateTime.now();
    final timeSinceLastRefill = now.difference(_lastRefill).inMilliseconds / 1000.0;
    final tokensToAdd = timeSinceLastRefill * requestsPerSecond;
    
    _tokens = min(bucketCapacity.toDouble(), _tokens + tokensToAdd);
    _lastRefill = now;
  }
}

/// Anti-entropy synchronization protocol interface per Locked Spec §9
abstract class AntiEntropyProtocol {
  /// Perform synchronization with a remote node
  Future<SyncResult> performSync(String remoteNodeId);
  
  /// Handle incoming SYNC request
  Future<void> handleSyncRequest(SyncRequest request);
  
  /// Handle incoming SYNC_KEYS request
  Future<void> handleSyncKeysRequest(SyncKeysRequest request);
  
  /// Configure rate limiting
  void configureRateLimit({double? requestsPerSecond, int? bucketCapacity});
  
  /// Dispose resources
  void dispose();
}

/// Implementation of anti-entropy synchronization protocol per Locked Spec §9
class AntiEntropyProtocolImpl implements AntiEntropyProtocol {
  final StorageInterface _storage;
  final MerkleTree _merkleTree;
  final MqttClientInterface _mqttClient;
  final ReplicationMetrics _metrics;
  final String _nodeId;
  final int _defaultTimeoutMs;
  
  RateLimiter _rateLimiter;
  final Map<String, Completer<SyncResponse>> _pendingSyncRequests = {};
  final Map<String, Completer<SyncKeysResponse>> _pendingSyncKeysRequests = {};

  AntiEntropyProtocolImpl({
    required StorageInterface storage,
    required MerkleTree merkleTree,
    required MqttClientInterface mqttClient,
    required ReplicationMetrics metrics,
    required String nodeId,
    double requestsPerSecond = 5.0,
    int defaultTimeoutMs = 30000,
  }) : _storage = storage,
       _merkleTree = merkleTree,
       _mqttClient = mqttClient,
       _metrics = metrics,
       _nodeId = nodeId,
       _defaultTimeoutMs = defaultTimeoutMs,
       _rateLimiter = RateLimiter(requestsPerSecond: requestsPerSecond) {
    _setupMessageHandling();
  }

  void _setupMessageHandling() {
    // Subscribe to anti-entropy topics
    final syncRequestTopic = 'merkle_kv/$_nodeId/sync/request';
    final syncResponseTopic = 'merkle_kv/$_nodeId/sync/response';
    final syncKeysRequestTopic = 'merkle_kv/$_nodeId/sync_keys/request';
    final syncKeysResponseTopic = 'merkle_kv/$_nodeId/sync_keys/response';

    // Set up message handlers for each topic
    _mqttClient.subscribe(syncRequestTopic, (topic, message) {
      _handleMessage(topic, message);
    });
    _mqttClient.subscribe(syncResponseTopic, (topic, message) {
      _handleMessage(topic, message);
    });
    _mqttClient.subscribe(syncKeysRequestTopic, (topic, message) {
      _handleMessage(topic, message);
    });
    _mqttClient.subscribe(syncKeysResponseTopic, (topic, message) {
      _handleMessage(topic, message);
    });
  }

  void _handleMessage(String topic, String message) {
    try {
      final payload = jsonDecode(message) as Map<String, dynamic>;
      
      if (topic.endsWith('/sync/request')) {
        final request = SyncRequest.fromMap(payload);
        handleSyncRequest(request);
      } else if (topic.endsWith('/sync/response')) {
        final response = SyncResponse.fromMap(payload);
        _handleSyncResponse(response);
      } else if (topic.endsWith('/sync_keys/request')) {
        final request = SyncKeysRequest.fromMap(payload);
        handleSyncKeysRequest(request);
      } else if (topic.endsWith('/sync_keys/response')) {
        final response = SyncKeysResponse.fromMap(payload);
        _handleSyncKeysResponse(response);
      }
    } catch (e) {
      _metrics.incrementAntiEntropyErrors();
      // Log error but don't crash - malformed messages should be ignored
    }
  }

  @override
  Future<SyncResult> performSync(String remoteNodeId) async {
    final stopwatch = Stopwatch()..start();
    var keysExamined = 0;
    var keysSynced = 0;
    var rounds = 0;

    try {
      _metrics.incrementAntiEntropySyncAttempts();

      // Rate limiting check
      if (!_rateLimiter.tryConsume()) {
        _metrics.incrementAntiEntropyRateLimitHits();
        throw SyncException(
          SyncErrorCode.rateLimited,
          'Sync rate limit exceeded (${_rateLimiter.requestsPerSecond} req/sec)',
        );
      }

      // Phase 1: SYNC - Exchange root hashes
      rounds++;
      final localRootHash = await _merkleTree.getRootHash();
      final syncResponse = await _performSyncRequest(remoteNodeId, localRootHash);

      if (syncResponse.hashesMatch) {
        stopwatch.stop();
        _metrics.incrementAntiEntropySyncSuccess();
        _metrics.recordAntiEntropySyncDuration(stopwatch.elapsedMicroseconds);
        
        return SyncResult.success(
          remoteNodeId: remoteNodeId,
          keysExamined: keysExamined,
          keysSynced: keysSynced,
          rounds: rounds,
          duration: stopwatch.elapsed,
        );
      }

      // Phase 2: Identify divergent keys through subtree comparison
      final divergentKeys = await _findDivergentKeys(remoteNodeId, syncResponse.divergentPaths ?? []);
      keysExamined = divergentKeys.length;
      _metrics.recordAntiEntropyDivergentKeysFound(divergentKeys.length);

      if (divergentKeys.isEmpty) {
        stopwatch.stop();
        _metrics.incrementAntiEntropySyncSuccess();
        _metrics.recordAntiEntropySyncDuration(stopwatch.elapsedMicroseconds);
        
        return SyncResult.success(
          remoteNodeId: remoteNodeId,
          keysExamined: keysExamined,
          keysSynced: keysSynced,
          rounds: rounds,
          duration: stopwatch.elapsed,
        );
      }

      // Phase 3: SYNC_KEYS - Exchange and reconcile divergent keys
      rounds++;
      keysSynced = await _performSyncKeysOperation(remoteNodeId, divergentKeys);

      stopwatch.stop();
      _metrics.incrementAntiEntropySyncSuccess();
      _metrics.recordAntiEntropySyncDuration(stopwatch.elapsedMicroseconds);
      _metrics.recordAntiEntropyKeysSynced(keysSynced);
      _metrics.incrementAntiEntropyConvergenceRounds();

      return SyncResult.success(
        remoteNodeId: remoteNodeId,
        keysExamined: keysExamined,
        keysSynced: keysSynced,
        rounds: rounds,
        duration: stopwatch.elapsed,
      );

    } catch (e) {
      stopwatch.stop();
      
      if (e is SyncException) {
        _metrics.recordAntiEntropySyncDuration(stopwatch.elapsedMicroseconds);
        return SyncResult.failure(
          remoteNodeId: remoteNodeId,
          errorCode: e.code,
          errorMessage: e.message,
          duration: stopwatch.elapsed,
          keysExamined: keysExamined,
          keysSynced: keysSynced,
          rounds: rounds,
        );
      } else {
        _metrics.recordAntiEntropySyncDuration(stopwatch.elapsedMicroseconds);
        return SyncResult.failure(
          remoteNodeId: remoteNodeId,
          errorCode: SyncErrorCode.networkError,
          errorMessage: 'Unexpected error during sync: $e',
          duration: stopwatch.elapsed,
          keysExamined: keysExamined,
          keysSynced: keysSynced,
          rounds: rounds,
        );
      }
    }
  }

  Future<SyncResponse> _performSyncRequest(String remoteNodeId, Uint8List localRootHash) async {
    final requestId = _generateRequestId();
    final request = SyncRequest(
      requestId: requestId,
      sourceNodeId: _nodeId,
      rootHash: localRootHash,
      timestamp: DateTime.now(),
      timeoutMs: _defaultTimeoutMs,
    );

    // Validate payload size
    PayloadValidator.validatePayload(request.toMap(), 'SYNC request');

    final completer = Completer<SyncResponse>();
    _pendingSyncRequests[requestId] = completer;

    try {
      // Publish request
      final topic = 'merkle_kv/$remoteNodeId/sync/request';
      await _mqttClient.publish(topic, jsonEncode(request.toMap()));

      // Wait for response with timeout
      final response = await completer.future.timeout(
        Duration(milliseconds: request.timeoutMs),
        onTimeout: () {
          _pendingSyncRequests.remove(requestId);
          throw const SyncException(SyncErrorCode.timeout, 'SYNC request timeout');
        },
      );

      return response;
    } finally {
      _pendingSyncRequests.remove(requestId);
    }
  }

  Future<List<String>> _findDivergentKeys(String remoteNodeId, List<String> paths) async {
    // For this implementation, we'll use a simplified approach:
    // Get all entries and let the SYNC_KEYS operation handle comparison
    final allEntries = await _storage.getAllEntries();
    return allEntries.map((entry) => entry.key).toList();
  }

  Future<int> _performSyncKeysOperation(String remoteNodeId, List<String> divergentKeys) async {
    var totalKeysSynced = 0;
    final batchSize = 50; // Start with reasonable batch size

    // Process keys in batches to respect payload limits
    for (int i = 0; i < divergentKeys.length; i += batchSize) {
      final batch = divergentKeys.skip(i).take(batchSize).toList();
      
      // Get local entries for this batch
      final localEntries = <String, StorageEntry>{};
      for (final key in batch) {
        final entry = await _storage.get(key);
        if (entry != null) {
          localEntries[key] = entry;
        }
      }

      // Validate payload size
      if (!PayloadValidator.validateSyncKeysPayload(batch, localEntries)) {
        // Reduce batch size and retry
        if (batch.length > 1) {
          final smallerBatch = batch.take(batch.length ~/ 2).toList();
          final smallerEntries = <String, StorageEntry>{};
          for (final key in smallerBatch) {
            if (localEntries.containsKey(key)) {
              smallerEntries[key] = localEntries[key]!;
            }
          }
          
          if (PayloadValidator.validateSyncKeysPayload(smallerBatch, smallerEntries)) {
            // Process smaller batch
            final synced = await _performSyncKeysRequest(remoteNodeId, smallerBatch, smallerEntries);
            totalKeysSynced += synced;
            
            // Add remaining keys back to the queue
            divergentKeys.insertAll(i + smallerBatch.length, batch.skip(smallerBatch.length));
            continue;
          }
        }
        
        throw const SyncException(
          SyncErrorCode.payloadTooLarge,
          'Cannot fit SYNC_KEYS payload within 512KiB limit even with single key',
        );
      }

      final synced = await _performSyncKeysRequest(remoteNodeId, batch, localEntries);
      totalKeysSynced += synced;
    }

    return totalKeysSynced;
  }

  Future<int> _performSyncKeysRequest(String remoteNodeId, List<String> keys, Map<String, StorageEntry> localEntries) async {
    final requestId = _generateRequestId();
    final request = SyncKeysRequest(
      requestId: requestId,
      sourceNodeId: _nodeId,
      keys: keys,
      entries: localEntries,
      timestamp: DateTime.now(),
      timeoutMs: _defaultTimeoutMs,
    );

    // Validate payload size
    PayloadValidator.validatePayload(request.toMap(), 'SYNC_KEYS request');
    final payloadSize = PayloadValidator.calculateTotalSize(keys, localEntries);
    _metrics.recordAntiEntropyPayloadSize(payloadSize);

    final completer = Completer<SyncKeysResponse>();
    _pendingSyncKeysRequests[requestId] = completer;

    try {
      // Publish request
      final topic = 'merkle_kv/$remoteNodeId/sync_keys/request';
      await _mqttClient.publish(topic, jsonEncode(request.toMap()));

      // Wait for response with timeout
      final response = await completer.future.timeout(
        Duration(milliseconds: request.timeoutMs),
        onTimeout: () {
          _pendingSyncKeysRequests.remove(requestId);
          throw const SyncException(SyncErrorCode.timeout, 'SYNC_KEYS request timeout');
        },
      );

      // Apply reconciliation (with loop prevention)
      return await _applyReconciliation(response.entries, response.notFoundKeys);
    } finally {
      _pendingSyncKeysRequests.remove(requestId);
    }
  }

  Future<int> _applyReconciliation(Map<String, StorageEntry> remoteEntries, List<String> notFoundKeys) async {
    var keysSynced = 0;

    // Apply remote entries using LWW conflict resolution with loop prevention
    for (final entry in remoteEntries.values) {
      final localEntry = await _storage.get(entry.key);
      
      if (localEntry == null || _shouldUpdateEntry(localEntry, entry)) {
        // Apply update with reconciliation flag to prevent re-publishing
        await _storage.putWithReconciliation(entry.key, entry);
        keysSynced++;
      }
    }

    // Handle keys that don't exist on remote (potential deletes)
    for (final key in notFoundKeys) {
      final localEntry = await _storage.get(key);
      if (localEntry != null && !localEntry.isTombstone) {
        // Remote doesn't have this key - it might have been deleted
        // For now, we keep our local copy (could be configurable)
      }
    }

    return keysSynced;
  }

  bool _shouldUpdateEntry(StorageEntry local, StorageEntry remote) {
    // Use LWW conflict resolution
    if (remote.timestampMs > local.timestampMs) {
      return true;
    } else if (remote.timestampMs == local.timestampMs) {
      // Tie-break with node ID
      return remote.nodeId.compareTo(local.nodeId) > 0;
    }
    return false;
  }

  @override
  Future<void> handleSyncRequest(SyncRequest request) async {
    try {
      final localRootHash = await _merkleTree.getRootHash();
      final hashesMatch = _compareHashes(request.rootHash, localRootHash);
      
      List<String>? divergentPaths;
      if (!hashesMatch) {
        // In a full implementation, this would analyze the Merkle tree structure
        // to identify specific divergent paths. For now, we signal that keys need sync.
        divergentPaths = ['*']; // Indicates all keys may need checking
      }

      final response = SyncResponse(
        requestId: request.requestId,
        responseNodeId: _nodeId,
        rootHash: localRootHash,
        hashesMatch: hashesMatch,
        divergentPaths: divergentPaths,
        timestamp: DateTime.now(),
      );

      // Validate payload size
      PayloadValidator.validatePayload(response.toMap(), 'SYNC response');

      // Send response
      final topic = 'merkle_kv/${request.sourceNodeId}/sync/response';
      await _mqttClient.publish(topic, jsonEncode(response.toMap()));

    } catch (e) {
      // Log error but don't crash
    }
  }

  @override
  Future<void> handleSyncKeysRequest(SyncKeysRequest request) async {
    try {
      final remoteEntries = <String, StorageEntry>{};
      final notFoundKeys = <String>[];

      // Get local entries for requested keys
      for (final key in request.keys) {
        final localEntry = await _storage.get(key);
        if (localEntry != null) {
          remoteEntries[key] = localEntry;
        } else {
          notFoundKeys.add(key);
        }
      }

      final response = SyncKeysResponse(
        requestId: request.requestId,
        responseNodeId: _nodeId,
        entries: remoteEntries,
        notFoundKeys: notFoundKeys,
        timestamp: DateTime.now(),
      );

      // Validate payload size
      PayloadValidator.validatePayload(response.toMap(), 'SYNC_KEYS response');

      // Send response
      final topic = 'merkle_kv/${request.sourceNodeId}/sync_keys/response';
      await _mqttClient.publish(topic, jsonEncode(response.toMap()));

      // Apply reconciliation for entries we received
      await _applyReconciliation(request.entries, []);

    } catch (e) {
      // Log error but don't crash
    }
  }

  void _handleSyncResponse(SyncResponse response) {
    final completer = _pendingSyncRequests.remove(response.requestId);
    completer?.complete(response);
  }

  void _handleSyncKeysResponse(SyncKeysResponse response) {
    final completer = _pendingSyncKeysRequests.remove(response.requestId);
    completer?.complete(response);
  }

  bool _compareHashes(Uint8List hash1, Uint8List hash2) {
    if (hash1.length != hash2.length) return false;
    for (int i = 0; i < hash1.length; i++) {
      if (hash1[i] != hash2[i]) return false;
    }
    return true;
  }

  String _generateRequestId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(10000);
    return '${_nodeId}_${timestamp}_$random';
  }

  @override
  void configureRateLimit({double? requestsPerSecond, int? bucketCapacity}) {
    if (requestsPerSecond != null) {
      _rateLimiter = RateLimiter(
        requestsPerSecond: requestsPerSecond,
        bucketCapacity: bucketCapacity,
      );
    }
  }

  @override
  void dispose() {
    // Cancel any pending requests
    for (final completer in _pendingSyncRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(SyncException(SyncErrorCode.timeout, 'Protocol disposed'));
      }
    }
    for (final completer in _pendingSyncKeysRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(SyncException(SyncErrorCode.timeout, 'Protocol disposed'));
      }
    }
    
    _pendingSyncRequests.clear();
    _pendingSyncKeysRequests.clear();
  }
}