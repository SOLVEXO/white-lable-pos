// Unit tests for PosOpenRegisterController's session-open lifecycle against
// a mocked PosRepository. Follows the pattern established in
// pos_home_checkout_test.dart / pos_sale_detail_actions_test.dart:
// ResponsiveSizer-wrapped GetMaterialApp + settled snackbars. This
// controller's success path also calls Get.offAllNamed(Routes.posHome), so
// that route must exist in the test app's route table, and
// AppPreferences.savePosSession touches real SharedPreferences, so that's
// given a mock backing store.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_session_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_open_register/controllers/pos_open_register_controller.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';

class MockPosRepository extends Mock implements PosRepository {}

PosEmployeeModel _employee({List<String> shiftIds = const ['shift-1']}) => PosEmployeeModel(
      id: 'emp-1',
      storeId: 'store-1',
      sellerId: 'seller-1',
      name: 'Cashier One',
      email: 'cashier@example.com',
      role: 'cashier',
      shiftIds: shiftIds,
      status: 'active',
      createdAt: DateTime(2026, 1, 1),
    );

PosSessionModel _session() => PosSessionModel(
      id: 'session-1',
      storeId: 'store-1',
      registerId: 'register-1',
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
      status: 'open',
      cashAdjustments: const [],
    );

void main() {
  late MockPosRepository posRepo;
  late PosOpenRegisterController c;

  setUpAll(() {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() {
    posRepo = MockPosRepository();
    c = PosOpenRegisterController(posRepository: posRepo);
    c.employee = _employee();
    c.registerId = 'register-1';
    c.registerName = 'Front Counter';
    c.storeId = 'store-1';
    c.openingCashController.text = '100';
  });

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
        ResponsiveSizer(
          builder: (context, orientation, screenType) => GetMaterialApp(
            initialRoute: '/open-register',
            getPages: [
              GetPage(name: '/open-register', page: () => const Scaffold(body: SizedBox.shrink())),
              GetPage(name: Routes.posHome, page: () => const Scaffold(body: SizedBox.shrink())),
            ],
          ),
        ),
      );

  Future<void> settleSnackbar(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
  }

  testWidgets('openRegister calls openSession with the entered cash and navigates to POS home on success',
      (tester) async {
    await pumpApp(tester);
    when(() => posRepo.openSession(
          storeId: any(named: 'storeId'),
          registerId: any(named: 'registerId'),
          employeeId: any(named: 'employeeId'),
          shiftId: any(named: 'shiftId'),
          openingCash: any(named: 'openingCash'),
        )).thenAnswer((_) async => (success: true, session: _session(), message: null));

    await c.openRegister();
    await settleSnackbar(tester);
    await tester.pumpAndSettle();

    final captured = verify(() => posRepo.openSession(
          storeId: 'store-1',
          registerId: 'register-1',
          employeeId: 'emp-1',
          shiftId: 'shift-1',
          openingCash: captureAny(named: 'openingCash'),
        )).captured;
    expect(captured.single, 100.0);
    expect(Get.currentRoute, Routes.posHome);
  });

  testWidgets('openRegister rejects a non-numeric cash amount without calling the repository', (tester) async {
    await pumpApp(tester);
    c.openingCashController.text = 'not a number';

    await c.openRegister();
    await settleSnackbar(tester);

    verifyNever(() => posRepo.openSession(
          storeId: any(named: 'storeId'),
          registerId: any(named: 'registerId'),
          employeeId: any(named: 'employeeId'),
          shiftId: any(named: 'shiftId'),
          openingCash: any(named: 'openingCash'),
        ));
  });

  testWidgets('openRegister rejects a negative cash amount without calling the repository', (tester) async {
    await pumpApp(tester);
    c.openingCashController.text = '-5';

    await c.openRegister();
    await settleSnackbar(tester);

    verifyNever(() => posRepo.openSession(
          storeId: any(named: 'storeId'),
          registerId: any(named: 'registerId'),
          employeeId: any(named: 'employeeId'),
          shiftId: any(named: 'shiftId'),
          openingCash: any(named: 'openingCash'),
        ));
  });

  testWidgets('openRegister refuses to open with no shift assigned to the employee', (tester) async {
    await pumpApp(tester);
    c.employee = _employee(shiftIds: const []);

    await c.openRegister();
    await settleSnackbar(tester);

    verifyNever(() => posRepo.openSession(
          storeId: any(named: 'storeId'),
          registerId: any(named: 'registerId'),
          employeeId: any(named: 'employeeId'),
          shiftId: any(named: 'shiftId'),
          openingCash: any(named: 'openingCash'),
        ));
  });

  testWidgets('openRegister surfaces a failure without navigating away', (tester) async {
    await pumpApp(tester);
    when(() => posRepo.openSession(
          storeId: any(named: 'storeId'),
          registerId: any(named: 'registerId'),
          employeeId: any(named: 'employeeId'),
          shiftId: any(named: 'shiftId'),
          openingCash: any(named: 'openingCash'),
        )).thenAnswer((_) async => (success: false, session: null, message: 'This register already has an open session.'));

    await c.openRegister();
    await settleSnackbar(tester);

    expect(c.isOpening.value, isFalse);
    expect(Get.currentRoute, '/open-register');
  });
}
