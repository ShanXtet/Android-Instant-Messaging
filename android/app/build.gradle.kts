plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.study1"

    // Flutter template variables are fine; just ensure compile/target are recent.
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.example.study1"

        // ⚠️ Make sure minSdk >= 21 for flutter_local_notifications
        // If flutter.minSdkVersion < 21, override it explicitly:
         minSdk = flutter.minSdkVersion
       // minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // ✅ Enable Java desugaring
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true   // <-- IMPORTANT
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    buildTypes {
        release {
            // keep debug signing for now
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ✅ Add the desugaring library
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // (Other dependencies injected by Flutter stay as-is)
}
