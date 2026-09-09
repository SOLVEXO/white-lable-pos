// Unit tests for SellerPosManagementController's employee/register/shift
// CRUD against mocked PosRepository. onInit's _loadAll() is never triggered
// (constructed directly, not via Get.put) — storeId is seeded directly
// instead. Follows the same ResponsiveSizer + settled-snackbar pattern as
// the other controller test files; addEmployee/addRegister/addShift all
// call Get.back() on success, so those specific tests push an extra route
// first (see pos_sale_detail_actions_test.dart's discard() test for why).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/common_models/store_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_session_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/repositories/seller_repository.dart';
import 'package:solvexo_pos/app/modules/seller_pos_management/controllers/seller_pos_management_controller.dart';

class MockPosRepository extends Mock implements PosRepository {}

class MockSellerRepository extends Mock implements SellerRepository {}

PosEmployeeModel _employee({String id = 'emp-1'}) => PosEmployeeModel(
      id: id,
      storeId: 'store-1',
      sellerId: 'seller-1',
      name: 'Cashier One',
      email: 'cashier@example.com',
      role: 'cashier',
      shiftIds: const [],
      status: 'active',
      createdAt: DateTime(2026, 1, 1),
    );

const _register = StoreRegister(id: 'register-1', name: 'Front Counter', defaultFloatCash: 100, status: 'active');

const _shift = StoreShift(
  id: 'shift-1',
  name: 'Morning',
  startTime: '08:00',
  endTime: '16:00',
  daysOfWeek: [1, 2, 3, 4, 5],
  status: 'active',
);

void main() {
  late MockPosRepository posRepo;
  late MockSellerRepository sellerRepo;
  late SellerPosManagementController c;

  setUpAll(() {
    Get.testMode = true;
    // addRegister()/addShift() call _loadAll() on success, which reads
    // AppPreferences.getStoreId() — real SharedPreferences with no mock
    // backing store never completes the awaited call at all. Seed the same
    // 'store_id' key _loadAll() reads so it doesn't overwrite storeId.value
    // (set directly in setUp below) with an empty string and bail out.
    SharedPreferences.setMockInitialValues({'store_id': 'store-1'});
  });

  setUp(() {
    posRepo = MockPosRepository();
    sellerRepo = MockSellerRepository();
    c = SellerPosManagementController(posRepository: posRepo, sellerRepository: sellerRepo);
    c.storeId.value = 'store-1';
  });

  tearDown(() {
    c.empNameCtrl.dispose();
    c.empEmailCtrl.dispose();
    c.empPinCtrl.dispose();
    c.regNameCtrl.dispose();
    c.shiftNameCtrl.dispose();
    c.shiftStartCtrl.dispose();
    c.shiftEndCtrl.dispose();
  });

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
        ResponsiveSizer(
          builder: (context, orientation, screenType) =>
              GetMaterialApp(home: const Scaffold(body: SizedBox.shrink())),
        ),
      );

  Future<void> settleSnackbar(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
  }

  // For actions that end with Get.back() — pushes a second route first so
  // that pop lands back on this one instead of tearing down the root
  // Scaffold's Overlay mid-snackbar-animation.
  Future<void> pushDummyRoute(WidgetTester tester) async {
    Get.to(() => const Scaffold(body: SizedBox.shrink()));
    await tester.pumpAndSettle();
  }

  group('addEmployee', () {
    testWidgets('rejects an incomplete form without calling the repository', (tester) async {
      await pumpApp(tester);
      c.empNameCtrl.text = 'Cashier One';
      // email and PIN left blank

      await c.addEmployee();
      await settleSnackbar(tester);

      verifyNever(() => posRepo.createEmployee(
            storeId: any(named: 'storeId'),
            name: any(named: 'name'),
            email: any(named: 'email'),
            role: any(named: 'role'),
            pin: any(named: 'pin'),
            shiftIds: any(named: 'shiftIds'),
          ));
    });

    testWidgets('rejects a non-4-digit PIN without calling the repository', (tester) async {
      await pumpApp(tester);
      c.empNameCtrl.text = 'Cashier One';
      c.empEmailCtrl.text = 'cashier@example.com';
      c.empPinCtrl.text = '12'; // too short

      await c.addEmployee();
      await settleSnackbar(tester);

      verifyNever(() => posRepo.createEmployee(
            storeId: any(named: 'storeId'),
            name: any(named: 'name'),
            email: any(named: 'email'),
            role: any(named: 'role'),
            pin: any(named: 'pin'),
            shiftIds: any(named: 'shiftIds'),
          ));
    });

    testWidgets('adds the employee to the list and clears the form on success', (tester) async {
      await pumpApp(tester);
      await pushDummyRoute(tester);
      c.empNameCtrl.text = 'Cashier One';
      c.empEmailCtrl.text = 'cashier@example.com';
      c.empPinCtrl.text = '1234';
      when(() => posRepo.createEmployee(
            storeId: any(named: 'storeId'),
            name: any(named: 'name'),
            email: any(named: 'email'),
            role: any(named: 'role'),
            pin: any(named: 'pin'),
            shiftIds: any(named: 'shiftIds'),
          )).thenAnswer((_) async => _employee());

      await c.addEmployee();
      await settleSnackbar(tester);

      expect(c.employees, hasLength(1));
      expect(c.empNameCtrl.text, isEmpty, reason: 'form clears after a successful add');
    });
  });

  group('deleteEmployee', () {
    testWidgets('removes the employee from the list on success', (tester) async {
      await pumpApp(tester);
      final emp = _employee();
      c.employees.add(emp);
      when(() => posRepo.deleteEmployee('store-1', 'emp-1')).thenAnswer((_) async => true);

      await c.deleteEmployee(emp);
      await settleSnackbar(tester);

      expect(c.employees, isEmpty);
      expect(c.deletingEmployeeId.value, isEmpty);
    });

    testWidgets('keeps the employee in the list when the repository reports failure', (tester) async {
      await pumpApp(tester);
      final emp = _employee();
      c.employees.add(emp);
      when(() => posRepo.deleteEmployee('store-1', 'emp-1')).thenAnswer((_) async => false);

      await c.deleteEmployee(emp);

      expect(c.employees, hasLength(1));
    });
  });

  group('registers', () {
    testWidgets('addRegister rejects an empty name without calling the repository', (tester) async {
      await pumpApp(tester);

      await c.addRegister();
      await settleSnackbar(tester);

      verifyNever(() => posRepo.createRegister(storeId: any(named: 'storeId'), name: any(named: 'name')));
    });

    // No pushDummyRoute/settleSnackbar here (unlike the other success
    // tests) — addRegister() pops the current route, shows a snackbar,
    // *then* runs a full _loadAll() reload before returning, and that
    // extra work interleaved with the pop+snackbar reliably hung the test
    // (see discard()'s comment in pos_sale_detail_actions_test.dart for
    // the same underlying GetX-in-tests fragility). A single bare pump is
    // enough since nothing here depends on the snackbar's animation.
    testWidgets('addRegister reloads all data on success', (tester) async {
      await pumpApp(tester);
      c.regNameCtrl.text = 'Back Counter';
      when(() => posRepo.createRegister(storeId: any(named: 'storeId'), name: any(named: 'name')))
          .thenAnswer((_) async => true);
      when(() => posRepo.getEmployees(any())).thenAnswer((_) async => <PosEmployeeModel>[]);
      when(() => sellerRepo.getStoreById(any())).thenAnswer((_) async => null);
      when(() => posRepo.getSessionHistory(storeId: any(named: 'storeId'))).thenAnswer(
          (_) async => (items: <PosSessionModel>[], total: 0, totalPages: 0, hasMore: false));
      when(() => posRepo.getDailyReport(any())).thenAnswer((_) async => null);

      await c.addRegister();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      verify(() => posRepo.getEmployees('store-1')).called(1);
      expect(c.regNameCtrl.text, isEmpty);
    });

    testWidgets('updateRegister replaces the register in place on success', (tester) async {
      await pumpApp(tester);
      c.registers.add(_register);
      const updated = StoreRegister(id: 'register-1', name: 'Renamed', defaultFloatCash: 100, status: 'active');
      when(() => posRepo.updateRegister(
            storeId: any(named: 'storeId'),
            registerId: any(named: 'registerId'),
            name: any(named: 'name'),
            status: any(named: 'status'),
          )).thenAnswer((_) async => updated);

      await c.updateRegister(_register, name: 'Renamed');
      await settleSnackbar(tester);

      expect(c.registers.single.name, 'Renamed');
      expect(c.processingRegisterId.value, isEmpty);
    });

    testWidgets('deleteRegister removes it from the list on success', (tester) async {
      await pumpApp(tester);
      c.registers.add(_register);
      when(() => posRepo.deleteRegister('store-1', 'register-1')).thenAnswer((_) async => true);

      await c.deleteRegister(_register);
      await settleSnackbar(tester);

      expect(c.registers, isEmpty);
    });
  });

  group('shifts', () {
    testWidgets('addShift rejects an incomplete form without calling the repository', (tester) async {
      await pumpApp(tester);
      c.shiftNameCtrl.text = 'Morning';
      // start/end left blank

      await c.addShift();
      await settleSnackbar(tester);

      verifyNever(() => posRepo.createShift(
            storeId: any(named: 'storeId'),
            name: any(named: 'name'),
            startTime: any(named: 'startTime'),
            endTime: any(named: 'endTime'),
          ));
    });

    testWidgets('deleteShift removes it from the list on success', (tester) async {
      await pumpApp(tester);
      c.shifts.add(_shift);
      when(() => posRepo.deleteShift('store-1', 'shift-1', force: false)).thenAnswer((_) async => true);

      final result = await c.deleteShift(_shift);
      await settleSnackbar(tester);

      expect(result, isTrue);
      expect(c.shifts, isEmpty);
    });

    testWidgets('deleteShift returns false and keeps the shift when the backend reports assigned employees',
        (tester) async {
      await pumpApp(tester);
      c.shifts.add(_shift);
      when(() => posRepo.deleteShift('store-1', 'shift-1', force: false)).thenAnswer((_) async => false);

      final result = await c.deleteShift(_shift);

      expect(result, isFalse);
      expect(c.shifts, hasLength(1));
    });
  });
}
