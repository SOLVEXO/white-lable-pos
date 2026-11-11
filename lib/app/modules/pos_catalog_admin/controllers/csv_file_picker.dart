import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// G4.8: the ONLY use of `file_picker` outside KYB (owner-approved for CSV import; the store-release guard test allows exactly this file).
/// A .csv file only, at most 2 MB (the server's limit) — checked BEFORE the file is read; decoded and counted off the UI thread.

/// The server refuses more than 2 MB (`CSV_TOO_LARGE`); the till refuses it before reading the file.
const int csvMaxBytes = 2 * 1024 * 1024;

class CsvFileTooLarge implements Exception {
  const CsvFileTooLarge(this.bytes);
  final int bytes;
}

class CsvFileNotCsv implements Exception {
  const CsvFileNotCsv(this.name);
  final String name;
}

/// A picked CSV: its name, its text, and how many data rows it has (lines after the header).
typedef PickedCsv = ({String name, String text, int rows});

/// Decoding + counting, run in a background isolate ([compute]) so a large file never janks the UI. Top-level for [compute].
({String text, int rows}) decodeCsv(Uint8List bytes) {
  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.startsWith('﻿')) text = text.substring(1); // a BOM from Excel
  final lines = const LineSplitter().convert(text).where((l) => l.trim().isNotEmpty).length;
  return (text: text, rows: lines > 0 ? lines - 1 : 0);
}

/// Opens the system picker for a .csv file. Null when the user backed out; throws [CsvFileTooLarge] / [CsvFileNotCsv].
Future<PickedCsv?> pickCsvFile() async {
  final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['csv'], withData: false);
  final f = r?.files.single;
  if (f == null) return null;
  try {
    if (!f.name.toLowerCase().endsWith('.csv')) throw CsvFileNotCsv(f.name);
    if (f.size > csvMaxBytes) throw CsvFileTooLarge(f.size); // known before reading a single byte
    final bytes = f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
    if (bytes == null) return null;
    if (bytes.length > csvMaxBytes) throw CsvFileTooLarge(bytes.length);
    final d = await compute(decodeCsv, bytes);
    return (name: f.name, text: d.text, rows: d.rows);
  } finally {
    if (!kIsWeb) await FilePicker.clearTemporaryFiles(); // nothing of the file is left on the device
  }
}
