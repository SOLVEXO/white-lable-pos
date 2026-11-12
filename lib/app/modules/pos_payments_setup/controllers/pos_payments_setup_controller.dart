import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_connectors_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// G5.4 — Owner → Payments setup: Raast (business verification status, provider test mode, on / off for the store), card on an external bank
/// terminal (on / off), and the card gateway's status (no provider yet). Every switch is the server's (`connectors`, owner only, audited).
class PosPaymentsSetupController extends GetxController {
  PosPaymentsSetupController({PosRepository? repo, String? storeId}) : _repo = repo ?? PosRepository(), _storeId = storeId;
  final PosRepository _repo;
  String? _storeId;

  final RxBool loading = true.obs;
  final Rxn<ConnectorsStatus> status = Rxn<ConnectorsStatus>();
  final RxnString error = RxnString();
  final RxnString saving = RxnString(); // the switch being saved

  @override
  void onReady() {
    super.onReady();
    load();
  }

  Future<void> load() async {
    loading.value = true;
    error.value = null;
    _storeId ??= await AppPreferences.getStoreId();
    final id = _storeId ?? '';
    final s = id.isEmpty ? null : await _repo.getConnectors(id);
    status.value = s;
    if (s == null) error.value = 'Could not load payment settings. Check the connection and try again.';
    loading.value = false;
  }

  /// Raast on/off: the store switch is "raastDisabled" (on by default once verified), so "on" writes false.
  Future<void> setRaast(bool on) => _set('raastDisabled', !on);
  Future<void> setCardTerminal(bool on) => _set('cardExternalTerminal', on);

  Future<void> _set(String key, bool value) async {
    final id = _storeId ?? '';
    if (id.isEmpty || saving.value != null) return;
    saving.value = key;
    error.value = null;
    final r = await _repo.setConnectors(id, {key: value});
    saving.value = null;
    if (!r.success) {
      error.value = connectorErrorMessage(r.code, r.message);
      return;
    }
    await load();
  }

  static String connectorErrorMessage(String? code, String? message) => switch (code) {
        'OWNER_REQUIRED' || 'OWNER_SESSION_REQUIRED' => 'Only the store owner can change this. Unlock as the owner and try again.',
        _ => (message != null && message.isNotEmpty) ? message : 'Could not save. Try again.',
      };
}
