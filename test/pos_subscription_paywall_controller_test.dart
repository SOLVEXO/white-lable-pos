// Unit tests for PosSubscriptionPaywallController against a mocked
// PosSubscriptionRepository. onInit (which reads Get.arguments) is never
// triggered — storeId/storeName/isExpired/expiresAt are `late final` fields
// normally set from arguments in onInit; here they're assigned directly
// instead, same pattern as PosSaleDetailController's saleId in
// pos_sale_detail_actions_test.dart. Load behavior is exercised via the
// public retryLoad() (onInit just calls the same private _loadPlans).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_plan_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_subscription_repository.dart';
import 'package:solvexo_pos/app/modules/pos_subscription_paywall/controllers/pos_subscription_paywall_controller.dart';
import 'package:solvexo_pos/app/network/api_constaints.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';

class MockPosSubscriptionRepository extends Mock implements PosSubscriptionRepository {}

const _plan1 = PosPlanModel(
  id: 'plan-1',
  name: '3 Month Plan',
  price: 49,
  currency: 'USD',
  durationInDays: 90,
);
const _plan2 = PosPlanModel(
  id: 'plan-2',
  name: '1 Year Plan',
  price: 149,
  currency: 'USD',
  durationInDays: 365,
);

void main() {
  late MockPosSubscriptionRepository repo;
  late PosSubscriptionPaywallController c;

  setUpAll(() {
    Get.testMode = true;
  });

  setUp(() {
    repo = MockPosSubscriptionRepository();
    c = PosSubscriptionPaywallController(repository: repo);
  });

  // storeId/storeName/isExpired/expiresAt are `late final` — assigned
  // exactly once per test, here rather than in setUp, so a test that needs
  // a different value (e.g. an empty storeId) doesn't hit an
  // "already initialized" error.
  void seed({String storeId = 'store-1', String storeName = 'Test Store', bool isExpired = false}) {
    c.storeId = storeId;
    c.storeName = storeName;
    c.isExpired = isExpired;
    c.expiresAt = null;
  }

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
        ResponsiveSizer(
          builder: (context, orientation, screenType) => GetMaterialApp(
            initialRoute: '/paywall',
            getPages: [
              GetPage(name: '/paywall', page: () => const Scaffold(body: SizedBox.shrink())),
              GetPage(name: Routes.posSubscriptionCheckout, page: () => const Scaffold(body: SizedBox.shrink())),
            ],
          ),
        ),
      );

  group('retryLoad / _loadPlans', () {
    test('an empty storeId goes straight to error without calling the repository', () async {
      seed(storeId: '');

      await c.retryLoad();

      expect(c.uiState.value, PosSubscriptionPaywallUiState.error);
      expect(c.errorMessage.value, 'No store selected.');
      verifyNever(() => repo.getPlans());
    });

    test('populates the plan list and moves to ready when plans exist', () async {
      seed();
      when(() => repo.getPlans()).thenAnswer((_) async => [_plan1, _plan2]);

      await c.retryLoad();

      expect(c.uiState.value, PosSubscriptionPaywallUiState.ready);
      expect(c.plans, [_plan1, _plan2]);
    });

    test('moves to empty when the admin has created no plans', () async {
      seed();
      when(() => repo.getPlans()).thenAnswer((_) async => []);

      await c.retryLoad();

      expect(c.uiState.value, PosSubscriptionPaywallUiState.empty);
    });
  });

  group('selectPlan', () {
    test('sets the selected plan', () async {
      seed();
      when(() => repo.getPlans()).thenAnswer((_) async => [_plan1, _plan2]);
      await c.retryLoad();

      c.selectPlan(_plan2);

      expect(c.selectedPlan.value, _plan2);
    });
  });

  group('confirm', () {
    test('does nothing when no plan is selected', () async {
      seed();

      await c.confirm();

      verifyNever(() => repo.createCheckoutSession(
            any(),
            planId: any(named: 'planId'),
            successUrl: any(named: 'successUrl'),
            cancelUrl: any(named: 'cancelUrl'),
          ));
    });

    testWidgets('builds never-resolving return URLs and navigates to checkout on success', (tester) async {
      seed();
      await pumpApp(tester);
      c.selectPlan(_plan1);
      when(() => repo.createCheckoutSession(
            'store-1',
            planId: captureAny(named: 'planId'),
            successUrl: captureAny(named: 'successUrl'),
            cancelUrl: captureAny(named: 'cancelUrl'),
          )).thenAnswer((_) async => 'https://checkout.stripe.com/session-1');

      unawaited(c.confirm());
      await tester.pump();

      final captured = verify(() => repo.createCheckoutSession(
            'store-1',
            planId: captureAny(named: 'planId'),
            successUrl: captureAny(named: 'successUrl'),
            cancelUrl: captureAny(named: 'cancelUrl'),
          )).captured;
      expect(captured[0], 'plan-1');
      expect(captured[1], '${ApiConstants.baseUrl}/pos-subscription-return/success');
      expect(captured[2], '${ApiConstants.baseUrl}/pos-subscription-return/cancel');
      expect(Get.currentRoute, Routes.posSubscriptionCheckout);
      expect(Get.arguments['url'], 'https://checkout.stripe.com/session-1');
      expect(Get.arguments['storeId'], 'store-1');
    });

    testWidgets('a null url surfaces an error and does not navigate', (tester) async {
      seed();
      await pumpApp(tester);
      c.selectPlan(_plan1);
      when(() => repo.createCheckoutSession(
            any(),
            planId: any(named: 'planId'),
            successUrl: any(named: 'successUrl'),
            cancelUrl: any(named: 'cancelUrl'),
          )).thenAnswer((_) async => null);

      await c.confirm();
      await tester.pump();

      expect(c.errorMessage.value, 'Could not start checkout. Please try again.');
      expect(Get.currentRoute, '/paywall');
    });
  });
}
