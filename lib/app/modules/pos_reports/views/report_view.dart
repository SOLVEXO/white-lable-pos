import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/report_controller.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/report_bodies.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/report_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// One G4.1 report: the date strip, compare / filters, the body and the export (CSV / PDF). Online only.
class ReportView extends StatefulWidget {
  const ReportView({super.key, required this.kind, this.controller, this.employeeId});
  final ReportKind kind;
  final ReportController? controller;

  /// opens the report already filtered to one cashier (the cashier report's drill-down)
  final String? employeeId;

  @override
  State<ReportView> createState() => _ReportViewState();
}

class _ReportViewState extends State<ReportView> {
  late final String _tag = 'report_${widget.kind.path}_${identityHashCode(this)}';
  late final ReportController c =
      widget.controller ??
      Get.put(
        ReportController(kind: widget.kind, employeeId: widget.employeeId),
        tag: _tag,
      );

  @override
  void dispose() {
    if (widget.controller == null) Get.delete<ReportController>(tag: _tag);
    super.dispose();
  }

  String get _title {
    final manager = c.canManage.value; // read first: the Obx must always observe it
    return widget.kind == ReportKind.cashiers && !manager ? 'My sales' : widget.kind.label;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => InvScaffold(
        title: _title,
        maxWidth: 1100,
        actions: [ReportExportButton(c: c)],
        body: Obx(() {
          if (!reportsOnlineRx().value && c.report.value == null) return ReportsNeedsInternet(subject: 'The ${widget.kind.label.toLowerCase()} report');
          final r = c.report.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ReportControls(c: c),
              Expanded(
                child: c.loading.value && r == null
                    ? const Center(child: CircularProgressIndicator(key: Key('reportLoading')))
                    : r == null
                    ? InvErrorState(message: c.error.value ?? 'Try again.', onRetry: c.load)
                    : RefreshIndicator(
                        onRefresh: c.load,
                        child: ListView(
                          key: const Key('reportBody'),
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
                          children: [
                            if (c.loading.value) const LinearProgressIndicator(minHeight: 2),
                            if (c.exportError.value != null) ReportInfo(c.exportError.value!, warn: true),
                            ReportBody(c: c, r: r),
                          ],
                        ),
                      ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
