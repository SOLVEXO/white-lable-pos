import 'package:flutter/material.dart';
import 'package:solvexo_pos/core/design/design.dart';

class PosStatusBadge extends StatelessWidget {
  final String status;
  const PosStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, tone) = _resolve(status);
    return StatusBadge(label, tone: tone, dot: true);
  }

  static (String, StatusTone) _resolve(String status) {
    switch (status) {
      case 'held':
        return ('Held', StatusTone.warning);
      case 'refunded':
        return ('Refunded', StatusTone.danger);
      case 'partially_refunded':
        return ('Partial refund', StatusTone.danger);
      case 'voided':
        return ('Voided', StatusTone.neutral);
      case 'completed':
      default:
        return ('Completed', StatusTone.success);
    }
  }
}
