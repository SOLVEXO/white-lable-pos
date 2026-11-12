import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_connectors_models.dart';
import 'package:solvexo_pos/app/modules/pos_integrations/controllers/pos_integrations_controller.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// G5.7 — Owner → Integrations. Each connection says plainly whether it can work yet; nothing provider-dependent is on until switched on.
class PosIntegrationsView extends StatelessWidget {
  PosIntegrationsView({super.key, PosIntegrationsController? controller}) : c = controller ?? Get.put(PosIntegrationsController());
  final PosIntegrationsController c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(title: const Text('Integrations'), backgroundColor: p.background, foregroundColor: p.textPrimary, elevation: 0),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Obx(() {
              final s = c.status.value;
              if (c.loading.value && s == null) return const Center(child: CircularProgressIndicator(key: Key('intLoading')));
              if (s == null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.s5),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.error_outline_rounded, size: 40, color: p.textMuted),
                      const SizedBox(height: Space.s3),
                      Text(c.error.value ?? 'Could not load the integrations.', key: const Key('intError'), textAlign: TextAlign.center, style: context.type.body.copyWith(color: p.textSecondary)),
                      const SizedBox(height: Space.s4),
                      AppButton(key: const Key('intReload'), label: 'Reload', expand: false, onPressed: c.load),
                    ]),
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: c.load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
                  children: [
                    if (c.error.value != null) _Banner(key: const Key('intSaveError'), text: c.error.value!, danger: true),
                    if (c.notice.value != null) _Banner(key: const Key('intNotice'), text: c.notice.value!),
                    const SectionHeader('Receipts'),
                    _FlagTile(c: c, flag: 'emailReceipts', icon: Icons.email_outlined, title: 'E-mail receipts', text: 'Send the receipt link by e-mail from the sale (link only, with the customer\'s consent).', on: s.flag('emailReceipts')),
                    _FlagTile(c: c, flag: 'smsReceipts', icon: Icons.sms_outlined, title: 'SMS receipts', text: 'Send the receipt link by SMS through your store\'s SMS gateway.', on: s.flag('smsReceipts')),
                    const SectionHeader('Tax'),
                    _FlagTile(
                      c: c,
                      flag: 'fiscal',
                      icon: Icons.account_balance_outlined,
                      title: 'FBR fiscal invoices',
                      text: s.fiscal.configured
                          ? (s.fiscal.testMode ? 'Test mode: invoices get a test fiscal number. Not for real tax reporting.' : 'Invoices and credit notes are sent to the tax authority.')
                          : 'Not available yet: the FBR connection is waiting for the route decision and documents. Receipts would show "Fiscal pending".',
                      on: s.fiscalOn,
                      badge: s.fiscal.testMode ? 'Test mode' : (s.fiscal.configured ? null : 'Not available'),
                    ),
                    const SectionHeader('Payments'),
                    AppCard(
                      key: const Key('intPayments'),
                      radius: Radii.rMd,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.payments_outlined),
                        title: const Text('Payments setup'),
                        subtitle: Text(s.raast?.enabled == true ? 'Raast QR is on' : 'Raast QR, card on a bank terminal'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Get.toNamed(Routes.posPaymentsSetup),
                      ),
                    ),
                    const SectionHeader('Accounting export'),
                    _ExportCard(c: c),
                    const SectionHeader('API keys'),
                    _ApiKeys(c: c),
                  ],
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.text, this.danger = false});
  final String text;
  final bool danger;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: Space.s3),
      padding: const EdgeInsets.all(Space.s3),
      decoration: BoxDecoration(color: danger ? p.dangerSoft : p.successSoft, borderRadius: Radii.rMd),
      child: Text(text, style: context.type.body.copyWith(color: danger ? p.dangerFg : p.successFg)),
    );
  }
}

class _FlagTile extends StatelessWidget {
  const _FlagTile({required this.c, required this.flag, required this.icon, required this.title, required this.text, required this.on, this.badge});
  final PosIntegrationsController c;
  final String flag, title, text;
  final IconData icon;
  final bool on;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s3),
      child: AppCard(
        key: Key('intFlag_$flag'),
        radius: Radii.rMd,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, color: p.textPrimary)),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(title, style: context.type.subtitle)),
                if (badge != null) ...[const SizedBox(width: Space.s2), StatusBadge(badge!, tone: badge == 'Test mode' ? StatusTone.warning : StatusTone.neutral)],
              ]),
              const SizedBox(height: Space.s1),
              Text(text, style: context.type.bodySmall.copyWith(color: p.textSecondary)),
            ]),
          ),
          c.saving.value == flag
              ? const Padding(padding: EdgeInsets.all(Space.s2), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
              : Switch.adaptive(key: Key('intSwitch_$flag'), value: on, onChanged: c.saving.value != null ? null : (v) => c.setFlag(flag, v)),
        ]),
      ),
    );
  }
}

class _ExportCard extends StatelessWidget {
  const _ExportCard({required this.c});
  final PosIntegrationsController c;

  Future<void> _pick(BuildContext context, bool start) async {
    final cur = start ? c.exportFrom.value : c.exportTo.value;
    final d = await showDatePicker(context: context, initialDate: cur, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1)));
    if (d == null) return;
    if (start) {
      c.exportFrom.value = d;
    } else {
      c.exportTo.value = d;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final f = DateFormat('d MMM yyyy');
    return AppCard(
      key: const Key('intExport'),
      radius: Radii.rMd,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Invoices, credit notes, expenses and supplier payments as a CSV for your accountant, by store day. Amounts in minor units with the currency, plus formatted amounts. Cost columns only when you may see cost.', style: context.type.bodySmall.copyWith(color: p.textSecondary)),
        const SizedBox(height: Space.s3),
        Row(children: [
          Expanded(child: OutlinedButton(key: const Key('intExportFrom'), onPressed: () => _pick(context, true), child: Text('From ${f.format(c.exportFrom.value)}'))),
          const SizedBox(width: Space.s2),
          Expanded(child: OutlinedButton(key: const Key('intExportTo'), onPressed: () => _pick(context, false), child: Text('To ${f.format(c.exportTo.value)}'))),
        ]),
        const SizedBox(height: Space.s3),
        AppButton(key: const Key('intExportGo'), label: 'Export CSV', icon: Icons.download_rounded, loading: c.exporting.value, onPressed: c.exportAccounting),
      ]),
    );
  }
}

class _ApiKeys extends StatelessWidget {
  const _ApiKeys({required this.c});
  final PosIntegrationsController c;

  Future<void> _create(BuildContext context) async {
    final ks = c.keys.value;
    final scopes = ks?.scopes.isNotEmpty == true ? ks!.scopes : const ['sales:read', 'inventory:read', 'accounting:read'];
    final req = await showModalBottomSheet<({String name, List<String> scopes, int days})>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => _NewKeySheet(scopes: scopes));
    if (req == null) return;
    final key = await c.createKey(name: req.name, scopes: req.scopes, days: req.days);
    if (key == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Copy your key now'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('This is the only time the full key is shown. Store it somewhere safe. If you lose it, revoke it and make a new one.'),
          const SizedBox(height: Space.s3),
          SelectableText(key, key: const Key('apiKeyValue'), style: const TextStyle(fontFamily: 'Courier', fontSize: 13)),
        ]),
        actions: [
          TextButton(key: const Key('apiKeyCopy'), onPressed: () => Clipboard.setData(ClipboardData(text: key)), child: const Text('Copy')),
          FilledButton(key: const Key('apiKeyDone'), onPressed: () => Navigator.of(ctx).pop(), child: const Text('I have saved it')),
        ],
      ),
    );
  }

  Future<void> _revoke(BuildContext context, StoreApiKey k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Revoke "${k.name}"?'),
        content: const Text('Anything using this key stops working at once. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(key: const Key('apiKeyRevokeConfirm'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Revoke')),
        ],
      ),
    );
    if (ok == true) await c.revokeKey(k);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ks = c.keys.value;
    final f = DateFormat('d MMM yyyy');
    return AppCard(
      key: const Key('intApiKeys'),
      radius: Radii.rMd,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Read-only keys for your own systems (accounting, spreadsheets). Keys never change anything and never see cost. Every use is logged. Limit: ${ks?.ratePerMinute ?? 60} requests a minute per key.', style: context.type.bodySmall.copyWith(color: p.textSecondary)),
        if (ks == null)
          Padding(padding: const EdgeInsets.only(top: Space.s3), child: Text('Only the owner can see the keys.', key: const Key('apiKeysHidden'), style: context.type.body.copyWith(color: p.textMuted)))
        else ...[
          for (final k in ks.keys)
            ListTile(
              key: Key('apiKey_${k.id}'),
              contentPadding: EdgeInsets.zero,
              title: Row(children: [Flexible(child: Text(k.name)), const SizedBox(width: Space.s2), StatusBadge(k.active ? 'Active' : (k.status == 'revoked' ? 'Revoked' : 'Expired'), tone: k.active ? StatusTone.success : StatusTone.neutral)]),
              subtitle: Text('sxk_${k.prefix}_…  ·  ${k.scopes.map(StoreApiKey.scopeLabel).join(', ')}\n${k.expiresAt != null ? 'Expires ${f.format(k.expiresAt!.toLocal())}' : ''}${k.lastUsedAt != null ? '  ·  Last used ${f.format(k.lastUsedAt!.toLocal())}' : '  ·  Never used'}'),
              isThreeLine: true,
              trailing: k.active ? IconButton(key: Key('apiKeyRevoke_${k.id}'), tooltip: 'Revoke', icon: const Icon(Icons.block_rounded), onPressed: c.saving.value != null ? null : () => _revoke(context, k)) : null,
            ),
          const SizedBox(height: Space.s2),
          AppButton(key: const Key('apiKeyNew'), label: 'New API key', icon: Icons.key_rounded, variant: AppButtonVariant.secondary, loading: c.saving.value == 'apiKey', onPressed: c.saving.value != null ? null : () => _create(context)),
        ],
      ]),
    );
  }
}

class _NewKeySheet extends StatefulWidget {
  const _NewKeySheet({required this.scopes});
  final List<String> scopes;
  @override
  State<_NewKeySheet> createState() => _NewKeySheetState();
}

class _NewKeySheetState extends State<_NewKeySheet> {
  final _name = TextEditingController();
  late final Set<String> _scopes = {widget.scopes.first};
  int _days = 90;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _name.text.trim().isNotEmpty && _scopes.isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, MediaQuery.of(context).viewInsets.bottom + Space.s4),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('New API key', style: context.type.subtitle),
        const SizedBox(height: Space.s3),
        AppTextField(key: const Key('apiKeyName'), label: 'Name (what it is for)', controller: _name, onChanged: (_) => setState(() {})),
        const SizedBox(height: Space.s2),
        for (final s in widget.scopes)
          CheckboxListTile(
            key: Key('apiKeyScope_$s'),
            contentPadding: EdgeInsets.zero,
            value: _scopes.contains(s),
            title: Text(StoreApiKey.scopeLabel(s)),
            onChanged: (v) => setState(() => v == true ? _scopes.add(s) : _scopes.remove(s)),
          ),
        const SizedBox(height: Space.s2),
        SegmentedButton<int>(
          key: const Key('apiKeyDays'),
          segments: const [ButtonSegment(value: 30, label: Text('30 days')), ButtonSegment(value: 90, label: Text('90 days')), ButtonSegment(value: 365, label: Text('1 year'))],
          selected: {_days},
          onSelectionChanged: (v) => setState(() => _days = v.first),
        ),
        const SizedBox(height: Space.s4),
        AppButton(key: const Key('apiKeyCreate'), label: 'Create key', onPressed: ok ? () => Navigator.of(context).pop((name: _name.text.trim(), scopes: [for (final s in widget.scopes) if (_scopes.contains(s)) s], days: _days)) : null),
      ]),
    );
  }
}
