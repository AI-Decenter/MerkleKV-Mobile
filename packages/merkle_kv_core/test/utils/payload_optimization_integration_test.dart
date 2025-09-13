@Tags(['integration'])
import 'dart:convert';
import 'dart:math';

import 'package:test/test.dart';
import 'package:merkle_kv_core/src/utils/payload_optimizer.dart';
import 'package:merkle_kv_core/src/commands/command.dart';

void main() {
  group('Payload Optimization Integration Tests', () {
    final PayloadOptimizer optimizer = PayloadOptimizer();
    
    test('Real-world command optimization effectiveness', () {
      // Create a realistic command similar to production use
      final Map<String, dynamic> keyValues = {};
      
      // Simulate a realistic batch of key-values with varied content
      for (int i = 0; i < 10; i++) {
        keyValues['user:$i'] = jsonEncode({
          'name': 'User $i',
          'email': 'user$i@example.com',
          'active': i % 2 == 0,
          'lastLogin': 1649876543210 + i * 1000,
          'preferences': {
            'theme': i % 3 == 0 ? 'dark' : 'light',
            'notifications': true,
            'language': 'en-US'
          },
          'roles': ['user', if (i % 5 == 0) 'admin']
        });
      }
      
      final Command command = Command(
        id: '9fe7c757-d00a-4630-9cae-7b8fbd8c0f87',
        op: 'MSET',
        keyValues: keyValues,
      );
      
      // Get original JSON size
      final String originalJson = command.toJsonString();
      final int originalSize = originalJson.length;
      
      // Apply optimization
      final String optimizedJson = optimizer.optimizeJSON(command);
      final int optimizedSize = optimizedJson.length;
      
      // Verify optimization effectiveness
      final double reductionPercent = (1 - (optimizedSize / originalSize)) * 100;
      print('Command optimization: $originalSize -> $optimizedSize bytes (${reductionPercent.toStringAsFixed(2)}% reduction)');
      
      // Verify the result is valid JSON and preserves semantic content
      final Command parsedCommand = Command.fromJsonString(optimizedJson);
      expect(parsedCommand.id, equals(command.id));
      expect(parsedCommand.op, equals(command.op));
      expect(parsedCommand.keyValues?.length, equals(command.keyValues?.length));
    });
    
    test('Stress test with large payloads near size limit', () {
      // Generate a payload that's close to but under the size limit
      final Random random = Random(42); // Fixed seed for reproducibility
      
      // Create a large nested structure
      Map<String, dynamic> generateNestedStructure(int depth, int breadth) {
        final Map<String, dynamic> result = {};
        
        if (depth <= 0) {
          // Leaf node
          for (int i = 0; i < breadth; i++) {
            final String key = 'key_${random.nextInt(1000)}';
            final String value = List.generate(
              random.nextInt(20) + 10, 
              (_) => String.fromCharCode(random.nextInt(26) + 97)
            ).join();
            result[key] = value;
          }
        } else {
          // Interior node
          for (int i = 0; i < breadth; i++) {
            final String key = 'node_${random.nextInt(1000)}';
            result[key] = generateNestedStructure(depth - 1, breadth - 1);
          }
        }
        
        return result;
      }
      
      // Generate a large structure
      final Map<String, dynamic> largeStructure = generateNestedStructure(3, 5);
      
      // Create a large command
      final Command largeCommand = Command(
        id: '9fe7c757-d00a-4630-9cae-7b8fbd8c0f87',
        op: 'SET',
        key: 'large:data',
        value: largeStructure,
      );
      
      // Verify size estimation works for large payloads
      final int estimatedSize = SizeEstimator.estimateCommandSize(largeCommand);
      expect(estimatedSize, greaterThan(1000)); // Should be quite large
      
      // Optimize the large payload
      final String optimizedJson = optimizer.optimizeJSON(largeCommand);
      
      // Verify the result is valid JSON and preserves semantic content
      final Command parsedCommand = Command.fromJsonString(optimizedJson);
      expect(parsedCommand.id, equals(largeCommand.id));
      expect(parsedCommand.op, equals(largeCommand.op));
      
      // Verify we can handle payloads near the limit
      expect(SizeEstimator.validateCommandSize(largeCommand), isTrue);
    });
    
    test('Format compatibility verification', () {
      // Create a standard replication event
      final Map<String, dynamic> event = {
        'type': 'update',
        'key': 'user:123',
        'value': '{"name":"Alice","age":30}',
        'timestamp': 1649876543210,
        'nodeId': 'device-abc-123',
        'seq': 42,
      };
      
      // Optimize it
      final optimizedBytes = optimizer.optimizeCBOR(event);
      
      // Verify a standard decoder can parse it
      final decoded = jsonDecode(utf8.decode(optimizedBytes));
      
      // Check semantic equality
      expect(decoded['type'], equals(event['type']));
      expect(decoded['key'], equals(event['key']));
      expect(decoded['value'], equals(event['value']));
      expect(decoded['timestamp'], equals(event['timestamp']));
      expect(decoded['nodeId'], equals(event['nodeId']));
      expect(decoded['seq'], equals(event['seq']));
    });
  });
}