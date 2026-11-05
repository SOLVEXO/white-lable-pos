/// Whether the Raast QR tender can be used right now, and the words to show when it cannot.
///
/// The server is the real gate (`403 STORE_NOT_VERIFIED`, offline = no answer); this only decides what the chooser shows so the
/// cashier is not offered something that will be refused. [verified] is the server's `digitalPaymentsEnabled` flag for the store;
/// `null` = not known (an older server, or the status call failed) → the option stays usable and the server's answer is shown.
enum QrAvailability { available, needsInternet, notVerified }

class QrAvailabilityInfo {
  const QrAvailabilityInfo(this.availability, this.message);
  final QrAvailability availability;
  final String? message;
  bool get isAvailable => availability == QrAvailability.available;
}

abstract final class QrAvailabilityRules {
  static const cashierNotVerified = 'Not available for this store yet';
  static const managerNotVerified = 'Business verification required';
  static const needsInternet = 'Raast QR needs internet';

  static QrAvailabilityInfo evaluate({required bool? verified, required bool online, required bool isManager}) {
    if (verified == false) {
      return QrAvailabilityInfo(QrAvailability.notVerified, isManager ? managerNotVerified : cashierNotVerified);
    }
    if (!online) return const QrAvailabilityInfo(QrAvailability.needsInternet, needsInternet);
    return const QrAvailabilityInfo(QrAvailability.available, null);
  }
}
