import 'package:solvexo_pos/app/components/custom_app_bar_two.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_session_model.dart';
import 'package:solvexo_pos/app/modules/pos_session_history/controllers/pos_session_history_controller.dart';
import 'package:solvexo_pos/app/modules/pos_session_history/widgets/pos_session_history_shimmer.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class PosSessionHistoryView extends StatelessWidget {
  PosSessionHistoryView({super.key});

  final PosSessionHistoryController c = Get.put(PosSessionHistoryController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBarTwo(
        title: 'Shift History',
        color: AppColors.black2,
        actions: [
          Obx(() => GestureDetector(
            onTap: c.toggleCurrentRegisterOnly,
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: c.currentRegisterOnly.value
                    ? AppColors.primaryColor.withOpacity(0.1)
                    : AppColors.background,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: c.currentRegisterOnly.value ? AppColors.primaryColor : AppColors.lightGrey2,
                ),
              ),
              child: CustomText(
                text: c.currentRegisterOnly.value ? 'This register' : 'All registers',
                fontSize: AppFontSize.tiny,
                fontWeight: FontWeight.w600,
                color: c.currentRegisterOnly.value ? AppColors.primaryColor : AppColors.black2,
              ),
            ),
          )),
        ],
      ),
      body: Obx(() {
        if (c.isLoading.value) {
          return const PosSessionHistoryShimmer();
        }
        if (c.sessions.isEmpty) {
          return Center(
            child: CustomText(
              text: c.currentRegisterOnly.value
                  ? 'No past shifts yet on this register.'
                  : 'No past shifts yet.',
              fontSize: AppFontSize.small2,
              color: AppColors.iosGrey,
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: c.refreshData,
          color: AppColors.primaryColor,
          child: ListView.separated(
            controller: c.scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: c.sessions.length + (c.hasMore ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              if (i >= c.sessions.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryColor)),
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
    final isOpen = session.isOpen;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: AppColors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: (isOpen ? AppColors.green2 : AppColors.iosGrey).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(isOpen ? Icons.lock_open_rounded : Icons.lock_rounded, color: isOpen ? AppColors.green2 : AppColors.iosGrey, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CustomText(
                text: DateFormat('MMM d, y  h:mm a').format(session.openedAt.toLocal()),
                fontSize: AppFontSize.verySmall,
                fontWeight: FontWeight.w600,
                color: AppColors.black2,
              ),
              CustomText(
                text: session.isForceClosed
                    ? 'Force closed'
                    : (isOpen ? 'Currently open' : '${session.totalTransactions} transactions'),
                fontSize: AppFontSize.tiny,
                color: AppColors.iosGrey,
              ),
            ]),
          ),
          CustomText(
            text: '\$${session.totalSales.toStringAsFixed(2)}',
            fontSize: AppFontSize.small2,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryColor,
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: AppColors.lightGrey5, size: 20),
        ]),
      ),
    );
  }
}
