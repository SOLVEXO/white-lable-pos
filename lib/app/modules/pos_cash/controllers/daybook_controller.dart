import 'dart:typed_data';

import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart' show dayKey, parseDayKey;
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart' show StoreDay;
import 'package:share_plus/share_plus.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/cash_common.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/daybook_escpos.dart';
import 'package:solvexo_pos/utils/daybook_pdf.dart';
import 'package:solvexo_pos/utils/tax_document_escpos.dart';

/// The daybook of one local day: every shift that opened that day with each line of the drawer in order and its running balance, the totals, and a clear
/// "does not reconcile" warning when the server says the lines and the shift's own figure disagree. A cashier only gets their own shifts (the server says so).
/// Online only. Prints on the saved thermal printer (58 / 80 mm) and shares an A4 PDF.
class DaybookController extends GetxController {
  DaybookController({
    PosRepository? repository,
    String? storeId,
    DateTime Function()? clock,
    ThermalPrinterService? printer,
    Future<void> Function(ShareParams)? share,
    Future<String?> Function()? storeName,
  }) : _repo = repository ?? PosRepository(),
       _storeIdOverride = storeId,
       _clock = clock ?? DateTime.now,
       _printerOverride = printer,
       _share = share ?? ((p) async => SharePlus.instance.share(p)),
       _storeName = storeName ?? AppPreferences.getStoreName;

  final PosRepository _repo;
  final String? _storeIdOverride;
  final DateTime Function() _clock;
  final ThermalPrinterService? _printerOverride;
  final Future<void> Function(ShareParams) _share;
  final Future<String?> Function() _storeName;
  ThermalPrinterService? get _printer => _printerOverride ?? (Get.isRegistered<ThermalPrinterService>() ? Get.find<ThermalPrinterService>() : null);

  final Rxn<Daybook> daybook = Rxn<Daybook>();
  final Rx<DateTime> day = DateTime.now().obs;
  final RxBool loading = true.obs;
  final RxnString error = RxnString();
  final RxBool busy = false.obs;
  final RxnString printNotice = RxnString();
  final RxBool printOk = false.obs;
  Worker? _online;
  int _ticket = 0;

  /// midnight of [day] and midnight of the next day, as local times
  (DateTime, DateTime) get range {
    final d = day.value;
    final from = DateTime(d.year, d.month, d.day);
    return (from, DateTime(d.year, d.month, d.day + 1));
  }

  /// the STORE's today (from the time-zone endpoint); the device date until it is known
  DateTime? _storeToday;

  bool get isToday {
    final n = _storeToday ?? _clock();
    return day.value.year == n.year && day.value.month == n.month && day.value.day == n.day;
  }

  @override
  void onInit() {
    super.onInit();
    day.value = _clock();
    _start();
    _online = ever<bool>(cashOnlineRx(), (on) {
      if (on && daybook.value == null) load();
    });
  }

  /// G4.1: the picker starts on the STORE's today (its time zone), not the device's date.
  Future<void> _start() async {
    try {
      final d = parseDayKey(await StoreDay.today(_repo, await cashStoreId(_storeIdOverride), _clock()));
      if (d != null) {
        _storeToday = d;
        day.value = d;
      }
    } catch (_) {
      /* the device date stays */
    }
    await load();
  }

  @override
  void onClose() {
    _online?.dispose();
    super.onClose();
  }

  void setDay(DateTime d) {
    day.value = DateTime(d.year, d.month, d.day);
    load();
  }

  void previousDay() => setDay(day.value.subtract(const Duration(days: 1)));
  void nextDay() {
    if (!isToday) setDay(DateTime(day.value.year, day.value.month, day.value.day + 1));
  }

  Future<void> load() async {
    final ticket = ++_ticket;
    error.value = null;
    if (!cashOnline()) {
      loading.value = false;
      return;
    }
    loading.value = true;
    // G4.0: the server takes the STORE day (its own time zone decides where the day starts and ends)
    final d = await _repo.getDaybookDay(await cashStoreId(_storeIdOverride), date: dayKey(day.value));
    if (ticket != _ticket) return; // a newer day was asked for meanwhile
    if (d == null) {
      daybook.value = null;
      error.value = cashErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the daybook. Try again.');
    } else {
      daybook.value = d;
    }
    loading.value = false;
  }

  Future<void> printIt() async {
    final d = daybook.value;
    if (d == null || busy.value) return;
    busy.value = true;
    printNotice.value = null;
    printOk.value = false;
    try {
      final pr = _printer;
      if (pr == null || !pr.hasSavedPrinter) {
        printNotice.value = 'No printer is set up. Go to Settings → Receipt printer, or share the PDF.';
        return;
      }
      final name = await _storeName();
      final err = await pr.printDocument((cols) => DaybookEscPos.lines(d, cols: cols, storeName: name, printedAt: _clock()));
      printOk.value = err == null;
      printNotice.value = err == null ? 'Printed.' : '$err You can also share it as a PDF.';
    } catch (_) {
      printNotice.value = 'Printing failed. You can share it as a PDF instead.';
    } finally {
      busy.value = false;
    }
  }

  /// The daybook text for [cols] columns (what a 58 mm / 80 mm printer would print): used by tests and previews.
  String previewText(int cols) {
    final d = daybook.value;
    return d == null ? '' : TaxDocumentEscPos.render(DaybookEscPos.lines(d, cols: cols, printedAt: _clock()), cols);
  }

  Future<void> sharePdf() async {
    final d = daybook.value;
    if (d == null || busy.value) return;
    busy.value = true;
    error.value = null;
    try {
      final Uint8List bytes = await DaybookPdf.build(d, storeName: await _storeName(), printedAt: _clock());
      final dd = day.value;
      final stamp = '${dd.year}-${dd.month.toString().padLeft(2, '0')}-${dd.day.toString().padLeft(2, '0')}';
      await _share(
        ShareParams(
          files: [XFile.fromData(bytes, name: 'daybook-$stamp.pdf', mimeType: 'application/pdf')],
          subject: 'Daybook $stamp',
        ),
      );
    } catch (_) {
      error.value = 'Could not share the daybook.';
    } finally {
      busy.value = false;
    }
  }
}
