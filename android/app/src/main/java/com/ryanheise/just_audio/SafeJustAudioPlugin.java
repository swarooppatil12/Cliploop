package com.ryanheise.just_audio;

import android.content.Context;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;

/**
 * just_audio registers its MethodChannel then may NPE on {@code binding.getFlutterEngine()}
 * (null on Flutter 3.27+), which aborts plugin attach and breaks playback/upload flows.
 */
public class SafeJustAudioPlugin implements FlutterPlugin {
    private MethodChannel channel;
    private MainMethodCallHandler methodCallHandler;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        Context applicationContext = binding.getApplicationContext();
        BinaryMessenger messenger = binding.getBinaryMessenger();
        methodCallHandler = new MainMethodCallHandler(applicationContext, messenger);

        channel = new MethodChannel(messenger, "com.ryanheise.just_audio.methods");
        channel.setMethodCallHandler(methodCallHandler);

        @SuppressWarnings("deprecation")
        FlutterEngine engine = binding.getFlutterEngine();
        if (engine != null) {
            engine.addEngineLifecycleListener(new FlutterEngine.EngineLifecycleListener() {
                @Override
                public void onPreEngineRestart() {
                    methodCallHandler.dispose();
                }

                @Override
                public void onEngineWillDestroy() {
                }
            });
        }
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (methodCallHandler != null) {
            methodCallHandler.dispose();
            methodCallHandler = null;
        }
        if (channel != null) {
            channel.setMethodCallHandler(null);
        }
    }
}
