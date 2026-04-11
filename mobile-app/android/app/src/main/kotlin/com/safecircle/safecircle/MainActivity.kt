package com.safecircle.safecircle

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Main activity bridging Flutter (Dart) with native Android services.
 *
 * Exposes a MethodChannel at "com.safecircle.app/background" that the
 * Dart BackgroundService calls to start/stop the foreground service and
 * request battery optimization exemption.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.safecircle.app/background"
        private const val TAG = "SafeCircleMain"
        private const val PREF_KEY = "safecircle_always_on_enabled"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startForegroundService" -> {
                        val title = call.argument<String>("title") ?: "SafeCircle Active"
                        val body = call.argument<String>("body")
                            ?: "Your safety guardian is running. All data is encrypted."

                        try {
                            SafeCircleForegroundService.start(this, title, body)
                            // Persist preference so BootReceiver knows to restart
                            getSharedPreferences("safecircle_prefs", Context.MODE_PRIVATE)
                                .edit()
                                .putBoolean(PREF_KEY, true)
                                .apply()
                            Log.i(TAG, "Foreground service started from Flutter")
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to start foreground service", e)
                            result.error("SERVICE_ERROR", e.message, null)
                        }
                    }

                    "stopForegroundService" -> {
                        try {
                            SafeCircleForegroundService.stop(this)
                            getSharedPreferences("safecircle_prefs", Context.MODE_PRIVATE)
                                .edit()
                                .putBoolean(PREF_KEY, false)
                                .apply()
                            Log.i(TAG, "Foreground service stopped from Flutter")
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to stop foreground service", e)
                            result.error("SERVICE_ERROR", e.message, null)
                        }
                    }

                    "isServiceRunning" -> {
                        val prefs = getSharedPreferences("safecircle_prefs", Context.MODE_PRIVATE)
                        result.success(prefs.getBoolean(PREF_KEY, false))
                    }

                    "requestBatteryOptimizationExemption" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                                if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                                    val intent = Intent(
                                        Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                        Uri.parse("package:$packageName")
                                    )
                                    startActivity(intent)
                                    result.success(false) // Will be true after user accepts
                                } else {
                                    result.success(true) // Already exempted
                                }
                            } else {
                                result.success(true) // Not needed on older Android
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to request battery optimization", e)
                            result.error("BATTERY_ERROR", e.message, null)
                        }
                    }

                    "isBatteryOptimizationExempt" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                            result.success(pm.isIgnoringBatteryOptimizations(packageName))
                        } else {
                            result.success(true)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
