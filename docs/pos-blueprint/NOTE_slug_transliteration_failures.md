# Note: 10 failing tests in `solvexo-api/src/common/slug-transliteration.util.spec.ts`

Status: **open, not fixed** (out of scope for G1a/G1b; recorded here so it is not lost). Not POS-related.

* **Failing:** 10 of 20 tests in `src/common/slug-transliteration.util.spec.ts` — every Arabic and Urdu case (`transliterateArabic`, `transliterateUrdu`, `transliterate` for `ar`/`ur`, `createSlug` and `createLocalizedSlug` with Arabic/Urdu). English cases pass.
* **Not caused by our work:** they fail identically on a clean `git stash` of `feature/jamibranch` (verified during G1a, 2026-11-04), so they pre-date G1a.
* **What the failure looks like:** the util returns text with the vowels missing, e.g. `transliterateArabic('السلام')` → `"alslam"`, the spec expects `"alsalam"` (and `كتاب` → `"kitab"`). So either the specs describe a transliteration behaviour (inserting short vowels) that `src/common/slug-transliteration.util.ts` never implemented, or the util was changed later (last touched in `ccd46c4 improve theme customizer, storefront UX, and store access control`) without updating the specs.
* **Impact:** storefront slug generation for Arabic/Urdu product and store names may produce consonant-only slugs. English slugs are unaffected. No POS code path uses it.
* **To decide (product, not engineering):** which output is wanted — then either fix the util or the specs.
* **CI:** `ci.yml` runs `npx jest --runInBand`, so this suite is red there too unless it is excluded; whoever owns the storefront should triage.
