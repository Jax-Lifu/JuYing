package com.flytech.juying

import com.flytech.juying.tvbox.TvBoxDexRuntime
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.flytech.juying/tvbox_dex",
        ).setMethodCallHandler(TvBoxDexRuntime(applicationContext))
    }
}
