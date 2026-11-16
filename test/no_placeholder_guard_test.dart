// G6.3 guard: no "Coming soon" / "Soon" placeholder entry anywhere in lib/. An entry whose screen exists links to it; one whose screen does not
// exist is hidden. (A feature the server reports as off — "Not available yet: …" — is a state, not a placeholder entry, and is allowed.)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _placeholder = RegExp(r'''['"](?:[^'"]*\bcoming soon\b[^'"]*|soon)['"]''', caseSensitive: false);

List<String> placeholders(String path, String src) {
  final out = <String>[];
  final lines = src.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i].trimLeft();
    if (l.startsWith('//')) continue;
    if (_placeholder.hasMatch(lines[i])) out.add('$path:${i + 1}: ${l.trim()}');
  }
  return out;
}

void main() {
  test('the rule catches placeholder labels and nothing else', () {
    expect(placeholders('x', "const StatusBadge('Soon')"), hasLength(1));
    expect(placeholders('x', "HubSection('Coming soon', [])"), hasLength(1));
    expect(placeholders('x', "Text('Feature coming soon to your store')"), hasLength(1));
    expect(placeholders('x', "subtitle: 'Reorder soon'"), isEmpty);
    expect(placeholders('x', "StatusBadge('Expiring soon')"), isEmpty);
    expect(placeholders('x', "// a comment about Coming soon"), isEmpty);
  });

  test('no "Coming soon" or "Soon" placeholder text in lib/ (it would ship in a release build)', () {
    final found = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      found.addAll(placeholders(f.path.replaceAll(r'\', '/'), f.readAsStringSync()));
    }
    expect(found, isEmpty, reason: found.join('\n'));
  });
}
