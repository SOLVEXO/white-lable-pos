import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// One manager approval for one action (a custom item above the limit, a card-slip variance at shift close…). The manager types
/// their email and PIN; the server checks both and the role, and answers with a signed token that is used for THIS action only —
/// it never replaces the signed-in cashier's own session. Returns the token, or null when cancelled.
abstract final class ManagerApproval {
  static Future<String?> request({required String reason, PosRepository? repository}) {
    return AppBottomSheet.showGet<String>(
      ManagerApprovalSheet(reason: reason, repository: repository ?? PosRepository()),
      title: 'Manager approval',
    );
  }
}

class ManagerApprovalSheet extends StatefulWidget {
  const ManagerApprovalSheet({super.key, required this.reason, required this.repository});
  final String reason;
  final PosRepository repository;

  @override
  State<ManagerApprovalSheet> createState() => _ManagerApprovalSheetState();
}

class _ManagerApprovalSheetState extends State<ManagerApprovalSheet> {
  static const _pinLength = 4;
  final _email = TextEditingController();
  String _pin = '';
  String? _error;
  bool _busy = false;
  int _errorTick = 0;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _digit(String d) {
    if (_busy || _pin.length >= _pinLength) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length == _pinLength) _submit();
  }

  void _back() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    if (_busy) return; // double-submit protection
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() {
        _error = 'Enter the manager\'s email first.';
        _pin = '';
        _errorTick++;
      });
      return;
    }
    setState(() => _busy = true);
    final storeId = await AppPreferences.getStoreId() ?? '';
    final res = await widget.repository.pinLogin(storeId: storeId, email: email, pin: _pin);
    if (!mounted) return;
    if (res.success && res.employee != null && res.employee!.role == 'manager' && res.employeeToken != null) {
      Get.back(result: res.employeeToken);
      return;
    }
    setState(() {
      _busy = false;
      _pin = '';
      _errorTick++;
      _error = res.success ? 'That person is not a manager.' : (res.message ?? 'Wrong email or PIN.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.reason, style: context.type.body.copyWith(color: p.textSecondary)),
        const SizedBox(height: Space.s4),
        AppTextField(
          key: const Key('approverEmail'),
          label: 'Manager email',
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          enabled: !_busy,
        ),
        const SizedBox(height: Space.s4),
        Center(child: PinDots(length: _pinLength, filled: _pin.length, errorTick: _errorTick, hasError: _error != null)),
        if (_error != null) ...[
          const SizedBox(height: Space.s2),
          Text(_error!, key: const Key('approverError'), textAlign: TextAlign.center, style: context.type.caption.copyWith(color: p.danger)),
        ],
        const SizedBox(height: Space.s3),
        PinPad(onDigit: _digit, onBackspace: _back, onClear: () => setState(() => _pin = ''), enabled: !_busy),
        const SizedBox(height: Space.s3),
        AppButton(key: const Key('approverCancel'), label: 'Cancel', variant: AppButtonVariant.secondary, onPressed: _busy ? null : () => Get.back()),
      ],
    );
  }
}
