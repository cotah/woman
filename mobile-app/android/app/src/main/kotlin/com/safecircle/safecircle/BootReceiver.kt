package com.safecircle.safecircle

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Receives BOOT_COMPLETED broadcast and restarts the foreground service
 * if the user had it enabled before the device was rebooted.
 *
 * Also handles MY_PACKAGE_REPLACED to restart after app updates.
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SafeCircleBoot"
        private const val PREF_KEY = "safecircle_always_on_enabled"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {

            val prefs = context.getSharedPreferences("safecircle_prefs", Context.MODE_PRIVATE)
            val isEnabled = prefs.getBoolean(PREF_KEY, false)

            if (isEnabled) {
                Log.i(TAG, "Device booted / app updated — restarting SafeCircle service")
                SafeCircleForegroundService.start(
                    context,
                    "SafeCircle Active",
                    "Your safety guardian is running. All data is encrypted."
                )
            } else {
                Log.d(TAG, "Device booted but always-on not enabled — skipping")
            }
        }
    }
}
