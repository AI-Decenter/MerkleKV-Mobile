import 'dart:convert';

/// Topic type enumeration for canonical scheme.
enum TopicType {
  /// Command topic: {prefix}/{client_id}/cmd
  command,
  
  /// Response topic: {prefix}/{client_id}/res
  response,
  
  /// Replication topic: {prefix}/replication/events
  replication,
}

/// Comprehensive topic validation and building for multi-tenant isolation.
///
/// Implements enhanced validation per Issue #22 with UTF-8 byte length
/// calculation, strict character validation, and canonical topic scheme
/// support for secure multi-tenant deployments.
class TopicValidator {
  /// Maximum total topic length in UTF-8 bytes.
  static const int maxTopicLength = 100;
  
  /// Maximum prefix length to reserve space for client_id and suffixes.
  static const int maxPrefixLength = 50;
  
  /// Maximum client ID length in UTF-8 bytes.
  static const int maxClientIdLength = 128;
  
  /// Allowed characters pattern: [A-Za-z0-9_/-] but no consecutive slashes
  static final RegExp _allowedCharsPattern = RegExp(r'^[A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*$');
  
  /// MQTT wildcard characters that must be rejected.
  static const List<String> _mqttWildcards = ['+', '#'];
  
  /// Validates topic prefix according to enhanced multi-tenant requirements.
  ///
  /// Validation rules:
  /// - No MQTT wildcards (+ or #)
  /// - No leading or trailing slashes
  /// - Only allowed characters: [A-Za-z0-9_/-]
  /// - UTF-8 byte length ≤ maxPrefixLength
  /// - Cannot be empty after normalization
  ///
  /// Throws [ArgumentError] with clear error messages for violations.
  static void validatePrefix(String prefix) {
    if (prefix.isEmpty) {
      throw ArgumentError('Topic prefix cannot be empty');
    }
    
    // Check for MQTT wildcards
    for (final wildcard in _mqttWildcards) {
      if (prefix.contains(wildcard)) {
        throw ArgumentError(
          'Topic prefix cannot contain MQTT wildcard \'$wildcard\'',
        );
      }
    }
    
    // Check for leading or trailing slashes
    if (prefix.startsWith('/')) {
      throw ArgumentError('Topic prefix cannot have leading slash');
    }
    
    if (prefix.endsWith('/')) {
      throw ArgumentError('Topic prefix cannot have trailing slash');
    }
    
    // Check allowed characters
    if (!_allowedCharsPattern.hasMatch(prefix)) {
      throw ArgumentError(
        'Topic prefix contains invalid characters. '
        'Only [A-Za-z0-9_/-] are allowed',
      );
    }
    
    // Check UTF-8 byte length
    final prefixBytes = utf8.encode(prefix);
    if (prefixBytes.length > maxPrefixLength) {
      throw ArgumentError(
        'Topic prefix too long: ${prefixBytes.length} UTF-8 bytes. '
        'Maximum allowed: $maxPrefixLength bytes',
      );
    }
  }
  
  /// Validates client ID according to MQTT and multi-tenant requirements.
  ///
  /// Validation rules:
  /// - Cannot be empty
  /// - No forward slashes (/)
  /// - No MQTT wildcards (+ or #)
  /// - UTF-8 byte length ≤ maxClientIdLength
  ///
  /// Throws [ArgumentError] with clear error messages for violations.
  static void validateClientId(String clientId) {
    if (clientId.isEmpty) {
      throw ArgumentError('Client ID cannot be empty');
    }
    
    // Check for forward slash
    if (clientId.contains('/')) {
      throw ArgumentError('Client ID cannot contain forward slash (/)');
    }
    
    // Check for MQTT wildcards
    for (final wildcard in _mqttWildcards) {
      if (clientId.contains(wildcard)) {
        throw ArgumentError(
          'Client ID cannot contain MQTT wildcard \'$wildcard\'',
        );
      }
    }
    
    // Check UTF-8 byte length
    final clientIdBytes = utf8.encode(clientId);
    if (clientIdBytes.length > maxClientIdLength) {
      throw ArgumentError(
        'Client ID too long: ${clientIdBytes.length} UTF-8 bytes. '
        'Maximum allowed: $maxClientIdLength bytes',
      );
    }
  }
  
  /// Builds a canonical topic according to the specified type.
  ///
  /// Canonical scheme:
  /// - Command: {prefix}/{client_id}/cmd
  /// - Response: {prefix}/{client_id}/res
  /// - Replication: {prefix}/replication/events
  ///
  /// Validates all components and checks total UTF-8 byte length.
  /// 
  /// Throws [ArgumentError] if validation fails or topic exceeds length limit.
  static String buildTopic(String prefix, String clientId, TopicType type) {
    // Validate components
    validatePrefix(prefix);
    validateClientId(clientId);
    
    // Build topic based on type
    final String topic;
    switch (type) {
      case TopicType.command:
        topic = '$prefix/$clientId/cmd';
        break;
      case TopicType.response:
        topic = '$prefix/$clientId/res';
        break;
      case TopicType.replication:
        topic = '$prefix/replication/events';
        break;
    }
    
    // Validate total topic length
    final topicBytes = utf8.encode(topic);
    if (topicBytes.length > maxTopicLength) {
      throw ArgumentError(
        'Generated topic exceeds maximum length: ${topicBytes.length} UTF-8 bytes. '
        'Maximum allowed: $maxTopicLength bytes. Topic: $topic',
      );
    }
    
    return topic;
  }
  
  /// Builds a command topic for the target client.
  ///
  /// Convenience method for building command topics to specific clients.
  /// Validates the target client ID and builds: {prefix}/{targetClientId}/cmd
  static String buildCommandTopic(String prefix, String targetClientId) {
    return buildTopic(prefix, targetClientId, TopicType.command);
  }
  
  /// Normalizes a raw prefix by trimming whitespace and removing slashes.
  ///
  /// This method provides backward compatibility with existing TopicScheme
  /// normalization while applying enhanced validation.
  ///
  /// Returns the default prefix 'mkv' if the input becomes empty after
  /// normalization.
  static String normalizePrefix(String rawPrefix) {
    String normalized = rawPrefix.trim();
    
    // Remove leading slashes
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    
    // Remove trailing slashes
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    
    // Return default if empty after normalization
    if (normalized.isEmpty) {
      return 'mkv';
    }
    
    return normalized;
  }
  
  /// Validates a complete topic string for multi-tenant isolation.
  ///
  /// Checks that the topic follows the canonical scheme and doesn't
  /// exceed length limits. Useful for validating incoming topics.
  static bool isValidTopic(String topic) {
    try {
      // Check basic constraints
      if (topic.isEmpty) return false;
      
      // Check UTF-8 byte length
      final topicBytes = utf8.encode(topic);
      if (topicBytes.length > maxTopicLength) return false;
      
      // Check for wildcards in the complete topic
      for (final wildcard in _mqttWildcards) {
        if (topic.contains(wildcard)) return false;
      }
      
      // Check basic structure (should have at least 2 slashes for canonical topics)
      final parts = topic.split('/');
      if (parts.length < 3) return false;
      
      // Validate each part contains only allowed characters
      for (final part in parts) {
        if (part.isEmpty) return false;
        if (!_allowedCharsPattern.hasMatch(part)) return false;
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// Extracts the tenant prefix from a canonical topic.
  ///
  /// For topics following canonical scheme, returns the prefix portion.
  /// Useful for multi-tenant isolation verification.
  ///
  /// Returns null if the topic doesn't follow canonical format.
  static String? extractPrefix(String topic) {
    try {
      final parts = topic.split('/');
      
      // Check for different canonical patterns
      if (parts.length >= 4) {
        // For cmd/res topics: prefix/.../clientId/cmd|res
        if (parts.last == 'cmd' || parts.last == 'res') {
          return parts.sublist(0, parts.length - 2).join('/');
        }
      }
      
      if (parts.length >= 3) {
        // For replication topics: prefix/.../replication/events
        if (parts[parts.length - 2] == 'replication' && 
            parts.last == 'events') {
          return parts.sublist(0, parts.length - 2).join('/');
        }
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }
  
  /// Calculates the UTF-8 byte length of a string.
  ///
  /// Helper method for length validation that properly handles Unicode characters.
  static int getUtf8ByteLength(String text) {
    return utf8.encode(text).length;
  }
}