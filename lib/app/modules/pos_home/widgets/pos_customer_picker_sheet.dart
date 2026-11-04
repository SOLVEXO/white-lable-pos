import 'dart:async';

import 'package:solvexo_pos/app/data/models/customer/customer_model.dart';
import 'package:solvexo_pos/app/data/repositories/customer_repository.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Attach a real customer to the current sale. Typing searches globally by
/// name/email/phone (the only search capability the backend exposes);
/// clearing the search falls back to a browsable list of the store's
/// actual past buyers. A local-state sheet calling CustomerRepository
/// directly — mirrors PosBarcodeSheet's pattern rather than spinning up a
/// full GetX controller for what's a single, self-contained interaction.
class PosCustomerPickerSheet extends StatefulWidget {
  final String storeId;
  final CustomerRepository? customerRepository;
  const PosCustomerPickerSheet({super.key, required this.storeId, this.customerRepository});

  @override
  State<PosCustomerPickerSheet> createState() => _PosCustomerPickerSheetState();
}

class _PosCustomerPickerSheetState extends State<PosCustomerPickerSheet> {
  late final _repo = widget.customerRepository ?? CustomerRepository();
  final _searchController = TextEditingController();
  Timer? _debounce;

  bool _isLoading = true;
  List<CustomerModel> _results = [];

  @override
  void initState() {
    super.initState();
    _loadBrowseList();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBrowseList() async {
    setState(() => _isLoading = true);
    final page = await _repo.getStoreCustomers(widget.storeId);
    if (!mounted) return;
    setState(() {
      _results = page.items;
      _isLoading = false;
    });
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      _loadBrowseList();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _isLoading = true);
      final results = await _repo.searchCustomers(widget.storeId, q.trim());
      if (!mounted) return;
      setState(() {
        _results = results;
        _isLoading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Opened with Get.bottomSheet (transparent route background), so the sheet draws its own surface.
    return AppSheetSurface(
      scrollable: false,
      padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s4),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Semantics(header: true, child: Text('Select customer', style: context.type.title.copyWith(color: p.textPrimary)))),
                TextButton(
                  key: const Key('walkInButton'),
                  onPressed: () => Get.back(),
                  style: TextButton.styleFrom(minimumSize: const Size(Space.minTouch, Space.minTouch), foregroundColor: p.accentFg),
                  child: Text('Walk-in', style: context.type.label.copyWith(color: p.accentFg)),
                ),
              ],
            ),
            const SizedBox(height: Space.s2),
            AppSearchBar(controller: _searchController, hint: 'Search by name, email, or phone', onChanged: _onSearchChanged),
            const SizedBox(height: Space.s3),
            Expanded(
              child: _isLoading
                  ? const SkeletonList(itemCount: 5, padding: EdgeInsets.zero)
                  : _results.isEmpty
                  ? const EmptyState(icon: Icons.people_outline_rounded, title: 'No customers found.')
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: p.border),
                      itemBuilder: (_, i) {
                        final customer = _results[i];
                        final sub = customer.phone ?? customer.email ?? '';
                        return InkWell(
                          key: Key('customer-${customer.id}'),
                          onTap: () => Get.back(result: customer),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: Space.minTouch + 8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: Space.s2),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: p.accentSoft,
                                    child: Text(customer.name.isEmpty ? '?' : customer.name.characters.first.toUpperCase(), style: context.type.subtitle.copyWith(color: p.accentFg)),
                                  ),
                                  const SizedBox(width: Space.s3),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(customer.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.type.subtitle.copyWith(color: p.textPrimary)),
                                        if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.type.caption.copyWith(color: p.textMuted)),
                                      ],
                                    ),
                                  ),
                                  if (customer.orderCount != null) StatusBadge('${customer.orderCount} orders'),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
