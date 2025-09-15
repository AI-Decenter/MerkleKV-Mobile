import 'package:merkle_kv_core/merkle_kv.dart';

/// Example demonstrating the MerkleKV public API usage
Future<void> main() async {
  // 1. Configure using builder pattern
  final config = MerkleKV.builder()
      .mqttHost('mqtt.example.com')
      .mqttPort(8883)
      .useTls()
      .credentials('username', 'password')
      .clientId('mobile-app-${DateTime.now().millisecondsSinceEpoch}')
      .nodeId('device-uuid-123')
      .topicPrefix('myapp/production')
      .keepAlive(60)
      .persistence(true, '/data/merkle_kv')
      .build();

  // 2. Create client instance
  final client = MerkleKV(config);

  print('MerkleKV Client Version: ${client.version}');

  try {
    // 3. Connect to broker
    print('Connecting to MQTT broker...');
    await client.connect();
    print('Connected successfully!');

    // 4. Monitor connection state
    client.connectionState.listen((state) {
      print('Connection state changed: $state');
    });

    // 5. Basic operations
    await client.set('user:123:name', 'Alice Smith');
    print('Set user name');

    final userName = await client.get('user:123:name');
    print('Retrieved user name: $userName');

    // 6. Numeric operations
    await client.increment('global:counter');
    final count = await client.increment('global:counter', 5);
    print('Global counter: $count');

    // 7. String operations
    await client.set('log:entry', 'Starting application');
    await client.append('log:entry', ' - User logged in');
    await client.prepend('log:entry', '[INFO] ');
    final logEntry = await client.get('log:entry');
    print('Log entry: $logEntry');

    // 8. Bulk operations
    final userIds = ['user:123', 'user:456', 'user:789'];
    final users = await client.multiGet([
      'user:123:name',
      'user:456:name', 
      'user:789:name'
    ]);
    print('Retrieved users: $users');

    await client.multiSet({
      'user:new:name': 'Bob Johnson',
      'user:new:email': 'bob@example.com',
      'user:new:role': 'admin',
    });
    print('Created new user with multiple fields');

    // 9. Idempotent operations with custom request IDs
    const requestId = 'critical-operation-123';
    await client.set('important:data', 'critical value', requestId);
    // Retry with same ID - will be idempotent
    await client.set('important:data', 'critical value', requestId);

    // 10. Delete operations (always succeed)
    await client.delete('temp:data');
    await client.delete('non-existent:key'); // Still succeeds
    print('Cleanup completed');

  } on ValidationException catch (e) {
    print('Validation error: ${e.message}');
  } on ConnectionException catch (e) {
    print('Connection error: ${e.message}');
  } on TimeoutException catch (e) {
    print('Timeout error: ${e.message}');
  } on PayloadException catch (e) {
    print('Payload error: ${e.message}');
  } on KeyNotFoundException catch (e) {
    print('Key not found: ${e.message}');
  } on MerkleKVException catch (e) {
    print('MerkleKV error: ${e.message} (code: ${e.errorCode})');
  } finally {
    // 11. Clean shutdown
    print('Disconnecting...');
    await client.disconnect();
    await client.dispose();
    print('Shutdown complete');
  }
}

/// Example of advanced configuration
Future<void> advancedConfigExample() async {
  final config = MerkleKVConfig.builder()
      .mqttHost('secure.mqtt.company.com')
      .mqttPort(8883)
      .useTls()
      .credentials('mobile-user', 'secure-password')
      .clientId('mobile-app-v2')
      .nodeId('device-serial-12345')
      .topicPrefix('company/mobile/prod')
      .keepAlive(120)
      .sessionExpiry(7200) // 2 hours
      .maxFutureSkew(600000) // 10 minutes
      .tombstoneRetention(48) // 48 hours
      .connectionTimeout(30)
      .persistence(true, '/data/company/merkle_kv')
      .build();

  final client = MerkleKV(config);

  print('Advanced configuration example:');
  print('Host: ${config.mqttHost}');
  print('TLS: ${config.mqttUseTls}');
  print('Topic Prefix: ${config.topicPrefix}');
  print('Persistence: ${config.persistenceEnabled}');

  await client.dispose();
}

/// Example error handling patterns
Future<void> errorHandlingExample() async {
  final config = MerkleKV.builder()
      .mqttHost('mqtt.test.com')
      .clientId('test-client')
      .nodeId('test-node')
      .build();
      
  final client = MerkleKV(config);

  try {
    // This will fail validation
    await client.get(''); // Empty key
  } on ValidationException catch (e) {
    print('Caught validation error: ${e.message}');
  }

  try {
    // This will fail with connection error
    await client.get('valid-key'); // Not connected
  } on DisconnectedException catch (e) {
    print('Caught disconnection error: ${e.message}');
  }

  try {
    // This will fail validation
    final oversizedKey = 'x' * 300; // > 256 bytes
    await client.get(oversizedKey);
  } on ValidationException catch (e) {
    print('Caught oversized key error: ${e.message}');
  }

  await client.dispose();
}