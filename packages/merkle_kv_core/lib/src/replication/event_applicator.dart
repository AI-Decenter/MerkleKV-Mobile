import 'dart:typed_data';
import 'dart:async';
import 'package:meta/meta.dart';

import '../config/merkle_kv_config.dart';
import '../storage/storage_interface.dart';
import '../storage/storage_entry.dart';
import 'cbor_serializer.dart';
import 'metrics.dart';
import 'lww_resolver.dart';

/// Application status for incoming replication events
enum ApplicationResult {
  applied,     // Event was successfully applied to storage
  duplicate,   // Event was a duplicate and ignored
  rejected,    // Event was rejected (older timestamp, validation error, etc.)
  conflict,    // Event had timestamp conflict but was resolved
}

/// Detailed status information for event application
class ApplicationStatus {
  final ApplicationResult result;
  final String? reason;
  final ReplicationEvent event;
  final Duration processingTime;

  const ApplicationStatus({
    required this.result,
    required this.event,
    required this.processingTime,
    this.reason,
  });

  @override
  String toString() => 'ApplicationStatus(result: $result, reason: $reason, '
      'key: ${event.key}, nodeId: ${event.nodeId}, seq: ${event.seq})';
}

/// Abstract interface for replication event application per Locked Spec §7
abstract class ReplicationEventApplicator {
  /// Applies an incoming replication event to the storage layer
  ///
  /// Performs deduplication, validation, and Last-Write-Wins conflict resolution
  /// before applying the event to storage. Events are processed idempotently.
  Future<void> applyEvent(ReplicationEvent event);

  /// Applies CBOR-encoded event data from MQTT
  ///
  /// Deserializes the CBOR data and applies the event. Malformed events
  /// are logged and skipped without affecting other events.
  Future<void> applyCborEvent(Uint8List cborData);

  /// Configures deduplication parameters
  ///
  /// [windowSize] - Size of the sliding window per node (default: 4096)
  /// [ttl] - Time-to-live for deduplication entries (default: 7 days)
  /// [maxNodes] - Maximum number of nodes to track (default: 1000)
  void configureDeduplication({
    int? windowSize,
    Duration? ttl,
    int? maxNodes,
  });

  /// Stream of application status updates for observability
  Stream<ApplicationStatus> get applicationStatus;

  /// Current deduplication statistics
  Map<String, dynamic> getDeduplicationStats();

  /// Initializes the applicator
  Future<void> initialize();

  /// Disposes the applicator and cleans up resources
  Future<void> dispose();
}

/// Sliding bitmap window for efficient O(1) deduplication tracking
class _SequenceWindow {
  final int windowSize;
  final Set<int> _sequences = <int>{};
  int _baseSequence = 0;
  DateTime _lastAccess = DateTime.now();

  _SequenceWindow(this.windowSize);

  /// Checks if sequence number is within the current window
  bool isInWindow(int seq) {
    return seq >= _baseSequence && seq < _baseSequence + windowSize;
  }

  /// Checks if sequence has been seen (O(1) operation)
  bool hasSeen(int seq) {
    _lastAccess = DateTime.now();
    return _sequences.contains(seq);
  }

  /// Marks sequence as seen and slides window if necessary
  /// Returns true if the window was advanced/slid
  bool markSeen(int seq) {
    _lastAccess = DateTime.now();
    
    if (seq >= _baseSequence + windowSize) {
      // Slide window forward
      final newBase = seq - (windowSize ~/ 2);
      _sequences.removeWhere((s) => s < newBase);
      _baseSequence = newBase;
      _sequences.add(seq);
      return true; // Window was advanced
    } else if (seq < _baseSequence) {
      // Sequence is too old, ignore
      return false;
    }
    
    _sequences.add(seq);
    return false; // No window advance
  }

  /// Gets the age of this window based on last access
  Duration get age => DateTime.now().difference(_lastAccess);

  /// Gets current window statistics
  Map<String, dynamic> get stats => {
    'baseSequence': _baseSequence,
    'trackedSequences': _sequences.length,
    'windowSize': windowSize,
    'lastAccess': _lastAccess.toIso8601String(),
  };
}

/// Deduplication tracker with configurable window size and TTL
class DeduplicationTracker {
  final int windowSize;
  final Duration ttl;
  final int maxNodes;
  
  final Map<String, _SequenceWindow> _nodeWindows = <String, _SequenceWindow>{};
  Timer? _cleanupTimer;
  
  // Metrics
  int _totalChecks = 0;
  int _duplicateHits = 0;
  int _windowEvictions = 0;
  int _ttlEvictions = 0;
  int _windowAdvanceCount = 0;

  DeduplicationTracker({
    this.windowSize = 4096,
    this.ttl = const Duration(days: 7),
    this.maxNodes = 1000,
  }) {
    // Start periodic cleanup - more frequent for short TTLs
    final cleanupInterval = ttl.inMilliseconds < 1000 
        ? Duration(milliseconds: (ttl.inMilliseconds / 2).round().clamp(10, 500))
        : const Duration(minutes: 30);
    
    _cleanupTimer = Timer.periodic(
      cleanupInterval, 
      (_) => _performCleanup(),
    );
  }

  /// Checks if (nodeId, seq) pair is a duplicate (O(1) operation)
  bool isDuplicate(String nodeId, int seq) {
    _totalChecks++;
    
    final window = _nodeWindows[nodeId];
    if (window == null) {
      return false;
    }
    
    final isDupe = window.hasSeen(seq);
    if (isDupe) {
      _duplicateHits++;
    }
    
    return isDupe;
  }

  /// Marks (nodeId, seq) as seen
  void markSeen(String nodeId, int seq) {
    _nodeWindows.putIfAbsent(nodeId, () => _SequenceWindow(windowSize));
    final windowAdvanced = _nodeWindows[nodeId]!.markSeen(seq);
    
    if (windowAdvanced) {
      _windowAdvanceCount++;
    }
    
    // Enforce max nodes limit with LRU eviction
    if (_nodeWindows.length > maxNodes) {
      _evictOldestNode();
    }
  }

  /// Performs TTL-based cleanup of old entries
  void _performCleanup() {
    final now = DateTime.now();
    final toRemove = <String>[];
    
    for (final entry in _nodeWindows.entries) {
      if (now.difference(entry.value._lastAccess) > ttl) {
        toRemove.add(entry.key);
      }
    }
    
    for (final nodeId in toRemove) {
      _nodeWindows.remove(nodeId);
      _ttlEvictions++;
    }
  }

  /// Triggers cleanup for testing purposes
  @visibleForTesting
  void performCleanupForTesting() {
    _performCleanup();
  }

  /// Evicts the least recently used node
  void _evictOldestNode() {
    if (_nodeWindows.isEmpty) return;
    
    String? oldestNode;
    DateTime? oldestTime;
    
    for (final entry in _nodeWindows.entries) {
      if (oldestTime == null || entry.value._lastAccess.isBefore(oldestTime)) {
        oldestTime = entry.value._lastAccess;
        oldestNode = entry.key;
      }
    }
    
    if (oldestNode != null) {
      _nodeWindows.remove(oldestNode);
      _windowEvictions++;
    }
  }

  /// Gets deduplication statistics
  Map<String, dynamic> get stats {
    // Calculate estimated memory usage
    final bitsetBytes = ((windowSize + 31) ~/ 32) * 4; // Bytes per bitset
    const overhead = 64; // Overhead per node in bytes
    final estimatedMemoryBytes = _nodeWindows.length * (bitsetBytes + overhead);
    
    return {
      'totalChecks': _totalChecks,
      'duplicateHits': _duplicateHits,
      'windowEvictions': _windowAdvanceCount + _windowEvictions, // Combined for backward compatibility
      'nodeEvictions': _windowEvictions, // LRU node evictions only
      'ttlEvictions': _ttlEvictions,
      'activeNodes': _nodeWindows.length,
      'estimatedMemoryBytes': estimatedMemoryBytes,
      'hitRate': _totalChecks > 0 ? _duplicateHits / _totalChecks : 0.0,
      'nodeWindows': _nodeWindows.map((k, v) => MapEntry(k, v.stats)),
    };
  }

  /// Disposes the tracker and stops cleanup timer
  void dispose() {
    _cleanupTimer?.cancel();
    _nodeWindows.clear();
  }
}

/// Implementation of replication event applicator with deduplication and LWW
class ReplicationEventApplicatorImpl implements ReplicationEventApplicator {
  final StorageInterface _storage;
  final ReplicationMetrics _metrics;
  final DeduplicationTracker _deduplicationTracker;
  final LWWResolver _lwwResolver;
  
  final StreamController<ApplicationStatus> _statusController = 
      StreamController<ApplicationStatus>.broadcast();
  
  bool _initialized = false;
  bool _disposed = false;
  
  // Metrics
  int _eventsApplied = 0;
  int _eventsRejected = 0;
  int _eventsDuplicate = 0;
  int _conflictsResolved = 0;

  ReplicationEventApplicatorImpl({
    required MerkleKVConfig config,
    required StorageInterface storage,
    ReplicationMetrics? metrics,
    DeduplicationTracker? deduplicationTracker,
    LWWResolver? lwwResolver,
  }) : _storage = storage,
       _metrics = metrics ?? const NoOpReplicationMetrics(),
       _deduplicationTracker = deduplicationTracker ?? DeduplicationTracker(),
       _lwwResolver = lwwResolver ?? LWWResolverImpl();

  @override
  Stream<ApplicationStatus> get applicationStatus => _statusController.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
  }

  @override
  Future<void> applyEvent(ReplicationEvent event) async {
    _ensureInitialized();
    
    final startTime = DateTime.now();
    ApplicationStatus status;
    
    try {
      // Step 1: Basic validation
      final validationResult = _validateEvent(event);
      if (validationResult != null) {
        status = ApplicationStatus(
          result: ApplicationResult.rejected,
          event: event,
          processingTime: DateTime.now().difference(startTime),
          reason: validationResult,
        );
        _eventsRejected++;
        _metrics.incrementEventsRejected();
        _emitStatus(status);
        return;
      }

      // Step 2: Deduplication check
      if (_deduplicationTracker.isDuplicate(event.nodeId, event.seq)) {
        status = ApplicationStatus(
          result: ApplicationResult.duplicate,
          event: event,
          processingTime: DateTime.now().difference(startTime),
          reason: 'Duplicate (nodeId=${event.nodeId}, seq=${event.seq})',
        );
        _eventsDuplicate++;
        _metrics.incrementEventsDuplicate();
        _emitStatus(status);
        return;
      }

      // Step 3: Timestamp clamping (skew protection)
      final clampedEvent = _clampTimestamp(event);
      final wasClamped = clampedEvent.timestampMs != event.timestampMs;

      // Step 4: Last-Write-Wins conflict resolution
      final existing = await _storage.get(event.key);
      final lwwResult = _resolveLWWConflict(clampedEvent, existing);
      
      if (lwwResult == _LWWResult.older) {
        status = ApplicationStatus(
          result: ApplicationResult.rejected,
          event: event,
          processingTime: DateTime.now().difference(startTime),
          reason: 'Older timestamp (LWW)',
        );
        _eventsRejected++;
        _metrics.incrementEventsRejected();
        _emitStatus(status);
        return;
      }

      if (lwwResult == _LWWResult.duplicate) {
        status = ApplicationStatus(
          result: ApplicationResult.duplicate,
          event: event,
          processingTime: DateTime.now().difference(startTime),
          reason: 'Identical timestamp and content',
        );
        _eventsDuplicate++;
        _metrics.incrementEventsDuplicate();
        _emitStatus(status);
        return;
      }

      if (lwwResult == _LWWResult.anomaly) {
        status = ApplicationStatus(
          result: ApplicationResult.conflict,
          event: event,
          processingTime: DateTime.now().difference(startTime),
          reason: 'Timestamp collision with different content',
        );
        _conflictsResolved++;
        _metrics.incrementConflictsResolved();
        _emitStatus(status);
        return; // Keep existing entry
      }

      // Step 5: Apply event to storage
      await _applyToStorage(clampedEvent);
      
      // Step 6: Mark as seen for deduplication
      _deduplicationTracker.markSeen(event.nodeId, event.seq);

      status = ApplicationStatus(
        result: ApplicationResult.applied,
        event: event,
        processingTime: DateTime.now().difference(startTime),
        reason: wasClamped ? 'Applied (timestamp clamped)' : 'Applied',
      );
      
      _eventsApplied++;
      _metrics.incrementEventsApplied();
      
      if (wasClamped) {
        _metrics.incrementEventsClamped();
      }
      
    } catch (e) {
      status = ApplicationStatus(
        result: ApplicationResult.rejected,
        event: event,
        processingTime: DateTime.now().difference(startTime),
        reason: 'Error: $e',
      );
      _eventsRejected++;
      _metrics.incrementEventsRejected();
    }
    
    final latency = DateTime.now().difference(startTime).inMicroseconds;
    // Clamp latency to at least 1 microsecond to prevent zero values
    final clampedLatency = latency > 0 ? latency : 1;
    _metrics.recordApplicationLatency(clampedLatency);
    
    _emitStatus(status);
  }

  @override
  Future<void> applyCborEvent(Uint8List cborData) async {
    try {
      // Validate CBOR payload size
      if (cborData.length > 300 * 1024) { // 300 KiB limit
        throw const CborValidationException('CBOR payload exceeds 300 KiB limit');
      }
      
      final event = CborSerializer.decode(cborData);
      await applyEvent(event);
    } catch (e) {
      // Create a dummy event for error reporting
      const errorEvent = ReplicationEvent.value(
        key: 'unknown',
        nodeId: 'unknown',
        seq: 0,
        timestampMs: 0,
        value: '',
      );
      
      final status = ApplicationStatus(
        result: ApplicationResult.rejected,
        event: errorEvent,
        processingTime: const Duration(milliseconds: 1),
        reason: 'CBOR deserialization error: $e',
      );
      
      _eventsRejected++;
      _metrics.incrementEventsRejected();
      _emitStatus(status);
    }
  }

  @override
  void configureDeduplication({
    int? windowSize,
    Duration? ttl,
    int? maxNodes,
  }) {
    // Current implementation uses fixed tracker, but this could be enhanced
    // to recreate the tracker with new parameters if needed
  }

  @override
  Map<String, dynamic> getDeduplicationStats() {
    return {
      'tracker': _deduplicationTracker.stats,
      'events': {
        'applied': _eventsApplied,
        'rejected': _eventsRejected,
        'duplicate': _eventsDuplicate,
        'conflicts': _conflictsResolved,
      },
    };
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    
    _deduplicationTracker.dispose();
    await _statusController.close();
  }

  /// Validates event structure and size constraints
  String? _validateEvent(ReplicationEvent event) {
    // Check key size (≤256 bytes UTF-8)
    final keyBytes = event.key.codeUnits.length;
    if (keyBytes > 256) {
      return 'Key exceeds 256 bytes UTF-8 limit';
    }
    
    // Check value size if present (≤256 KiB UTF-8)
    if (event.value != null) {
      final valueBytes = event.value!.codeUnits.length;
      if (valueBytes > 256 * 1024) {
        return 'Value exceeds 256 KiB UTF-8 limit';
      }
    }
    
    // Validate tombstone consistency
    if (event.tombstone && event.value != null) {
      return 'Tombstone event cannot have value';
    }
    
    if (!event.tombstone && event.value == null) {
      return 'Non-tombstone event must have value';
    }
    
    // Validate sequence number
    if (event.seq < 0) {
      return 'Sequence number cannot be negative';
    }
    
    // Validate timestamp
    if (event.timestampMs <= 0) {
      return 'Timestamp must be positive';
    }
    
    return null; // Valid
  }

  /// Clamps timestamp to prevent excessive future skew
  ReplicationEvent _clampTimestamp(ReplicationEvent event) {
    final originalTimestamp = event.timestampMs;
    final clampedTimestamp = _lwwResolver.clampTimestamp(originalTimestamp);
    
    // Track clamping metrics
    if (clampedTimestamp != originalTimestamp) {
      _metrics.incrementLWWTimestampClamps();
    }
    
    // Convert back to ReplicationEvent with clamped timestamp
    if (event.tombstone) {
      return ReplicationEvent.tombstone(
        key: event.key,
        nodeId: event.nodeId,
        seq: event.seq,
        timestampMs: clampedTimestamp,
      );
    } else {
      return ReplicationEvent.value(
        key: event.key,
        nodeId: event.nodeId,
        seq: event.seq,
        timestampMs: clampedTimestamp,
        value: event.value!,
      );
    }
  }

  /// Performs Last-Write-Wins conflict resolution
  _LWWResult _resolveLWWConflict(ReplicationEvent event, StorageEntry? existing) {
    if (existing == null) {
      return _LWWResult.apply; // No conflict
    }
    
    // Convert event to StorageEntry for comparison
    final StorageEntry eventEntry;
    if (event.tombstone) {
      eventEntry = StorageEntry.tombstone(
        key: event.key,
        timestampMs: event.timestampMs,
        nodeId: event.nodeId,
        seq: event.seq,
      );
    } else {
      eventEntry = StorageEntry.value(
        key: event.key,
        value: event.value!,
        timestampMs: event.timestampMs,
        nodeId: event.nodeId,
        seq: event.seq,
      );
    }
    
    // Check for timestamp anomaly BEFORE LWW comparison
    // Same timestamp + same nodeId but different content = anomaly
    if (eventEntry.timestampMs == existing.timestampMs && 
        eventEntry.nodeId == existing.nodeId) {
      // Check if content is actually different
      final bool contentSame;
      if (eventEntry.isTombstone && existing.isTombstone) {
        contentSame = true; // Both tombstones
      } else if (eventEntry.isTombstone != existing.isTombstone) {
        contentSame = false; // One tombstone, one value
      } else {
        contentSame = eventEntry.value == existing.value; // Compare values
      }
      
      if (!contentSame) {
        // Same timestamp and nodeId but different content - this is an anomaly
        _metrics.incrementLWWAnomalies();
        return _LWWResult.anomaly;
      }
    }
    
    // Use LWW resolver to compare entries
    final comparison = _lwwResolver.compare(eventEntry, existing);
    
    // Track metrics
    _metrics.incrementLWWComparisons();
    
    switch (comparison) {
      case ComparisonResult.localWins:
        _metrics.incrementLWWLocalWins();
        return _LWWResult.apply; // Event is newer
      case ComparisonResult.remoteWins:
        _metrics.incrementLWWRemoteWins();
        return _LWWResult.older; // Event is older
      case ComparisonResult.duplicate:
        _metrics.incrementLWWDuplicates();
        return _LWWResult.duplicate; // Same content
    }
  }

  /// Applies event to storage layer
  Future<void> _applyToStorage(ReplicationEvent event) async {
    if (event.tombstone) {
      await _storage.delete(
        event.key,
        event.timestampMs,
        event.nodeId,
        event.seq,
      );
    } else {
      final entry = StorageEntry.value(
        key: event.key,
        value: event.value!,
        timestampMs: event.timestampMs,
        nodeId: event.nodeId,
        seq: event.seq,
      );
      await _storage.put(event.key, entry);
    }
  }

  void _emitStatus(ApplicationStatus status) {
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('ReplicationEventApplicator not initialized');
    }
    if (_disposed) {
      throw StateError('ReplicationEventApplicator has been disposed');
    }
  }
}

/// Result of Last-Write-Wins conflict resolution
enum _LWWResult {
  apply,     // Apply the event (newer or no conflict)
  older,     // Event is older, reject
  duplicate, // Same timestamp and content, treat as duplicate
  anomaly,   // Same timestamp but different content, keep existing
}
