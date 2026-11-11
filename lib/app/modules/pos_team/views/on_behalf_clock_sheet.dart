import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/clock_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// G5.4 — clock ANOTHER team member in or out. Pick the person and the action, then that person types their own PIN (their email is known), or a manager
/// types their email + PIN instead. The PIN is checked by the server (a PIN login that is NOT kept — the till's own session is untouched) and its token
/// approves this one clock event; the server checks it again and records who did it, for whom, and who approved. Online only.
class OnBehalfClockSheet extends StatefulWidget {
  const OnBehalfClockSheet({super.key, required this.controller, required this.repository, this.members});
  final TeamClockController controller;
  final PosRepository repository;
  final List<PosEmployeeModel>? members; // tests

  static Future<void> open(TeamClockController c, {PosRepository? repository}) async {
    if (c.isOffline) {
      c.actionError.value = 'Clocking someone else needs a connection — their PIN is checked by the server.';
      return;
    }
    await AppBottomSheet.showGet<void>(OnBehalfClockSheet(controller: c, repository: repository ?? PosRepository()), title: 'Clock someone else');
  }

  @override
  State<OnBehalfClockSheet> createState() => _OnBehalfClockSheetState();
}

class _OnBehalfClockSheetState extends State<OnBehalfClockSheet> {
  static const _pinLength = 4;
  List<PosEmployeeModel>? _members;
  PosEmployeeModel? _member;
  String _action = ClockAction.clockIn;
  bool _managerMode = false;
  final _managerEmail = TextEditingController();
  String _pin = '';
  String? _error;
  bool _busy = false;
  int _errorTick = 0;

  @override
  void initState() {
    super.initState();
    if (widget.members != null) {
      _members = widget.members;
    } else {
      widget.controller.teamMembers().then((m) {
        if (mounted) setState(() => _members = m);
      });
    }
  }

  @override
  void dispose() {
    _managerEmail.dispose();
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

  void _fail(String msg) => setState(() {
    _busy = false;
    _pin = '';
    _errorTick++;
    _error = msg;
  });

  Future<void> _submit() async {
    final m = _member;
    if (_busy || m == null) return;
    final email = _managerMode ? _managerEmail.text.trim() : m.email;
    if (email.isEmpty) return _fail(_managerMode ? 'Enter the manager\'s email first.' : '${m.name} has no email on file — use a manager\'s PIN.');
    setState(() => _busy = true);
    final storeId = await AppPreferences.getStoreId() ?? '';
    final res = await widget.repository.pinLogin(storeId: storeId, email: email, pin: _pin);
    if (!mounted) return;
    final ok = res.success && res.employeeToken != null && res.employee != null && (_managerMode ? res.employee!.role == 'manager' : res.employee!.id == m.id);
    if (!ok) return _fail(res.success ? (_managerMode ? 'That person is not a manager.' : 'That is not ${m.name}\'s PIN.') : (res.message ?? 'Wrong email or PIN.'));
    final err = await widget.controller.clockOnBehalf(member: m, action: _action, approverToken: res.employeeToken!);
    if (!mounted) return;
    if (err != null) return _fail(err);
    Get.back<void>();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final m = _member;
    if (m == null) {
      final list = _members;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Who are you clocking? They (or a manager) will enter a PIN next.', style: t.body.copyWith(color: p.textSecondary)),
          const SizedBox(height: Space.s3),
          if (list == null)
            const Center(child: Padding(padding: EdgeInsets.all(Space.s4), child: CircularProgressIndicator()))
          else if (list.isEmpty)
            Text('No other team members to clock.', key: const Key('onBehalfEmpty'), style: t.body.copyWith(color: p.textMuted))
          else
            for (final e in list)
              ListTile(
                key: Key('onBehalf_${e.id}'),
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(backgroundColor: p.fill, child: Text(e.name.isEmpty ? '?' : e.name[0].toUpperCase(), style: t.subtitle.copyWith(color: p.textPrimary))),
                title: Text(e.name, style: t.subtitle.copyWith(color: p.textPrimary)),
                subtitle: Text(e.role == 'manager' ? 'Manager' : 'Cashier', style: t.caption.copyWith(color: p.textSecondary)),
                trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
                onTap: () => setState(() => _member = e),
              ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(m.name, key: const Key('onBehalfName'), style: t.title.copyWith(color: p.textPrimary)),
        const SizedBox(height: Space.s2),
        SegmentedButton<String>(
          key: const Key('onBehalfAction'),
          segments: const [ButtonSegment(value: ClockAction.clockIn, label: Text('Clock in')), ButtonSegment(value: ClockAction.clockOut, label: Text('Clock out'))],
          selected: {_action},
          onSelectionChanged: _busy ? null : (s) => setState(() => _action = s.first),
        ),
        const SizedBox(height: Space.s3),
        Text(_managerMode ? 'A manager enters their email and PIN.' : '${m.name}, enter your PIN.', key: const Key('onBehalfPrompt'), style: t.body.copyWith(color: p.textSecondary)),
        if (_managerMode) ...[
          const SizedBox(height: Space.s2),
          AppTextField(key: const Key('onBehalfManagerEmail'), label: 'Manager email', controller: _managerEmail, keyboardType: TextInputType.emailAddress, enabled: !_busy),
        ],
        const SizedBox(height: Space.s3),
        Center(child: PinDots(length: _pinLength, filled: _pin.length, errorTick: _errorTick, hasError: _error != null)),
        if (_error != null) ...[
          const SizedBox(height: Space.s2),
          Text(_error!, key: const Key('onBehalfError'), textAlign: TextAlign.center, style: t.caption.copyWith(color: p.danger)),
        ],
        const SizedBox(height: Space.s3),
        PinPad(onDigit: _digit, onBackspace: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1)), onClear: () => setState(() => _pin = ''), enabled: !_busy),
        const SizedBox(height: Space.s2),
        TextButton(
          key: const Key('onBehalfSwitch'),
          onPressed: _busy ? null : () => setState(() {
            _managerMode = !_managerMode;
            _pin = '';
            _error = null;
          }),
          child: Text(_managerMode ? 'Use ${m.name}\'s PIN instead' : 'Use a manager\'s PIN instead'),
        ),
      ],
    );
  }
}
