// G6.3 design-system guard: outside lib/core/design/ no screen picks its own colours, fonts or text styles. Every colour comes from
// `context.palette`, every text style from `context.type`, and the legacy kit (AppColors, CustomText, responsive_sizer's `.sp`) is gone.
//
// Ratchet: test/design_guard_baseline.txt lists the violations that existed when the guard was added (`<path> <count>`). A file may never
// exceed its baseline, a file not listed must have none, and when a file improves the baseline must be lowered in the same commit (so the list
// only ever shrinks). Regenerate after restyling: DESIGN_GUARD_WRITE=1 flutter test test/design_guard_test.dart
// By the end of G6.3 the baseline is empty.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The design system itself is the one place allowed to define colours and type.
const _exemptDirs = ['lib/core/design/'];

/// Individual exceptions that cannot follow the rule, each with its reason. Key: `<path>|<rule>`.
const Map<String, String> allowlist = {};

final rules = <String, RegExp>{
  'raw-color': RegExp(r'\bColor\(0x|\bColor\.from(ARGB|RGBO)\('),
  'material-colors': RegExp(r'(?<![A-Za-z_])Colors\.(?!transparent\b)'),
  'font-size': RegExp(r'\bfontSize\s*:'),
  'font-family': RegExp(r'\bfontFamily\s*:|\bGoogleFonts\.'),
  'ad-hoc-textstyle': RegExp(r'(?<![A-Za-z_])TextStyle\('),
  'legacy-appcolors': RegExp(r'\bAppColors\.'),
  'legacy-customtext': RegExp(r'\bCustomText\('),
  'legacy-sp': RegExp(r'\d\.sp\b|\)\.sp\b|\b[a-z]\w*\.sp\b'),
};

/// Violations of one source file, as `line: rule` strings (comments ignored).
List<String> scan(String path, String src) {
  final out = <String>[];
  final lines = src.split('\n');
  var inBlock = false;
  for (var i = 0; i < lines.length; i++) {
    var l = lines[i];
    if (inBlock) {
      if (!l.contains('*/')) continue;
      l = l.substring(l.indexOf('*/') + 2);
      inBlock = false;
    }
    final t = l.trimLeft();
    if (t.startsWith('//')) continue;
    final c = l.indexOf(' //');
    if (c >= 0) l = l.substring(0, c);
    if (l.contains('/*') && !l.contains('*/')) {
      inBlock = true;
      l = l.substring(0, l.indexOf('/*'));
    }
    for (final e in rules.entries) {
      if (allowlist.containsKey('$path|${e.key}')) continue;
      final n = e.value.allMatches(l).length;
      for (var k = 0; k < n; k++) {
        out.add('${i + 1}: ${e.key}');
      }
    }
  }
  return out;
}

Map<String, List<String>> scanLib() {
  final res = <String, List<String>>{};
  final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final p = f.path.replaceAll(r'\', '/');
    if (_exemptDirs.any(p.startsWith)) continue;
    final v = scan(p, f.readAsStringSync());
    if (v.isNotEmpty) res[p] = v;
  }
  return res;
}

const _baselinePath = 'test/design_guard_baseline.txt';

Map<String, int> readBaseline() {
  final f = File(_baselinePath);
  if (!f.existsSync()) return {};
  final out = <String, int>{};
  for (final l in f.readAsLinesSync()) {
    final s = l.trim();
    if (s.isEmpty || s.startsWith('#')) continue;
    final parts = s.split(' ');
    out[parts[0]] = int.parse(parts[1]);
  }
  return out;
}

void main() {
  test('rules catch what they should, and nothing else', () {
    expect(scan('x', 'final c = Color(0xFF112233);'), ['1: raw-color']);
    expect(scan('x', 'color: Colors.red,'), ['1: material-colors']);
    expect(scan('x', 'color: Colors.transparent,'), isEmpty);
    expect(scan('x', 'color: AppColors.primary,'), ['1: legacy-appcolors']);
    expect(scan('x', 'style: TextStyle(fontSize: 12)'), ['1: font-size', '1: ad-hoc-textstyle']);
    expect(scan('x', 'style: context.type.body.copyWith(fontFamily: "X")'), ['1: font-family']);
    expect(scan('x', 'SizedBox(height: 2.sp)'), ['1: legacy-sp']);
    expect(scan('x', 'final s = Space.s4; context.palette.accent; x.spacing'), isEmpty);
    expect(scan('x', '// Colors.red in a comment\n/* Color(0xFF000000)\n*/ ok'), isEmpty);
  });

  test('no file has more violations than the baseline; improved files must lower it (the list only shrinks)', () {
    final found = scanLib();
    if (Platform.environment['DESIGN_GUARD_WRITE'] == '1') {
      final b = StringBuffer('# G6.3 design guard baseline: <path> <violations>. Only ever shrinks; empty at the end of G6.3.\n');
      for (final e in found.entries) {
        b.writeln('${e.key} ${e.value.length}');
      }
      File(_baselinePath).writeAsStringSync(b.toString());
    }
    final base = readBaseline();
    final problems = <String>[];
    for (final e in found.entries) {
      final allowed = base[e.key] ?? 0;
      if (e.value.length > allowed) {
        problems.add('${e.key}: ${e.value.length} violations (baseline $allowed) — use context.palette / context.type / design components:\n    '
            '${e.value.take(8).join('\n    ')}');
      }
    }
    for (final e in base.entries) {
      final now = found[e.key]?.length ?? 0;
      if (now < e.value) problems.add('${e.key}: now $now, baseline ${e.value} — lower the baseline (DESIGN_GUARD_WRITE=1)');
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('every allow-list entry names a real file and a reason', () {
    for (final e in allowlist.entries) {
      final path = e.key.split('|').first;
      expect(File(path).existsSync(), isTrue, reason: e.key);
      expect(e.value.trim().length, greaterThan(10), reason: e.key);
    }
  });
}
