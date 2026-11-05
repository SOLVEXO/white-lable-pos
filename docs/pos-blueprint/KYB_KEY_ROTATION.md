# KYB encryption keys — setup, rotation, fail-closed behaviour

## What is encrypted
CNIC, NTN, IBAN and account title of every store's business verification. AES-256-GCM, a random 12-byte IV per value, Node's built-in `crypto` (no package). Each stored value is `kyb:v<key version>:<iv>:<tag>:<ciphertext>`; the additional authenticated data is `<storeId>:<field>`, so a value copied to another store or field cannot be decrypted.

## Keys (one set per environment — dev, staging, production each have their OWN; never committed, never shared)
| Variable | Meaning |
|---|---|
| `KYB_ENC_KEY_V1`, `KYB_ENC_KEY_V2`, … | one variable per key version, **32 random bytes, base64**. Generate: `openssl rand -base64 32` |
| `KYB_ENC_KEY_CURRENT` | the version used for **new** writes, e.g. `1` |

Read from the environment / your secret store at call time. Store them in the server's secret manager (not in the repo, not in the workflow file); back them up separately from the database — **losing a key makes every value encrypted with it unrecoverable**.

## Fail closed
With no usable key (`KYB_ENC_KEY_CURRENT` unset, that version's key missing, or a key that is not 32 bytes) the KYB endpoints that need it answer **503 `KYB_ENCRYPTION_UNAVAILABLE`** and nothing is stored: a save that touches CNIC/NTN/IBAN/account title is refused as a whole, the admin detail view is refused (and no "viewed" audit row is written for a read that did not happen). Plaintext is never stored. Reads that need no decryption (owner's masked view, admin list, audit trail) keep working.

## First-time setup (per environment)
1. `openssl rand -base64 32` → set `KYB_ENC_KEY_V1`; set `KYB_ENC_KEY_CURRENT=1`; restart the API.
2. Verify: owner saves a draft with a CNIC → in the database `cnicEnc` starts with `kyb:v1:` and the CNIC digits appear nowhere in the document.

## Rotation procedure
Rotate on a schedule you choose (e.g. yearly), and immediately if a key may have leaked.
1. **Add the new key** next to the old one: `KYB_ENC_KEY_V2=<new 32-byte base64>`. Keep `KYB_ENC_KEY_V1`. Set `KYB_ENC_KEY_CURRENT=2`. Restart the API. New writes now use V2; old values still decrypt with V1 (nothing is broken).
2. **Dry run**: `MONGO_URI=… KYB_ENC_KEY_V1=… KYB_ENC_KEY_V2=… KYB_ENC_KEY_CURRENT=2 npm run kyb:rotate-key -- --dry-run`. It reports how many values would be re-encrypted and changes nothing.
3. **Rotate**: the same command without `--dry-run`. It decrypts each value with its old version and re-encrypts it with V2. Idempotent and resumable (run it again any time); each write is guarded on the old ciphertext so a concurrent edit is never overwritten. It writes an audit row (`kyb_key_rotation_run`, counts only). Exit code 1 if any value failed.
4. **Check**: the report shows `remainingOnOldVersions: 0` and `failed: 0`. Spot-check: an admin opens a submission (decrypted values look right).
5. **Retire the old key**: only now remove `KYB_ENC_KEY_V1` from the secret store and restart. (If you remove it early, values still on V1 fail loudly with 503 instead of silently — put the key back and finish step 3.)
6. Keep an offline, access-controlled backup of the retired key for as long as any database backup that contains V1-encrypted values must stay restorable.

## Rollback
Rotation only adds ciphertexts under a newer key; to go back, set `KYB_ENC_KEY_CURRENT` to the old version (the old key is still configured until step 5). Values already re-encrypted with V2 still need V2 to be read, so keep V2 configured.

## Tested
`kyb-field-crypto.spec.ts` (round trip, AAD binding, tamper detection, every missing/invalid-key case, rotation with old key removed early) and `kyb.integration.spec.ts` (rotation over real documents: dry run changes nothing, 4 values re-encrypted to `kyb:v2:`, idempotent second run, admin detail still decrypts after V1 is removed; old key removed too early is reported as `failed`, not skipped; no current key → 503).
