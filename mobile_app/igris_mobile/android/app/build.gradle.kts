plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.igris_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Enable core library desugaring for plugins that require it
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.igris_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Porcupine / pvrecorder require minSdk 23+ (Android 6.0).
        // flutter_foreground_task requires minSdk 23+.
        minSdk = maxOf(23, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Match the .ppn model with 16 kHz mono PCM.
        ndk {
            abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a", "x86_64"))
        }
        // Porcupine + flutter_foreground_task ship a few large .aar libs.
        multiDexEnabled = true
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // TFLite for the on-device "Hey IGRIS" wake word detector. We pin a
    // specific minor version to avoid surprise SDK breakage on AGP 8.x.
    // The InterpreterApi is the modern, AAR-shipped entry point.
    implementation("org.tensorflow:tensorflow-lite:2.14.0")
    // TFLite support includes the Java/Kotlin metadata helpers used by
    // WakeWordEngine to read the input/output tensor shapes.
    implementation("org.tensorflow:tensorflow-lite-support:0.4.4")
}
