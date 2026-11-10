import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_admin_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/idle_lock_service.dart';
import 'package:solvexo_pos/app/data/services/pending_cash_sync_service.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/app/data/services/pending_team_sync_service.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// What is still on THIS device, waiting to reach the server.
class LocalQueues {
  const LocalQueues({this.sales = 0, this.salesFailed = 0, this.cash = 0, this.cashFailed = 0, this.team = 0});
  final int sales, salesFailed, cash, cashFailed, team;
  int get total => sales + salesFailed + cash + cashFailed + team;

  static LocalQueues read() {
    final s = Get.isRegistered<PendingSaleSyncService>() ? Get.find<PendingSaleSyncService>() : null;
    final c = Get.isRegistered<PendingCashSyncService>() ? Get.find<PendingCashSyncService>() : null;
    final t = Get.isRegistered<PendingTeamSyncService>() ? Get.find<PendingTeamSyncService>() : null;
    return LocalQueues(
      sales: s?.pendingCount.value ?? 0,
      salesFailed: s?.failedCount.value ?? 0,
      cash: c?.pendingCount.value ?? 0,
      cashFailed: c?.failedCount.value ?? 0,
      team: t?.pendingCount.value ?? 0,
    );
  }
}

/// G4.4 settings hub: one controller for the hub and its screens (receipt designer, notifications, security, backup & sync). Managers read; the
/// owner edits (`canEdit` from the server, which refuses anyone else). Each screen saves only the keys it changed; the server validates every value.
class StoreSettingsController extends GetxController {
  StoreSettingsController({PosRepository? repository, String? storeId, LocalQueues Function()? queues, Future<void> Function(int minutes, bool onBackground)? applyLock, DateTime Function()? clock})
    : _repo = repository ?? PosRepository(),
      _storeIdOverride = storeId,
      _queues = queues ?? LocalQueues.read,
      _applyLock = applyLock ?? _applyLockOnDevice,
      _clock = clock ?? DateTime.now;

  final PosRepository _repo;
  final String? _storeIdOverride;
  final LocalQueues Function() _queues;
  final Future<void> Function(int, bool) _applyLock;
  final DateTime Function() _clock;

  final Rxn<StoreSettings> settings = Rxn<StoreSettings>();
  final RxBool loading = true.obs;
  final RxBool saving = false.obs;
  final RxnString error = RxnString();
  final RxnString saveError = RxnString();
  final RxnString notice = RxnString();

  /// the receipt designer's working copy (the live preview draws it)
  final Rx<ReceiptOptions> receiptDraft = const ReceiptOptions().obs;

  /// bumped when the draft is replaced from outside the text fields (load, discard) so they show the new text
  final RxInt receiptRevision = 0.obs;

  final Rxn<SyncStatus> sync = Rxn<SyncStatus>();
  final RxBool syncLoading = false.obs;
  final RxnString syncError = RxnString();
  final Rx<LocalQueues> local = const LocalQueues().obs;

  Worker? _online;

  bool get canEdit => (settings.value?.canEdit ?? false) && reportsOnlineRx().value;
  bool get receiptDirty => settings.value != null && _receiptPatch.isNotEmpty;
  DateTime now() => _clock();

  @override
  void onInit() {
    super.onInit();
    load();
    _online = ever<bool>(reportsOnlineRx(), (on) {
      if (on && settings.value == null) load();
    });
  }

  @override
  void onClose() {
    _online?.dispose();
    super.onClose();
  }

  Future<void> load() async {
    error.value = null;
    if (!reportsOnline()) {
      loading.value = false;
      return;
    }
    loading.value = true;
    final s = await _repo.getStoreSettings(await reportsStoreId(_storeIdOverride));
    if (s == null) {
      error.value = settingsErrorMessage(_repo.lastErrorCode, message: 'Could not load the store settings. Try again.');
    } else {
      _take(s);
      await _applySecurity();
    }
    loading.value = false;
  }

  void _take(StoreSettings s) {
    settings.value = s;
    if (receiptDraft.value.toJson().toString() != s.receipt.toJson().toString()) receiptRevision.value++;
    receiptDraft.value = s.receipt;
  }

  // ── receipt designer ──────────────────────────────────────────────────────
  void setReceiptFlag(String k, bool v) => receiptDraft.value = receiptDraft.value.withFlag(k, v);
  void setPaperWidth(int w) => receiptDraft.value = receiptDraft.value.copyWith(defaultPaperWidth: w);

  /// header / footer / promo: an empty field clears the line
  void setReceiptText(String key, String v) => receiptDraft.value = ReceiptOptions.fromJson({...receiptDraft.value.toJson(), key: v.trim().isEmpty ? null : v});
  void discardReceipt() {
    receiptDraft.value = settings.value?.receipt ?? const ReceiptOptions();
    receiptRevision.value++;
  }

  Map<String, dynamic> get _receiptPatch {
    final before = settings.value?.receipt.toJson() ?? const {};
    final after = receiptDraft.value.toJson();
    return {
      for (final e in after.entries)
        if (before[e.key] != e.value) e.key: e.value,
    };
  }

  Future<bool> saveReceipt() async {
    final p = _receiptPatch;
    if (p.isEmpty) return false;
    return _save({'receipt': p}, 'Receipt saved. New receipts use it.');
  }

  // ── notifications ─────────────────────────────────────────────────────────
  Future<bool> setAlert(String key, bool on) => _save({
    'alerts': {key: on},
  }, null);

  // ── security ──────────────────────────────────────────────────────────────
  Future<bool> setAutoLock(int minutes) async {
    final ok = await _save({
      'security': {'autoLockMinutes': minutes},
    }, 'Every till now locks after $minutes min without use.');
    if (ok) await _applySecurity();
    return ok;
  }

  Future<bool> setLockOnBackground(bool on) async {
    final ok = await _save({
      'security': {'lockOnBackground': on},
    }, null);
    if (ok) await _applySecurity();
    return ok;
  }

  /// This device follows the store's security settings at once (every other till picks them up when it next loads them).
  Future<void> _applySecurity() async {
    final s = settings.value?.security;
    if (s != null) await _applyLock(s.autoLockMinutes, s.lockOnBackground);
  }

  /// Read on load by the hub too, so a till that opens the hub follows the latest values even offline afterwards.
  Future<void> applySecurityOnDevice() => _applySecurity();

  static Future<void> _applyLockOnDevice(int minutes, bool onBackground) async {
    await AppPreferences.setPosAutoLockMinutes(minutes);
    await AppPreferences.setPosLockOnBackground(onBackground);
    if (Get.isRegistered<IdleLockService>()) {
      final l = Get.find<IdleLockService>();
      await l.setMinutes(minutes);
      l.lockOnBackground.value = onBackground;
    }
  }

  Future<bool> _save(Map<String, dynamic> patch, String? doneNotice) async {
    saveError.value = null;
    notice.value = null;
    if (!reportsOnline()) {
      saveError.value = 'Changing settings needs an internet connection.';
      return false;
    }
    if (saving.value) return false;
    saving.value = true;
    try {
      final r = await _repo.updateStoreSettings(await reportsStoreId(_storeIdOverride), patch);
      if (!r.success || r.settings == null) {
        saveError.value = settingsErrorMessage(r.code, message: r.message);
        return false;
      }
      _take(r.settings!);
      notice.value = doneNotice;
      return true;
    } finally {
      saving.value = false;
    }
  }

  // ── backup & sync ─────────────────────────────────────────────────────────
  Future<void> loadSync() async {
    local.value = _queues();
    syncError.value = null;
    if (!reportsOnline()) return;
    syncLoading.value = true;
    final s = await _repo.getSyncStatus(await reportsStoreId(_storeIdOverride));
    if (s == null) {
      syncError.value = settingsErrorMessage(_repo.lastErrorCode, message: 'Could not read the sync status. Try again.');
    } else {
      sync.value = s;
    }
    syncLoading.value = false;
  }
}
