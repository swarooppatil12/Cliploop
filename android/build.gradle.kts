allprojects {
    repositories {
        google()
        mavenCentral()
    }
    // sherpa_onnx 1.13.2 bundles ONNX Runtime 1.24.3 (versioned symbols
    // OrtGetApiBase@VERS_1.24.3). flutter_onnxruntime defaults to
    // onnxruntime-android 1.22.0, whose libonnxruntime4j_jni.so imports
    // OrtGetApiBase@VERS_1.22.0. Since both ship libonnxruntime.so and only one
    // survives packaging (pickFirst), the version mismatch causes
    // UnsatisfiedLinkError at load and aborts ALL plugin registration. Force the
    // matching ORT so a single libonnxruntime.so satisfies both stacks.
    configurations.all {
        resolutionStrategy {
            force("com.microsoft.onnxruntime:onnxruntime-android:1.24.3")
            // Use the QNN-enabled ORT build (adds the QNN Execution Provider for
            // Hexagon NPU). Same 1.24.3 / VERS_1.24.3 symbols as sherpa's bundled
            // libonnxruntime.so, so no link conflict. NOTE: the QNN *backend* libs
            // (libQnnHtp.so + Hexagon vNN skels) are NOT in this AAR — they must be
            // bundled in app/src/main/jniLibs/arm64-v8a from the Qualcomm QAIRT SDK
            // before the QNN provider will actually load (see docs/android-npu-integration.md).
            dependencySubstitution {
                substitute(module("com.microsoft.onnxruntime:onnxruntime-android"))
                    .using(module("com.microsoft.onnxruntime:onnxruntime-android-qnn:1.24.3"))
                    .because("Hexagon NPU acceleration via ORT QNN EP")
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.apply {
            compileSdkVersion(36)
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
        extensions.findByType(com.android.build.gradle.AppExtension::class.java)?.apply {
            compileSdkVersion(36)
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
    }

    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
    }
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
