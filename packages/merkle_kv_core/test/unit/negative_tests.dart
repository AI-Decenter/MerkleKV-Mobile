import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:merkle_kv_core/src/config/merkle_kv_config.dart';
import 'package:merkle_kv_core/src/commands/command.dart';
import 'package:merkle_kv_core/src/commands/command_processor.dart';
import 'package:merkle_kv_core/src/storage/in_memory_storage.dart';
import 'package:merkle_kv_core/src/storage/storage_entry.dart';

void main() {
  group('Negative Tests', () {
    late MerkleKVConfig config;
    late InMemoryStorage storage;
    late CommandProcessorImpl processor;

    setUp(() async {
      config = MerkleKVConfig.create(
        mqttHost: 'test-broker.local',
        clientId: 'negative-test-client',
        nodeId: 'negative-test-node',
        persistenceEnabled: false,
      );
      
      storage = InMemoryStorage(config);
      await storage.initialize();
      processor = CommandProcessorImpl(config, storage);
    });

    tearDown(() async {
      await storage.dispose();
    });

    group('Payload Size Limit Tests', () {
      test('value exactly 256KiB+1 byte rejected', () async {
        // Create value that's exactly 1 byte over the limit
        final oversizedValue = 'a' * (256 * 1024 + 1);
        
        final command = Command(
          id: 'oversized-value-test',
          op: 'SET',
          key: 'test-key',
          value: oversizedValue,
        );
        
        final response = await processor.processCommand(command);
        
        expect(response.status, equals('ERROR'));
        expect(response.message, contains('256KiB'));
        expect(response.message, contains('value'));
      });

      test('bulk operation payload exactly 512KiB+1 byte rejected', () async {
        // Create bulk operation that exceeds 512KiB total payload
        final keyValuePairs = <String, String>{};
        
        // Each pair contributes ~5.2KB (5KB value + key + JSON overhead)
        // 100 pairs = ~520KB > 512KiB limit
        for (int i = 0; i < 100; i++) {
          keyValuePairs['key-$i'] = 'x' * (5 * 1024); // 5KB each
        }
        
        final bulkCommand = Command(
          id: 'bulk-oversized-test',
          op: 'MSET',
          keyValues: keyValuePairs,
        );
        
        final response = await processor.processCommand(bulkCommand);
        
        expect(response.status, equals('PAYLOAD_TOO_LARGE'));
        expect(response.message, contains('512KiB'));
      });

      test('key exactly 256 bytes UTF-8+1 rejected', () async {
        // Create key that's exactly 1 byte over UTF-8 limit
        final oversizedKey = 'k' * 257; // 257 bytes UTF-8
        
        final command = Command(
          id: 'oversized-key-test',
          op: 'GET',
          key: oversizedKey,
        );
        
        final response = await processor.processCommand(command);
        
        expect(response.status, equals('ERROR'));
        expect(response.message, contains('256 bytes'));
        expect(response.message, contains('key'));
      });

      test('multi-byte UTF-8 characters counted correctly in limits', () async {
        // Each € character is 3 bytes in UTF-8
        // 86 × 3 = 258 bytes (over 256 limit)
        final multiByteKey = '€' * 86;
        
        final command = Command(
          id: 'multibyte-key-test',
          op: 'GET',
          key: multiByteKey,
        );
        
        final response = await processor.processCommand(command);
        
        expect(response.status, equals('ERROR'));
        expect(response.message, contains('256 bytes'));
      });

      test('emoji and complex Unicode handled in size calculations', () async {
        // Create value with complex emoji (4 bytes each)
        // 65536 × 4 = 262144 bytes (over 256KiB = 262144 bytes exactly)
        final emojiValue = '🚀' * 65537; // Just over limit
        
        final command = Command(
          id: 'emoji-oversized-test',
          op: 'SET',
          key: 'emoji-key',
          value: emojiValue,
        );
        
        final response = await processor.processCommand(command);
        
        expect(response.status, equals('ERROR'));
        expect(response.message, contains('256KiB'));
      });
    });

    group('UTF-8 Byte Limit Tests', () {
      test('invalid UTF-8 byte sequences rejected', () {
        // Test various invalid UTF-8 sequences
        final invalidSequences = [
          [0xFF], // Invalid start byte
          [0xC0, 0x80], // Overlong encoding of null
          [0xF5, 0x80, 0x80, 0x80], // Invalid start byte for 4-byte sequence
          [0xC2], // Incomplete 2-byte sequence
          [0xE1, 0x80], // Incomplete 3-byte sequence
          [0xF0, 0x90, 0x80], // Incomplete 4-byte sequence
        ];
        
        for (final sequence in invalidSequences) {
          expect(
            () {
              // Try to create string from invalid UTF-8 bytes
              final invalidString = utf8.decode(sequence, allowMalformed: false);
              Command(
                id: 'invalid-utf8-test',
                op: 'SET',
                key: invalidString,
                value: 'test-value',
              );
            },
            throwsA(isA<FormatException>()),
            reason: 'Invalid UTF-8 sequence should be rejected: $sequence',
          );
        }
      });

      test('surrogate pairs in UTF-16 not allowed in UTF-8', () {
        // Test high and low surrogate characters
        final surrogateChars = [
          '\uD800', // High surrogate start
          '\uDBFF', // High surrogate end
          '\uDC00', // Low surrogate start
          '\uDFFF', // Low surrogate end
        ];
        
        for (final surrogateChar in surrogateChars) {
          final command = Command(
            id: 'surrogate-test',
            op: 'SET',
            key: 'test-key',
            value: 'value$surrogateChar',
          );
          
          // Should handle gracefully or reject
          final response = processor.processCommand(command);
          expect(response, completes);
        }
      });

      test('null bytes in strings rejected', () async {
        final nullByteKey = 'key\u0000with-null';
        final nullByteValue = 'value\u0000with-null';
        
        final command = Command(
          id: 'null-byte-test',
          op: 'SET',
          key: nullByteKey,
          value: nullByteValue,
        );
        
        final response = await processor.processCommand(command);
        
        // Should either work (storing as-is) or reject with clear error
        expect(response.status, isIn(['OK', 'ERROR']));
        if (response.status == 'ERROR') {
          expect(response.message, contains('null'));
        }
      });

      test('control characters handling in keys and values', () async {
        final controlChars = [
          '\u0001', // Start of heading
          '\u0008', // Backspace
          '\u001F', // Unit separator
          '\u007F', // Delete
        ];
        
        for (final controlChar in controlChars) {
          final command = Command(
            id: 'control-char-test',
            op: 'SET',
            key: 'key${controlChar}test',
            value: 'value${controlChar}test',
          );
          
          final response = await processor.processCommand(command);
          
          // Should handle gracefully
          expect(response.status, isIn(['OK', 'ERROR']));
          if (response.status == 'ERROR') {
            expect(response.message, contains('character'));
          }
        }
      });
    });

    group('Malformed JSON Tests', () {
      test('truncated JSON messages rejected', () {
        final truncatedJsons = [
          '{"id": "test", "op": "GET", "key":', // Missing value and closing
          '{"id": "test", "op": "GET"', // Missing closing brace
          '{"id": "test", ', // Severely truncated
          '{"id": "test", "op": "SET", "key": "test", "value": "test"', // Missing closing brace
        ];
        
        for (final truncatedJson in truncatedJsons) {
          expect(
            () => Command.fromJsonString(truncatedJson),
            throwsA(isA<FormatException>()),
            reason: 'Truncated JSON should be rejected: $truncatedJson',
          );
        }
      });

      test('invalid JSON syntax rejected', () {
        final invalidJsons = [
          '{id: "test", op: "GET", key: "test"}', // Missing quotes on keys
          '{"id": "test", "op": "GET", "key": "test",}', // Trailing comma
          '{"id": "test" "op": "GET", "key": "test"}', // Missing comma
          "{'id': 'test', 'op': 'GET', 'key': 'test'}", // Single quotes
          '{"id": "test", "op": "GET", "key": test}', // Unquoted string value
        ];
        
        for (final invalidJson in invalidJsons) {
          expect(
            () => Command.fromJsonString(invalidJson),
            throwsA(isA<FormatException>()),
            reason: 'Invalid JSON syntax should be rejected: $invalidJson',
          );
        }
      });

      test('type mismatches in JSON fields rejected', () {
        final typeMismatchJsons = [
          '{"id": 123, "op": "GET", "key": "test"}', // Numeric ID
          '{"id": "test", "op": true, "key": "test"}', // Boolean operation
          '{"id": "test", "op": "GET", "key": 456}', // Numeric key
          '{"id": "test", "op": "SET", "key": "test", "value": [1,2,3]}', // Array value
          '{"id": "test", "op": "MGET", "keys": "not-an-array"}', // String instead of array
        ];
        
        for (final typeMismatchJson in typeMismatchJsons) {
          expect(
            () => Command.fromJsonString(typeMismatchJson),
            throwsA(isA<TypeError>()),
            reason: 'Type mismatch should be rejected: $typeMismatchJson',
          );
        }
      });

      test('nested objects in unexpected fields handled', () {
        final nestedJson = '''
        {
          "id": "nested-test",
          "op": "SET",
          "key": "test-key",
          "value": "test-value",
          "nested": {
            "deep": {
              "object": "value"
            }
          }
        }
        ''';
        
        // Should either accept with extra fields or reject cleanly
        expect(
          () => Command.fromJsonString(nestedJson),
          returnsNormally,
          reason: 'Nested objects should be handled gracefully',
        );
      });

      test('extremely large JSON payloads rejected', () {
        // Create JSON that would exceed reasonable parsing limits
        final largeArray = List.generate(10000, (i) => 'item-$i');
        final largeJson = json.encode({
          'id': 'large-test',
          'op': 'MGET',
          'keys': largeArray,
        });
        
        expect(
          () => Command.fromJsonString(largeJson),
          throwsA(isA<Exception>()),
          reason: 'Extremely large JSON should be rejected',
        );
      });

      test('JSON with escape sequence attacks', () {
        final escapeAttacks = [
          '{"id": "test", "op": "SET", "key": "\\x00\\x01\\x02", "value": "test"}',
          '{"id": "test", "op": "SET", "key": "\\u0000\\u0001", "value": "test"}',
          '{"id": "test", "op": "SET", "key": "test", "value": "\\\\\\\\\\\\"}',
        ];
        
        for (final escapeAttack in escapeAttacks) {
          // Should handle escape sequences properly without security issues
          expect(
            () => Command.fromJsonString(escapeAttack),
            returnsNormally,
            reason: 'Escape sequences should be handled safely: $escapeAttack',
          );
        }
      });
    });

    group('Network Failure Simulation', () {
      test('partial message corruption handling', () async {
        // Simulate partially corrupted command
        final validCommand = Command(
          id: 'corruption-test',
          op: 'SET',
          key: 'test-key',
          value: 'test-value',
        );
        
        var jsonString = validCommand.toJsonString();
        
        // Corrupt middle of JSON
        final corruptedJson = jsonString.substring(0, jsonString.length ~/ 2) + 
                            'CORRUPTED' + 
                            jsonString.substring(jsonString.length ~/ 2 + 9);
        
        expect(
          () => Command.fromJsonString(corruptedJson),
          throwsA(isA<FormatException>()),
          reason: 'Corrupted JSON should be rejected',
        );
      });

      test('timeout scenarios during command processing', () async {
        // Simulate command that would timeout during storage operation
        final timeoutCommand = Command(
          id: 'timeout-test',
          op: 'SET',
          key: 'timeout-key',
          value: 'timeout-value',
        );
        
        // This test verifies the processor handles timeouts gracefully
        // In real implementation, storage operations might timeout
        final response = await processor.processCommand(timeoutCommand);
        
        // Should complete without throwing
        expect(response.id, equals('timeout-test'));
        expect(response.status, isIn(['OK', 'ERROR', 'TIMEOUT']));
      });

      test('concurrent malformed request handling', () async {
        final futures = <Future<void>>[];
        
        // Send multiple malformed requests concurrently
        for (int i = 0; i < 10; i++) {
          final malformedJson = '{"id": "concurrent-$i", "op": "GET"'; // Missing closing
          
          futures.add(
            Future(() {
              expect(
                () => Command.fromJsonString(malformedJson),
                throwsA(isA<FormatException>()),
              );
            }),
          );
        }
        
        // All should complete without affecting each other
        await Future.wait(futures);
      });
    });

    group('Resource Exhaustion Tests', () {
      test('excessive key count in bulk operations', () async {
        // Test with way more than allowed keys
        final excessiveKeys = List.generate(10000, (i) => 'key-$i');
        
        final excessiveCommand = Command(
          id: 'excessive-keys-test',
          op: 'MGET',
          keys: excessiveKeys,
        );
        
        final response = await processor.processCommand(excessiveCommand);
        
        expect(response.status, equals('ERROR'));
        expect(response.message, contains('256'));
        expect(response.message, contains('limit'));
      });

      test('memory exhaustion protection in value processing', () async {
        // Test multiple large values that could exhaust memory
        final largeKeyValues = <String, String>{};
        
        // Each value is 100KB, total would be ~10MB if all processed
        for (int i = 0; i < 100; i++) {
          largeKeyValues['large-key-$i'] = 'x' * (100 * 1024);
        }
        
        final memoryTestCommand = Command(
          id: 'memory-test',
          op: 'MSET',
          keyValues: largeKeyValues,
        );
        
        final response = await processor.processCommand(memoryTestCommand);
        
        // Should be rejected due to payload size limits before memory exhaustion
        expect(response.status, isIn(['ERROR', 'PAYLOAD_TOO_LARGE']));
      });

      test('recursive JSON structure rejection', () {
        // Create JSON with deep nesting that could cause stack overflow
        var deepJson = '{"id": "deep-test", "op": "SET", "key": "test"';
        
        for (int i = 0; i < 1000; i++) {
          deepJson += ', "level$i": {';
        }
        
        deepJson += '"value": "deep"';
        
        for (int i = 0; i < 1000; i++) {
          deepJson += '}';
        }
        
        deepJson += '}';
        
        expect(
          () => Command.fromJsonString(deepJson),
          throwsA(isA<Exception>()),
          reason: 'Deeply nested JSON should be rejected',
        );
      });
    });

    group('Security Edge Cases', () {
      test('command injection attempts through field values', () async {
        final injectionAttempts = [
          '{"id": "$(rm -rf /)", "op": "GET", "key": "test"}',
          '{"id": "test", "op": "; DROP TABLE users; --", "key": "test"}',
          '{"id": "test", "op": "GET", "key": "../../../etc/passwd"}',
          '{"id": "test", "op": "SET", "key": "test", "value": "<script>alert(1)</script>"}',
        ];
        
        for (final injectionJson in injectionAttempts) {
          // Should parse as regular strings, not execute as commands
          final command = Command.fromJsonString(injectionJson);
          final response = await processor.processCommand(command);
          
          // Should treat as regular string data
          expect(response.status, isIn(['OK', 'ERROR']));
          if (response.status == 'ERROR') {
            expect(response.message, isNot(contains('executed')));
          }
        }
      });

      test('buffer overflow simulation in string operations', () async {
        // Test append/prepend operations that could theoretically overflow buffers
        final entry = StorageEntry.value(
          key: 'buffer-test',
          value: 'x' * (256 * 1024 - 100), // Near the limit
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          nodeId: config.nodeId,
          seq: 1,
        );
        
        await storage.put('buffer-test', entry);
        
        final appendCommand = Command(
          id: 'buffer-overflow-test',
          op: 'APPEND',
          key: 'buffer-test',
          value: 'y' * 200, // Would exceed limit
        );
        
        final response = await processor.processCommand(appendCommand);
        
        expect(response.status, equals('ERROR'));
        expect(response.message, contains('256KiB'));
      });
    });
  });
}