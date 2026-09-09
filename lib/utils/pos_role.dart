import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// The POS employee role model (cashier/manager, set when a store owner
/// adds staff — distinct from the app-level "seller" role that gates the
/// whole terminal). See [isCurrentEmployeeManager]'s doc comment for what
/// this actually guards.
class PosRole {
  static const manager = 'manager';
  static const cashier = 'cashier';

  /// Pure decision logic, separated from the AppPreferences read so it's
  /// directly unit-testable — see pos_role_test.dart.
  static bool isManagerRole(String? role) => role == manager;

  /// Whether the currently PIN-logged-in employee is a manager.
  ///
  /// This mirrors the backend's real enforcement on refund/void/cash
  /// in-out/discounts: the backend independently verifies the employee's
  /// signed PIN-login token (see AppPreferences.setPosEmployeeToken) and
  /// its `role` claim — it does not trust anything from this client-side
  /// check. Gating the UI here is what makes a cashier's experience clean
  /// (a clear explanation instead of the backend's 403), not the source of
  /// the actual authorization decision — that's the token, verified
  /// server-side on every privileged call.
  static Future<bool> isCurrentEmployeeManager() async {
    final role = await AppPreferences.getPosEmployeeRole();
    return isManagerRole(role);
  }
}
