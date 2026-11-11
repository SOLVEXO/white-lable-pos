// G4.8 currency guard: no hard-coded currency symbol in lib/ outside the money formatter. Money is always shown in the currency the server states
// (Money.format / Money.symbol / the response's currency + exponent), so a literal "$", "Rs", "₨", "€", "£" or a code glued to an amount ("PKR 1,000")
// in a string is a bug. Currency CODES as data (a fallback `?? 'USD'`, the notes & coins table keyed by code) are not display text and are allowed.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The only place allowed to know symbols: the formatter itself.
const _allowedFiles = {'lib/utils/money.dart'};

final _dollar = String.fromCharCode(36);
final _backslash = String.fromCharCode(92);

/// String literals of a Dart source line (single or double quoted), after removing a trailing `//` comment that is outside any string.
Iterable<String> _literals(String line) sync* {
  String? quote;
  final buf = StringBuffer();
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (quote == null) {
      if (ch == '/' && i + 1 < line.length && line[i + 1] == '/') return; // a comment
      if (ch == "'" || ch == '"') {
        quote = ch;
        buf.clear();
      }
      continue;
    }
    if (ch == _backslash && i + 1 < line.length) {
      buf.write(ch);
      buf.write(line[++i]);
      continue;
    }
    if (ch == quote) {
      yield buf.toString();
      quote = null;
      continue;
    }
    buf.write(ch);
  }
}

List<String> violations(String path, String src) {
  final out = <String>[];
  final literalDollar = '$_backslash$_dollar'; // \$ in source = a printed dollar sign
  final symbol = RegExp(r'[₨€£¥]|\bRs\.?(?=\s|\d|$)');
  final codeAmount = RegExp(r'\b(PKR|USD|EUR|GBP|AED|SAR|INR|JPY|KWD)\s?\d');
  final lines = src.split('\n');
  var inBlock = false;
  for (var i = 0; i < lines.length; i++) {
    var l = lines[i];
    if (inBlock) {
      if (!l.contains('*/')) continue;
      l = l.substring(l.indexOf('*/') + 2);
      inBlock = false;
    }
    if (l.trimLeft().startsWith('///') || l.trimLeft().startsWith('//')) continue;
    if (l.contains('/*') && !l.contains('*/')) inBlock = true;
    for (final lit in _literals(l)) {
      if (lit.contains(literalDollar) || symbol.hasMatch(lit) || codeAmount.hasMatch(lit)) out.add('$path:${i + 1}: $lit');
    }
  }
  return out;
}

void main() {
  test('no hard-coded currency symbol in lib/ outside the money formatter', () {
    final found = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final p = f.path.replaceAll(_backslash, '/');
      if (_allowedFiles.contains(p)) continue;
      found.addAll(violations(p, f.readAsStringSync()));
    }
    expect(found, isEmpty, reason: 'format money with Money.format / Money.symbol and the currency the server states');
  });

  test('the guard itself catches what it should and lets data codes through', () {
    final src = [
      "final a = '$_backslash${_dollar}12';", // a printed dollar
      "final b = 'Rs 500';",
      "final c = 'PKR 1,000';",
      "final d = currency ?? 'USD';", // a data default: fine
      "// final e = 'Rs 5'; a comment: fine",
      "final f = '$_dollar{Money.format(v)}';", // interpolation: fine
      "final g = '€9';",
    ].join('\n');
    final v = violations('x.dart', src);
    expect(v.map((e) => e.split(':')[1]), ['1', '2', '3', '7']);
  });
}
