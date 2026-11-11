import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_stock_ops_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// G4.6: low stock → a DRAFT purchase order for one supplier (the store's reorder suggestions at their suggested quantities and current cost).
/// Nothing is approved or sent: the draft opens in the purchase order screen to edit as usual. Managers (supply.po.write); refusals in words.
class DraftPoSheet extends StatefulWidget {
  const DraftPoSheet({super.key, this.repository, this.storeId});
  final PosRepository? repository;
  final String? storeId;

  static Future<void> open({PosRepository? repository, String? storeId}) =>
      Get.bottomSheet(DraftPoSheet(repository: repository, storeId: storeId), isScrollControlled: true, backgroundColor: Colors.transparent);

  @override
  State<DraftPoSheet> createState() => _DraftPoSheetState();
}

class _DraftPoSheetState extends State<DraftPoSheet> {
  late final PosRepository _repo = widget.repository ?? PosRepository();
  List<Supplier>? _suppliers;
  String? _error;
  String? _busyFor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!reportsOnline()) {
      setState(() => _error = 'Drafting a purchase order needs an internet connection.');
      return;
    }
    final r = await _repo.getSuppliers(await reportsStoreId(widget.storeId));
    if (!mounted) return;
    setState(() {
      _suppliers = r?.suppliers.where((s) => s.status != 'archived' && s.status != 'inactive').toList();
      _error = r == null ? stockOpsErrorMessage(_repo.lastErrorCode, message: 'Could not load the suppliers. Try again.') : null;
    });
  }

  Future<void> _draft(Supplier s) async {
    setState(() {
      _busyFor = s.id;
      _error = null;
    });
    final r = await _repo.draftPoFromLowStock(await reportsStoreId(widget.storeId), s.id);
    if (!mounted) return;
    setState(() => _busyFor = null);
    if (!r.success || r.order == null) {
      setState(() => _error = stockOpsErrorMessage(r.code, message: r.message));
      return;
    }
    Get.back();
    Get.toNamed(Routes.posSupplyOrder, arguments: {'orderId': r.order!.id});
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final list = _suppliers;
    return AppSheetSurface(
      key: const Key('draftPoSheet'),
      title: 'Draft a purchase order',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Choose the supplier. Their low items go into a draft at the suggested quantities; you review it before approving.', style: t.bodySmall.copyWith(color: p.textSecondary)),
          const SizedBox(height: Space.s2),
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: Space.s2), child: Text(_error!, key: const Key('draftPoError'), style: t.caption.copyWith(color: p.dangerFg))),
          if (list == null && _error == null)
            const Padding(padding: EdgeInsets.all(Space.s4), child: Center(child: CircularProgressIndicator(key: Key('draftPoLoading'))))
          else if (list != null && list.isEmpty)
            Text('No suppliers yet. Add one in Suppliers & purchase orders.', key: const Key('draftPoNoSuppliers'), style: t.caption.copyWith(color: p.textMuted))
          else
            for (final s in list ?? const <Supplier>[])
              ListTile(
                key: Key('draftPoSupplier_${s.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(s.name),
                trailing: _busyFor == s.id ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.chevron_right_rounded),
                onTap: _busyFor == null ? () => _draft(s) : null,
              ),
        ],
      ),
    );
  }
}
