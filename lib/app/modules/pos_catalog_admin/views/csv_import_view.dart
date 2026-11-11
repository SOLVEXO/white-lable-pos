import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/controllers/catalog_admin_controllers.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/views/catalog_admin_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/report_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// G4.5 CSV import: products or categories, pasted or read from a .csv file, sent as text; the server's report (created / updated / failed and
/// the rows it refused).
class CsvImportView extends StatefulWidget {
  const CsvImportView({super.key, this.controller});
  final CsvImportController? controller;
  @override
  State<CsvImportView> createState() => _CsvImportViewState();
}

class _CsvImportViewState extends State<CsvImportView> with CatOwnedController<CsvImportView, CsvImportController> {
  @override
  CsvImportController? get given => widget.controller;
  @override
  CsvImportController create() => CsvImportController();

  final TextEditingController _text = TextEditingController();
  Worker? _file;

  @override
  void initState() {
    super.initState();
    // a picked file replaces the pasted text
    _file = ever<int>(c.revision, (_) => _text.text = c.csv.value);
  }

  @override
  void dispose() {
    _file?.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InvScaffold(
    title: 'Import from CSV',
    body: CatStateBody(
      c: c,
      subject: 'Importing',
      builder: (context) {
        final p = context.palette;
        final t = context.type;
        final r = c.report.value;
        return [
          const CatHint('The same columns as the dashboard importer. Rows are checked one by one: good rows are saved, the others are listed with the reason.'),
          SegmentedButton<String>(
            key: const Key('importKind'),
            segments: const [
              ButtonSegment(value: 'products', label: Text('Products')),
              ButtonSegment(value: 'categories', label: Text('Categories')),
            ],
            selected: {c.kind.value},
            onSelectionChanged: (v) => c.setKind(v.first),
          ),
          const SizedBox(height: Space.s3),
          TextField(
            key: const Key('importText'),
            controller: _text,
            minLines: 6,
            maxLines: 12,
            style: t.bodySmall.copyWith(fontFamily: 'Courier'),
            decoration: catField('CSV text', hint: 'Paste the CSV here, header row first'),
            onChanged: c.setText,
          ),
          if (c.fileName.value != null) CatHint('From ${c.fileName.value}'),
          const SizedBox(height: Space.s2),
          Row(
            children: [
              if (c.canPickFile) ...[
                Expanded(
                  child: AppButton(
                    key: const Key('importPick'),
                    label: 'Choose a .csv file',
                    icon: Icons.attach_file_rounded,
                    variant: AppButtonVariant.secondary,
                    onPressed: c.busy.value ? null : c.pickFile,
                  ),
                ),
                const SizedBox(width: Space.s2),
              ],
              Expanded(
                child: AppButton(key: const Key('importSubmit'), label: 'Import', icon: Icons.upload_rounded, loading: c.busy.value, onPressed: c.busy.value ? null : c.submit),
              ),
            ],
          ),
          if (r != null) ...[
            const InvSectionTitle('Report'),
            ReportRow(key: const Key('importCreated'), title: 'Created', value: '${r.created}'),
            ReportRow(key: const Key('importUpdated'), title: 'Updated', value: '${r.updated}'),
            ReportRow(key: const Key('importSkipped'), title: 'Skipped (nothing to change)', value: '${r.skipped}'),
            ReportRow(key: const Key('importFailed'), title: 'Failed', value: '${r.failed}'),
            if (r.errors.isNotEmpty) ...[
              const InvSectionTitle('Rows not imported'),
              for (final (i, e) in r.errors.indexed)
                Padding(
                  key: Key('importError_$i'),
                  padding: const EdgeInsets.only(bottom: Space.s1),
                  child: Text(e, style: t.bodySmall.copyWith(color: p.dangerFg)),
                ),
            ],
          ],
        ];
      },
    ),
  );
}
