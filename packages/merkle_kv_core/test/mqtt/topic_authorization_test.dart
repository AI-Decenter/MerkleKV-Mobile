import 'package:test/test.dart';
import 'package:merkle_kv_core/src/config/merkle_kv_config.dart';
import 'package:merkle_kv_core/src/mqtt/topic_authorization.dart';

void main() {
  group('TopicAuthorization', () {
    late MerkleKVConfig config;
    const prefix = 'merkle_kv_mobile';
    const clientId = 'client_a';

    setUp(() {
      config = MerkleKVConfig(
        mqttHost: 'localhost',
        clientId: clientId,
        nodeId: 'node_a',
        topicPrefix: prefix,
        mqttUseTls: false,
        replicationCanPublishEvents: false,
        replicationCanSubscribeEvents: true,
      );
      TopicAuthorizationMetrics.reset();
    });

    test('allows publish to own command topic', () {
      expect(() => TopicAuthorization.checkPublish(config, '$prefix/$clientId/cmd'), returnsNormally);
    });

    test('denies publish to other command topic', () {
      expect(() => TopicAuthorization.checkPublish(config, '$prefix/other/cmd'), throwsA(isA<AuthorizationException>()));
    });

    test('allows subscribe to own response topic', () {
      expect(() => TopicAuthorization.checkSubscribe(config, '$prefix/$clientId/res'), returnsNormally);
    });

    test('denies subscribe to other response topic', () {
      expect(() => TopicAuthorization.checkSubscribe(config, '$prefix/other/res'), throwsA(isA<AuthorizationException>()));
    });

    test('denies wildcard subscribe to cmd namespace', () {
      expect(() => TopicAuthorization.checkSubscribe(config, '$prefix/+/cmd'), throwsA(isA<AuthorizationException>()));
    });

    test('denies multi-level wildcard subscribe to response namespace', () {
      expect(() => TopicAuthorization.checkSubscribe(config, '$prefix/#'), throwsA(isA<AuthorizationException>()));
    });

    test('replication publish denied without permission', () {
      expect(() => TopicAuthorization.checkPublish(config, '$prefix/replication/events'), throwsA(isA<AuthorizationException>()));
    });

    test('replication publish allowed with permission', () {
      final cfg2 = config.copyWith(replicationCanPublishEvents: true);
      expect(() => TopicAuthorization.checkPublish(cfg2, '$prefix/replication/events'), returnsNormally);
    });

    test('replication subscribe denied without permission', () {
      final cfgNoSub = MerkleKVConfig(
        mqttHost: 'localhost',
        clientId: clientId,
        nodeId: 'node_a',
        topicPrefix: prefix,
        mqttUseTls: false,
        replicationCanPublishEvents: false,
        replicationCanSubscribeEvents: false,
      );
      expect(() => TopicAuthorization.checkSubscribe(cfgNoSub, '$prefix/replication/events'), throwsA(isA<AuthorizationException>()));
    });

    test('metrics exported with expected keys', () {
      // Trigger some checks/failures
      expect(() => TopicAuthorization.checkPublish(config, '$prefix/$clientId/cmd'), returnsNormally);
      expect(() => TopicAuthorization.checkPublish(config, '$prefix/other/cmd'), throwsA(isA<AuthorizationException>()));
      expect(() => TopicAuthorization.checkSubscribe(config, '$prefix/#'), throwsA(isA<AuthorizationException>()));

      final metrics = TopicAuthorizationMetrics.export();
      expect(metrics.keys, containsAll([
        'canonical_topic_authorization_checks_total',
        'authorization_failures_total',
        'authorization_failures_command_total',
        'authorization_failures_response_total',
        'authorization_failures_replication_total',
        'authorization_wildcard_denied_total',
      ]));
      expect(metrics['canonical_topic_authorization_checks_total'], greaterThan(0));
      expect(metrics['authorization_failures_total'], greaterThan(0));
      expect(metrics['authorization_failures_command_total'], greaterThan(0));
      expect(metrics['authorization_wildcard_denied_total'], greaterThanOrEqualTo(1));
    });
  });
}
