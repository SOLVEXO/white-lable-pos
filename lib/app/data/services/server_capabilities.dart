import 'package:get/get.dart';

/// G6.1 — what the connected backend can do, learned from its answers (no version call needed). The production API may still be the G5.1
/// backend (c889af0) while this app is in closed testing: the features of backend release #2 (G5.2–G5.7: product page, receipt sending,
/// payments setup, fiscal, receipt logo, presets, integrations, API keys) are then hidden instead of failing on screens people use.
class ServerCapabilities {
  /// `GET /api/pos/connectors` answered 404 → the backend predates release #2. null = not known yet (offline / not asked) → shown as before.
  static final RxnBool releaseTwo = RxnBool();

  /// true only when the server has told us it is older (a network error never hides anything)
  static bool get olderServer => releaseTwo.value == false;

  static void learnFromConnectors({required bool found, int? httpStatus}) {
    if (found) {
      releaseTwo.value = true;
    } else if (httpStatus == 404) {
      releaseTwo.value = false;
    }
  }
}
