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
      clientId: 'processor-test-client',
      nodeId: 'processor-test-node',
      mqttHost: 'localhost',
    );
    storage = InMemoryStorage(config);
    await storage.initialize();
    processor = CommandProcessorImpl(config, storage);
  });

  group('Command Processor Tests', () {
    group('JSON Validation', () {
      test('valid SET command processes successfully', () async {
        final command = Command(
          id: 'test-id',
          op: 'SET',
          key: 'test-key',
          value: 'test-value',
        );

        final response = await processor.processCommand(command);
        expect(response.status.value, equals('OK'));
        expect(response.id, equals('test-id'));
      });

      test('invalid operation returns error', () async {
        final command = Command(
          id: 'test-id',
          op: 'INVALID_OP',
          key: 'test-key',
        );

        final response = await processor.processCommand(command);
        expect(response.status.value, equals('ERROR'));
        expect(response.error, isNotNull);
      });
    });

    group('Payload Size Limits', () {
      test('large value exceeding 256KiB is rejected', () async {
        const maxSize = 256 * 1024;
        final largeValue = 'x' * (maxSize + 1000);
        
        final command = Command(
          id: 'large-value-test',
          op: 'SET',
          key: 'test-key',
          value: largeValue,
        );

        final response = await processor.processCommand(command);
        expect(response.status.value, equals('ERROR'));
        expect(response.error, isNotNull);
      });

      test('reasonable size value is accepted', () async {
        final normalValue = 'x' * 1000; // 1KB value
        
        final command = Command(
          id: 'normal-value-test',
          op: 'SET',
          key: 'test-key',
          value: normalValue,
        );

        final response = await processor.processCommand(command);
        expect(response.status.value, equals('OK'));
      });
    });

    group('Idempotency', () {
      test('duplicate command ID returns cached response', () async {
        final command = Command(
          id: 'idempotent-test',
          op: 'SET',
          key: 'test-key',
          value: 'test-value',
        );

        // First request
        final response1 = await processor.processCommand(command);
        expect(response1.status.value, equals('OK'));

        // Second request with same ID should return cached response
        final response2 = await processor.processCommand(command);
        expect(response2.status.value, equals('OK'));
        expect(response2.id, equals('idempotent-test'));
      });
    });

    group('GET Operations', () {
      test('GET existing key returns value', () async {
        // First store a value
        final setCommand = Command(
          id: 'set-test',
          op: 'SET',
          key: 'get-test-key',
          value: 'stored-value',
        );
        await processor.processCommand(setCommand);

        // Then retrieve it
        final response = await processor.get('get-test-key', 'get-test-id');
        expect(response.status.value, equals('OK'));
        expect(response.value, equals('stored-value'));
      });

      test('GET non-existent key returns not found', () async {
        final response = await processor.get('missing-key', 'missing-test-id');
        expect(response.status.value, equals('ERROR'));
        expect(response.error, isNotNull);
      });
    });

    group('SET Operations', () {
      test('SET creates new entry', () async {
        final response = await processor.set('new-key', 'new-value', 'set-test-id');
        expect(response.status.value, equals('OK'));
        
        // Verify it was stored
        final getResponse = await processor.get('new-key', 'verify-id');
        expect(getResponse.value, equals('new-value'));
      });

      test('SET updates existing entry', () async {
        await processor.set('update-key', 'initial-value', 'set1-id');
        await processor.set('update-key', 'updated-value', 'set2-id');
        
        final response = await processor.get('update-key', 'get-updated-id');
        expect(response.value, equals('updated-value'));
      });
    });

    group('DELETE Operations', () {
      test('DELETE removes existing key', () async {
        await processor.set('delete-key', 'to-be-deleted', 'set-delete-id');
        
        final deleteResponse = await processor.delete('delete-key', 'delete-id');
        expect(deleteResponse.status.value, equals('OK'));
        
        final getResponse = await processor.get('delete-key', 'get-after-delete-id');
        expect(getResponse.status.value, equals('ERROR')); // Should not be found
      });

      test('DELETE on non-existent key is idempotent', () async {
        final response = await processor.delete('non-existent-key', 'delete-missing-id');
        expect(response.status.value, equals('OK')); // DELETE is idempotent
      });
    });

    group('Error Handling', () {
      test('missing required key parameter', () async {
        final command = Command(
          id: 'missing-key-test',
          op: 'GET',
          // Missing key parameter
        );

        final response = await processor.processCommand(command);
        expect(response.status.value, equals('ERROR'));
        expect(response.error, isNotNull);
      });

      test('empty command ID is handled', () async {
        final command = Command(
          id: '',
          op: 'SET',
          key: 'test-key',
          value: 'test-value',
        );

        final response = await processor.processCommand(command);
        expect(response, isNotNull); // Should not throw
      });
    });
  });
}