plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.swaroop.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.swaroop.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 34
        multiDexEnabled = true
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // R8 minify breaks ONNX / sherpa / ffmpeg on release; keep full bytecode.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // sherpa_onnx (Silero SVAD) and flutter_onnxruntime (UVR MDX-NET) both bundle
    // libonnxruntime.so — pick one copy so mergeDebugNativeLibs succeeds.
    packaging {
        jniLibs {
            pickFirsts += listOf(
                "**/libonnxruntime.so",
                "**/libonnxruntime4j_jni.so",
                "**/libc++_shared.so",
            )
            // QNN Hexagon skel libs (libQnnHtpV*Skel.so) are loaded onto the DSP
            // from a filesystem path, so the native libs must be extracted at
            // install rather than mmap'd from the APK. Harmless when QNN is unused.
            useLegacyPackaging = true
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // TFLite runtime + Qualcomm QNN delegate for Hexagon NPU acceleration.
    // Classic org.tensorflow:tensorflow-lite (not com.google.ai.edge.litert) because
    // it cleanly EXPORTS org.tensorflow.lite.{Interpreter,Delegate} (which QnnDelegate
    // implements) and is pure Java (no Kotlin-metadata version conflict). qnn-runtime
    // bundles the matched Hexagon backend libs (incl. v81 for sm8850) — no manual QAIRT.
    implementation("org.tensorflow:tensorflow-lite:2.17.0")
    implementation("com.qualcomm.qti:qnn-runtime:2.46.0")
    implementation("com.qualcomm.qti:qnn-litert-delegate:2.46.0")
}
