import 'package:solvexo_pos/app/data/services/owner_session.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/pos_role.dart';

/// Who is using the till, for deciding what the navigation SHOWS. This is a convenience for a clean UI only — the server
/// still enforces every rule from the signed PIN token / owner JWT on each call (never trusted from here).
///
///  * cashier — the PIN-logged-in employee is a cashier and no owner session is open,
///  * manager — the PIN-logged-in employee is a manager,
///  * owner   — an owner session is open on this device (the owner gate was passed).
enum PosAccess {
  cashier,
  manager,
  owner;

  /// Pure decision, so it is unit-testable without preferences.
  static PosAccess resolve({required String? employeeRole, required bool ownerSessionActive}) {
    if (ownerSessionActive) return PosAccess.owner;
    return PosRole.isManagerRole(employeeRole) ? PosAccess.manager : PosAccess.cashier;
  }

  static Future<PosAccess> current() async => resolve(employeeRole: await AppPreferences.getPosEmployeeRole(), ownerSessionActive: OwnerSession.isActive);

  /// Manager or owner: sees business numbers and the management rows (each still goes through its own gate / PIN).
  bool get canManage => this != PosAccess.cashier;
  bool get isOwner => this == PosAccess.owner;
}
