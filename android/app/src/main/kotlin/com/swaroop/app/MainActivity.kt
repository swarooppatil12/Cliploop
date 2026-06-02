package com.swaroop.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.tensorflow.lite.Interpreter
import com.qualcomm.qti.QnnDelegate
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors

/**
 * Runs UVR MDX-Net on the Hexagon NPU via TFLite + Qualcomm QNN delegate.
 * The interpreter is created once (init) and reused for every chunk (run) on a
 * single dedicated thread — TFLite/QNN contexts are thread-affine and not
 * thread-safe, so all delegate ops stay on one executor thread.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.swaroop.app/qnn"
    private val exec = Executors.newSingleThreadExecutor()

    private var interpreter: Interpreter? = null
    private var delegate: QnnDelegate? = null
    private var inBuf: ByteBuffer? = null
    private var outBuf: ByteBuffer? = null
    private var ioLen = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "init" -> exec.execute {
                        val r = qnnInit()
                        runOnUiThread { result.success(r) }
                    }
                    "run" -> {
                        val input = call.arguments as? FloatArray
                        exec.execute {
                            val r = qnnRun(input)
                            runOnUiThread {
                                if (r != null) result.success(r)
                                else result.error("QNN_RUN", "run failed (not initialized or bad input)", null)
                            }
                        }
                    }
                    "close" -> exec.execute {
                        qnnClose()
                        runOnUiThread { result.success(true) }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun qnnInit(): Map<String, Any> {
        val out = HashMap<String, Any>()
        if (interpreter != null) { out["ok"] = true; out["reused"] = true; return out }
        try {
            val opts = QnnDelegate.Options().apply {
                setBackendType(QnnDelegate.Options.BackendType.HTP_BACKEND)
                setSkelLibraryDir(applicationInfo.nativeLibraryDir)
                setHtpPerformanceMode(QnnDelegate.Options.HtpPerformanceMode.HTP_PERFORMANCE_BURST)
                setHtpPrecision(QnnDelegate.Options.HtpPrecision.HTP_PRECISION_FP16)
            }
            delegate = QnnDelegate(opts)

            val modelBytes = assets.open("uvr_mdxnet_9482.tflite").readBytes()
            val modelBuf = ByteBuffer.allocateDirect(modelBytes.size).order(ByteOrder.nativeOrder())
            modelBuf.put(modelBytes); modelBuf.rewind()

            val iOpts = Interpreter.Options().apply { addDelegate(delegate) }
            val interp = Interpreter(modelBuf, iOpts)

            ioLen = 1 * 4 * 2048 * 256
            inBuf = ByteBuffer.allocateDirect(ioLen * 4).order(ByteOrder.nativeOrder())
            outBuf = ByteBuffer.allocateDirect(ioLen * 4).order(ByteOrder.nativeOrder())
            interpreter = interp
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
        val result = FloatArray(ioLen)
        ob.asFloatBuffer().get(result)
        return result
    }

    private fun qnnClose() {
        try { interpreter?.close() } catch (_: Throwable) {}
        try { delegate?.close() } catch (_: Throwable) {}
        interpreter = null; delegate = null; inBuf = null; outBuf = null
    }
}
