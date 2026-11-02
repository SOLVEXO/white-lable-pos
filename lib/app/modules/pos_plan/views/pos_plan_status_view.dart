import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_subscription_status_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_subscription_repository.dart';
import 'package:solvexo_pos/app/modules/pos_plan/views/plan_expiry_banner.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// Owner-only, READ-ONLY plan status: plan name, state and expiry date. No prices, no actions, no links.
class PosPlanStatusView extends StatefulWidget {
  const PosPlanStatusView({super.key, PosSubscriptionRepository? repository}) : _repo = repository;
  final PosSubscriptionRepository? _repo;

  @override
  State<PosPlanStatusView> createState() => _PosPlanStatusViewState();
}

class _PosPlanStatusViewState extends State<PosPlanStatusView> {
  late final PosSubscriptionRepository _repo = widget._repo ?? PosSubscriptionRepository();
  PosSubscriptionStatusModel? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final storeId = await AppPreferences.getStoreId() ?? '';
    final s = storeId.isEmpty ? null : await _repo.getStatus(storeId);
    if (!mounted) return;
    setState(() {
      _status = s;
      _loading = false;
    });
  }

  String _date(DateTime? d) => d == null ? '—' : DateFormat('MMM d, y').format(d.toLocal());

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final label = s == null || s.isUnknown
        ? 'Unavailable'
        : switch (s.status) {
            PosSubscriptionStatusValue.active => 'Active',
            PosSubscriptionStatusValue.expired => 'Expired',
            PosSubscriptionStatusValue.none => 'No plan',
          };
    return Scaffold(
      appBar: AppBar(title: const Text('POS plan'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(20), children: [
              PlanExpiryBanner(status: s),
              _row('Status', label, color: s?.status.isEntitled == true ? AppColors.green2 : AppColors.red),
              _row('Plan', s?.planName ?? '—'),
              _row('Started', _date(s?.purchasedAt)),
              _row('Expires', _date(s?.expiresAt)),
              if (s?.status.isEntitled == true) _row('Days remaining', '${s?.daysRemaining ?? '—'}'),
              const SizedBox(height: 16),
              TextButton(key: const Key('planStatusRefresh'), onPressed: _load, child: const Text('Refresh')),
            ]),
    );
  }

  Widget _row(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [Text(k, style: const TextStyle(color: AppColors.iosGrey)), const Spacer(), Text(v, style: TextStyle(fontWeight: FontWeight.w600, color: color))]),
      );
}
