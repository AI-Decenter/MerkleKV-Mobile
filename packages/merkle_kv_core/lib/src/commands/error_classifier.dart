import 'dart:async';
import 'dart:io';

/// Error classifier for determining which errors are retriable
class ErrorClassifier {
  /// List of error codes that are not retriable
  static const List<int> nonRetriableErrorCodes = [
    // Validation errors (100-109)
    100, 101, 102, 103, 104, 105, 106, 107, 108, 109,
    // Authentication errors
    200, 201, 202, 203,
    // Authorization errors
    300, 301, 302, 303,
  ];
  
  /// Determines if an error is retriable
  /// 
  /// [error] - The error object to check
  /// Returns true if the error is retriable
  static bool isRetriable(Object error) {
    // Network errors, timeouts, and broker disconnections are retriable
    if (error is TimeoutException) {
      return true;
    }
    
    // Check for specific error codes from the API
    if (error is ApiException) {
      return !nonRetriableErrorCodes.contains(error.code);
    }
    
    // Handle network-related exceptions
    if (error is SocketException || 
        error is HandshakeException ||
        error is ConnectionException ||
        error is MqttConnectionException) {
      return true;
    }
    
    // Default to non-retriable for unknown errors
    return false;
  }
}

/// Exception thrown for API errors
class ApiException implements Exception {
  final int code;
  final String message;
  
  ApiException(this.code, this.message);
  
  @override
  String toString() => 'ApiException: [$code] $message';
}

/// Exception for connection-related errors
class ConnectionException implements Exception {
  final String message;
  
  ConnectionException(this.message);
  
  @override
  String toString() => 'ConnectionException: $message';
}

/// Exception for MQTT connection errors
class MqttConnectionException implements Exception {
  final String message;
  
  MqttConnectionException(this.message);
  
  @override
  String toString() => 'MqttConnectionException: $message';
}