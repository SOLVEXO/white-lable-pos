import 'dart:async';

import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/components/custom_text_field.dart';
import 'package:solvexo_pos/app/data/models/customer/customer_model.dart';
import 'package:solvexo_pos/app/data/repositories/customer_repository.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
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
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 16),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        Container(
          width: 36, height: 4,
          decoration: BoxDecoration(color: AppColors.lightGrey2, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 16),
        Row(children: [
          const Expanded(
            child: CustomText(
              text: 'Select Customer',
              fontSize: AppFontSize.small2,
              fontWeight: FontWeight.bold,
              color: AppColors.black2,
            ),
          ),
          GestureDetector(
            onTap: () => Get.back(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
              child: const CustomText(text: 'Walk-in', fontSize: AppFontSize.tiny, color: AppColors.iosGrey),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        CustomTextField(
          controller: _searchController,
          hintText: 'Search by name, email, or phone',
          fillColor: AppColors.background,
          onChanged: _onSearchChanged,
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.iosGrey, size: 18),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _isLoading
              ? Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryColor))
              : _results.isEmpty
                  ? const Center(
                      child: CustomText(
                        text: 'No customers found.',
                        fontSize: AppFontSize.verySmall,
                        color: AppColors.iosGrey,
                      ),
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final customer = _results[i];
                        return GestureDetector(
                          onTap: () => Get.back(result: customer),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  CustomText(
                                    text: customer.name,
                                    fontSize: AppFontSize.verySmall,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.black2,
                                  ),
                                  CustomText(
                                    text: customer.phone ?? customer.email ?? '',
                                    fontSize: AppFontSize.tiny,
                                    color: AppColors.iosGrey,
                                  ),
                                ]),
                              ),
                              if (customer.orderCount != null)
                                CustomText(
                                  text: '${customer.orderCount} orders',
                                  fontSize: AppFontSize.tiny,
                                  color: AppColors.iosGrey,
                                ),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
