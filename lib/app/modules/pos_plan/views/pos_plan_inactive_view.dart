import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/repositories/pos_subscription_repository.dart';
import 'package:solvexo_pos/app/data/services/owner_gate.dart';
import 'package:solvexo_pos/app/data/services/pos_device_service.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/unsynced_guard.dart';

/// Shown when the store has no active POS plan. Deliberately neutral: no prices, no plan list, no links and no call to
/// action to buy anywhere. The app only READS the entitlement — Refresh re-reads it, Sign out leaves the device.
/// (An open register session keeps working in the app's restricted mode; this screen only stands in front of starting one.)
class PosPlanInactiveView extends StatefulWidget {
  const PosPlanInactiveView({super.key, PosSubscriptionRepository? repository}) : _repo = repository;
  final PosSubscriptionRepository? _repo;

  @override
  State<PosPlanInactiveView> createState() => _PosPlanInactiveViewState();
}

class _PosPlanInactiveViewState extends State<PosPlanInactiveView> {
  late final PosSubscriptionRepository _repo = widget._repo ?? PosSubscriptionRepository();
  bool _busy = false;
  String? _note;

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _note = null;
    });
    final storeId = await AppPreferences.getStoreId() ?? '';
    final status = storeId.isEmpty ? null : await _repo.getStatus(storeId);
    if (!mounted) return;
    if (status != null && !status.isUnknown && (status.status.isEntitled || !status.enforced)) {
      Get.offNamed(Routes.posPinLogin);
      return;
    }
    setState(() {
      _busy = false;
      _note = status == null || status.isUnknown ? "Couldn't check right now. Try again in a moment." : "The plan still isn't active.";
    });
  }

  Future<void> _signOut() async {
    // Leaving a registered device is the owner's call (and never while sales are unsynced).
    if (!await OwnerGate.ensure()) return;
    if (await UnsyncedGuard.blockIfUnsynced(action: 'sign out')) return;
    if (AppPreferences.cachedDeviceMode && Get.isRegistered<PosDeviceService>()) {
      await Get.find<PosDeviceService>().reset();
    } else {
      await AppPreferences.clearPreference();
    }
    Get.offAllNamed(Routes.posLogin);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.s6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Icon(Icons.pause_circle_outline_rounded, size: 56, color: p.textMuted),
                const SizedBox(height: Space.s4),
                Text("POS plan isn't active for this store", textAlign: TextAlign.center, style: t.headline.copyWith(color: p.textPrimary)),
                const SizedBox(height: Space.s2),
                Text('Selling is unavailable until the plan is active again.', textAlign: TextAlign.center, style: t.body.copyWith(color: p.textSecondary)),
                if (_note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.s3),
                    child: Text(_note!, key: const Key('planInactiveNote'), textAlign: TextAlign.center, style: t.bodySmall.copyWith(color: p.warningFg)),
                  ),
                const SizedBox(height: Space.s6),
                AppButton(key: const Key('planInactiveRefresh'), label: 'Refresh', expand: true, loading: _busy, onPressed: _busy ? null : _refresh),
                const SizedBox(height: Space.s2),
                AppButton(key: const Key('planInactiveSignOut'), label: 'Sign out', variant: AppButtonVariant.ghost, expand: true, onPressed: _busy ? null : _signOut),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
