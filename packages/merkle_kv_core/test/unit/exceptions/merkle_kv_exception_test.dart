import 'package:test/test.dart';
import '../../../lib/src/exceptions/merkle_kv_exception.dart';
import '../../../lib/src/commands/response.dart';

void main() {
  group('MerkleKVException', () {
    test('base class properties', () {
      const exception = ValidationException('Test message');
      expect(exception.errorCode, equals(ErrorCode.invalidRequest));
      expect(exception.message, equals('Test message'));
      expect(exception.cause, isNull);
      expect(exception.toString(), contains('ValidationException'));
      expect(exception.toString(), contains('Test message'));
      expect(exception.toString(), contains('100'));
    });

    test('exception with cause', () {
      final cause = ArgumentError('Original error');
      final exception = ConnectionException('Connection failed', cause);
      expect(exception.cause, equals(cause));
    });

    group('fromResponse factory', () {
      test('creates ValidationException for invalid request', () {
        final response = Response.error(
          id: 'test',
          error: 'Invalid key format',
          errorCode: ErrorCode.invalidRequest,
        );

        final exception = MerkleKVException.fromResponse(response);
        expect(exception, isA<ValidationException>());
        expect(exception.message, equals('Invalid key format'));
        expect(exception.errorCode, equals(ErrorCode.invalidRequest));
      });

      test('creates TimeoutException for timeout', () {
        final response = Response.timeout('test');

        final exception = MerkleKVException.fromResponse(response);
        expect(exception, isA<TimeoutException>());
        expect(exception.errorCode, equals(ErrorCode.timeout));
      });

      test('creates KeyNotFoundException for not found', () {
        final response = Response.notFound('test');

        final exception = MerkleKVException.fromResponse(response);
        expect(exception, isA<KeyNotFoundException>());
        expect(exception.errorCode, equals(ErrorCode.notFound));
      });

      test('creates PayloadException for payload too large', () {
        final response = Response.payloadTooLarge('test');

        final exception = MerkleKVException.fromResponse(response);
        expect(exception, isA<PayloadException>());
        expect(exception.errorCode, equals(ErrorCode.payloadTooLarge));
      });

      test('creates ValidationException for range overflow', () {
        final response = Response.rangeOverflow('test', 'Value overflow');

        final exception = MerkleKVException.fromResponse(response);
        expect(exception, isA<ValidationException>());
        expect(exception.errorCode, equals(ErrorCode.rangeOverflow));
      });

      test('creates ValidationException for invalid type', () {
        final response = Response.invalidType('test', 'Not a number');

        final exception = MerkleKVException.fromResponse(response);
        expect(exception, isA<ValidationException>());
        expect(exception.errorCode, equals(ErrorCode.invalidType));
      });

      test('creates InternalException for internal error', () {
        final response = Response.internalError('test', 'Database error');

        final exception = MerkleKVException.fromResponse(response);
        expect(exception, isA<InternalException>());
        expect(exception.errorCode, equals(ErrorCode.internalError));
      });

      test('creates InternalException for unknown error code', () {
        final response = Response.error(
          id: 'test',
          error: 'Unknown error',
          errorCode: 999, // Unknown code
        );

        final exception = MerkleKVException.fromResponse(response);
        expect(exception, isA<InternalException>());
        expect(exception.message, equals('Unknown error'));
      });

      test('throws ArgumentError for successful response', () {
        final response = Response.ok(id: 'test', value: 'success');

        expect(
          () => MerkleKVException.fromResponse(response),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('specific exception types', () {
      test('ConnectionException', () {
        const exception = ConnectionException('Connection lost');
        expect(exception.errorCode, equals(ErrorCode.timeout));
        expect(exception.message, equals('Connection lost'));
      });

      test('ValidationException', () {
        const exception = ValidationException('Invalid input');
        expect(exception.errorCode, equals(ErrorCode.invalidRequest));
        expect(exception.message, equals('Invalid input'));
      });

      test('TimeoutException', () {
        const exception = TimeoutException('Operation timed out');
        expect(exception.errorCode, equals(ErrorCode.timeout));
        expect(exception.message, equals('Operation timed out'));
      });

      test('PayloadException', () {
        const exception = PayloadException('Payload too large');
        expect(exception.errorCode, equals(ErrorCode.payloadTooLarge));
        expect(exception.message, equals('Payload too large'));
      });

      test('KeyNotFoundException', () {
        const exception = KeyNotFoundException('Key not found');
        expect(exception.errorCode, equals(ErrorCode.notFound));
        expect(exception.message, equals('Key not found'));
      });

      test('InternalException', () {
        const exception = InternalException('Internal error');
        expect(exception.errorCode, equals(ErrorCode.internalError));
        expect(exception.message, equals('Internal error'));
      });

      test('DisconnectedException', () {
        const exception = DisconnectedException('Client disconnected');
        expect(exception.errorCode, equals(ErrorCode.timeout));
        expect(exception.message, equals('Client disconnected'));
      });
    });
  });
}