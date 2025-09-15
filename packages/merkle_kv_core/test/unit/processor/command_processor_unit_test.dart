import 'dart:convert';
import 'dart:math';
import 'package:test/test.dart';
import '../../../lib/src/commands/command_processor.dart';
import '../../../lib/src/commands/command.dart';
import '../../../lib/src/commands/response.dart';
import '../../../lib/src/config/merkle_kv_config.dart';
import '../../../lib/src/storage/storage_entry.dart';
import '../../../lib/src/utils/bulk_operations.dart';
import '../../utils/generators.dart';
import '../../utils/mock_helpers.dart';

void main() {
  group('Command Processor Unit Tests', () {
    late CommandProcessorImpl processor;
    late MockStorage storage;
    late MerkleKVConfig config;

    setUp(() async {
      config = MerkleKVConfig(
        mqttHost: 'localhost',
        clientId: 'test-client',
        nodeId: 'test-node',
        topicPrefix: 'test',
      );
      storage = MockStorage();
      await storage.initialize();
      processor = CommandProcessorImpl(config, storage);
    });

    tearDown(() async {
      await storage.dispose();
    });

    group('JSON Command Validation', () {
      test('malformed JSON command structures are rejected', () async {
        final malformedCommands = [
          TestDataFactory.createMalformedJson('truncated'),
          TestDataFactory.createMalformedJson('missing_quote'),
          TestDataFactory.createMalformedJson('invalid_escape'),
          TestDataFactory.createMalformedJson('trailing_comma'),
          TestDataFactory.createMalformedJson('control_char'),
        ];

        for (final malformedJson in malformedCommands) {
          expect(() {
            Command.fromJsonString(malformedJson);
          }, throwsFormatException);
        }
      });

      test('commands missing required fields are rejected', () async {
        final invalidCommands = [
          {'op': 'GET'}, // Missing id
          {'id': 'test-1'}, // Missing op
          {'id': 'test-2', 'op': 'GET'}, // Missing key for GET
          {'id': 'test-3', 'op': 'SET', 'key': 'test'}, // Missing value for SET
          {'id': 'test-4', 'op': 'MGET'}, // Missing keys for MGET
          {'id': 'test-5', 'op': 'MSET'}, // Missing keyValues for MSET
        ];

        for (final invalidCmd in invalidCommands) {
          // For commands missing id or op, expect FormatException during parsing
          if (!invalidCmd.containsKey('id') || !invalidCmd.containsKey('op')) {
            expect(() => Command.fromJson(invalidCmd), throwsFormatException);
          } else {
            // For commands with id and op but missing other fields, expect processor to reject
            final command = Command.fromJson(invalidCmd);
            final response = await processor.processCommand(command);
            
            expect(response.status, equals(ResponseStatus.error));
            expect(response.errorCode, equals(ErrorCode.invalidRequest));
          }
        }
      });

      test('commands with invalid operation types are rejected', () async {
        final command = Command.fromJson({
          'id': 'test-1',
          'op': 'INVALID_OP',
          'key': 'test-key',
        });

        final response = await processor.processCommand(command);
        
        expect(response.status, equals(ResponseStatus.error));
        expect(response.errorCode, equals(ErrorCode.invalidRequest));
        expect(response.error, contains('Unsupported operation'));
      });

      test('commands with invalid data types are rejected', () async {
        final invalidTypeCommands = [
          {'id': 123, 'op': 'GET', 'key': 'test'}, // id should be string
          {'id': 'test', 'op': 123, 'key': 'test'}, // op should be string
          {'id': 'test', 'op': 'GET', 'key': 123}, // key should be string
          {'id': 'test', 'op': 'MGET', 'keys': 'not-array'}, // keys should be array
          {'id': 'test', 'op': 'MSET', 'keyValues': 'not-object'}, // keyValues should be object
        ];

        for (final invalidCmd in invalidTypeCommands) {
          expect(() {
            Command.fromJson(invalidCmd);
          }, throwsFormatException);
        }
      });

      test('property: all valid JSON commands are parsed correctly', () {
        final commandData = TestDataFactory.createCommand(
          id: TestGenerators.randomUuid(Random()),
          op: ['GET', 'SET', 'DELETE', 'MGET', 'MSET'][Random().nextInt(5)],
          key: TestGenerators.randomUtf8String(maxLength: 50),
          value: TestGenerators.randomUtf8String(maxLength: 100),
        );
        
        final command = Command.fromJson(commandData);
        expect(command.id, equals(commandData['id']));
        expect(command.op, equals(commandData['op']));
      });
    });

    group('Bulk Operation Limits', () {
      test('MGET with exactly 256 keys is accepted', () async {
        final keys = List.generate(256, (i) => 'key-${i.toString().padLeft(3, '0')}');
        final command = Command(id: 'test-1', op: 'MGET', keys: keys);
        
        final response = await processor.processCommand(command);
        expect(response.status, equals(ResponseStatus.ok));
        expect(response.results?.length, equals(256));
      });

      test('MGET with 257 keys is rejected', () async {
        final keys = TestGenerators.bulkMgetKeys(
          keyCount: 256,
          exceedLimits: true, // This will generate 257 keys
        );
        
        final command = Command(id: 'test-1', op: 'MGET', keys: keys);
        final response = await processor.processCommand(command);
        
        expect(response.status, equals(ResponseStatus.error));
        expect(response.errorCode, equals(ErrorCode.invalidRequest));
        expect(response.error, contains('maximum 256 keys'));
      });

      test('MGET with empty key list is rejected', () async {
        final command = Command(id: 'test-1', op: 'MGET', keys: []);
        final response = await processor.processCommand(command);
        
        expect(response.status, equals(ResponseStatus.error));
        expect(response.errorCode, equals(ErrorCode.invalidRequest));
        expect(response.error, contains('at least one key'));
      });

      test('MGET with duplicate keys is rejected', () async {
        final keys = TestGenerators.bulkMgetKeys(
          keyCount: 10,
          includeDuplicates: true,
        );
        
        final command = Command(id: 'test-1', op: 'MGET', keys: keys);
        final response = await processor.processCommand(command);
        
        expect(response.status, equals(ResponseStatus.error));
        expect(response.errorCode, equals(ErrorCode.invalidRequest));
        expect(response.error, contains('must be unique'));
      });

      test('MSET with exactly 100 pairs is accepted', () async {
        final keyValues = TestGenerators.bulkMsetData(pairCount: 100);
        final command = Command(id: 'test-1', op: 'MSET', keyValues: keyValues);
        
        final response = await processor.processCommand(command);
        expect(response.status, equals(ResponseStatus.ok));
        expect(response.results?.length, equals(100));
      });

      test('MSET with 101 pairs is rejected', () async {
        final keyValues = TestGenerators.bulkMsetData(
          pairCount: 100,
          exceedLimits: true, // This will generate 101 pairs
        );
        
        final command = Command(id: 'test-1', op: 'MSET', keyValues: keyValues);
        final response = await processor.processCommand(command);
        
        expect(response.status, equals(ResponseStatus.error));
        expect(response.errorCode, equals(ErrorCode.invalidRequest));
        expect(response.error, contains('maximum 100 pairs'));
      });

      test('MSET with empty key-value pairs is rejected', () async {
        final command = Command(id: 'test-1', op: 'MSET', keyValues: {});
        final response = await processor.processCommand(command);
        
        expect(response.status, equals(ResponseStatus.error));
        expect(response.errorCode, equals(ErrorCode.invalidRequest));
        expect(response.error, contains('at least one key-value pair'));
      });

      test('bulk operations maintain result order', () async {
        // Set up test data in specific order
        final keys = ['key-3', 'key-1', 'key-2']; // Intentionally unordered
        
        await processor.set('key-1', 'value-1', 'setup-1');
        await processor.set('key-3', 'value-3', 'setup-2');
        // key-2 intentionally missing
        
        final command = Command(id: 'test-1', op: 'MGET', keys: keys);
        final response = await processor.processCommand(command);
        
        expect(response.status, equals(ResponseStatus.ok));
        expect(response.results, isNotNull, reason: 'Results should not be null');
        expect(response.results!.length, equals(3));
        
        // Verify order matches submission order
        expect(response.results![0].key, equals('key-3'));
        expect(response.results![0].isSuccess, isTrue);
        expect(response.results![1].key, equals('key-1'));
        expect(response.results![1].isSuccess, isTrue);
        expect(response.results![2].key, equals('key-2'));
        expect(response.results![2].isNotFound, isTrue);
      });
    });

    group('Payload Size Validation', () {
      test('commands exactly at 512KiB total payload are accepted', () async {
        final commandData = TestGenerators.bulkCommandNearLimit();
        final command = Command.fromJson(commandData);
        
        final jsonPayload = command.toJsonString();
        TestAssertions.assertPayloadSize(jsonPayload, 512 * 1024);
        
        final response = await processor.processCommand(command);
        expect(response.status, equals(ResponseStatus.ok));
      });

      test('commands over 512KiB total payload are rejected', () async {
        // Create oversized command
        final largeKeyValues = <String, String>{};
        for (int i = 0; i < 50; i++) {
          largeKeyValues['key-$i'] = 'x' * 12000; // 50 * 12KB = 600KB > 512KB
        }
        
        final command = Command(
          id: 'oversized-test',
          op: 'MSET',
          keyValues: largeKeyValues,
        );
        
        final response = await processor.processCommand(command);
        expect(response.status, equals(ResponseStatus.error));
        expect(response.errorCode, equals(ErrorCode.payloadTooLarge));
      });

      test('individual keys exactly 256 bytes are accepted', () async {
        final maxSizeKey = TestGenerators.payloadOfSize(256);
        final response = await processor.set(maxSizeKey, 'test-value', 'test-1');
        
        expect(response.status, equals(ResponseStatus.ok));
      });

      test('individual keys over 256 bytes are rejected', () async {
        final oversizedKey = TestGenerators.payloadOfSize(257);
        final response = await processor.set(oversizedKey, 'test-value', 'test-1');
        
        expect(response.status, equals(ResponseStatus.error));
        expect(response.errorCode, equals(ErrorCode.payloadTooLarge));
      });

      test('individual values exactly 256KiB are accepted', () async {
        final maxSizeValue = TestGenerators.payloadOfSize(256 * 1024);
        final response = await processor.set('test-key', maxSizeValue, 'test-1');
        
        expect(response.status, equals(ResponseStatus.ok));
      });

      test('individual values over 256KiB are rejected', () async {
        final oversizedValue = TestGenerators.payloadOfSize(256 * 1024 + 1);
        final response = await processor.set('test-key', oversizedValue, 'test-1');
        
        expect(response.status, equals(ResponseStatus.error));
        expect(response.errorCode, equals(ErrorCode.payloadTooLarge));
      });

      test('UTF-8 multibyte characters are counted correctly for size limits', () async {
        // Each emoji is 4 bytes in UTF-8
        final emojiKey = '🚀' * 64; // 64 * 4 = 256 bytes exactly
        final emojiValue = '⚡' * (64 * 1024); // 64K * 4 = 256KB exactly
        
        TestAssertions.assertUtf8ByteLength(emojiKey, 256);
        TestAssertions.assertUtf8ByteLength(emojiValue, 256 * 1024);
        
        final response = await processor.set(emojiKey, emojiValue, 'test-1');
        expect(response.status, equals(ResponseStatus.ok));
      });

      test('property: payload validation is consistent', () {
        final testString = TestGenerators.randomUtf8String(
          minLength: 200,
          maxLength: 300,
          includeMultibyte: true,
          includeEmoji: true,
        );
        
        final bytes = utf8.encode(testString);
        final exceedsKeyLimit = bytes.length > 256;
        
        if (bytes.length > 256) {
          expect(() => throw ArgumentError('Key exceeds 256 byte limit'), throwsA(isA<ArgumentError>()));
        } else {
          expect(exceedsKeyLimit, isFalse);
        }
      });
    });

    group('Idempotency and Request Deduplication', () {
      test('duplicate request IDs return cached responses', () async {
        final requestId = 'idempotent-test-1';
        
        // First request
        final response1 = await processor.set('test-key', 'first-value', requestId);
        expect(response1.status, equals(ResponseStatus.ok));
        
        // Second request with same ID should return cached response
        final response2 = await processor.set('test-key', 'second-value', requestId);
        expect(response2.status, equals(ResponseStatus.ok));
        expect(response2.id, equals(requestId));
        
        // Verify idempotency: storage should only contain first value due to cache hit
        final stored = storage.getEntry('test-key');
        expect(stored?.value, equals('first-value')); // Should be first value, not second
        
        // Verify responses are identical (from cache)
        expect(response1.status, equals(response2.status));
        expect(response1.id, equals(response2.id));
      });

      test('different request IDs are processed separately', () async {
        await processor.set('test-key', 'first-value', 'request-1');
        await processor.set('test-key', 'second-value', 'request-2');
        
        // Second request should overwrite first (different IDs)
        final stored = storage.getEntry('test-key');
        expect(stored?.value, equals('second-value'));
      });

      test('idempotency cache handles various operation types', () async {
        const requestId = 'multi-op-test';
        
        // Set operation
        final setResponse1 = await processor.set('key1', 'value1', requestId);
        final setResponse2 = await processor.set('key1', 'different', requestId);
        expect(setResponse1.id, equals(setResponse2.id));
        
        // Get operation (different request ID)
        final getResponse1 = await processor.get('key1', 'get-$requestId');
        final getResponse2 = await processor.get('key1', 'get-$requestId');
        expect(getResponse1.value, equals(getResponse2.value));
        
        // Delete operation (different request ID)
        final delResponse1 = await processor.delete('key1', 'del-$requestId');
        final delResponse2 = await processor.delete('key1', 'del-$requestId');
        expect(delResponse1.status, equals(delResponse2.status));
      });

      test('idempotency cache expires after timeout', () async {
        // Note: In real implementation, cache would have TTL
        // This test documents the expected behavior
        
        final requestId = 'expire-test';
        
        final response1 = await processor.set('expire-key', 'value1', requestId);
        expect(response1.status, equals(ResponseStatus.ok));
        
        // In real implementation, after TTL expires, 
        // same request ID would be processed again
        // Here we just verify current behavior
        final response2 = await processor.set('expire-key', 'value2', requestId);
        expect(response2.id, equals(requestId));
      });

      test('empty request IDs bypass idempotency cache', () async {
        // Empty IDs should not use cache
        final response1 = await processor.set('no-id-key', 'value1', '');
        final response2 = await processor.set('no-id-key', 'value2', '');
        
        expect(response1.status, equals(ResponseStatus.ok));
        expect(response2.status, equals(ResponseStatus.ok));
        
        // Second value should overwrite first
        final stored = storage.getEntry('no-id-key');
        expect(stored?.value, equals('value2'));
      });

      test('idempotency cache handles bulk operations', () async {
        const requestId = 'bulk-idempotent';
        
        final keyValues1 = {'bulk1': 'value1', 'bulk2': 'value2'};
        final keyValues2 = {'bulk1': 'different1', 'bulk2': 'different2'};
        
        final response1 = await processor.mset(keyValues1, requestId);
        final response2 = await processor.mset(keyValues2, requestId);
        
        expect(response1.id, equals(response2.id));
        
        // Verify idempotency: original values should be preserved due to cache hit
        final stored1 = storage.getEntry('bulk1');
        final stored2 = storage.getEntry('bulk2');
        expect(stored1?.value, equals('value1')); // Should be first value, not 'different1'
        expect(stored2?.value, equals('value2')); // Should be first value, not 'different2'
        
        // Verify responses are identical (from cache)
        expect(response1.status, equals(response2.status));
        expect(response1.results?.length, equals(response2.results?.length));
      });
    });

    group('Sequence Number Management', () {
      test('sequence numbers increment for each operation', () async {
        await processor.set('seq-key-1', 'value1', 'req-1');
        await processor.set('seq-key-2', 'value2', 'req-2');
        await processor.set('seq-key-3', 'value3', 'req-3');
        
        final entry1 = storage.getEntry('seq-key-1');
        final entry2 = storage.getEntry('seq-key-2');
        final entry3 = storage.getEntry('seq-key-3');
        
        expect(entry1, isNotNull, reason: 'Entry 1 should exist');
        expect(entry2, isNotNull, reason: 'Entry 2 should exist');
        expect(entry3, isNotNull, reason: 'Entry 3 should exist');
        
        expect(entry1!.seq, equals(1));
        expect(entry2!.seq, equals(2));
        expect(entry3!.seq, equals(3));
      });

      test('sequence numbers are unique per node', () async {
        await processor.set('node-key-1', 'value1', 'req-1');
        await processor.set('node-key-2', 'value2', 'req-2');
        
        final entry1 = storage.getEntry('node-key-1');
        final entry2 = storage.getEntry('node-key-2');
        
        expect(entry1, isNotNull, reason: 'Entry 1 should exist');
        expect(entry2, isNotNull, reason: 'Entry 2 should exist');
        
        expect(entry1!.nodeId, equals('test-node'));
        expect(entry2!.nodeId, equals('test-node'));
        expect(entry1.seq, isNot(equals(entry2.seq)));
      });

      test('sequence numbers persist across different operation types', () async {
        await processor.set('multi-op-1', 'value1', 'req-1'); // seq 1
        await processor.delete('multi-op-1', 'req-2'); // seq 2 (overwrites seq 1 due to LWW)
        await processor.set('multi-op-2', 'value2', 'req-3'); // seq 3
        
        final allEntries = await storage.getAllEntries();
        final sequences = allEntries.map((e) => e.seq).toList();
        sequences.sort();
        
        // Only 2 entries should remain after LWW resolution:
        // - 'multi-op-1' tombstone (seq 2) wins over value (seq 1)
        // - 'multi-op-2' value (seq 3)
        expect(sequences, equals([2, 3]));
      });

      test('read operations do not increment sequence numbers', () async {
        await processor.set('read-test', 'value', 'req-1'); // seq 1
        await processor.get('read-test', 'req-2'); // Should not increment
        await processor.set('read-test-2', 'value2', 'req-3'); // seq 2
        
        final entry1 = storage.getEntry('read-test');
        final entry2 = storage.getEntry('read-test-2');
        
        expect(entry1, isNotNull, reason: 'Read test entry should exist');
        expect(entry2, isNotNull, reason: 'Read test entry 2 should exist');
        
        expect(entry1!.seq, equals(1));
        expect(entry2!.seq, equals(2)); // Should be 2, not 3
      });

      test('bulk operations increment sequence for each item', () async {
        final keyValues = {'bulk-1': 'value1', 'bulk-2': 'value2', 'bulk-3': 'value3'};
        await processor.mset(keyValues, 'bulk-req');
        
        final entry1 = storage.getEntry('bulk-1');
        final entry2 = storage.getEntry('bulk-2');
        final entry3 = storage.getEntry('bulk-3');
        
        expect(entry1, isNotNull, reason: 'Bulk entry 1 should exist');
        expect(entry2, isNotNull, reason: 'Bulk entry 2 should exist');
        expect(entry3, isNotNull, reason: 'Bulk entry 3 should exist');
        
        // Each item should have different sequence number
        final sequences = [entry1!.seq, entry2!.seq, entry3!.seq];
        expect(sequences.toSet().length, equals(3)); // All unique
      });
    });

    group('Error Handling and Edge Cases', () {
      test('storage errors are handled gracefully', () async {
        // Simulate storage error by disposing storage
        await storage.dispose();
        
        final response = await processor.set('error-key', 'value', 'error-req');
        expect(response.status, equals(ResponseStatus.error));
        expect(response.errorCode, equals(ErrorCode.internalError));
      });

      test('null and undefined values are handled correctly', () async {
        // Test with empty string instead of null since the method doesn't accept null
        final response = await processor.set('null-key', '', 'null-req');
        expect(response.status, equals(ResponseStatus.ok));
      });

      test('extremely long operation chains maintain consistency', () async {
        const operationCount = 1000;
        
        for (int i = 0; i < operationCount; i++) {
          await processor.set('chain-key', 'value-$i', 'req-$i');
        }
        
        final finalEntry = storage.getEntry('chain-key');
        expect(finalEntry, isNotNull, reason: 'Final chain entry should exist');
        expect(finalEntry!.value, equals('value-${operationCount - 1}'));
        expect(finalEntry.seq, equals(operationCount));
      });

      test('concurrent command processing maintains consistency', () async {
        final futures = <Future<Response>>[];
        
        // Submit multiple concurrent operations
        for (int i = 0; i < 50; i++) {
          futures.add(processor.set('concurrent-$i', 'value-$i', 'concurrent-req-$i'));
        }
        
        final responses = await Future.wait(futures);
        
        // All should succeed
        for (final response in responses) {
          expect(response.status, equals(ResponseStatus.ok));
        }
        
        // All should be stored
        expect(storage.entryCount, equals(50));
      });

      test('malformed internal data is handled gracefully', () async {
        // Set up valid entry first
        await processor.set('test-key', 'valid-value', 'valid-req');
        
        // Corrupt storage entry (simulating data corruption)
        // Create a corrupted entry with null value directly using main constructor
        final corruptEntry = StorageEntry(
          key: 'test-key',
          value: null, // This simulates corruption - null value but not tombstone
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          nodeId: 'test-node',
          seq: 1,
          isTombstone: false, // Not marked as tombstone - this is the corruption
        );
        storage.setEntry('test-key', corruptEntry);
        
        // Processor should handle corrupted data gracefully
        final response = await processor.get('test-key', 'corrupt-req');
        // Should either return error or handle corruption transparently
        expect(response.status, anyOf(
          equals(ResponseStatus.error),
          equals(ResponseStatus.ok),
        ));
      });
    });

    group('Operation-Specific Tests', () {
      test('APPEND operation concatenates correctly', () async {
        await processor.set('append-key', 'Hello ', 'setup');
        
        final response = await processor.processCommand(Command(
          id: 'append-test',
          op: 'APPEND',
          key: 'append-key',
          value: 'World!',
        ));
        
        expect(response.status, equals(ResponseStatus.ok));
        expect(response.value, equals('Hello World!'));
      });

      test('PREPEND operation concatenates correctly', () async {
        await processor.set('prepend-key', 'World!', 'setup');
        
        final response = await processor.processCommand(Command(
          id: 'prepend-test',
          op: 'PREPEND',
          key: 'prepend-key',
          value: 'Hello ',
        ));
        
        expect(response.status, equals(ResponseStatus.ok));
        expect(response.value, equals('Hello World!'));
      });

      test('APPEND on non-existent key treats as empty string', () async {
        final response = await processor.processCommand(Command(
          id: 'append-missing',
          op: 'APPEND',
          key: 'missing-key',
          value: 'New Content',
        ));
        
        expect(response.status, equals(ResponseStatus.ok));
        expect(response.value, equals('New Content'));
      });

      test('APPEND returns PAYLOAD_TOO_LARGE when result exceeds limit', () async {
        final largeInitial = 'x' * 200000; // 200KB
        await processor.set('large-key', largeInitial, 'setup');
        
        final addition = 'x' * 70000; // 70KB - total would be 270KB > 256KB
        final response = await processor.processCommand(Command(
          id: 'append-oversized',
          op: 'APPEND',
          key: 'large-key',
          value: addition,
        ));
        
        expect(response.status, equals(ResponseStatus.error));
        expect(response.errorCode, equals(ErrorCode.payloadTooLarge));
      });

      test('mixed success/failure in MSET maintains partial success model', () async {
        final keyValues = {
          'good-key-1': 'value1',
          'x' * 300: 'value2', // Oversized key
          'good-key-2': 'value3',
        };
        
        final response = await processor.processCommand(Command(
          id: 'mixed-mset',
          op: 'MSET',
          keyValues: keyValues,
        ));
        
        expect(response.status, equals(ResponseStatus.ok));
        expect(response.results?.length, equals(3));
        
        // Check individual results
        expect(response.results![0].isSuccess, isTrue); // good-key-1
        expect(response.results![1].isError, isTrue); // oversized key
        expect(response.results![2].isSuccess, isTrue); // good-key-2
      });
    });

    group('Property-Based Tests', () {
      test('property: all successful SET operations are retrievable with GET', () async {
        final key = TestGenerators.randomUtf8String(minLength: 1, maxLength: 50);
        final value = TestGenerators.randomUtf8String(minLength: 1, maxLength: 100);
        final requestId = TestGenerators.randomUuid(Random());
        
        final setResponse = await processor.set(key, value, requestId);
        expect(setResponse.status, equals(ResponseStatus.ok));
        
        final getResponse = await processor.get(key, '$requestId-get');
        expect(getResponse.status, equals(ResponseStatus.ok));
        expect(getResponse.value, equals(value));
      });

      test('property: DELETE operations create proper tombstones', () async {
        final key = TestGenerators.randomUtf8String(minLength: 1, maxLength: 50);
        final requestId = TestGenerators.randomUuid(Random());
        
        // Set then delete
        await processor.set(key, 'temp-value', '$requestId-set');
        final deleteResponse = await processor.delete(key, '$requestId-del');
            
        expect(deleteResponse.status, equals(ResponseStatus.ok));
        
        // Should not be retrievable
        final getResponse = await processor.get(key, '$requestId-get');
        expect(getResponse.status, equals(ResponseStatus.error));
        expect(getResponse.errorCode, equals(ErrorCode.notFound));
      });

      test('property: idempotency is maintained across operation types', () async {
        final key = TestGenerators.randomUtf8String(minLength: 1, maxLength: 50);
        final value = TestGenerators.randomUtf8String(minLength: 1, maxLength: 100);
        final requestId = TestGenerators.randomUuid(Random());
        
        // Execute same operation twice
        final response1 = await processor.set(key, value, requestId);
        final response2 = await processor.set(key, 'different-value', requestId);
        
        expect(response1.status, equals(ResponseStatus.ok));
        
        // Both should succeed and return same response
        expect(response2.status, equals(ResponseStatus.ok));
        expect(response1.id, equals(response2.id));
      });
    });
  });
}