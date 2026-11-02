# R8 / ProGuard rules for the release build (minify + shrink are ON).
# Flutter's own rules are added by the Flutter Gradle plugin; most plugins ship consumer rules. Everything below is the
# belt-and-braces set for the plugins this app uses.

# Flutter deferred components reference Play Core, which this app does not bundle.
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**

# flutter_secure_storage (Keystore-backed credentials AND the offline-queue encryption key — losing these = unreadable queue)
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class androidx.security.crypto.** { *; }
-dontwarn com.google.crypto.tink.**
-keep class com.google.crypto.tink.** { *; }

# sqflite (offline queue database) — plugin classes are looked up by the engine
-keep class com.tekartik.sqflite.** { *; }

# print_bluetooth_thermal (receipt printer over Bluetooth) — Bluetooth socket / device reflection
-keep class com.kurenai7968.print_bluetooth_thermal.** { *; }
-keep class android.bluetooth.** { *; }

# mobile_scanner (barcode scanning: CameraX + ML Kit)
-keep class dev.steenbakker.mobile_scanner.** { *; }
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
-keep class androidx.camera.** { *; }

# Firebase / Crashlytics / Google sign-in (keep line numbers so stack traces can be de-obfuscated)
-keepattributes SourceFile,LineNumberTable,*Annotation*,Signature,InnerClasses,EnclosingMethod
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
-keep class androidx.credentials.** { *; }
-keep class com.google.android.libraries.identity.googleid.** { *; }
-keepclassmembers class * { @com.google.firebase.crashlytics.** *; }

# audioplayers, share_plus, image_picker, permission_handler, connectivity_plus, pdf: pure plugin classes with consumer rules.
-keep class xyz.luan.audioplayers.** { *; }
-keep class dev.fluttercommunity.plus.share.** { *; }
