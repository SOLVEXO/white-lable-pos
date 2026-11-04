import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_login/controllers/pos_login_controller.dart';
import 'package:solvexo_pos/config/app_brand.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Owner sign-in: email/password or Google (both as role 'seller' — see
/// [PosLoginController]). Tablet / landscape: brand panel + form side by side;
/// phone: one column. Apple sign-in is not offered here (it isn't today).
class PosLoginView extends StatelessWidget {
  const PosLoginView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<PosLoginController>();
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      body: Obx(() {
        // A saved session is being checked (see PosLoginController._restoreSession) — don't flash the form for a
        // returning seller who's about to be routed straight past it.
        if (c.isCheckingSession.value) {
          return Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: p.accent,
              ),
            ),
          );
        }
        return LayoutBuilder(
          builder: (context, box) {
            final split = box.maxWidth >= 840;
            final form = _FormPane(c: c, showLogo: !split);
            if (!split) return SafeArea(child: form);
            return Row(
              children: [
                const Expanded(
                  flex: 5,
                  child: BrandPanel(
                    title: AppBrand.posName,
                    tagline: 'Fast · Reliable · Simple',
                    points: [
                      'Ring up a sale in seconds',
                      'Keeps selling offline, syncs when you are back',
                      'Every register and store in one place',
                    ],
                  ),
                ),
                Expanded(flex: 6, child: SafeArea(child: form)),
              ],
            );
          },
        );
      }),
    );
  }
}

class _FormPane extends StatelessWidget {
  const _FormPane({required this.c, required this.showLogo});
  final PosLoginController c;
  final bool showLogo;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s6,
          vertical: Space.s6,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight - Space.s12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: _LoginForm(c: c, showLogo: showLogo),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginForm extends StatefulWidget {
  const _LoginForm({required this.c, required this.showLogo});
  final PosLoginController c;
  final bool showLogo;

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _passwordFocus = FocusNode();
  String? _emailError;
  String? _passwordError;
  bool _attempted = false;

  PosLoginController get c => widget.c;

  @override
  void dispose() {
    _passwordFocus.dispose();
    super.dispose();
  }

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool _validate() {
    final email = c.emailController.text.trim();
    final pw = c.passwordController.text;
    setState(() {
      _emailError = email.isEmpty
          ? 'Enter your email'
          : (_emailRe.hasMatch(email) ? null : 'Enter a valid email address');
      _passwordError = pw.isEmpty ? 'Enter your password' : null;
    });
    return _emailError == null && _passwordError == null;
  }

  void _submit() {
    if (c.isBusy) return;
    _attempted = true;
    if (_validate()) c.loginWithEmail();
  }

  void _onChanged() {
    if (_attempted) _validate();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showLogo) ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: BrandLogo(size: 72),
            ),
            const SizedBox(height: Space.s6),
          ],
          Semantics(
            header: true,
            child: Text(
              'Sign in',
              style: t.display.copyWith(color: p.textPrimary),
            ),
          ),
          const SizedBox(height: Space.s2),
          Text(
            'Use your store owner account to continue.',
            style: t.body.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: Space.s8),
          AppTextField(
            label: 'Email',
            controller: c.emailController,
            prefixIcon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email, AutofillHints.username],
            errorText: _emailError,
            onChanged: (_) => _onChanged(),
            onSubmitted: (_) => _passwordFocus.requestFocus(),
          ),
          const SizedBox(height: Space.s4),
          AppTextField(
            label: 'Password',
            controller: c.passwordController,
            focusNode: _passwordFocus,
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: true,
            showObscureToggle: true,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            errorText: _passwordError,
            onChanged: (_) => _onChanged(),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: Space.s6),
          Obx(
            () => AppButton(
              label: 'Sign in',
              size: AppButtonSize.lg,
              loading: c.isEmailLoading.value,
              onPressed: c.isBusy && !c.isEmailLoading.value ? null : _submit,
            ),
          ),
          const SizedBox(height: Space.s5),
          Row(
            children: [
              Expanded(child: Divider(color: p.border)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.s3),
                child: Text(
                  'or',
                  style: t.caption.copyWith(color: p.textMuted),
                ),
              ),
              Expanded(child: Divider(color: p.border)),
            ],
          ),
          const SizedBox(height: Space.s5),
          Obx(
            () => GoogleSignInButton(
              loading: c.isGoogleLoading.value,
              onPressed: c.isBusy && !c.isGoogleLoading.value
                  ? null
                  : c.continueWithGoogle,
            ),
          ),
          const SizedBox(height: Space.s6),
          Text(
            'New store owners: signing up with Google creates your account automatically.',
            textAlign: TextAlign.center,
            style: t.caption.copyWith(color: p.textMuted),
          ),
        ],
      ),
    );
  }
}
