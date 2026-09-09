// Unit tests for PosPinLoginController's PIN-submit flow against mocked
// PosRepository/SellerRepository. onInit (which calls _loadStore(),
// touching AppPreferences + SellerRepository) is never triggered here since
// the controller is constructed directly rather than via Get.put/bindings —
// storeId/selectedRegister are seeded directly instead, matching the other
// controller test files' pattern.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_session_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/repositories/seller_repository.dart';
import 'package:solvexo_pos/app/modules/pos_pin_login/controllers/pos_pin_login_controller.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';

class MockPosRepository extends Mock implements PosRepository {}

class MockSellerRepository extends Mock implements SellerRepository {}

PosEmployeeModel _employee() => PosEmployeeModel(
      id: 'emp-1',
      storeId: 'store-1',
      sellerId: 'seller-1',
      name: 'Cashier One',
      email: 'cashier@example.com',
      role: 'cashier',
      shiftIds: const ['shift-1'],
      status: 'active',
      createdAt: DateTime(2026, 1, 1),
    );

PosSessionModel _session({required String registerId, required String status}) => PosSessionModel(
      id: 'session-1',
      storeId: 'store-1',
      registerId: registerId,
      employeeId: 'emp-1',
      shiftId: 'shift-1',
      openedAt: DateTime(2026, 1, 1),
      openingCash: 100,
      expectedCash: 100,
      cashDifference: 0,
      cashSales: 0,
      cardSales: 0,
      otherSales: 0,
      totalSales: 0,
      totalTransactions: 0,
      totalRefunds: 0,
      status: status,
      cashAdjustments: const [],
    );

void main() {
  late MockPosRepository posRepo;
  late MockSellerRepository sellerRepo;
  late PosPinLoginController c;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    registerFallbackValue(_employee());
    // setPosEmployeeToken writes through flutter_secure_storage, a real
    // platform channel with no test double registered by default — left
    // unmocked, the awaited native call never completes at all (not even
    // a thrown MissingPluginException), silently hanging every test on
    // the success path forever.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  setUp(() {
    posRepo = MockPosRepository();
    sellerRepo = MockSellerRepository();
    c = PosPinLoginController(posRepository: posRepo, sellerRepository: sellerRepo);
    c.storeId.value = 'store-1';
    c.registers.assignAll([
      {'id': 'register-1', 'name': 'Front Counter'},
    ]);
    c.selectedRegister.value = {'id': 'register-1', 'name': 'Front Counter'};
    c.emailController.text = 'cashier@example.com';
  });

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
        ResponsiveSizer(
          builder: (context, orientation, screenType) => GetMaterialApp(
            initialRoute: '/pin-login',
            getPages: [
              GetPage(name: '/pin-login', page: () => const Scaffold(body: SizedBox.shrink())),
              GetPage(name: Routes.posHome, page: () => const Scaffold(body: SizedBox.shrink())),
              GetPage(name: Routes.posOpenRegister, page: () => const Scaffold(body: SizedBox.shrink())),
            ],
          ),
        ),
      );

  Future<void> enterPin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      c.appendDigit(digit);
    }
    // The 4th digit triggers _submit() internally without appendDigit
    // awaiting it — pump repeatedly so every awaited call inside _submit
    // (pinLogin, then possibly getActiveSession, then AppPreferences
    // writes) gets a chance to resolve, without pumpAndSettle's risk of
    // hanging forever against the snackbar's still-running animation.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('a 4th digit with an active session on the picked register goes straight to POS home',
      (tester) async {
    await pumpApp(tester);
    when(() => posRepo.pinLogin(storeId: any(named: 'storeId'), email: any(named: 'email'), pin: any(named: 'pin')))
        .thenAnswer((_) async => (
              success: true,
              employee: _employee(),
              activeSession: _session(registerId: 'register-1', status: 'open'),
              employeeToken: 'token-abc',
              message: null,
            ));

    // No settleSnackbar here — this success path never shows one, and
    // Get.offAllNamed replaces the whole route stack (including the root
    // Overlay); waiting extra frames against a route that's already gone
    // is exactly what corrupted GetX's static navigator key for later
    // tests in this file when this used the same pattern as the others.
    await enterPin(tester, '1234');
    await tester.pumpAndSettle();

    verify(() => posRepo.pinLogin(storeId: 'store-1', email: 'cashier@example.com', pin: '1234')).called(1);
    expect(Get.currentRoute, Routes.posHome);
  });

  testWidgets('an active session on a different register warns instead of resuming onto it', (tester) async {
    await pumpApp(tester);
    when(() => posRepo.pinLogin(storeId: any(named: 'storeId'), email: any(named: 'email'), pin: any(named: 'pin')))
        .thenAnswer((_) async => (
              success: true,
              employee: _employee(),
              activeSession: _session(registerId: 'register-9', status: 'open'),
              employeeToken: 'token-abc',
              message: null,
            ));

    await enterPin(tester, '1234');
    // pumpAndSettle alone stops once the snackbar's entrance animation
    // finishes scheduling frames — it doesn't know to wait out the
    // separate 3s display Timer that triggers the exit animation, so a
    // bare pumpAndSettle() here leaves that Timer pending at test
    // teardown. Force past it explicitly first.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(Get.currentRoute, '/pin-login', reason: 'must not silently resume onto an unpicked register');
    expect(c.pin.value, isEmpty, reason: 'PIN is cleared after the warning');
  });

  testWidgets('no active session but the picked register is already open by someone else resumes onto it',
      (tester) async {
    await pumpApp(tester);
    when(() => posRepo.pinLogin(storeId: any(named: 'storeId'), email: any(named: 'email'), pin: any(named: 'pin')))
        .thenAnswer((_) async =>
            (success: true, employee: _employee(), activeSession: null, employeeToken: 'token-abc', message: null));
    when(() => posRepo.getActiveSession(storeId: any(named: 'storeId'), registerId: any(named: 'registerId')))
        .thenAnswer((_) async => _session(registerId: 'register-1', status: 'open'));

    await enterPin(tester, '1234');
    await tester.pumpAndSettle();

    expect(Get.currentRoute, Routes.posHome);
  });

  testWidgets('no active session anywhere routes to Open Register with the right arguments', (tester) async {
    await pumpApp(tester);
    when(() => posRepo.pinLogin(storeId: any(named: 'storeId'), email: any(named: 'email'), pin: any(named: 'pin')))
        .thenAnswer((_) async =>
            (success: true, employee: _employee(), activeSession: null, employeeToken: 'token-abc', message: null));
    when(() => posRepo.getActiveSession(storeId: any(named: 'storeId'), registerId: any(named: 'registerId')))
        .thenAnswer((_) async => null);

    await enterPin(tester, '1234');
    await tester.pumpAndSettle();

    expect(Get.currentRoute, Routes.posOpenRegister);
    expect(Get.arguments['registerId'], 'register-1');
    expect(Get.arguments['storeId'], 'store-1');
  });

  testWidgets('an invalid PIN clears the pad and does not navigate', (tester) async {
    await pumpApp(tester);
    when(() => posRepo.pinLogin(storeId: any(named: 'storeId'), email: any(named: 'email'), pin: any(named: 'pin')))
        .thenAnswer((_) async =>
            (success: false, employee: null, activeSession: null, employeeToken: null, message: 'Invalid PIN'));

    await enterPin(tester, '0000');
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(c.pin.value, isEmpty);
    expect(Get.currentRoute, '/pin-login');
  });

  testWidgets('submitting with no register selected shows a warning and never calls the repository',
      (tester) async {
    await pumpApp(tester);
    c.selectedRegister.value = null;

    await enterPin(tester, '1234');
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    verifyNever(
        () => posRepo.pinLogin(storeId: any(named: 'storeId'), email: any(named: 'email'), pin: any(named: 'pin')));
    expect(c.pin.value, isEmpty);
  });
}
