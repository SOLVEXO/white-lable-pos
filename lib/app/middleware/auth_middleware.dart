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
class PosAccessMiddleware extends GetMiddleware {
  final bool requireActiveSession;

  PosAccessMiddleware({this.requireActiveSession = false});

  @override
  int? get priority => 1;

  @override
  GetPage? onPageCalled(GetPage? page) {
    _check();
    return page;
  }

  Future<void> _check() async {
    final token = await AppPreferences.getAccessTokenAsync();
    if (token == null || token.isEmpty) {
      await AppPreferences.clearTokens();
      Get.offAllNamed(Routes.posLogin);
      return;
    }

    final role = await AppPreferences.getUserRole();
    if (role != 'seller') {
      Get.offAllNamed(Routes.posLogin);
      return;
    }

    if (requireActiveSession && !await AppPreferences.hasPosSession()) {
      Get.offAllNamed(Routes.posPinLogin);
    }
  }
}
