import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:solvexo_pos/app/data/models/pos/kyb_models.dart';
import 'package:solvexo_pos/app/data/repositories/kyb_repository.dart';
import 'package:solvexo_pos/app/data/services/idle_lock_service.dart';
import 'package:solvexo_pos/app/platform/screen_privacy.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// Owner business verification (KYB). PRIVACY RULES (by design, tested):
///  * nothing is stored on the device — no cache, no draft, and a picked photo is DELETED right after it is uploaded;
///  * the form and the loaded application are wiped when the app goes to the background, when the till locks, and on leaving;
///  * screenshots / recordings / the recent-apps thumbnail are blocked while this screen is up (see [ScreenPrivacy]).
/// The server returns sensitive values masked only, so the form starts blank: only what the owner types is sent.
class PosKybController extends GetxController with WidgetsBindingObserver {
  PosKybController({KybRepository? repository, ImagePicker? picker, String? storeId, Worker? Function(PosKybController)? lockWatcher})
      : _repo = repository ?? KybRepository(),
        _picker = picker ?? ImagePicker(),
        _storeIdOverride = storeId,
        _lockWatcher = lockWatcher;

  final KybRepository _repo;
  final ImagePicker _picker;
  final String? _storeIdOverride;
  final Worker? Function(PosKybController)? _lockWatcher;

  final Rxn<KybView> view = Rxn<KybView>();
  final RxBool loading = true.obs;
  final RxBool saving = false.obs;
  final RxBool submitting = false.obs;
  final RxnString uploadingType = RxnString();
  final RxnString error = RxnString();
  final RxnString info = RxnString();
  final RxBool wiped = false.obs; // true after a background / lock wipe, until the next load

  final RxnString businessType = RxnString();
  final legalName = TextEditingController();
  final address = TextEditingController();
  final contactName = TextEditingController();
  final contactDesignation = TextEditingController();
  final contactEmail = TextEditingController();
  final contactPhone = TextEditingController();
  final bankName = TextEditingController();
  final accountTitle = TextEditingController();
  final iban = TextEditingController();
  final cnic = TextEditingController();
  final ntn = TextEditingController();

  List<TextEditingController> get _all => [legalName, address, contactName, contactDesignation, contactEmail, contactPhone, bankName, accountTitle, iban, cnic, ntn];

  Worker? _lockWorker;
  String _storeId = '';

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    ScreenPrivacy.acquire();
    _lockWorker = _lockWatcher?.call(this) ?? _watchIdleLock();
    load();
  }

  Worker? _watchIdleLock() {
    if (!Get.isRegistered<IdleLockService>()) return null;
    return ever(Get.find<IdleLockService>().locked, (locked) {
      if (locked == true) wipe();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // inactive covers the iOS app switcher; paused / hidden / detached cover everything else
    if (state != AppLifecycleState.resumed) {
      wipe();
    } else if (wiped.value) {
      load();
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _lockWorker?.dispose();
    wipe();
    ScreenPrivacy.release();
    for (final c in _all) {
      c.dispose();
    }
    super.onClose();
  }

  /// Clears the form and everything loaded from the server. The server still has the application; the screen reloads it on return.
  void wipe() {
    for (final c in _all) {
      c.clear();
    }
    businessType.value = null;
    view.value = null;
    error.value = null;
    info.value = null;
    wiped.value = true;
  }

  Future<String> _store() async => _storeId = _storeIdOverride ?? (await AppPreferences.getStoreId()) ?? '';

  Future<void> load() async {
    loading.value = true;
    error.value = null;
    final sid = await _store();
    final r = await _repo.get(sid);
    loading.value = false;
    if (r.view == null) {
      error.value = r.message ?? 'Could not load the verification.';
      return;
    }
    wiped.value = false;
    _fill(r.view!);
  }

  /// Non-sensitive text is shown for editing; sensitive values stay masked on the screen and the fields start blank.
  void _fill(KybView v) {
    view.value = v;
    businessType.value = v.businessType;
    legalName.text = v.legalBusinessName ?? '';
    address.text = v.businessAddress ?? '';
    contactName.text = v.contactName ?? '';
    contactDesignation.text = v.contactDesignation ?? '';
    contactEmail.text = v.contactEmail ?? '';
    contactPhone.text = v.contactPhone ?? '';
    bankName.text = v.bankName ?? '';
  }

  Map<String, dynamic> _draftPayload() {
    String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final m = <String, dynamic>{
      if (businessType.value != null) 'businessType': businessType.value,
      if (t(legalName) != null) 'legalBusinessName': t(legalName),
      if (t(address) != null) 'businessAddress': t(address),
      if (t(bankName) != null) 'bankName': t(bankName),
      'contact': {
        if (t(contactName) != null) 'name': t(contactName),
        if (t(contactDesignation) != null) 'designation': t(contactDesignation),
        if (t(contactEmail) != null) 'email': t(contactEmail),
        if (t(contactPhone) != null) 'phone': t(contactPhone),
      },
      // sensitive: only when the owner typed a new value
      if (t(cnic) != null) 'cnic': t(cnic),
      if (t(ntn) != null) 'ntn': t(ntn),
      if (t(iban) != null) 'iban': t(iban),
      if (t(accountTitle) != null) 'accountTitle': t(accountTitle),
    };
    return m;
  }

  /// Saves the draft. Returns true on success.
  Future<bool> save() async {
    if (saving.value || submitting.value) return false; // double-submit protection
    return _save();
  }

  Future<bool> _save() async {
    saving.value = true;
    error.value = null;
    info.value = null;
    try {
      final r = await _repo.saveDraft(await _store(), _draftPayload());
      if (r.view == null) {
        error.value = r.message ?? 'Could not save.';
        return false;
      }
      // typed sensitive values are now on the server (masked in the response) — wipe them from the form straight away
      for (final c in [cnic, ntn, iban, accountTitle]) {
        c.clear();
      }
      view.value = r.view;
      info.value = 'Saved.';
      return true;
    } finally {
      saving.value = false;
    }
  }

  Future<void> submit() async {
    if (submitting.value || saving.value) return;
    submitting.value = true;
    error.value = null;
    try {
      if (!await _save()) return; // submit what the server has, after saving what is on screen
      final r = await _repo.submit(_storeId);
      if (r.view == null) {
        error.value = r.message ?? 'Could not submit.';
        return;
      }
      view.value = r.view;
      info.value = 'Submitted for review.';
    } finally {
      submitting.value = false;
    }
  }

  /// Camera or gallery. The picked photo only exists in the system temp folder for the length of the upload, then it is deleted.
  Future<void> pickAndUpload(String type, ImageSource source) async {
    if (uploadingType.value != null) return; // one upload at a time
    uploadingType.value = type;
    error.value = null;
    File? file;
    try {
      final x = await _picker.pickImage(source: source, maxWidth: 2000, imageQuality: 85, requestFullMetadata: false);
      if (x == null) return;
      file = File(x.path);
      final r = await _repo.uploadDocument(await _store(), type: type, file: file);
      if (r.view == null) {
        error.value = r.message ?? 'Could not upload the document.';
        return;
      }
      view.value = r.view;
      info.value = 'Document uploaded.';
    } finally {
      try {
        if (file != null && file.existsSync()) file.deleteSync();
      } catch (_) {}
      uploadingType.value = null;
    }
  }

  Future<void> removeDocument(KybDocumentInfo d) async {
    if (uploadingType.value != null) return;
    uploadingType.value = d.type;
    try {
      final r = await _repo.removeDocument(await _store(), d.id);
      if (r.view == null) {
        error.value = r.message ?? 'Could not remove the document.';
        return;
      }
      view.value = r.view;
    } finally {
      uploadingType.value = null;
    }
  }
}
