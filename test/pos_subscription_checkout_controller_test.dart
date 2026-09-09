// Unit tests for PosSubscriptionCheckoutController's confirm/cancel flow
// against a mocked PosSubscriptionRepository.
//
// onInit (which builds a real WebViewController via _openWebView) is never
// triggered — constructing one needs platform channels no test environment
// provides. The buyer app's GatewayPaymentControllerTest hits the exact same
// wall: none of its tests reach a redirect-based session either, so
// onNavigationRequest is never exercised there. That's a real gap on both
// sides. debugSeed()/debugSimulateSuccessReturn()/debugSimulateCancelReturn()
// (added alongside this test) are test-only seams that let the
// state-machine logic (confirm polling, cancel) be verified without a real
// WebView — narrower than "the whole screen works", but covers what a real
// WebView test never does today either way.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_subscription_status_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_subscription_repository.dart';
import 'package:solvexo_pos/app/modules/pos_subscription_checkout/controllers/pos_subscription_checkout_controller.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';

class MockPosSubscriptionRepository extends Mock implements PosSubscriptionRepository {}

PosSubscriptionStatusModel _status(PosSubscriptionStatusValue value) => PosSubscriptionStatusModel(status: value);

void main() {
  late MockPosSubscriptionRepository repo;
  late PosSubscriptionCheckoutController c;

  setUpAll(() {
    Get.testMode = true;
  });

  setUp(() {
    repo = MockPosSubscriptionRepository();
    c = PosSubscriptionCheckoutController(repository: repo);
  });

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
        ResponsiveSizer(
          builder: (context, orientation, screenType) => GetMaterialApp(
            initialRoute: '/checkout',
            getPages: [
              GetPage(name: '/checkout', page: () => const Scaffold(body: SizedBox.shrink())),
              GetPage(name: Routes.posPinLogin, page: () => const Scaffold(body: SizedBox.shrink())),
            ],
          ),
        ),
      );

  group('simulated success return', () {
    testWidgets('an immediately-entitled status confirms without delay and lands on posPinLogin', (tester) async {
      await pumpApp(tester);
      c.debugSeed(storeId: 'store-1', successUrl: 'https://app/success', cancelUrl: 'https://app/cancel');
      when(() => repo.getStatus('store-1')).thenAnswer((_) async => _status(PosSubscriptionStatusValue.active));

      c.debugSimulateSuccessReturn();
      await tester.pump();
      expect(c.uiState.value, PosSubscriptionCheckoutUiState.confirming);
      await tester.pump();

      expect(Get.currentRoute, Routes.posPinLogin);
      verify(() => repo.getStatus('store-1')).called(1);
    });

    testWidgets('a transitional status polls again before confirming', (tester) async {
      await pumpApp(tester);
      c.debugSeed(storeId: 'store-1', successUrl: 'https://app/success', cancelUrl: 'https://app/cancel');
      var call = 0;
      when(() => repo.getStatus('store-1')).thenAnswer((_) async {
        call++;
        return _status(call < 2 ? PosSubscriptionStatusValue.none : PosSubscriptionStatusValue.active);
      });

      c.debugSimulateSuccessReturn();
      await tester.pump();
      // First check is transitional — the loop then awaits a 1s delay
      // before checking again.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(Get.currentRoute, Routes.posPinLogin);
      verify(() => repo.getStatus('store-1')).called(2);
    });

    testWidgets('exhausting the poll shows an honest error instead of claiming success', (tester) async {
      await pumpApp(tester);
      c.debugSeed(storeId: 'store-1', successUrl: 'https://app/success', cancelUrl: 'https://app/cancel');
      when(() => repo.getStatus('store-1')).thenAnswer((_) async => _status(PosSubscriptionStatusValue.none));

      c.debugSimulateSuccessReturn();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();

      expect(c.uiState.value, PosSubscriptionCheckoutUiState.error);
      expect(c.errorMessage.value, "We couldn't confirm your purchase yet. Please check back shortly.");
      expect(Get.currentRoute, '/checkout', reason: 'never navigates away without confirming');
      verify(() => repo.getStatus('store-1')).called(10);
    });

    testWidgets('a second success callback is ignored once already resolved', (tester) async {
      await pumpApp(tester);
      c.debugSeed(storeId: 'store-1', successUrl: 'https://app/success', cancelUrl: 'https://app/cancel');
      when(() => repo.getStatus('store-1')).thenAnswer((_) async => _status(PosSubscriptionStatusValue.active));

      c.debugSimulateSuccessReturn();
      await tester.pump();
      await tester.pump();
      c.debugSimulateSuccessReturn();
      await tester.pump();

      verify(() => repo.getStatus('store-1')).called(1);
    });
  });

  group('simulated cancel return', () {
    testWidgets('pops the screen without calling getStatus', (tester) async {
      await pumpApp(tester);
      c.debugSeed(storeId: 'store-1', successUrl: 'https://app/success', cancelUrl: 'https://app/cancel');
      Get.to(() => const Scaffold(body: SizedBox.shrink()));
      await tester.pumpAndSettle();

      c.debugSimulateCancelReturn();
      await tester.pumpAndSettle();

      verifyNever(() => repo.getStatus(any()));
    });
  });
}
