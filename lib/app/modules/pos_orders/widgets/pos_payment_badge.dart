import 'package:flutter/material.dart';
import 'package:solvexo_pos/core/design/design.dart';

class PosPaymentBadge extends StatelessWidget {
  final String method;

  const PosPaymentBadge({super.key, required this.method});

  @override
  Widget build(BuildContext context) {
    final (label, tone) = _resolve(method);
    return StatusBadge(label, tone: tone);
  }

  static (String, StatusTone) _resolve(String method) {
    switch (method.toLowerCase()) {
      case 'card':
        return ('Card', StatusTone.neutral);
      case 'store_credit':
        return ('Store credit', StatusTone.accent);
      case 'cash':
        return ('Cash', StatusTone.success);
      default:
        return ('Other', StatusTone.accent);
    }
  }
}
