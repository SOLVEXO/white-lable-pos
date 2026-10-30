// Restricted mode is driven ONLY by what the backend says: the plan status AND whether the backend is
// enforcing it. A failed status call must never lock a cashier out, and a store the server is not
// (yet) enforcing for must keep selling.

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_subscription_status_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_subscription_repository.dart';
import 'package:solvexo_pos/app/data/services/pos_entitlement_service.dart';

class MockRepo extends Mock implements PosSubscriptionRepository {}

PosSubscriptionStatusModel _status(String s, {bool enforced = true}) =>
    PosSubscriptionStatusModel.fromJson({'status': s, 'enforced': enforced});

void main() {
  late MockRepo repo;
  late PosEntitlementService service;

  setUp(() {
    Get.reset();
    repo = MockRepo();
    service = PosEntitlementService(repository: repo);
  });

  test('no plan + backend enforcing → restricted', () async {
    when(() => repo.getStatus('s1')).thenAnswer((_) async => _status('none'));
    expect(await service.checkPlan(storeId: 's1'), isTrue);
    expect(service.restricted.value, isTrue);
    expect(service.message.value, PosEntitlementService.planInactiveMessage);
  });

  test('expired + enforcing → restricted', () async {
    when(() => repo.getStatus('s1')).thenAnswer((_) async => _status('expired'));
    expect(await service.checkPlan(storeId: 's1'), isTrue);
  });

  test('no plan but the backend is NOT enforcing (report-only rollout) → NOT restricted', () async {
    when(() => repo.getStatus('s1')).thenAnswer((_) async => _status('none', enforced: false));
    expect(await service.checkPlan(storeId: 's1'), isFalse);
  });

  test('an older backend that does not send `enforced` is treated as not enforcing', () async {
    when(() => repo.getStatus('s1')).thenAnswer((_) async => PosSubscriptionStatusModel.fromJson({'status': 'none'}));
    expect(await service.checkPlan(storeId: 's1'), isFalse);
  });

  test('active plan → not restricted, and clears an earlier restriction', () async {
    service.markRestricted();
    when(() => repo.getStatus('s1')).thenAnswer((_) async => _status('active'));
    expect(await service.checkPlan(storeId: 's1'), isFalse);
    expect(service.restricted.value, isFalse);
    expect(service.message.value, isEmpty);
  });

  test('a FAILED status call changes nothing — a network blip never locks the till', () async {
    when(() => repo.getStatus('s1')).thenAnswer((_) async => PosSubscriptionStatusModel.unknown());
    expect(await service.checkPlan(storeId: 's1'), isFalse);
    service.markRestricted();
    expect(await service.checkPlan(storeId: 's1'), isTrue, reason: 'unknown must keep the previous state, not clear it');
  });

  test('markRestricted / clear drive the observable (server refusal with POS_PLAN_REQUIRED)', () {
    expect(service.restricted.value, isFalse);
    service.markRestricted();
    expect(service.restricted.value, isTrue);
    service.clear();
    expect(service.restricted.value, isFalse);
  });

  test('static helpers are safe when the service is not registered', () {
    expect(PosEntitlementService.maybe, isNull);
    expect(PosEntitlementService.isRestricted, isFalse);
    Get.put<PosEntitlementService>(service);
    service.markRestricted();
    expect(PosEntitlementService.isRestricted, isTrue);
  });
}
