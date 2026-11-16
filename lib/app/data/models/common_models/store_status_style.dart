import 'package:solvexo_pos/core/design/design.dart' show StatusTone;

/// Label + tone for a [StoreModel.status] value — shared by every place
/// that renders a store status badge (`store_meta_card.dart`,
/// `seller_stores/widgets/store_card.dart`, `store_verification_card.dart`)
/// so the mapping can't drift between screens. No new enum: `status` stays
/// the raw backend string — marketplace LISTING lifecycle only
/// (`pending|active|rejected|suspended`). The KYC review's own state lives
/// separately on `verificationStatus` — see [verificationStatusStyle].
class StoreStatusStyle {
  /// Full label — used where there's room (meta card info row, verification CTA card).
  final String label;
  /// Compact label — used in tight inline pills (store list card badge).
  final String shortLabel;
  /// The design system's status tone (G6.3: was a legacy colour); draw it with `StatusBadge(label, tone: tone)`.
  final StatusTone tone;
  const StoreStatusStyle(this.label, this.shortLabel, this.tone);
}

StoreStatusStyle storeStatusStyle(String status) {
  switch (status) {
    case 'active':
      return const StoreStatusStyle(
        'Active & Verified',
        'Active',
        StatusTone.success,
      );
    case 'pending':
      return const StoreStatusStyle(
        'Pending Verification',
        'Pending',
        StatusTone.warning,
      );
    case 'rejected':
      return const StoreStatusStyle(
        'Verification Rejected',
        'Rejected',
        StatusTone.danger,
      );
    case 'suspended':
      return const StoreStatusStyle('Suspended', 'Suspended', StatusTone.danger);
    default:
      return const StoreStatusStyle('Inactive', 'Inactive', StatusTone.neutral);
  }
}

/// Label + tone for a [StoreModel.verificationStatus] value
/// (`not_started|pending|under_review|verified|rejected`) — the KYC review's
/// own state, independent of the marketplace [storeStatusStyle] above. Used
/// wherever a screen needs to show *where the review itself stands* while
/// `status` is still `pending` (or, after a resubmission, still `rejected`
/// until the next admin decision — see `store_verification` module).
class VerificationStatusStyle {
  final String label;
  final String shortLabel;
  /// The design system's status tone (G6.3: was a legacy colour); draw it with `StatusBadge(label, tone: tone)`.
  final StatusTone tone;
  const VerificationStatusStyle(this.label, this.shortLabel, this.tone);
}

VerificationStatusStyle verificationStatusStyle(String verificationStatus) {
  switch (verificationStatus) {
    case 'verified':
      return const VerificationStatusStyle(
        'Verified',
        'Verified',
        StatusTone.success,
      );
    case 'pending':
      return const VerificationStatusStyle(
        'Submitted — Awaiting Review',
        'Submitted',
        StatusTone.warning,
      );
    case 'under_review':
      return const VerificationStatusStyle(
        'Under Review',
        'In Review',
        StatusTone.warning,
      );
    case 'rejected':
      return const VerificationStatusStyle(
        'Verification Rejected',
        'Rejected',
        StatusTone.danger,
      );
    case 'not_started':
    default:
      return const VerificationStatusStyle(
        'Verification Not Started',
        'Not Started',
        StatusTone.warning,
      );
  }
}
