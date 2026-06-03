package com.swaroop.app

import android.content.Context
import android.os.Build
import android.system.Os
import java.io.File
import java.util.Locale

/**
 * Prepares Qualcomm AI Engine Direct (QNN / Hexagon HTP) for ONNX Runtime.
 *
 * QNN replaces legacy NNAPI on Snapdragon — it talks to the NPU directly.
 * Requires libQnn*.so in the APK (see scripts/copy_qnn_android_libs.sh).
 */
object QnnRuntimeHelper {
    private var configured = false

    /** HTP stub/skel suffix for this device, e.g. "V81" for SM8850. */
    fun htpArchSuffix(): String? {
        val soc = (Build.SOC_MODEL ?: "").lowercase(Locale.US)
        return when {
            soc.contains("sm8850") || soc.contains("sm8845") -> "V81"
            soc.contains("sm8750") || soc.contains("sm8735") -> "V79"
            soc.contains("sm8650") || soc.contains("sm8635") -> "V75"
            soc.contains("sm8550") || soc.contains("sm8535") -> "V73"
            soc.contains("sm8475") || soc.contains("sm8450") || soc.contains("sm8350") -> "V69"
            else -> null
        }
    }

    fun configure(context: Context) {
        if (configured) return
        configured = true

        val libDir = context.applicationInfo.nativeLibraryDir ?: return
        val existing = Os.getenv("ADSP_LIBRARY_PATH") ?: ""
        if (!existing.contains(libDir)) {
            val merged = if (existing.isEmpty()) libDir else "$libDir:$existing"
            try {
                Os.setenv("ADSP_LIBRARY_PATH", merged, true)
            } catch (_: Exception) {
                // Non-fatal — QNN may still load from default paths.
            }
        }
    }

    fun qnnLibsPresent(context: Context): Boolean {
        val libDir = File(context.applicationInfo.nativeLibraryDir ?: return false)
        if (!File(libDir, "libQnnHtp.so").exists()) return false
        if (!File(libDir, "libQnnSystem.so").exists()) return false

        val suffix = htpArchSuffix() ?: return true
        val stub = File(libDir, "libQnnHtp${suffix}Stub.so")
        val skel = File(libDir, "libQnnHtp${suffix}Skel.so")
        return stub.exists() && skel.exists()
    }
}
