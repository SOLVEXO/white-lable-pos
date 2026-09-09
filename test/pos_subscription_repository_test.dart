// Direct unit tests for PosSubscriptionRepository — plan-list parsing,
// response envelope unwrapping for every PosSubscriptionStatusValue,
// checkout-session URL extraction, and failure paths (DioException,
// {success:false}). Mocks BaseClient, same seam/pattern as
// pos_repository_test.dart; never touches Dio or a real network call.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;
import 'package:mocktail/mocktail.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_subscription_status_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_subscription_repository.dart';
import 'package:solvexo_pos/app/network/base_client.dart';

class MockBaseClient extends Mock implements BaseClient {}

Response _res(dynamic data) => Response(data: data, requestOptions: RequestOptions(path: ''));

DioException _dioError() => DioException(
      requestOptions: RequestOptions(path: ''),
      response: Response(statusCode: 500, requestOptions: RequestOptions(path: '')),
    );

void main() {
  late MockBaseClient client;
  late PosSubscriptionRepository repo;

  setUpAll(() {
    Get.testMode = true;
  });

  setUp(() {
    client = MockBaseClient();
    repo = PosSubscriptionRepository(client: client);
  });

  void stubGet(Response response) {
    when(() => client.get(any(), requiresAuth: any(named: 'requiresAuth'))).thenAnswer((_) async => response);
  }

  void stubGetThrows(DioException e) {
    when(() => client.get(any(), requiresAuth: any(named: 'requiresAuth'))).thenThrow(e);
  }

  void stubPostCheckout(Response response) {
    when(() => client.post(
          any(),
          data: any(named: 'data'),
          requiresAuth: any(named: 'requiresAuth'),
        )).thenAnswer((_) async => response);
  }

  void stubPostCheckoutThrows(DioException e) {
    when(() => client.post(
          any(),
          data: any(named: 'data'),
          requiresAuth: any(named: 'requiresAuth'),
        )).thenThrow(e);
  }

  group('getPlans', () {
    test('parses the active-plans list', () async {
      stubGet(_res({
        'success': true,
        'data': [
          {
            'id': 'plan-1',
            'name': '3 Month Plan',
            'price': 49,
            'currency': 'USD',
            'durationInDays': 90,
            'description': 'Great for seasonal sellers',
          },
          {
            'id': 'plan-2',
            'name': '1 Year Plan',
            'price': 149,
            'currency': 'USD',
            'durationInDays': 365,
          },
        ],
      }));

      final plans = await repo.getPlans();

      expect(plans, hasLength(2));
      expect(plans[0].id, 'plan-1');
      expect(plans[0].name, '3 Month Plan');
      expect(plans[0].price, 49);
      expect(plans[0].durationInDays, 90);
      expect(plans[0].description, 'Great for seasonal sellers');
      expect(plans[1].description, isNull);
    });

    test('returns an empty list when the backend reports failure', () async {
      stubGet(_res({'success': false, 'message': 'error'}));

      final plans = await repo.getPlans();

      expect(plans, isEmpty);
    });

    test('returns an empty list (not throws) on a DioException', () async {
      stubGetThrows(_dioError());

      final plans = await repo.getPlans();

      expect(plans, isEmpty);
    });
  });

  group('getStatus — status parsing', () {
    final cases = {
      'active': PosSubscriptionStatusValue.active,
      'expired': PosSubscriptionStatusValue.expired,
      'none': PosSubscriptionStatusValue.none,
    };

    for (final entry in cases.entries) {
      test('"${entry.key}" maps to ${entry.value}', () async {
        stubGet(_res({
          'success': true,
          'data': {
            'status': entry.key,
            'planName': 'Pro',
            'purchasedAt': '2026-01-01T00:00:00.000Z',
            'expiresAt': '2026-04-01T00:00:00.000Z',
            'daysRemaining': 12,
          },
        }));

        final result = await repo.getStatus('store-1');

        expect(result.status, entry.value);
        expect(result.planName, 'Pro');
        expect(result.purchasedAt, DateTime.parse('2026-01-01T00:00:00.000Z'));
        expect(result.expiresAt, DateTime.parse('2026-04-01T00:00:00.000Z'));
        expect(result.daysRemaining, 12);
      });
    }

    test('an unrecognized status string falls back to none rather than throwing', () async {
      stubGet(_res({
        'success': true,
        'data': {'status': 'something_new_the_backend_added'},
      }));

      final result = await repo.getStatus('store-1');

      expect(result.status, PosSubscriptionStatusValue.none);
    });

    test('missing planName/purchasedAt/expiresAt/daysRemaining leaves them null', () async {
      stubGet(_res({
        'success': true,
        'data': {'status': 'active'},
      }));

      final result = await repo.getStatus('store-1');

      expect(result.status, PosSubscriptionStatusValue.active);
      expect(result.planName, isNull);
      expect(result.purchasedAt, isNull);
      expect(result.expiresAt, isNull);
      expect(result.daysRemaining, isNull);
    });
  });

  group('getStatus — failure paths', () {
    test('a {success:false} envelope returns .unknown() (status none)', () async {
      stubGet(_res({'success': false, 'message': 'not found'}));

      final result = await repo.getStatus('store-1');

      expect(result.status, PosSubscriptionStatusValue.none);
    });

    test('a DioException returns .unknown() instead of throwing', () async {
      stubGetThrows(_dioError());

      final result = await repo.getStatus('store-1');

      expect(result.status, PosSubscriptionStatusValue.none);
    });
  });

  group('createCheckoutSession', () {
    test('extracts the url from a successful response', () async {
      stubPostCheckout(_res({
        'success': true,
        'data': {'url': 'https://checkout.stripe.com/session-1'},
      }));

      final url = await repo.createCheckoutSession(
        'store-1',
        planId: 'plan-1',
        successUrl: 'https://app/success',
        cancelUrl: 'https://app/cancel',
      );

      expect(url, 'https://checkout.stripe.com/session-1');
    });

    test('returns null when the backend reports failure', () async {
      stubPostCheckout(_res({'success': false, 'message': 'Stripe error'}));

      final url = await repo.createCheckoutSession(
        'store-1',
        planId: 'plan-1',
        successUrl: 'https://app/success',
        cancelUrl: 'https://app/cancel',
      );

      expect(url, isNull);
    });

    test('returns null (not throws) on a DioException', () async {
      stubPostCheckoutThrows(_dioError());

      final url = await repo.createCheckoutSession(
        'store-1',
        planId: 'plan-1',
        successUrl: 'https://app/success',
        cancelUrl: 'https://app/cancel',
      );

      expect(url, isNull);
    });
  });
}
