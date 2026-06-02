package com.swaroop.app

import android.os.Build
import android.os.Bundle
import com.ryanheise.just_audio.SafeJustAudioPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        QnnRuntimeHelper.configure(applicationContext)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Re-register just_audio with a null-safe plugin (see SafeJustAudioPlugin).
        flutterEngine.plugins.add(SafeJustAudioPlugin())

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "com.swaroop.app/paths").setMethodCallHandler { call, result ->
            when (call.method) {
                "getAppDocumentsPath" -> result.success(filesDir.absolutePath)
                "getAppSupportPath" -> {
                    val support = applicationContext.filesDir
                    result.success(support.absolutePath)
                }
                "getAppCachePath" -> result.success(cacheDir.absolutePath)
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "com.swaroop.app/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceProfile" -> {
                    result.success(
                        mapOf(
                            "isSnapdragon" to isSnapdragon(),
                            "socModel" to (Build.SOC_MODEL ?: ""),
                            "hardware" to Build.HARDWARE,
                            "board" to Build.BOARD,
                            "qnnHtpArch" to (QnnRuntimeHelper.htpArchSuffix() ?: ""),
                            "hasQnnLibs" to QnnRuntimeHelper.qnnLibsPresent(applicationContext),
                        ),
                    )
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Detect Qualcomm Snapdragon SoCs for QNN / Hexagon HTP acceleration. */
    private fun isSnapdragon(): Boolean {
        val soc = (Build.SOC_MODEL ?: "").lowercase(Locale.US)
        val hardware = Build.HARDWARE.lowercase(Locale.US)
        val board = Build.BOARD.lowercase(Locale.US)

        if (soc.contains("snapdragon")) return true
        if (soc.matches(Regex("sm[0-9a-z]+"))) return true
        if (hardware.contains("qcom") || hardware.startsWith("qcom")) return true

        val qcomBoards = listOf(
            "lahaina", "taro", "kalama", "pineapple", "sun", "parrot",
            "crow", "canoe", "bonito", "blueline", "crosshatch", "coral",
            "flame", "redfin", "barbet", "bramble", "sunfish", "kona", "m3q",
        )
        if (qcomBoards.any { board.contains(it) }) return true

        return false
    }
}
