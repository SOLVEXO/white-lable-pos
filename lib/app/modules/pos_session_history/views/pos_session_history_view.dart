import 'package:solvexo_pos/utils/money.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_session_model.dart';
import 'package:solvexo_pos/app/modules/pos_session_history/controllers/pos_session_history_controller.dart';
import 'package:solvexo_pos/app/modules/pos_session_history/widgets/pos_session_history_shimmer.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class PosSessionHistoryView extends StatelessWidget {
  PosSessionHistoryView({super.key});

  final PosSessionHistoryController c = Get.put(PosSessionHistoryController());

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppPage(
      title: 'Shift History',
      actions: [
        Obx(() {
          final only = c.currentRegisterOnly.value;
          return Padding(
            padding: const EdgeInsets.only(right: Space.s2),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: Radii.rFull,
                onTap: c.toggleCurrentRegisterOnly,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: Space.minTouch),
                  child: Center(
                    widthFactor: 1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: Space.s3, vertical: Space.s1 + 2),
                      decoration: BoxDecoration(
                        color: only ? p.accentSoft : p.fill,
                        borderRadius: Radii.rFull,
                        border: Border.all(color: only ? p.accentFg : p.border),
                      ),
                      child: Text(
                        only ? 'This register' : 'All registers',
                        style: context.type.label.copyWith(color: only ? p.accentFg : p.textPrimary),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
      body: Obx(() {
        if (c.isLoading.value) {
          return const PosSessionHistoryShimmer();
        }
        if (c.sessions.isEmpty) {
          return EmptyState(
            icon: Icons.history_rounded,
            title: c.currentRegisterOnly.value ? 'No past shifts yet on this register.' : 'No past shifts yet.',
          );
        }
        return RefreshIndicator(
          onRefresh: c.refreshData,
          child: ListView.separated(
            controller: c.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
            itemCount: c.sessions.length + (c.hasMore ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(height: Space.s2),
            itemBuilder: (_, i) {
              if (i >= c.sessions.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: Space.s3),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              return _SessionTile(session: c.sessions[i], onTap: () => c.openReport(c.sessions[i]));
            },
          ),
        );
      }),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final PosSessionModel session;
  final VoidCallback onTap;
  const _SessionTile({required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isOpen = session.isOpen;
    return AppListRow(
      icon: isOpen ? Icons.lock_open_rounded : Icons.lock_rounded,
      tone: isOpen ? StatusTone.success : StatusTone.neutral,
      title: DateFormat('MMM d, y  h:mm a').format(session.openedAt.toLocal()),
      subtitle: session.isForceClosed ? 'Force closed' : (isOpen ? 'Currently open' : '${session.totalTransactions} transactions'),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 140),
        child: AmountText(Money.format(session.totalSales), style: context.type.amountMd, color: p.accentFg, animate: false, alignment: MainAxisAlignment.end),
      ),
      onTap: onTap,
    );
  }
}
