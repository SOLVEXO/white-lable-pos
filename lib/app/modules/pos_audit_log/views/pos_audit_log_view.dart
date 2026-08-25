import 'package:solvexo_pos/app/components/custom_app_bar_two.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_audit_log_model.dart';
import 'package:solvexo_pos/app/modules/pos_audit_log/controllers/pos_audit_log_controller.dart';
import 'package:solvexo_pos/app/modules/pos_audit_log/widgets/pos_audit_log_shimmer.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class PosAuditLogView extends StatelessWidget {
  PosAuditLogView({super.key});

  final PosAuditLogController c = Get.put(PosAuditLogController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CustomAppBarTwo(
        title: 'Activity Log',
        color: AppColors.black2,
      ),
      body: Obx(() {
        if (c.isLoading.value) {
          return const PosAuditLogShimmer();
        }
        if (c.logs.isEmpty) {
          return const Center(
            child: CustomText(text: 'No activity recorded yet.', fontSize: AppFontSize.small2, color: AppColors.iosGrey),
          );
        }
        return RefreshIndicator(
          onRefresh: c.refreshData,
          color: AppColors.primaryColor,
          child: ListView.separated(
            controller: c.scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: c.logs.length + (c.hasMore ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              if (i >= c.logs.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryColor)),
                );
              }
              return _LogTile(log: c.logs[i]);
            },
          ),
        );
      }),
    );
  }
}

class _LogTile extends StatelessWidget {
  final PosAuditLogModel log;
  const _LogTile({required this.log});

  IconData get _icon {
    if (log.action.contains('void')) return Icons.block_rounded;
    if (log.action.contains('refund')) return Icons.undo_rounded;
    if (log.action.contains('pin')) return Icons.pin_rounded;
    if (log.action.contains('employee')) return Icons.person_outline_rounded;
    if (log.action.contains('session')) return Icons.lock_clock_rounded;
    return Icons.history_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: AppColors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 1))],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: AppColors.primaryColor.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
          child: Icon(_icon, size: 16, color: AppColors.primaryColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CustomText(text: log.actionLabel, fontSize: AppFontSize.verySmall, fontWeight: FontWeight.w600, color: AppColors.black2),
            CustomText(
              text: DateFormat('MMM d, h:mm a').format(log.createdAt.toLocal()),
              fontSize: AppFontSize.tiny,
              color: AppColors.iosGrey,
            ),
          ]),
        ),
      ]),
    );
  }
}
