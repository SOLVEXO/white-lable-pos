// G6.3: "Open register" on Home (register closed) goes to the PIN sign-in, and a successful PIN with no open shift lands DIRECTLY on the
// open-register form — not back on Home. Home stays underneath, so Back from the form returns there.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/repositories/inventory_repository.dart';
import 'package:solvexo_pos/app/data/repositories/seller_repository.dart';
import 'package:solvexo_pos/app/modules/pos/controllers/pos_home_tab_controller.dart';
import 'package:solvexo_pos/app/modules/pos/utils/pos_access.dart';
import 'package:solvexo_pos/app/modules/pos/views/pos_home_tab_view.dart';
import 'package:solvexo_pos/app/modules/pos_pin_login/controllers/pos_pin_login_controller.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

import 'support/fake_payments.dart';
import 'support/sale_harness.dart' show MockPosRepository;

class _Inv extends Mock implements InventoryRepository {}

class _Seller extends Mock implements SellerRepository {}

PosEmployeeModel _employee() => PosEmployeeModel(
      id: 'emp-1', storeId: 'store-1', sellerId: 'seller-1', name: 'Mia Manager', email: 'mia@example.com', role: 'manager',
      shiftIds: const [], status: 'active', createdAt: DateTime(2026),
    );

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async => null);
  });
  tearDown(Get.reset);

  testWidgets('Home "Open register" → PIN sign-in → after a correct PIN the open-register form, with Home underneath', (t) async {
    SharedPreferences.setMockInitialValues({'store_id': 'store-1', 'pos_employee_role': 'manager'});
    await AppPreferences.warmCache(); // no shift on this till
    t.view.physicalSize = const Size(390, 2600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    final pos = MockPosRepository();
    final inv = _Inv();
    when(() => pos.getDashboard(any())).thenAnswer((_) async => null);
    when(() => pos.getDailyReport(any())).thenAnswer((_) async => null);
    when(() => pos.getRangeReport(any(), from: any(named: 'from'), to: any(named: 'to'))).thenAnswer((_) async => null);
    when(() => inv.getLowStockSummary(any())).thenAnswer((_) async => null);
    // the PIN step: correct PIN, no open shift for this employee, and the picked register is not open either
    when(() => pos.pinLogin(storeId: any(named: 'storeId'), email: any(named: 'email'), pin: any(named: 'pin')))
        .thenAnswer((_) async => (success: true, employee: _employee(), activeSession: null, employeeToken: 'tok', message: null));
    when(() => pos.getActiveSession(storeId: any(named: 'storeId'), registerId: any(named: 'registerId'))).thenAnswer((_) async => null);

    final home = PosHomeTabController(posRepository: pos, inventoryRepository: inv, paymentsRepository: FakePaymentsRepo(), accessOverride: PosAccess.manager);
    Get.put<PosHomeTabController>(home);
    final pin = PosPinLoginController(posRepository: pos, sellerRepository: _Seller())
      ..storeId.value = 'store-1'
      ..registers.assignAll([
        {'id': 'register-1', 'name': 'Front Counter'},
      ])
      ..selectedRegister.value = {'id': 'register-1', 'name': 'Front Counter'};
    pin.emailController.text = 'mia@example.com';

    Object? openArgs;
    await t.pumpWidget(GetMaterialApp(
      theme: AppTheme.light,
      initialRoute: Routes.posHome,
      getPages: [
        GetPage(name: Routes.posHome, page: () => PosHomeTabView(controller: home)),
        GetPage(name: Routes.posPinLogin, page: () => const Scaffold(body: Text('PIN SIGN-IN'))),
        GetPage(name: Routes.posOpenRegister, page: () {
          openArgs = Get.arguments;
          return const Scaffold(body: Text('OPEN REGISTER FORM'));
        }),
      ],
    ));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Register closed'), findsOneWidget);
    await t.tap(find.byKey(const Key('homeRegisterOpen')));
    await t.pumpAndSettle();
    expect(Get.currentRoute, Routes.posPinLogin);

    for (final d in '1111'.split('')) {
      pin.appendDigit(d);
    }
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.pumpAndSettle();

    expect(Get.currentRoute, Routes.posOpenRegister, reason: 'a correct PIN lands on the open-register form, not back on Home');
    expect(find.text('OPEN REGISTER FORM'), findsOneWidget);
    expect((openArgs as Map)['registerId'], 'register-1');
    expect((openArgs as Map)['employee'], isA<PosEmployeeModel>());
    // the PIN screen was replaced, so Back from the form returns to Home (not to the PIN pad)
    Get.back();
    await t.pumpAndSettle();
    expect(Get.currentRoute, Routes.posHome);
  });
}
