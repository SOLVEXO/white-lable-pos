import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:flutter/material.dart';

/// Label + color for a [StoreModel.status] value — shared by every place
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
  final Color color;
  const StoreStatusStyle(this.label, this.shortLabel, this.color);
}

StoreStatusStyle storeStatusStyle(String status) {
  switch (status) {
    case 'active':
      return const StoreStatusStyle(
        'Active & Verified',
        'Active',
        AppColors.greenSuccess,
      );
    case 'pending':
      return const StoreStatusStyle(
        'Pending Verification',
        'Pending',
        AppColors.orange,
      );
    case 'rejected':
      return const StoreStatusStyle(
        'Verification Rejected',
        'Rejected',
        AppColors.red,
      );
    case 'suspended':
      return const StoreStatusStyle('Suspended', 'Suspended', AppColors.red);
    default:
      return const StoreStatusStyle('Inactive', 'Inactive', AppColors.grey);
  }
}

/// Label + color for a [StoreModel.verificationStatus] value
/// (`not_started|pending|under_review|verified|rejected`) — the KYC review's
/// own state, independent of the marketplace [storeStatusStyle] above. Used
/// wherever a screen needs to show *where the review itself stands* while
/// `status` is still `pending` (or, after a resubmission, still `rejected`
/// until the next admin decision — see `store_verification` module).
class VerificationStatusStyle {
  final String label;
  final String shortLabel;
  final Color color;
  const VerificationStatusStyle(this.label, this.shortLabel, this.color);
}

VerificationStatusStyle verificationStatusStyle(String verificationStatus) {
  switch (verificationStatus) {
    case 'verified':
      return const VerificationStatusStyle(
        'Verified',
        'Verified',
        AppColors.greenSuccess,
      );
    case 'pending':
      return const VerificationStatusStyle(
        'Submitted — Awaiting Review',
        'Submitted',
        AppColors.amberDark,
      );
    case 'under_review':
      return const VerificationStatusStyle(
        'Under Review',
        'In Review',
        AppColors.amberDark,
      );
    case 'rejected':
      return const VerificationStatusStyle(
        'Verification Rejected',
        'Rejected',
        AppColors.red,
      );
    case 'not_started':
    default:
      return const VerificationStatusStyle(
        'Verification Not Started',
        'Not Started',
        AppColors.orange,
      );
  }
}
