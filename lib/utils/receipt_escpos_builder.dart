import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';

/// Builds the same receipt content as [ReceiptPdfBuilder], but as raw
/// ESC/POS command bytes for a thermal printer instead of a PDF. Kept as a
/// separate builder (not a shared formatter) since the two targets differ
/// enough — fixed-width columns and cut commands here vs. a page layout
/// there — that sharing code would mean threading print-target-specific
/// branches through one method.
class ReceiptEscPosBuilder {
  static Future<List<int>> build({
    required PosSaleModel sale,
    required String currencySymbol,
    PosSettingsModel? settings,
    PaperSize paperSize = PaperSize.mm80,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    final bytes = <int>[];
    String money(double v) => '$currencySymbol${v.toStringAsFixed(2)}';

    void row(String label, String value, {bool bold = false}) {
      bytes.addAll(generator.row([
        PosColumn(text: label, width: 7, styles: PosStyles(bold: bold)),
        PosColumn(
          text: value,
          width: 5,
          styles: PosStyles(bold: bold, align: PosAlign.right),
        ),
      ]));
    }

    bytes.addAll(generator.reset());

    if ((settings?.businessName ?? '').isNotEmpty) {
      bytes.addAll(generator.text(
        settings!.businessName!,
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2),
      ));
    }
    if ((settings?.receiptHeader ?? '').isNotEmpty) {
      bytes.addAll(generator.text(
        settings!.receiptHeader!,
        styles: const PosStyles(align: PosAlign.center),
      ));
    }
    bytes.addAll(generator.text(
      sale.saleNumber.isNotEmpty ? sale.saleNumber : sale.id,
      styles: const PosStyles(align: PosAlign.center, bold: true),
    ));
    bytes.addAll(generator.text(
      sale.createdAt.toLocal().toString(),
      styles: const PosStyles(align: PosAlign.center),
    ));
    bytes.addAll(generator.hr());

    for (final item in sale.items) {
      row('${item.name} x${item.qty}', money(item.lineTotal));
    }
    bytes.addAll(generator.hr());

    row('Subtotal', money(sale.subtotal));
    if (sale.discount > 0) row('Discount', '-${money(sale.discount)}');
    if (sale.tax > 0) row('Tax', '+${money(sale.tax)}');
    bytes.addAll(generator.emptyLines(1));
    row('Total', money(sale.total), bold: true);
    bytes.addAll(generator.emptyLines(1));
    row('Payment', sale.paymentMethod.toUpperCase());
    row('Customer', sale.customerName.isEmpty ? 'Walk-in' : sale.customerName);
    if (sale.refundedAmount > 0) row('Refunded', money(sale.refundedAmount));

    if ((settings?.receiptFooter ?? '').isNotEmpty) {
      bytes.addAll(generator.hr());
      bytes.addAll(generator.text(
        settings!.receiptFooter!,
        styles: const PosStyles(align: PosAlign.center),
      ));
    }

    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());
    return bytes;
  }
}
