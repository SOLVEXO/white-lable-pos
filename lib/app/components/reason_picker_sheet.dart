import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// What the reason is for. The codes are the server's (`pos-reasons.ts`); the labels are the till's.
enum PosReasonKind { refund, voidSale, discard }

class PosReasonChoice {
  final String code;
  final String note;
  const PosReasonChoice(this.code, this.note);
}

const Map<PosReasonKind, List<(String, String)>> kPosReasons = {
  PosReasonKind.refund: [
    ('wrong_item', 'Wrong item'),
    ('damaged_or_defective', 'Damaged or defective'),
    ('customer_changed_mind', 'Customer changed their mind'),
    ('price_error', 'Price error'),
    ('duplicate_charge', 'Charged twice'),
    ('other', 'Other'),
  ],
  PosReasonKind.voidSale: [
    ('cashier_error', 'Cashier error'),
    ('customer_cancelled', 'Customer cancelled'),
    ('wrong_total', 'Wrong total'),
    ('payment_problem', 'Payment problem'),
    ('other', 'Other'),
  ],
  PosReasonKind.discard: [
    ('customer_left', 'Customer left'),
    ('wrong_items', 'Wrong items'),
    ('duplicate', 'Duplicate'),
    ('no_longer_needed', 'No longer needed'),
    ('other', 'Other'),
  ],
};

/// "Why?" — a reason picker with an optional note (required words for "Other"). Returns null when cancelled.
abstract final class ReasonPicker {
  static Future<PosReasonChoice?> ask(PosReasonKind kind) => AppBottomSheet.showGet<PosReasonChoice>(_ReasonSheet(kind: kind), title: switch (kind) {
        PosReasonKind.refund => 'Reason for the refund',
        PosReasonKind.voidSale => 'Reason for voiding',
        PosReasonKind.discard => 'Reason for discarding',
      });
}

class _ReasonSheet extends StatefulWidget {
  const _ReasonSheet({required this.kind});
  final PosReasonKind kind;

  @override
  State<_ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<_ReasonSheet> {
  final _note = TextEditingController();
  String? _code;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_code == null) return setState(() => _error = 'Choose a reason.');
    if (_code == 'other' && _note.text.trim().isEmpty) return setState(() => _error = 'Say what happened (a few words).');
    Get.back(result: PosReasonChoice(_code!, _note.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: Space.s2,
          runSpacing: Space.s2,
          children: [
            for (final (code, label) in kPosReasons[widget.kind]!)
              ChoiceChip(
                key: Key('reason_$code'),
                label: Text(label),
                selected: _code == code,
                onSelected: (_) => setState(() {
                  _code = code;
                  _error = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: Space.s3),
        AppTextField(key: const Key('reasonNote'), label: _code == 'other' ? 'What happened?' : 'Note (optional)', controller: _note, maxLines: 2),
        if (_error != null) ...[
          const SizedBox(height: Space.s2),
          Text(_error!, key: const Key('reasonError'), style: context.type.caption.copyWith(color: p.danger)),
        ],
        const SizedBox(height: Space.s4),
        Row(
          children: [
            Expanded(child: AppButton(key: const Key('reasonCancel'), label: 'Cancel', variant: AppButtonVariant.secondary, onPressed: () => Get.back())),
            const SizedBox(width: Space.s3),
            Expanded(child: AppButton(key: const Key('reasonConfirm'), label: 'Continue', onPressed: _confirm)),
          ],
        ),
      ],
    );
  }
}
