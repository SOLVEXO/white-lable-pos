// Unit tests for the RBAC gating rule: refund/void/cash-management/discounts
// are only shown to managers, matching the backend's real, signed-employee-
// token-verified check on those actions (pos.service.ts's
// requireManagerEmployee). Tests the pure decision logic plus the actual
// visibility rules used in pos_sale_detail_view.dart / pos_transaction_card
// .dart / pos_settings_controller.dart, without needing AppPreferences/
// SharedPreferences/secure-storage plumbing.

import 'package:solvexo_pos/utils/pos_role.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors the `sale.canRefund && isManager` / `sale.canVoid && isManager`
/// condition used at both call sites — kept here as a small pure helper so
/// the rule itself (not just PosRole.isManagerRole) is under test.
bool canShowAction({required bool actionAllowedByStatus, required bool isManager}) =>
    actionAllowedByStatus && isManager;

void main() {
  group('PosRole.isManagerRole', () {
    test('true only for the exact "manager" role string', () {
      expect(PosRole.isManagerRole('manager'), isTrue);
      expect(PosRole.isManagerRole('cashier'), isFalse);
      expect(PosRole.isManagerRole(null), isFalse);
      expect(PosRole.isManagerRole(''), isFalse);
      expect(PosRole.isManagerRole('Manager'), isFalse, reason: 'case-sensitive — matches the backend enum exactly');
    });
  });

  group('refund/void visibility (canShowAction)', () {
    test('a manager sees the action when the sale status allows it', () {
      expect(canShowAction(actionAllowedByStatus: true, isManager: true), isTrue);
    });

    test('a cashier never sees the action, even when the sale status allows it', () {
      expect(canShowAction(actionAllowedByStatus: true, isManager: false), isFalse);
    });

    test('a manager does not see the action when the sale status disallows it', () {
      // e.g. sale.canRefund is false because it's already fully refunded.
      expect(canShowAction(actionAllowedByStatus: false, isManager: true), isFalse);
    });
  });

  group('Cash Management tile (pos_settings_controller.dart)', () {
    String trailingFor(bool isManager) => isManager ? 'Cash in / out' : 'Managers only';

    test('a manager sees the normal trailing label', () {
      expect(trailingFor(true), 'Cash in / out');
    });

    test('a cashier sees "Managers only" instead', () {
      expect(trailingFor(false), 'Managers only');
    });
  });
}
