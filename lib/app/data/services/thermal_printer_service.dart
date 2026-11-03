import 'dart:async';
import 'dart:io';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:solvexo_pos/app/data/services/network_printer_transport.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';
import 'package:solvexo_pos/utils/receipt_escpos_builder.dart';

/// A candidate printer, surfaced to the picker UI before connecting.
class PosPrinterOption {
  final String name;
  final String address;

  /// `bluetooth` (address = MAC / BLE id) or `network` (address = `ip:port`).
  final String kind;
  PosPrinterOption({required this.name, required this.address, this.kind = ThermalPrinterService.kindBluetooth});
}

/// The bytes-level transport, behind an interface so printing can be tested without hardware.
abstract class PrinterTransport {
  Future<bool> get bluetoothEnabled;
  Future<bool> get permissionGranted;
  Future<bool> connect(String address);
  Future<bool> write(List<int> bytes);
  Future<void> disconnect();
  Future<List<PosPrinterOption>> discover();
}

class BluetoothPrinterTransport implements PrinterTransport {
  @override
  Future<bool> get bluetoothEnabled => PrintBluetoothThermal.bluetoothEnabled;
  @override
  Future<bool> get permissionGranted => PrintBluetoothThermal.isPermissionBluetoothGranted;
  @override
  Future<bool> connect(String address) => PrintBluetoothThermal.connect(macPrinterAddress: address);
  @override
  Future<bool> write(List<int> bytes) => PrintBluetoothThermal.writeBytes(bytes);
  @override
  Future<void> disconnect() async {
    await PrintBluetoothThermal.disconnect;
  }

  @override
  Future<List<PosPrinterOption>> discover() async {
    final devices = await PrintBluetoothThermal.pairedBluetooths;
    return devices.map((d) => PosPrinterOption(name: d.name, address: d.macAdress)).toList();
  }
}

/// Receipt printing. What is supported where:
///  * **Android** — Bluetooth *Classic* (SPP) ESC/POS printers paired in the system Bluetooth settings, and **network
///    (Wi-Fi/Ethernet) ESC/POS printers on TCP port 9100**.
///  * **iOS** — Bluetooth **Low Energy** printers only (CoreBluetooth; no Classic/SPP without Apple's MFi programme, no "paired"
///    list — the picker shows nearby BLE devices), **network printers on port 9100** (needs the Local Network permission), and the
///    PDF/Share/AirPrint route, which works everywhere. The typical cheap 58 mm Classic printer will NOT work on iOS.
///  * Network printing is identical on both platforms (raw sockets), so a Wi-Fi/Ethernet printer is the one choice that works on
///    every device.
///
/// Printing is best effort and NEVER part of the sale: a failure is reported, the sale is already saved, and the receipt can be
/// reprinted or shared (PDF/text) from the sale's detail screen.
///
/// Settings (paper width, auto-print, copies, cash-drawer kick) are per DEVICE and kept in preferences.
class ThermalPrinterService extends GetxController {
  ThermalPrinterService({PrinterTransport? transport, PrinterTransport? networkTransport, Duration reconnectDelay = const Duration(milliseconds: 700)})
      : _bluetooth = transport ?? BluetoothPrinterTransport(),
        _network = networkTransport ?? NetworkPrinterTransport(),
        _reconnectDelay = reconnectDelay;

  static const kindBluetooth = 'bluetooth';
  static const kindNetwork = 'network';

  final PrinterTransport _bluetooth;
  final PrinterTransport _network;
  final Duration _reconnectDelay;

  final RxString savedPrinterName = ''.obs;
  final RxString savedPrinterAddress = ''.obs;

  /// Which transport the remembered printer uses.
  final RxString savedPrinterKind = kindBluetooth.obs;
  bool get isNetworkPrinter => savedPrinterKind.value == kindNetwork;
  PrinterTransport get _transport => isNetworkPrinter ? _network : _bluetooth;

  /// 58 or 80 (mm).
  final RxInt paperMm = 80.obs;
  final RxBool autoPrint = false.obs;
  final RxInt copies = 1.obs;
  final RxBool kickDrawer = false.obs;

  static const _kPaper = 'pos_printer_paper_mm';
  static const _kAuto = 'pos_printer_auto_print';
  static const _kCopies = 'pos_printer_copies';
  static const _kDrawer = 'pos_printer_drawer_kick';
  static const _kKind = 'pos_printer_kind';

  /// Where the last failure message of a background print goes (the UI shows it as a non-blocking notice).
  void Function(String message)? onBackgroundFailure;

  Future<void> init() async {
    savedPrinterName.value = await AppPreferences.getPosPrinterName() ?? '';
    savedPrinterAddress.value = await AppPreferences.getPosPrinterAddress() ?? '';
    savedPrinterKind.value = (await AppPreferences.getString(_kKind)) == kindNetwork ? kindNetwork : kindBluetooth;
    paperMm.value = int.tryParse(await AppPreferences.getString(_kPaper) ?? '') == 58 ? 58 : 80;
    autoPrint.value = (await AppPreferences.getString(_kAuto)) == '1';
    copies.value = (int.tryParse(await AppPreferences.getString(_kCopies) ?? '') ?? 1).clamp(1, 5);
    kickDrawer.value = (await AppPreferences.getString(_kDrawer)) == '1';
  }

  bool get hasSavedPrinter => savedPrinterAddress.value.isNotEmpty;
  PaperSize get paperSize => paperMm.value == 58 ? PaperSize.mm58 : PaperSize.mm80;

  Future<void> setPaperMm(int mm) async {
    paperMm.value = mm == 58 ? 58 : 80;
    await AppPreferences.setString(_kPaper, '${paperMm.value}');
  }

  Future<void> setAutoPrint(bool v) async {
    autoPrint.value = v;
    await AppPreferences.setString(_kAuto, v ? '1' : '0');
  }

  Future<void> setCopies(int n) async {
    copies.value = n.clamp(1, 5);
    await AppPreferences.setString(_kCopies, '${copies.value}');
  }

  Future<void> setKickDrawer(bool v) async {
    kickDrawer.value = v;
    await AppPreferences.setString(_kDrawer, v ? '1' : '0');
  }

  Future<bool> get isBluetoothEnabled => _bluetooth.bluetoothEnabled;

  Future<List<PosPrinterOption>> listPairedPrinters() async {
    if (!await _bluetooth.permissionGranted) return [];
    return _bluetooth.discover();
  }

  Future<void> selectPrinter(PosPrinterOption printer) async {
    await AppPreferences.setPosPrinter(address: printer.address, name: printer.name);
    await AppPreferences.setString(_kKind, printer.kind);
    savedPrinterName.value = printer.name;
    savedPrinterAddress.value = printer.address;
    savedPrinterKind.value = printer.kind;
  }

  /// Remembers a network printer by IP. Returns an error text for an invalid address, or null when saved.
  Future<String?> selectNetworkPrinter({required String name, required String host, String? port}) async {
    final parsed = NetworkPrinterAddress.parse(host, port);
    if (parsed.error != null) return parsed.error;
    final a = parsed.address!;
    await selectPrinter(PosPrinterOption(name: name.trim().isEmpty ? 'Network printer ${a.host}' : name.trim(), address: a.id, kind: kindNetwork));
    return null;
  }

  Future<void> forgetPrinter() async {
    await AppPreferences.clearPosPrinter();
    await AppPreferences.removeKey(_kKind);
    savedPrinterName.value = '';
    savedPrinterAddress.value = '';
    savedPrinterKind.value = kindBluetooth;
  }

  /// Runs [job] over a fresh connection to the remembered printer: checks Bluetooth/permission, connects (one automatic
  /// retry — printers drop idle links), and always disconnects. Returns a plain-language error, or null on success.
  Future<String?> _withPrinter(Future<List<int>> Function() bytes) async {
    final address = savedPrinterAddress.value;
    if (address.isEmpty) return 'No printer selected. Pick one in Settings → Receipt printer first.';
    final net = isNetworkPrinter;
    final t = _transport;
    try {
      if (!net) {
        if (!await t.bluetoothEnabled) return 'Bluetooth is turned off. Turn it on to print.';
        if (!await t.permissionGranted) return 'Bluetooth permission is needed to print. Allow it in the device settings.';
      }
      var connected = await t.connect(address);
      if (!connected) {
        await Future<void>.delayed(_reconnectDelay);
        connected = await t.connect(address);
      }
      if (!connected) {
        return net
            ? "Couldn't reach the printer at $address. Check that it is on, connected to the same Wi-Fi/network as this device, and that the IP address is right. On iPhone/iPad also allow Local Network access for this app in Settings."
            : "Couldn't reach the printer ($savedPrinterName). Check that it is on, has paper and is in range.";
      }
      try {
        final ok = await t.write(await bytes());
        return ok
            ? null
            : net
                ? 'The printer was reached but the print job was not accepted (it went offline or the connection dropped). Try again.'
                : 'The printer connected but did not accept the print job (out of paper, cover open, or it went to sleep).';
      } finally {
        await t.disconnect();
      }
    } catch (e) {
      debugPrint('printer error: ${e.runtimeType}');
      return 'Printing failed (the printer disconnected). The sale is saved — try again, or share the receipt as PDF.';
    }
  }

  /// Prints [receipt] [copies] times (and kicks the drawer first when [openDrawer]). Returns an error message or null.
  Future<String?> printReceipt({required ReceiptData receipt, bool openDrawer = false, PaperSize? paperSize}) =>
      _withPrinter(() => ReceiptEscPosBuilder.build(data: receipt, paperSize: paperSize ?? this.paperSize, copies: copies.value, openDrawer: openDrawer));

  Future<String?> printTest() => _withPrinter(() => ReceiptEscPosBuilder.buildTest(paperSize: paperSize, openDrawer: kickDrawer.value));

  /// Just the drawer pulse (cash sale with no receipt to print).
  Future<String?> openDrawer() async {
    return _withPrinter(() async {
      final g = Generator(paperSize, await CapabilityProfile.load());
      return g.drawer();
    });
  }

  /// Called after a sale is saved. Never throws, never blocks the caller: prints (when auto-print is on) and kicks the drawer
  /// on cash sales (when enabled), reporting any failure through [onBackgroundFailure] only.
  void afterSale({ReceiptData? receipt, required bool hadCash}) {
    final wantsDrawer = kickDrawer.value && hadCash;
    final r = receipt;
    final wantsPrint = autoPrint.value && r != null;
    if (!hasSavedPrinter || (!wantsDrawer && !wantsPrint)) return;
    unawaited(() async {
      final err = wantsPrint ? await printReceipt(receipt: r, openDrawer: wantsDrawer) : await openDrawer();
      if (err != null) onBackgroundFailure?.call('Receipt did not print: $err');
    }());
  }

  /// Human description of what this platform's printer support is (shown in the picker).
  static String get platformNote => Platform.isIOS
      ? 'iPhone/iPad can print to Bluetooth Low Energy (BLE) printers or to Wi-Fi/Ethernet (network) printers. Bluetooth Classic printers are not supported by iOS — use a BLE or network printer, or share the receipt as PDF.'
      : "Bluetooth: pair the printer in the device's Bluetooth settings first, then pick it here. Network: add a Wi-Fi/Ethernet printer by its IP address (port 9100).";
}
