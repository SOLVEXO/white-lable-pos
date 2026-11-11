import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart' show invMoney;
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos/views/pos_hub_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/report_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/team_common.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// G5.1 — the team (managers): everyone, tap for their profile.
class TeamMembersView extends StatefulWidget {
  const TeamMembersView({super.key, this.repository, this.storeId});
  final PosRepository? repository;
  final String? storeId;

  @override
  State<TeamMembersView> createState() => _TeamMembersViewState();
}

class _TeamMembersViewState extends State<TeamMembersView> {
  List<PosEmployeeModel>? _people;

  @override
  void initState() {
    super.initState();
    () async {
      final all = await (widget.repository ?? PosRepository()).getEmployees(await teamStoreId(widget.storeId));
      if (mounted) setState(() => _people = all..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));
    }();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final people = _people;
    return HubScaffold(
      title: 'Team members',
      listKey: const Key('teamMembersList'),
      children: [
        if (people == null)
          const Padding(padding: EdgeInsets.all(Space.s6), child: Center(child: CircularProgressIndicator()))
        else if (people.isEmpty)
          const EmptyState(icon: Icons.groups_2_outlined, title: 'No team members', message: 'Add employees from Registers & team.')
        else
          for (final e in people)
            HubRow(
              key: Key('member_${e.id}'),
              icon: e.role == 'manager' ? Icons.verified_user_outlined : Icons.person_outline_rounded,
              title: e.name,
              subtitle: '${e.role == 'manager' ? 'Manager' : 'Cashier'}${e.status == 'inactive' ? ' · deactivated' : ''}',
              onTap: () => Get.to(() => StaffProfileView(employeeId: e.id, repository: widget.repository, storeId: widget.storeId)),
            ),
        if (people != null && people.isNotEmpty) Padding(padding: const EdgeInsets.all(Space.s3), child: Text('Edit people and PINs in Settings → Registers & team.', style: context.type.caption.copyWith(color: p.textMuted))),
      ],
    );
  }
}

/// G5.1 — one person: role, last PIN login, clocked in now, sales today / last 7 / last 30 days, and links to their attendance and the cashier report.
class StaffProfileView extends StatefulWidget {
  const StaffProfileView({super.key, required this.employeeId, this.repository, this.storeId});
  final String employeeId;
  final PosRepository? repository;
  final String? storeId;

  @override
  State<StaffProfileView> createState() => _StaffProfileViewState();
}

class _StaffProfileViewState extends State<StaffProfileView> {
  StaffProfile? _p;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = widget.repository ?? PosRepository();
    final p = await repo.getStaffProfile(await teamStoreId(widget.storeId), widget.employeeId);
    if (!mounted) return;
    setState(() {
      _p = p;
      _loading = false;
      _error = p == null ? (repo.lastErrorCode == 'POS_ACTION_FORBIDDEN' ? 'You can only open your own profile.' : 'Could not load the profile. Check the connection and try again.') : null;
    });
  }

  String _when(DateTime? d) => d == null ? 'Never' : DateFormat('d MMM yyyy, HH:mm').format(d);

  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    final t = context.type;
    final p = _p;
    String money(({int sales, int totalMinor}) w) => p?.cur == null ? '${w.sales} sales' : '${w.sales} · ${invMoney(w.totalMinor, p!.cur!)}';
    return HubScaffold(
      title: p?.name ?? 'Profile',
      listKey: const Key('staffProfile'),
      children: [
        if (_loading && p == null) const Padding(padding: EdgeInsets.all(Space.s6), child: Center(child: CircularProgressIndicator())),
        if (_error != null) Padding(padding: const EdgeInsets.all(Space.s4), child: Text(_error!, key: const Key('staffProfileError'), style: t.body.copyWith(color: pal.danger))),
        if (p != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s3),
            child: Row(
              children: [
                CircleAvatar(radius: 28, backgroundColor: pal.accentSoft, child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase(), style: t.title.copyWith(color: pal.accentFg))),
                const SizedBox(width: Space.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: t.title.copyWith(color: pal.textPrimary)),
                      Text('${p.role == 'manager' ? 'Manager' : 'Cashier'}${p.status == 'inactive' ? ' · deactivated' : ''}${p.email != null ? ' · ${p.email}' : ''}', style: t.caption.copyWith(color: pal.textSecondary)),
                    ],
                  ),
                ),
                StatusBadge(p.clockedIn ? 'Clocked in' : 'Not clocked in', key: const Key('staffClockState'), tone: p.clockedIn ? StatusTone.success : StatusTone.neutral),
              ],
            ),
          ),
          HubSection('Activity', [
            ReportRow(key: const Key('staffLastLogin'), title: 'Last PIN login', value: _when(p.lastLoginAt)),
            if (p.clockedIn) ReportRow(title: 'Clocked in since', value: _when(p.clockedInSince)),
          ]),
          HubSection('Sales they rang up', [
            ReportRow(key: const Key('staffSalesToday'), title: 'Today', value: money(p.today)),
            ReportRow(key: const Key('staffSales7'), title: 'Last 7 days', value: money(p.last7)),
            ReportRow(key: const Key('staffSales30'), title: 'Last 30 days', value: money(p.last30)),
          ]),
          HubSection('More', [
            HubRow(icon: Icons.fact_check_outlined, title: 'Attendance', subtitle: 'Hours and clock events', onTap: () => Get.toNamed(Routes.posTeamAttendance, arguments: {'employeeId': p.employeeId})),
          ]),
        ],
      ],
    );
  }
}
