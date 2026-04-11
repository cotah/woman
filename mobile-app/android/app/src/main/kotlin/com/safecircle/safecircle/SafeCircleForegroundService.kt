package com.safecircle.safecircle

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * SafeCircle Always-On Foreground Service
 *
 * This service keeps the app running 24/7 in the background after the user
 * activates it during onboarding. It:
 * - Displays a persistent notification so the OS doesn't kill the process
 * - Acquires a partial wake lock so the CPU stays active for voice detection
 * - Auto-restarts if the system kills it (START_STICKY)
 *
 * The user explicitly authorizes this in the onboarding flow, understanding
 * that all data is encrypted and no information is leaked.
 */
class SafeCircleForegroundService : Service() {

    companion object {
        private const val TAG = "SafeCircleFG"
        private const val CHANNEL_ID = "safecircle_always_on"
        private const val NOTIFICATION_ID = 9001
        private const val WAKELOCK_TAG = "SafeCircle::AlwaysOn"

        fun start(context: Context, title: String, body: String) {
            val intent = Intent(context, SafeCircleForegroundService::class.java).apply {
                putExtra("title", title)
                putExtra("body", body)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, SafeCircleForegroundService::class.java))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        acquireWakeLock()
        Log.i(TAG, "SafeCircle foreground service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: "SafeCircle Active"
        val body = intent?.getStringExtra("body")
            ?: "Your safety guardian is running. All data is encrypted."

        val notification = buildNotification(title, body)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION or
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        Log.i(TAG, "SafeCircle foreground service started: $title")

        // START_STICKY = restart the service if the system kills it
        return START_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        Log.i(TAG, "SafeCircle foreground service destroyed")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTaskRemoved(rootIntent: Intent?) {
        // If the user swipes the app away, reschedule the service
        Log.w(TAG, "Task removed — scheduling restart")
        val restartIntent = Intent(this, SafeCircleForegroundService::class.java).apply {
            putExtra("title", "SafeCircle Active")
            putExtra("body", "Your safety guardian is running. All data is encrypted.")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(restartIntent)
        } else {
            startService(restartIntent)
        }
        super.onTaskRemoved(rootIntent)
    }

    // ── Notification ──────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "SafeCircle Protection",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Persistent notification while SafeCircle is protecting you"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_SECRET
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(title: String, body: String): Notification {
        // Tapping the notification opens the app
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(pendingIntent)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .build()
    }

    // ── Wake Lock ─────────────────────────────────────

    private fun acquireWakeLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            WAKELOCK_TAG
        ).apply {
            acquire()  // Indefinite — released on service destroy
        }
        Log.d(TAG, "Wake lock acquired")
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
                Log.d(TAG, "Wake lock released")
            }
        }
        wakeLock = null
    }
}
