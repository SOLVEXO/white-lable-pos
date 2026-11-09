// G2.7: Orders search by the number on the customer's receipt (OFF-…, INV-…, CN-…) is STORE-wide (a return may happen at another till),
// and every refund/void goes through the one Return flow.
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_orders/controllers/pos_orders_controller.dart';

class _Repo extends Mock implements PosRepository {}

PosSaleModel _sale(String id) => PosSaleModel.fromJson({'_id': id, 'saleNumber': 'POS-$id', 'storeId': 'store-1', 'sessionId': 'other-till-shift', 'registerId': 'r-other', 'employeeId': 'e', 'status': 'completed', 'subtotal': 10.0, 'total': 10.0, 'paymentMethod': 'cash', 'customerName': 'Walk-in', 'createdAt': '2026-11-06T10:00:00.000Z', 'items': []});

void main() {
  late _Repo repo;
  setUp(() {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({'store_id': 'store-1'});
    repo = _Repo();
    when(() => repo.getPosSettings(any())).thenAnswer((_) async => null);
    when(() => repo.getSales(storeId: any(named: 'storeId'), sessionId: any(named: 'sessionId'), page: any(named: 'page'), from: any(named: 'from'), to: any(named: 'to'), paymentMethod: any(named: 'paymentMethod'), status: any(named: 'status'))).thenAnswer((_) async => (items: <PosSaleModel>[], hasMore: false, total: 0, totalPages: 1));
  });

  test('searching an OFF- number looks across the whole store (not this shift) and lists the sale found on another till', () async {
    when(() => repo.lookupSales(any(), 'OFF-AB12CD-0007')).thenAnswer((_) async => [_sale('1')]);
    final c = PosOrdersController(posRepository: repo);
    await c.searchByReceipt('  OFF-AB12CD-0007 ');
    expect(c.searchQuery.value, 'OFF-AB12CD-0007');
    expect(c.sales.single.id, '1');
    expect(c.hasMore, isFalse);
    verify(() => repo.lookupSales(any(), 'OFF-AB12CD-0007')).called(1);
  });

  test('clearing the search goes back to the normal list', () async {
    when(() => repo.lookupSales(any(), any())).thenAnswer((_) async => [_sale('1')]);
    final c = PosOrdersController(posRepository: repo);
    await c.searchByReceipt('INV-000001');
    await c.searchByReceipt('');
    expect(c.sales, isEmpty);
    verify(() => repo.getSales(storeId: any(named: 'storeId'), sessionId: any(named: 'sessionId'), page: any(named: 'page'), from: any(named: 'from'), to: any(named: 'to'), paymentMethod: any(named: 'paymentMethod'), status: any(named: 'status'))).called(1);
  });

  test('the old quick refund / void actions are gone from the Orders controller (single path: the Return flow)', () {
    final c = PosOrdersController(posRepository: repo) as dynamic;
    expect(() => c.refundSale(null), throwsA(isA<NoSuchMethodError>()));
    expect(() => c.voidSale(null), throwsA(isA<NoSuchMethodError>()));
  });
}
