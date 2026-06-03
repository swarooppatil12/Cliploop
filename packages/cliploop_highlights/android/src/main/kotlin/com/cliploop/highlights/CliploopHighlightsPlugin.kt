package com.cliploop.highlights

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.tensorflow.lite.Interpreter
import com.qualcomm.qti.QnnDelegate
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors

/**
 * Runs the bundled UVR MDX-Net TFLite model on the Hexagon NPU via the Qualcomm
 * QNN delegate. The interpreter is created once (init) and reused per chunk (run)
 * on a single dedicated thread — TFLite/QNN contexts are thread-affine.
 *
 * Dart side: [QnnMdxRuntime] over the "cliploop_highlights/qnn" channel.
 */
class CliploopHighlightsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val main = Handler(Looper.getMainLooper())
    private val exec = Executors.newSingleThreadExecutor()

    private var interpreter: Interpreter? = null
    private var delegate: QnnDelegate? = null
    private var inBuf: ByteBuffer? = null
    private var outBuf: ByteBuffer? = null
    private var ioLen = 0

    private val modelAsset = "uvr_mdxnet_9482.tflite"

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "cliploop_highlights/qnn")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        exec.execute { qnnClose() }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> exec.execute { val r = qnnInit(); main.post { result.success(r) } }
            "run" -> {
                val input = call.arguments as? FloatArray
                exec.execute {
                    val r = qnnRun(input)
                    main.post {
                        if (r != null) result.success(r)
                        else result.error("QNN_RUN", "run failed (not initialized or bad input)", null)
                    }
                }
            }
            "close" -> exec.execute { qnnClose(); main.post { result.success(true) } }
            else -> result.notImplemented()
        }
    }

    private fun qnnInit(): Map<String, Any> {
        val out = HashMap<String, Any>()
        if (interpreter != null) { out["ok"] = true; out["reused"] = true; return out }
        try {
            val opts = QnnDelegate.Options().apply {
                setBackendType(QnnDelegate.Options.BackendType.HTP_BACKEND)
                setSkelLibraryDir(context.applicationInfo.nativeLibraryDir)
                setHtpPerformanceMode(QnnDelegate.Options.HtpPerformanceMode.HTP_PERFORMANCE_BURST)
                setHtpPrecision(QnnDelegate.Options.HtpPrecision.HTP_PRECISION_FP16)
            }
            delegate = QnnDelegate(opts)

            val modelBytes = context.assets.open(modelAsset).readBytes()
            val modelBuf = ByteBuffer.allocateDirect(modelBytes.size).order(ByteOrder.nativeOrder())
            modelBuf.put(modelBytes); modelBuf.rewind()

            val iOpts = Interpreter.Options().apply { addDelegate(delegate) }
            interpreter = Interpreter(modelBuf, iOpts)

            ioLen = 1 * 4 * 2048 * 256
            inBuf = ByteBuffer.allocateDirect(ioLen * 4).order(ByteOrder.nativeOrder())
            outBuf = ByteBuffer.allocateDirect(ioLen * 4).order(ByteOrder.nativeOrder())
            out["ok"] = true
            out["qnnVersion"] = QnnDelegate.getVersion().joinToString(".")
        } catch (e: Throwable) {
            qnnClose()
            out["ok"] = false
            out["error"] = e.javaClass.simpleName + ": " + (e.message ?: "")
        }
        return out
    }

    private fun qnnRun(input: FloatArray?): FloatArray? {
        val interp = interpreter ?: return null
        val ib = inBuf ?: return null
        val ob = outBuf ?: return null
        if (input == null || input.size != ioLen) return null
        ib.rewind(); ib.asFloatBuffer().put(input); ib.rewind()
        ob.rewind()
        interp.run(ib, ob)
        ob.rewind()
        val r = FloatArray(ioLen)
        ob.asFloatBuffer().get(r)
        return r
    }

    private fun qnnClose() {
        try { interpreter?.close() } catch (_: Throwable) {}
        try { delegate?.close() } catch (_: Throwable) {}
        interpreter = null; delegate = null; inBuf = null; outBuf = null
    }
}
