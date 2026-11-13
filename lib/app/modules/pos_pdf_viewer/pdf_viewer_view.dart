import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:printing/printing.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// G5.8: one PDF the till can show in the app — a receipt, tax invoice, credit note or an expense's PDF attachment. The bytes are built (or
/// downloaded) in memory when the viewer opens; nothing is written to the device by the app itself.
class PdfDoc {
  const PdfDoc({required this.title, required this.fileName, required this.bytes});
  final String title;
  final String fileName;
  final Future<Uint8List> Function() bytes;
}

/// Opens [doc] in the in-app viewer. Screens take an `openPdf` hook so tests can check what would open without rendering a PDF.
typedef PdfOpener = Future<void> Function(PdfDoc doc);

Future<void> openPdfViewer(PdfDoc doc) async => Get.to<void>(() => PdfViewerView(doc: doc));

/// The in-app PDF viewer: pages rendered on the device, with print (system print dialog / AirPrint / Android print service) and share in the
/// toolbar. Page size and orientation are those of the document — the till never changes them.
class PdfViewerView extends StatelessWidget {
  const PdfViewerView({super.key, required this.doc});
  final PdfDoc doc;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(title: Text(doc.title), backgroundColor: p.background, foregroundColor: p.textPrimary, elevation: 0),
      body: SafeArea(
        child: PdfPreview(
          key: const Key('pdfViewer'),
          build: (_) => doc.bytes(),
          pdfFileName: doc.fileName,
          allowPrinting: true,
          allowSharing: true,
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
          loadingWidget: const Center(child: CircularProgressIndicator(key: Key('pdfViewerLoading'))),
          onError: (context, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(Space.s5),
              child: Text(
                'This document could not be shown. Go back and try again.',
                key: const Key('pdfViewerError'),
                textAlign: TextAlign.center,
                style: context.type.body.copyWith(color: context.palette.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
