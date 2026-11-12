import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:solvexo_pos/app/components/owner_unlock_button.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_admin_models.dart';
import 'package:solvexo_pos/app/modules/pos/views/pos_hub_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_admin/controllers/store_settings_controller.dart';
import 'package:solvexo_pos/app/modules/pos_admin/views/about_help_views.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/report_widgets.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/receipt_logo.dart';

/// The hub's controller is shared by its screens; a screen opened on its own creates it.
StoreSettingsController _settingsC(StoreSettingsController? given) =>
    given ?? (Get.isRegistered<StoreSettingsController>() ? Get.find<StoreSettingsController>() : Get.put(StoreSettingsController()));

// ── the hub ─────────────────────────────────────────────────────────────────
/// G4.4 settings hub: every store setting in one place. New screens (receipt designer, notifications, security, backup & sync) and the existing
/// ones (time zone, tax profile, verification, registers, devices, printer, roles, activity log), each behind its own guard.
class SettingsHubView extends StatefulWidget {
  const SettingsHubView({super.key, this.controller});
  final StoreSettingsController? controller;
  @override
  State<SettingsHubView> createState() => _SettingsHubViewState();
}

class _SettingsHubViewState extends State<SettingsHubView> {
  late final bool _owns = widget.controller == null && !Get.isRegistered<StoreSettingsController>();
  late final StoreSettingsController c = _settingsC(widget.controller);

  @override
  void initState() {
    super.initState();
    // a controller left by a screen opened on its own is refreshed (a new one loads in onInit)
    if (!_owns && widget.controller == null) c.load();
  }

  @override
  void dispose() {
    if (_owns) Get.delete<StoreSettingsController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final s = c.settings.value;
      final edit = s?.canEdit ?? false;
      String? onOff(bool v) => v ? 'On' : 'Off';
      return HubScaffold(
        title: 'Store settings',
        listKey: const Key('settingsHub'),
        children: [
          if (s != null && !edit) ...[
            const ReportInfo(key: Key('settingsReadOnly'), 'Only the owner can change store settings. You can see them here.', icon: Icons.lock_outline_rounded),
            OwnerUnlockButton(onUnlocked: c.load),
          ],
          if (c.error.value != null && s == null) ReportInfo(c.error.value!, warn: true),
          HubSection('Store', [
            HubRow(icon: Icons.storefront_outlined, title: s?.businessName ?? 'Store profile', subtitle: s?.businessAddress ?? 'Name, address and tax ID (from the tax profile)', onTap: () => Get.toNamed(Routes.posTaxProfile), locked: true),
            HubRow(icon: Icons.public_rounded, title: 'Store time zone', subtitle: s?.timeZone ?? 'Decides when a business day starts and ends', onTap: () => Get.toNamed(Routes.posStoreTimeZone)),
            HubRow(icon: Icons.hub_outlined, title: 'Integrations', subtitle: 'E-mail / SMS receipts, FBR, accounting export, API keys', onTap: () => Get.toNamed(Routes.posIntegrations), locked: true),
            HubRow(icon: Icons.payments_outlined, title: 'Payments setup', subtitle: 'Raast QR, card on a bank terminal', onTap: () => Get.toNamed(Routes.posPaymentsSetup), locked: true),
            HubRow(icon: Icons.verified_user_outlined, title: 'Business verification', subtitle: 'Needed for Raast QR payments', onTap: () => Get.toNamed(Routes.posKyb), locked: true),
          ]),
          HubSection('Registers & devices', [
            HubRow(icon: Icons.point_of_sale_rounded, title: 'Registers & team', subtitle: 'Registers, employees and PINs', onTap: () => Get.toNamed(Routes.sellerPosManagement), locked: true),
            HubRow(icon: Icons.devices_other_rounded, title: 'Devices', subtitle: 'Registered tills', onTap: () => Get.toNamed(Routes.posDevices), locked: true),
          ]),
          HubSection('Receipts & hardware', [
            HubRow(
              key: const Key('hubReceipt'),
              icon: Icons.receipt_long_outlined,
              title: 'Receipt designer',
              subtitle: s == null ? 'What every receipt shows' : '${s.receipt.defaultPaperWidth} mm · ${ReceiptOptions.flags.where(s.receipt.flag).length} of ${ReceiptOptions.flags.length} items shown',
              onTap: () => Get.to(() => ReceiptDesignerView(controller: c)),
            ),
            HubRow(icon: Icons.print_outlined, title: 'Printer, drawer & sound', subtitle: 'This device', onTap: () => Get.toNamed(Routes.posSettings)),
            HubRow(key: const Key('hubHardware'), icon: Icons.build_circle_outlined, title: 'Hardware check', subtitle: 'Test page, cash drawer, barcode scanner', onTap: () => Get.to(() => const HardwareCheckView())),
          ]),
          HubSection('Team & security', [
            HubRow(icon: Icons.admin_panel_settings_outlined, title: 'Roles & permissions', subtitle: 'Who may do what, and who approves', onTap: () => Get.toNamed(Routes.posRoles)),
            HubRow(
              key: const Key('hubSecurity'),
              icon: Icons.lock_clock_outlined,
              title: 'Security',
              subtitle: s == null ? 'Auto-lock' : 'Auto-lock after ${s.security.autoLockMinutes} min · lock in background ${onOff(s.security.lockOnBackground)}',
              onTap: () => Get.to(() => SecuritySettingsView(controller: c)),
            ),
            HubRow(icon: Icons.shield_outlined, title: 'Activity log & integrity', subtitle: 'Who did what, and whether anything changed', onTap: () => Get.toNamed(Routes.posAuditLog), locked: true),
          ]),
          HubSection('Alerts', [
            HubRow(
              key: const Key('hubAlerts'),
              icon: Icons.notifications_none_rounded,
              title: 'Notifications',
              subtitle: s == null ? 'Which alerts managers see' : '${AlertKeys.all.where(s.alert).length} of ${AlertKeys.all.length} alerts on',
              onTap: () => Get.to(() => AlertSettingsView(controller: c)),
            ),
          ]),
          HubSection('Data', [
            HubRow(key: const Key('hubSync'), icon: Icons.cloud_sync_outlined, title: 'Backup & sync', subtitle: 'What is on this device, devices, the last audit seal', onTap: () => Get.to(() => BackupSyncView(controller: c))),
            HubRow(icon: Icons.sync_problem_rounded, title: 'Needs attention', subtitle: 'Offline sales the server did not accept', onTap: () => Get.toNamed(Routes.posNeedsAttention)),
          ]),
          HubSection('Support', [
            HubRow(key: const Key('hubHelp'), icon: Icons.help_outline_rounded, title: 'Help', subtitle: 'Short answers for everyday tasks', onTap: () => Get.to(() => const HelpView())),
            HubRow(key: const Key('hubAbout'), icon: Icons.info_outline_rounded, title: 'About', subtitle: 'Version, store id, environment, licences', onTap: () => Get.to(() => const AboutView())),
          ]),
        ],
      );
    });
  }
}

// ── shared bits ─────────────────────────────────────────────────────────────
class _SettingsBody extends StatelessWidget {
  const _SettingsBody({required this.c, required this.subject, required this.builder});
  final StoreSettingsController c;
  final String subject;
  final List<Widget> Function(BuildContext, StoreSettings) builder;

  @override
  Widget build(BuildContext context) => Obx(() {
    final s = c.settings.value;
    if (!reportsOnlineRx().value && s == null) return ReportsNeedsInternet(subject: subject);
    if (s == null && c.loading.value) return const Center(child: CircularProgressIndicator(key: Key('settingsLoading')));
    if (s == null) return InvErrorState(message: c.error.value ?? 'Try again.', onRetry: c.load);
    final p = context.palette;
    // the outcome of a save stays in sight above the list, wherever it is scrolled
    final banners = [
      if (!s.canEdit) ...[
        const ReportInfo(key: Key('settingsReadOnly'), 'Only the owner can change these settings.', icon: Icons.lock_outline_rounded),
        OwnerUnlockButton(onUnlocked: c.load),
      ]
      else if (!reportsOnlineRx().value)
        const ReportInfo('Changing settings needs an internet connection.', warn: true),
      if (c.notice.value != null) ReportInfo(key: const Key('settingsNotice'), c.notice.value!, icon: Icons.check_circle_outline_rounded),
      if (c.saveError.value != null)
        Container(
          key: const Key('settingsError'),
          margin: const EdgeInsets.only(bottom: Space.s2),
          padding: const EdgeInsets.all(Space.s3),
          decoration: BoxDecoration(color: p.dangerSoft, borderRadius: Radii.rMd),
          child: Text(c.saveError.value!, style: context.type.bodySmall.copyWith(color: p.dangerFg)),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (banners.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: banners),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
            children: builder(context, s),
          ),
        ),
      ],
    );
  });
}

class _Switch extends StatelessWidget {
  const _Switch({super.key, required this.title, this.subtitle, required this.value, required this.onChanged});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    title: Text(title, style: context.type.body.copyWith(color: context.palette.textPrimary)),
    subtitle: subtitle == null ? null : Text(subtitle!, style: context.type.caption.copyWith(color: context.palette.textSecondary)),
    value: value,
    onChanged: onChanged,
  );
}

// ── receipt designer ────────────────────────────────────────────────────────
class ReceiptDesignerView extends StatelessWidget {
  ReceiptDesignerView({super.key, StoreSettingsController? controller}) : c = _settingsC(controller);
  final StoreSettingsController c;

  @override
  Widget build(BuildContext context) {
    return InvScaffold(
      title: 'Receipt designer',
      maxWidth: 1000,
      actions: [
        Obx(
          () => c.canEdit && c.receiptDirty
              ? TextButton(key: const Key('receiptSave'), onPressed: c.saving.value ? null : c.saveReceipt, child: const Text('Save'))
              : const SizedBox.shrink(),
        ),
      ],
      body: _SettingsBody(
        c: c,
        subject: 'The receipt designer',
        builder: (context, s) {
          final edit = c.canEdit;
          final d = c.receiptDraft.value;
          final controls = <Widget>[
            const InvSectionTitle('Paper'),
            SegmentedButton<int>(
              key: const Key('receiptWidth'),
              segments: const [ButtonSegment(value: 58, label: Text('58 mm')), ButtonSegment(value: 80, label: Text('80 mm'))],
              selected: {d.defaultPaperWidth},
              onSelectionChanged: edit ? (v) => c.setPaperWidth(v.first) : null,
            ),
            Padding(
              padding: const EdgeInsets.only(top: Space.s1),
              child: Text('The preview width. Each till prints at its own printer\'s paper size (Printer settings).', style: context.type.caption.copyWith(color: context.palette.textSecondary)),
            ),
            const InvSectionTitle('What to print'),
            for (final k in ReceiptOptions.flags)
              _Switch(
                key: Key('receiptFlag_$k'),
                title: ReceiptOptions.flagLabel(k),
                subtitle: ReceiptOptions.notPrintedYet.contains(k)
                    ? 'Saved; not on printed receipts yet'
                    : k == 'showQr'
                    ? 'The digital receipt link — printed offline too (it says "syncing" until the sale reaches the server)'
                    : null,
                value: d.flag(k),
                onChanged: edit ? (v) => c.setReceiptFlag(k, v) : null,
              ),
            const InvSectionTitle('Logo'),
            _LogoSection(c: c, edit: edit),
            const InvSectionTitle('Your text'),
            _ReceiptText(key: ValueKey('header_${c.receiptRevision.value}'), fieldKey: 'header', label: 'Header (under the store name)', initial: d.header, max: 300, enabled: edit, c: c),
            _ReceiptText(key: ValueKey('promoText_${c.receiptRevision.value}'), fieldKey: 'promoText', label: 'Promotion line', initial: d.promoText, max: 200, enabled: edit, c: c),
            _ReceiptText(key: ValueKey('footer_${c.receiptRevision.value}'), fieldKey: 'footer', label: 'Footer (e.g. returns policy)', initial: d.footer, max: 300, enabled: edit, c: c),
            if (edit && c.receiptDirty)
              Padding(
                padding: const EdgeInsets.only(top: Space.s3),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(key: const Key('receiptDiscard'), onPressed: c.discardReceipt, child: const Text('Discard')),
                    ),
                    const SizedBox(width: Space.s2),
                    Expanded(
                      child: FilledButton(key: const Key('receiptSaveBottom'), onPressed: c.saving.value ? null : c.saveReceipt, child: const Text('Save receipt')),
                    ),
                  ],
                ),
              ),
          ];
          final preview = Column(
            children: [
              const InvSectionTitle('Preview'),
              ReceiptPreview(options: d, storeName: s.businessName ?? 'Your store', address: s.businessAddress, taxId: s.businessTaxId, logo: c.logoPreview.value),
            ],
          );
          return [
            LayoutBuilder(
              builder: (context, box) => box.maxWidth >= 760
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: controls)),
                        const SizedBox(width: Space.s5),
                        SizedBox(width: 340, child: preview),
                      ],
                    )
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [preview, ...controls]),
            ),
          ];
        },
      ),
    );
  }
}

class _ReceiptText extends StatefulWidget {
  const _ReceiptText({super.key, required this.fieldKey, required this.label, required this.initial, required this.max, required this.enabled, required this.c});
  final String fieldKey, label;
  final String? initial;
  final int max;
  final bool enabled;
  final StoreSettingsController c;
  @override
  State<_ReceiptText> createState() => _ReceiptTextState();
}

class _ReceiptTextState extends State<_ReceiptText> {
  late final TextEditingController _t = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.s2),
    child: TextField(
      key: Key('receiptText_${widget.fieldKey}'),
      controller: _t,
      enabled: widget.enabled,
      maxLength: widget.max,
      maxLines: null,
      decoration: InputDecoration(labelText: widget.label),
      onChanged: (v) => widget.c.setReceiptText(widget.fieldKey, v),
    ),
  );
}

/// A sample receipt drawn from the designer's options (58 mm is narrower). It shows what each switch does; the printer prints the real sale.
class ReceiptPreview extends StatelessWidget {
  const ReceiptPreview({super.key, required this.options, required this.storeName, this.address, this.taxId, this.logo});
  final ReceiptOptions options;
  /// G5.6: the uploaded logo as the printer will print it (null → the placeholder icon)
  final LogoBitmap? logo;
  final String storeName;
  final String? address, taxId;

  @override
  Widget build(BuildContext context) {
    final o = options;
    const ink = Color(0xFF1C1B1A);
    const paper = Color(0xFFFFFDF8);
    final mono = context.type.caption.copyWith(fontFamily: 'Courier', color: ink, height: 1.35);
    Widget line(String a, [String? b]) => Row(
      children: [
        Expanded(child: Text(a, style: mono)),
        if (b != null) Text(b, style: mono),
      ],
    );
    Widget rule() => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('-' * (o.defaultPaperWidth == 58 ? 28 : 40), style: mono, maxLines: 1, overflow: TextOverflow.clip));
    Widget center(String s, {bool bold = false}) => Text(s, style: bold ? mono.copyWith(fontWeight: FontWeight.w700) : mono, textAlign: TextAlign.center);
    return Center(
      child: Container(
        key: Key('receiptPreview_${o.defaultPaperWidth}'),
        width: o.defaultPaperWidth == 58 ? 220 : 300,
        padding: const EdgeInsets.all(Space.s3),
        decoration: BoxDecoration(
          color: paper,
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (o.showLogo) logo != null ? Center(child: LogoBitmapImage(key: const Key('previewLogoBitmap'), bitmap: logo!, width: (o.defaultPaperWidth == 58 ? 220 : 300) * 0.66)) : const Icon(Icons.storefront_rounded, key: Key('previewLogo'), color: ink, size: 28),
            center(storeName, bold: true),
            if (o.showStoreAddress && (address ?? '').isNotEmpty) center(address!),
            if (o.showTaxId) center('NTN ${taxId ?? '1234567-8'}'),
            if (o.header != null) ...[const SizedBox(height: 4), center(o.header!)],
            rule(),
            line('Receipt S-1042', '14:05'),
            if (o.showCashierName) line('Cashier: Ayesha'),
            if (o.showCustomerName) line('Customer: Bilal'),
            rule(),
            line('2 x Tea (Large)', '13.60'),
            line('1 x Biscuits', '1.20'),
            rule(),
            line('Subtotal', '14.80'),
            if (o.showTaxBreakdown) line('Sales tax 18%', '2.66'),
            line('TOTAL', '17.46'),
            line('Cash', '20.00'),
            line('Change', '2.54'),
            if (o.showLoyaltyBalance) ...[rule(), line('Points balance', '140')], // G4.9: the balance after the sale (earned / redeemed when the server has no balance)
            if (o.promoText != null) ...[rule(), center(o.promoText!)],
            if (o.showQr) const Padding(padding: EdgeInsets.only(top: 6), child: Icon(Icons.qr_code_2_rounded, key: Key('previewQr'), color: ink, size: 56)),
            if (o.showBarcode) Padding(padding: const EdgeInsets.only(top: 4), child: center('||| |||| | ||| || ||||', bold: true)),
            if (o.footer != null) ...[const SizedBox(height: 4), center(o.footer!)],
          ],
        ),
      ),
    );
  }
}

// ── notifications ───────────────────────────────────────────────────────────
class AlertSettingsView extends StatelessWidget {
  AlertSettingsView({super.key, StoreSettingsController? controller}) : c = _settingsC(controller);
  final StoreSettingsController c;

  @override
  Widget build(BuildContext context) => InvScaffold(
    title: 'Notifications',
    body: _SettingsBody(
      c: c,
      subject: 'Notification settings',
      builder: (context, s) => [
        Text('In-app alerts managers and the owner see on the till.', style: context.type.bodySmall.copyWith(color: context.palette.textSecondary)),
        const SizedBox(height: Space.s2),
        for (final k in AlertKeys.all)
          _Switch(
            key: Key('alert_$k'),
            title: AlertKeys.label(k),
            subtitle: AlertKeys.help(k),
            value: s.alert(k),
            onChanged: c.canEdit && !c.saving.value ? (v) => c.setAlert(k, v) : null,
          ),
      ],
    ),
  );
}

// ── security ────────────────────────────────────────────────────────────────
const autoLockChoices = [1, 2, 5, 10, 15, 30, 60];

class SecuritySettingsView extends StatelessWidget {
  SecuritySettingsView({super.key, StoreSettingsController? controller}) : c = _settingsC(controller);
  final StoreSettingsController c;

  @override
  Widget build(BuildContext context) => InvScaffold(
    title: 'Security',
    body: _SettingsBody(
      c: c,
      subject: 'Security settings',
      builder: (context, s) {
        final edit = c.canEdit && !c.saving.value;
        final cur = s.security.autoLockMinutes;
        return [
          const InvSectionTitle('Auto-lock'),
          Text('Every till goes back to the PIN screen after this long without a touch. The cart and offline sales stay.', style: context.type.bodySmall.copyWith(color: context.palette.textSecondary)),
          const SizedBox(height: Space.s2),
          Wrap(
            key: const Key('autoLockChoices'),
            spacing: Space.s2,
            runSpacing: Space.s1,
            children: [
              for (final m in {...autoLockChoices, cur}.toList()..sort())
                ChoiceChip(key: Key('autoLock_$m'), label: Text(m == 60 ? '1 hour' : '$m min'), selected: m == cur, onSelected: edit && m != cur ? (_) => c.setAutoLock(m) : null),
            ],
          ),
          const SizedBox(height: Space.s3),
          _Switch(
            key: const Key('lockOnBackground'),
            title: 'Lock when the app is left',
            subtitle: 'Locks as soon as someone switches app or the screen turns off',
            value: s.security.lockOnBackground,
            onChanged: edit ? c.setLockOnBackground : null,
          ),
          const InvSectionTitle('Reprints & costs'),
          _Switch(
            key: const Key('requirePinForReprint'),
            title: 'Manager PIN to reprint',
            subtitle: 'A cashier reprinting a receipt, invoice or credit note needs a manager. Every reprint is recorded and prints "REPRINT #n".',
            value: s.security.requirePinForReprint,
            onChanged: edit ? c.setRequirePinForReprint : null,
          ),
          _Switch(
            key: const Key('hideCostsFromManagers'),
            title: 'Hide costs from managers',
            subtitle: 'Managers no longer see cost prices, stock value, margins or purchase amounts. Only you (the owner) still see them.',
            value: s.security.hideCostsFromManagers,
            onChanged: edit ? c.setHideCostsFromManagers : null,
          ),
          const InvSectionTitle('PINs & sessions'),
          Text(
            'PIN tries are limited per employee and per device by the server; managers approve above the limits set in Roles & permissions.',
            style: context.type.bodySmall.copyWith(color: context.palette.textSecondary),
          ),
        ];
      },
    ),
  );
}

// ── backup & sync ───────────────────────────────────────────────────────────
String _ago(DateTime? at, DateTime now) {
  if (at == null) return 'never';
  final d = now.difference(at);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

class BackupSyncView extends StatefulWidget {
  const BackupSyncView({super.key, this.controller});
  final StoreSettingsController? controller;
  @override
  State<BackupSyncView> createState() => _BackupSyncViewState();
}

class _BackupSyncViewState extends State<BackupSyncView> {
  late final StoreSettingsController c = _settingsC(widget.controller);

  @override
  void initState() {
    super.initState();
    c.loadSync();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return InvScaffold(
      title: 'Backup & sync',
      actions: [IconButton(key: const Key('syncRefresh'), tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded), onPressed: c.loadSync)],
      body: Obx(() {
        final q = c.local.value;
        final s = c.sync.value;
        final now = c.now();
        final gap = s?.clockGap(now);
        return ListView(
          key: const Key('syncList'),
          padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
          children: [
            const InvSectionTitle('On this device'),
            if (q.total == 0)
              const ReportInfo(key: Key('syncAllClear'), 'Everything on this device has reached the server.', icon: Icons.cloud_done_outlined)
            else
              ReportInfo(key: const Key('syncPending'), '${q.total} record${q.total == 1 ? '' : 's'} still on this device. They upload by themselves when online.', warn: true),
            ReportRow(key: const Key('queueSales'), title: 'Sales waiting', value: '${q.sales}', detail: q.salesFailed > 0 ? '${q.salesFailed} need attention' : null),
            ReportRow(key: const Key('queueCash'), title: 'Cash records waiting', value: '${q.cash}', detail: q.cashFailed > 0 ? '${q.cashFailed} need attention' : null),
            ReportRow(key: const Key('queueTeam'), title: 'Clock punches waiting', value: '${q.team}'),
            const InvSectionTitle('Server'),
            if (!reportsOnlineRx().value)
              const ReportInfo('Offline: the server status shows when the connection is back.', warn: true)
            else if (c.syncLoading.value && s == null)
              const Padding(padding: EdgeInsets.all(Space.s4), child: Center(child: CircularProgressIndicator(key: Key('syncLoading'))))
            else if (c.syncError.value != null && s == null)
              InvErrorState(message: c.syncError.value!, onRetry: c.loadSync)
            else if (s != null) ...[
              if (gap != null && gap.inMinutes.abs() >= 5)
                ReportInfo(
                  key: const Key('syncClockGap'),
                  'This device\'s clock is ${gap.inMinutes.abs()} min ${gap.isNegative ? 'behind' : 'ahead of'} the server. Set the time automatically, or offline sales get wrong times.',
                  warn: true,
                ),
              ReportRow(
                key: const Key('syncSeal'),
                title: 'Last audit seal',
                subtitle: s.lastSealDay == null ? 'Days are sealed the night after' : '${storeDayLabel(s.lastSealDay!)} · ${s.lastSealRecords} records',
                value: _ago(s.lastSealAt, now),
              ),
              if (s.timeZone != null) ReportRow(title: 'Store time zone', value: s.timeZone!),
              InvSectionTitle('Devices · ${s.devices.length}'),
              for (final d in s.devices)
                ReportRow(
                  key: Key('syncDevice_${d.id}'),
                  title: d.name ?? 'Till',
                  subtitle: [if (d.platform != null) d.platform!, if (d.appVersion != null) 'v${d.appVersion}'].join(' · '),
                  value: _ago(d.lastSeenAt, now),
                ),
              if (s.devices.isEmpty) Text('No registered devices.', style: t.bodySmall.copyWith(color: p.textSecondary)),
            ],
          ],
        );
      }),
    );
  }
}


/// G5.6: upload / replace / remove the receipt logo (owner), with what goes wrong said in place.
class _LogoSection extends StatelessWidget {
  const _LogoSection({required this.c, required this.edit});
  final StoreSettingsController c;
  final bool edit;

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2048, imageQuality: 95);
    if (x != null) await c.uploadLogo(File(x.path));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final has = c.settings.value?.receiptLogoUrl != null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            has ? 'Printed in black and white (dithered) at the top of the receipt when "Store logo" is on. The preview shows the exact dots.' : 'No logo yet. Upload a square or wide logo (JPEG, PNG or WebP, up to 2 MB). Dark on a light background prints best.',
            key: const Key('logoHint'),
            style: context.type.caption.copyWith(color: p.textSecondary),
          ),
          if (c.logoError.value != null) Padding(padding: const EdgeInsets.only(top: Space.s2), child: Text(c.logoError.value!, key: const Key('logoError'), style: context.type.body.copyWith(color: p.danger))),
          if (edit)
            Padding(
              padding: const EdgeInsets.only(top: Space.s2),
              child: Row(children: [
                Expanded(child: OutlinedButton.icon(key: const Key('logoUpload'), onPressed: c.logoBusy.value ? null : _pick, icon: const Icon(Icons.upload_rounded), label: Text(has ? 'Replace logo' : 'Upload logo'))),
                if (has) ...[
                  const SizedBox(width: Space.s2),
                  Expanded(child: OutlinedButton.icon(key: const Key('logoRemove'), onPressed: c.logoBusy.value ? null : c.removeLogo, icon: const Icon(Icons.delete_outline_rounded), label: const Text('Remove'))),
                ],
              ]),
            ),
        ],
      );
    });
  }
}

/// G5.6: draws a [LogoBitmap] dot for dot (what the thermal printer will print).
class LogoBitmapImage extends StatefulWidget {
  const LogoBitmapImage({super.key, required this.bitmap, required this.width});
  final LogoBitmap bitmap;
  final double width;
  @override
  State<LogoBitmapImage> createState() => _LogoBitmapImageState();
}

class _LogoBitmapImageState extends State<LogoBitmapImage> {
  ui.Image? _img;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(LogoBitmapImage old) {
    super.didUpdateWidget(old);
    if (!identical(old.bitmap, widget.bitmap)) _decode();
  }

  void _decode() {
    final b = widget.bitmap;
    ui.decodeImageFromPixels(b.toRgba(), b.width, b.height, ui.PixelFormat.rgba8888, (img) {
      if (!mounted) return img.dispose();
      setState(() {
        _img?.dispose();
        _img = img;
      });
    });
  }

  @override
  void dispose() {
    _img?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bitmap;
    final h = widget.width * b.height / b.width;
    return SizedBox(width: widget.width, height: h, child: _img == null ? const SizedBox.shrink() : RawImage(image: _img, fit: BoxFit.contain, filterQuality: FilterQuality.none));
  }
}
