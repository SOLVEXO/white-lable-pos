// 5F — receipt printing: layout per paper width, settings, drawer, copies, connection handling, never blocking a sale.

import 'dart:convert';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';
import 'package:solvexo_pos/utils/receipt_escpos_builder.dart';

class FakeTransport implements PrinterTransport {
  bool enabled = true, granted = true, writeOk = true;
  int connectFailures = 0; // fail this many connects before succeeding
  int connects = 0, disconnects = 0;
  final writes = <List<int>>[];
  @override
  Future<bool> get bluetoothEnabled async => enabled;
  @override
  Future<bool> get permissionGranted async => granted;
  @override
  Future<bool> connect(String address) async {
    connects++;
    if (connectFailures > 0) {
      connectFailures--;
      return false;
    }
    return true;
  }

  @override
  Future<bool> write(List<int> bytes) async {
    writes.add(bytes);
    return writeOk;
  }

  @override
  Future<void> disconnect() async => disconnects++;
  @override
  Future<List<PosPrinterOption>> discover() async => [PosPrinterOption(name: 'BT-Printer', address: 'AA:BB')];
}

ReceiptData _receipt({String? banner, bool copy = false, String longName = 'Organic single-origin Ethiopian Yirgacheffe coffee beans 1kg resealable bag'}) => ReceiptData(
      businessName: 'Corner Café',
      address: '12 Long Street Name, Some Very Long District, Karachi, Pakistan',
      receiptNumber: 'POS-00042',
      dateText: 'Jan 5, 2026 10:00',
      cashier: 'Cal',
      customer: 'Walk-in',
      lines: [ReceiptLine(name: longName, qtyAndPrice: '2 x JPY 1,500', total: 'JPY 3,000')],
      subtotal: 'JPY 3,000',
      total: 'JPY 3,000',
      payments: const [ReceiptPaymentRow(label: 'Cash', amount: 'JPY 3,000')],
      refunds: const [],
      banner: banner,
      isCopy: copy,
    );

String _text(List<int> bytes) => latin1.decode(bytes.where((b) => b >= 32 || b == 10).toList(), allowInvalid: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('layout adapts to paper width', () {
    test('58 mm = 32 columns, 80 mm = 48', () {
      expect(ReceiptEscPosBuilder.columnsFor(58), 32);
      expect(ReceiptEscPosBuilder.columnsFor(80), 48);
    });

    test('long names wrap and no line exceeds the paper width; the amount stays flush right', () {
      for (final cols in [32, 48]) {
        final lines = ReceiptEscPosBuilder.twoColumn('Organic single-origin Ethiopian Yirgacheffe coffee beans 1kg resealable bag', 'JPY 3,000', cols);
        expect(lines.length, greaterThan(1));
        expect(lines.every((l) => l.length <= cols), isTrue, reason: 'cols=$cols $lines');
        expect(lines.last.endsWith('JPY 3,000'), isTrue);
        expect(lines.last.length, cols);
      }
    });

    test('a single word longer than the line is hard-broken, not cut off', () {
      final w = ReceiptEscPosBuilder.wrap('A' * 70, 32);
      expect(w.join(), 'A' * 70);
      expect(w.every((l) => l.length <= 32), isTrue);
    });

    test('non-Latin text never crashes the print (becomes ?)', () {
      expect(ReceiptEscPosBuilder.printable('قهوة ☕ 2×'), contains('?'));
      expect(ReceiptEscPosBuilder.printable('2×'), '2x');
    });

    test('a built receipt carries the whole name across lines (58 mm) and the banners / COPY', () async {
      final bytes = await ReceiptEscPosBuilder.build(data: _receipt(banner: 'VOID', copy: true), paperSize: PaperSize.mm58);
      final t = _text(bytes);
      expect(t, contains('VOID'));
      expect(t, contains('COPY'));
      expect(t, contains('JPY 3,000')); // exponent-0 currency: no decimals invented
      expect(t, isNot(contains('3,000.00')));
      expect(t, contains('Yirgacheffe'));
      expect(t, contains('resealable'));
    });

    test('copies repeat the receipt; the drawer pulse (ESC p) comes first when asked', () async {
      final one = await ReceiptEscPosBuilder.build(data: _receipt());
      final three = await ReceiptEscPosBuilder.build(data: _receipt(), copies: 3, openDrawer: true);
      expect('POS-00042'.allMatches(_text(three)).length, 3);
      expect(three.length, greaterThan(one.length * 2));
      expect(three.sublist(0, 2), [0x1B, 0x70]);
      expect((await ReceiptEscPosBuilder.build(data: _receipt())).sublist(0, 2), isNot([0x1B, 0x70]));
    });

    test('the test page states the paper width', () async {
      expect(_text(await ReceiptEscPosBuilder.buildTest(paperSize: PaperSize.mm58)), contains('58 mm (32 columns)'));
    });
  });

  group('printer service', () {
    late FakeTransport t;
    late ThermalPrinterService svc;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'pos_printer_address': 'AA:BB', 'pos_printer_name': 'BT-Printer'});
      t = FakeTransport();
      svc = ThermalPrinterService(transport: t, reconnectDelay: Duration.zero);
      await svc.init();
    });

    test('settings persist across a restart (paper, auto-print, copies, drawer)', () async {
      await svc.setPaperMm(58);
      await svc.setAutoPrint(true);
      await svc.setCopies(2);
      await svc.setKickDrawer(true);
      final again = ThermalPrinterService(transport: t);
      await again.init();
      expect([again.paperMm.value, again.autoPrint.value, again.copies.value, again.kickDrawer.value], [58, true, 2, true]);
      await again.setCopies(99);
      expect(again.copies.value, 5);
    });

    test('prints with the configured copies and always disconnects', () async {
      await svc.setCopies(2);
      expect(await svc.printReceipt(receipt: _receipt()), isNull);
      expect('POS-00042'.allMatches(_text(t.writes.single)).length, 2);
      expect(t.disconnects, 1);
    });

    test('clear messages: no printer / bluetooth off / no permission / unreachable / rejected', () async {
      final none = ThermalPrinterService(transport: t);
      expect(await none.printReceipt(receipt: _receipt()), contains('No printer selected'));
      t.enabled = false;
      expect(await svc.printReceipt(receipt: _receipt()), contains('Bluetooth is turned off'));
      t.enabled = true;
      t.granted = false;
      expect(await svc.printReceipt(receipt: _receipt()), contains('permission'));
      t.granted = true;
      t.connectFailures = 5;
      expect(await svc.printReceipt(receipt: _receipt()), contains("Couldn't reach the printer"));
      t.connectFailures = 0;
      t.writeOk = false;
      expect(await svc.printReceipt(receipt: _receipt()), contains('did not accept'));
    });

    test('reconnects once automatically when the first connect fails', () async {
      t.connectFailures = 1;
      expect(await svc.printReceipt(receipt: _receipt()), isNull);
      expect(t.connects, 2);
    });

    test('a transport that throws is reported, never thrown', () async {
      final bad = _ThrowingTransport();
      final s = ThermalPrinterService(transport: bad, reconnectDelay: Duration.zero);
      SharedPreferences.setMockInitialValues({'pos_printer_address': 'AA:BB'});
      await s.init();
      expect(await s.printReceipt(receipt: _receipt()), contains('Printing failed'));
    });

    test('afterSale: does nothing when auto-print and drawer are off', () async {
      svc.afterSale(receipt: _receipt(), hadCash: true);
      await Future<void>.delayed(Duration.zero);
      expect(t.writes, isEmpty);
    });

    test('afterSale: auto-print prints; cash sale kicks the drawer in the same job; a card sale does not', () async {
      await svc.setAutoPrint(true);
      await svc.setKickDrawer(true);
      svc.afterSale(receipt: _receipt(), hadCash: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(t.writes.single.sublist(0, 2), [0x1B, 0x70]);
      t.writes.clear();
      svc.afterSale(receipt: _receipt(), hadCash: false);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(t.writes.single.sublist(0, 2), isNot([0x1B, 0x70]));
    });

    test('afterSale with no receipt (offline-queued cash sale) still opens the drawer', () async {
      await svc.setKickDrawer(true);
      svc.afterSale(receipt: null, hadCash: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(t.writes.single.sublist(0, 2), [0x1B, 0x70]);
    });

    test('a failed background print only produces a notice — the caller is never blocked or thrown at', () async {
      await svc.setAutoPrint(true);
      t.enabled = false;
      String? notice;
      svc.onBackgroundFailure = (m) => notice = m;
      svc.afterSale(receipt: _receipt(), hadCash: false); // returns immediately
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notice, contains('Receipt did not print'));
      expect(t.writes, isEmpty);
    });

    test('test print and drawer test use the same connection handling', () async {
      expect(await svc.printTest(), isNull);
      expect(_text(t.writes.single), contains('Test print'));
      expect(await svc.openDrawer(), isNull);
    });
  });
}

class _ThrowingTransport extends FakeTransport {
  @override
  Future<bool> connect(String address) async => throw StateError('boom');
}
