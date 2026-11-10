import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_admin_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';

/// G4.2 roles & permissions editor. The owner edits a working copy (who may do each action, and each approval rule: on / off and who approves);
/// Save first asks the server for the PREVIEW diff, then saves with the matrix version it read (a stale screen gets VERSION_CONFLICT). Managers read
/// only; the server refuses a cashier. The owner can never be removed and pinned actions never change (the screen locks them; the server enforces it).
class RolesController extends GetxController {
  RolesController({PosRepository? repository, String? storeId}) : _repo = repository ?? PosRepository(), _storeIdOverride = storeId;
  final PosRepository _repo;
  final String? _storeIdOverride;

  final Rxn<PermissionMatrix> matrix = Rxn<PermissionMatrix>();
  final RxBool loading = true.obs;
  final RxBool busy = false.obs;
  final RxnString error = RxnString();
  final RxnString saveError = RxnString();
  final RxnString notice = RxnString();

  /// the server said someone else changed the permissions meanwhile: only a reload helps
  final RxBool conflict = false.obs;

  /// the owner's unsaved edits, by action
  final RxMap<String, PermAction> edits = <String, PermAction>{}.obs;
  Worker? _online;

  bool get canEdit => (matrix.value?.canEdit ?? false) && reportsOnlineRx().value;
  bool get dirty => edits.isNotEmpty;

  PermAction? _original(String action) => matrix.value?.actions.firstWhereOrNull((a) => a.action == action);
  PermAction current(PermAction a) => edits[a.action] ?? a;

  /// the actions of each area, in the screen's order (areas with no action are left out)
  Map<String, List<PermAction>> get byArea {
    final out = <String, List<PermAction>>{};
    for (final area in permAreas) {
      final list = (matrix.value?.actions ?? const <PermAction>[]).where((a) => a.area == area).toList();
      if (list.isNotEmpty) out[area] = list;
    }
    return out;
  }

  String labelOf(String action) => _original(action)?.label ?? action;

  @override
  void onInit() {
    super.onInit();
    load();
    _online = ever<bool>(reportsOnlineRx(), (on) {
      if (on && matrix.value == null) load();
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
    final m = await _repo.getPermissionMatrix(await reportsStoreId(_storeIdOverride));
    if (m == null) {
      error.value = permErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the permissions. Try again.');
    } else {
      matrix.value = m;
      edits.clear();
      conflict.value = false;
      saveError.value = null;
    }
    loading.value = false;
  }

  bool _same(PermAction a, PermAction b) =>
      ([...a.roles]..sort()).join() == ([...b.roles]..sort()).join() &&
      a.approval.length == b.approval.length &&
      [for (var i = 0; i < a.approval.length; i++) a.approval[i].enabled == b.approval[i].enabled && a.approval[i].approver == b.approval[i].approver].every((x) => x);

  void _put(PermAction next) {
    final o = _original(next.action);
    if (o != null && _same(o, next)) {
      edits.remove(next.action);
    } else {
      edits[next.action] = next;
    }
    notice.value = null;
  }

  /// Cashier / manager on or off. The owner always may; a pinned action never changes.
  void toggleRole(PermAction a, String role) {
    if (!canEdit || a.pinned || role == PermRole.owner) return;
    final cur = current(a);
    final roles = cur.roles.contains(role) ? (cur.roles.where((r) => r != role).toList()) : [...cur.roles, role];
    _put(
      PermAction(
        action: a.action,
        label: a.label,
        pinned: a.pinned,
        changed: a.changed,
        defaultRoles: a.defaultRoles,
        roles: [
          for (final r in PermRole.all)
            if (roles.contains(r) || r == PermRole.owner) r,
        ],
        approval: cur.approval,
      ),
    );
  }

  void setApproval(PermAction a, int i, {bool? enabled, String? approver}) {
    if (!canEdit || a.pinned) return;
    final cur = current(a);
    if (i < 0 || i >= cur.approval.length) return;
    final list = [...cur.approval];
    list[i] = list[i].copyWith(enabled: enabled, approver: approver);
    _put(PermAction(action: a.action, label: a.label, pinned: a.pinned, changed: a.changed, defaultRoles: a.defaultRoles, roles: cur.roles, approval: list));
  }

  void discard() {
    edits.clear();
    saveError.value = null;
  }

  /// What goes to the server: every edited action with its full roles and approval list.
  Map<String, dynamic> get changes => {
    for (final e in edits.values)
      e.action: {
        'roles': e.roles,
        if (e.approval.isNotEmpty)
          'approval': [
            for (final a in e.approval) {'enabled': a.enabled, 'approver': a.approver},
          ],
      },
  };

  /// The server's preview of the pending changes (null on a refusal, with [saveError] set).
  Future<List<PermDiff>?> previewSave() async {
    if (!dirty || busy.value) return null;
    return _call(() async => _repo.updatePermissions(await reportsStoreId(_storeIdOverride), changes, preview: true), preview: true);
  }

  Future<bool> save() async {
    if (!dirty || busy.value) return false;
    final r = await _call(() async => _repo.updatePermissions(await reportsStoreId(_storeIdOverride), changes, expectedVersion: matrix.value?.version ?? 0));
    if (r != null) notice.value = 'Saved. The new permissions apply on every till at once.';
    return r != null;
  }

  Future<List<PermDiff>?> previewReset() async {
    if (busy.value) return null;
    return _call(() async => _repo.resetPermissions(await reportsStoreId(_storeIdOverride), preview: true), preview: true);
  }

  Future<bool> reset() async {
    if (busy.value) return false;
    final r = await _call(() async => _repo.resetPermissions(await reportsStoreId(_storeIdOverride)));
    if (r != null) notice.value = 'Back to the default permissions.';
    return r != null;
  }

  Future<List<PermDiff>?> _call(Future<({bool success, String? code, String? message, PermissionMatrix? matrix, List<PermDiff> diff})> Function() run, {bool preview = false}) async {
    saveError.value = null;
    notice.value = null;
    if (!reportsOnline()) {
      saveError.value = 'Changing permissions needs an internet connection.';
      return null;
    }
    busy.value = true;
    try {
      final r = await run();
      if (!r.success) {
        conflict.value = r.code == 'VERSION_CONFLICT';
        saveError.value = permErrorMessage(r.code, fallback: r.message);
        return null;
      }
      if (!preview) {
        if (r.matrix != null) {
          matrix.value = r.matrix;
          edits.clear();
        } else {
          await load();
        }
      }
      return r.diff;
    } finally {
      busy.value = false;
    }
  }
}
