// Unit tests for BaseClient's retry decision logic, extracted as pure
// top-level functions specifically so they're testable without a real Dio
// instance. Covers the Phase 3 safety rule: only network-level failures are
// retried — a real response from the server (a genuine 4xx/5xx business
// error) never is, since repeating it can't turn it into a success.

import 'package:solvexo_pos/app/network/base_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isRetryableDioErrorType', () {
    test('network-level failures are retryable', () {
      expect(isRetryableDioErrorType(DioExceptionType.connectionTimeout), isTrue);
      expect(isRetryableDioErrorType(DioExceptionType.receiveTimeout), isTrue);
      expect(isRetryableDioErrorType(DioExceptionType.sendTimeout), isTrue);
      expect(isRetryableDioErrorType(DioExceptionType.connectionError), isTrue);
    });

    test('a real response from the server is never retried', () {
      expect(isRetryableDioErrorType(DioExceptionType.badResponse), isFalse,
          reason: 'retrying a genuine 4xx/5xx business error just repeats it');
    });

    test('cancellation and other non-network types are not retried', () {
      expect(isRetryableDioErrorType(DioExceptionType.cancel), isFalse);
      expect(isRetryableDioErrorType(DioExceptionType.badCertificate), isFalse);
      expect(isRetryableDioErrorType(DioExceptionType.unknown), isFalse);
    });
  });

  group('retryBackoffDelay', () {
    test('doubles each attempt starting at 500ms', () {
      expect(retryBackoffDelay(1), const Duration(milliseconds: 500));
      expect(retryBackoffDelay(2), const Duration(milliseconds: 1000));
      expect(retryBackoffDelay(3), const Duration(milliseconds: 2000));
    });
  });
}
