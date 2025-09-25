import 'dart:async';
import 'package:test/test.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';
import 'package:merkle_kv_core/src/mqtt/topic_authorization.dart';

import 'test_config.dart';
import '../utils/test_broker_helper.dart';

void main() {
  group('Basic End-to-End Operations', () {
    setUpAll(() async {
      await TestBrokerHelper.ensureBroker(port: IntegrationTestConfig.mosquittoPort);
    });
    late String clientId;
    late String nodeId;

    setUp(() {
      clientId = TestDataGenerator.generateClientId('e2e_basic');
      nodeId = TestDataGenerator.generateNodeId('e2e_basic');
    });

    test('Basic storage and command processing', () async {
      final config = TestConfigurations.mosquittoBasic(
        clientId: clientId,
        nodeId: nodeId,
      );

      final storage = InMemoryStorage(config);
      await storage.initialize();
      final processor = CommandProcessorImpl(config, storage);

      // Test SET operation
      final setResponse =
          await processor.set('test-key', 'test-value', 'cmd-1');
      expect(setResponse.status, equals(ResponseStatus.ok));
      expect(setResponse.id, equals('cmd-1'));

      // Test GET operation
      final getResponse = await processor.get('test-key', 'cmd-2');
      expect(getResponse.status, equals(ResponseStatus.ok));
      expect(getResponse.value, equals('test-value'));
      expect(getResponse.id, equals('cmd-2'));

      // Test DELETE operation
      final deleteResponse = await processor.delete('test-key', 'cmd-3');
      expect(deleteResponse.status, equals(ResponseStatus.ok));
      expect(deleteResponse.id, equals('cmd-3'));

      // Test GET on deleted key
      final getResponse2 = await processor.get('test-key', 'cmd-4');
      expect(getResponse2.status, equals(ResponseStatus.error));
      expect(getResponse2.id, equals('cmd-4'));
    });

    test('MQTT client connection lifecycle', () async {
      final config = TestConfigurations.mosquittoBasic(
        clientId: clientId,
        nodeId: nodeId,
      );

      final mqttClient = MqttClientImpl(config);

      // Test connection
      await mqttClient.connect();

      // Wait for connection to establish
      await Future.delayed(Duration(milliseconds: 200));

      // Test basic publish
      await mqttClient.publish('test/topic', 'test message');

      // Test disconnection
      await mqttClient.disconnect();
    });

    test('Topic routing functionality', () async {
      final baseConfig = TestConfigurations.mosquittoBasic(
        clientId: clientId,
        nodeId: nodeId,
      );
      final config = baseConfig.copyWith(replicationCanPublishEvents: true);

      final mqttClient = MqttClientImpl(config);
      final topicRouter = TopicRouterImpl(config, mqttClient);

      try {
        await mqttClient.connect();

        // Test topic router can publish to different topics
        await topicRouter.publishCommand(
            config.clientId, '{"test": "command"}');
        await topicRouter.publishResponse('{"test": "response"}');
        await topicRouter.publishReplication('{"test": "replication"}');

        await expectLater(
          topicRouter.publishCommand(
            'target-client',
            '{"test": "unauthorized"}',
          ),
          throwsA(isA<AuthorizationException>()),
        );

        await mqttClient.disconnect();
      } finally {
        await topicRouter.dispose();
      }
    });

    test('Command creation and serialization', () async {
      // Test Command creation
      final setCommand = Command.set(
        id: 'test-cmd-1',
        key: 'test-key',
        value: 'test-value',
      );

      expect(setCommand.id, equals('test-cmd-1'));
      expect(setCommand.op, equals('SET'));
      expect(setCommand.key, equals('test-key'));
      expect(setCommand.value, equals('test-value'));

      // Test serialization
      final jsonString = setCommand.toJsonString();
      expect(jsonString, contains('test-cmd-1'));
      expect(jsonString, contains('SET'));
      expect(jsonString, contains('test-key'));
      expect(jsonString, contains('test-value'));

      // Test deserialization
      final parsedCommand = Command.fromJsonString(jsonString);
      expect(parsedCommand.id, equals(setCommand.id));
      expect(parsedCommand.op, equals(setCommand.op));
      expect(parsedCommand.key, equals(setCommand.key));
      expect(parsedCommand.value, equals(setCommand.value));
    });

    test('Response creation and validation', () async {
      // Test OK response
      final okResponse = Response.ok(
        id: 'test-response-1',
        value: 'success-value',
      );

      expect(okResponse.id, equals('test-response-1'));
      expect(okResponse.status, equals(ResponseStatus.ok));
      expect(okResponse.value, equals('success-value'));

      // Test error response
      final errorResponse = Response.error(
        id: 'test-response-2',
        error: 'Test error',
        errorCode: ErrorCode.notFound,
      );

      expect(errorResponse.id, equals('test-response-2'));
      expect(errorResponse.status, equals(ResponseStatus.error));
      expect(errorResponse.error, equals('Test error'));
      expect(errorResponse.errorCode, equals(ErrorCode.notFound));

      // Test JSON serialization
      final jsonString = okResponse.toJsonString();
      expect(jsonString, contains('test-response-1'));
      expect(jsonString, contains('OK'));

      // Test JSON deserialization
      final parsedResponse = Response.fromJsonString(jsonString);
      expect(parsedResponse.id, equals(okResponse.id));
      expect(parsedResponse.status, equals(okResponse.status));
      expect(parsedResponse.value, equals(okResponse.value));
    });
  });
}
