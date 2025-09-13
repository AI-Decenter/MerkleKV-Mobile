import 'dart:async';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:merkle_kv_core/src/config/merkle_kv_config.dart';
import 'package:merkle_kv_core/src/mqtt/mqtt_client_impl.dart';
import 'package:merkle_kv_core/src/mqtt/connection_state.dart';

// Generate mocks for external dependencies
@GenerateMocks([MqttServerClient])
import 'mqtt_client_test.mocks.dart';

void main() {
  group('MQTT Client', () {
    late MerkleKVConfig config;
    late MqttClientImpl mqttClient;
    late MockMqttServerClient mockClient;

    setUp(() {
      config = MerkleKVConfig.create(
        mqttHost: 'test-broker.local',
        clientId: 'test-client-123',
        nodeId: 'test-node',
        mqttPort: 1883,
        mqttUseTls: false,
      );
    });

    tearDown(() async {
      await mqttClient.disconnect();
    });

    group('Connection Lifecycle', () {
      test('QoS=1 must be granted by broker or connection fails', () async {
        // Create a mock that denies QoS=1
        final mockClient = MockMqttServerClient();
        
        // Mock the broker denying QoS=1 subscription
        when(mockClient.subscribe(any, MqttQos.atLeastOnce))
            .thenReturn(null); // Broker denies QoS=1
        
        // Connection should fail when QoS=1 is denied
        final completer = Completer<void>();
        
        mqttClient = MqttClientImpl(config);
        mqttClient.connectionState.listen((state) {
          if (state == ConnectionState.error) {
            completer.complete();
          }
        });
        
        // Attempt to connect and subscribe
        try {
          await mqttClient.connect();
          await mqttClient.subscribe('test/topic', (topic, message) {});
          
          // Should not reach here if QoS=1 is properly enforced
          fail('Connection should fail when broker denies QoS=1');
        } catch (e) {
          // Expected behavior - connection fails
          expect(e, isA<Exception>());
          expect(e.toString(), contains('QoS'));
        }
        
        await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => fail('Connection state should change to error'),
        );
      });

      test('TLS validation when credentials present', () async {
        final tlsConfig = MerkleKVConfig.create(
          mqttHost: 'secure-broker.local',
          clientId: 'secure-client',
          nodeId: 'secure-node',
          mqttUseTls: false, // TLS disabled but credentials provided
          username: 'testuser',
          password: 'testpass',
        );
        
        expect(
          () => MqttClientImpl(tlsConfig),
          throwsA(isA<ArgumentError>()),
          reason: 'TLS must be enforced when credentials are provided',
        );
      });

      test('validates certificate rejection on bad certificates', () async {
        final tlsConfig = MerkleKVConfig.create(
          mqttHost: 'bad-cert-broker.local',
          clientId: 'tls-client',
          nodeId: 'tls-node',
          mqttUseTls: true,
          mqttPort: 8883,
        );
        
        mqttClient = MqttClientImpl(tlsConfig);
        
        // Connection should fail with bad certificate
        expect(
          () => mqttClient.connect(),
          throwsA(isA<Exception>()),
          reason: 'Bad certificates should be rejected',
        );
      });

      test('Last Will and Testament configuration', () async {
        mqttClient = MqttClientImpl(config);
        
        // Verify LWT is properly configured
        final connectionMessage = mqttClient.getConnectionMessage();
        expect(connectionMessage, isNotNull);
        expect(connectionMessage!.willTopic, equals('${config.topicPrefix}/${config.clientId}/res'));
        expect(connectionMessage.willQos, equals(MqttQos.atLeastOnce));
        
        final lwtPayload = json.decode(connectionMessage.willMessage);
        expect(lwtPayload['status'], equals('offline'));
        expect(lwtPayload['timestamp_ms'], isA<int>());
      });
    });

    group('Reconnection Backoff', () {
      test('reconnection backoff: 1s→32s with ±20% jitter', () async {
        mqttClient = MqttClientImpl(config);
        
        final backoffTimes = <Duration>[];
        final startTime = DateTime.now();
        
        // Simulate multiple reconnection attempts
        for (int attempt = 0; attempt < 6; attempt++) {
          final backoffDuration = mqttClient.calculateBackoff(attempt);
          backoffTimes.add(backoffDuration);
        }
        
        // Verify exponential backoff: 1s, 2s, 4s, 8s, 16s, 32s
        final expectedBase = [1, 2, 4, 8, 16, 32];
        
        for (int i = 0; i < backoffTimes.length; i++) {
          final actualSeconds = backoffTimes[i].inSeconds;
          final expectedSeconds = expectedBase[i];
          
          // Allow ±20% jitter
          final minExpected = (expectedSeconds * 0.8).round();
          final maxExpected = (expectedSeconds * 1.2).round();
          
          expect(actualSeconds, greaterThanOrEqualTo(minExpected),
              reason: 'Attempt $i: backoff too short');
          expect(actualSeconds, lessThanOrEqualTo(maxExpected),
              reason: 'Attempt $i: backoff too long');
        }
        
        // Verify cap at 32 seconds
        final cappedBackoff = mqttClient.calculateBackoff(10);
        expect(cappedBackoff.inSeconds, lessThanOrEqualTo(39)); // 32s + 20% jitter
      });

      test('reset backoff on successful connection', () async {
        mqttClient = MqttClientImpl(config);
        
        // Simulate failed attempts to increase backoff
        for (int i = 0; i < 3; i++) {
          mqttClient.calculateBackoff(i);
        }
        
        // Simulate successful connection
        mqttClient.onConnectionSuccess();
        
        // Next backoff should be reset to initial value
        final resetBackoff = mqttClient.calculateBackoff(0);
        expect(resetBackoff.inSeconds, lessThanOrEqualTo(2)); // 1s + 20% jitter
      });
    });

    group('Message Handling', () {
      test('malformed MQTT packets handled gracefully', () async {
        mqttClient = MqttClientImpl(config);
        
        final errorMessages = <String>[];
        
        // Listen for error events
        mqttClient.connectionState.listen((state) {
          if (state == ConnectionState.error) {
            errorMessages.add('Connection error detected');
          }
        });
        
        // Simulate malformed packet
        final malformedData = [0xFF, 0xFE, 0xFD]; // Invalid MQTT packet
        
        expect(
          () => mqttClient.handleIncomingData(malformedData),
          returnsNormally,
          reason: 'Malformed packets should not crash the client',
        );
        
        // Client should attempt to recover
        await Future.delayed(const Duration(milliseconds: 100));
        expect(errorMessages, isNotEmpty,
            reason: 'Error should be reported for malformed packets');
      });

      test('message queue persistence during disconnection', () async {
        mqttClient = MqttClientImpl(config);
        
        // Queue messages while disconnected
        await mqttClient.publish('test/topic1', 'message1');
        await mqttClient.publish('test/topic2', 'message2');
        
        final queuedMessages = mqttClient.getQueuedMessages();
        expect(queuedMessages.length, equals(2));
        expect(queuedMessages[0].topic, equals('test/topic1'));
        expect(queuedMessages[1].topic, equals('test/topic2'));
        
        // Messages should be sent when connection is established
        await mqttClient.connect();
        
        await Future.delayed(const Duration(milliseconds: 100));
        final remainingMessages = mqttClient.getQueuedMessages();
        expect(remainingMessages, isEmpty,
            reason: 'Queued messages should be sent after connection');
      });

      test('subscription management with QoS enforcement', () async {
        mqttClient = MqttClientImpl(config);
        await mqttClient.connect();
        
        var receivedMessages = <String>[];
        
        // Subscribe with QoS=1 requirement
        await mqttClient.subscribe('test/qos1', (topic, message) {
          receivedMessages.add(message);
        });
        
        // Verify subscription uses QoS=1
        final subscriptions = mqttClient.getActiveSubscriptions();
        expect(subscriptions.containsKey('test/qos1'), isTrue);
        
        // Simulate message delivery
        await mqttClient.simulateMessageReceived('test/qos1', 'test-message');
        
        await Future.delayed(const Duration(milliseconds: 50));
        expect(receivedMessages, contains('test-message'));
      });
    });

    group('Error Handling', () {
      test('network failure recovery', () async {
        mqttClient = MqttClientImpl(config);
        
        final connectionStates = <ConnectionState>[];
        mqttClient.connectionState.listen((state) {
          connectionStates.add(state);
        });
        
        // Simulate connection
        await mqttClient.connect();
        expect(connectionStates, contains(ConnectionState.connected));
        
        // Simulate network failure
        mqttClient.simulateNetworkFailure();
        
        await Future.delayed(const Duration(milliseconds: 100));
        expect(connectionStates, contains(ConnectionState.disconnected));
        
        // Should attempt automatic reconnection
        await Future.delayed(const Duration(seconds: 2));
        expect(connectionStates, contains(ConnectionState.connecting),
            reason: 'Should attempt reconnection after network failure');
      });

      test('broker timeout handling', () async {
        mqttClient = MqttClientImpl(config);
        
        final timeoutOccurred = Completer<bool>();
        
        mqttClient.connectionState.listen((state) {
          if (state == ConnectionState.error) {
            timeoutOccurred.complete(true);
          }
        });
        
        // Simulate broker timeout
        mqttClient.simulateBrokerTimeout();
        
        final didTimeout = await timeoutOccurred.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => false,
        );
        
        expect(didTimeout, isTrue,
            reason: 'Broker timeout should trigger error state');
      });

      test('QoS downgrade rejection', () async {
        mqttClient = MqttClientImpl(config);
        await mqttClient.connect();
        
        // Mock broker attempting to downgrade QoS from 1 to 0
        expect(
          () => mqttClient.handleQosDowngrade('test/topic', MqttQos.atMostOnce),
          throwsA(isA<Exception>()),
          reason: 'QoS downgrades should be rejected',
        );
      });
    });

    group('Performance and Reliability', () {
      test('connection establishment time limit', () async {
        final slowConfig = MerkleKVConfig.create(
          mqttHost: 'slow-broker.local', // Non-existent host
          clientId: 'timeout-client',
          nodeId: 'timeout-node',
          connectionTimeoutSeconds: 2,
        );
        
        mqttClient = MqttClientImpl(slowConfig);
        
        final startTime = DateTime.now();
        
        try {
          await mqttClient.connect();
          fail('Connection should timeout');
        } catch (e) {
          final elapsed = DateTime.now().difference(startTime);
          expect(elapsed.inSeconds, lessThanOrEqualTo(3),
              reason: 'Connection should timeout within configured limit');
        }
      });

      test('keep-alive mechanism validation', () async {
        final keepAliveConfig = MerkleKVConfig.create(
          mqttHost: 'test-broker.local',
          clientId: 'keepalive-client',
          nodeId: 'keepalive-node',
          keepAliveSeconds: 30,
        );
        
        mqttClient = MqttClientImpl(keepAliveConfig);
        await mqttClient.connect();
        
        // Verify keep-alive setting
        expect(mqttClient.getKeepAlivePeriod(), equals(30));
        
        // Simulate keep-alive timeout
        mqttClient.simulateKeepAliveTimeout();
        
        await Future.delayed(const Duration(milliseconds: 100));
        
        final connectionStates = <ConnectionState>[];
        mqttClient.connectionState.listen((state) {
          connectionStates.add(state);
        });
        
        // Should trigger reconnection
        await Future.delayed(const Duration(seconds: 1));
        expect(connectionStates, contains(ConnectionState.connecting),
            reason: 'Keep-alive timeout should trigger reconnection');
      });
    });

    group('Security Validation', () {
      test('credential handling security', () async {
        final secureConfig = MerkleKVConfig.create(
          mqttHost: 'secure-broker.local',
          clientId: 'secure-client',
          nodeId: 'secure-node',
          mqttUseTls: true,
          username: 'secure-user',
          password: 'secure-password',
        );
        
        mqttClient = MqttClientImpl(secureConfig);
        
        // Verify credentials are not logged
        final logOutput = mqttClient.getDebugInfo();
        expect(logOutput, isNot(contains('secure-password')),
            reason: 'Passwords should not appear in logs');
        expect(logOutput, isNot(contains('secure-user')),
            reason: 'Usernames should not appear in logs');
      });

      test('TLS certificate validation strictness', () async {
        final strictTlsConfig = MerkleKVConfig.create(
          mqttHost: 'self-signed-broker.local',
          clientId: 'strict-client',
          nodeId: 'strict-node',
          mqttUseTls: true,
          validateCertificates: true,
        );
        
        mqttClient = MqttClientImpl(strictTlsConfig);
        
        // Should reject self-signed certificates by default
        expect(
          () => mqttClient.connect(),
          throwsA(isA<Exception>()),
          reason: 'Self-signed certificates should be rejected in strict mode',
        );
      });
    });
  });
}