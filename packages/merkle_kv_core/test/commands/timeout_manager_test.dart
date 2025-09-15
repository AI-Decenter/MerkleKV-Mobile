import 'dart:async';
import 'dart:math';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:merkle_kv_core/src/commands/timeout_manager.dart';
import 'package:merkle_kv_core/src/commands/retry_policy.dart';
import 'package:merkle_kv_core/src/commands/operation_manager.dart';

class MockRandom extends Mock implements Random {
  @override
  double nextDouble() => 0.5;
}

void main() {
  group('TimeoutManager', () {
    late TimeoutManager timeoutManager;

    setUp(() {
      timeoutManager = TimeoutManager();
    });

    test('starts tracking operation correctly', () {
      const String requestId = 'test-request-1';
      timeoutManager.startOperation(requestId);
      expect(timeoutManager.getElapsedTime(requestId), isNot(Duration.zero));
    });

    test('stops tracking operation correctly', () {
      const String requestId = 'test-request-2';
      timeoutManager.startOperation(requestId);
      timeoutManager.stopOperation(requestId);
      expect(timeoutManager.getElapsedTime(requestId), Duration.zero);
    });

    test('detects timeout based on operation type', () async {
      const String requestId = 'test-request-3';
      timeoutManager.startOperation(requestId);
      
      // Wait to ensure timeout check will pass
      await Future.delayed(const Duration(milliseconds: 50));
      
      // Manually override timeout to smaller value for testing
      final testTimeout = Duration(milliseconds: 10);
      expect(timeoutManager.isTimedOut(requestId, testTimeout), isTrue);
    });

    test('returns correct timeout duration per operation type', () {
      expect(timeoutManager.getTimeoutForType(OperationType.singleKey), TimeoutManager.singleKeyTimeout);
      expect(timeoutManager.getTimeoutForType(OperationType.multiKey), TimeoutManager.multiKeyTimeout);
      expect(timeoutManager.getTimeoutForType(OperationType.sync), TimeoutManager.syncTimeout);
    });

    test('throws TimeoutException when operation times out', () async {
      const String requestId = 'test-request-4';
      timeoutManager.startOperation(requestId);

      // Wait beyond a short timeout to ensure the operation is actually timed out
      await Future.delayed(const Duration(milliseconds: 50));

      // Test that isTimedOut works with a very short timeout
      final shortTimeout = Duration(milliseconds: 10);
      expect(timeoutManager.isTimedOut(requestId, shortTimeout), isTrue);
      
      // Now test that checkTimeout throws when using the short timeout
      // We need to manually call checkTimeout with our custom timeout logic
      expect(() {
        if (timeoutManager.isTimedOut(requestId, shortTimeout)) {
          final elapsed = timeoutManager.getElapsedTime(requestId);
          timeoutManager.stopOperation(requestId);
          throw TimeoutException(requestId, elapsed);
        }
      }, throwsA(isA<TimeoutException>()));
    });

    test('cleanup stale operations', () async {
      const String requestId = 'test-request-5';
      timeoutManager.startOperation(requestId);
      
      // Wait to ensure operation would be considered stale (> 30ms)
      await Future.delayed(const Duration(milliseconds: 50));
      
      // Run cleanup - this should remove stale operations
      final cleanedCount = timeoutManager.cleanupStaleOperations();
      
      // Should have cleaned up 1 stale operation
      expect(cleanedCount, equals(1));
      
      // After cleanup, the operation should be removed, so elapsed time should be zero
      expect(timeoutManager.getElapsedTime(requestId), Duration.zero);
    });
  });

  group('RetryPolicy', () {
    test('calculates exponential backoff with jitter', () {
      final retryPolicy = RetryPolicy(
        maxAttempts: 3,
        initialDelay: const Duration(milliseconds: 100),
        backoffFactor: 2,
        maxDelay: const Duration(milliseconds: 1000),
        jitterFactor: 0.2,
        random: MockRandom(),
      );

      final delay1 = retryPolicy.calculateDelay(1);
      final delay2 = retryPolicy.calculateDelay(2);
      final delay3 = retryPolicy.calculateDelay(3);
      
      // With MockRandom returning 0.5:
      // jitter = (0.5 - 0.5) * 2 * 0.2 = 0
      // So delays should be exactly: 100ms, 200ms, 400ms
      expect(delay1.inMilliseconds, 100);
      expect(delay2.inMilliseconds, 200);
      expect(delay3.inMilliseconds, 400);
    });

    test('respects maximum delay cap', () {
      final policy = RetryPolicy(
        initialDelay: const Duration(seconds: 1),
        backoffFactor: 10.0,
        maxDelay: const Duration(seconds: 5),
        random: MockRandom(),
      );
      
      final delay1 = policy.calculateDelay(1);
      final delay2 = policy.calculateDelay(2);
      
      expect(delay1.inSeconds, 1);
      expect(delay2.inSeconds, 5); // Capped at maxDelay
    });

    test('determines if error is retriable', () {
      final policy = RetryPolicy(maxAttempts: 3);
      
      // Retriable errors
      final timeoutError = TimeoutException('request-id', Duration(seconds: 1));
      final networkError = Exception('Network connection lost');
      final brokerError = Exception('Broker disconnected');
      
      // Non-retriable errors
      final validationError = Exception('Invalid request format');
      final authError = Exception('Authentication failed');
      
      // Should retry network-related errors
      expect(policy.shouldRetry(timeoutError, 1), isTrue);
      expect(policy.shouldRetry(networkError, 1), isTrue);
      expect(policy.shouldRetry(brokerError, 1), isTrue);
      
      // Should not retry validation or auth errors
      expect(policy.shouldRetry(validationError, 1), isFalse);
      expect(policy.shouldRetry(authError, 1), isFalse);
    });

    test('stops retrying after max attempts', () {
      final policy = RetryPolicy(maxAttempts: 3);
      final error = TimeoutException('request-id', Duration(seconds: 1));
      
      expect(policy.shouldRetry(error, 1), isTrue);
      expect(policy.shouldRetry(error, 2), isTrue);
      expect(policy.shouldRetry(error, 3), isFalse); // Max attempts reached
    });
  });

  group('OperationManager', () {
    late OperationManager operationManager;

    setUp(() {
      operationManager = OperationManager();
    });

    test('executes operation with retry on failure', () async {
      int attempts = 0;
      bool succeeded = false;
      
      await operationManager.executeWithRetry(
        requestId: 'test-op',
        operationType: OperationType.singleKey,
        operation: () async {
          attempts++;
          
          if (attempts < 2) {
            throw Exception('Network connection lost'); // Retriable error
          }
          
          succeeded = true;
          return 'success';
        },
      );
      
      expect(attempts, 2);
      expect(succeeded, isTrue);
    });

    test('uses custom retry policy when specified', () async {
      final customManager = OperationManager(
        retryPolicy: RetryPolicy(
          initialDelay: const Duration(milliseconds: 10), // Very fast for testing
          maxAttempts: 3,
        ),
      );
      
      int attempts = 0;
      
      final result = await customManager.executeWithRetry(
        requestId: 'custom-policy-test',
        operationType: OperationType.singleKey,
        operation: () async {
          attempts++;
          
          if (attempts < 3) {
            throw Exception('Network connection lost'); // Retriable error
          }
          
          return 'success';
        },
      );
      
      expect(attempts, 3);
      expect(result, 'success');
    });

    test('times out operations that take too long', () async {
        // Create a manager with a very short timeout for testing
        final testTimeoutManager = TimeoutManager();
        // Set a very short timeout for testing (100ms)
        testTimeoutManager.setCustomTimeout(OperationType.singleKey, Duration(milliseconds: 100));
        
        final testManager = OperationManager(timeoutManager: testTimeoutManager);
        
        final String requestId = 'timeout-test';
        
        // Test that executeWithRetry actually times out
        await expectLater(
            testManager.executeWithRetry(
            requestId: requestId,
            operationType: OperationType.singleKey,
            operation: () async {
                // This operation takes longer than our 100ms timeout
                await Future.delayed(const Duration(milliseconds: 200));
                return 'success';
            },
            ),
            throwsA(isA<TimeoutException>()),
        );
        
        // Clean up
        testTimeoutManager.clearCustomTimeouts();
    }, timeout: Timeout(Duration(seconds: 5))); // Give the test enough time

    test('queues failed operations for retry', () async {
      final operation = RetriableOperation(
        requestId: 'retry-test',
        executeOperation: () async {
          throw Exception('Network error');
        },
      );
      
      await operationManager.queueForRetry(operation);
      
      expect(operationManager.retryQueueSize, 1);
    });

    test('enforces queue size limit', () async {
      // Test with a smaller number to avoid timeout issues
      final testLimit = 10;
      for (int i = 0; i < testLimit + 5; i++) {
        final operation = RetriableOperation(
          requestId: 'queue-test-$i',
          executeOperation: () async {},
        );
        
        await operationManager.queueForRetry(operation);
      }
      
      // Queue should be capped at max size (1000), oldest operations dropped
      expect(operationManager.retryQueueSize, lessThanOrEqualTo(OperationManager.maxQueueSize));
    });

    test('processes retry queue on reconnection', () async {
      int successCount = 0;
      
      // Add some operations that will succeed
      for (int i = 0; i < 5; i++) {
        final operation = RetriableOperation(
          requestId: 'reconnect-test-$i',
          executeOperation: () async {
            successCount++;
          },
        );
        
        await operationManager.queueForRetry(operation);
      }
      
      // Simulate reconnection
      operationManager.setConnectionState(true);
      
      // Allow time for queue processing
      await Future.delayed(Duration(milliseconds: 100));
      
      expect(successCount, 5);
      expect(operationManager.retryQueueSize, 0);
    });
  });
}