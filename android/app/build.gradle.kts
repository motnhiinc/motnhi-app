plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.storybookar.storybook_ar"
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
        applicationId = "com.storybookar.storybook_ar"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
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
}

flutter {
    source = "../.."
}

dependencies {
    debugImplementation("com.google.android.gms:play-services-mlkit-document-scanner:16.0.0")
    debugImplementation("com.google.mlkit:text-recognition:16.0.1")
    debugImplementation("com.google.ar:core:1.54.0")
    // Pinned to 4.18.0 deliberately: this is the newest arsceneview whose
    // kotlin-stdlib constraint (2.3.21, metadata 2.3.0) the project's Kotlin
    // 2.2.20 compiler can read. 4.19.0+ strictly require kotlin-stdlib 2.4.x,
    // whose 2.4.0 metadata this compiler rejects, which fails the build.
    // Raising this version requires bumping the Kotlin plugin first.
    debugImplementation("io.github.sceneview:arsceneview:4.18.0")
    testImplementation("junit:junit:4.13.2")
}
