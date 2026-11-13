import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_connectors_models.dart' show ConnectorUiStore;
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:url_launcher/url_launcher.dart';

/// `https://wa.me/<digits>?text=…` — WhatsApp's own click-to-chat link (digits only, with the country code; no "+").
Uri whatsAppUri(String phone, String text) =>
    Uri(scheme: 'https', host: 'wa.me', path: '/${phone.replaceAll(RegExp(r'[^0-9]'), '')}', query: 'text=${Uri.encodeComponent(text)}'); // built, not a URL literal: the only URL literal in lib/ is the API's (store-release guard)

/// G5.3 — send a receipt out of the app: the phone's share sheet, WhatsApp to the customer's number (wa.me; falls back to the share sheet), and e-mail / SMS
/// when the store has switched them on (the server sends only the store name, the total and the public link).
class SendReceiptSheet extends StatefulWidget {
  const SendReceiptSheet({super.key, required this.storeId, required this.saleId, required this.link, required this.message, this.customerPhone, this.customerEmail, this.repository, this.launcher, this.share});
  final String storeId, saleId, link, message;
  final String? customerPhone, customerEmail;
  final PosRepository? repository;
  final Future<bool> Function(Uri uri)? launcher;
  final Future<void> Function(ShareParams p)? share;

  static Future<void> open({required String storeId, required String saleId, required String link, required String storeName, required String total, String? customerPhone, String? customerEmail}) =>
      AppBottomSheet.showGet<void>(SendReceiptSheet(storeId: storeId, saleId: saleId, link: link, message: '$storeName: your receipt ($total) — $link', customerPhone: customerPhone, customerEmail: customerEmail), title: 'Send receipt');

  @override
  State<SendReceiptSheet> createState() => _SendReceiptSheetState();
}

class _SendReceiptSheetState extends State<SendReceiptSheet> {
  late final PosRepository _repo = widget.repository ?? PosRepository();
  ({bool email, bool sms})? _channels;
  late final _phone = TextEditingController(text: widget.customerPhone ?? '');
  late final _email = TextEditingController(text: widget.customerEmail ?? '');
  bool _given = false, _busy = false;
  String? _notice, _error;

  @override
  void initState() {
    super.initState();
    _repo.getReceiptChannels(widget.storeId).then((c) { if (mounted) setState(() => _channels = c ?? (email: false, sms: false)); });
  }

  @override
  void dispose() {
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _share() => (widget.share ?? (p) async => SharePlus.instance.share(p))(ShareParams(text: widget.message, subject: 'Your receipt'));

  Future<void> _whatsApp() async {
    final phone = _phone.text.trim();
    // G6.1: the server says how WhatsApp works (`connectors.ui.receipts.whatsapp.mode`): `api` → it sends it; otherwise the wa.me link from here
    if (ConnectorUiStore.current.whatsappMode == 'api') return _send('whatsapp');
    if (phone.replaceAll(RegExp(r'[^0-9]'), '').length < ConnectorUiStore.current.minPhoneDigits) return _share(); // no number → the share sheet
    final ok = await (widget.launcher ?? (u) => launchUrl(u, mode: LaunchMode.externalApplication))(whatsAppUri(phone, widget.message)).catchError((_) => false);
    if (!ok) await _share();
  }

  Future<void> _send(String channel) async {
    final typed = (channel == 'email' ? _email : _phone).text.trim();
    final onFile = channel == 'email' ? widget.customerEmail : widget.customerPhone;
    final other = typed.isNotEmpty && typed != onFile;
    if (other && !_given) return setState(() => _error = 'Tick that the customer gave this ${channel == 'email' ? 'e-mail' : 'number'} for their receipt.');
    setState(() { _busy = true; _error = null; _notice = null; });
    final r = await _repo.sendReceipt(widget.storeId, widget.saleId, channel: channel, to: typed.isEmpty ? null : typed, givenForSale: other);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.success) {
        _notice = switch (channel) { 'email' => 'E-mail sent.', 'whatsapp' => 'WhatsApp sent.', _ => 'SMS sent.' };
      } else if ((r.message ?? '').trim().isNotEmpty && r.code != null && r.code != 'NETWORK_ERROR') {
        _error = r.message!.trim(); // G6.1: the server's words first (a real provider's reasons need no app update)
      } else {
        _error = switch (r.code) {
          'CHANNEL_OFF' => channel == 'email' ? 'E-mail receipts are switched off for this store.' : 'SMS receipts are switched off for this store.',
          'RATE_LIMITED' => 'This receipt was sent too many times — try again later.',
          'RECIPIENT_INVALID' => 'That ${channel == 'email' ? 'e-mail address' : 'phone number'} does not look right.',
          'RECIPIENT_REQUIRED' => 'Enter the customer\'s ${channel == 'email' ? 'e-mail' : 'number'}.',
          'SEND_FAILED' => r.message ?? 'Could not send.',
          _ => r.message ?? 'Could not send.',
        };
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final ch = _channels;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(ConnectorUiStore.current.privacyNote, style: t.caption.copyWith(color: p.textMuted)),
        const SizedBox(height: Space.s3),
        AppButton(key: const Key('sendShare'), label: 'Share link', icon: Icons.ios_share_rounded, variant: AppButtonVariant.secondary, onPressed: _share),
        const SizedBox(height: Space.s3),
        AppTextField(key: const Key('sendPhone'), label: 'Customer phone (with country code)', controller: _phone, keyboardType: TextInputType.phone),
        const SizedBox(height: Space.s2),
        if (ConnectorUiStore.current.whatsappMode != 'off') AppButton(key: const Key('sendWhatsApp'), label: 'WhatsApp', icon: Icons.chat_outlined, loading: _busy && ConnectorUiStore.current.whatsappMode == 'api', onPressed: _whatsApp),
        if (ch?.sms == true) ...[
          const SizedBox(height: Space.s2),
          AppButton(key: const Key('sendSms'), label: 'Send by SMS', icon: Icons.sms_outlined, variant: AppButtonVariant.secondary, loading: _busy, onPressed: _busy ? null : () => _send('sms')),
        ],
        if (ch?.email == true) ...[
          const SizedBox(height: Space.s3),
          AppTextField(key: const Key('sendEmail'), label: 'Customer e-mail', controller: _email, keyboardType: TextInputType.emailAddress),
          const SizedBox(height: Space.s2),
          AppButton(key: const Key('sendEmailButton'), label: 'Send by e-mail', icon: Icons.mail_outline_rounded, variant: AppButtonVariant.secondary, loading: _busy, onPressed: _busy ? null : () => _send('email')),
        ],
        if (ch?.sms == true || ch?.email == true)
          CheckboxListTile(key: const Key('sendGiven'), contentPadding: EdgeInsets.zero, value: _given, onChanged: (v) => setState(() => _given = v ?? false), title: Text(ConnectorUiStore.current.consentText, style: t.body)),
        if (_notice != null) Text(_notice!, key: const Key('sendNotice'), style: t.body.copyWith(color: p.successFg)),
        if (_error != null) Text(_error!, key: const Key('sendError'), style: t.body.copyWith(color: p.danger)),
      ],
    );
  }
}
