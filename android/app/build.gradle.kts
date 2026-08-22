plugins {
    id("com.android.application")
    id("kotlin-android")
    // SceneView 4.x exposes ARScene only as a @Composable; neither arsceneview nor
    // sceneview contains an Android View subclass. Rendering the character therefore
    // requires Compose. The plugin and buildFeatures flag below are module-wide, not
    // per-variant: the Compose compiler runs for release too. It emits nothing there,
    // because every Compose dependency and every @Composable is debug-only.
    id("org.jetbrains.kotlin.plugin.compose")
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

    buildFeatures {
        compose = true
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
    // Promoted out of debug: the page scanner ships in release builds. ARCore,
    // SceneView and Compose below stay debug-only, so the release manifest keeps
    // zero AR entries.
    implementation("com.google.android.gms:play-services-mlkit-document-scanner:16.0.0")
    implementation("com.google.mlkit:text-recognition:16.0.1")
    debugImplementation("com.google.ar:core:1.54.0")
    // Pinned to 4.18.0 deliberately: this is the newest arsceneview whose
    // kotlin-stdlib constraint (2.3.21, metadata 2.3.0) the project's Kotlin
    // 2.2.20 compiler can read. 4.19.0+ strictly require kotlin-stdlib 2.4.x,
    // whose 2.4.0 metadata this compiler rejects, which fails the build.
    // Raising this version requires bumping the Kotlin plugin first.
    debugImplementation("io.github.sceneview:arsceneview:4.18.0")
    // arsceneview already brings compose-bom, compose.ui and compose.foundation
    // transitively. This is only for ComponentActivity.setContent.
    debugImplementation("androidx.activity:activity-compose:1.9.3")
    debugImplementation(platform("androidx.compose:compose-bom:2026.05.01"))
    debugImplementation("androidx.compose.ui:ui")
    debugImplementation("androidx.compose.foundation:foundation")
    // buildFeatures.compose is module-wide, so the Compose compiler also runs over the
    // release and profile sources, and it refuses to run without the Compose runtime on
    // the compile classpath. compileOnly satisfies that check for every variant without
    // putting Compose into the release APK: no release or profile source references a
    // @Composable, so nothing is needed at runtime. Keeping this as implementation would
    // ship Compose in release for the sake of a debug-only feature.
    compileOnly(platform("androidx.compose:compose-bom:2026.05.01"))
    compileOnly("androidx.compose.runtime:runtime")
    // buildFeatures.compose is module-wide, so the Compose compiler also runs over the
    // release and profile UNIT TEST sources. compileOnly above does not propagate to the
    // test classpath, and the plugin refuses to run without the runtime on it — which only
    // surfaces once src/test actually contains something to compile.
    testCompileOnly(platform("androidx.compose:compose-bom:2026.05.01"))
    testCompileOnly("androidx.compose.runtime:runtime")
    testImplementation("junit:junit:4.13.2")
}
