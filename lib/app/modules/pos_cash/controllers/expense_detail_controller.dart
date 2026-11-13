import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/cash_common.dart';
import 'package:solvexo_pos/app/modules/pos_pdf_viewer/pdf_viewer_view.dart';

/// One expense: its status and the manager's decision note, the receipt (a fresh 5-minute link is fetched every time it is opened, shown from memory
/// only, and dropped when it is closed: never stored, cached or logged), and the manager's Approve / Reject (a rejection needs a reason).
class ExpenseDetailController extends GetxController {
  ExpenseDetailController({required this.expenseId, PosRepository? repository, String? storeId, PdfOpener? openPdf, Future<Uint8List> Function(String url)? fetchBytes})
    : _repo = repository ?? PosRepository(),
      _storeIdOverride = storeId,
      _openPdf = openPdf ?? openPdfViewer,
      _fetchBytes = fetchBytes ?? _download;
  final PdfOpener _openPdf;
  final Future<Uint8List> Function(String url) _fetchBytes;

  /// The signed link is fetched with a plain client — never the app's API client, so no auth header goes to the storage host. Memory only.
  static Future<Uint8List> _download(String url) async {
    final r = await Dio().get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
    return Uint8List.fromList(r.data ?? const []);
  }
  final String expenseId;
  final PosRepository _repo;
  final String? _storeIdOverride;

  final Rxn<Expense> expense = Rxn<Expense>();
  final RxBool loading = true.obs;
  final RxnString error = RxnString();
  final RxBool busy = false.obs;
  final RxnString actionError = RxnString();
  final RxnString notice = RxnString();
  final RxBool canManageHint = false.obs;

  /// the receipt link while the receipt is open (null otherwise). Held only in memory.
  final Rxn<ReceiptLink> receipt = Rxn<ReceiptLink>();
  final RxBool receiptLoading = false.obs;
  final RxnString receiptError = RxnString();
  Worker? _online;

  bool get canDecide => canManageHint.value && (expense.value != null && !expense.value!.decided);

  @override
  void onInit() {
    super.onInit();
    cashGuessCanManage().then((v) => canManageHint.value = v);
    load();
    _online = ever<bool>(cashOnlineRx(), (on) {
      if (on && expense.value == null) load();
    });
  }

  @override
  void onClose() {
    receipt.value = null;
    _online?.dispose();
    super.onClose();
  }

  Future<void> load({bool silent = false}) async {
    error.value = null;
    if (!cashOnline()) {
      loading.value = false;
      return;
    }
    if (!silent) loading.value = true;
    final e = await _repo.getExpense(await cashStoreId(_storeIdOverride), expenseId);
    if (e == null) {
      if (expense.value == null) error.value = cashErrorMessage(_repo.lastErrorCode, fallback: 'Could not load this expense. Try again.');
    } else {
      expense.value = e;
    }
    loading.value = false;
  }

  /// Fetches a FRESH link (never reuses an earlier one) and keeps it in memory for the viewer.
  Future<void> openReceipt() async {
    if (receiptLoading.value) return;
    receiptError.value = null;
    if (!cashOnline()) {
      receiptError.value = 'Needs internet.';
      return;
    }
    receiptLoading.value = true;
    try {
      final l = await _repo.getExpenseReceiptLink(await cashStoreId(_storeIdOverride), expenseId);
      if (l == null || l.url.isEmpty) {
        receiptError.value = cashErrorMessage(_repo.lastErrorCode, fallback: 'Could not open the receipt. Try again.');
      } else {
        receipt.value = l;
      }
    } finally {
      receiptLoading.value = false;
    }
  }

  void closeReceipt() => receipt.value = null;

  /// G5.8: a PDF receipt opens in the in-app viewer (view, print, share): a FRESH link each time, downloaded into memory when the viewer opens.
  Future<void> viewReceiptPdf() async {
    if (receiptLoading.value) return;
    receiptError.value = null;
    if (!cashOnline()) {
      receiptError.value = 'Needs internet.';
      return;
    }
    receiptLoading.value = true;
    ReceiptLink? l;
    try {
      l = await _repo.getExpenseReceiptLink(await cashStoreId(_storeIdOverride), expenseId);
    } finally {
      receiptLoading.value = false;
    }
    if (l == null || l.url.isEmpty) {
      receiptError.value = cashErrorMessage(_repo.lastErrorCode, fallback: 'Could not open the receipt. Try again.');
      return;
    }
    final url = l.url;
    final no = expense.value?.number ?? '';
    await _openPdf(PdfDoc(title: 'Expense receipt', fileName: 'expense-receipt${no.isEmpty ? '' : '-$no'}.pdf', bytes: () => _fetchBytes(url)));
  }

  /// [approve] true = approve; false = reject (needs [note]).
  Future<bool> decide({required bool approve, String? note}) async {
    if (busy.value) return false;
    actionError.value = null;
    notice.value = null;
    if (!approve && (note ?? '').trim().isEmpty) {
      actionError.value = cashErrorMessage('NOTE_REQUIRED');
      return false;
    }
    if (!cashOnline()) {
      actionError.value = 'Needs internet.';
      return false;
    }
    busy.value = true;
    try {
      final r = await _repo.decideExpense(await cashStoreId(_storeIdOverride), expenseId, approve: approve, note: note);
      if (!r.success) {
        actionError.value = cashErrorMessage(r.code ?? _repo.lastErrorCode, fallback: r.message);
        return false;
      }
      notice.value = approve ? 'Expense approved.' : 'Expense rejected.';
      if (r.expense != null) {
        expense.value = r.expense;
      } else {
        await load(silent: true);
      }
      return true;
    } finally {
      busy.value = false;
    }
  }
}
