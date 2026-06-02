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
            // Align ORT to sherpa's bundled libonnxruntime.so (VERS_1.24.3) to avoid
            // the UnsatisfiedLinkError/OrtGetApiBase symbol-version conflict that
            // otherwise aborts all plugin registration. (Stock ORT keeps XNNPACK;
            // NPU acceleration is handled separately via the LiteRT QNN delegate.)
            force("com.microsoft.onnxruntime:onnxruntime-android:1.24.3")
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
