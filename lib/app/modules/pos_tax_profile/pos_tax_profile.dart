import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/money.dart';

/// Store tax profile (OWNER, behind the owner gate): NTN, STRN, the business name and address as registered, the default tax category for a
/// custom item — plus the return policy (may a cashier return; amount / day limits above which a manager must approve). All optional now;
/// the tax identifiers become required later, when fiscal integration is enabled for the store.
class PosTaxProfileController extends GetxController {
  PosTaxProfileController({PosRepository? repository, String? storeId}) : _repo = repository ?? PosRepository(), _storeIdOverride = storeId;
  final PosRepository _repo;
  final String? _storeIdOverride;

  final ntn = TextEditingController();
  final strn = TextEditingController();
  final legalName = TextEditingController();
  final address = TextEditingController();
  final amountLimit = TextEditingController();
  final daysLimit = TextEditingController();
  final RxString defaultCategory = 'standard'.obs;
  final RxBool cashierReturns = false.obs;
  final RxBool loading = true.obs;
  final RxBool saving = false.obs;
  final RxnString error = RxnString();
  final RxnString info = RxnString();
  PosSettingsModel? settings;
  String storeId = '';

  @override
  void onInit() {
    super.onInit();
    load();
  }

  @override
  void onClose() {
    for (final c in [ntn, strn, legalName, address, amountLimit, daysLimit]) {
      c.dispose();
    }
    super.onClose();
  }

  Future<void> load() async {
    loading.value = true;
    storeId = _storeIdOverride ?? (await AppPreferences.getStoreId()) ?? '';
    final s = await _repo.getPosSettings(storeId);
    settings = s;
    if (s == null) {
      error.value = 'Could not load the settings.';
    } else {
      ntn.text = s.taxNtn ?? '';
      strn.text = s.taxStrn ?? '';
      legalName.text = s.taxLegalName ?? '';
      address.text = s.taxRegisteredAddress ?? '';
      defaultCategory.value = s.defaultTaxCategory;
      cashierReturns.value = s.cashierReturnsEnabled;
      amountLimit.text = s.returnApprovalAboveMinor == null ? '' : (s.returnApprovalAboveMinor! / _p10(s.currencyExponent)).toString().replaceFirst(RegExp(r'\.0$'), '');
      daysLimit.text = s.returnApprovalAfterDays?.toString() ?? '';
    }
    loading.value = false;
  }

  static num _p10(int e) => e <= 0 ? 1 : List.filled(e, 10).fold<num>(1, (a, b) => a * b);

  /// Saves the profile. An empty field clears it. Guarded against a double tap.
  Future<bool> save() async {
    if (saving.value) return false;
    error.value = null;
    info.value = null;
    final exp = settings?.currencyExponent ?? 2;
    int? limitMinor;
    if (amountLimit.text.trim().isNotEmpty) {
      final v = double.tryParse(amountLimit.text.trim());
      if (v == null || v < 0) {
        error.value = 'Enter a valid amount limit, or leave it empty for no limit.';
        return false;
      }
      limitMinor = (v * _p10(exp)).round();
    }
    int? days;
    if (daysLimit.text.trim().isNotEmpty) {
      days = int.tryParse(daysLimit.text.trim());
      if (days == null || days < 0) {
        error.value = 'Enter the number of days as a whole number, or leave it empty for no limit.';
        return false;
      }
    }
    String? n(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    saving.value = true;
    try {
      final r = await _repo.updatePosSettings(storeId, {
        'taxNtn': n(ntn),
        'taxStrn': n(strn),
        'taxLegalName': n(legalName),
        'taxRegisteredAddress': n(address),
        'defaultTaxCategory': defaultCategory.value,
        'cashierReturnsEnabled': cashierReturns.value,
        'returnApprovalAboveMinor': limitMinor,
        'returnApprovalAfterDays': days,
      });
      if (r == null) {
        error.value = 'Could not save. Check the NTN (7–15 digits) and STRN, then try again.';
        return false;
      }
      settings = r;
      info.value = 'Saved.';
      return true;
    } finally {
      saving.value = false;
    }
  }

  String get currencyLabel => Money.symbol();
}

class PosTaxProfileView extends StatelessWidget {
  PosTaxProfileView({super.key, PosTaxProfileController? controller}) : c = controller ?? Get.put(PosTaxProfileController());
  final PosTaxProfileController c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(title: const Text('Store tax profile'), backgroundColor: p.background, foregroundColor: p.textPrimary, elevation: 0),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Obx(() {
              if (c.loading.value) return const Center(child: CircularProgressIndicator(key: Key('taxLoading')));
              return ListView(
                padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s6),
                children: [
                  Text('As registered with the tax authority. Printed on tax invoices and credit notes. Optional today.', style: t.body.copyWith(color: p.textSecondary)),
                  const SizedBox(height: Space.s4),
                  AppTextField(key: const Key('taxNtn'), label: 'NTN', controller: c.ntn, mono: true, hint: '1234567-8'),
                  const SizedBox(height: Space.s3),
                  AppTextField(key: const Key('taxStrn'), label: 'STRN', controller: c.strn, mono: true),
                  const SizedBox(height: Space.s3),
                  AppTextField(key: const Key('taxLegalName'), label: 'Registered business name', controller: c.legalName),
                  const SizedBox(height: Space.s3),
                  AppTextField(key: const Key('taxAddress'), label: 'Registered address', controller: c.address, maxLines: 2),
                  const SizedBox(height: Space.s4),
                  Text('Default tax category (custom items)', style: t.subtitle.copyWith(color: p.textPrimary)),
                  const SizedBox(height: Space.s2),
                  Obx(() => SegmentedButton<String>(key: const Key('taxCategory'), segments: const [ButtonSegment(value: 'standard', label: Text('Store tax rate')), ButtonSegment(value: 'exempt', label: Text('Tax exempt'))], selected: {c.defaultCategory.value}, onSelectionChanged: (s) => c.defaultCategory.value = s.first)),
                  const SizedBox(height: Space.s5),
                  Text('Returns', style: t.title.copyWith(color: p.textPrimary)),
                  const SizedBox(height: Space.s2),
                  AppCard(
                    radius: Radii.rMd,
                    child: Row(children: [Expanded(child: Text('Cashiers may process returns', style: t.body.copyWith(color: p.textPrimary))), Obx(() => Switch(key: const Key('cashierReturns'), value: c.cashierReturns.value, onChanged: (v) => c.cashierReturns.value = v))]),
                  ),
                  const SizedBox(height: Space.s3),
                  AppTextField(key: const Key('returnAmountLimit'), label: 'A manager must approve returns above (${c.currencyLabel})', controller: c.amountLimit, mono: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), helperText: 'Empty = no limit'),
                  const SizedBox(height: Space.s3),
                  AppTextField(key: const Key('returnDaysLimit'), label: '… or later than this many days after the sale', controller: c.daysLimit, mono: true, keyboardType: TextInputType.number, helperText: 'Empty = no limit. A return without the original receipt always needs a manager.'),
                  Obx(() => c.error.value == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: Space.s3), child: Text(c.error.value!, key: const Key('taxError'), style: t.body.copyWith(color: p.danger)))),
                  Obx(() => c.info.value == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: Space.s3), child: Text(c.info.value!, key: const Key('taxInfo'), style: t.body.copyWith(color: p.successFg)))),
                  const SizedBox(height: Space.s4),
                  Obx(() => AppButton(key: const Key('taxSave'), label: 'Save', loading: c.saving.value, onPressed: c.saving.value ? null : c.save)),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}
