plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.saathi_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.saathi_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Shareable APK name (matches launcher label Saathi_V1).
    base {
        archivesName = "Saathi_V1"
    }
}

flutter {
    source = "../.."
}

// After release build, mirror Gradle's named APK as Saathi_V1.apk for sharing.
// Use configureEach so debug-only invocations do not fail if release task is absent.
tasks.matching { it.name == "assembleRelease" }.configureEach {
    doLast {
        val namedApk =
            layout.buildDirectory
                .get()
                .asFile
                .resolve("outputs/apk/release/Saathi_V1-release.apk")
        val dest =
            layout.buildDirectory
                .get()
                .asFile
                .resolve("outputs/flutter-apk/Saathi_V1.apk")
        if (namedApk.isFile) {
            dest.parentFile?.mkdirs()
            namedApk.copyTo(dest, overwrite = true)
        }
    }
}
