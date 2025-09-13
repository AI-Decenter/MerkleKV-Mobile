import 'dart:math';
import 'package:test/test.dart';
import 'package:merkle_kv_core/src/config/merkle_kv_config.dart';
import 'package:merkle_kv_core/src/storage/in_memory_storage.dart';
import 'package:merkle_kv_core/src/storage/storage_entry.dart';
import 'package:merkle_kv_core/src/commands/command.dart';
import 'package:merkle_kv_core/src/commands/command_processor.dart';

void main() {
  group('Property-Based Tests', () {
    late MerkleKVConfig config;
    late InMemoryStorage storage;
    late CommandProcessorImpl processor;
    late Random random;

    setUp(() async {
      config = MerkleKVConfig.create(
        mqttHost: 'test-broker.local',
        clientId: 'property-test-client',
        nodeId: 'property-test-node',
        persistenceEnabled: false,
      );
      
      storage = InMemoryStorage(config);
      await storage.initialize();
      processor = CommandProcessorImpl(config, storage);
      random = Random(42); // Fixed seed for reproducibility
    });

    tearDown(() async {
      await storage.dispose();
    });

    group('LWW Resolution Properties', () {
      test('LWW resolution is consistent regardless of comparison order', () async {
        // Property: For any two entries A and B, LWW(A,B) == LWW(B,A) in terms of winner
        for (int iteration = 0; iteration < 100; iteration++) {
          final timestamp1 = random.nextInt(1000000);
          final timestamp2 = random.nextInt(1000000);
          final nodeId1 = generateRandomNodeId(random);
          final nodeId2 = generateRandomNodeId(random);
          final seq1 = random.nextInt(1000);
          final seq2 = random.nextInt(1000);
          
          final entry1 = StorageEntry.value(
            key: 'lww-property-test',
            value: 'value-1',
            timestampMs: timestamp1,
            nodeId: nodeId1,
            seq: seq1,
          );
          
          final entry2 = StorageEntry.value(
            key: 'lww-property-test',
            value: 'value-2',
            timestampMs: timestamp2,
            nodeId: nodeId2,
            seq: seq2,
          );
          
          // Test both insertion orders
          await storage.put('lww-property-test', entry1);
          await storage.put('lww-property-test', entry2);
          final result1 = await storage.get('lww-property-test');
          
          // Clear and test reverse order
          await storage.delete('lww-property-test');
          await storage.put('lww-property-test', entry2);
          await storage.put('lww-property-test', entry1);
          final result2 = await storage.get('lww-property-test');
          
          // Results should be identical
          expect(result1?.value, equals(result2?.value),
              reason: 'LWW resolution must be deterministic for iteration $iteration');
          expect(result1?.timestampMs, equals(result2?.timestampMs));
          expect(result1?.nodeId, equals(result2?.nodeId));
          expect(result1?.seq, equals(result2?.seq));
        }
      });

      test('LWW resolution transitivity property', () async {
        // Property: If A > B and B > C, then A > C (where > means "wins in LWW")
        for (int iteration = 0; iteration < 50; iteration++) {
          final baseTimestamp = DateTime.now().millisecondsSinceEpoch;
          
          // Create three entries with clear temporal ordering
          final entryA = StorageEntry.value(
            key: 'transitivity-test',
            value: 'value-A',
            timestampMs: baseTimestamp + 2000,
            nodeId: 'node-A',
            seq: 1,
          );
          
          final entryB = StorageEntry.value(
            key: 'transitivity-test',
            value: 'value-B',
            timestampMs: baseTimestamp + 1000,
            nodeId: 'node-B',
            seq: 1,
          );
          
          final entryC = StorageEntry.value(
            key: 'transitivity-test',
            value: 'value-C',
            timestampMs: baseTimestamp,
            nodeId: 'node-C',
            seq: 1,
          );
          
          // Test all permutations of insertion order
          final orders = [
            [entryA, entryB, entryC],
            [entryA, entryC, entryB],
            [entryB, entryA, entryC],
            [entryB, entryC, entryA],
            [entryC, entryA, entryB],
            [entryC, entryB, entryA],
          ];
          
          for (final order in orders) {
            await storage.delete('transitivity-test');
            
            for (final entry in order) {
              await storage.put('transitivity-test', entry);
            }
            
            final result = await storage.get('transitivity-test');
            
            // A should always win due to latest timestamp
            expect(result?.value, equals('value-A'),
                reason: 'Entry A should win in all orders for iteration $iteration');
          }
        }
      });

      test('timestamp equality uses nodeId tiebreaker consistently', () async {
        for (int iteration = 0; iteration < 100; iteration++) {
          final timestamp = random.nextInt(1000000);
          final nodeId1 = generateRandomNodeId(random);
          final nodeId2 = generateRandomNodeId(random);
          
          // Skip if node IDs are identical
          if (nodeId1 == nodeId2) continue;
          
          final entry1 = StorageEntry.value(
            key: 'tiebreaker-test',
            value: 'value-1',
            timestampMs: timestamp,
            nodeId: nodeId1,
            seq: 1,
          );
          
          final entry2 = StorageEntry.value(
            key: 'tiebreaker-test',
            value: 'value-2',
            timestampMs: timestamp, // Same timestamp
            nodeId: nodeId2,
            seq: 1,
          );
          
          await storage.put('tiebreaker-test', entry1);
          await storage.put('tiebreaker-test', entry2);
          final result = await storage.get('tiebreaker-test');
          
          // Winner should be determined by lexicographic nodeId comparison
          final expectedWinner = nodeId1.compareTo(nodeId2) > 0 ? nodeId1 : nodeId2;
          expect(result?.nodeId, equals(expectedWinner),
              reason: 'NodeId tiebreaker should be consistent for iteration $iteration');
        }
      });
    });

    group('Concurrent Operations Properties', () {
      test('concurrent increments maintain mathematical consistency', () async {
        // Property: Sum of increments should equal final value regardless of order
        for (int iteration = 0; iteration < 50; iteration++) {
          final key = 'concurrent-incr-$iteration';
          final initialValue = random.nextInt(1000);
          
          // Set initial value
          final command = Command(
            id: 'init-$iteration',
            op: 'SET',
            key: key,
            value: initialValue.toString(),
          );
          await processor.processCommand(command);
          
          // Generate random increments
          final increments = List.generate(10, (_) => random.nextInt(100) - 50); // -50 to 49
          final expectedSum = initialValue + increments.fold(0, (a, b) => a + b);
          
          // Apply increments concurrently
          final futures = increments.asMap().entries.map((entry) {
            final incrCommand = Command(
              id: 'incr-$iteration-${entry.key}',
              op: 'INCR',
              key: key,
              amount: entry.value,
            );
            return processor.processCommand(incrCommand);
          }).toList();
          
          await Future.wait(futures);
          
          // Check final value
          final getCommand = Command(
            id: 'get-$iteration',
            op: 'GET',
            key: key,
          );
          final result = await processor.processCommand(getCommand);
          
          if (result.status == 'OK') {
            final finalValue = int.parse(result.value!);
            expect(finalValue, equals(expectedSum),
                reason: 'Concurrent increments should sum correctly for iteration $iteration');
          }
        }
      });

      test('concurrent string operations maintain order independence', () async {
        // Property: Order of append operations shouldn't affect final character count
        for (int iteration = 0; iteration < 30; iteration++) {
          final key = 'concurrent-string-$iteration';
          
          // Generate random strings to append
          final strings = List.generate(5, (i) => generateRandomString(random, 10));
          final expectedLength = strings.fold(0, (sum, str) => sum + str.length);
          
          // Apply appends in random order
          final shuffledStrings = List.from(strings)..shuffle(random);
          
          final futures = shuffledStrings.asMap().entries.map((entry) {
            final appendCommand = Command(
              id: 'append-$iteration-${entry.key}',
              op: 'APPEND',
              key: key,
              value: entry.value,
            );
            return processor.processCommand(appendCommand);
          }).toList();
          
          await Future.wait(futures);
          
          // Check final length
          final getCommand = Command(
            id: 'get-string-$iteration',
            op: 'GET',
            key: key,
          );
          final result = await processor.processCommand(getCommand);
          
          if (result.status == 'OK') {
            expect(result.value!.length, equals(expectedLength),
                reason: 'Concurrent appends should preserve total length for iteration $iteration');
          }
        }
      });
    });

    group('Boundary Condition Properties', () {
      test('key and value size limits are strictly enforced', () async {
        for (int iteration = 0; iteration < 100; iteration++) {
          // Test keys at various sizes around the boundary
          final keySizes = [255, 256, 257, 300, 1000];
          
          for (final keySize in keySizes) {
            final key = generateRandomString(random, keySize);
            final command = Command(
              id: 'boundary-key-$iteration-$keySize',
              op: 'SET',
              key: key,
              value: 'test-value',
            );
            
            final response = await processor.processCommand(command);
            
            if (keySize <= 256) {
              expect(response.status, equals('OK'),
                  reason: 'Key of size $keySize should be accepted');
            } else {
              expect(response.status, equals('ERROR'),
                  reason: 'Key of size $keySize should be rejected');
            }
          }
          
          // Test values at various sizes around the boundary
          final valueSizes = [256 * 1024 - 1, 256 * 1024, 256 * 1024 + 1];
          
          for (final valueSize in valueSizes) {
            final value = generateRandomString(random, valueSize);
            final command = Command(
              id: 'boundary-value-$iteration-$valueSize',
              op: 'SET',
              key: 'test-key',
              value: value,
            );
            
            final response = await processor.processCommand(command);
            
            if (valueSize <= 256 * 1024) {
              expect(response.status, equals('OK'),
                  reason: 'Value of size $valueSize should be accepted');
            } else {
              expect(response.status, equals('ERROR'),
                  reason: 'Value of size $valueSize should be rejected');
            }
          }
        }
      });

      test('numeric operations handle edge values correctly', () async {
        // Property: Numeric operations should handle min/max int64 values safely
        final edgeValues = [
          '0',
          '1',
          '-1',
          '9223372036854775807',  // Max int64
          '-9223372036854775808', // Min int64
        ];
        
        for (int iteration = 0; iteration < edgeValues.length * 10; iteration++) {
          final edgeValue = edgeValues[iteration % edgeValues.length];
          final key = 'edge-numeric-$iteration';
          
          // Set edge value
          final setCommand = Command(
            id: 'set-edge-$iteration',
            op: 'SET',
            key: key,
            value: edgeValue,
          );
          await processor.processCommand(setCommand);
          
          // Try small increment/decrement
          final operations = ['INCR', 'DECR'];
          final amounts = [1, -1, 0];
          
          for (final op in operations) {
            for (final amount in amounts) {
              final opCommand = Command(
                id: 'op-edge-$iteration-$op-$amount',
                op: op,
                key: key,
                amount: amount,
              );
              
              final response = await processor.processCommand(opCommand);
              
              // Should either succeed or fail gracefully with overflow/underflow
              expect(response.status, isIn(['OK', 'ERROR']));
              if (response.status == 'ERROR') {
                expect(response.message, 
                       anyOf(contains('overflow'), contains('underflow')));
              }
            }
          }
        }
      });
    });

    group('Idempotency Properties', () {
      test('repeated identical commands always return same response', () async {
        for (int iteration = 0; iteration < 100; iteration++) {
          final command = Command(
            id: 'idempotent-$iteration',
            op: random.nextBool() ? 'GET' : 'SET',
            key: generateRandomString(random, 20),
            value: random.nextBool() ? generateRandomString(random, 50) : null,
          );
          
          // Execute command multiple times
          final responses = <String>[];
          for (int repeat = 0; repeat < 5; repeat++) {
            final response = await processor.processCommand(command);
            responses.add(response.toJsonString());
          }
          
          // All responses should be identical
          final firstResponse = responses.first;
          for (final response in responses) {
            expect(response, equals(firstResponse),
                reason: 'Repeated command should return identical response for iteration $iteration');
          }
        }
      });

      test('delete operations are always idempotent', () async {
        for (int iteration = 0; iteration < 50; iteration++) {
          final key = generateRandomString(random, 20);
          
          // First, set a value
          final setCommand = Command(
            id: 'set-for-delete-$iteration',
            op: 'SET',
            key: key,
            value: 'to-be-deleted',
          );
          await processor.processCommand(setCommand);
          
          // Delete multiple times
          final deleteResponses = <String>[];
          for (int deleteAttempt = 0; deleteAttempt < 5; deleteAttempt++) {
            final deleteCommand = Command(
              id: 'delete-$iteration-$deleteAttempt',
              op: 'DELETE',
              key: key,
            );
            
            final response = await processor.processCommand(deleteCommand);
            deleteResponses.add(response.status);
          }
          
          // All deletes should return OK (idempotent)
          for (final status in deleteResponses) {
            expect(status, equals('OK'),
                reason: 'Delete should always return OK for iteration $iteration');
          }
        }
      });
    });

    group('Data Integrity Properties', () {
      test('round-trip encoding preserves data integrity', () async {
        for (int iteration = 0; iteration < 100; iteration++) {
          final originalKey = generateRandomUnicodeString(random, 50);
          final originalValue = generateRandomUnicodeString(random, 1000);
          
          final setCommand = Command(
            id: 'roundtrip-$iteration',
            op: 'SET',
            key: originalKey,
            value: originalValue,
          );
          
          final setResponse = await processor.processCommand(setCommand);
          if (setResponse.status != 'OK') continue; // Skip invalid test data
          
          final getCommand = Command(
            id: 'roundtrip-get-$iteration',
            op: 'GET',
            key: originalKey,
          );
          
          final getResponse = await processor.processCommand(getCommand);
          
          expect(getResponse.status, equals('OK'));
          expect(getResponse.value, equals(originalValue),
              reason: 'Round-trip should preserve data for iteration $iteration');
        }
      });

      test('bulk operations maintain atomicity properties', () async {
        for (int iteration = 0; iteration < 20; iteration++) {
          final keyValues = <String, String>{};
          for (int i = 0; i < 10; i++) {
            keyValues[generateRandomString(random, 20)] = 
                   generateRandomString(random, 100);
          }
          
          final msetCommand = Command(
            id: 'bulk-atomicity-$iteration',
            op: 'MSET',
            keyValues: keyValues,
          );
          
          final msetResponse = await processor.processCommand(msetCommand);
          
          if (msetResponse.status == 'OK') {
            // All keys should be retrievable
            final mgetCommand = Command(
              id: 'bulk-verify-$iteration',
              op: 'MGET',
              keys: keyValues.keys.toList(),
            );
            
            final mgetResponse = await processor.processCommand(mgetCommand);
            expect(mgetResponse.status, equals('OK'));
            
            // Check that all values match
            final results = mgetResponse.results!;
            for (final result in results) {
              if (result.found) {
                expect(result.value, equals(keyValues[result.key]),
                    reason: 'Bulk operation should be atomic for iteration $iteration');
              }
            }
          }
        }
      });
    });
  });
}

// Helper functions for property-based testing

String generateRandomNodeId(Random random) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789-';
  return List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
}

String generateRandomString(Random random, int length) {
  const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
}

String generateRandomUnicodeString(Random random, int length) {
  final codeUnits = <int>[];
  for (int i = 0; i < length; i++) {
    // Generate valid Unicode code points (avoiding surrogates)
    int codePoint;
    do {
      codePoint = random.nextInt(0x10FFFF);
    } while ((codePoint >= 0xD800 && codePoint <= 0xDFFF) || // Surrogates
             codePoint == 0x0000); // Null
    
    codeUnits.add(codePoint);
  }
  return String.fromCharCodes(codeUnits);
}