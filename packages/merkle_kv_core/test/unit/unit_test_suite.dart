/// Comprehensive Unit Test Suite for MerkleKV Core
/// 
/// This file imports and runs all unit tests to ensure comprehensive coverage
/// of storage engine, MQTT client, topic router, and command processor components.
/// 
/// Test Categories:
/// - Storage Engine: LWW resolution, tombstone GC, UTF-8 validation, deduplication
/// - MQTT Client: QoS enforcement, connection lifecycle, backoff, security
/// - Topic Router: Canonical topics, validation, multi-tenant isolation
/// - Command Processor: JSON validation, payload limits, idempotency
/// - Negative Tests: Payload caps, malformed JSON, resource exhaustion
///
/// Coverage Target: >95% line coverage
/// Execution Time Target: <30 seconds

import 'storage/storage_engine_test.dart' as storage_tests;
import 'mqtt/mqtt_client_test.dart' as mqtt_tests;
import 'router/topic_router_test.dart' as router_tests;
import 'processor/command_processor_test.dart' as processor_tests;
import 'negative_tests.dart' as negative_tests;

void main() {
  // Run storage engine tests
  storage_tests.main();
  
  // Run MQTT client tests
  mqtt_tests.main();
  
  // Run topic router tests
  router_tests.main();
  
  // Run command processor tests
  processor_tests.main();
  
  // Run negative tests
  negative_tests.main();
}