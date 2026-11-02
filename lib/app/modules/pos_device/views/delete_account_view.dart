import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/data/repositories/account_repository.dart';
import 'package:solvexo_pos/app/data/services/owner_session.dart';
import 'package:solvexo_pos/app/data/services/pos_device_service.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/unsynced_guard.dart';

/// Owner-only "Delete account". Reached through the owner password gate; asks for the password AGAIN and an explicit
/// confirmation, and states plainly what happens. Never offered while sales are unsynced (they would be lost).
class DeleteAccountView extends StatefulWidget {
  const DeleteAccountView({super.key, AccountRepository? repository, this.skipUnsyncedGuard = false}) : _repo = repository;
  final AccountRepository? _repo;

  /// Tests only: the real guard talks to the sync service.
  final bool skipUnsyncedGuard;

  static const int graceDays = 30;

  @override
  State<DeleteAccountView> createState() => _DeleteAccountViewState();
}

class _DeleteAccountViewState extends State<DeleteAccountView> {
  late final AccountRepository _repo = widget._repo ?? AccountRepository();
  final _password = TextEditingController();
  bool _confirmed = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_busy || !_confirmed || _password.text.isEmpty) return;
    if (!widget.skipUnsyncedGuard && await UnsyncedGuard.blockIfUnsynced(action: 'delete the account')) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _repo.requestDeletion(_password.text);
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
          AlertDialog(
            title: const Text('Account scheduled for deletion'),
            content: Text('Your account and stores are now switched off. Your personal data will be erased$when. To change your mind, sign in on the web before then and cancel the deletion.'),
            actions: [TextButton(onPressed: () => Get.back(), child: const Text('OK'))],
          ),
          barrierDismissible: false,
        );
        Get.offAllNamed(Routes.posLogin);
        return;
      case DeletionOutcome.wrongPassword:
        setState(() => _error = 'That password is not correct.');
      case DeletionOutcome.openSessions:
        setState(() => _error = 'Close every open register shift first (Settings → Close Shift), then try again.');
      case DeletionOutcome.needsWeb:
        setState(() => _error = 'This account signs in with Google and has no password to confirm with. Delete it from your account settings on the web instead.');
      case DeletionOutcome.failed:
        setState(() => _error = r.message ?? "Couldn't reach the server. Nothing was deleted — try again.");
    }
    setState(() => _busy = false);
  }

  Widget _bullet(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('•  '), Expanded(child: Text(t))]));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('This permanently removes your Solvexo owner account.', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          const Text('What happens'),
          const SizedBox(height: 8),
          _bullet('You are signed out everywhere, and every POS device and staff PIN session stops working immediately.'),
          _bullet('Your stores and storefronts are switched off right away.'),
          _bullet('After ${DeleteAccountView.graceDays} days your name, email, phone, password, staff names/PINs and customer names are erased. You can cancel by signing in on the web before then.'),
          _bullet('Sales, payments, refunds and tax records are kept as the law requires, with the people in them removed.'),
          _bullet('Your POS plan is not refunded.'),
          const SizedBox(height: 16),
          TextField(key: const Key('deletePassword'), controller: _password, obscureText: true, onChanged: (_) => setState(() {}), decoration: InputDecoration(border: const OutlineInputBorder(), labelText: 'Enter your owner password to confirm', errorText: _error, errorMaxLines: 4)),
          CheckboxListTile(
            key: const Key('deleteConfirm'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _confirmed,
            onChanged: (v) => setState(() => _confirmed = v ?? false),
            title: const Text('I understand my account and stores will be switched off and my personal data erased.'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('deleteSubmit'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: _busy || !_confirmed || _password.text.isEmpty ? null : _delete,
            child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Delete my account'),
          ),
        ]),
      ),
    );
  }
}
