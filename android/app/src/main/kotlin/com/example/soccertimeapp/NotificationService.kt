package com.example.soccertimeapp

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class NotificationService : Service() {
    companion object {
        const val CHANNEL_ID = "SoccerTimeForegroundService"
        const val NOTIFICATION_ID = 1
        const val VIBRATION_CHANNEL_ID = "VibrationChannel"
        const val VIBRATION_NOTIFICATION_ID = 2
        
        const val ACTION_START_TIMER = "START_TIMER"
        const val ACTION_PAUSE_TIMER = "PAUSE_TIMER"
        const val ACTION_STOP_TIMER = "STOP_TIMER"
        const val ACTION_PERIOD_END_ALERT = "PERIOD_END_ALERT"
        const val ACTION_UPDATE_TIMER = "UPDATE_TIMER"
        const val ACTION_STOP_PERIOD_END_ALERT = "STOP_PERIOD_END_ALERT"
        
        const val EXTRA_MATCH_TIME = "MATCH_TIME"
        const val EXTRA_PERIOD = "PERIOD"
        const val EXTRA_IS_PAUSED = "IS_PAUSED"
        const val EXTRA_ALERT_TIME = "ALERT_TIME"
    }

    private lateinit var notificationManager: NotificationManager
    private lateinit var vibrator: Vibrator
    private var isTimerRunning = false
    private var currentMatchTime = 0
    private var currentPeriod = 1
    private var isPaused = false
    private var alertTime = 0
    private var isAlerting = false

    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            vibratorManager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }

        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        // Main notification channel
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Soccer Timer Service",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Keeps the soccer timer running in the background"
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        notificationManager.createNotificationChannel(channel)

        // Vibration alert channel
        val vibrationChannel = NotificationChannel(
            VIBRATION_CHANNEL_ID,
            "Timer Alerts",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Period end and timer alerts"
            enableVibration(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        notificationManager.createNotificationChannel(vibrationChannel)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_TIMER -> {
                currentMatchTime = intent.getIntExtra(EXTRA_MATCH_TIME, 0)
                currentPeriod = intent.getIntExtra(EXTRA_PERIOD, 1)
                isPaused = intent.getBooleanExtra(EXTRA_IS_PAUSED, false)
                alertTime = intent.getIntExtra(EXTRA_ALERT_TIME, 5) // 5 seconds before period end
                startTimer()
            }
            ACTION_PAUSE_TIMER -> {
                pauseTimer()
            }
            ACTION_STOP_TIMER -> {
                stopTimer()
            }
            ACTION_PERIOD_END_ALERT -> {
                startPeriodEndAlert()
            }
            ACTION_UPDATE_TIMER -> {
                currentMatchTime = intent.getIntExtra(EXTRA_MATCH_TIME, currentMatchTime)
                currentPeriod = intent.getIntExtra(EXTRA_PERIOD, currentPeriod)
                isPaused = intent.getBooleanExtra(EXTRA_IS_PAUSED, isPaused)
                updateNotification()
            }
            ACTION_STOP_PERIOD_END_ALERT -> {
                stopPeriodEndAlert()
            }
        }

        return START_STICKY // Restart service if killed
    }

    private fun startTimer() {
        isTimerRunning = true
        isPaused = false
        startForeground(NOTIFICATION_ID, createTimerNotification())
        startPeriodEndAlert()
    }

    private fun pauseTimer() {
        isPaused = true
        updateNotification()
    }

    private fun stopTimer() {
        isTimerRunning = false
        isPaused = false
        isAlerting = false
        stopForeground(true)
        stopSelf()
    }

    private fun startPeriodEndAlert() {
        if (!isTimerRunning || isPaused) return

        // Calculate when to start alerting (5 seconds before period end)
        val periodDuration = 45 * 60 // 45 minutes in seconds
        val alertStartTime = periodDuration - alertTime

        // Start a timer to begin alerting
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            if (isTimerRunning && !isPaused) {
                startVibrationAlert()
            }
        }, (alertStartTime * 1000).toLong())
    }

    private fun stopPeriodEndAlert() {
        isAlerting = false
        notificationManager.cancel(VIBRATION_NOTIFICATION_ID)
    }

    private fun startVibrationAlert() {
        isAlerting = true
        
        // Create high-priority notification for vibration
        val alertNotification = NotificationCompat.Builder(this, VIBRATION_CHANNEL_ID)
            .setContentTitle("Period Ending Soon!")
            .setContentText("Period ${currentPeriod} will end in ${alertTime} seconds")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(false)
            .setOngoing(true)
            .build()

        notificationManager.notify(VIBRATION_NOTIFICATION_ID, alertNotification)

        // Start vibrating every second
        val vibrationRunnable = object : Runnable {
            override fun run() {
                if (isAlerting && isTimerRunning && !isPaused) {
                    vibrate()
                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(this, 1000)
                }
            }
        }
        android.os.Handler(android.os.Looper.getMainLooper()).post(vibrationRunnable)
    }

    private fun vibrate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val vibrationEffect = VibrationEffect.createOneShot(500, VibrationEffect.DEFAULT_AMPLITUDE)
            vibrator.vibrate(vibrationEffect)
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(500)
        }
    }

    private fun createTimerNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val pauseIntent = Intent(this, NotificationService::class.java).apply {
            action = ACTION_PAUSE_TIMER
        }
        val pausePendingIntent = PendingIntent.getService(
            this, 1, pauseIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, NotificationService::class.java).apply {
            action = ACTION_STOP_TIMER
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 2, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val statusText = if (isPaused) "Paused" else "Running"
        val timeText = formatTime(currentMatchTime)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Soccer Timer - Period $currentPeriod")
            .setContentText("$timeText - $statusText")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(pendingIntent)
            .addAction(android.R.drawable.ic_media_pause, "Pause", pausePendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
    }

    private fun updateNotification() {
        if (isTimerRunning) {
            notificationManager.notify(NOTIFICATION_ID, createTimerNotification())
        }
    }

    private fun formatTime(seconds: Int): String {
        val minutes = seconds / 60
        val remainingSeconds = seconds % 60
        return String.format("%02d:%02d", minutes, remainingSeconds)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        isAlerting = false
        notificationManager.cancelAll()
    }
}
