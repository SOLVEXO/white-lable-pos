package com.solvexo.solvexo_pos

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Business-verification screens ask for FLAG_SECURE: no screenshots, no screen recording, a blank recent-apps thumbnail.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "solvexo/screen_privacy").setMethodCallHandler { call, result ->
            if (call.method == "setSecure") {
                val secure = call.arguments as? Boolean ?: false
                runOnUiThread {
                    if (secure) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }
}
