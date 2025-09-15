import 'dart:math';
import 'dart:typed_data';

/// Test data generators for property-based testing and edge case validation
class TestGenerators {
  static final Random _random = Random(42); // Fixed seed for reproducibility

  /// Generates random timestamps within reasonable bounds
  static int randomTimestamp({int? seed}) {
    final random = seed != null ? Random(seed) : _random;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Generate timestamps within ±7 days to test LWW edge cases
    // 7 days * 24 hours * 60 minutes * 60 seconds * 1000 milliseconds = 604,800,000
    // Range is 2 * 604,800,000 = 1,209,600,000 which is well under 2^32 limit
    const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;
    return now + random.nextInt(2 * sevenDaysMs) - sevenDaysMs;
  }

  /// Generates random node IDs with realistic format patterns
  static String randomNodeId({int? seed}) {
    final random = seed != null ? Random(seed) : _random;
    final formats = [
      'node-${random.nextInt(1000)}',
      'device-${randomHex(random, 8)}',
      'mobile-${randomUuid(random).substring(0, 8)}',
      'edge-${random.nextInt(10000)}',
    ];
    return formats[random.nextInt(formats.length)];
  }

  /// Generates random hex strings
  static String randomHex(Random random, int length) {
    const chars = '0123456789abcdef';
    return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// Generates random UUID-like strings
  static String randomUuid(Random random) {
    return '${randomHex(random, 8)}-${randomHex(random, 4)}-${randomHex(random, 4)}-${randomHex(random, 4)}-${randomHex(random, 12)}';
  }

  /// Generates random UTF-8 strings with various character sets
  static String randomUtf8String({
    int minLength = 1,
    int maxLength = 100,
    bool includeEmoji = false,
    bool includeMultibyte = false,
    int? seed,
  }) {
    final random = seed != null ? Random(seed) : _random;
    final length = minLength + random.nextInt(maxLength - minLength + 1);
    
    String charSet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_';
    
    if (includeMultibyte) {
      charSet += 'áéíóúñç北京东京αβγδ';
    }
    
    if (includeEmoji) {
      charSet += '🚀🌟✨💎🔥⚡';
    }
    
    return List.generate(length, (_) => charSet[random.nextInt(charSet.length)]).join();
  }

  /// Generates invalid UTF-8 byte sequences for negative testing
  static Uint8List invalidUtf8Bytes({int? seed}) {
    final random = seed != null ? Random(seed) : _random;
    final invalidPatterns = [
      // Invalid start bytes
      [0xFF, 0xFE],
      [0xC0, 0x80], // Overlong encoding
      [0xE0, 0x80, 0x80], // Overlong encoding
      [0xF0, 0x80, 0x80, 0x80], // Overlong encoding
      // Truncated sequences
      [0xC2], // Missing continuation byte
      [0xE0, 0xA0], // Missing continuation byte
      [0xF0, 0x90, 0x80], // Missing continuation byte
      // Invalid continuation bytes
      [0xC2, 0xFF],
      [0xE0, 0xA0, 0xFF],
      // Surrogate pairs (invalid in UTF-8)
      [0xED, 0xA0, 0x80], // High surrogate
      [0xED, 0xB0, 0x80], // Low surrogate
    ];
    
    final pattern = invalidPatterns[random.nextInt(invalidPatterns.length)];
    return Uint8List.fromList(pattern);
  }

  /// Generates payloads of specific byte sizes for boundary testing
  static String payloadOfSize(int targetBytes, {bool useUtf8 = true}) {
    if (!useUtf8) {
      return 'a' * targetBytes;
    }
    
    // Mix of ASCII and multi-byte characters to reach exact byte size
    final buffer = StringBuffer();
    int currentBytes = 0;
    
    while (currentBytes < targetBytes) {
      final remaining = targetBytes - currentBytes;
      
      if (remaining >= 4 && _random.nextBool()) {
        // Add emoji (4 bytes)
        buffer.write('🚀');
        currentBytes += 4;
      } else if (remaining >= 2 && _random.nextBool()) {
        // Add 2-byte character
        buffer.write('é');
        currentBytes += 2;
      } else {
        // Add ASCII character (1 byte)
        buffer.write('a');
        currentBytes += 1;
      }
    }
    
    return buffer.toString();
  }

  /// Generates malformed JSON strings for negative testing
  static String malformedJson({int? seed}) {
    final random = seed != null ? Random(seed) : _random;
    final patterns = [
      '{"incomplete":',
      '{"missing_quote: "value"}',
      '{"trailing_comma": "value",}',
      '{"invalid_escape": "\\q"}',
      '{duplicate_key": "value1", "duplicate_key": "value2"}',
      '{"nested": {"unclosed": "value"}',
      '{"array": [1, 2, 3,]}',
      '{"number": 12.34.56}',
      '{"boolean": tru}',
      '{"null": nul}',
      // Control characters
      '{"control": "value\x00"}',
      '{"newline": "line1\nline2"}',
      // Invalid Unicode escapes
      '{"unicode": "\\uZZZZ"}',
      '{"unicode": "\\u12G5"}',
    ];
    
    return patterns[random.nextInt(patterns.length)];
  }

  /// Generates realistic MQTT topic names
  static String randomMqttTopic({
    String prefix = 'test',
    String clientId = 'client-1',
    int? seed,
  }) {
    final random = seed != null ? Random(seed) : _random;
    final suffixes = ['cmd', 'res', 'events', 'data', 'status'];
    final suffix = suffixes[random.nextInt(suffixes.length)];
    return '$prefix/$clientId/$suffix';
  }

  /// Generates edge case client IDs for topic validation testing
  static String edgeCaseClientId({int? seed}) {
    final random = seed != null ? Random(seed) : _random;
    final cases = [
      'a' * 128, // Max length
      'a' * 129, // Over max length (should fail)
      'client/with/slashes', // Contains forbidden characters
      'client+wildcard', // Contains MQTT wildcard
      'client#wildcard', // Contains MQTT wildcard
      '', // Empty (should fail)
      'client-_123-ABC', // Valid mixed characters
      'device-${randomHex(random, 16)}', // Long hex ID
    ];
    
    return cases[random.nextInt(cases.length)];
  }

  /// Generates bulk operation data for testing limits
  static Map<String, String> bulkMsetData({
    int pairCount = 50,
    bool exceedLimits = false,
    int? seed,
  }) {
    final random = seed != null ? Random(seed) : _random;
    final actualCount = exceedLimits ? 101 : pairCount; // 101 exceeds limit of 100
    
    final data = <String, String>{};
    for (int i = 0; i < actualCount; i++) {
      final key = 'key-${i.toString().padLeft(3, '0')}';
      final value = randomUtf8String(
        minLength: 10,
        maxLength: 100,
        includeMultibyte: random.nextBool(),
        seed: seed != null ? seed + i : null,
      );
      data[key] = value;
    }
    
    return data;
  }

  /// Generates MGET key lists for testing limits
  static List<String> bulkMgetKeys({
    int keyCount = 200,
    bool exceedLimits = false,
    bool includeDuplicates = false,
    int? seed,
  }) {
    final random = seed != null ? Random(seed) : _random;
    final actualCount = exceedLimits ? 257 : keyCount; // 257 exceeds limit of 256
    
    final keys = <String>[];
    for (int i = 0; i < actualCount; i++) {
      keys.add('key-${i.toString().padLeft(4, '0')}');
    }
    
    if (includeDuplicates && keys.length > 2) {
      // Add some duplicates by replacing a key that's not the first one
      final targetIndex = 1 + random.nextInt(keys.length - 1); // Never index 0
      keys[targetIndex] = keys[0]; // Create duplicate of first key
    }
    
    return keys;
  }

  /// Generates command payloads near size limits for testing
  static Map<String, dynamic> bulkCommandNearLimit({int? seed}) {
    final random = seed != null ? Random(seed) : _random;
    
    // Target: just under 512KiB total payload
    const targetSize = 512 * 1024 - 1000; // Leave margin for JSON overhead
    
    final keyValues = <String, String>{};
    int currentSize = 50; // Base JSON structure overhead
    
    while (currentSize < targetSize && keyValues.length < 100) {
      final keySize = 20 + random.nextInt(30); // 20-50 byte keys
      final valueSize = random.nextInt(10000) + 100; // 100-10000 byte values
      
      if (currentSize + keySize + valueSize > targetSize) {
        // Make final value exact
        final remainingSize = targetSize - currentSize - keySize;
        if (remainingSize > 0) {
          final key = randomUtf8String(minLength: keySize, maxLength: keySize, seed: seed);
          final value = payloadOfSize(remainingSize);
          keyValues[key] = value;
        }
        break;
      }
      
      final key = randomUtf8String(minLength: keySize, maxLength: keySize, seed: seed);
      final value = randomUtf8String(minLength: valueSize, maxLength: valueSize, seed: seed);
      keyValues[key] = value;
      
      // Estimate JSON overhead (quotes, colons, commas)
      currentSize += keySize + valueSize + 10;
    }
    
    return {
      'id': randomUuid(random),
      'op': 'MSET',
      'keyValues': keyValues,
    };
  }

  /// Generates realistic replication events for testing
  static Map<String, dynamic> replicationEvent({
    bool isTombstone = false,
    int? seed,
  }) {
    final random = seed != null ? Random(seed) : _random;
    
    final event = {
      'key': randomUtf8String(minLength: 5, maxLength: 50, seed: seed),
      'nodeId': randomNodeId(seed: seed),
      'seq': random.nextInt(10000) + 1,
      'timestampMs': randomTimestamp(seed: seed),
    };
    
    if (isTombstone) {
      event['tombstone'] = true;
    } else {
      event['value'] = randomUtf8String(
        minLength: 10,
        maxLength: 1000,
        includeMultibyte: random.nextBool(),
        includeEmoji: random.nextBool(),
        seed: seed,
      );
    }
    
    return event;
  }

  /// Generates sequence of events with potential conflicts for LWW testing
  static List<Map<String, dynamic>> conflictingEvents({
    String key = 'conflict-key',
    int eventCount = 5,
    int? seed,
  }) {
    final random = seed != null ? Random(seed) : _random;
    final baseTime = DateTime.now().millisecondsSinceEpoch;
    
    final events = <Map<String, dynamic>>[];
    
    for (int i = 0; i < eventCount; i++) {
      final nodeId = 'node-${random.nextInt(3)}'; // 3 nodes max for conflicts
      final timestamp = baseTime + random.nextInt(10000) - 5000; // ±5 seconds
      
      events.add({
        'key': key,
        'nodeId': nodeId,
        'seq': i + 1,
        'timestampMs': timestamp,
        'value': 'value-$i-from-$nodeId',
      });
    }
    
    return events;
  }
}

/// Property-based test helpers
class PropertyTestHelpers {
  /// Runs a property test with multiple random inputs
  static void forAll<T>(
    T Function() generator,
    bool Function(T) property, {
    int iterations = 100,
    int? seed,
  }) {
    // Use fixed seed for deterministic testing if provided
    final baseSeed = seed ?? 42;
    
    for (int i = 0; i < iterations; i++) {
      // Create deterministic seed for each iteration for reproducibility
      final iterationSeed = baseSeed + i;
      final value = generator();
      
      if (!property(value)) {
        throw AssertionError(
          'Property failed on iteration $i with value: $value (seed: $iterationSeed)'
        );
      }
    }
  }

  /// Runs a property test with two inputs
  static void forAll2<T, U>(
    T Function() generatorT,
    U Function() generatorU,
    bool Function(T, U) property, {
    int iterations = 100,
    int? seed,
  }) {
    for (int i = 0; i < iterations; i++) {
      final valueT = generatorT();
      final valueU = generatorU();
      
      if (!property(valueT, valueU)) {
        throw AssertionError(
          'Property failed on iteration $i with values: ($valueT, $valueU)'
        );
      }
    }
  }

  /// Runs a property test with three inputs  
  static void forAll3<T, U, V>(
    T Function() generatorT,
    U Function() generatorU,
    V Function() generatorV,
    bool Function(T, U, V) property, {
    int iterations = 100,
    int? seed,
  }) {
    for (int i = 0; i < iterations; i++) {
      final valueT = generatorT();
      final valueU = generatorU();
      final valueV = generatorV();
      
      if (!property(valueT, valueU, valueV)) {
        throw AssertionError(
          'Property failed on iteration $i with values: ($valueT, $valueU, $valueV)'
        );
      }
    }
  }
}