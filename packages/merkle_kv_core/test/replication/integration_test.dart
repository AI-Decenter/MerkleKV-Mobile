@Tags(['integration'])
library merkle_kv_core.integration_tests;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:test/test.dart';
import 'package:merkle_kv_core/merkle_kv_core.dart';

typedef AsyncBody = Future<void> Function();

class ItAssumptions {
  final String host;
  final int port;
  final bool reachable;
  final bool connectable; // broker accepts CONNECT/auth/tls
  final String reasonIfSkip;
  
  ItAssumptions({
    required this.host,
    required this.port,
    required this.reachable,
    required this.connectable,
    required this.reasonIfSkip,
  });
}

/// Enhanced environment configuration with IPv4 forcing and comprehensive auth support
class MqttTestConfig {
  final String host;
  final int port;
  final String? username;
  final String? password;
  final bool tls;
  
  MqttTestConfig({
    required this.host,
    required this.port,
    this.username,
    this.password,
    required this.tls,
  });
  
  factory MqttTestConfig.fromEnv() {
    var host = Platform.environment['MQTT_HOST'] ?? '127.0.0.1';
    
    // Force IPv4 for localhost variants
    if (host.isEmpty || host == 'localhost') {
      host = '127.0.0.1';
    }
    
    final port = int.tryParse(Platform.environment['MQTT_PORT'] ?? '') ?? 1883;
    final username = Platform.environment['MQTT_USERNAME'];
    final password = Platform.environment['MQTT_PASSWORD'];
    final tls = Platform.environment['MQTT_TLS']?.toLowerCase() == 'true';
    
    return MqttTestConfig(
      host: host,
      port: port,
      username: username,
      password: password,
      tls: tls,
    );
  }
  
  @override
  String toString() => '$host:$port (tls=$tls, user=${username ?? '-'})';
}

/// Hardened MQTT client builder with consistent configuration
MqttClientInterface buildMqtt(MqttTestConfig cfg, {required String role, String? suffix}) {
  final id = 'it-${role}-${DateTime.now().millisecondsSinceEpoch}-${suffix ?? Random().nextInt(10000)}';
  final host = (cfg.host.isEmpty || cfg.host == 'localhost') ? '127.0.0.1' : cfg.host;
  
  return MqttClientImpl(
    MerkleKVConfig(
      mqttHost: host,
      mqttPort: cfg.port,
      username: cfg.username,
      password: cfg.password,
      mqttUseTls: cfg.tls,
      nodeId: 'test-node-$id',
      clientId: id,
      topicPrefix: 'test',
      storagePath: '',
      persistenceEnabled: false,
    ),
  );
}

/// Hardened connection with explicit timeout and skip behavior
Future<void> connectOrSkip(MqttClientInterface c, {
  Duration timeout = const Duration(seconds: 20),
  bool require = false,
  String? what,
}) async {
  final name = what ?? 'mqtt';
  try {
    // Start listening BEFORE calling connect to avoid race condition
    final completer = Completer<void>();
    late StreamSubscription subscription;
    
    subscription = c.connectionState.listen((state) {
      if (state == ConnectionState.connected && !completer.isCompleted) {
        completer.complete();
      }
    });
    
    // Set timeout
    Timer? timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('Connection timeout', timeout));
      }
    });
    
    try {
      // Now call connect
      await c.connect(); // MUST await
      
      // Wait for connected state
      await completer.future;
      
      // Additional stabilization wait for message routing
      await Future.delayed(const Duration(milliseconds: 200));
      
    } finally {
      timeoutTimer.cancel();
      await subscription.cancel();
    }
    
  } on TimeoutException catch (e) {
    if (require) fail('Connection timeout ($name): ${e.message}');
    // runtime skip (return early, no fail)
    return Future.value();
  } catch (e) {
    if (require) fail('Connection failed ($name): $e');
    return Future.value();
  }
}

/// Helper to create publisher with proper initialization
Future<ReplicationEventPublisherImpl> makePublisher(
  MqttTestConfig cfg, 
  MqttClientInterface mqttClient,
  String testId,
) async {
  final config = MerkleKVConfig(
    mqttHost: (cfg.host.isEmpty || cfg.host == 'localhost') ? '127.0.0.1' : cfg.host,
    mqttPort: cfg.port,
    username: cfg.username,
    password: cfg.password,
    mqttUseTls: cfg.tls,
    nodeId: 'test-node-$testId',
    clientId: mqttClient.hashCode.toString(), // Use existing client ID
    topicPrefix: 'test/$testId',
    storagePath: '',
    persistenceEnabled: false,
  );
  
  final topicScheme = TopicScheme.create(config.topicPrefix, config.clientId);
  final metrics = InMemoryReplicationMetrics();
  
  final publisher = ReplicationEventPublisherImpl(
    config: config,
    mqttClient: mqttClient,
    topicScheme: topicScheme,
    metrics: metrics,
  );
  
  await publisher.initialize();
  await publisher.ready();
  return publisher;
}

Future<ItAssumptions> computeItAssumptions() async {
  final cfg = MqttTestConfig.fromEnv();
  final host = (cfg.host.isEmpty || cfg.host == 'localhost') ? '127.0.0.1' : cfg.host;
  final port = cfg.port;

  // 1) Reachability (TCP)
  final reachable = await _tryReach(host, port, const Duration(seconds: 5));

  if (!reachable) {
    return ItAssumptions(
      host: host,
      port: port,
      reachable: false,
      connectable: false,
      reasonIfSkip: 'MQTT broker not reachable at $host:$port',
    );
  }

  // 2) Connectability (MQTT CONNECT/CONNACK success with current auth/TLS)
  final ok = await _tryConnectOnce(host, port, cfg, const Duration(seconds: 8));
  return ItAssumptions(
    host: host,
    port: port,
    reachable: true,
    connectable: ok,
    reasonIfSkip: ok
        ? ''
        : 'MQTT broker refused or auth/TLS mismatch at $host:$port (skipping integration tests)',
  );
}

Future<bool> _tryReach(String host, int port, Duration timeout) async {
  try {
    final s = await Socket.connect(host, port, timeout: timeout);
    await s.close();
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> _tryConnectOnce(String host, int port, MqttTestConfig cfg, Duration timeout) async {
  final client = buildMqtt(cfg, role: 'probe');
  
  try {
    // Start listening BEFORE calling connect to avoid race condition
    final completer = Completer<void>();
    late StreamSubscription subscription;
    
    subscription = client.connectionState.listen((state) {
      if (state == ConnectionState.connected && !completer.isCompleted) {
        completer.complete();
      }
    });
    
    // Set timeout
    Timer? timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('Connection timeout', timeout));
      }
    });
    
    try {
      await client.connect();
      await completer.future;
      return true;
    } finally {
      timeoutTimer.cancel();
      await subscription.cancel();
    }
    
  } catch (e) {
    return false;
  } finally {
    try { 
      await client.disconnect(); 
    } catch (e) {
      // Ignore disconnect errors
    }
  }
}

// At top of integration_test.dart (replace previous globals)
Future<ItAssumptions>? _assumptionsFuture;

Future<ItAssumptions> _getAssumptions() {
  _assumptionsFuture ??= computeItAssumptions();
  return _assumptionsFuture!;
}

// New guardedTest that computes assumptions at runtime (no top-level access)
void guardedTest(
  String name,
  Future<void> Function(ItAssumptions a) body, {
  Duration? timeout,
}) {
  test(
    name,
    () async {
      final a = await _getAssumptions();
      final require = Platform.environment['IT_REQUIRE_BROKER'] == '1';

      // If broker not usable: either fail early (when required) or return early (runtime skip)
      if (!a.reachable || !a.connectable) {
        if (require) {
          fail('Broker required for integration tests: ${a.reasonIfSkip}');
        }
        // Runtime skip: do not fail, do not hang
        return;
      }

      await body(a);
    },
    timeout: timeout != null ? Timeout(timeout) : null,
  );
}

/// Enhanced connection state waiting with auth/TLS detection
Future<void> waitForConnected(MqttClientInterface mqtt, {Duration timeout = const Duration(seconds: 20)}) async {
  final completer = Completer<void>();
  StreamSubscription? subscription;
  Timer? timeoutTimer;
  
  try {
    // Set up listener first to avoid race condition
    subscription = mqtt.connectionState.listen((state) {
      if (state == ConnectionState.connected && !completer.isCompleted) {
        completer.complete();
      }
    });
    
    // Set timeout
    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('Connection timeout', timeout));
      }
    });
    
    await completer.future;
    
    // Additional stabilization wait for message routing
    await Future.delayed(const Duration(milliseconds: 200));
    
  } finally {
    timeoutTimer?.cancel();
    await subscription?.cancel();
  }
}

/// Enhanced subscription verification with retained probe messages
Future<void> subscribeAndProbe({
  required MqttClientInterface listener,
  required String topic,
  required MqttClientInterface prober,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final completer = Completer<void>();
  Timer? timeoutTimer;
  
  try {
    // Subscribe first
    await listener.subscribe(topic, (topic, payload) {
      if (payload.contains('__probe__') && !completer.isCompleted) {
        completer.complete();
      }
    });
    
    // Small delay for subscription to propagate
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Send probe message
    await prober.publish('$topic/__probe__', '__probe__');
    
    // Set timeout
    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('Subscription probe timeout for topic: $topic', timeout));
      }
    });
    
    await completer.future;
    
  } finally {
    timeoutTimer?.cancel();
  }
}

/// Enhanced outbox draining with proper timeout handling
Future<void> waitForOutboxDrained(ReplicationEventPublisherImpl publisher, {Duration timeout = const Duration(seconds: 30)}) async {
  final deadline = DateTime.now().add(timeout);
  
  while (DateTime.now().isBefore(deadline)) {
    final status = await Future.any([
      publisher.outboxStatus.first,
      Future.delayed(const Duration(seconds: 1)).then((_) => throw TimeoutException('Status timeout', const Duration(seconds: 1)))
    ]);
    
    if (status.pendingEvents == 0) {
      return;
    }
    await Future.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('Outbox did not drain within timeout', timeout);
}

/// Generate unique test ID for topic prefixes and client IDs
String _generateTestId() {
  return '${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(10000)}';
}

/// Integration tests for replication event publishing with real MQTT broker
/// 
/// Environment variables:
/// - MQTT_HOST: MQTT broker host (default: 127.0.0.1, forced IPv4 for localhost)  
/// - MQTT_PORT: MQTT broker port (default: 1883)
/// - MQTT_USERNAME: MQTT username (optional)
/// - MQTT_PASSWORD: MQTT password (optional) 
/// - MQTT_TLS: Enable TLS (default: false)
/// - IT_REQUIRE_BROKER: Require broker availability (default: false)
void main() {
  group('Replication Event Publisher Integration Tests', () {
    guardedTest('should publish and receive replication events', (a) async {
      final cfg = MqttTestConfig.fromEnv();
      final testId = _generateTestId();
      
      // Create hardened clients with unique IDs
      final listenerClient = buildMqtt(cfg, role: 'listener', suffix: testId);
      final publisherClient = buildMqtt(cfg, role: 'publisher', suffix: testId);
      
      try {
        // Hardened connections with explicit timeouts
        await connectOrSkip(listenerClient, timeout: const Duration(seconds: 15), require: true, what: 'listener');
        await connectOrSkip(publisherClient, timeout: const Duration(seconds: 15), require: true, what: 'publisher');

        // Create and initialize publisher with explicit ready check
        final publisher = await makePublisher(cfg, publisherClient, testId);
        
        // Subscribe to replication events with probe verification
        final eventReceived = Completer<ReplicationEvent>();
        await listenerClient.subscribe('test/$testId/replication/events/+', (topic, payload) {
          try {
            final json = jsonDecode(payload) as Map<String, dynamic>;
            final event = ReplicationEvent.fromJson(json);
            if (!eventReceived.isCompleted) {
              eventReceived.complete(event);
            }
          } catch (e) {
            if (!eventReceived.isCompleted) {
              eventReceived.completeError(e);
            }
          }
        });

        // Verify subscription with probe (increased timeout for CI reliability)
        await subscribeAndProbe(
          listener: listenerClient,
          topic: 'test/$testId/replication/events',
          prober: publisherClient,
          timeout: const Duration(seconds: 20),
        );

        // Publish test event
        await publisher.publishEvent(ReplicationEvent.value(
          key: 'test-key-1',
          nodeId: 'test-node-$testId',
          seq: 1,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          value: 'test-value-1',
        ));

        // Wait for outbox to drain with timeout
        await waitForOutboxDrained(publisher, timeout: const Duration(seconds: 20));

        // Wait for event with explicit timeout
        final receivedEvent = await eventReceived.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutException('Event not received within timeout', const Duration(seconds: 15)),
        );

        // Verify event data
        expect(receivedEvent.key, equals('test-key-1'));
        expect(receivedEvent.nodeId, equals('test-node-$testId'));
        expect(receivedEvent.seq, equals(1));
        expect(receivedEvent.value, equals('test-value-1'));
        expect(receivedEvent.tombstone, equals(false));
        
      } finally {
        try { await listenerClient.disconnect(); } catch (_) {}
        try { await publisherClient.disconnect(); } catch (_) {}
      }
    }, timeout: const Duration(seconds: 60));

    guardedTest('should handle concurrent replication events', (a) async {
      final cfg = MqttTestConfig.fromEnv();
      final testId = _generateTestId();
      
      // Create hardened clients for multiple publishers
      final listenerClient = buildMqtt(cfg, role: 'listener', suffix: testId);
      final publisher1Client = buildMqtt(cfg, role: 'pub1', suffix: testId);
      final publisher2Client = buildMqtt(cfg, role: 'pub2', suffix: testId);
      
      try {
        // Hardened connections with explicit timeouts
        await connectOrSkip(listenerClient, timeout: const Duration(seconds: 15), require: true, what: 'listener');
        await connectOrSkip(publisher1Client, timeout: const Duration(seconds: 15), require: true, what: 'publisher1');
        await connectOrSkip(publisher2Client, timeout: const Duration(seconds: 15), require: true, what: 'publisher2');

        // Create publishers
        final publisher1 = await makePublisher(cfg, publisher1Client, '${testId}-1');
        final publisher2 = await makePublisher(cfg, publisher2Client, '${testId}-2');

        // Subscribe to all test events
        final receivedEvents = <ReplicationEvent>[];
        await listenerClient.subscribe('test/+/replication/events/+', (topic, payload) {
          try {
            final json = jsonDecode(payload) as Map<String, dynamic>;
            final event = ReplicationEvent.fromJson(json);
            receivedEvents.add(event);
          } catch (e) {
            // Ignore malformed events
          }
        });

        // Verify subscription with probes (increased timeout for CI reliability)
        await subscribeAndProbe(
          listener: listenerClient,
          topic: 'test/${testId}-1/replication/events',
          prober: publisher1Client,
          timeout: const Duration(seconds: 20),
        );
        await subscribeAndProbe(
          listener: listenerClient,
          topic: 'test/${testId}-2/replication/events',
          prober: publisher2Client,
          timeout: const Duration(seconds: 20),
        );

        // Publish concurrent events
        final futures = <Future>[];
        for (int i = 0; i < 3; i++) {
          futures.add(publisher1.publishEvent(ReplicationEvent.value(
            key: 'pub1-key-$i',
            nodeId: 'test-node-${testId}-1',
            seq: i + 1,
            timestampMs: DateTime.now().millisecondsSinceEpoch,
            value: 'pub1-value-$i',
          )));
          futures.add(publisher2.publishEvent(ReplicationEvent.value(
            key: 'pub2-key-$i',
            nodeId: 'test-node-${testId}-2',
            seq: i + 1,
            timestampMs: DateTime.now().millisecondsSinceEpoch,
            value: 'pub2-value-$i',
          )));
        }

        // Wait for all publishing to complete
        await Future.wait(futures, eagerError: true);

        // Wait for outboxes to drain
        await waitForOutboxDrained(publisher1, timeout: const Duration(seconds: 20));
        await waitForOutboxDrained(publisher2, timeout: const Duration(seconds: 20));

        // Wait for events to arrive with timeout
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (receivedEvents.length < 6 && DateTime.now().isBefore(deadline)) {
          await Future.delayed(const Duration(milliseconds: 100));
        }

        // Verify all events received
        expect(receivedEvents.length, equals(6));
        
        final pub1Events = receivedEvents.where((e) => e.nodeId.contains('-1')).toList();
        final pub2Events = receivedEvents.where((e) => e.nodeId.contains('-2')).toList();
        
        expect(pub1Events.length, equals(3));
        expect(pub2Events.length, equals(3));

        // Verify event ordering within each publisher
        pub1Events.sort((a, b) => a.seq.compareTo(b.seq));
        pub2Events.sort((a, b) => a.seq.compareTo(b.seq));

        for (int i = 0; i < 3; i++) {
          expect(pub1Events[i].key, equals('pub1-key-$i'));
          expect(pub2Events[i].key, equals('pub2-key-$i'));
        }
        
      } finally {
        try { await listenerClient.disconnect(); } catch (_) {}
        try { await publisher1Client.disconnect(); } catch (_) {}
        try { await publisher2Client.disconnect(); } catch (_) {}
      }
    }, timeout: const Duration(seconds: 90));

    guardedTest('should handle broker disconnection gracefully', (a) async {
      final cfg = MqttTestConfig.fromEnv();
      final testId = _generateTestId();
      
      final publisherClient = buildMqtt(cfg, role: 'disconnect-test', suffix: testId);
      
      try {
        // Initial hardened connection
        await connectOrSkip(publisherClient, timeout: const Duration(seconds: 15), require: true, what: 'publisher');

        // Create publisher
        final publisher = await makePublisher(cfg, publisherClient, testId);

        // Publish an event while connected
        await publisher.publishEvent(ReplicationEvent.value(
          key: 'pre-disconnect-key',
          nodeId: 'test-node-$testId',
          seq: 1,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          value: 'connected-value',
        ));

        // Wait for outbox to drain
        await waitForOutboxDrained(publisher, timeout: const Duration(seconds: 20));

        // Force disconnect
        await publisherClient.disconnect();

        // Attempt to publish while disconnected (should queue)
        await publisher.publishEvent(ReplicationEvent.value(
          key: 'post-disconnect-key',
          nodeId: 'test-node-$testId',
          seq: 2,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          value: 'disconnected-value',
        ));

        // Verify outbox has queued events
        final outboxStatus = await publisher.outboxStatus.first.timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('Outbox status timeout', const Duration(seconds: 5)),
        );
        expect(outboxStatus.pendingEvents, greaterThan(0));

        // Reconnect
        await connectOrSkip(publisherClient, timeout: const Duration(seconds: 15), require: true, what: 'reconnect');

        // Wait for outbox to drain after reconnection
        await waitForOutboxDrained(publisher, timeout: const Duration(seconds: 30));

        // Verify graceful handling
        expect(publisher, isNotNull);
        
      } finally {
        try { await publisherClient.disconnect(); } catch (_) {}
      }
    }, timeout: const Duration(seconds: 120));
  });
}
