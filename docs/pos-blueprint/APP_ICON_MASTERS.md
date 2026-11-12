# App icon and brand masters (G5.6)

**Receipt logo: not blocked any more.** Each store uploads its own logo (Receipt designer → Logo). The till dithers it into a black-and-white bitmap for its paper width and prints it when "Store logo" is on. The Solvexo brand masters below are only for the **app icon, splash and store listings**.

## Masters needed (from the brand owner / designer)

| File | Size / format | Where it goes | Today |
|---|---|---|---|
| App icon master | **1024×1024 PNG**, opaque, full-bleed, no rounded corners, no text smaller than ~60 px | `assets/icon/app_icon.png` (iOS and Android via `flutter_launcher_icons`) | Placeholder in place, to be confirmed as final |
| Android adaptive foreground | **1024×1024 PNG**, transparent, logo inside the central 66% safe zone | `assets/icon/app_icon_foreground.png` (background colour `#F06839` in `pubspec.yaml`) | Placeholder in place |
| Splash tile | **480×480 PNG** (shown at 120 logical px) | `assets/icon/splash_logo.png` | Placeholder in place |
| Android 12 splash | **960×960 PNG** canvas, tile drawn at 400 px centred | `assets/icon/splash_logo_android12.png` | Placeholder in place |
| Vector master | **SVG** (or PDF/AI) of the wordmark and the symbol | Source for the above, store listing art and the web | Not received |
| Monochrome symbol | **SVG**, single colour | Notification icon (Android), and a possible Solvexo footer on receipts | Not received |

## Once they arrive
1. Replace the four PNGs in `assets/icon/` (same names and sizes).
2. Run `dart run flutter_launcher_icons && dart run flutter_native_splash:create`.
3. Check the generated iOS `AppIcon.appiconset` (1024 px with no alpha) and the Android `mipmap-*` and adaptive icons on a device. Check the splash in light and dark.
4. Commit the generated files together with the masters.
