// G6.3: the app honours OS text scaling up to 1.3 (raised from 1.2 at the end of the restyle; every screen was checked at 1.3) — the cap
// stays, and main.dart's MaterialApp builder clamps with it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solvexo_pos/main.dart' show kMaxTextScale;

void main() {
  test('the text-scale cap is 1.3 and the app builder clamps OS text scaling to 0.9–kMaxTextScale', () {
    expect(kMaxTextScale, 1.3);
    final src = File('lib/main.dart').readAsStringSync();
    expect(src, contains('mq.textScaler.scale(1).clamp(0.9, kMaxTextScale)'));
    expect(src.contains('clamp(0.9, 1.2)'), isFalse);
  });
}
