import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:get/get.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/receipt_escpos_builder.dart';

/// A paired candidate printer, surfaced to the picker UI before connecting.
class PosPrinterOption {
  final String name;
  final String address;
  PosPrinterOption({required this.name, required this.address});
}

/// Wraps `print_bluetooth_thermal` (Bluetooth transport) with
/// `ReceiptEscPosBuilder` (ESC/POS byte formatting) and remembers the
/// chosen printer in `AppPreferences` so the cashier pairs it once, not on
/// every receipt. Printing is a synchronous, best-effort local-hardware
/// action — unlike `createSale`, a failure here is just surfaced as an
/// error; there's nothing to queue and retry.
class ThermalPrinterService extends GetxController {
  final RxString savedPrinterName = ''.obs;
  final RxString savedPrinterAddress = ''.obs;

  Future<void> init() async {
    savedPrinterName.value = await AppPreferences.getPosPrinterName() ?? '';
    savedPrinterAddress.value = await AppPreferences.getPosPrinterAddress() ?? '';
  }

  bool get hasSavedPrinter => savedPrinterAddress.value.isNotEmpty;

  Future<bool> get isBluetoothEnabled => PrintBluetoothThermal.bluetoothEnabled;

  Future<List<PosPrinterOption>> listPairedPrinters() async {
    final granted = await PrintBluetoothThermal.isPermissionBluetoothGranted;
    if (!granted) return [];
    final devices = await PrintBluetoothThermal.pairedBluetooths;
    return devices.map((d) => PosPrinterOption(name: d.name, address: d.macAdress)).toList();
  }

  Future<void> selectPrinter(PosPrinterOption printer) async {
    await AppPreferences.setPosPrinter(address: printer.address, name: printer.name);
    savedPrinterName.value = printer.name;
    savedPrinterAddress.value = printer.address;
  }

  Future<void> forgetPrinter() async {
    await AppPreferences.clearPosPrinter();
    savedPrinterName.value = '';
    savedPrinterAddress.value = '';
  }

  /// Connects to the saved printer, sends the receipt, then disconnects.
  /// Returns a message on failure (no saved printer, connect failed, or
  /// the write itself failed) or null on success.
  Future<String?> printReceipt({
    required PosSaleModel sale,
    required String currencySymbol,
    PosSettingsModel? settings,
    PaperSize paperSize = PaperSize.mm80,
  }) async {
    final address = savedPrinterAddress.value;
    if (address.isEmpty) return 'No printer selected. Pick one in Settings first.';

    final connected = await PrintBluetoothThermal.connect(macPrinterAddress: address);
    if (!connected) return 'Could not connect to the printer. Make sure it\'s on and in range.';

    try {
      final bytes = await ReceiptEscPosBuilder.build(
        sale: sale,
        currencySymbol: currencySymbol,
        settings: settings,
        paperSize: paperSize,
      );
      final sent = await PrintBluetoothThermal.writeBytes(bytes);
      return sent ? null : 'Printer accepted the connection but rejected the print job.';
    } finally {
      await PrintBluetoothThermal.disconnect;
    }
  }
}
