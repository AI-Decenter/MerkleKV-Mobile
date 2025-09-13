/// Storage entry representing a key-value pair with version vector for LWW conflict resolution.
///
/// Each entry contains a version vector (timestampMs, nodeId, seq) that enables
/// Last-Write-Wins conflict resolution per Locked Spec §5.1 and tombstone
/// management per §5.6.
class StorageEntry {
  /// The key associated with this entry.
  /// Must be ≤256 bytes when encoded as UTF-8 per Locked Spec §11.
  final String key;

  /// The value associated with this key.
  /// null for tombstones (deleted entries).
  /// Must be ≤256KiB bytes when encoded as UTF-8 per Locked Spec §11.
  final String? value;

  /// Wall clock timestamp in milliseconds since Unix epoch.
  /// Used for Last-Write-Wins conflict resolution per §5.1.
  final int timestampMs;

  /// Unique identifier of the node that created this entry.
  /// Used as tiebreaker in LWW conflict resolution per §5.1.
  final String nodeId;

  /// Sequence number for this node.
  /// Incremented for each operation on a given node.
  final int seq;

  /// Whether this entry represents a deleted key (tombstone).
  /// Tombstones have value=null and are garbage collected after 24h per §5.6.
  final bool isTombstone;

  const StorageEntry({
    required this.key,
    required this.value,
    required this.timestampMs,
    required this.nodeId,
    required this.seq,
    required this.isTombstone,
  });

  /// Creates a regular (non-tombstone) entry.
  factory StorageEntry.value({
    required String key,
    required String value,
    required int timestampMs,
    required String nodeId,
    required int seq,
  }) {
    return StorageEntry(
      key: key,
      value: value,
      timestampMs: timestampMs,
      nodeId: nodeId,
      seq: seq,
      isTombstone: false,
    );
  }

  /// Creates a tombstone entry for a deleted key.
  factory StorageEntry.tombstone({
    required String key,
    required int timestampMs,
    required String nodeId,
    required int seq,
  }) {
    return StorageEntry(
      key: key,
      value: null,
      timestampMs: timestampMs,
      nodeId: nodeId,
      seq: seq,
      isTombstone: true,
    );
  }

  /// Compares two entries for Last-Write-Wins conflict resolution per §5.1.
  ///
  /// Returns:
  /// - positive if this entry wins over [other]
  /// - negative if [other] wins over this entry
  /// - 0 if entries are equivalent (same timestamp, nodeId, and seq)
  ///
  /// LWW ordering: (timestampMs, nodeId, seq) with lexicographic tiebreaker.
  int compareVersions(StorageEntry other) {
    // Compare timestamps first
    final timestampComparison = timestampMs.compareTo(other.timestampMs);
    if (timestampComparison != 0) {
      return timestampComparison;
    }

    // If timestamps are equal, compare nodeId lexicographically
    final nodeComparison = nodeId.compareTo(other.nodeId);
    if (nodeComparison != 0) {
      return nodeComparison;
    }

    // If timestamps and nodeIds are equal, compare sequence numbers
    return seq.compareTo(other.seq);
  }

  /// Returns true if this entry wins over [other] in LWW conflict resolution.
  bool winsOver(StorageEntry other) {
    return compareVersions(other) > 0;
  }

  /// Returns true if this entry is equivalent to [other] (same version vector).
  bool isEquivalentTo(StorageEntry other) {
    return compareVersions(other) == 0;
  }

  /// Returns true if this tombstone is older than 24 hours and can be garbage collected.
  bool isExpiredTombstone() {
    if (!isTombstone) return false;

    final now = DateTime.now().millisecondsSinceEpoch;
    const twentyFourHours = 24 * 60 * 60 * 1000; // 24h in milliseconds

    return (now - timestampMs) > twentyFourHours;
  }

  /// Converts this entry to a JSON map for persistence.
  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'value': value,
      'timestampMs': timestampMs,
      'nodeId': nodeId,
      'seq': seq,
      'isTombstone': isTombstone,
    };
  }

  /// Creates a StorageEntry from a JSON map.
  factory StorageEntry.fromJson(Map<String, dynamic> json) {
    return StorageEntry(
      key: json['key'] as String,
      value: json['value'] as String?,
      timestampMs: json['timestampMs'] as int,
      nodeId: json['nodeId'] as String,
      seq: json['seq'] as int,
      isTombstone: json['isTombstone'] as bool,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StorageEntry &&
        other.key == key &&
        other.value == value &&
        other.timestampMs == timestampMs &&
        other.nodeId == nodeId &&
        other.seq == seq &&
        other.isTombstone == isTombstone;
  }

  @override
  int get hashCode {
    return Object.hash(key, value, timestampMs, nodeId, seq, isTombstone);
  }

  @override
  String toString() {
    return 'StorageEntry(key: $key, value: $value, timestampMs: $timestampMs, '
        'nodeId: $nodeId, seq: $seq, isTombstone: $isTombstone)';
  }
}
