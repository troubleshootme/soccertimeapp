import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import '../providers/app_state.dart';
import 'package:meta/meta.dart';

@pragma('vm:entry-point')
class BackgroundService {
  static const String BACKGROUND_ENABLED_KEY = 'background_service_enabled';
  static const int PERIOD_END_ALARM_ID = 42; // Unique ID for our period end alarm
  
  // Singleton instance
  @pragma('vm:entry-point')
  static final BackgroundService _instance = BackgroundService._internal();
  
  @pragma('vm:entry-point')
  factory BackgroundService() => _instance;
  
  @pragma('vm:entry-point')
  BackgroundService._internal();

  bool _isInitialized = false;
  bool _isRunning = false;
  Timer? _backgroundTimer;
  Timer? _reminderVibrationTimer; // Add timer for periodic vibration reminders
  int? _lastBackgroundTimestamp;
  bool _periodEndDetected = false;
  bool _matchEndDetected = false;

  // Background service configuration for Android
  final androidConfig = const FlutterBackgroundAndroidConfig(
    notificationTitle: 'Soccer Time App',
    notificationText: 'Timers are running in the background',
    notificationImportance: AndroidNotificationImportance.max,
    notificationIcon: const AndroidResource(
      name: 'ic_notification',
      defType: 'drawable',
    ),
    enableWifiLock: false,
  );

  // Initialize background service
  @pragma('vm:entry-point')
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    print("Initializing background service...");
    
    // Request Android permissions explicitly
    await _requestPermissions();
    
    // Initialize Android Alarm Manager
    await AndroidAlarmManager.initialize();
    
    // Check if the device supports background execution
    bool hasPermissions = await FlutterBackground.hasPermissions;
    print("Background permissions check: $hasPermissions");
    if (!hasPermissions) {
      print("No background execution permissions");
      return false;
    }
    
    // Initialize the background service
    print("Calling FlutterBackground.initialize with config...");
    final success = await FlutterBackground.initialize(androidConfig: androidConfig);
    print("Background service initialization result: $success");
    _isInitialized = success;
    return success;
  }
  
  // Request Android permissions needed for foreground service
  Future<void> _requestPermissions() async {
    print("Requesting necessary Android permissions...");
    
    // Request notification permission for Android 13+
    final notificationStatus = await Permission.notification.request();
    print("Notification permission status: $notificationStatus");
    
    // Request post notifications permission explicitly
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
    
    // For foreground service
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  // Start the background service
  @pragma('vm:entry-point')
  Future<bool> startBackgroundService() async {
    print("startBackgroundService called, initialized: $_isInitialized");
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        print("Failed to initialize background service");
        return false;
      }
    }
    
    if (!_isRunning) {
      print("Enabling background execution...");
      final success = await FlutterBackground.enableBackgroundExecution();
      print("Enable background execution result: $success");
      if (success) {
        _isRunning = true;
        // Save the state to preferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(BACKGROUND_ENABLED_KEY, true);
        print('Background service started successfully');
      } else {
        print('Failed to start background service');
      }
      return success;
    }
    
    print("Background service already running");
    return true; // Already running
  }

  // Stop the background service
  Future<bool> stopBackgroundService() async {
    if (_isRunning) {
      final success = await FlutterBackground.disableBackgroundExecution();
      if (success) {
        _isRunning = false;
        // Save the state to preferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(BACKGROUND_ENABLED_KEY, false);
        debugPrint('Background service stopped successfully');
      } else {
        debugPrint('Failed to stop background service');
      }
      return success;
    }
    
    return true; // Already stopped
  }

  // Check if the background service is running
  bool get isRunning => _isRunning;
  
  // Check if a period end was detected while in background
  bool get periodEndDetected => _periodEndDetected;
  
  // Check if match end was detected while in background
  bool get matchEndDetected => _matchEndDetected;
  
  // Reset event flags
  void resetEventFlags() {
    _periodEndDetected = false;
    _matchEndDetected = false;
    
    // Cancel any existing reminder vibration timer
    _reminderVibrationTimer?.cancel();
    _reminderVibrationTimer = null;
  }

  // Restore previous state of background service on app launch
  Future<void> restorePreviousState() async {
    final prefs = await SharedPreferences.getInstance();
    final wasEnabled = prefs.getBool(BACKGROUND_ENABLED_KEY) ?? false;
    
    if (wasEnabled) {
      await startBackgroundService();
    }
  }

  @pragma('vm:entry-point')
  void startBackgroundTimer(AppState appState) {
    // Cancel any existing background timer to avoid duplicates
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    
    // Reset event flags
    _periodEndDetected = false;
    _matchEndDetected = false;
    
    // Store initial timestamp when starting the background timer
    _lastBackgroundTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    
    // Very important: Update appState's lastUpdateTime to match our start time
    // This ensures synchronization between foreground and background timers
    appState.session.lastUpdateTime = _lastBackgroundTimestamp;
    
    print("--- BG Timer Starting ---");
    print("  Timestamp (s) : $_lastBackgroundTimestamp");
    print("  Match Time    : ${appState.session.matchTime}");
    print("  Period        : ${appState.session.currentPeriod}/${appState.session.matchSegments}");
    
    // Calculate period end time and schedule alarm
    final periodDuration = appState.session.matchDuration ~/ appState.session.matchSegments;
    final currentPeriodEndTime = periodDuration * appState.session.currentPeriod;
    
    print("Current period end time: $currentPeriodEndTime (running period ${appState.session.currentPeriod})");
    
    // If we're already past period end time, force end period immediately
    if (appState.session.matchTime >= currentPeriodEndTime && 
        appState.session.enableMatchDuration && 
        !appState.session.hasWhistlePlayed &&
        appState.session.currentPeriod < appState.session.matchSegments) {
      print("Match time already past period end, forcing period end");
      appState.session.matchTime = currentPeriodEndTime;
      _periodEndDetected = true;
      appState.endPeriod();
      appState.session.isPaused = true;
      appState.session.matchRunning = false;
      return;
    }
    
    // Update notification with initial match information
    _updateBackgroundNotification(
      _getMatchTimeNotificationText(appState.session.matchTime, currentPeriodEndTime, appState.session.currentPeriod, appState.session.matchSegments)
    );
    
    if (appState.session.enableMatchDuration && !appState.session.hasWhistlePlayed) {
      final timeUntilPeriodEnd = currentPeriodEndTime - appState.session.matchTime;
      
      if (timeUntilPeriodEnd > 0) {
        _schedulePeriodEndAlarm(timeUntilPeriodEnd, appState);
      }
    }
    
    // Start a new background timer that ticks every second
    _backgroundTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (appState.session.matchRunning && !appState.session.isPaused) {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final lastUpdate = appState.session.lastUpdateTime ?? now;
        
        // Calculate elapsed time since last update
        final elapsed = now - lastUpdate;

        // Only update if time has actually elapsed
        if (elapsed > 0) {
          // IMPORTANT: We do not update the match time here - that would lead to double-counting
          // Instead we only update the lastUpdateTime so the foreground sync can calculate
          // the correct elapsed time
          
          // Update the lastUpdateTime to now
          appState.session.lastUpdateTime = now;
          
          // Get current match time from app state (unchanged)
          final currentMatchTime = appState.session.matchTime;
          
          // Calculate period boundary information
          final periodDuration = appState.session.matchDuration ~/ appState.session.matchSegments;
          final currentPeriodEndTime = periodDuration * appState.session.currentPeriod;
          
          // First, check for match end condition (in final period)
          final isFinalPeriod = appState.session.currentPeriod == appState.session.matchSegments;
          if (isFinalPeriod && 
              currentMatchTime >= appState.session.matchDuration && 
              appState.session.enableMatchDuration && 
              !appState.session.isMatchComplete) {
              
            print("Background timer detected MATCH END condition");
            print("Current time: $currentMatchTime, Match duration: ${appState.session.matchDuration}");
            
            // Record that a match end was detected
            _matchEndDetected = true;
            
            // Update lastUpdateTime
            appState.session.lastUpdateTime = now;
            _lastBackgroundTimestamp = now;
            
            // Call endMatch to handle the match completion
            appState.endMatch();
            
            // Update notification to show match ended
            _updateBackgroundNotification("🏆 MATCH COMPLETE! 🏆");
            
            print("Match ended in background at exactly ${appState.session.matchDuration}");
            
            // Start periodic reminder vibrations for match end
            _startReminderVibrations(isMatchEnd: true, enableVibration: appState.session.enableVibration);
            
            return;
          }
          
          // Check if we would cross or reach period end
          if (currentMatchTime >= currentPeriodEndTime && 
              appState.session.enableMatchDuration && 
              !appState.session.hasWhistlePlayed &&
              appState.session.currentPeriod < appState.session.matchSegments) {
              
            print("Background timer detected period end condition");
            print("Current time: $currentMatchTime, Period end: $currentPeriodEndTime");
            
            // Record that a period end was detected
            _periodEndDetected = true;
            
            // Update lastUpdateTime
            appState.session.lastUpdateTime = now;
            _lastBackgroundTimestamp = now;
            
            // Call endPeriod to handle pausing and state changes
            appState.endPeriod();
            
            // Update notification to show period ended
            final periodName = appState.session.matchSegments == 2 ? 'Half' : 'Quarter';
            final periodEndText = "🔔 ${appState.session.currentPeriod}${_getOrdinalSuffix(appState.session.currentPeriod)} $periodName ENDED! 🔔";
            _updateBackgroundNotification(periodEndText);
            
            print("Period ended in background at exactly $currentPeriodEndTime");
            
            // Start periodic reminder vibrations with vibration setting
            _startReminderVibrations(isPeriodEnd: true, enableVibration: appState.session.enableVibration);
            
            // Pause the match
            appState.session.isPaused = true;
            appState.session.matchRunning = false;
          } else {
            // Just update notification text periodically (every 5 seconds or on multiples of 5)
            if (elapsed >= 5 || currentMatchTime % 5 == 0) {
              _updateBackgroundNotification(
                _getMatchTimeNotificationText(currentMatchTime, currentPeriodEndTime, appState.session.currentPeriod, appState.session.matchSegments)
              );
            }
          }
        }
      }
    });
  }

  // Method to update background notification text
  void _updateBackgroundNotification(String message) {
    if (_isRunning) {
      try {
        // According to flutter_background docs, we can't easily update notifications
        // Instead, stop and restart the service with new notification text
        FlutterBackground.disableBackgroundExecution().then((_) {
          // Update config to use the new message
          final updatedConfig = FlutterBackgroundAndroidConfig(
            notificationTitle: 'Soccer Time App',
            notificationText: message,
            notificationImportance: AndroidNotificationImportance.max,
            notificationIcon: const AndroidResource(
              name: 'ic_notification',
              defType: 'drawable',
            ),
            enableWifiLock: false,
          );
          
          // Re-initialize with updated message
          FlutterBackground.initialize(androidConfig: updatedConfig).then((_) {
            // Re-enable background execution with new notification
            FlutterBackground.enableBackgroundExecution();
          });
        });
        
        print("Updated background notification: $message");
      } catch (e) {
        print("Failed to update background notification: $e");
      }
    }
  }

  // Sync time when app resumes
  void syncTimeOnResume(AppState appState) {
    // IMPORTANT: Stop the background timer FIRST to prevent double-counting
    stopBackgroundTimer();
    
    // Use AppState's lastUpdateTime directly
    final lastUpdateTimeBeforeBackground = appState.session.lastUpdateTime;
    final matchTimeBeforeSync = appState.session.matchTime; // Capture time before sync

    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    final nowSecs = nowMillis ~/ 1000;

    // --- START Detailed Logging ---
    print('--- App Resume Sync ---');
    print('  Now          : $nowSecs ($nowMillis ms)');
    print('  LastUpdatePreBG: $lastUpdateTimeBeforeBackground s');
    print('  MatchTimePreSync: $matchTimeBeforeSync');
    // --- END Detailed Logging ---

    if (lastUpdateTimeBeforeBackground != null) {
      // Calculate elapsed time since the *last update by background timer*
      // The background timer only updates lastUpdateTime but not matchTime
      final elapsedInBackground = nowSecs - lastUpdateTimeBeforeBackground;

      print('  Elapsed In BG: $elapsedInBackground secs');

      if (elapsedInBackground > 0) {
        // In the new approach, the background timer only updates lastUpdateTime
        // So we need to calculate the elapsed time properly here
        int newMatchTime = matchTimeBeforeSync + elapsedInBackground;
        
        // Sanity check to avoid large jumps
        if (_lastBackgroundTimestamp != null) {
          // How much time has actually passed since background mode started
          final timeSinceBackgroundStarted = nowSecs - _lastBackgroundTimestamp!;
          print('  Time since background started: $timeSinceBackgroundStarted s');
          
          // If the background timestamp is more recent than lastUpdateTime,
          // use that for a more accurate measure
          if (_lastBackgroundTimestamp! > lastUpdateTimeBeforeBackground) {
            final betterElapsed = nowSecs - _lastBackgroundTimestamp!;
            print('  Using more accurate background timestamp for sync');
            print('  Better elapsed time: $betterElapsed s');
            newMatchTime = matchTimeBeforeSync + betterElapsed;
          }
        }

        // --- More Logging ---
        print('  Calculated New Time: $newMatchTime');
        if (newMatchTime < matchTimeBeforeSync) {
           print('  *** WARNING: Synced time decreased! Old: $matchTimeBeforeSync, New: $newMatchTime ***');
           // Don't allow time to go backwards
           newMatchTime = matchTimeBeforeSync;
        }
        
        // Sanity check - make sure we don't have an unreasonable time jump
        // If more than 30 seconds elapsed, log a warning (but still apply it)
        if (newMatchTime - matchTimeBeforeSync > 30) {
          print('  *** WARNING: Large time jump detected: ${newMatchTime - matchTimeBeforeSync} seconds ***');
        }
        // --- End More Logging ---

        // Apply the sync adjustment directly to AppState
        appState.session.matchTime = newMatchTime;
        
        // Update player times based on elapsed time during background
        // Use the same time adjustment we used for the match time
        int adjustedElapsed = newMatchTime - matchTimeBeforeSync;
        appState.updatePlayerTimesForBackgroundSync(adjustedElapsed);
        
        print('  Successfully updated match time: $matchTimeBeforeSync -> $newMatchTime (+$adjustedElapsed s)');
      } else if (elapsedInBackground < 0) {
        print('  *** WARNING: Negative elapsed time calculated during sync! Clock jump? ***');
        // Don't adjust time backwards
      } else {
        print('  No elapsed time detected in background for sync.');
      }
    } else {
      print('  Cannot sync: lastUpdateTimeBeforeBackground is null.');
    }

    // CRITICAL: Update lastUpdateTime to NOW, regardless of sync result
    appState.session.lastUpdateTime = nowSecs;
    // Also reset _lastBackgroundTimestamp to help with future calculations
    _lastBackgroundTimestamp = null;
    print('  Updated lastUpdateTime to: $nowSecs');
  }

  void stopBackgroundTimer() {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
  }

  Future<void> dispose() async {
    print("Disposing BackgroundService");
    stopBackgroundTimer();
    _reminderVibrationTimer?.cancel();
    _reminderVibrationTimer = null;
    await AndroidAlarmManager.cancel(PERIOD_END_ALARM_ID);
    await stopBackgroundService();
    _lastBackgroundTimestamp = null;
    resetEventFlags();
  }

  // New methods for vibration in background
  
  // Vibrate with pattern for period end
  void _vibratePeriodEnd() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        // Strong double vibration for period end
        Vibration.vibrate(pattern: [0, 300, 150, 300], intensities: [0, 255, 0, 255]);
        print("Vibrating for period end");
      }
    } catch (e) {
      print("Error while vibrating for period end: $e");
    }
  }
  
  // Vibrate with pattern for match end
  void _vibrateMatchEnd() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        // Triple strong vibration pattern for match end
        Vibration.vibrate(pattern: [0, 250, 100, 250, 100, 250], intensities: [0, 255, 0, 255, 0, 255]);
        print("Vibrating for match end");
      }
    } catch (e) {
      print("Error while vibrating for match end: $e");
    }
  }

  // Helper to generate notification text from match time
  String _getMatchTimeNotificationText(int matchTime, int periodEndTime, int currentPeriod, int totalPeriods) {
    // Format match time
    final minutes = matchTime ~/ 60;
    final seconds = matchTime % 60;
    final timeStr = "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
    
    // Calculate time until period end
    final timeUntilEnd = periodEndTime - matchTime;
    
    // Choose proper period name
    final periodName = totalPeriods == 2 ? 'Half' : 'Quarter';
    
    // Build notification text
    if (timeUntilEnd <= 60 && timeUntilEnd > 5) {
      // Last minute of period
      return "⏱️ $timeStr - $currentPeriod${_getOrdinalSuffix(currentPeriod)} $periodName ends in ${timeUntilEnd}s";
    } else if (timeUntilEnd <= 5 && timeUntilEnd > 0) {
      // Last 5 seconds countdown
      return "⚠️ $timeStr - $timeUntilEnd SECONDS TO PERIOD END! ⚠️";
    } else {
      // Regular time display
      return "⏱️ $timeStr - $currentPeriod${_getOrdinalSuffix(currentPeriod)}/$totalPeriods $periodName";
    }
  }
  
  // Helper for ordinal suffixes
  String _getOrdinalSuffix(int number) {
    if (number % 10 == 1 && number % 100 != 11) return "st";
    if (number % 10 == 2 && number % 100 != 12) return "nd";
    if (number % 10 == 3 && number % 100 != 13) return "rd";
    return "th";
  }

  // Start periodic reminder vibrations
  void _startReminderVibrations({bool isPeriodEnd = false, bool isMatchEnd = false, required bool enableVibration}) {
    // Cancel any existing timer
    _reminderVibrationTimer?.cancel();
    
    // Check if vibration is enabled
    if (!enableVibration) {
      print("Reminder vibrations not started: vibration disabled in settings");
      return;
    }
    
    print("Starting reminder vibrations for ${isMatchEnd ? 'match end' : 'period end'}");
    
    // Create a new timer that fires every 10 seconds
    _reminderVibrationTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      // We'll rely on the initial check, since we have no way to check settings later
      if (isMatchEnd) {
        _vibrateMatchEndReminder();
      } else if (isPeriodEnd) {
        _vibratePeriodEndReminder();
      }
    });
  }
  
  // Vibrate pattern for period end reminder
  void _vibratePeriodEndReminder() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        // Two short pulses for period end reminder
        Vibration.vibrate(
          pattern: [0, 120, 100, 120], 
          intensities: [0, 180, 0, 180]
        );
        print("Vibrating period end reminder");
      }
    } catch (e) {
      print("Error while vibrating for period end reminder: $e");
    }
  }
  
  // Vibrate pattern for match end reminder
  void _vibrateMatchEndReminder() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        // Three short pulses for match end reminder
        Vibration.vibrate(
          pattern: [0, 120, 100, 120, 100, 120], 
          intensities: [0, 220, 0, 220, 0, 220]
        );
        print("Vibrating match end reminder");
      }
    } catch (e) {
      print("Error while vibrating for match end reminder: $e");
    }
  }

  // Add a new method to stop reminder vibrations
  void stopReminderVibrations() {
    if (_reminderVibrationTimer != null) {
      print("Stopping reminder vibrations");
      _reminderVibrationTimer?.cancel();
      _reminderVibrationTimer = null;
    }
  }

  // Schedule an alarm to wake up before period end
  Future<void> _schedulePeriodEndAlarm(int secondsUntilPeriodEnd, AppState appState) async {
    // Cancel any existing alarm first
    await AndroidAlarmManager.cancel(PERIOD_END_ALARM_ID);
    
    // Calculate when to wake up - exactly 5 seconds before period end
    final wakeupTime = DateTime.now().add(Duration(seconds: secondsUntilPeriodEnd - 5));
    
    print("Scheduling period end alarm for: $wakeupTime");
    print("Current match time: ${appState.session.matchTime}, Seconds until period end: $secondsUntilPeriodEnd");
    
    // Store the expected period end time and settings for validation
    final prefs = await SharedPreferences.getInstance();
    final expectedEndTime = DateTime.now().millisecondsSinceEpoch ~/ 1000 + secondsUntilPeriodEnd;
    await prefs.setInt('expected_period_end', expectedEndTime);
    
    // Store both sound and vibration settings
    await prefs.setBool('vibration_enabled', appState.session.enableVibration);
    await prefs.setBool('sound_enabled', appState.session.enableSound);
    
    // Schedule exact alarm that will wake up the device
    await AndroidAlarmManager.oneShot(
      Duration(seconds: secondsUntilPeriodEnd - 5),
      PERIOD_END_ALARM_ID,
      _handlePeriodEndAlarm,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
      alarmClock: true, // This ensures the alarm will fire even in doze mode
    );
  }
  
  // Static callback for the alarm
  @pragma('vm:entry-point')
  static void _handlePeriodEndAlarm() async {
    print("Period end alarm triggered!");
    
    // Get the singleton instance
    final instance = BackgroundService();
    
    // Get the shared preferences to check expected end time and settings
    final prefs = await SharedPreferences.getInstance();
    final expectedEndTime = prefs.getInt('expected_period_end') ?? 0;
    final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    
    print("Expected period end time: $expectedEndTime");
    print("Current time: $currentTime");
    
    // If we're more than 30 seconds before the expected end time, don't trigger
    if (currentTime < expectedEndTime - 30) {
      print("Alarm triggered too early, ignoring!");
      return;
    }
    
    // Check both sound and vibration settings
    final vibrationEnabled = prefs.getBool('vibration_enabled') ?? true;
    final soundEnabled = prefs.getBool('sound_enabled') ?? false;
    
    print("Sound enabled: $soundEnabled, Vibration enabled: $vibrationEnabled");
    
    // Only vibrate if enabled
    if (vibrationEnabled && (await Vibration.hasVibrator() ?? false)) {
      // Start countdown vibrations with precise timing
      for (int i = 5; i > 0; i--) {
        print("Countdown vibration: $i seconds remaining");
        
        // Calculate vibration parameters based on remaining time
        final duration = 150 + ((5 - i) * 30);  // 150ms to 270ms
        final intensity = 128 + ((5 - i) * 25);  // 128 to 228
        
        // Vibrate with increasing intensity
        await Vibration.vibrate(duration: duration, amplitude: intensity);
        
        if (i > 1) {
          // Wait exactly one second minus the vibration duration
          final waitTime = 1000 - duration;
          await Future.delayed(Duration(milliseconds: waitTime));
        }
      }
    }
  }
} 