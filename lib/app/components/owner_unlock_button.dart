import 'package:flutter/material.dart';
import 'package:solvexo_pos/app/data/services/owner_gate.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// Under an "only the owner can change this" banner on a registered till: the owner re-enters their password (the owner gate), then the screen
/// reloads with the owner's short-lived session, so the server answers it as the owner. Hidden on a terminal that is not a registered till.
class OwnerUnlockButton extends StatelessWidget {
  const OwnerUnlockButton({super.key, required this.onUnlocked});
  final VoidCallback onUnlocked;

  @override
  Widget build(BuildContext context) {
    if (!AppPreferences.cachedDeviceMode) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const Key('ownerUnlock'),
        icon: const Icon(Icons.lock_open_rounded, size: 18),
        label: const Text('I am the owner: unlock to edit'),
        onPressed: () async {
          if (await OwnerGate.ensure()) onUnlocked();
        },
      ),
    );
  }
}
