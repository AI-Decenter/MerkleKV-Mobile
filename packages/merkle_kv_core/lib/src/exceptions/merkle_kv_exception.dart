import '../commands/response.dart';

/// Base exception class for all MerkleKV operations per Locked Spec §12.
///
/// Provides a hierarchy of exception types corresponding to specific error 
/// conditions that can occur during MerkleKV operations.
abstract class MerkleKVException implements Exception {
  /// Error code from Locked Spec §12
  final int errorCode;
  
  /// Human-readable error message
  final String message;
  
  /// Optional underlying cause
  final Object? cause;
  
  const MerkleKVException(this.errorCode, this.message, [this.cause]);
  
  @override
  String toString() => '$runtimeType: $message (code: $errorCode)';
  
  /// Creates a MerkleKVException from a Response object
  factory MerkleKVException.fromResponse(Response response) {
    if (response.isSuccess) {
      throw ArgumentError('Cannot create exception from successful response');
    }
    
    final code = response.errorCode ?? ErrorCode.internalError;
    final message = response.error ?? 'Unknown error';
    
    switch (code) {
      case ErrorCode.invalidRequest:
        return ValidationException(message);
      case ErrorCode.timeout:
        return TimeoutException(message);
      case ErrorCode.notFound:
        return KeyNotFoundException(message);
      case ErrorCode.payloadTooLarge:
        return PayloadException(message);
      case ErrorCode.rangeOverflow:
        return ValidationException(message);
      case ErrorCode.invalidType:
        return ValidationException(message);
      case ErrorCode.internalError:
      default:
        return InternalException(message);
    }
  }
}

/// Exception thrown when connection to MQTT broker fails or is lost.
class ConnectionException extends MerkleKVException {
  const ConnectionException(String message, [Object? cause]) 
      : super(ErrorCode.timeout, message, cause);
}

/// Exception thrown when input validation fails.
class ValidationException extends MerkleKVException {
  const ValidationException(String message, [Object? cause])
      : super(ErrorCode.invalidRequest, message, cause);
}

/// Exception thrown when operations timeout.
class TimeoutException extends MerkleKVException {
  const TimeoutException(String message, [Object? cause])
      : super(ErrorCode.timeout, message, cause);
}

/// Exception thrown when payload size limits are exceeded.
class PayloadException extends MerkleKVException {
  const PayloadException(String message, [Object? cause])
      : super(ErrorCode.payloadTooLarge, message, cause);
}

/// Exception thrown when a requested key is not found.
class KeyNotFoundException extends MerkleKVException {
  const KeyNotFoundException(String message, [Object? cause])
      : super(ErrorCode.notFound, message, cause);
}

/// Exception thrown for internal errors.
class InternalException extends MerkleKVException {
  const InternalException(String message, [Object? cause])
      : super(ErrorCode.internalError, message, cause);
}

/// Exception thrown when client is disconnected and offline queue is disabled.
class DisconnectedException extends MerkleKVException {
  const DisconnectedException(String message, [Object? cause])
      : super(ErrorCode.timeout, message, cause);
}