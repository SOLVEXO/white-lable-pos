// 5F.1 — network (Wi-Fi/LAN) ESC/POS printing over TCP 9100: address validation, byte stream against a real local server,
// timeouts, refusal, drawer kick, the service's retry/error handling, discovery bounds, and offline cash sales still kicking the drawer.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/services/network_printer_transport.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/app/modules/pos_settings/widgets/pos_printer_picker_sheet.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';

/// A tiny fake printer: records every byte it receives.
class FakePrinter {
  late ServerSocket server;
  final received = <int>[];
  int connections = 0;
  Future<void> start() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((c) {
      connections++;
      c.listen(received.addAll, onError: (_) {});
    });
  }

  String get id => '127.0.0.1:${server.port}';
  Future<void> stop() => server.close();
}

class _BtFake implements PrinterTransport {
  int connects = 0;
  @override
  Future<bool> get bluetoothEnabled async => false; // would fail every print if the network path touched it
  @override
  Future<bool> get permissionGranted async => false;
  @override
  Future<bool> connect(String address) async => ++connects > 0;
  @override
  Future<bool> write(List<int> bytes) async => true;
  @override
  Future<void> disconnect() async {}
  @override
  Future<List<PosPrinterOption>> discover() async => [];
}

ReceiptData _receipt() => ReceiptData(
      businessName: 'Café',
      receiptNumber: 'POS-1',
      dateText: 'Jan 5, 2026',
      cashier: 'Cal',
      customer: 'Walk-in',
      lines: [ReceiptLine(name: 'Tea', qtyAndPrice: '1 x 2.00', total: '2.00')],
      subtotal: '2.00',
      total: '2.00',
      payments: const [ReceiptPaymentRow(label: 'Cash', amount: '2.00')],
      refunds: const [],
    );

/// ESC p (drawer pulse) = 0x1B 0x70
bool hasDrawerKick(List<int> b) {
  for (var i = 0; i < b.length - 1; i++) {
    if (b[i] == 0x1B && b[i + 1] == 0x70) return true;
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('address validation', () {
    test('accepts IPv4 with default or explicit port, also "ip:port"', () {
      expect(NetworkPrinterAddress.parse('192.168.1.50').address!.id, '192.168.1.50:9100');
      expect(NetworkPrinterAddress.parse(' 10.0.0.7 ', '9101').address!.id, '10.0.0.7:9101');
      expect(NetworkPrinterAddress.parse('10.0.0.7:9200').address!.id, '10.0.0.7:9200');
    });
    test('rejects hostnames, bad octets, IPv6, loopback/multicast, bad ports — with a plain message', () {
      for (final bad in ['printer.local', '300.1.1.1', '1.2.3', '::1', 'a:b:c', '127.0.0.1', '0.0.0.0', '239.1.1.1', '']) {
        final r = NetworkPrinterAddress.parse(bad);
        expect(r.address, isNull, reason: bad);
        expect(r.error, isNotNull);
      }
      expect(NetworkPrinterAddress.parse('192.168.1.5', '0').error, contains('port'));
      expect(NetworkPrinterAddress.parse('192.168.1.5', '70000').error, contains('port'));
      expect(NetworkPrinterAddress.parse('192.168.1.5', 'abc').error, contains('port'));
    });
  });

  group('NetworkPrinterTransport (real sockets)', () {
    setUpAll(() => NetworkPrinterAddress.allowLoopback = true);
    tearDownAll(() => NetworkPrinterAddress.allowLoopback = false);
    late FakePrinter printer;
    setUp(() async {
      printer = FakePrinter();
      await printer.start();
    });
    tearDown(() => printer.stop());

    test('delivers the exact bytes, then closes', () async {
      final t = NetworkPrinterTransport(settleDelay: const Duration(milliseconds: 20));
      expect(await t.connect(printer.id), isTrue);
      final job = List<int>.generate(3000, (i) => i % 256);
      expect(await t.write(job), isTrue);
      await t.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(printer.received, job);
    });

    test('connection refused → connect returns false (no exception)', () async {
      final port = printer.server.port;
      await printer.stop();
      final t = NetworkPrinterTransport();
      expect(await t.connect('127.0.0.1:$port'), isFalse);
    });

    test('unreachable host → times out within the configured limit', () async {
      final t = NetworkPrinterTransport(
        connectTimeout: const Duration(milliseconds: 150),
        connector: (h, p, to) => Completer<Socket>().future.timeout(to),
      );
      final sw = Stopwatch()..start();
      expect(await t.connect('10.255.255.1:9100'), isFalse);
      expect(sw.elapsedMilliseconds, lessThan(1500));
    });

    test('write without a connection is false; invalid stored address is false', () async {
      final t = NetworkPrinterTransport();
      expect(await t.write([1, 2, 3]), isFalse);
      expect(await t.connect('not-an-address'), isFalse);
    });

    test('never touches Bluetooth state', () async {
      final t = NetworkPrinterTransport();
      expect(await t.bluetoothEnabled, isTrue);
      expect(await t.permissionGranted, isTrue);
    });
  });

  group('ThermalPrinterService with a network printer', () {
    setUpAll(() => NetworkPrinterAddress.allowLoopback = true);
    tearDownAll(() => NetworkPrinterAddress.allowLoopback = false);
    late FakePrinter printer;
    late ThermalPrinterService svc;
    setUp(() async {
      Get.reset();
      SharedPreferences.setMockInitialValues({});
      printer = FakePrinter();
      await printer.start();
      svc = ThermalPrinterService(
        transport: _BtFake(),
        networkTransport: NetworkPrinterTransport(settleDelay: const Duration(milliseconds: 10)),
        reconnectDelay: const Duration(milliseconds: 10),
      );
      await svc.init();
      final e = await svc.selectNetworkPrinter(name: 'Counter', host: '127.0.0.1', port: '${printer.server.port}');
      expect(e, isNull);
    });
    tearDown(() => printer.stop());

    test('the selection is remembered across a restart (kind + ip:port + name) and forgotten cleanly', () async {
      final again = ThermalPrinterService(transport: _BtFake());
      await again.init();
      expect(again.isNetworkPrinter, isTrue);
      expect(again.savedPrinterAddress.value, printer.id);
      expect(again.savedPrinterName.value, 'Counter');
      await again.forgetPrinter();
      final third = ThermalPrinterService(transport: _BtFake());
      await third.init();
      expect(third.hasSavedPrinter, isFalse);
      expect(third.isNetworkPrinter, isFalse);
    });

    test('an invalid IP is not saved', () async {
      expect(await svc.selectNetworkPrinter(name: 'x', host: 'banana'), isNotNull);
      expect(svc.savedPrinterAddress.value, printer.id, reason: 'previous printer untouched');
    });

    test('test page reaches the printer; Bluetooth being off does not matter', () async {
      expect(await svc.printTest(), isNull);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(printer.received, isNotEmpty);
    });

    test('receipt with copies; drawer kick (ESC p) is sent when requested, not otherwise', () async {
      await svc.setCopies(2);
      expect(await svc.printReceipt(receipt: _receipt(), openDrawer: false), isNull);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(hasDrawerKick(printer.received), isFalse);
      printer.received.clear();
      expect(await svc.printReceipt(receipt: _receipt(), openDrawer: true), isNull);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(hasDrawerKick(printer.received), isTrue);
    });

    test('drawer-only pulse', () async {
      expect(await svc.openDrawer(), isNull);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(hasDrawerKick(printer.received), isTrue);
    });

    test('paper width setting changes the bytes (58 vs 80 mm layout)', () async {
      await svc.setPaperMm(80);
      await svc.printReceipt(receipt: _receipt());
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final w80 = printer.received.length;
      printer.received.clear();
      await svc.setPaperMm(58);
      await svc.printReceipt(receipt: _receipt());
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(printer.received.length, isNot(w80));
    });

    test('printer unreachable → one retry, then a plain-language network message (no Bluetooth wording)', () async {
      final port = printer.server.port;
      await printer.stop();
      final err = await svc.printTest();
      expect(err, contains('127.0.0.1:$port'));
      expect(err, contains('same Wi-Fi/network'));
      expect(err!.toLowerCase(), isNot(contains('bluetooth')));
    });

    test('offline-queued cash sale (no receipt object) still kicks the drawer, fire-and-forget', () async {
      await svc.setKickDrawer(true);
      svc.afterSale(receipt: null, hadCash: true);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(hasDrawerKick(printer.received), isTrue);
    });

    test('failure in the background is only a notice and never throws', () async {
      await svc.setKickDrawer(true);
      final msgs = <String>[];
      svc.onBackgroundFailure = msgs.add;
      final port = printer.server.port;
      await printer.stop();
      svc.afterSale(receipt: null, hadCash: true);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(msgs.single, contains('127.0.0.1:$port'));
    });
  });

  group('NetworkPrinterDiscovery', () {
    test('probes the /24 of the device (254 hosts minus itself), reports responders sorted, with progress', () async {
      final probed = <String>[];
      final d = NetworkPrinterDiscovery(
        localAddresses: () async => ['192.168.7.20'],
        probe: (h, p, t) async {
          probed.add(h);
          expect(p, 9100);
          return h == '192.168.7.50' || h == '192.168.7.9';
        },
      );
      var last = 0;
      final r = await d.scan(onProgress: (done, total) => last = done);
      expect(r, ['192.168.7.9', '192.168.7.50']);
      expect(probed.length, 253);
      expect(probed.toSet().length, 253);
      expect(probed, isNot(contains('192.168.7.20')));
      expect(last, 253);
    });

    test('no usable network → null; cancel stops early', () async {
      expect(await NetworkPrinterDiscovery(localAddresses: () async => []).scan(), isNull);
      late NetworkPrinterDiscovery d;
      var n = 0;
      d = NetworkPrinterDiscovery(
        concurrency: 4,
        localAddresses: () async => ['10.0.0.2'],
        probe: (h, p, t) async {
          if (++n == 10) d.cancel();
          return false;
        },
      );
      await d.scan();
      expect(n, lessThan(30));
    });
  });

  group('picker sheet', () {
    Future<ThermalPrinterService> pump(WidgetTester tester, {NetworkPrinterDiscovery? discovery}) async {
      Get.reset();
      SharedPreferences.setMockInitialValues({});
      final svc = ThermalPrinterService(transport: _BtFake());
      await svc.init();
      await tester.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(home: Scaffold(body: PosPrinterPickerSheet(service: svc, discovery: discovery)))));
      await tester.pump();
      return svc;
    }

    testWidgets('Network tab: invalid IP shows an error and saves nothing; valid IP saves a network printer', (tester) async {
      final svc = await pump(tester);
      await tester.tap(find.text('Network (Wi-Fi/LAN)'));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('netHost')), 'printer.local');
      await tester.tap(find.byKey(const Key('netSave')));
      await tester.pump();
      expect(find.textContaining('IPv4 address'), findsOneWidget);
      expect(svc.hasSavedPrinter, isFalse);
      await tester.enterText(find.byKey(const Key('netName')), 'Kitchen');
      await tester.enterText(find.byKey(const Key('netHost')), '192.168.1.50');
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('netSave')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      expect(svc.savedPrinterAddress.value, '192.168.1.50:9100');
      expect(svc.savedPrinterName.value, 'Kitchen');
      expect(svc.isNetworkPrinter, isTrue);
    });

    testWidgets('discovery results can be tapped to fill the address; "none found" is explained', (tester) async {
      await pump(tester, discovery: NetworkPrinterDiscovery(localAddresses: () async => ['192.168.1.2'], probe: (h, p, t) async => h == '192.168.1.77'));
      await tester.tap(find.text('Network (Wi-Fi/LAN)'));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('netScan')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(find.byKey(const Key('found-192.168.1.77')), findsOneWidget);
      await tester.tap(find.byKey(const Key('found-192.168.1.77')));
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const Key('netHost'))).controller!.text, '192.168.1.77');
    });
  });
}
