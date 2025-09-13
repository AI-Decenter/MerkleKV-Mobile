import 'dart:convert';
import 'dart:math';
import 'package:test/test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:merkle_kv_core/src/config/merkle_kv_config.dart';
import 'package:merkle_kv_core/src/commands/command_processor.dart';
import 'package:merkle_kv_core/src/commands/command.dart';
import 'package:merkle_kv_core/src/commands/response.dart';
import 'package:merkle_kv_core/src/storage/storage_interface.dart';
import 'package:merkle_kv_core/src/storage/storage_entry.dart';

// Generate mocks
@GenerateMocks([StorageInterface])
import 'command_processor_test.mocks.dart';

void main() {
  group('Command Processor', () {
    late MerkleKVConfig config;
    late MockStorageInterface mockStorage;
    late CommandProcessorImpl processor;

    setUp(() {
      config = MerkleKVConfig.create(
        mqttHost: 'test-broker.local',
        clientId: 'test-client',
        nodeId: 'test-node',
      );
      
      mockStorage = MockStorageInterface();
      processor = CommandProcessorImpl(config, mockStorage);
      
      // Setup default mock behaviors
      when(mockStorage.initialize()).thenAnswer((_) async {});
      when(mockStorage.put(any, any)).thenAnswer((_) async {});
    });

    group('JSON Validation', () {
      test('JSON validation rejects malformed command structures', () async {
        // Test various malformed JSON scenarios
        final malformedCommands = [
          '{"id": "test", "op": "GET"}', // Missing required key field
          '{"op": "SET", "key": "test"}', // Missing id and value
          '{"id": "", "op": "INVALID", "key": "test"}', // Invalid operation
          '{"id": "test", "op": "SET", "key": "", "value": "test"}', // Empty key
          '{"id": "test", "op": "GET", "key": null}', // Null key
          '{"id": "test", "op": "SET", "key": "test", "value": null}', // Null value for SET
        ];
        
        for (final malformedJson in malformedCommands) {
          expect(
            () => Command.fromJsonString(malformedJson),
            throwsA(isA<FormatException>()),
            reason: 'Malformed JSON should be rejected: $malformedJson',
          );
        }
      });

      test('validates command structure completeness', () async {
        // Valid command should work
        final validCommand = Command(
          id: 'test-123',
          op: 'GET',
          key: 'test-key',
        );
        
        final response = await processor.processCommand(validCommand);
        expect(response.id, equals('test-123'));
        
        // Command with extra fields should be accepted
        final commandWithExtras = Command(
          id: 'test-456',
          op: 'SET',
          key: 'test-key',
          value: 'test-value',
          extra: {'custom': 'field'}, // Extra fields allowed
        );
        
        final response2 = await processor.processCommand(commandWithExtras);
        expect(response2.id, equals('test-456'));
      });

      test('type validation for command fields', () async {
        // Test type mismatches in JSON
        expect(
          () => Command.fromJsonString('{"id": 123, "op": "GET", "key": "test"}'),
          throwsA(isA<TypeError>()),
          reason: 'Non-string ID should be rejected',
        );
        
        expect(
          () => Command.fromJsonString('{"id": "test", "op": 42, "key": "test"}'),
          throwsA(isA<TypeError>()),
          reason: 'Non-string operation should be rejected',
        );
      });

      test('handles escaped characters in JSON properly', () async {
        final commandWithEscapes = Command(
          id: 'test-escape',
          op: 'SET',
          key: 'key\\nwith\\tescapes',
          value: 'value\"with\\\"quotes',
        );
        
        final jsonString = commandWithEscapes.toJsonString();
        final parsedCommand = Command.fromJsonString(jsonString);
        
        expect(parsedCommand.key, equals('key\\nwith\\tescapes'));
        expect(parsedCommand.value, equals('value\"with\\\"quotes'));
      });
    });

    group('Bulk Operation Limits', () {
      test('bulk operation limits: MGET ≤256 keys, MSET ≤100 pairs', () async {
        // Test MGET with exactly 256 keys (should work)
        final validMgetKeys = List.generate(256, (i) => 'key-$i');
        final validMgetCommand = Command(
          id: 'mget-256',
          op: 'MGET',
          keys: validMgetKeys,
        );
        
        when(mockStorage.get(any)).thenAnswer((_) async => null);
        
        final validResponse = await processor.processCommand(validMgetCommand);
        expect(validResponse.status, equals('OK'));
        
        // Test MGET with 257 keys (should fail)
        final invalidMgetKeys = List.generate(257, (i) => 'key-$i');
        final invalidMgetCommand = Command(
          id: 'mget-257',
          op: 'MGET',
          keys: invalidMgetKeys,
        );
        
        final invalidResponse = await processor.processCommand(invalidMgetCommand);
        expect(invalidResponse.status, equals('ERROR'));
        expect(invalidResponse.message, contains('256'));
      });

      test('MSET bulk limit enforcement', () async {
        // Test MSET with exactly 100 pairs (should work)
        final validMsetPairs = <String, String>{};
        for (int i = 0; i < 100; i++) {
          validMsetPairs['key-$i'] = 'value-$i';
        }
        
        final validMsetCommand = Command(
          id: 'mset-100',
          op: 'MSET',
          keyValues: validMsetPairs,
        );
        
        final validResponse = await processor.processCommand(validMsetCommand);
        expect(validResponse.status, equals('OK'));
        
        // Test MSET with 101 pairs (should fail)
        final invalidMsetPairs = <String, String>{};
        for (int i = 0; i < 101; i++) {
          invalidMsetPairs['key-$i'] = 'value-$i';
        }
        
        final invalidMsetCommand = Command(
          id: 'mset-101',
          op: 'MSET',
          keyValues: invalidMsetPairs,
        );
        
        final invalidResponse = await processor.processCommand(invalidMsetCommand);
        expect(invalidResponse.status, equals('ERROR'));
        expect(invalidResponse.message, contains('100'));
      });

      test('empty bulk operations handling', () async {
        // Empty MGET should return empty result
        final emptyMgetCommand = Command(
          id: 'empty-mget',
          op: 'MGET',
          keys: [],
        );
        
        final emptyMgetResponse = await processor.processCommand(emptyMgetCommand);
        expect(emptyMgetResponse.status, equals('OK'));
        expect(emptyMgetResponse.results, isEmpty);
        
        // Empty MSET should return OK
        final emptyMsetCommand = Command(
          id: 'empty-mset',
          op: 'MSET',
          keyValues: {},
        );
        
        final emptyMsetResponse = await processor.processCommand(emptyMsetCommand);
        expect(emptyMsetResponse.status, equals('OK'));
      });
    });

    group('Payload Validation', () {
      test('payload validation: bulk operations ≤512KiB total', () async {
        // Create payload exactly at 512KiB limit
        final largeValue = 'x' * (500 * 1024); // 500KB per value
        final limitTestPairs = <String, String>{
          'key1': largeValue,
          'key2': 'small', // Total should be just over 512KiB
        };
        
        final limitCommand = Command(
          id: 'limit-test',
          op: 'MSET',
          keyValues: limitTestPairs,
        );
        
        final response = await processor.processCommand(limitCommand);
        expect(response.status, equals('PAYLOAD_TOO_LARGE'),
            reason: 'Payload exceeding 512KiB should be rejected');
      });

      test('individual value size limit: 256KiB', () async {
        // Create value exactly 256KiB + 1 byte
        final oversizedValue = 'a' * (256 * 1024 + 1);
        
        final oversizedCommand = Command(
          id: 'oversized-test',
          op: 'SET',
          key: 'test-key',
          value: oversizedValue,
        );
        
        final response = await processor.processCommand(oversizedCommand);
        expect(response.status, equals('ERROR'));
        expect(response.message, contains('256KiB'));
      });

      test('key size limit: 256 bytes UTF-8', () async {
        // Create key exactly 257 bytes UTF-8
        final oversizedKey = 'k' * 257;
        
        final oversizedKeyCommand = Command(
          id: 'oversized-key-test',
          op: 'GET',
          key: oversizedKey,
        );
        
        final response = await processor.processCommand(oversizedKeyCommand);
        expect(response.status, equals('ERROR'));
        expect(response.message, contains('256 bytes'));
      });

      test('UTF-8 encoding validation for keys and values', () async {
        // Valid UTF-8 with emoji should work
        final validUnicodeCommand = Command(
          id: 'unicode-test',
          op: 'SET',
          key: '🔑-key',
          value: '🚀-value',
        );
        
        final response = await processor.processCommand(validUnicodeCommand);
        expect(response.status, equals('OK'));
        
        verify(mockStorage.put(any, any)).called(1);
      });
    });

    group('Idempotency', () {
      test('idempotency: duplicate request IDs return cached responses', () async {
        final command = Command(
          id: 'idempotent-test',
          op: 'SET',
          key: 'test-key',
          value: 'test-value',
        );
        
        // First execution
        final response1 = await processor.processCommand(command);
        expect(response1.status, equals('OK'));
        
        // Second execution with same ID - should return cached response
        final response2 = await processor.processCommand(command);
        expect(response2.status, equals('OK'));
        expect(response2.id, equals(response1.id));
        
        // Storage should only be called once
        verify(mockStorage.put(any, any)).called(1);
      });

      test('idempotency cache expiration', () async {
        // Use a processor with shorter cache timeout for testing
        final shortTimeoutProcessor = CommandProcessorImpl(config, mockStorage);
        shortTimeoutProcessor.setCacheTimeout(const Duration(milliseconds: 100));
        
        final command = Command(
          id: 'expiry-test',
          op: 'SET',
          key: 'test-key',
          value: 'test-value',
        );
        
        // First execution
        await shortTimeoutProcessor.processCommand(command);
        
        // Wait for cache expiration
        await Future.delayed(const Duration(milliseconds: 150));
        
        // Second execution should not use cache
        await shortTimeoutProcessor.processCommand(command);
        
        // Storage should be called twice
        verify(mockStorage.put(any, any)).called(2);
      });

      test('idempotency cache LRU eviction', () async {
        final processor = CommandProcessorImpl(config, mockStorage);
        processor.setMaxCacheSize(2); // Small cache for testing
        
        // Fill cache to capacity
        for (int i = 1; i <= 3; i++) {
          final command = Command(
            id: 'cache-test-$i',
            op: 'SET',
            key: 'key-$i',
            value: 'value-$i',
          );
          await processor.processCommand(command);
        }
        
        // First command should be evicted, re-executing should call storage
        final firstCommand = Command(
          id: 'cache-test-1',
          op: 'SET',
          key: 'key-1',
          value: 'value-1',
        );
        
        await processor.processCommand(firstCommand);
        
        // Should be called 4 times total (3 initial + 1 re-execution)
        verify(mockStorage.put(any, any)).called(4);
      });

      test('empty request ID bypasses idempotency cache', () async {
        final command = Command(
          id: '', // Empty ID
          op: 'SET',
          key: 'test-key',
          value: 'test-value',
        );
        
        // Execute same command twice
        await processor.processCommand(command);
        await processor.processCommand(command);
        
        // Storage should be called twice (no caching)
        verify(mockStorage.put(any, any)).called(2);
      });
    });

    group('Numeric Operations', () {
      test('increment operation with overflow protection', () async {
        // Mock existing value
        final existingEntry = StorageEntry.value(
          key: 'counter',
          value: '9223372036854775800', // Near max int64
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          nodeId: 'test-node',
          seq: 1,
        );
        
        when(mockStorage.get('counter')).thenAnswer((_) async => existingEntry);
        
        final incrementCommand = Command(
          id: 'increment-test',
          op: 'INCR',
          key: 'counter',
          amount: 100, // Would cause overflow
        );
        
        final response = await processor.processCommand(incrementCommand);
        expect(response.status, equals('ERROR'));
        expect(response.message, contains('overflow'));
      });

      test('decrement operation with underflow protection', () async {
        final existingEntry = StorageEntry.value(
          key: 'counter',
          value: '-9223372036854775800', // Near min int64
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          nodeId: 'test-node',
          seq: 1,
        );
        
        when(mockStorage.get('counter')).thenAnswer((_) async => existingEntry);
        
        final decrementCommand = Command(
          id: 'decrement-test',
          op: 'DECR',
          key: 'counter',
          amount: 100, // Would cause underflow
        );
        
        final response = await processor.processCommand(decrementCommand);
        expect(response.status, equals('ERROR'));
        expect(response.message, contains('underflow'));
      });

      test('numeric operations on non-numeric values', () async {
        final nonNumericEntry = StorageEntry.value(
          key: 'text-key',
          value: 'not-a-number',
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          nodeId: 'test-node',
          seq: 1,
        );
        
        when(mockStorage.get('text-key')).thenAnswer((_) async => nonNumericEntry);
        
        final incrementCommand = Command(
          id: 'incr-non-numeric',
          op: 'INCR',
          key: 'text-key',
          amount: 1,
        );
        
        final response = await processor.processCommand(incrementCommand);
        expect(response.status, equals('ERROR'));
        expect(response.message, contains('numeric'));
      });
    });

    group('String Operations', () {
      test('append operation concatenates correctly', () async {
        final existingEntry = StorageEntry.value(
          key: 'text-key',
          value: 'Hello',
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          nodeId: 'test-node',
          seq: 1,
        );
        
        when(mockStorage.get('text-key')).thenAnswer((_) async => existingEntry);
        
        final appendCommand = Command(
          id: 'append-test',
          op: 'APPEND',
          key: 'text-key',
          value: ' World',
        );
        
        final response = await processor.processCommand(appendCommand);
        expect(response.status, equals('OK'));
        
        // Verify the concatenated value was stored
        final capturedEntry = verify(mockStorage.put('text-key', captureAny)).captured.single as StorageEntry;
        expect(capturedEntry.value, equals('Hello World'));
      });

      test('prepend operation concatenates correctly', () async {
        final existingEntry = StorageEntry.value(
          key: 'text-key',
          value: 'World',
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          nodeId: 'test-node',
          seq: 1,
        );
        
        when(mockStorage.get('text-key')).thenAnswer((_) async => existingEntry);
        
        final prependCommand = Command(
          id: 'prepend-test',
          op: 'PREPEND',
          key: 'text-key',
          value: 'Hello ',
        );
        
        final response = await processor.processCommand(prependCommand);
        expect(response.status, equals('OK'));
        
        // Verify the concatenated value was stored
        final capturedEntry = verify(mockStorage.put('text-key', captureAny)).captured.single as StorageEntry;
        expect(capturedEntry.value, equals('Hello World'));
      });

      test('string operations on missing keys create new entries', () async {
        when(mockStorage.get('missing-key')).thenAnswer((_) async => null);
        
        final appendCommand = Command(
          id: 'append-missing',
          op: 'APPEND',
          key: 'missing-key',
          value: 'New Value',
        );
        
        final response = await processor.processCommand(appendCommand);
        expect(response.status, equals('OK'));
        
        // Should create new entry with just the appended value
        final capturedEntry = verify(mockStorage.put('missing-key', captureAny)).captured.single as StorageEntry;
        expect(capturedEntry.value, equals('New Value'));
      });

      test('string operations respect size limits after concatenation', () async {
        // Create existing value that's already large
        final largeValue = 'x' * (256 * 1024 - 10); // Just under limit
        final existingEntry = StorageEntry.value(
          key: 'large-key',
          value: largeValue,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          nodeId: 'test-node',
          seq: 1,
        );
        
        when(mockStorage.get('large-key')).thenAnswer((_) async => existingEntry);
        
        final appendCommand = Command(
          id: 'append-overflow',
          op: 'APPEND',
          key: 'large-key',
          value: 'x' * 20, // Would exceed 256KiB limit
        );
        
        final response = await processor.processCommand(appendCommand);
        expect(response.status, equals('ERROR'));
        expect(response.message, contains('256KiB'));
      });
    });

    group('Error Response Generation', () {
      test('appropriate error response for unknown operations', () async {
        final invalidCommand = Command(
          id: 'invalid-op-test',
          op: 'INVALID_OP',
          key: 'test-key',
        );
        
        final response = await processor.processCommand(invalidCommand);
        expect(response.status, equals('ERROR'));
        expect(response.message, contains('Unknown operation'));
        expect(response.id, equals('invalid-op-test'));
      });

      test('error responses include request ID for correlation', () async {
        final errorCommand = Command(
          id: 'error-correlation-test',
          op: 'SET',
          key: 'k' * 300, // Oversized key
          value: 'test-value',
        );
        
        final response = await processor.processCommand(errorCommand);
        expect(response.status, equals('ERROR'));
        expect(response.id, equals('error-correlation-test'));
      });

      test('storage errors are properly handled and reported', () async {
        when(mockStorage.put(any, any)).thenThrow(Exception('Storage failure'));
        
        final command = Command(
          id: 'storage-error-test',
          op: 'SET',
          key: 'test-key',
          value: 'test-value',
        );
        
        final response = await processor.processCommand(command);
        expect(response.status, equals('ERROR'));
        expect(response.message, contains('Storage failure'));
      });
    });
  });
}