import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:solvexo_pos/app/data/models/pos/kyb_models.dart';
import 'package:solvexo_pos/app/modules/pos_kyb/controllers/pos_kyb_controller.dart';
import 'package:solvexo_pos/app/platform/privacy_curtain.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Owner → Business verification: status (and why it was sent back), the application form, document upload (camera or photo library),
/// submit. Behind the owner gate; protected from screenshots; wiped on background / lock (see [PosKybController]).
class PosKybView extends StatelessWidget {
  PosKybView({super.key, PosKybController? controller}) : c = controller ?? Get.put(PosKybController());
  final PosKybController c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PrivacyCurtain(
      child: Scaffold(
        backgroundColor: p.background,
        appBar: AppBar(title: const Text('Business verification'), backgroundColor: p.background, foregroundColor: p.textPrimary, elevation: 0),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Obx(() {
                if (c.loading.value) return const Center(child: CircularProgressIndicator(key: Key('kybLoading')));
                final v = c.view.value;
                if (v == null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.s5),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(c.wiped.value ? Icons.lock_outline_rounded : Icons.error_outline_rounded, size: 40, color: p.textMuted),
                          const SizedBox(height: Space.s3),
                          Text(c.error.value ?? 'Hidden while the app was in the background.', key: const Key('kybEmpty'), textAlign: TextAlign.center, style: context.type.body.copyWith(color: p.textSecondary)),
                          const SizedBox(height: Space.s4),
                          AppButton(key: const Key('kybReload'), label: 'Reload', expand: false, onPressed: c.load),
                        ],
                      ),
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s6),
                  children: [
                    _StatusCard(v: v),
                    if (c.error.value != null) Padding(padding: const EdgeInsets.only(top: Space.s3), child: Text(c.error.value!, key: const Key('kybError'), style: context.type.body.copyWith(color: p.danger))),
                    if (c.info.value != null) Padding(padding: const EdgeInsets.only(top: Space.s3), child: Text(c.info.value!, key: const Key('kybInfo'), style: context.type.body.copyWith(color: p.successFg))),
                    const SizedBox(height: Space.s4),
                    _Form(c: c, v: v),
                    const SizedBox(height: Space.s4),
                    _Documents(c: c, v: v),
                    const SizedBox(height: Space.s5),
                    if (v.editable) ...[
                      AppButton(key: const Key('kybSave'), label: 'Save draft', variant: AppButtonVariant.secondary, loading: c.saving.value, onPressed: c.submitting.value ? null : c.save),
                      const SizedBox(height: Space.s3),
                      AppButton(key: const Key('kybSubmit'), label: v.status == 'rejected' ? 'Submit again' : 'Submit for review', loading: c.submitting.value, onPressed: (c.saving.value || v.missingDocuments.isNotEmpty) ? null : c.submit),
                      if (v.missingDocuments.isNotEmpty)
                        Padding(padding: const EdgeInsets.only(top: Space.s2), child: Text('Upload the required documents to submit.', key: const Key('kybMissingHint'), textAlign: TextAlign.center, style: context.type.caption.copyWith(color: p.textMuted))),
                    ],
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.v});
  final KybView v;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (label, tone, text) = switch (v.status) {
      'verified' => ('Verified', StatusTone.success, v.digitalPaymentsEnabled ? 'Raast QR payments are on.' : 'Verified. Digital payments switch on once the payment provider finishes setting up your business.'),
      'submitted' || 'under_review' => ('In review', StatusTone.warning, 'Solvexo is reviewing your application. You cannot edit it while it is in review.'),
      'rejected' => ('Sent back', StatusTone.danger, 'Fix what is listed below and submit again.'),
      _ => ('Draft', StatusTone.neutral, 'Fill in your business details and upload the documents, then submit.'),
    };
    return AppCard(
      radius: Radii.rMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusBadge(label, key: const Key('kybStatus'), tone: tone),
          const SizedBox(height: Space.s2),
          Text(text, style: context.type.body.copyWith(color: p.textSecondary)),
          if (v.status == 'rejected' && (v.rejectionReason ?? '').isNotEmpty) ...[
            const SizedBox(height: Space.s2),
            Container(
              padding: const EdgeInsets.all(Space.s3),
              decoration: BoxDecoration(color: p.dangerSoft, borderRadius: Radii.rMd),
              child: Text(v.rejectionReason!, key: const Key('kybRejection'), style: context.type.body.copyWith(color: p.dangerFg)),
            ),
          ],
        ],
      ),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({required this.c, required this.v});
  final PosKybController c;
  final KybView v;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ro = !v.editable;
    Widget gap() => const SizedBox(height: Space.s3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Business type', style: context.type.title.copyWith(color: p.textPrimary)),
        const SizedBox(height: Space.s2),
        Obx(() => Wrap(
              spacing: Space.s2,
              children: [
                for (final (code, label) in kKybBusinessTypes)
                  ChoiceChip(key: Key('kybType_$code'), label: Text(label), selected: c.businessType.value == code, onSelected: ro ? null : (_) => c.businessType.value = code),
              ],
            )),
        gap(),
        AppTextField(key: const Key('kybLegalName'), label: 'Legal business name', controller: c.legalName, readOnly: ro),
        gap(),
        AppTextField(key: const Key('kybAddress'), label: 'Business address', controller: c.address, readOnly: ro, maxLines: 2),
        gap(),
        Text('Contact person', style: context.type.title.copyWith(color: p.textPrimary)),
        const SizedBox(height: Space.s2),
        AppTextField(key: const Key('kybContactName'), label: 'Name', controller: c.contactName, readOnly: ro),
        gap(),
        AppTextField(key: const Key('kybContactDesignation'), label: 'Designation', controller: c.contactDesignation, readOnly: ro),
        gap(),
        AppTextField(key: const Key('kybContactEmail'), label: 'Email', controller: c.contactEmail, readOnly: ro, keyboardType: TextInputType.emailAddress),
        gap(),
        AppTextField(key: const Key('kybContactPhone'), label: 'Phone', controller: c.contactPhone, readOnly: ro, keyboardType: TextInputType.phone),
        gap(),
        Text('Identity and bank', style: context.type.title.copyWith(color: p.textPrimary)),
        const SizedBox(height: Space.s2),
        AppTextField(key: const Key('kybCnic'), label: 'CNIC (13 digits)', controller: c.cnic, readOnly: ro, keyboardType: TextInputType.number, helperText: v.cnicMasked == null ? null : 'Saved: ${v.cnicMasked}. Type a new one only to replace it.'),
        if (v.registeredBusiness || c.businessType.value == 'company' || c.businessType.value == 'partnership') ...[
          gap(),
          AppTextField(key: const Key('kybNtn'), label: 'NTN', controller: c.ntn, readOnly: ro, keyboardType: TextInputType.number, helperText: v.ntnMasked == null ? null : 'Saved: ${v.ntnMasked}. Type a new one only to replace it.'),
        ],
        gap(),
        AppTextField(key: const Key('kybBank'), label: 'Bank name', controller: c.bankName, readOnly: ro),
        gap(),
        AppTextField(key: const Key('kybAccountTitle'), label: 'Account title', controller: c.accountTitle, readOnly: ro, helperText: v.accountTitleSet ? 'Saved. Type a new one only to replace it.' : null),
        gap(),
        AppTextField(key: const Key('kybIban'), label: 'IBAN', controller: c.iban, readOnly: ro, helperText: v.ibanMasked == null ? null : 'Saved: ${v.ibanMasked}. Type a new one only to replace it.'),
      ],
    );
  }
}

class _Documents extends StatelessWidget {
  const _Documents({required this.c, required this.v});
  final PosKybController c;
  final KybView v;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final types = [...v.requiredDocuments, ...v.optionalDocuments];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Documents', style: context.type.title.copyWith(color: p.textPrimary)),
        const SizedBox(height: Space.s1),
        Text('Photos and PDFs are sent straight to Solvexo and are not kept on this device.', style: context.type.caption.copyWith(color: p.textMuted)),
        const SizedBox(height: Space.s2),
        for (final type in types)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s2),
            child: _DocRow(c: c, v: v, type: type, required: v.requiredDocuments.contains(type)),
          ),
      ],
    );
  }
}

class _DocRow extends StatelessWidget {
  const _DocRow({required this.c, required this.v, required this.type, required this.required});
  final PosKybController c;
  final KybView v;
  final String type;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final docs = v.documents.where((d) => d.type == type).toList();
    return AppCard(
      key: Key('kybDoc_$type'),
      radius: Radii.rMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(kKybDocumentLabels[type] ?? type, style: context.type.subtitle.copyWith(color: p.textPrimary))),
              StatusBadge(docs.isNotEmpty ? 'Uploaded' : (required ? 'Required' : 'Optional'), tone: docs.isNotEmpty ? StatusTone.success : (required ? StatusTone.warning : StatusTone.neutral)),
            ],
          ),
          for (final d in docs)
            Row(
              children: [
                Icon(Icons.description_outlined, size: 18, color: p.textMuted),
                const SizedBox(width: Space.s2),
                Expanded(child: Text(d.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.type.caption.copyWith(color: p.textSecondary))),
                if (v.editable) IconButton(key: Key('kybRemove_${d.id}'), tooltip: 'Remove', icon: const Icon(Icons.delete_outline_rounded), onPressed: () => c.removeDocument(d)),
              ],
            ),
          if (v.editable)
            Obx(() {
              final busy = c.uploadingType.value != null;
              return Padding(
                padding: const EdgeInsets.only(top: Space.s2),
                child: Row(
                  children: [
                    Expanded(child: AppButton(key: Key('kybCamera_$type'), label: 'Camera', icon: Icons.photo_camera_outlined, variant: AppButtonVariant.secondary, loading: c.uploadingType.value == type, onPressed: busy ? null : () => c.pickAndUpload(type, ImageSource.camera))),
                    const SizedBox(width: Space.s2),
                    Expanded(child: AppButton(key: Key('kybGallery_$type'), label: 'Photos', icon: Icons.photo_library_outlined, variant: AppButtonVariant.secondary, onPressed: busy ? null : () => c.pickAndUpload(type, ImageSource.gallery))),
                    const SizedBox(width: Space.s2),
                    Expanded(child: AppButton(key: Key('kybPdf_$type'), label: 'PDF', icon: Icons.picture_as_pdf_outlined, variant: AppButtonVariant.secondary, onPressed: busy ? null : () => c.pickPdfAndUpload(type))),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
