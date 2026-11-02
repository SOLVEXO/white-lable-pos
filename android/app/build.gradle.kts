import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// A release build (assemble/bundle/package ...Release) must be signed. Fail EARLY with an actionable message instead of
// Gradle's cryptic "null cannot be cast" when key.properties is absent or incomplete. (Debug builds don't need it.)
gradle.taskGraph.whenReady {
    val releaseRequested = allTasks.any {
        val n = it.name
        (n.startsWith("assemble") || n.startsWith("bundle") || n.startsWith("package")) && n.endsWith("Release")
    }
    if (releaseRequested) {
        if (!keystorePropertiesFile.exists()) {
            throw GradleException(
                "Release signing is not configured: android/key.properties is missing.\n" +
                "Create it (it is git-ignored) with:\n  storePassword=...\n  keyPassword=...\n  keyAlias=...\n  storeFile=/absolute/path/to/upload-keystore.jks\n" +
                "See docs/store_submission_checklist.md (\"Android release signing\")."
            )
        }
        val missing = listOf("storePassword", "keyPassword", "keyAlias", "storeFile").filter { keystoreProperties[it] == null }
        if (missing.isNotEmpty()) throw GradleException("android/key.properties is missing: " + missing.joinToString(", "))
        if (!file(keystoreProperties["storeFile"] as String).exists()) {
            throw GradleException("android/key.properties: storeFile does not exist: " + keystoreProperties["storeFile"])
        }
    }
}

android {
    namespace = "com.solvexo.solvexo_pos"
    // Google Play: new apps and updates must target Android 16 (API 36) from 31 Aug 2026.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
        }
    }

    signingConfigs {
        create("release") {
            // Values are validated above (before any release task runs); a debug build never reads them.
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    defaultConfig {
        applicationId = "com.solvexo.solvexo_pos"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.getByName("release")
            // Upload native symbols + mapping so Crashlytics can de-obfuscate release crashes.
            configure<com.google.firebase.crashlytics.buildtools.gradle.CrashlyticsExtension> {
                mappingFileUploadEnabled = true
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}