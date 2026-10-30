// The idempotency key belongs to one user *intent*, not one HTTP attempt: the
// same intent must get the same key on every retry (including after an app
// restart — the key is persisted) until it is released, and a different
// intent must never share a key. See IdempotencyIntentStore.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/idempotency_intent_store.dart';

void main() {
  late DateTime now;
  var counter = 0;

  IdempotencyIntentStore newStore() => IdempotencyIntentStore(
        clock: () => now,
        keyGenerator: () => 'key-${++counter}',
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 1, 1, 12);
    counter = 0;
  });

  test('the same intent gets the same key on every retry', () async {
    final store = newStore();
    final fp = IdempotencyIntentStore.fingerprint('refundSale:s1', {'items': [{'saleItemId': 'a', 'qty': 1}]});
    final first = await store.keyFor(fp);
    expect(await store.keyFor(fp), first);
    expect(await store.keyFor(fp), first);
  });

  test('a different intent (different parameters) gets a different key', () async {
    final store = newStore();
    final one = await store.keyFor(IdempotencyIntentStore.fingerprint('refundSale:s1', {'qty': 1}));
    final two = await store.keyFor(IdempotencyIntentStore.fingerprint('refundSale:s1', {'qty': 2}));
    expect(one, isNot(two));
  });

  test('fingerprint ignores map key order (same intent however it was built)', () {
    expect(
      IdempotencyIntentStore.fingerprint('createSale', {'a': 1, 'b': {'x': 1, 'y': 2}}),
      IdempotencyIntentStore.fingerprint('createSale', {'b': {'y': 2, 'x': 1}, 'a': 1}),
    );
  });

  test('the key survives an app restart (a brand-new store instance reads it back)', () async {
    final fp = IdempotencyIntentStore.fingerprint('createSale', {'total': 20});
    final before = await newStore().keyFor(fp);
    final afterRestart = await newStore().keyFor(fp);
    expect(afterRestart, before);
  });

  test('release makes the next identical action a new intent with a new key', () async {
    final store = newStore();
    final fp = IdempotencyIntentStore.fingerprint('cashAdjustment:s1', {'amount': 20});
    final first = await store.keyFor(fp);
    await store.release(fp);
    expect(await store.keyFor(fp), isNot(first));
  });

  test('an unreleased key expires after the TTL so an unrelated identical action days later is not deduped', () async {
    final store = newStore();
    final fp = IdempotencyIntentStore.fingerprint('createSale', {'total': 20});
    final first = await store.keyFor(fp);
    now = now.add(IdempotencyIntentStore.ttl + const Duration(minutes: 1));
    expect(await store.keyFor(fp), isNot(first));
  });

  test('a corrupt stored blob never blocks a sale — it just starts clean', () async {
    SharedPreferences.setMockInitialValues({'pos_idempotency_intents': 'not json'});
    final key = await newStore().keyFor('x');
    expect(key, startsWith('key-'));
  });
}
