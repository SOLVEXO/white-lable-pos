import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/services/owner_session.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// Shared helpers of the G3.1 inventory controllers.
Future<String> invStoreId(String? override) async => override ?? (await AppPreferences.getStoreId()) ?? '';

/// A first guess of the role BEFORE the server's `overview.role` is known (only decides what is shown; the server enforces).
Future<String> invGuessRole() async {
  if (OwnerSession.isActive) return InvRole.owner;
  return (await AppPreferences.getPosEmployeeRole()) == 'manager' ? InvRole.manager : InvRole.cashier;
}
