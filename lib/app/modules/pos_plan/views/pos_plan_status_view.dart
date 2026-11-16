import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_subscription_status_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_subscription_repository.dart';
import 'package:solvexo_pos/app/modules/pos_plan/views/plan_expiry_banner.dart';
import 'package:solvexo_pos/core/design/design.dart';
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
    final p = context.palette;
    final entitled = s?.status.isEntitled == true;
    return AppPage(
      title: 'POS plan',
      actions: [IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      body: _loading
          ? Center(child: CircularProgressIndicator(color: p.accent))
          : ListView(padding: const EdgeInsets.all(Space.s4), children: [
              PlanExpiryBanner(status: s),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: Space.s4, vertical: Space.s2),
                child: Column(children: [
                  _row(context, 'Status', label, color: entitled ? p.successFg : p.dangerFg),
                  _row(context, 'Plan', s?.planName ?? '—'),
                  _row(context, 'Started', _date(s?.purchasedAt)),
                  _row(context, 'Expires', _date(s?.expiresAt)),
                  if (entitled) _row(context, 'Days remaining', '${s?.daysRemaining ?? '—'}'),
                ]),
              ),
              const SizedBox(height: Space.s4),
              AppButton(key: const Key('planStatusRefresh'), label: 'Refresh', variant: AppButtonVariant.ghost, icon: Icons.refresh_rounded, expand: true, onPressed: _load),
            ]),
    );
  }

  Widget _row(BuildContext context, String k, String v, {Color? color}) {
    final p = context.palette;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Space.minTouch),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s2),
        child: Row(children: [
          Expanded(child: Text(k, style: context.type.body.copyWith(color: p.textSecondary))),
          const SizedBox(width: Space.s3),
          Flexible(child: Text(v, textAlign: TextAlign.end, style: context.type.subtitle.copyWith(color: color ?? p.textPrimary))),
        ]),
      ),
    );
  }
}
