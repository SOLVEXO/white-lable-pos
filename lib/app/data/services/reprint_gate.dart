import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/manager_approval_sheet.dart';

/// The outcome of asking to reprint: go ahead (with the server's number, or null when it could not be recorded offline), or stop with words.
typedef ReprintGo = ({bool ok, int? number, String? message});

/// G4.8: every reprint (receipt, tax invoice, credit note) goes through here first.
///   · online: the server records it and answers the number ("REPRINT #n"); when the store requires a PIN and the caller is a cashier it answers
///     POS_APPROVAL_REQUIRED → a manager enters their PIN → recorded with the manager's token;
///   · offline: a store that requires a PIN refuses (nothing can be recorded or approved), otherwise the till prints "COPY" as before.
class ReprintGate {
  ReprintGate({PosRepository? repository, Future<String?> Function(String reason)? askManager})
    : _repo = repository ?? PosRepository(),
      _askManager = askManager ?? ((r) => ManagerApproval.request(reason: r, repository: repository));

  final PosRepository _repo;
  final Future<String?> Function(String reason) _askManager;

  Future<ReprintGo> record({required String storeId, required String documentType, required String documentId, required bool requirePinCached}) async {
    var r = await _repo.recordReprint(storeId, documentType: documentType, documentId: documentId);
    if (r.success) return (ok: true, number: r.reprintNumber, message: null);
    if (r.code == 'POS_APPROVAL_REQUIRED') {
      final token = await _askManager('This store needs a manager to approve reprints.');
      if (token == null) return (ok: false, number: null, message: 'Reprint cancelled: a manager did not approve it.');
      r = await _repo.recordReprint(storeId, documentType: documentType, documentId: documentId, approverToken: token);
      if (r.success) return (ok: true, number: r.reprintNumber, message: null);
      return (ok: false, number: null, message: r.code == 'POS_APPROVAL_REQUIRED' ? 'That PIN is not a manager\'s. Reprint not approved.' : (r.message ?? 'Could not record the reprint.'));
    }
    if (r.code == null && r.message == null) {
      // no connection: nothing can be recorded
      if (requirePinCached) return (ok: false, number: null, message: 'Reprints need a manager\'s approval and an internet connection in this store. Try again when online.');
      return (ok: true, number: null, message: null);
    }
    return (ok: false, number: null, message: r.message ?? 'Could not record the reprint.');
  }
}
