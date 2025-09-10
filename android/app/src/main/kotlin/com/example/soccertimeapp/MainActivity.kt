package com.example.soccertimeapp

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "soccertime/foreground"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startTimer" -> {
                    val matchTime = call.argument<Int>("matchTime") ?: 0
                    val period = call.argument<Int>("period") ?: 1
                    val isPaused = call.argument<Boolean>("isPaused") ?: false
                    val alertTimeSeconds = call.argument<Int>("alertTimeSeconds") ?: 5
                    
                    val intent = Intent(this, NotificationService::class.java).apply {
                        action = NotificationService.ACTION_START_TIMER
                        putExtra(NotificationService.EXTRA_MATCH_TIME, matchTime)
                        putExtra(NotificationService.EXTRA_PERIOD, period)
                        putExtra(NotificationService.EXTRA_IS_PAUSED, isPaused)
                        putExtra(NotificationService.EXTRA_ALERT_TIME, alertTimeSeconds)
                    }
                    startForegroundService(intent)
                    result.success(true)
                }
                "pauseTimer" -> {
                    val intent = Intent(this, NotificationService::class.java).apply {
                        action = NotificationService.ACTION_PAUSE_TIMER
                    }
                    startService(intent)
                    result.success(true)
                }
                "resumeTimer" -> {
                    val intent = Intent(this, NotificationService::class.java).apply {
                        action = NotificationService.ACTION_START_TIMER
                    }
                    startService(intent)
                    result.success(true)
                }
                "stopTimer" -> {
                    val intent = Intent(this, NotificationService::class.java).apply {
                        action = NotificationService.ACTION_STOP_TIMER
                    }
                    startService(intent)
                    result.success(true)
                }
                "updateTimer" -> {
                    val matchTime = call.argument<Int>("matchTime") ?: 0
                    val period = call.argument<Int>("period") ?: 1
                    val isPaused = call.argument<Boolean>("isPaused") ?: false
                    
                    val intent = Intent(this, NotificationService::class.java).apply {
                        action = "UPDATE_TIMER"
                        putExtra(NotificationService.EXTRA_MATCH_TIME, matchTime)
                        putExtra(NotificationService.EXTRA_PERIOD, period)
                        putExtra(NotificationService.EXTRA_IS_PAUSED, isPaused)
                    }
                    startService(intent)
                    result.success(true)
                }
                "startPeriodEndAlert" -> {
                    val intent = Intent(this, NotificationService::class.java).apply {
                        action = NotificationService.ACTION_PERIOD_END_ALERT
                    }
                    startService(intent)
                    result.success(true)
                }
                "stopPeriodEndAlert" -> {
                    val intent = Intent(this, NotificationService::class.java).apply {
                        action = "STOP_PERIOD_END_ALERT"
                    }
                    startService(intent)
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
