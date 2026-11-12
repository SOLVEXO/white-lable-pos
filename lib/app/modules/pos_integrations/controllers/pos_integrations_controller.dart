import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_connectors_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// G5.7 — Owner → Integrations: every connection in one place. Receipts by e-mail / SMS and fiscal (each OFF until switched on; the provider status
/// says whether it can work yet), payments (→ Payments setup), the accounting export (CSV, shared), and the store's read-only API keys.
class PosIntegrationsController extends GetxController {
  PosIntegrationsController({PosRepository? repo, String? storeId, Future<void> Function(ShareParams p)? share, DateTime Function()? clock})
      : _repo = repo ?? PosRepository(),
        _storeId = storeId,
        _share = share ?? ((p) async => SharePlus.instance.share(p)),
        _clock = clock ?? DateTime.now;
  final PosRepository _repo;
  String? _storeId;
  final Future<void> Function(ShareParams p) _share;
  final DateTime Function() _clock;

  final RxBool loading = true.obs;
  final Rxn<ConnectorsStatus> status = Rxn<ConnectorsStatus>();
  final Rxn<StoreApiKeys> keys = Rxn<StoreApiKeys>();
  final RxnString error = RxnString();
  final RxnString notice = RxnString();
  final RxnString saving = RxnString();
  final RxBool exporting = false.obs;

  /// export period (store days)
  late final Rx<DateTime> exportFrom = DateTime(_clock().year, _clock().month, 1).obs;
  late final Rx<DateTime> exportTo = DateTime(_clock().year, _clock().month, _clock().day).obs;

  @override
  void onReady() {
    super.onReady();
    load();
  }

  Future<String> _id() async => _storeId ??= await AppPreferences.getStoreId() ?? '';

  Future<void> load() async {
    loading.value = true;
    error.value = null;
    final id = await _id();
    final results = await Future.wait([_repo.getConnectors(id), _repo.getApiKeys(id)]);
    status.value = results[0] as ConnectorsStatus?;
    keys.value = results[1] as StoreApiKeys?;
    if (status.value == null) error.value = 'Could not load the integrations. Check the connection and try again.';
    loading.value = false;
  }

  Future<void> setFlag(String key, bool value) async {
    if (saving.value != null) return;
    saving.value = key;
    error.value = null;
    notice.value = null;
    final r = await _repo.setConnectors(await _id(), {key: value});
    saving.value = null;
    if (!r.success) {
      error.value = integrationsErrorMessage(r.code, r.message);
      return;
    }
    await load();
  }

  static String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> exportAccounting() async {
    if (exporting.value) return;
    if (exportTo.value.isBefore(exportFrom.value)) {
      error.value = 'The end date is before the start date.';
      return;
    }
    exporting.value = true;
    error.value = null;
    notice.value = null;
    try {
      final from = ymd(exportFrom.value), to = ymd(exportTo.value);
      final r = await _repo.accountingExport(await _id(), from: from, to: to);
      if (r.bytes == null) {
        error.value = integrationsErrorMessage(r.code, r.message);
        return;
      }
      await _share(ShareParams(files: [XFile.fromData(Uint8List.fromList(r.bytes!), name: 'accounting_${from}_$to.csv', mimeType: 'text/csv')], subject: 'Accounting export $from to $to'));
      notice.value = 'Export ready ($from to $to).';
    } finally {
      exporting.value = false;
    }
  }

  /// Creates a key; returns the full key to show ONCE (null on failure, with [error] set).
  Future<String?> createKey({required String name, required List<String> scopes, required int days}) async {
    if (saving.value != null) return null;
    saving.value = 'apiKey';
    error.value = null;
    final r = await _repo.createApiKey(await _id(), name: name.trim(), scopes: scopes, expiresInDays: days);
    saving.value = null;
    if (!r.success || r.key == null) {
      error.value = integrationsErrorMessage(r.code, r.message);
      return null;
    }
    await load();
    return r.key;
  }

  Future<void> revokeKey(StoreApiKey k) async {
    if (saving.value != null) return;
    saving.value = 'revoke:${k.id}';
    error.value = null;
    final r = await _repo.revokeApiKey(await _id(), k.id);
    saving.value = null;
    if (!r.success) {
      error.value = integrationsErrorMessage(r.code, r.message);
      return;
    }
    notice.value = '"${k.name}" revoked. It stops working at once.';
    await load();
  }

  static String integrationsErrorMessage(String? code, String? message) => switch (code) {
        'POS_ACTION_FORBIDDEN' || 'OWNER_REQUIRED' => 'Only the store owner can do this. Unlock as the owner and try again.',
        'TOO_MANY_KEYS' => 'This store already has the most active keys allowed. Revoke one first.',
        'SCOPES_INVALID' => 'Choose at least one thing the key may read.',
        'NAME_REQUIRED' => 'Give the key a name (up to 60 characters).',
        'EXPIRY_INVALID' => 'A key can last 1 to 365 days.',
        'RANGE_TOO_LONG' => 'An export covers at most 366 days.',
        'RANGE_INVALID' => 'The end date is before the start date.',
        _ => (message != null && message.isNotEmpty) ? message : 'Something went wrong. Try again.',
      };
}
