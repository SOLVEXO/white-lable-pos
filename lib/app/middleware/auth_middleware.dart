import 'package:solvexo_pos/app/data/services/pos_entitlement_service.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:get/get.dart';

/// Guards the POS terminal screens. Every POS backend endpoint requires the
/// store owner's own `seller` JWT — there is no separate "pos" account role,
/// so this checks for `role == 'seller'` (the locally-cached role; see
/// SellerOnboardingController.complete() for how a brand-new signup gets
/// flipped to 'seller' after creating their first store).
///
/// [requireActiveSession] additionally requires a PIN-logged-in employee with
/// an open register session (tracked locally via [AppPreferences] POS keys).
/// Use this on the POS terminal shell and its tabs; leave it false for the
/// PIN-login and open-register screens themselves, which establish that
/// session in the first place.
///
/// [allowWhenRestricted] marks the screens that stay reachable in *restricted mode* (the store has no
/// active POS plan and the backend is enforcing it — see [PosEntitlementService]): the shell, Orders /
/// sale detail (refund + void), reports, shift history and Settings (close shift, sign out). There, a
/// PIN-logged-in cashier with no open session is let through instead of being bounced to PIN login,
/// because there is nothing to open and nothing to sell.
class PosAccessMiddleware extends GetMiddleware {
  final bool requireActiveSession;
  final bool allowWhenRestricted;

  PosAccessMiddleware({this.requireActiveSession = false, this.allowWhenRestricted = false});

  @override
  int? get priority => 1;

  @override
  GetPage? onPageCalled(GetPage? page) {
    // Synchronous — checked against AppPreferences' in-memory cache (warmed
    // at boot in main.dart) rather than awaiting SharedPreferences, so a
    // redirect happens before this page is ever returned/rendered instead of
    // one frame after (see AppPreferences.warmCache doc comment).
    final token = AppPreferences.cachedToken;
    if (token == null || token.isEmpty) {
      AppPreferences.clearTokens();
      Get.offAllNamed(Routes.posLogin);
      return page;
    }

    if (AppPreferences.cachedRole != 'seller') {
      Get.offAllNamed(Routes.posLogin);
      return page;
    }

    if (requireActiveSession && !AppPreferences.cachedHasPosSession) {
      if (allowWhenRestricted && PosEntitlementService.isRestricted) return page;
      Get.offAllNamed(Routes.posPinLogin);
    }
    return page;
  }
}
