package com.farazlabs.kryvo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager

/**
 * App Lock watcher. Runs as a foreground service (with a small "App Lock is
 * on" notification) while App Lock is enabled. It checks which app is in
 * front a few times per second using Usage Access, and when a locked app
 * comes to the front it shows [AppLockActivity] over it.
 *
 * An app stays unlocked only until the user leaves it (or the screen turns
 * off); after that it asks again.
 */
class AppLockService : Service() {
    companion object {
        private const val CHANNEL = "app_lock"
        private const val NOTIFICATION_ID = 7301
        private const val INTERVAL_MS = 300L

        /** Package unlocked by the user; cleared as soon as they leave it. */
        @Volatile
        var unlockedPkg: String? = null

        fun start(context: Context) {
            val i = Intent(context, AppLockService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(i)
            } else {
                context.startService(i)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, AppLockService::class.java))
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var store: AppLockStore
    private lateinit var usage: UsageStatsManager
    private var foreground: String? = null
    private var lastQuery = 0L
    private var recheck = false

    private fun showLock(pkg: String) {
        startActivity(
            Intent(this, AppLockActivity::class.java)
                .putExtra(AppLockActivity.EXTRA_PKG, pkg)
                .addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_NO_ANIMATION or
                        Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
                )
        )
    }

    private val screenOff = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            // Screen off: everything locks again — including the app that is
            // still open in front when the screen comes back on.
            unlockedPkg = null
            recheck = true
        }
    }

    private val tick = object : Runnable {
        override fun run() {
            try {
                check()
            } catch (_: Exception) {
            }
            handler.postDelayed(this, INTERVAL_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        store = AppLockStore(this)
        usage = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        startForegroundNotification()
        registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF))
        handler.post(tick)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!store.enabled) {
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        try {
            unregisterReceiver(screenOff)
        } catch (_: Exception) {
        }
        super.onDestroy()
    }

    private fun check() {
        if (!store.enabled) {
            stopSelf()
            return
        }
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!pm.isInteractive) return

        val now = System.currentTimeMillis()
        val from = if (lastQuery == 0L) now - 10_000 else lastQuery - 1_000
        lastQuery = now
        val events = usage.queryEvents(from, now)
        val e = UsageEvents.Event()
        var latest: String? = null
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            @Suppress("DEPRECATION")
            if (e.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                latest = e.packageName
            }
        }
        if (recheck) {
            recheck = false
            val cur = latest ?: foreground
            if (cur != null && cur != packageName && cur in store.lockedApps) {
                foreground = cur
                showLock(cur)
                return
            }
        }
        val pkg = latest ?: return
        if (pkg == foreground) return
        foreground = pkg

        // Our own screens (Kryvo or the lock screen) don't count as leaving.
        if (pkg == packageName) return
        if (pkg != unlockedPkg) unlockedPkg = null
        if (pkg in store.lockedApps && pkg != unlockedPkg) showLock(pkg)
    }

    private fun startForegroundNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "App Lock", NotificationManager.IMPORTANCE_MIN)
                    .apply { setShowBadge(false) }
            )
        }
        val open = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName)
                ?: Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val n = builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setContentTitle("App Lock is on")
            .setContentText("Your locked apps are protected")
            .setContentIntent(open)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, n)
        }
    }
}
