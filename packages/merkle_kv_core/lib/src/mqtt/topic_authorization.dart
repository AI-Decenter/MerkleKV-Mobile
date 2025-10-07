library topic_authorization;

import '../config/merkle_kv_config.dart';

class AuthorizationException implements Exception {
  final String message;
  final String? topic;
  const AuthorizationException(this.message, {this.topic});
  @override
  String toString() => 'AuthorizationException: $message';
}

class TopicAuthorizationMetrics {
  static int totalChecks = 0;
  static int failures = 0;
  static int commandFailures = 0;
  static int responseFailures = 0;
  static int replicationFailures = 0;
  static int wildcardDenied = 0;

  static void reset() {
    totalChecks = 0;
    failures = 0;
    commandFailures = 0;
    responseFailures = 0;
    replicationFailures = 0;
    wildcardDenied = 0;
  }

  /// Returns metrics in canonical naming expected by observability layer.
  static Map<String, int> export() => {
        'canonical_topic_authorization_checks_total': totalChecks,
        'authorization_failures_total': failures,
        'authorization_failures_command_total': commandFailures,
        'authorization_failures_response_total': responseFailures,
        'authorization_failures_replication_total': replicationFailures,
        'authorization_wildcard_denied_total': wildcardDenied,
      };
}

class TopicAuthorization {
  static void checkPublish(MerkleKVConfig config, String topic) {
    TopicAuthorizationMetrics.totalChecks++;
    final prefix = config.topicPrefix;
    final clientId = config.clientId;

    final cmdPattern = RegExp('^${RegExp.escape(prefix)}/([^/]+)/cmd\$');
    final cmdMatch = cmdPattern.firstMatch(topic);
    if (cmdMatch != null) {
      final targetClient = cmdMatch.group(1)!;
      if (targetClient != clientId) {
        TopicAuthorizationMetrics.failures++;
        TopicAuthorizationMetrics.commandFailures++;
        throw AuthorizationException('Publish denied: cannot publish to another client\'s command topic', topic: topic);
      }
      return;
    }

    final resPattern = RegExp('^${RegExp.escape(prefix)}/([^/]+)/res\$');
    final resMatch = resPattern.firstMatch(topic);
    if (resMatch != null) {
      final targetClient = resMatch.group(1)!;
      if (targetClient != clientId) {
        TopicAuthorizationMetrics.failures++;
        TopicAuthorizationMetrics.responseFailures++;
        throw AuthorizationException('Publish denied: cannot publish to another client\'s response topic', topic: topic);
      }
      return;
    }

    final replicationTopic = '$prefix/replication/events';
    if (topic == replicationTopic) {
      if (!config.replicationCanPublishEvents) {
        TopicAuthorizationMetrics.failures++;
        TopicAuthorizationMetrics.replicationFailures++;
        throw AuthorizationException('Publish denied: replication publish not permitted for this client', topic: topic);
      }
      return;
    }
  }

  static void checkSubscribe(MerkleKVConfig config, String topicFilter) {
    TopicAuthorizationMetrics.totalChecks++;
    final prefix = config.topicPrefix;
    final clientId = config.clientId;

    final hasWildcard = topicFilter.contains('+') || topicFilter.contains('#');
    if (hasWildcard) {
      final targetsCanonicalTopics =
          topicFilter.contains('/cmd') || topicFilter.contains('/res');
  final targetsCanonicalNamespace = topicFilter.startsWith('$prefix/');

      if (targetsCanonicalTopics || targetsCanonicalNamespace) {
        TopicAuthorizationMetrics.failures++;
        TopicAuthorizationMetrics.wildcardDenied++;
        throw const AuthorizationException('Subscribe denied: wildcard access to canonical command/response topics is not allowed');
      }
    }

    final resPattern = RegExp('^${RegExp.escape(prefix)}/([^/]+)/res\$');
    final resMatch = resPattern.firstMatch(topicFilter);
    if (resMatch != null) {
      final targetClient = resMatch.group(1)!;
      if (targetClient != clientId) {
        TopicAuthorizationMetrics.failures++;
        TopicAuthorizationMetrics.responseFailures++;
        throw AuthorizationException('Subscribe denied: cannot subscribe to another client\'s response topic', topic: topicFilter);
      }
      return;
    }

    final cmdPattern = RegExp('^${RegExp.escape(prefix)}/([^/]+)/cmd\$');
    final cmdMatch = cmdPattern.firstMatch(topicFilter);
    if (cmdMatch != null) {
      final targetClient = cmdMatch.group(1)!;
      if (targetClient != clientId) {
        TopicAuthorizationMetrics.failures++;
        TopicAuthorizationMetrics.commandFailures++;
        throw AuthorizationException('Subscribe denied: cannot subscribe to another client\'s command topic', topic: topicFilter);
      }
      return;
    }

    final replicationTopic = '$prefix/replication/events';
    if (topicFilter == replicationTopic) {
      if (!config.replicationCanSubscribeEvents) {
        TopicAuthorizationMetrics.failures++;
        TopicAuthorizationMetrics.replicationFailures++;
        throw AuthorizationException('Subscribe denied: replication subscribe not permitted for this client', topic: topicFilter);
      }
      return;
    }
  }
}
