import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/data/models/common_models/social_login_model.dart';
import 'package:solvexo_pos/app/data/repositories/account_repository.dart';
import 'package:solvexo_pos/app/data/services/owner_session.dart';
import 'package:solvexo_pos/app/data/services/pos_device_service.dart';
import 'package:solvexo_pos/app/data/services/social_auth_service.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/unsynced_guard.dart';

/// Owner-only "Delete account". Reached through the owner password gate; asks for the password AGAIN and an explicit
/// confirmation, and states plainly what happens. Never offered while sales are unsynced (they would be lost).
class DeleteAccountView extends StatefulWidget {
  const DeleteAccountView({super.key, AccountRepository? repository, SocialAuthService? socialAuth, this.skipUnsyncedGuard = false})
      : _repo = repository,
        _social = socialAuth;
  final AccountRepository? _repo;
  final SocialAuthService? _social;

  /// Tests only: the real guard talks to the sync service.
  final bool skipUnsyncedGuard;

  static const int graceDays = 30;

  @override
  State<DeleteAccountView> createState() => _DeleteAccountViewState();
}

class _DeleteAccountViewState extends State<DeleteAccountView> {
  late final AccountRepository _repo = widget._repo ?? AccountRepository();
  late final SocialAuthService _social = widget._social ?? SocialAuthService();
  final _password = TextEditingController();
  DeletionAuthMethods? _methods; // null while loading
  bool _confirmed = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo.authMethods().then((m) {
      if (mounted) setState(() => _methods = m);
    });
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  /// Password path.
  Future<void> _delete() => _submit(() async => _repo.requestDeletion(password: _password.text), needsPassword: true);

  /// Social path: a FRESH Google/Apple sign-in is the re-authentication (no password exists, or the owner prefers it).
  Future<void> _deleteWithProvider(String provider) => _submit(() async {
        SocialLoginModel? id;
        try {
          id = provider == 'apple' ? await _social.signInWithApple() : await _social.signInWithGoogle();
        } catch (_) {
          id = null;
        }
        if (id == null) return (outcome: DeletionOutcome.failed, scheduledFor: null, message: 'Sign-in was cancelled or failed. Nothing was deleted.');
        return _repo.requestDeletion(reauth: id);
      });

  Future<void> _submit(Future<({DeletionOutcome outcome, DateTime? scheduledFor, String? message})> Function() call, {bool needsPassword = false}) async {
    if (_busy || !_confirmed || (needsPassword && _password.text.isEmpty)) return;
    if (!widget.skipUnsyncedGuard && await UnsyncedGuard.blockIfUnsynced(action: 'delete the account')) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await call();
    if (!mounted) return;
    switch (r.outcome) {
      case DeletionOutcome.requested:
        OwnerSession.end();
        if (Get.isRegistered<PosDeviceService>()) {
          await Get.find<PosDeviceService>().reset();
        } else {
          await AppPreferences.clearPreference(wipeQueueKey: true);
        }
        final when = r.scheduledFor == null ? '' : ' on ${DateFormat('MMM d, y').format(r.scheduledFor!.toLocal())}';
        await Get.dialog<void>(
          Center(
            child: Padding(
              padding: const EdgeInsets.all(Space.s6),
              child: AppDialogCard(
                title: 'Account scheduled for deletion',
                message: 'Your account and stores are now switched off. Your personal data will be erased$when. To change your mind, sign in on the web before then and cancel the deletion.',
                actions: [AppButton(label: 'OK', onPressed: () => Get.back())],
              ),
            ),
          ),
          barrierDismissible: false,
        );
        Get.offAllNamed(Routes.posLogin);
        return;
      case DeletionOutcome.wrongPassword:
        setState(() => _error = 'That password is not correct.');
      case DeletionOutcome.openSessions:
        setState(() => _error = 'Close every open register shift first (Settings → Close Shift), then try again.');
      case DeletionOutcome.wrongIdentity:
        setState(() => _error = 'That sign-in does not match this owner account. Use the same Google/Apple account you registered with.');
      case DeletionOutcome.needsWeb:
        setState(() => _error = 'This account has no password to confirm with. Re-authenticate with Google or Apple instead, or delete it from your account settings on the web.');
      case DeletionOutcome.failed:
        setState(() => _error = r.message ?? "Couldn't reach the server. Nothing was deleted — try again.");
    }
    setState(() => _busy = false);
  }

  Widget _bullet(BuildContext context, String t) {
    final style = context.type.body.copyWith(color: context.palette.textPrimary);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('•  ', style: style), Expanded(child: Text(t, style: style))]),
    );
  }

  List<Widget> _authSection(BuildContext context) {
    final p = context.palette;
    final m = _methods;
    if (m == null) return [Padding(padding: const EdgeInsets.symmetric(vertical: Space.s4), child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: p.accent)))];
    return [
      if (m.hasPassword)
        AppTextField(key: const Key('deletePassword'), controller: _password, obscureText: true, onChanged: (_) => setState(() {}), label: 'Enter your owner password to confirm')
      else
        Text(
          m.canUseApple ? 'You sign in with Apple, so you will confirm with Apple.' : m.canUseGoogle ? 'You sign in with Google, so you will confirm with Google.' : 'This account has no password and no supported sign-in on this device.',
          key: const Key('deleteNoPassword'),
          style: context.type.body.copyWith(color: p.textPrimary),
        ),
      // the error sits under the field (not as the field's errorText) so long messages wrap instead of being cut off
      if (_error != null) Padding(padding: const EdgeInsets.only(top: Space.s2), child: Text(_error!, style: context.type.bodySmall.copyWith(color: p.dangerFg))),
    ];
  }

  bool _canUse(String provider) => provider == 'apple' ? SocialAuthService.appleSupported : true;

  List<Widget> _actions(BuildContext context) {
    final m = _methods;
    if (m == null) return const [];
    final active = !_busy && _confirmed;
    return [
      const SizedBox(height: Space.s2),
      if (m.hasPassword)
        AppButton(
          key: const Key('deleteSubmit'),
          label: 'Delete my account',
          variant: AppButtonVariant.danger,
          expand: true,
          loading: _busy,
          onPressed: active && _password.text.isNotEmpty ? _delete : null,
        ),
      if (m.hasProvider && _canUse(m.authProvider!)) ...[
        if (m.hasPassword) const SizedBox(height: Space.s3),
        AppButton(
          key: const Key('deleteWithProvider'),
          label: '${m.hasPassword ? 'Or re-authenticate' : 'Re-authenticate'} with ${m.canUseApple ? 'Apple' : 'Google'} and delete',
          variant: m.hasPassword ? AppButtonVariant.secondary : AppButtonVariant.danger,
          expand: true,
          loading: _busy && !m.hasPassword,
          onPressed: active ? () => _deleteWithProvider(m.authProvider!) : null,
        ),
      ],
      if (!m.hasPassword && m.hasProvider && !_canUse(m.authProvider!))
        Padding(
          padding: const EdgeInsets.only(top: Space.s2),
          child: Text('Apple sign-in is only available on iPhone/iPad. Use one, or delete your account from your account settings on the web.', style: context.type.bodySmall.copyWith(color: context.palette.textSecondary)),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return AppPage(
      title: 'Delete account',
      // a plain scroll view (not a lazy list) so the confirmation and the buttons always exist, even below the fold
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.s5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('This permanently removes your Solvexo owner account.', style: t.title.copyWith(color: p.textPrimary)),
        const SizedBox(height: Space.s3),
        Text('What happens', style: t.label.copyWith(color: p.textSecondary)),
        const SizedBox(height: Space.s2),
        _bullet(context, 'You are signed out everywhere, and every POS device and staff PIN session stops working immediately.'),
        _bullet(context, 'Your stores and storefronts are switched off right away.'),
        _bullet(context, 'After ${DeleteAccountView.graceDays} days your name, email, phone, password, staff names/PINs and customer names are erased. You can cancel by signing in on the web before then.'),
        _bullet(context, 'Sales, payments, refunds and tax records are kept as the law requires, with the people in them removed.'),
        _bullet(context, 'Your POS plan is not refunded.'),
        const SizedBox(height: Space.s4),
        ..._authSection(context),
        CheckboxListTile(
          key: const Key('deleteConfirm'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _confirmed,
          onChanged: (v) => setState(() => _confirmed = v ?? false),
          title: Text('I understand my account and stores will be switched off and my personal data erased.', style: t.body.copyWith(color: p.textPrimary)),
        ),
        const SizedBox(height: Space.s2),
        ..._actions(context),
        ]),
      ),
    );
  }
}
