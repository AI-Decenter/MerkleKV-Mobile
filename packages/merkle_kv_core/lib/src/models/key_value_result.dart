/// Result for a single key operation in bulk operations.
class KeyValueResult {
  /// The key that was operated on
  final String key;

  /// Operation status (OK, NOT_FOUND, ERROR)
  final String status;

  /// Value for successful operations
  final String? value;

  /// Error code for failed operations
  final int? errorCode;

  /// Error message for failed operations
  final String? error;

  const KeyValueResult({
    required this.key,
    required this.status,
    this.value,
    this.errorCode,
    this.error,
  });

  /// Creates a successful result.
  factory KeyValueResult.ok(String key, String? value) {
    return KeyValueResult(
      key: key,
      status: 'OK',
      value: value,
    );
  }

  /// Creates a not found result.
  factory KeyValueResult.notFound(String key) {
    return KeyValueResult(
      key: key,
      status: 'NOT_FOUND',
      errorCode: 102,
      error: 'Key not found',
    );
  }

  /// Creates an error result.
  factory KeyValueResult.error(String key, int errorCode, String error) {
    return KeyValueResult(
      key: key,
      status: 'ERROR',
      errorCode: errorCode,
      error: error,
    );
  }

  /// Creates KeyValueResult from JSON object.
  factory KeyValueResult.fromJson(Map<String, dynamic> json) {
    return KeyValueResult(
      key: json['key'] as String,
      status: json['status'] as String,
      value: json['value'] as String?,
      errorCode: json['errorCode'] as int?,
      error: json['error'] as String?,
    );
  }

  /// Converts KeyValueResult to JSON object.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'key': key,
      'status': status,
    };

    if (value != null) json['value'] = value;
    if (errorCode != null) json['errorCode'] = errorCode;
    if (error != null) json['error'] = error;

    return json;
  }

  /// Returns true if this result indicates success.
  bool get isSuccess => status == 'OK';

  /// Returns true if this result indicates not found.
  bool get isNotFound => status == 'NOT_FOUND';

  /// Returns true if this result indicates an error.
  bool get isError => status == 'ERROR';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeyValueResult &&
          runtimeType == other.runtimeType &&
          key == other.key &&
          status == other.status &&
          value == other.value &&
          errorCode == other.errorCode &&
          error == other.error;

  @override
  int get hashCode =>
      key.hashCode ^
      status.hashCode ^
      value.hashCode ^
      errorCode.hashCode ^
      error.hashCode;

  @override
  String toString() => 'KeyValueResult(key: $key, status: $status)';
}