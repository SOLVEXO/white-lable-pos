// Unit tests for PosSaleDetailController's refund/void/discard actions
// against a mocked PosRepository — mirrors pos_home_checkout_test.dart's
// pattern (ResponsiveSizer + settled snackbar) since these actions also
// call CustomAppSnackbar. `saleId` is a `late final` field normally set
// from Get.arguments in onInit; here it's assigned directly instead of
// going through GetX routing, then `_load()` (called internally after
// every successful action) is satisfied by stubbing getSaleById.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:solvexo_pos/app/components/reason_picker_sheet.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/app/modules/pos_sale_detail/controllers/pos_sale_detail_controller.dart';

class MockPosRepository extends Mock implements PosRepository {}

PosSaleModel _sale({String status = 'completed', double refundedAmount = 0}) => PosSaleModel(
      id: 'sale-1',
      saleNumber: 'S-0001',
      storeId: 'store-1',
      sessionId: 'session-1',
      registerId: 'register-1',
      employeeId: 'employee-1',
      items: [
        const PosSaleItemModel(saleItemId: 'item-1', productId: 'p1', name: 'Widget', qty: 2, price: 5, lineTotal: 10),
      ],
      discount: 0,
      tax: 0,
      subtotal: 10,
      total: 10,
      paymentMethod: 'cash',
      customerName: 'Walk-in',
      notes: '',
      status: status,
      refundedAmount: refundedAmount,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  late MockPosRepository posRepo;
  late PosSaleDetailController c;

  setUpAll(() {
    Get.testMode = true;
    // Not exercised by any of these tests (no printReceipt call), but the
    // controller's constructor requires one — a real ThermalPrinterService
    // would otherwise reach for Get.find() with nothing registered.
    Get.put<ThermalPrinterService>(ThermalPrinterService());
  });

  setUp(() {
    ReasonPicker.testOverride = (_) async => const PosReasonChoice('wrong_item', 'size M'); // the picker itself is tested in g24_screens_test
    posRepo = MockPosRepository();
    c = PosSaleDetailController(posRepository: posRepo);
    c.saleId = 'sale-1';
    // onInit/_load() are never called (no GetX routing here), so sale.value
    // — read by every action method before doing anything — must be seeded
    // directly rather than relying on the controller to have loaded it.
    c.sale.value = _sale();
    when(() => posRepo.getSaleById(any())).thenAnswer((_) async => _sale());
    // _load() (called internally after every successful action) also reads
    // settings for the currency symbol — an unstubbed Future-returning
    // mocktail method throws instead of resolving, and that unhandled
    // rejection was corrupting GetX's static navigator state for every
    // later test in this file.
    when(() => posRepo.getPosSettings(any())).thenAnswer((_) async => null);
  });

  tearDown(() => ReasonPicker.testOverride = null);

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
        ResponsiveSizer(
          builder: (context, orientation, screenType) =>
              GetMaterialApp(home: const Scaffold(body: SizedBox.shrink())),
        ),
      );

  // Deliberately last: discard() ends with Get.back(), which — with no
  // second route pushed to pop instead — tears down the root Scaffold's
  // Overlay while the just-shown snackbar's animation is still ticking.
  // That corrupts GetX's static navigator key for every test after it in
  // this file, so this one only pumps once (starts the snackbar animating,
  // doesn't wait for it to finish) rather than settling it like the others.
  testWidgets('discard calls discardSale', (tester) async {
    await pumpApp(tester);
    when(() => posRepo.discardSale(any(), reasonCode: any(named: 'reasonCode'), reason: any(named: 'reason'))).thenAnswer((_) async => true);

    await c.discard();
    await tester.pump();

    verify(() => posRepo.discardSale('sale-1', reasonCode: 'wrong_item', reason: 'size M')).called(1);
  });
}
