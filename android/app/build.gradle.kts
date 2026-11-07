plugins {
    id("com.android.application")
    id("kotlin-android")
    // SceneView 4.x exposes ARScene only as a @Composable; neither arsceneview nor
    // sceneview contains an Android View subclass. Rendering the character therefore
    // requires Compose, in every build variant — the character reader ships in release.
    id("org.jetbrains.kotlin.plugin.compose")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.motnhi.app"
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
        applicationId = "com.motnhi.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Independent release-build A/B switches; lightest scanning path by default.
        buildConfigField("boolean", "READER_DEPTH_ENABLED",
            providers.gradleProperty("readerDepth").orElse("false").get().toBoolean().toString())
        buildConfigField("boolean", "READER_HDR_ENABLED",
            providers.gradleProperty("readerHdr").orElse("false").get().toBoolean().toString())
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
    testOptions {
        unitTests.isIncludeAndroidResources = true
    }

    // CI supplies a persistent release key; local builds keep the debug fallback.
    val releaseKeystore = System.getenv("ANDROID_KEYSTORE_PATH")
    if (!releaseKeystore.isNullOrBlank()) {
        signingConfigs.create("ciRelease") {
            storeFile = file(releaseKeystore)
            storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("ANDROID_KEY_ALIAS")
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (releaseKeystore.isNullOrBlank()) "debug" else "ciRelease"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.google.guava:guava:33.4.8-android")
    implementation("androidx.camera:camera-camera2:1.4.2")
    implementation("androidx.camera:camera-lifecycle:1.4.2")
    implementation("androidx.camera:camera-view:1.4.2")
    // The page scanner and the ARCore character reader both ship in release builds.
    implementation("com.google.mlkit:text-recognition:16.0.1")
    implementation("androidx.exifinterface:exifinterface:1.3.7")
    implementation("com.google.ar:core:1.54.0")
    // Pinned to 4.18.0 deliberately: this is the newest arsceneview whose
    // kotlin-stdlib constraint (2.3.21, metadata 2.3.0) the project's Kotlin
    // 2.2.20 compiler can read. 4.19.0+ strictly require kotlin-stdlib 2.4.x,
    // whose 2.4.0 metadata this compiler rejects, which fails the build.
    // Raising this version requires bumping the Kotlin plugin first.
    implementation("io.github.sceneview:arsceneview:4.18.0")
    // arsceneview already brings compose-bom, compose.ui and compose.foundation
    // transitively. This is only for ComponentActivity.setContent.
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation(platform("androidx.compose:compose-bom:2026.05.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16")
    testImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
