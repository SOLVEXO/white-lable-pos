import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/repositories/auth_repository.dart';
import 'package:solvexo_pos/app/data/services/owner_session.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// Owner re-authentication. Shown before any owner-only screen/action on a registered device: the owner's password gives a
/// short-lived, in-memory session ([OwnerSession]); nothing is stored on the device.
class OwnerGateView extends StatefulWidget {
  const OwnerGateView({super.key, AuthRepository? authRepository}) : _auth = authRepository;
  final AuthRepository? _auth;

  @override
  State<OwnerGateView> createState() => _OwnerGateViewState();
}

class _OwnerGateViewState extends State<OwnerGateView> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  String _email = '';

  @override
  void initState() {
    super.initState();
    AppPreferences.getUserEmail().then((e) {
      if (mounted) setState(() => _email = e ?? '');
    });
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final token = await (widget._auth ?? AuthRepository()).verifyOwnerPassword(email: _email, password: _password.text);
    if (!mounted) return;
    if (token == null) {
      setState(() {
        _busy = false;
        _error = 'That password did not work.';
      });
      return;
    }
    OwnerSession.start(token);
    final next = (Get.arguments is Map) ? (Get.arguments as Map)['next'] as String? : null;
    if (next != null && next.isNotEmpty) {
      Get.offNamed(next);
    } else {
      Get.back(result: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Owner access'), leading: BackButton(onPressed: () => Get.back(result: false))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('This area is for the store owner.', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('Enter the password of $_email to continue. Access ends after ${OwnerSession.ttl.inMinutes} minutes of inactivity or when the till locks.',
                style: const TextStyle(color: AppColors.iosGrey)),
            const SizedBox(height: 20),
            TextField(
              key: const Key('ownerGatePassword'),
              controller: _password,
              obscureText: true,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(border: const OutlineInputBorder(), labelText: 'Owner password', errorText: _error),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('ownerGateContinue'),
                onPressed: _busy ? null : _submit,
                child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Continue'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
