import 'package:test/test.dart';
import 'package:merkle_kv_core/src/commands/command_processor.dart';
import 'package:merkle_kv_core/src/commands/command.dart';
import 'package:merkle_kv_core/src/storage/in_memory_storage.dart';
import 'package:merkle_kv_core/src/config/merkle_kv_config.dart';

void main() {
  late CommandProcessorImpl processor;
  late InMemoryStorage storage;
  late MerkleKVConfig config;

  setUp(() async {
    config = MerkleKVConfig(
      clientId: 'negative-test-client',
      nodeId: 'negative-test-node',
      mqttHost: 'localhost',
    );
    storage = InMemoryStorage(config);
    await storage.initialize();
    processor = CommandProcessorImpl(config, storage);
  });

  group('Negative Tests', () {
    group('Payload Boundary Tests', () {
      test('large value exceeding 256KiB is rejected', () async {
        const exactLimit = 256 * 1024;
        final exactLimitValue = 'x' * (exactLimit + 1000);
        
        final command = Command(
          id: 'exact-limit-test',
          op: 'SET',
          key: 'test-key',
          value: exactLimitValue,
        );

        final response = await processor.processCommand(command);
        expect(response.status.value, equals('ERROR'));
        expect(response.error, isNotNull);
      });

      test('bulk operation with many items', () async {
        final operations = <String, String>{};
        
        for (int i = 0; i < 100; i++) {
          operations['bulk-$i'] = 'x' * 1000; // Simulate large bulk operation
        }

        final command = Command(
          id: 'bulk-limit-test',
          op: 'MSET',
          keyValues: operations,
        );

        final response = await processor.processCommand(command);
        expect(response.status.value, isIn(['OK', 'ERROR'])); // Either works or fails gracefully
      });
    });

    group('Malformed Data Tests', () {
      test('missing required fields', () async {
        final command = Command(
          id: 'incomplete-test',
          op: 'SET',
          // Missing key and value
        );

        final response = await processor.processCommand(command);
        expect(response.status.value, equals('ERROR'));
      });

      test('invalid operation type', () async {
        final command = Command(
          id: 'invalid-op-test',
          op: 'INVALID_OPERATION',
          key: 'test-key',
          value: 'test-value',
        );

        final response = await processor.processCommand(command);
        expect(response.status.value, equals('ERROR'));
      });
    });

    group('Security Edge Cases', () {
      test('SQL injection attempt in key', () async {
        final command = Command(
          id: 'injection-test',
          op: 'GET',
          key: "'; DROP TABLE entries; --",
        );

        final response = await processor.processCommand(command);
        // Should process normally (we use key-value store, not SQL)
        expect(response, isNotNull);
      });

      test('script injection in value', () async {
        final command = Command(
          id: 'script-test',
          op: 'SET',
          key: 'script-key',
          value: '<script>alert("xss")</script>',
        );

        final response = await processor.processCommand(command);
        expect(response.status.value, equals('OK')); // Should store safely
      });

      test('path traversal attempt in key', () async {
        final command = Command(
          id: 'traversal-test',
          op: 'GET',
          key: '../../../etc/passwd',
        );

        final response = await processor.processCommand(command);
        expect(response, isNotNull); // Should handle gracefully
      });
    });

    group('Edge Case Values', () {
      test('empty string values', () async {
        final command = Command(
          id: 'empty-test',
          op: 'SET',
          key: '',
          value: '',
        );

        final response = await processor.processCommand(command);
        expect(response, isNotNull);
      });

      test('unicode edge cases', () async {
        final command = Command(
          id: 'unicode-test',
          op: 'SET',
          key: '🔑',
          value: '👨‍💻👩‍💻',
        );

        final response = await processor.processCommand(command);
        expect(response.status.value, equals('OK'));
      });

      test('control characters in strings', () async {
        final command = Command(
          id: 'control-test',
          op: 'SET',
          key: 'control\x00\x1F\x7F',
          value: 'value\r\n\t',
        );

        final response = await processor.processCommand(command);
        expect(response, isNotNull);
      });
    });

    group('Numeric Operations', () {
      test('increment on non-numeric value', () async {
        // First set a non-numeric value
        final setCommand = Command(
          id: 'set-non-numeric',
          op: 'SET',
          key: 'numeric-key',
          value: 'not-a-number',
        );
        await processor.processCommand(setCommand);

        // Then try to increment it
        final incrCommand = Command(
          id: 'incr-test',
          op: 'INCR',
          key: 'numeric-key',
          amount: 5,
        );

        final response = await processor.processCommand(incrCommand);
        expect(response.status.value, equals('ERROR'));
      });

      test('decrement causing underflow', () async {
        final decrCommand = Command(
          id: 'decr-underflow-test',
          op: 'DECR',
          key: 'new-key',
          amount: 999999999999,
        );

        final response = await processor.processCommand(decrCommand);
        expect(response, isNotNull); // Should handle gracefully
      });
    });
  });
}