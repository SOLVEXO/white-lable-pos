import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/clock_controller.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// A small card on Home: the signed-in person's clock state with a "Clock in" chip, and their next rostered shift today or tomorrow with its times.
/// It appears only when the app registered the clock controller.
class ClockHomeCard extends StatefulWidget {
  const ClockHomeCard({super.key, this.controller});
  final TeamClockController? controller;

  @override
  State<ClockHomeCard> createState() => _ClockHomeCardState();
}

class _ClockHomeCardState extends State<ClockHomeCard> {
  TeamClockController? get c => widget.controller ?? (Get.isRegistered<TeamClockController>() ? Get.find<TeamClockController>() : null);

  @override
  void initState() {
    super.initState();
    // Home was opened (maybe right after a PIN login): look again at who is clocked in
    Future.microtask(() => c?.load());
  }

  @override
  Widget build(BuildContext context) {
    final c = this.c;
    if (c == null) return const SizedBox.shrink();
    final p = context.palette;
    final t = context.type;
    return Obx(() {
      if (c.needsPin.value) return const SizedBox.shrink();
      final s = c.state;
      final shift = c.nextShiftSoon;
      final label = !s.clockedIn ? 'Clock in' : (s.onBreak ? 'On a break' : 'Clocked in');
      return Padding(
        padding: const EdgeInsets.only(top: Space.s3),
        child: AppCard(
          key: const Key('clockHomeCard'),
          radius: Radii.rMd,
          onTap: () => Get.toNamed(Routes.posTeamClock),
          child: Row(
            children: [
              Icon(Icons.schedule_rounded, color: p.accentFg),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shift == null ? 'No shift today or tomorrow' : 'Next shift ${c.dayWord(shift.startAt)}: ${shift.range}',
                      key: const Key('clockHomeShift'),
                      style: t.body.copyWith(color: p.textPrimary),
                    ),
                    if (s.clockedIn) Text('Since ${teamTime(s.since)}', style: t.caption.copyWith(color: p.textMuted)),
                  ],
                ),
              ),
              StatusBadge(label, key: const Key('clockHomeChip'), tone: s.clockedIn ? (s.onBreak ? StatusTone.warning : StatusTone.success) : StatusTone.accent),
            ],
          ),
        ),
      );
    });
  }
}
