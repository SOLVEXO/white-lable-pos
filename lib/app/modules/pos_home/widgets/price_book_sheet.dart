import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// G4.5: pick the price book this sale is priced with (or the normal prices). The SERVER prices the sale with it; a book that is no longer in
/// force is refused at the quote / sale (PRICE_BOOK_NOT_ACTIVE, said in words). A customer's own book is applied by the server when none is picked.
class PriceBookSheet extends StatelessWidget {
  const PriceBookSheet({super.key, required this.c});
  final PosHomeController c;

  static Future<void> open(PosHomeController c) =>
      Get.bottomSheet(PriceBookSheet(c: c), isScrollControlled: true, backgroundColor: Colors.transparent);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final cur = c.priceBook.value?.id;
    Widget row(String? id, String title, String? subtitle) => ListTile(
      key: Key('priceBook_${id ?? 'none'}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(cur == id ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: cur == id ? p.accent : p.textMuted),
      title: Text(title, style: t.body.copyWith(color: p.textPrimary)),
      subtitle: subtitle == null ? null : Text(subtitle, style: t.caption.copyWith(color: p.textSecondary)),
      onTap: () {
        c.setPriceBook(id == null ? null : c.priceBooks.firstWhereOrNull((b) => b.id == id));
        Get.back();
      },
    );
    return AppSheetSurface(
      key: const Key('priceBookSheet'),
      title: 'Prices for this sale',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row(null, 'Normal prices', c.selectedCustomer.value != null ? 'The customer\'s own price book applies, if they have one' : null),
          for (final b in c.bookChoices) row(b.id, b.name, [if (b.note != null) b.note!, '${b.entries.length} item${b.entries.length == 1 ? '' : 's'}'].join(' · ')),
          if (c.bookChoices.isEmpty) Padding(padding: const EdgeInsets.only(top: Space.s2), child: Text('No price book is in force now.', style: t.caption.copyWith(color: p.textSecondary))),
        ],
      ),
    );
  }
}
