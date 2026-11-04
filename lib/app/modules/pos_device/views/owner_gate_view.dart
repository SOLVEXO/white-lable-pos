import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/repositories/auth_repository.dart';
import 'package:solvexo_pos/app/data/services/owner_session.dart';
import 'package:solvexo_pos/core/design/design.dart';
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
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        title: const Text('Owner access'),
        leading: BackButton(onPressed: () => Get.back(result: false)),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(Space.s6),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - Space.s12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: AutofillGroup(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const GateHeader(
                          icon: Icons.admin_panel_settings_outlined,
                          title: 'This area is for the store owner.',
                        ),
                        const SizedBox(height: Space.s3),
                        Text(
                          'Enter the password of $_email to continue. Access ends after ${OwnerSession.ttl.inMinutes} minutes of inactivity or when the till locks.',
                          textAlign: TextAlign.center,
                          style: context.type.body.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                        const SizedBox(height: Space.s6),
                        AppTextField(
                          key: const Key('ownerGatePassword'),
                          label: 'Owner password',
                          controller: _password,
                          prefixIcon: Icons.lock_outline_rounded,
                          obscureText: true,
                          showObscureToggle: true,
                          autofocus: true,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          errorText: _error,
                          onSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: Space.s5),
                        AppButton(
                          key: const Key('ownerGateContinue'),
                          label: 'Continue',
                          size: AppButtonSize.lg,
                          loading: _busy,
                          onPressed: _submit,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
