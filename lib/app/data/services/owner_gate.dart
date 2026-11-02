import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/services/owner_session.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// "Only the owner may do this" for a registered device. [ensure] returns true when the owner's elevated session is live
/// (extending it) or when the owner just re-authenticated with their password on the gate screen; false when they backed out.
/// On a terminal that is not registered yet (the owner's own session is still the stored one) there is nothing to gate.
class OwnerGate {
  OwnerGate._();

  static bool get required => AppPreferences.cachedDeviceMode && !OwnerSession.isActive;

  static Future<bool> ensure() async {
    if (!AppPreferences.cachedDeviceMode) return true;
    if (OwnerSession.isActive) {
      OwnerSession.touch();
      return true;
    }
    return (await Get.toNamed<bool>(Routes.posOwnerGate)) == true;
  }
}
