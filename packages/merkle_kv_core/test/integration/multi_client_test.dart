import 'dart:async';
import 'package:test/test.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';

import 'test_config.dart';
import '../utils/test_broker_helper.dart';

void main() {
  group('Basic Multi-Client Tests', () {
    setUpAll(() async {
      await TestBrokerHelper.ensureBroker(port: IntegrationTestConfig.mosquittoPort);
    });
    
    test('Multiple storage instances operate independently', () async {
      final config1 = TestConfigurations.mosquittoBasic(
        clientId: 'multi-client-1',
        nodeId: 'multi-node-1',
      );
      
      final config2 = TestConfigurations.mosquittoBasic(
        clientId: 'multi-client-2', 
        nodeId: 'multi-node-2',
      );
      
      final storage1 = InMemoryStorage(config1);
      final storage2 = InMemoryStorage(config2);
      
      await storage1.initialize();
      await storage2.initialize();
      
      final processor1 = CommandProcessorImpl(config1, storage1);
      final processor2 = CommandProcessorImpl(config2, storage2);
      
      // Set different values in each storage
      await processor1.set('shared-key', 'value-from-client-1', 'cmd-1');
      await processor2.set('shared-key', 'value-from-client-2', 'cmd-2');
      
      // Verify each storage has its own value
      final response1 = await processor1.get('shared-key', 'cmd-3');
      final response2 = await processor2.get('shared-key', 'cmd-4');
      
      expect(response1.status, equals(ResponseStatus.ok));
      expect(response1.value, equals('value-from-client-1'));
      
      expect(response2.status, equals(ResponseStatus.ok));
      expect(response2.value, equals('value-from-client-2'));
    });

    test('Multiple MQTT clients can connect simultaneously', () async {
      final config1 = TestConfigurations.mosquittoBasic(
        clientId: 'mqtt-client-1',
        nodeId: 'mqtt-node-1',
      );
      
      final config2 = TestConfigurations.mosquittoBasic(
        clientId: 'mqtt-client-2',
        nodeId: 'mqtt-node-2',
      );
      
      final mqttClient1 = MqttClientImpl(config1);
      final mqttClient2 = MqttClientImpl(config2);
      
      try {
        // Connect both clients
        await mqttClient1.connect();
        await mqttClient2.connect();
        
        // Wait for connections to establish
        await Future.delayed(Duration(milliseconds: 200));
        
        // Test that both can publish
        await mqttClient1.publish('test/topic1', 'message from client 1');
        await mqttClient2.publish('test/topic2', 'message from client 2');
        
        // Both clients should be able to disconnect
        await mqttClient1.disconnect();
        await mqttClient2.disconnect();
        
      } catch (e) {
        // Ensure cleanup in case of failure
        try { await mqttClient1.disconnect(); } catch (_) {}
        try { await mqttClient2.disconnect(); } catch (_) {}
        rethrow;
      }
    });

    test('Topic routers work with multiple clients', () async {
      final config1 = TestConfigurations.mosquittoBasic(
        clientId: 'router-client-1',
        nodeId: 'router-node-1', 
      ).copyWith(replicationCanPublishEvents: true);
      
      final config2 = TestConfigurations.mosquittoBasic(
        clientId: 'router-client-2',
        nodeId: 'router-node-2',
      ).copyWith(replicationCanPublishEvents: true);
      
      final mqttClient1 = MqttClientImpl(config1);
      final mqttClient2 = MqttClientImpl(config2);
      
      final topicRouter1 = TopicRouterImpl(config1, mqttClient1);
      final topicRouter2 = TopicRouterImpl(config2, mqttClient2);
      
      try {
        await mqttClient1.connect();
        await mqttClient2.connect();
        
        await Future.delayed(Duration(milliseconds: 200));
        
        // Test that routers can publish to their respective topics
        await topicRouter1.publishResponse('{"from": "client-1"}');
        await topicRouter2.publishResponse('{"from": "client-2"}');
        
        await topicRouter1.publishReplication('{"replication": "from-client-1"}');
        await topicRouter2.publishReplication('{"replication": "from-client-2"}');
        
        await mqttClient1.disconnect();
        await mqttClient2.disconnect();
        
      } finally {
        await topicRouter1.dispose();
        await topicRouter2.dispose();
      }
    });

    test('Command processors handle concurrent operations', () async {
      final config = TestConfigurations.mosquittoBasic(
        clientId: 'concurrent-client',
        nodeId: 'concurrent-node',
      );
      
      final storage = InMemoryStorage(config);
      await storage.initialize();
      final processor = CommandProcessorImpl(config, storage);
      
      // Execute multiple SET operations concurrently
      final futures = <Future<Response>>[];
      for (int i = 0; i < 10; i++) {
        futures.add(processor.set('key-$i', 'value-$i', 'cmd-$i'));
      }
      
      final responses = await Future.wait(futures);
      
      // All operations should succeed
      for (int i = 0; i < responses.length; i++) {
        expect(responses[i].status, equals(ResponseStatus.ok));
        expect(responses[i].id, equals('cmd-$i'));
      }
      
      // Verify all values were stored
      for (int i = 0; i < 10; i++) {
        final getResponse = await processor.get('key-$i', 'get-cmd-$i');
        expect(getResponse.status, equals(ResponseStatus.ok));
        expect(getResponse.value, equals('value-$i'));
      }
    });

    test('Error handling across multiple operations', () async {
      final config = TestConfigurations.mosquittoBasic(
        clientId: 'error-test-client',
        nodeId: 'error-test-node',
      );
      
      final storage = InMemoryStorage(config);
      await storage.initialize();
      final processor = CommandProcessorImpl(config, storage);
      
      // Test GET on non-existent keys
      final getResponse1 = await processor.get('nonexistent-1', 'cmd-1');
      final getResponse2 = await processor.get('nonexistent-2', 'cmd-2');
      
      expect(getResponse1.status, equals(ResponseStatus.error));
      expect(getResponse2.status, equals(ResponseStatus.error));
      
      // Test that valid operations still work
      final setResponse = await processor.set('valid-key', 'valid-value', 'cmd-3');
      expect(setResponse.status, equals(ResponseStatus.ok));
      
      final getResponse3 = await processor.get('valid-key', 'cmd-4');
      expect(getResponse3.status, equals(ResponseStatus.ok));
      expect(getResponse3.value, equals('valid-value'));
    });
  });
}