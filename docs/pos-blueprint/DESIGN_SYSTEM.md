# Solvexo POS design system ("Ink & Ember")

**Status:** consolidated in G6.3. Everything lives in `lib/core/design/`; a screen imports one file:

```dart
import 'package:solvexo_pos/core/design/design.dart';
```

**Source:** Sir Atiq's blueprint package (`Solvexo_POS_UI_Developer_Package`: `design-tokens.json`, `app/index.html`) — coral brand, Manrope for display and figures, DM Sans for text, the 5-tab shell. Dark mode is ours: the blueprint is light-only, so dark is re-based on the brand ink.

**Rule (enforced in CI):** outside `lib/core/design/`, no `Color(0x…)`, `Colors.*` (except `Colors.transparent`), `fontSize:`, `fontFamily:`, `TextStyle(…)`, `AppColors`, `CustomText` or `.sp`. The guard is `test/design_guard_test.dart`. Its baseline (`test/design_guard_baseline.txt`) lists today's violations, may only shrink, and is empty at the end of G6.3. Exceptions go in the test's `allowlist`, each with its reason.

**Gallery:** a debug-only route, `/design-gallery`, shows every token and component in light and dark. There is also a profile entry point: `flutter run --profile -t tool/gallery_main.dart`. Screenshots are in `g6_3_screenshots/gallery/` (`g63_gallery_01_tokens`, `02_buttons`, `03_states`, `04_patterns`, each `_light` / `_dark`).

## 1. Tokens

### Colour — `context.palette` (`tokens/palette.dart`)

Light and dark are two constant instances of one `ThemeExtension`, so a screen never branches on brightness. Every text/background pair is checked at WCAG ≥ 4.5:1 in `test/design_system_test.dart`.

| Token | Use |
|---|---|
| `background` | Page background (warm off-white / near-black) |
| `surface`, `surfaceRaised` | Cards, sheets, dialogs |
| `fill` | Inputs, chips, wells, secondary buttons |
| `border` | Hairlines, card outlines |
| `textPrimary`, `textSecondary`, `textMuted` | Text, in that order of emphasis |
| `accent`, `accentStrong` | Brand coral #DC7758: icons, highlights, selected state, focus. **Never text.** |
| `accentSoft` | Tinted backgrounds (icon tiles, selected chips) |
| `accentFg` | Coral that is safe as text or icon on a surface |
| `accentFill` + `onAccentFill` | Filled primary buttons (#B4553A with white text, 4.88:1) |
| `success` / `warning` / `danger` / `info` | Plus `…Soft` (tint) and `…Fg` (text-safe) for each, and `onDanger` |
| `heroStart`, `heroEnd`, `onHero`, `onHeroMuted` | The dark hero card, in both modes (added in G6.3) |
| `qrLight`, `qrDark` | QR codes: always white with black modules, in dark mode too, because scanners need the contrast (G6.3) |
| `media`, `onMedia`, `onMediaMuted` | Over a camera feed or a photo: the black backdrop and the light text and icons on it (G6.3) |
| `scrim` | Behind sheets and dialogs |

### Typography — `context.type` (`tokens/typography.dart`)

Styles carry no colour; the widget adds one from the palette (`context.type.body.copyWith(color: p.textPrimary)`). Sizes have a tablet step. The OS text scale applies on top, so there is no `.sp`.

| Style | Phone | Tablet | Family / weight |
|---|---|---|---|
| `display` | 32/40 | 40/48 | Manrope 800 |
| `headline` | 24/32 | 28/36 | Manrope 700 |
| `title` | 18/24 | 20/28 | Manrope 700 |
| `subtitle` | 16/22 | 17/24 | DM Sans 600 |
| `body` | 15/22 | 16/24 | DM Sans 400 |
| `bodySmall` | 13/18 | 14/20 | DM Sans 400 |
| `label` | 13/16 | 14/18 | DM Sans 600 |
| `caption` | 12/16 | 12/16 | DM Sans 500 |
| `amountXl` / `amountLg` / `amountMd` | 36 / 24 / 16 | 44 / 28 / 17 | Manrope with tabular figures — **every amount** |
| `amountSm` | 12/16 | 13/18 | Manrope 600, tabular: small figures under a line ("Rs120.00 each") (G6.3) |
| `mono` | 12/16 | 13/18 | The platform's own monospace face (Menlo / Courier / system monospace; no font asset): the thermal-receipt preview's character columns, CSV text, API keys (G6.3) |
| `amountDisplay` | 56/60 | 64/68 | Manrope 700, tabular: the one figure read from a distance (customer-facing QR amount, lock-screen clock) (G6.3) |

Manrope and DM Sans are variable fonts: each style sets the `wght` axis explicitly, because Flutter does not move it from `FontWeight`.

### Spacing, radii, elevation, icons, motion (`tokens/tokens.dart`)

- **Spacing:** `Space.s1`–`s16` (4, 8, 12, 16, 20, 24, 32, 40, 48, 64), plus `Space.gap1…gap8` for `SizedBox`es.
  - The page gutter is `s4`; the gap between sections is `s5`; the gap between rows is `s2`.
  - `Space.minTouch = 48` is the minimum tap target.
- **Radii:** `Radii.sm` 10 (inputs, small wells), `md` 14 (rows, tiles, buttons), `lg` 18 (cards, hero), `xl` 24 (sheets), `full` (pills). Each also has a `BorderRadius` form: `Radii.rSm…rFull`.
- **Elevation:** `AppShadows.soft` (cards), `raised` (sticky bars, floating buttons), `overlay` (sheets, dialogs, toasts). Each takes the brightness, so dark mode uses lighter shadows.
- **Icon sizes (G6.3):** `IconSizes.xxs` 14 / `xs` 16 (inline with captions), `sm` 20 (buttons, chips, quick actions), `md` 22 (list-row tiles), `lg` 28, `xl` 40 (empty and error states).
- **Motion:** `Motion.fast` 120 ms, `base` 200 ms, `slow` 320 ms; the standard and emphasized curves; and `Motion.reduced(context)`, which respects the OS "reduce motion" setting.
- **Breakpoints:** `context.screen`: phone below 600, tablet 600–1100, large 1100 and up. A page caps its content at 720 (lists and forms). The dashboard uses two columns from 680 of content width.

## 2. Components (`components/`)

| Need | Use | Notes |
|---|---|---|
| A pushed screen | `AppPage(title:, body:, actions:, bottom:, banner:)` | App bar on the page background, safe area, 720 width cap. **New in G6.3**, promoted from `InvScaffold`, which now delegates to it. |
| A tab root (Home, Stock, More) | `AppTabPage(title:, subtitle:, trailing:, children:)` | Large title, no back button. Promoted from `HubScaffold`. |
| A titled group of rows | `AppSection(title, rows)` / `SectionHeader(title, actionLabel:)` | Hidden when it has no rows. |
| The app shell | `AppShell` + `AppDestination` | Bottom bar on phones, collapsible rail on tablets. The 5 tabs: Home, Sell, Orders, Stock, More. |
| Buttons | `AppButton(label:, onPressed:, variant:, size:, icon:, loading:, expand:)` | Variants: `primary` (one per view), `secondary`, `ghost` (the text button), `danger` (destructive). At least 48 tall (56 with `lg`). Keeps its width while loading and ignores repeat taps. |
| Cards | `AppCard(child:, onTap:, padding:, radius:, color:, semanticLabel:)` | The only card. Gives one semantic label when tappable. |
| List rows | `AppListRow(icon:, title:, subtitle:, tone:, trailing:, badge:, locked:, onTap:)` | **New in G6.3**, promoted from `HubRow`. The `tone` tints the icon tile: accent for navigation, warning or danger for an alert. A `lock` icon marks an owner-gated row. There is no "coming soon" row: an entry whose screen does not exist is hidden (guarded by `test/no_placeholder_guard_test.dart`). |
| Inputs | `AppTextField(label:, prefixText:, prefixIcon:, suffix:, mono:, …)` | Floating label and error text. `prefixText` (G6.3) puts the currency symbol in front of an amount (`Money.symbol(...)`). `mono` is for code-like input. Tests find fields by `labelText`. |
| Search | `AppSearchBar(hint:, onChanged:, onSubmitted:, onScan:, textCapitalization:, fieldKey:)` | Search icon, clear button, optional scan button. `textCapitalization` and `fieldKey` were added in G6.3, e.g. for receipt numbers. |
| Chips / filters | `AppPill(label:, selected:, onTap:, icon:, trailingIcon:)`; `CategoryChips` for the sale screen's category row | `AppPill` (G6.3) is the filter / toggle pill: 48 dp, accent tint and check mark when selected. Use a `Wrap` of pills. |
| Status pills / badges | `StatusBadge(label, tone:, icon:, dot:)` | Tones: `success` / `warning` / `danger` / `info` / `accent` / `neutral`. The label carries the meaning; colour never does it alone. |
| Figures | `StatTile`, `AppHero(caption:, figure:, footnote:)` | `AppHero` is the dark headline card (**new in G6.3**). |
| Money | `AmountText(Money.format(v), style: context.type.amountMd, color: …)` | Every amount. Tabular figures, rolls when the value changes, `animate: false` in lists. Text always comes from `Money.format` (the currency guard forbids literal symbols). |
| Bottom sheets | `AppBottomSheet.show` / `showGet`, `AppSheetFrame` | Grab handle, xl radius, overlay shadow, keyboard-safe. |
| Dialogs | `AppDialog.show`, `AppDialogCard(title:, message:, content:, actions:)` | Since G6.3 the title, message and content scroll when they don't fit (keyboard up, large text); the actions stay visible. |
| Confirmation | `AppDialog.confirm(context, title:, message:, confirmLabel:, destructive:)` | Destructive actions use `destructive: true`, which gives a danger button with the cancel button first. Money-moving actions need a second step (manager PIN or typed reason), handled by the existing approval sheets. |
| Toasts | `AppToast.success / error / warning / info` | Replaces `Get.snackbar` and the legacy `CustomAppSnackbar`. |
| Empty | `EmptyState(icon:, title:, message:, actionLabel:, onAction:)` | |
| Loading | `SkeletonShimmer` + `SkeletonBox` / `SkeletonList` | Shaped like the content; no centred spinner for page loads. |
| Error | `AppErrorState(message:, onRetry:)` | Danger tone and "Try again". **New in G6.3**, promoted from `InvErrorState`. |
| Offline and notices | `AppBanner.offline()`, `AppBanner(message:, title:, tone:, actionLabel:)` | Inside a page (inset), or full-bleed under an app bar (`inset: false`). Covers offline, "needs the newer server", plan and permission notes. **New in G6.3.** |
| Sale and auth specials | `PinPad`/`PinDots`, `ProductTile`, `QuantityStepper`, `ReceiptPanel`, `FlyToCart`, `BrandLogo`, `BrandPanel`, `GateHeader`, `InkScope`, `PressScale`, `AppNetworkImage`, `GoogleSignInButton` | Already used by the sale flow and the sign-in screens. |

## 3. Page patterns

- **Header:** pushed screens use the `AppPage` app bar; tab roots use the `AppTabPage` large title. There is one primary action per view: a full-width `AppButton` in `AppPage.bottom`, or the first action in a card.
- **States, in this order:**
  1. loading → skeleton;
  2. could not load → `AppErrorState`;
  3. nothing yet → `EmptyState`;
  4. offline → `AppBanner.offline()` above whatever this device last saw, with selling never blocked;
  5. older backend → the feature is simply absent (gated by `ServerCapabilities.has`), never an error.
- **Lists:** `AppListRow`s with an `s2` gap, grouped by `AppSection`.
- **Large text:** readable at text scale 1.3. Rows of side-by-side figures or buttons stack when `MediaQuery.textScalerOf(context).scale(16) > 19`. Figures may scale down (`FittedBox`) but never clip or wrap mid-number.
- **Tablet:** cap the width (720), or use two columns for dashboards and master/detail screens.
- **Dark:** nothing to do per screen when only palette tokens are used.

## 4. Legacy kit (being removed in G6.3)

`AppColors` / `AppBrand` (`lib/config/resources/app_colors.dart`, `lib/core/theme/`), `CustomText`, `CustomAppBarTwo`, `CustomButton`, `LegacyAppButton`, `CustomTextField`, `CustomConfirmDialog`, `CustomBottomSheet`, `CustomAppSnackbar`, `lib/app/components/skeleton.dart`, `NetworkStatusBanner` and `responsive_sizer`'s `.sp`. Each is replaced by the row above that does the same job. Once nothing references them they are deleted, and `UI_CONSISTENCY_AUDIT.md` shows every screen as New.
